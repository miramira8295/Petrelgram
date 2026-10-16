import { BusinessError } from '@kit.BasicServicesKit';
import { logI, logE } from '../../util/log';
import { common } from '@kit.AbilityKit';
import { unifiedDataChannel as udc } from '@kit.ArkData';
import { fileIo as fs, fileUri } from '@kit.CoreFileKit';
import { promptAction, UIContext } from '@kit.ArkUI';
import { DropArrivalSession } from '../../util/dropArrival';
import { SharedPayload } from '../../util/sharedContent';
import { ShareArrivalHost, sendShareDirectly, remainingDirectShare } from '../../util/shareArrival';
import { ShareMediaGeometry } from '../../util/shareLivePhoto';
import { SendProgress } from '../../util/sendProgress';
import { str } from '../../util/strings';
import { decodeDrop } from '../../services/DropData';
import { ensureStagingDir, sweepStaging } from '../../util/sendStagingFs';
import { openDropPreview, DropSendResult } from './DropPreviewDialog';
import { SendPermissionError } from '../../store/SendPermissionApi';

const DROP_STAGING = 'drop-staging';
let nextDrop = 0;
export class ChatDropReceiver {
  private arrival = new DropArrivalSession();
  private generation: number = 0;
  private pending: boolean = false;
  private abort: (() => void) | null = null;
  private preview: (() => void) | null = null;

  cancel(): void {
    this.generation++; this.arrival.cancel(); this.abort?.(); this.abort = null;
    this.preview?.(); this.preview = null; this.pending = false;
  }

  receive(event: DragEvent, context: common.Context, ui: UIContext, host: ShareArrivalHost,
    active: () => boolean, target: string): void {
    if (this.pending || !active()) { event.setResult(DragResult.DRAG_FAILED); return; }
    const generation = ++this.generation;
    const current = (): boolean => generation === this.generation && active();
    const now = Date.now();
    sweepStaging(context.cacheDir, DROP_STAGING, now);
    const directory = ensureStagingDir(context.cacheDir, DROP_STAGING, now, ++nextDrop);
    if (directory === '') { event.setResult(DragResult.DRAG_FAILED); return; }
    this.pending = true;
    let retained = false;
    const cleanup = (): void => { fs.rmdir(directory).catch((): void => {}); };
    const load = (): Promise<SharedPayload> => new Promise<SharedPayload>((resolve, reject): void => {
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
        decodeDrop(immediate, directory, current).then(resolve).catch(reject);
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
            decodeDrop(data, directory, current).then(resolve).catch(reject);
          }
        });
      } catch (error) { logE(`[Drop] deferred start failed code=${(error as BusinessError).code ?? 0}`); fail(); }
    });
    // The system accepts the drop asynchronously; no message is sent here.
    event.dragBehavior = DragBehavior.COPY;
    event.setResult(DragResult.DRAG_SUCCESSFUL);
    this.arrival.receive(load, {
      active: current,
      check: async (payload: SharedPayload): Promise<void> => { await host.checkPermissions?.(payload); },
      draft: host.draftText,
      setDraft: host.setDraft,
      preview: (payload: SharedPayload): void => {
        let sent = false;
        this.preview = openDropPreview(ui, payload, target, current,
            async (pending: SharedPayload): Promise<DropSendResult> => {
              if (!current()) { return { remaining: null, uncertain: false, error: '' }; }
              sent = true;
              const progress = new SendProgress();
              try {
                await sendShareDirectly(pending, host, new Map<string, ShareMediaGeometry>(), progress, current);
                return { remaining: null, uncertain: false, error: '' };
              } catch (error) {
                if (!current()) { return { remaining: null, uncertain: false, error: '' }; }
                return { remaining: remainingDirectShare(pending, progress), uncertain: progress.hasUncertain(),
                  error: progress.hasUncertain() ? '' : (error instanceof SendPermissionError ? error.message : str('fw_failed')) };
              }
            },
            (): void => {
              if (!sent) { cleanup(); }
              if (generation === this.generation) { this.preview = null; this.pending = false; }
            });
        retained = true;
      }
    }).catch((error: Object): void => {
      logE(`[Drop] receive failed code=${(error as BusinessError).code ?? 0} current=${current()}`);
      if (current()) {
        promptAction.showToast({ message: error instanceof SendPermissionError ? error.message : $r('app.string.share_failed'), duration: 2500 });
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
