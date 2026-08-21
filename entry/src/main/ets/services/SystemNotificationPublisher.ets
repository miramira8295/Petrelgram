import { notificationManager } from '@kit.NotificationKit';
import { wantAgent } from '@kit.AbilityKit';
import { NotificationPublisher, LocalNotice } from './NotificationService';
import { avatarPixelMap } from '../util/avatarPixelMap';
import { logE } from '../util/log';

// NotificationPublisher 的系统实现：Notification Kit 文本通知。
// 点击经 wantAgent 拉起 EntryAbility 并携带 notifyChatId（Index 消费路由）。
export class SystemNotificationPublisher implements NotificationPublisher {
  private bundleName: string;
  private abilityName: string;

  constructor(bundleName: string, abilityName: string) {
    this.bundleName = bundleName;
    this.abilityName = abilityName;
  }

  publish(notice: LocalNotice): void {
    this.buildAgent(notice.chatId).then((agent: object): Promise<void> => {
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

  private buildAgent(chatId: number): Promise<object> {
    const params: Record<string, Object> = { 'notifyChatId': chatId };
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
