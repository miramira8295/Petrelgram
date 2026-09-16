import { notificationManager } from '@kit.NotificationKit';
import { common, wantAgent, WantAgent } from '@kit.AbilityKit';
import { BusinessError, commonEventManager } from '@kit.BasicServicesKit';
import { accountRegistry } from '../tdkit/AccountRegistry';
import {
  allocateDownloadNotificationId, DOWNLOAD_PROGRESS_TEMPLATE, downloadProgressTemplateSupported,
  markDownloadNotificationLive
} from './DownloadSaveNotification';
import {
  aggregateCachePercent, BG_WAIT_NETWORK, BG_WAIT_WIFI, CacheProgressSample
} from '../util/backgroundCacheModel';
import { DOWNLOAD_CENTER_WANT_KEY } from '../util/downloadCenterWant';
import { str } from '../util/strings';
import { logE } from '../util/log';

// 后台缓存的通知栏（2026-09-15）。
//
// 进行中的合并成**一行**：一条时标题是文件名、多条时是「后台缓存 3 个」，正文是汇总进度（全在等 Wi‑Fi / 等网络时
// 写明）。点一下打开下载中心；带一个「全部暂停」按钮——按钮发公共事件，本进程订阅处理（有后台缓存就持有长时任务，
// 进程在）。每条缓存完各发一行「已经缓存完成」，点一下打开来源消息；失败的发一行，点一下打开下载中心；这两种几秒后撤。
// id 走下载通知的号段并登记为「活着」，启动清扫和 ability 销毁时的撤销都认得它们（services/DownloadSaveNotification）。

const UPDATE_INTERVAL_MS: number = 500;
const TERMINAL_CLEAR_DELAY_MS: number = 5000;
const OPEN_CENTER_REQUEST_CODE: number = 8302;
const PAUSE_ALL_REQUEST_CODE: number = 8303;
const EVENT_SUFFIX: string = '.bgcache.action';
const OP_PAUSE_ALL: string = 'pauseAll';

export interface CacheNotifyEntry {
  title: string;
  downloaded: number;
  size: number;
  waiting: string;
}

// 每条消息一个 requestCode：同一个 requestCode + UPDATE_PRESENT_FLAG 会复用同一个 WantAgent、替换参数，
// 几条同时完成就都跳到最后那条（SystemNotificationPublisher 踩过同一个坑）。
function requestCodeForMessage(chatId: number, messageId: number): number {
  let hash: number = 9173;
  const text: string = `${chatId}_${messageId}`;
  for (let i = 0; i < text.length; i++) {
    hash = ((hash * 31) + text.charCodeAt(i)) % 0x7FFFFFFF;
  }
  return hash;
}

class BackgroundCacheNotifier {
  private context: common.UIAbilityContext | null = null;
  private onPauseAll: () => void = (): void => {};
  private entries: Map<number, CacheNotifyEntry> = new Map<number, CacheNotifyEntry>();
  private summaryId: number = -1;
  private publishTimer: number = -1;
  private lastPublishAt: number = 0;
  private publishSeq: number = 0;
  private subscribing: boolean = false;
  private openCenterAgent: Promise<WantAgent> | null = null;
  private pauseAllAgent: Promise<WantAgent> | null = null;

  bind(context: common.UIAbilityContext, onPauseAll: () => void): void {
    this.context = context;
    this.onPauseAll = onPauseAll;
    this.ensureSubscriber(context);
  }

  update(fileId: number, entry: CacheNotifyEntry): void {
    this.entries.set(fileId, entry);
    this.schedule();
  }

  remove(fileId: number): void {
    if (this.entries.delete(fileId)) {
      this.schedule();
    }
  }

  completed(fileId: number, title: string, chatId: number, messageId: number): void {
    this.remove(fileId);
    this.publishTerminal(title, str('dc_background_cache_done'), chatId, messageId, true);
  }

  failed(fileId: number, title: string): void {
    this.remove(fileId);
    this.publishTerminal(title, str('dc_background_cache_failed'), 0, 0, false);
  }

  private schedule(): void {
    if (this.entries.size === 0) {
      this.clearTimer();
      this.cancelSummary();
      return;
    }
    const elapsed: number = Date.now() - this.lastPublishAt;
    if (elapsed >= UPDATE_INTERVAL_MS) {
      this.clearTimer();
      this.publishSummary();
      return;
    }
    if (this.publishTimer === -1) {
      this.publishTimer = setTimeout((): void => {
        this.publishTimer = -1;
        this.publishSummary();
      }, UPDATE_INTERVAL_MS - elapsed);
    }
  }

  private clearTimer(): void {
    if (this.publishTimer !== -1) {
      clearTimeout(this.publishTimer);
      this.publishTimer = -1;
    }
  }

  private publishSummary(): void {
    const context: common.UIAbilityContext | null = this.context;
    if (context === null || this.entries.size === 0) {
      return;
    }
    if (this.summaryId === -1) {
      this.summaryId = allocateDownloadNotificationId();
      markDownloadNotificationLive(this.summaryId, true);
    }
    this.lastPublishAt = Date.now();
    const id: number = this.summaryId;
    const seq: number = ++this.publishSeq;
    const samples: CacheProgressSample[] = [];
    let firstTitle: string = '';
    let waitingWifi: number = 0;
    let waitingNetwork: number = 0;
    this.entries.forEach((e: CacheNotifyEntry): void => {
      samples.push({ downloaded: e.downloaded, size: e.size });
      if (firstTitle === '') {
        firstTitle = e.title;
      }
      if (e.waiting === BG_WAIT_WIFI) {
        waitingWifi++;
      } else if (e.waiting === BG_WAIT_NETWORK) {
        waitingNetwork++;
      }
    });
    const count: number = this.entries.size;
    const percent: number = aggregateCachePercent(samples);
    const title: string = count === 1 ? firstTitle : str('dc_notify_title', count);
    let text: string = str('dc_notify_caching', percent);
    if (waitingNetwork === count) {
      text = str('dc_status_waiting_network', percent);
    } else if (waitingWifi + waitingNetwork === count) {
      text = str('dc_status_waiting_wifi', percent);
    }
    this.publishSummaryAsync(context, id, seq, title, text, percent).catch((e: Object): void => {
      logE(`BackgroundCacheNotifier.summary(${id}) failed: ${JSON.stringify(e)}`);
    });
  }

  private async publishSummaryAsync(context: common.UIAbilityContext, id: number, seq: number, title: string,
    text: string, percent: number): Promise<void> {
    const supported: boolean = await downloadProgressTemplateSupported();
    const openAgent: WantAgent = await this.centerAgent(context);
    const pauseAgent: WantAgent = await this.pauseAgent(context);
    if (seq !== this.publishSeq || this.summaryId !== id) {
      return;
    }
    const pauseButton: notificationManager.NotificationActionButton = {
      title: str('dc_pause_all'), wantAgent: pauseAgent
    };
    const request: notificationManager.NotificationRequest = {
      id: id,
      notificationSlotType: notificationManager.SlotType.OTHER_TYPES,
      content: {
        notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
        normal: { title: title, text: text }
      },
      wantAgent: openAgent,
      actionButtons: [pauseButton]
    };
    if (supported) {
      request.template = {
        name: DOWNLOAD_PROGRESS_TEMPLATE,
        data: { title: text, fileName: title, progressValue: percent }
      };
    }
    await notificationManager.publish(request);
    if (this.summaryId !== id) {
      await notificationManager.cancel(id);
    }
  }

  private cancelSummary(): void {
    if (this.summaryId === -1) {
      return;
    }
    const id: number = this.summaryId;
    this.summaryId = -1;
    this.publishSeq++;
    markDownloadNotificationLive(id, false);
    notificationManager.cancel(id).catch((e: Error): void => {
      logE(`BackgroundCacheNotifier.cancel(${id}) failed: ${e.message}`);
    });
  }

  private publishTerminal(title: string, text: string, chatId: number, messageId: number, succeeded: boolean): void {
    const context: common.UIAbilityContext | null = this.context;
    if (context === null) {
      return;
    }
    const id: number = allocateDownloadNotificationId();
    markDownloadNotificationLive(id, true);
    this.publishTerminalAsync(context, id, title, text, chatId, messageId, succeeded).then((): void => {
      setTimeout((): void => {
        markDownloadNotificationLive(id, false);
        notificationManager.cancel(id).catch((): void => {});
      }, TERMINAL_CLEAR_DELAY_MS);
    }).catch((e: Object): void => {
      markDownloadNotificationLive(id, false);
      logE(`BackgroundCacheNotifier.terminal(${id}) failed: ${JSON.stringify(e)}`);
    });
  }

  private async publishTerminalAsync(context: common.UIAbilityContext, id: number, title: string, text: string,
    chatId: number, messageId: number, succeeded: boolean): Promise<void> {
    const supported: boolean = succeeded ? await downloadProgressTemplateSupported() : false;
    const agent: WantAgent = chatId !== 0 && messageId !== 0
      ? await this.messageAgent(context, chatId, messageId) : await this.centerAgent(context);
    const request: notificationManager.NotificationRequest = {
      id: id,
      notificationSlotType: notificationManager.SlotType.OTHER_TYPES,
      content: {
        notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
        normal: { title: title, text: text }
      },
      wantAgent: agent,
      tapDismissed: true
    };
    if (supported) {
      request.template = {
        name: DOWNLOAD_PROGRESS_TEMPLATE,
        data: { title: text, fileName: title, progressValue: 100 }
      };
    }
    await notificationManager.publish(request);
  }

  private centerAgent(context: common.UIAbilityContext): Promise<WantAgent> {
    if (this.openCenterAgent === null) {
      const params: Record<string, Object> = {};
      params[DOWNLOAD_CENTER_WANT_KEY] = true;
      const info: wantAgent.WantAgentInfo = {
        wants: [{
          bundleName: context.abilityInfo.bundleName,
          abilityName: context.abilityInfo.name,
          parameters: params
        }],
        actionType: wantAgent.OperationType.START_ABILITY,
        requestCode: OPEN_CENTER_REQUEST_CODE,
        actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
      };
      const pending: Promise<WantAgent> = wantAgent.getWantAgent(info);
      this.openCenterAgent = pending;
      pending.catch((_e: Object): void => { this.openCenterAgent = null; });
    }
    return this.openCenterAgent;
  }

  private pauseAgent(context: common.UIAbilityContext): Promise<WantAgent> {
    if (this.pauseAllAgent === null) {
      const params: Record<string, Object> = { 'op': OP_PAUSE_ALL };
      const info: wantAgent.WantAgentInfo = {
        wants: [{ action: this.eventName(context), parameters: params }],
        actionType: wantAgent.OperationType.SEND_COMMON_EVENT,
        requestCode: PAUSE_ALL_REQUEST_CODE,
        actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
      };
      const pending: Promise<WantAgent> = wantAgent.getWantAgent(info);
      this.pauseAllAgent = pending;
      pending.catch((_e: Object): void => { this.pauseAllAgent = null; });
    }
    return this.pauseAllAgent;
  }

  private messageAgent(context: common.UIAbilityContext, chatId: number, messageId: number): Promise<WantAgent> {
    const params: Record<string, Object> = {
      'notifyChatId': chatId, 'notifyMessageId': messageId, 'notifySlotId': accountRegistry.activeSlotId()
    };
    const info: wantAgent.WantAgentInfo = {
      wants: [{
        bundleName: context.abilityInfo.bundleName,
        abilityName: context.abilityInfo.name,
        parameters: params
      }],
      actionType: wantAgent.OperationType.START_ABILITY,
      requestCode: requestCodeForMessage(chatId, messageId),
      actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
    };
    return wantAgent.getWantAgent(info);
  }

  private ensureSubscriber(context: common.UIAbilityContext): void {
    if (this.subscribing) {
      return;
    }
    this.subscribing = true;
    const info: commonEventManager.CommonEventSubscribeInfo = { events: [this.eventName(context)] };
    commonEventManager.createSubscriber(info).then((subscriber: commonEventManager.CommonEventSubscriber): void => {
      commonEventManager.subscribe(subscriber, (error: BusinessError, data: commonEventManager.CommonEventData): void => {
        if (error !== undefined && error !== null && error.code !== 0) {
          logE(`BackgroundCacheNotifier event failed: ${error.message}`);
          return;
        }
        const params = data.parameters as Record<string, Object> | undefined;
        const op: string = params !== undefined ? ((params['op'] as string | undefined) ?? '') : '';
        if (op === OP_PAUSE_ALL) {
          this.onPauseAll();
        }
      });
    }).catch((e: Object): void => {
      this.subscribing = false;
      logE(`BackgroundCacheNotifier subscribe failed: ${JSON.stringify(e)}`);
    });
  }

  private eventName(context: common.UIAbilityContext): string {
    return `${context.abilityInfo.bundleName}${EVENT_SUFFIX}`;
  }
}

export const backgroundCacheNotifier: BackgroundCacheNotifier = new BackgroundCacheNotifier();
