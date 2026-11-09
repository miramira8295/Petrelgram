import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { wantAgent } from '@kit.AbilityKit';
import { common } from '@kit.AbilityKit';
import { geoLocationManager } from '@kit.LocationKit';
import { preferences } from '@kit.ArkData';
import { TdObject, TdRequest, TdError } from '../tdkit/TdTypes';
import { getTdClient } from '../tdkit/Globals';
import { logE } from '../util/log';

// 实时位置共享。
//
// 必须独立于 ChatPage：用户选了"共享 8 小时"，退出会话、切到后台都应该继续，
// 否则这个功能是骗人的。所以定时器挂在这个单例上，并申请 location 长时任务
// 让进程在后台也能继续上报。
//
// TDLib 不负责采集位置，更新完全由客户端驱动——它只提供 editMessageLiveLocation。

// 上报间隔。Telegram 官方也是分钟级：秒级上报既费电，接收端的地图精度也远
// 达不到那个粒度。
const UPDATE_INTERVAL_MS: number = 60000;
const LOCATE_TIMEOUT_MS: number = 8000;

// 上滑杀进程会连带干掉长时任务，共享随之中断，而接收方那条消息在到期前仍显示
// "正在共享"——坐标却永远停在最后一次上报，比干脆停掉更有误导性。所以把当前
// 共享落盘，下次启动时和 TDLib 推来的活跃列表比对，接续上去。
const STORE_NAME: string = 'live_location';
const KEY_CHAT: string = 'chat_id';
const KEY_MESSAGE: string = 'message_id';
const KEY_ENDS_AT: string = 'ends_at_ms';
const KEY_PERIOD: string = 'period_sec';

export interface LiveLocationState {
  active: boolean;
  chatId: number;
  messageId: number;
  endsAtMs: number;
}

class LiveLocationService {
  private context: common.UIAbilityContext | null = null;
  private chatId: number = 0;
  private messageId: number = 0;
  private endsAtMs: number = 0;
  private periodSec: number = 0;
  private timer: number = -1;
  private taskStarted: boolean = false;
  private unsubSendSucceeded: (() => void) | null = null;
  private unsubActive: (() => void) | null = null;
  private prefs: preferences.Preferences | null = null;
  private listeners: Array<(s: LiveLocationState) => void> = [];

  init(context: common.UIAbilityContext): void {
    this.context = context;
    this.watchActiveMessages();
    preferences.getPreferences(context, STORE_NAME).then((p: preferences.Preferences): void => {
      this.prefs = p;
    }).catch((e: Object): void => {
      // 拿不到存储只影响"杀进程后接续"，当前会话的共享不受影响。
      logE(`LiveLocationService.getPreferences failed: ${JSON.stringify(e)}`);
    });
  }

  // TDLib 启动时会主动推送账号下所有仍在有效期内的实时位置消息。只接续我们
  // 自己落盘过的那一条——别的设备上共享的同样会出现在这个列表里，接管过去
  // 就会把本机位置写到那条消息上。
  private watchActiveMessages(): void {
    if (this.unsubActive !== null) {
      return;
    }
    this.unsubActive = getTdClient().onUpdate('updateActiveLiveLocationMessages', (u: TdObject): void => {
      if (this.messageId !== 0) {
        return;
      }
      const list = u['messages'] as TdObject[] | undefined;
      if (list === undefined || list.length === 0) {
        this.clearPersisted();
        return;
      }
      this.resumeFrom(list);
    });
  }

  private resumeFrom(list: TdObject[]): void {
    const p = this.prefs;
    if (p === null) {
      return;
    }
    const savedChat: number = Number(p.getSync(KEY_CHAT, 0));
    const savedMessage: number = Number(p.getSync(KEY_MESSAGE, 0));
    const endsAtMs: number = Number(p.getSync(KEY_ENDS_AT, 0));
    const periodSec: number = Number(p.getSync(KEY_PERIOD, 0));
    if (savedMessage === 0 || endsAtMs <= Date.now()) {
      this.clearPersisted();
      return;
    }
    const match = list.find((m: TdObject): boolean =>
      (m['id'] as number | undefined) === savedMessage
      && (m['chat_id'] as number | undefined) === savedChat);
    if (match === undefined) {
      // 服务端已经不认这条了（到期或在别处停掉），别再接续。
      this.clearPersisted();
      return;
    }
    this.chatId = savedChat;
    this.messageId = savedMessage;
    this.endsAtMs = endsAtMs;
    this.periodSec = periodSec;
    this.watchSendSucceeded();
    this.startBackgroundTask();
    this.armTimer();
    this.notify();
  }

  private persistCurrent(): void {
    const p = this.prefs;
    if (p === null) {
      return;
    }
    p.putSync(KEY_CHAT, this.chatId);
    p.putSync(KEY_MESSAGE, this.messageId);
    p.putSync(KEY_ENDS_AT, this.endsAtMs);
    p.putSync(KEY_PERIOD, this.periodSec);
    p.flush().catch((e: Object): void => {
      logE(`LiveLocationService.persist failed: ${JSON.stringify(e)}`);
    });
  }

  private clearPersisted(): void {
    const p = this.prefs;
    if (p === null) {
      return;
    }
    p.putSync(KEY_MESSAGE, 0);
    p.flush().catch((e: Object): void => {
      logE(`LiveLocationService.clearPersisted failed: ${JSON.stringify(e)}`);
    });
  }

  subscribe(listener: (s: LiveLocationState) => void): () => void {
    this.listeners = [...this.listeners, listener];
    listener(this.snapshot());
    return (): void => {
      this.listeners = this.listeners.filter((l: (s: LiveLocationState) => void) => l !== listener);
    };
  }

  snapshot(): LiveLocationState {
    return {
      active: this.messageId !== 0,
      chatId: this.chatId,
      messageId: this.messageId,
      endsAtMs: this.endsAtMs
    };
  }

  isActive(): boolean {
    return this.messageId !== 0;
  }

  // 同一时刻只共享一条：Telegram 也是这个语义，开新的会顶掉旧的。
  start(chatId: number, messageId: number, periodSec: number): void {
    if (this.messageId !== 0) {
      this.stopSharing();
    }
    this.chatId = chatId;
    this.messageId = messageId;
    this.endsAtMs = Date.now() + periodSec * 1000;
    this.periodSec = periodSec;
    this.watchSendSucceeded();
    this.persistCurrent();
    this.startBackgroundTask();
    this.armTimer();
    this.notify();
  }

  // 用户主动停止：通知服务端结束共享（location 传空即停止）。
  stopSharing(): void {
    const chatId: number = this.chatId;
    const messageId: number = this.messageId;
    this.clearTimer();
    this.clearSendSucceededWatch();
    this.clearPersisted();
    this.chatId = 0;
    this.messageId = 0;
    this.endsAtMs = 0;
    this.periodSec = 0;
    this.stopBackgroundTask();
    this.notify();
    if (messageId === 0) {
      return;
    }
    const req: TdRequest = { '@type': 'editMessageLiveLocation' };
    req['chat_id'] = chatId;
    req['message_id'] = messageId;
    // 不带 location 即为 null —— 这就是"停止共享"。
    getTdClient().send(req, 15000).catch((e: TdError): void => {
      logE(`LiveLocationService.stopSharing failed: ${e.message}`);
    });
  }

  // sendMessage 返回的是**临时** id，服务端确认后才换成真 id。不换的话每次
  // editMessageLiveLocation 都是 "Message not found"。MessageStore 里虽然有
  // 同样的处理，但它绑定在单个会话上、退出会话就销毁了，所以这里自己订阅。
  private watchSendSucceeded(): void {
    if (this.unsubSendSucceeded !== null) {
      return;
    }
    this.unsubSendSucceeded = getTdClient().onUpdate('updateMessageSendSucceeded', (u: TdObject): void => {
      const oldId = u['old_message_id'] as number | undefined;
      if (oldId === undefined || oldId !== this.messageId) {
        return;
      }
      const m = u['message'] as TdObject | undefined;
      const newId = m !== undefined ? (m['id'] as number | undefined) : undefined;
      if (newId === undefined) {
        return;
      }
      this.messageId = newId;
      this.persistCurrent();
      this.notify();
    });
  }

  private clearSendSucceededWatch(): void {
    const unsub = this.unsubSendSucceeded;
    this.unsubSendSucceeded = null;
    if (unsub !== null) {
      unsub();
    }
  }

  private armTimer(): void {
    this.clearTimer();
    this.timer = setInterval((): void => { this.tick(); }, UPDATE_INTERVAL_MS);
  }

  private clearTimer(): void {
    if (this.timer !== -1) {
      clearInterval(this.timer);
      this.timer = -1;
    }
  }

  private tick(): void {
    if (this.messageId === 0) {
      this.clearTimer();
      return;
    }
    // 到期后服务端自己会结束共享，客户端只需停止上报并释放后台任务。
    if (Date.now() >= this.endsAtMs) {
      this.clearTimer();
      this.clearSendSucceededWatch();
      this.clearPersisted();
      this.chatId = 0;
      this.messageId = 0;
      this.endsAtMs = 0;
      this.stopBackgroundTask();
      this.notify();
      return;
    }
    const chatId: number = this.chatId;
    const messageId: number = this.messageId;
    const request: geoLocationManager.SingleLocationRequest = {
      locatingPriority: geoLocationManager.LocatingPriority.PRIORITY_LOCATING_SPEED,
      locatingTimeoutMs: LOCATE_TIMEOUT_MS
    };
    geoLocationManager.getCurrentLocation(request)
      .then((loc: geoLocationManager.Location): void => {
        // 期间可能已被停止或换了新的共享，避免写到过期的消息上。
        if (this.messageId !== messageId) {
          return;
        }
        const location: TdObject = { '@type': 'location' };
        location['latitude'] = loc.latitude;
        location['longitude'] = loc.longitude;
        // location 参数的类型是 liveLocation 包装层，和 inputMessageLiveLocation
        // 一致。这里传裸 location 不会报错 —— 该参数可空，TDLib 解析具体类时
        // 不校验 @type，裸对象里找不到 location 子字段就解析成 null，而 null
        // 的语义正是"停止共享"。于是第一次编辑请求成功返回、同时把共享结束掉，
        // 之后一律 Message can't be edited。
        const live: TdObject = { '@type': 'liveLocation' };
        live['location'] = location;
        live['live_period'] = this.periodSec;
        live['heading'] = 0;
        live['proximity_alert_radius'] = 0;
        const req: TdRequest = { '@type': 'editMessageLiveLocation' };
        req['chat_id'] = chatId;
        req['message_id'] = messageId;
        req['location'] = live;
        getTdClient().send(req, 15000).catch((e: TdError): void => {
          logE(`LiveLocationService.update failed: ${e.message}`);
        });
      })
      .catch((e: Object): void => {
        // 单次定位失败不终止共享，下一轮再试。
        logE(`LiveLocationService.locate failed: ${JSON.stringify(e)}`);
      });
  }

  private startBackgroundTask(): void {
    const context = this.context;
    if (context === null || this.taskStarted) {
      return;
    }
    const info: wantAgent.WantAgentInfo = {
      wants: [{
        bundleName: context.abilityInfo.bundleName,
        abilityName: context.abilityInfo.name
      }],
      actionType: wantAgent.OperationType.START_ABILITY,
      requestCode: 8296,
      actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
    };
    wantAgent.getWantAgent(info).then((agent: Object): Promise<void> => {
      // 用字符串数组的重载，和仓库里其它长时任务保持一致。
      return backgroundTaskManager.startBackgroundRunning(context, ['location'], agent)
        .then((): void => {});
    }).then((): void => {
      this.taskStarted = true;
    }).catch((e: Object): void => {
      // 拿不到长时任务不影响前台上报，只是切后台后会被冻结。
      logE(`LiveLocationService.startBackgroundRunning failed: ${JSON.stringify(e)}`);
    });
  }

  private stopBackgroundTask(): void {
    const context = this.context;
    if (context === null || !this.taskStarted) {
      return;
    }
    this.taskStarted = false;
    backgroundTaskManager.stopBackgroundRunning(context).catch((e: Object): void => {
      logE(`LiveLocationService.stopBackgroundRunning failed: ${JSON.stringify(e)}`);
    });
  }

  private notify(): void {
    const state = this.snapshot();
    for (const listener of this.listeners) {
      listener(state);
    }
  }
}

export const liveLocation: LiveLocationService = new LiveLocationService();
