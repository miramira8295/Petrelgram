import { describe, it, expect } from '@ohos/hypium';
import {
  NOTIFICATION_ID_END, NOTIFICATION_ID_START, isDownloadNotificationId,
  isTerminalPhase, nextNotificationIdAfter
} from '../main/ets/util/downloadNotify';

export default function downloadNotifyTest(): void {
  describe('downloadNotify', (): void => {

    // 清扫只认这一段。别的通知（新消息、通话）用的是别的 id，误伤了就是
    // 「启动一次把用户的未读通知全抹了」。
    it('只认下载专用的那一段 id', 0, (): void => {
      expect(isDownloadNotificationId(NOTIFICATION_ID_START)).assertTrue();
      expect(isDownloadNotificationId(NOTIFICATION_ID_END)).assertTrue();
      expect(isDownloadNotificationId(NOTIFICATION_ID_START + 1)).assertTrue();
      expect(isDownloadNotificationId(NOTIFICATION_ID_START - 1)).assertFalse();
      expect(isDownloadNotificationId(NOTIFICATION_ID_END + 1)).assertFalse();
      // 新消息通知那边用的是聊天 id 一类的小数字，必须落在段外。
      expect(isDownloadNotificationId(0)).assertFalse();
      expect(isDownloadNotificationId(1)).assertFalse();
      expect(isDownloadNotificationId(-1)).assertFalse();
    });

    // getActiveNotifications 回来的 id 是可选字段，取不到时调用方填 -1。
    it('野值不当成自己的', 0, (): void => {
      expect(isDownloadNotificationId(Number.NaN)).assertFalse();
      expect(isDownloadNotificationId(Number.POSITIVE_INFINITY)).assertFalse();
    });

    it('id 走到段尾绕回段首', 0, (): void => {
      expect(nextNotificationIdAfter(NOTIFICATION_ID_START)).assertEqual(NOTIFICATION_ID_START + 1);
      expect(nextNotificationIdAfter(NOTIFICATION_ID_END)).assertEqual(NOTIFICATION_ID_START);
      // 绕回去的下一个仍然在段内——绕一圈之后不会漏到别人的号段。
      expect(isDownloadNotificationId(nextNotificationIdAfter(NOTIFICATION_ID_END))).assertTrue();
    });

    // 终态 = 发完就该定时撤掉的那几个。
    it('终态只有已保存与两种失败', 0, (): void => {
      expect(isTerminalPhase('saved')).assertTrue();
      expect(isTerminalPhase('downloadFailed')).assertTrue();
      expect(isTerminalPhase('saveFailed')).assertTrue();
    });

    // 进行中的三个阶段一个都不能算终态：算了就是进度条撤在半路。
    it('进行中的阶段不算终态', 0, (): void => {
      expect(isTerminalPhase('downloading')).assertFalse();
      expect(isTerminalPhase('saving')).assertFalse();
      expect(isTerminalPhase('')).assertFalse();
    });
  });
}
