import { notificationManager } from '@kit.NotificationKit';
import { wantAgent } from '@kit.AbilityKit';
import { NotificationPublisher, LocalNotice } from './NotificationService';
import { avatarPixelMap } from '../util/avatarPixelMap';
import { logE } from '../util/log';
import { NOTIFY_QUEUE_MAX, overflowCount, publishDelayMs } from '../util/notifyRate';

// NotificationPublisher 的系统实现：Notification Kit 文本通知。
// 点击经 wantAgent 拉起 EntryAbility 并携带 notifyChatId + notifyMessageId（Index 消费路由，
// 后者走 ChatPage 的 jumpTo 定位到那条消息）。
export class SystemNotificationPublisher implements NotificationPublisher {
  private bundleName: string;
  private abilityName: string;
  // 限频队列，见 util/notifyRate。
  private queue: LocalNotice[] = [];
  private lastPublishAt: number = 0;
  private drainTimer: number = -1;

  constructor(bundleName: string, abilityName: string) {
    this.bundleName = bundleName;
    this.abilityName = abilityName;
  }

  // 系统对单应用发布**新**通知的上限是每秒 10 条，超了直接抛 1600009。真机日志
  // 里网络恢复后 TDLib 一次补推一批消息，这里原来逐条直发，一瞬间 9~10 条连号
  // 全被拒——那些通知用户根本没看见。改成入队按最小间隔放行，一条都不丢。
  // 间隔的取值理由见 util/notifyRate。
  publish(notice: LocalNotice): void {
    this.queue.push(notice);
    const over: number = overflowCount(this.queue.length, NOTIFY_QUEUE_MAX);
    if (over > 0) {
      // 丢最旧的：积压到这个量级时用户最关心的是最新那几条。
      this.queue = this.queue.slice(over);
    }
    this.scheduleDrain();
  }

  private scheduleDrain(): void {
    if (this.drainTimer !== -1 || this.queue.length === 0) {
      return;
    }
    this.drainTimer = setTimeout((): void => {
      this.drainTimer = -1;
      const next: LocalNotice | undefined = this.queue.shift();
      if (next !== undefined) {
        this.lastPublishAt = Date.now();
        this.sendNow(next);
      }
      // 队列里还有就接着排；空了这里直接返回，不留空转的定时器。
      this.scheduleDrain();
    }, publishDelayMs(this.lastPublishAt, Date.now()));
  }

  private sendNow(notice: LocalNotice): void {
    this.buildAgent(notice.chatId, notice.messageId ?? 0).then((agent: object): Promise<void> => {
      const request: notificationManager.NotificationRequest = {
        id: notice.id,
        notificationSlotType: notificationManager.SlotType.SOCIAL_COMMUNICATION,
        content: {
          notificationContentType:
            notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
          normal: {
            title: notice.title,
            text: notice.text
          }
        },
        wantAgent: agent
      };
      // 会话头像：largeIcon 是展开态右侧大图标，overlayIcon 是横幅上叠加在
      // 应用图标处的会话头像（IM 类通知的常见样式）。两者都设，覆盖顶部弹出
      // 横幅与通知中心两种形态；无头像时留空，系统回退应用图标。
      const avatar = avatarPixelMap(notice.avatarPath);
      if (avatar !== undefined) {
        request.largeIcon = avatar;
        request.overlayIcon = avatar;
      }
      return notificationManager.publish(request);
    }).then((): void => {
    }).catch((e: Error): void => {
      logE(`SystemNotificationPublisher.publish(${notice.id}) failed: ${e.message}`);
    });
  }

  cancel(id: number): void {
    notificationManager.cancel(id).catch((e: Error): void => {
      logE(`SystemNotificationPublisher.cancel(${id}) failed: ${e.message}`);
    });
  }

  cancelAll(): void {
    notificationManager.cancelAll().catch((e: Error): void => {
      logE(`SystemNotificationPublisher.cancelAll failed: ${e.message}`);
    });
  }

  // requestCode is what distinguishes one WantAgent from another. Every chat
  // used the same constant, and UPDATE_PRESENT_FLAG means "reuse the existing
  // agent, replace its extras" — so all notifications shared a single agent
  // carrying whichever chat published last, and tapping any notification
  // opened that chat instead of its own. Derived per chat, it is stable across
  // republishes of the same chat and distinct between chats.
  private requestCodeFor(chatId: number): number {
    // chat ids are 64-bit and negative for groups/channels; fold to a positive
    // 31-bit value so it survives the int the API expects.
    let hash = 8297;
    const text = `${chatId}`;
    for (let i = 0; i < text.length; i++) {
      hash = ((hash * 31) + text.charCodeAt(i)) % 0x7FFFFFFF;
    }
    return hash;
  }

  private buildAgent(chatId: number, messageId: number): Promise<object> {
    // requestCode 按会话取，UPDATE_PRESENT_FLAG 让同一会话后来的通知覆盖参数——
    // 点任何一条都定位到该会话最新被通知的那条，和官方一致。
    const params: Record<string, Object> = { 'notifyChatId': chatId, 'notifyMessageId': messageId };
    const info: wantAgent.WantAgentInfo = {
      wants: [{
        bundleName: this.bundleName,
        abilityName: this.abilityName,
        parameters: params
      }],
      actionType: wantAgent.OperationType.START_ABILITY,
      requestCode: this.requestCodeFor(chatId),
      actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
    };
    return wantAgent.getWantAgent(info);
  }
}
