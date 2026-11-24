import { showToast } from '../../util/toast';
import { getActiveTdAccountSlot } from '../../tdkit/Globals';
import { isSameChatMessageDrag, isSameChatMessageDragExtra } from '../../util/messageDragOrigin';
import { BusinessError } from '@kit.BasicServicesKit';
import { logI, logE } from '../../util/log';
import { common } from '@kit.AbilityKit';
import { unifiedDataChannel as udc } from '@kit.ArkData';
import { fileIo as fs, fileUri } from '@kit.CoreFileKit';
import { UIContext } from '@kit.ArkUI';
import { DropArrivalSession } from '../../util/dropArrival';
import { SharedPayload } from '../../util/sharedContent';
import { ShareArrivalHost } from '../../util/shareArrival';
import { decodeDrop } from '../../services/DropData';
import { ensureStagingDir, sweepStaging } from '../../util/sendStagingFs';
import { SendPermissionError } from '../../store/SendPermissionApi';

import { sendDropBatch, DropSendResult } from '../../util/dropSend';
import { openDropRecovery } from './DropRecoveryDialog';

const DROP_STAGING = 'drop-staging';
let nextDrop = 0;
export class ChatDropReceiver {
  private arrival = new DropArrivalSession();
  private generation: number = 0;
  private pending: boolean = false;
  private abort: (() => void) | null = null;
  private recovery: (() => void) | null = null;

  isPending(): boolean { return this.pending; }

  cancel(): void {
    this.generation++; this.arrival.cancel(); this.abort?.(); this.abort = null;
    this.recovery?.(); this.recovery = null; this.pending = false;
  }

  receive(event: DragEvent, context: common.Context, ui: UIContext, host: ShareArrivalHost,
    active: () => boolean, target: string, chatId: number, extraParams?: string): void {
    const account: string = getActiveTdAccountSlot();
    if (isSameChatMessageDragExtra(extraParams, account, chatId)) {
      event.setResult(DragResult.DRAG_CANCELED);
      return;
    }
    if (!active()) { event.setResult(DragResult.DRAG_FAILED); return; }
    if (this.pending) {
      event.setResult(DragResult.DRAG_FAILED);
      showToast($r('app.string.processing'), 2500);
      return;
    }
    const generation = ++this.generation;
    const current = (): boolean => generation === this.generation && active();
    const now = Date.now();
    sweepStaging(context.cacheDir, DROP_STAGING, now);
    const directory = ensureStagingDir(context.cacheDir, DROP_STAGING, now, ++nextDrop);
    if (directory === '') { event.setResult(DragResult.DRAG_FAILED); return; }
    this.pending = true;
    let retained = false;
    const cleanup = (): void => { fs.rmdir(directory).catch((): void => {}); };
    const decode = (data: udc.UnifiedData): Promise<SharedPayload | null> => {
      // Also check the UDMF marker after deferred or system-mediated delivery.
      if (isSameChatMessageDrag(data.properties.tag ?? '', account, chatId)) { return Promise.resolve(null); }
      return decodeDrop(data, directory, current);
    };
    const load = (): Promise<SharedPayload | null> => new Promise<SharedPayload | null>((resolve, reject): void => {
      let settled = false;
      let loadingKey = '';
      let timer = -1;
      const fail = (): void => {
        if (settled) { return; }
        settled = true;
        clearTimeout(timer);
        if (loadingKey !== '') { try { ui.getDragController().cancelDataLoading(loadingKey); } catch (_) {} }
        reject(new Error('drop loading failed'));
      };
      this.abort = fail;
      timer = setTimeout(fail, 60000);
      // Local SuperHub drags can already carry the complete data on this event.
      // Asking UDMF to fetch the same key again may find no DB entry.
      let immediate: udc.UnifiedData | null = null;
      try {
        const data = event.getData();
        if (data.getRecords().length > 0) { immediate = data; }
      } catch (error) { logI(`[Drop] event data unavailable code=${(error as BusinessError).code ?? 0}`); }
      if (immediate !== null) {
        settled = true; clearTimeout(timer); this.abort = null;
        logI('[Drop] reading event payload');
        decode(immediate).then(resolve).catch(reject);
        return;
      }
      try {
        logI('[Drop] starting deferred load');
        loadingKey = event.startDataLoading({
          destUri: fileUri.getUriFromPath(directory),
          fileConflictOptions: udc.FileConflictOptions.SKIP,
          progressIndicator: udc.ProgressIndicator.DEFAULT,
          dataProgressListener: (progress: udc.ProgressInfo, data: udc.UnifiedData | null): void => {
            if (settled) { return; }
            logI(`[Drop] load progress=${progress.progress} status=${progress.status}`);
            if (!current() || progress.progress < 0) { fail(); return; }
            if (progress.progress !== 100 || data === null) { return; }
            settled = true; clearTimeout(timer); this.abort = null;
            decode(data).then(resolve).catch(reject);
          }
        });
      } catch (error) { logE(`[Drop] deferred start failed code=${(error as BusinessError).code ?? 0}`); fail(); }
    });
    // 系统异步确认落点；真正的发送在下面的 deliver 里立刻开始，不再弹确认框。
    event.dragBehavior = DragBehavior.COPY;
    event.setResult(DragResult.DRAG_SUCCESSFUL);
    this.arrival.receive(load, {
      active: current,
      check: async (payload: SharedPayload): Promise<void> => {
        // Media permissions belong to sendDropBatch: even the first check can
        // fail transiently, and must retain the staged files for recovery.
        // Text only changes the draft, so keep its check before setDraft.
        if (payload.media.length === 0) { await host.checkPermissions?.(payload); }
      },
      draft: host.draftText,
      setDraft: host.setDraft,
      deliver: (payload: SharedPayload): void => {
        // 文件已经在暂存目录里了。这里 retained 置真：sendShareDirectly 只把请求
        // 交给 TDLib，上传在后台继续读这些文件，发送完成也不能立刻删目录——
        // 交给 sweepStaging 按 TTL 清（一个进程只扫一次）。
        retained = true;
        let recovering = false;
        sendDropBatch(payload, host, current).then((result: DropSendResult): void => {
          if (!current() || result.remaining === null) { return; }
          // Normal drops never open a dialog. Only the unsent remainder is shown
          // after a failure; uncertain requests are visible but cannot be retried.
          this.recovery = openDropRecovery(ui, result.remaining, target, current,
            (remaining: SharedPayload): Promise<DropSendResult> => sendDropBatch(remaining, host, current),
            (): void => {
              if (generation === this.generation) { this.recovery = null; this.pending = false; }
            }, result);
          recovering = true;
        }).catch((error: Object): void => {
          logE(`[Drop] recovery failed: ${error}`);
          if (current()) { showToast($r('app.string.fw_failed'), 2500); }
        }).finally((): void => {
          if (!recovering && generation === this.generation) { this.pending = false; }
        });
      }
    }).catch((error: Object): void => {
      logE(`[Drop] receive failed code=${(error as BusinessError).code ?? 0} current=${current()}`);
      if (current()) {
        showToast(error instanceof SendPermissionError ? error.message : $r('app.string.share_failed'), 2500);
      }
    }).finally((): void => {
      if (!retained) { cleanup(); }
      if (generation === this.generation) {
        this.abort = null;
        if (!retained) { this.pending = false; }
      }
    });
  }
}
