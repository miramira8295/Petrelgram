import { notificationManager } from '@kit.NotificationKit';
import { common, wantAgent } from '@kit.AbilityKit';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { getTdClient } from '../tdkit/Globals';
import { TdError, TdObject, TdRequest } from '../tdkit/TdTypes';
import { logE, logI } from '../util/log';
import {
  FileSaveProgress, prepareDownloadDirectory, saveFileToDownloads
} from '../util/mediaSaver';
import { progressFor, subscribeProgress } from '../util/mediaProgressChannel';
import { publishProgress } from '../util/mediaProgressChannel';
import { str } from '../util/strings';
import {
  NOTIFICATION_ID_START, isDownloadNotificationId, isTerminalPhase,
  nextNotificationIdAfter
} from '../util/downloadNotify';

const PROGRESS_TEMPLATE: string = 'downloadTemplate';
const UPDATE_INTERVAL_MS: number = 500;
// 终态那一行在通知栏里停留多久。
//
// 之前是**不撤**：下载完成后 publish 一条「已保存到 X」就撒手，那一行永远留在
// 通知栏等用户自己划掉（用户："通知栏下载不会回收"）。5 秒够读完文件名，再长
// 就成了常驻行；失败那条走同一个时长，失败在应用内另有 toast，不靠通知栏留存。
const TERMINAL_CLEAR_DELAY_MS: number = 5000;
const DOWNLOAD_PRIORITY: number = 24;
const TRANSFER_WANT_REQUEST_CODE: number = 8301;

let nextNotificationId: number = NOTIFICATION_ID_START;
let progressTemplateSupport: Promise<boolean> | null = null;
// 本次进程里还"活着"的下载通知 id。启动时的清扫（clearStaleDownloadNotifications）
// 要靠它避开正在更新的那几行——UIAbility 被销毁重建但进程还在时，模块状态是
// 留着的，任务可能还在跑。
const liveNotificationIds: Set<number> = new Set<number>();

function allocateNotificationId(): number {
  const id: number = nextNotificationId;
  nextNotificationId = nextNotificationIdAfter(nextNotificationId);
  return id;
}

// 清掉上一次运行残留的下载通知。**启动时调一次**。
//
// 为什么非有不可：进度行靠"重复 publish 同一个 id"原地更新，终态行由实例自己
// 延时撤掉——两条路都要求进程还活着。进程被杀（用户划掉后台卡片、系统回收、
// 崩溃）时没有任何一方来收尾，那一行就永远停在 42% 上，重启应用也不会消失，
// 因为通知是系统托管的。启动是唯一还能认领它们的时机。
export async function clearStaleDownloadNotifications(): Promise<void> {
  try {
    const active: notificationManager.NotificationRequest[] =
      await notificationManager.getActiveNotifications();
    for (let i = 0; i < active.length; i++) {
      const id: number = active[i].id ?? -1;
      // 本进程正在用的那几个不能撤：任务还在跑，撤了就是把进度条抹掉。
      if (isDownloadNotificationId(id) && !liveNotificationIds.has(id)) {
        await notificationManager.cancel(id);
        logI(`[DownloadNotify] cleared stale ${id}`);
      }
    }
  } catch (e) {
    const error = e as Error;
    logE(`clearStaleDownloadNotifications failed: ${error.message}`);
  }
}

// 撤掉本进程还挂着的下载通知。**Ability 被销毁时调**（用户从多任务里划掉
// 应用卡片走的就是这条）。
//
// 为什么这时候就能撤：整套保存都吊在这个 UIAbility 的 context 上（后台任务、
// 公共目录写入都要它），ability 一没，那几个任务就都是死的了——通知再留在那儿
// 就是一条永远不会动的进度条。进程被硬杀时这里跑不到，那种由启动清扫兜底。
export function cancelLiveDownloadNotifications(): void {
  liveNotificationIds.forEach((id: number): void => {
    notificationManager.cancel(id).catch((e: Error): void => {
      logE(`cancelLiveDownloadNotifications(${id}) failed: ${e.message}`);
    });
  });
  liveNotificationIds.clear();
}

function supportsProgressTemplate(): Promise<boolean> {
  if (progressTemplateSupport === null) {
    progressTemplateSupport = notificationManager.isSupportTemplate(PROGRESS_TEMPLATE)
      .catch((e: Error): boolean => {
        logE(`DownloadSaveNotification template check failed: ${e.message}`);
        return false;
      });
  }
  return progressTemplateSupport;
}

function displayFileName(fileName: string): string {
  const clean: string = fileName.trim();
  const slash: number = Math.max(clean.lastIndexOf('/'), clean.lastIndexOf('\\'));
  const name: string = slash >= 0 ? clean.substring(slash + 1) : clean;
  return name !== '' ? name : str('media_kind_file');
}

// One instance follows one explicit user save from the TDLib download through
// the public-directory copy. Re-publishing the same notification id updates the
// existing row instead of filling the notification center with every percent.
export class DownloadSaveNotification implements FileSaveProgress {
  private readonly id: number = allocateNotificationId();
  private readonly fileName: string;
  private phase: string = '';
  private percent: number = -1;
  private lastPublishAt: number = 0;
  private publishTimer: number = -1;
  private publishSeq: number = 0;
  private unsubscribeProgress: (() => void) | null = null;
  private clearTimer: number = -1;
  private terminal: boolean = false;
  private cancelled: boolean = false;
  private onTerminal: (() => void) | null;

  constructor(fileName: string, downloadFileId: number = 0,
    onTerminal: (() => void) | null = null) {
    this.fileName = displayFileName(fileName);
    this.onTerminal = onTerminal;
    liveNotificationIds.add(this.id);
    if (downloadFileId !== 0) {
      this.beginDownload(downloadFileId);
    }
  }

  private beginDownload(fileId: number): void {
    this.detachDownload();
    this.update('downloading', progressFor(fileId), true);
    this.unsubscribeProgress = subscribeProgress(fileId, (percent: number): void => {
      this.update('downloading', percent, false);
    });
  }

  private detachDownload(): void {
    if (this.unsubscribeProgress !== null) {
      this.unsubscribeProgress();
      this.unsubscribeProgress = null;
    }
  }

  onDownload(percent: number): void {
    this.update('downloading', percent, this.phase !== 'downloading');
  }

  private notifyTerminal(): void {
    const callback: (() => void) | null = this.onTerminal;
    this.onTerminal = null;
    callback?.();
  }

  private update(phase: string, percent: number, force: boolean): void {
    if (this.terminal || this.cancelled) {
      return;
    }
    const bounded: number = Math.max(0, Math.min(100, Math.floor(percent)));
    if (!force && phase === this.phase && bounded === this.percent) {
      return;
    }
    const phaseChanged: boolean = phase !== this.phase;
    this.phase = phase;
    this.percent = bounded;
    const elapsed: number = Date.now() - this.lastPublishAt;
    if (force || phaseChanged || elapsed >= UPDATE_INTERVAL_MS) {
      this.clearPublishTimer();
      this.publishNow();
      return;
    }
    if (this.publishTimer === -1) {
      this.publishTimer = setTimeout((): void => {
        this.publishTimer = -1;
        this.publishNow();
      }, UPDATE_INTERVAL_MS - elapsed);
    }
  }

  // 终态行发出去之后定时撤掉。**只在 publish 真的落地之后才排这个定时器**
  // （见两处调用点都挂在 publish 的 then 上），否则撤销可能跑到发布前面。
  private scheduleClear(): void {
    if (this.clearTimer !== -1) {
      clearTimeout(this.clearTimer);
    }
    this.clearTimer = setTimeout((): void => {
      this.clearTimer = -1;
      liveNotificationIds.delete(this.id);
      notificationManager.cancel(this.id).catch((e: Error): void => {
        logE(`DownloadSaveNotification.clear(${this.id}) failed: ${e.message}`);
      });
    }, TERMINAL_CLEAR_DELAY_MS);
  }

  private cancelClearTimer(): void {
    if (this.clearTimer !== -1) {
      clearTimeout(this.clearTimer);
      this.clearTimer = -1;
    }
  }

  private clearPublishTimer(): void {
    if (this.publishTimer !== -1) {
      clearTimeout(this.publishTimer);
      this.publishTimer = -1;
    }
  }

  private statusText(): string {
    if (this.phase === 'downloading') {
      return str('transfer_downloading', this.percent);
    }
    if (this.phase === 'saving') {
      return str('transfer_saving', this.percent);
    }
    if (this.phase === 'saved') {
      return str('transfer_saved_to', this.fileName);
    }
    if (this.phase === 'downloadFailed') {
      return str('transfer_download_failed');
    }
    return str('transfer_save_failed');
  }

  private publishNow(): void {
    if (this.cancelled || this.phase === '') {
      return;
    }
    this.lastPublishAt = Date.now();
    const seq: number = ++this.publishSeq;
    const phase: string = this.phase;
    const percent: number = this.percent;
    const text: string = this.statusText();
    supportsProgressTemplate().then((supported: boolean): Promise<void> | void => {
      if (this.cancelled || seq !== this.publishSeq) {
        return;
      }
      const request: notificationManager.NotificationRequest = {
        id: this.id,
        notificationSlotType: notificationManager.SlotType.OTHER_TYPES,
        content: {
          notificationContentType:
            notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
          normal: {
            title: this.fileName,
            text: text
          }
        }
      };
      if (supported && (phase === 'downloading' || phase === 'saving' || phase === 'saved')) {
        request.template = {
          name: PROGRESS_TEMPLATE,
          data: {
            title: text,
            fileName: this.fileName,
            progressValue: percent
          }
        };
      }
      return notificationManager.publish(request).then((): void => {
        if (isTerminalPhase(phase)) {
          this.scheduleClear();
        }
      });
    }).catch((e: Error): void => {
      logE(`DownloadSaveNotification.publish(${this.id}) failed: ${e.message}`);
    });
  }

  onSaving(percent: number): void {
    const phaseChanged: boolean = this.phase !== 'saving';
    this.detachDownload();
    this.update('saving', percent, phaseChanged);
  }

  onSaved(destination: string): void {
    if (this.cancelled || this.terminal) {
      return;
    }
    this.detachDownload();
    this.clearPublishTimer();
    this.phase = 'saved';
    this.percent = 100;
    this.terminal = true;
    const savedText: string = str('transfer_saved_to', destination);
    const seq: number = ++this.publishSeq;
    this.lastPublishAt = Date.now();
    supportsProgressTemplate().then((supported: boolean): Promise<void> | void => {
      if (this.cancelled || seq !== this.publishSeq) {
        return;
      }
      const request: notificationManager.NotificationRequest = {
        id: this.id,
        notificationSlotType: notificationManager.SlotType.OTHER_TYPES,
        content: {
          notificationContentType:
            notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
          normal: { title: this.fileName, text: savedText }
        }
      };
      if (supported) {
        request.template = {
          name: PROGRESS_TEMPLATE,
          data: { title: savedText, fileName: this.fileName, progressValue: 100 }
        };
      }
      return notificationManager.publish(request).then((): void => {
        this.scheduleClear();
      });
    }).catch((e: Error): void => {
      logE(`DownloadSaveNotification.complete(${this.id}) failed: ${e.message}`);
    });
    this.notifyTerminal();
  }

  downloadFailed(): void {
    this.failAs('downloadFailed');
  }

  onFailed(): void {
    this.failAs('saveFailed');
  }

  private failAs(phase: string): void {
    if (this.cancelled || this.terminal) {
      return;
    }
    this.detachDownload();
    this.clearPublishTimer();
    this.phase = phase;
    this.percent = 0;
    this.publishNow();
    this.terminal = true;
    this.notifyTerminal();
  }

  onCancelled(): void {
    if (this.terminal || this.cancelled) {
      return;
    }
    this.cancelled = true;
    this.detachDownload();
    this.clearPublishTimer();
    this.cancelClearTimer();
    this.publishSeq++;
    liveNotificationIds.delete(this.id);
    notificationManager.cancel(this.id).catch((): void => {});
    this.notifyTerminal();
  }

  dispose(): void {
    if (!this.terminal) {
      this.onCancelled();
    }
  }
}

// A single application-level data-transfer task keeps all explicit exports
// alive after their originating ChatPage disappears. The reference count also
// avoids starting one continuous-task notification per file.
class DownloadTransferKeepAlive {
  private context: common.UIAbilityContext | null = null;
  private activeTokens: Set<number> = new Set<number>();
  private nextToken: number = 1;
  private started: boolean = false;
  private operation: Promise<void> = Promise.resolve();

  acquire(context: common.UIAbilityContext): number {
    const token: number = this.nextToken++;
    this.context = context;
    this.activeTokens.add(token);
    this.enqueue(async (): Promise<void> => {
      if (this.started || this.activeTokens.size === 0 || this.context === null) {
        return;
      }
      const current: common.UIAbilityContext = this.context;
      const info: wantAgent.WantAgentInfo = {
        wants: [{
          bundleName: current.abilityInfo.bundleName,
          abilityName: current.abilityInfo.name
        }],
        actionType: wantAgent.OperationType.START_ABILITY,
        requestCode: TRANSFER_WANT_REQUEST_CODE,
        actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
      };
      const agent = await wantAgent.getWantAgent(info);
      await backgroundTaskManager.startBackgroundRunning(current, ['dataTransfer'], agent);
      this.started = true;
      logI(`[DownloadTransfer] background task started active=${this.activeTokens.size}`);
      if (this.activeTokens.size === 0) {
        await this.stopCurrent();
      }
    });
    return token;
  }

  release(token: number): void {
    this.activeTokens.delete(token);
    this.enqueue(async (): Promise<void> => {
      if (this.activeTokens.size === 0) {
        await this.stopCurrent();
      }
    });
  }

  private async stopCurrent(): Promise<void> {
    if (!this.started || this.context === null) {
      return;
    }
    try {
      await backgroundTaskManager.stopBackgroundRunning(this.context);
      logI('[DownloadTransfer] background task stopped');
    } finally {
      this.started = false;
    }
  }

  private enqueue(action: () => Promise<void>): void {
    this.operation = this.operation.then(action).catch((error: Error): void => {
      logE(`[DownloadTransfer] background task failed: ${error.message}`);
    });
  }
}

interface PendingDownloadSave {
  fileId: number;
  context: common.UIAbilityContext;
  fileName: string;
  progress: DownloadSaveNotification;
  keepAliveToken: number;
  copying: boolean;
}

class DownloadSaveService {
  private tasks: Map<number, PendingDownloadSave> = new Map<number, PendingDownloadSave>();
  private preparing: Set<number> = new Set<number>();
  private unsubscribeFile: (() => void) | null = null;
  private keepAlive: DownloadTransferKeepAlive = new DownloadTransferKeepAlive();

  saveDownloadedFile(context: common.UIAbilityContext, path: string, fileName: string): void {
    this.beginLocalSave(context, path, fileName).catch((error: Error): void => {
      logE(`[DownloadSaveService] local save failed: ${error.message}`);
    });
  }

  saveRemoteFile(context: common.UIAbilityContext, fileId: number,
    chatId: number, messageId: number, fileName: string): void {
    if (fileId === 0 || this.tasks.has(fileId) || this.preparing.has(fileId)) {
      return;
    }
    this.preparing.add(fileId);
    this.beginRemoteSave(context, fileId, chatId, messageId, fileName)
      .catch((error: Error): void => {
        logE(`[DownloadSaveService] remote save ${fileId} failed: ${error.message}`);
      }).finally((): void => {
        this.preparing.delete(fileId);
      });
  }

  private async beginLocalSave(
    context: common.UIAbilityContext, path: string, fileName: string
  ): Promise<void> {
    if (!await prepareDownloadDirectory(context)) {
      return;
    }
    const token: number = this.keepAlive.acquire(context);
    const progress = new DownloadSaveNotification(fileName, 0, (): void => {
      this.keepAlive.release(token);
    });
    saveFileToDownloads(context, path, fileName, progress);
  }

  private async beginRemoteSave(
    context: common.UIAbilityContext, fileId: number, chatId: number,
    messageId: number, fileName: string
  ): Promise<void> {
    if (!await prepareDownloadDirectory(context) || this.tasks.has(fileId)) {
      return;
    }
    const token: number = this.keepAlive.acquire(context);
    const progress = new DownloadSaveNotification(fileName, 0, (): void => {
      this.finish(fileId);
    });
    const task: PendingDownloadSave = {
      fileId, context, fileName, progress, keepAliveToken: token, copying: false
    };
    this.tasks.set(fileId, task);
    this.ensureFileSubscription();
    progress.onDownload(0);

    const request: TdRequest = { '@type': 'addFileToDownloads' };
    request['file_id'] = fileId;
    request['chat_id'] = chatId;
    request['message_id'] = messageId;
    request['priority'] = DOWNLOAD_PRIORITY;
    getTdClient().send(request, 30000).then((file: TdObject): void => {
      this.applyFile(file);
      if (!this.tasks.has(fileId)) {
        return;
      }
      const query: TdRequest = { '@type': 'getFile' };
      query['file_id'] = fileId;
      getTdClient().send(query).then((current: TdObject): void => {
        this.applyFile(current);
      }).catch((error: TdError): void => {
        logE(`[DownloadSaveService] getFile(${fileId}): ${error.message}`);
      });
    }).catch((error: TdError): void => {
      logE(`[DownloadSaveService] addFileToDownloads(${fileId}): ${error.message}`);
      progress.downloadFailed();
    });
  }

  private ensureFileSubscription(): void {
    if (this.unsubscribeFile !== null) {
      return;
    }
    this.unsubscribeFile = getTdClient().onUpdate('updateFile', (update: TdObject): void => {
      const file: TdObject | undefined = update['file'] as TdObject | undefined;
      if (file !== undefined) {
        this.applyFile(file);
      }
    });
  }

  private applyFile(file: TdObject): void {
    const fileId: number = (file['id'] as number | undefined) ?? 0;
    const task: PendingDownloadSave | undefined = this.tasks.get(fileId);
    if (task === undefined || task.copying) {
      return;
    }
    const local: TdObject | undefined = file['local'] as TdObject | undefined;
    if (local === undefined) {
      return;
    }
    const completed: boolean =
      (local['is_downloading_completed'] as boolean | undefined) ?? false;
    const path: string = (local['path'] as string | undefined) ?? '';
    const downloaded: number = (local['downloaded_size'] as number | undefined) ?? 0;
    const size: number = ((file['size'] as number | undefined) ?? 0) ||
      ((file['expected_size'] as number | undefined) ?? 0);
    const percent: number = completed && path !== ''
      ? 100 : (size > 0 ? Math.min(99, Math.floor(downloaded * 100 / size)) : 0);
    task.progress.onDownload(percent);
    publishProgress(fileId, percent);
    if (!completed || path === '') {
      return;
    }
    task.copying = true;
    saveFileToDownloads(task.context, path, task.fileName, task.progress);
  }

  private finish(fileId: number): void {
    const task: PendingDownloadSave | undefined = this.tasks.get(fileId);
    if (task === undefined) {
      return;
    }
    this.tasks.delete(fileId);
    this.keepAlive.release(task.keepAliveToken);
    if (this.tasks.size === 0 && this.unsubscribeFile !== null) {
      this.unsubscribeFile();
      this.unsubscribeFile = null;
    }
  }
}

export const downloadSaveService: DownloadSaveService = new DownloadSaveService();
