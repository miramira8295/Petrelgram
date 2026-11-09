import { describe, it, expect } from '@ohos/hypium';
import { notifySlotAction, NOTIFY_OPEN, NOTIFY_SWITCH, NOTIFY_DROP } from '../main/ets/util/notifySlot';

// 通知点击跨账号（用户报：A 账号收到推送，切到 B 再点通知会跳到错误页面）。
// 通知里带上发布时的槽位，点击时比对当前槽位决定：直接开 / 先切号 / 丢弃。
export default function notifySlotTest(): void {
  describe('notifySlot', (): void => {
    it('同一个账号：直接打开', 0, (): void => {
      expect(notifySlotAction('slot_a', 'slot_a', ['slot_a', 'slot_b'])).assertEqual(NOTIFY_OPEN);
    });
    it('不同账号但那个账号还在：先切号', 0, (): void => {
      expect(notifySlotAction('slot_a', 'slot_b', ['slot_a', 'slot_b'])).assertEqual(NOTIFY_SWITCH);
    });
    it('通知属于一个已经退掉的账号：丢弃，不拿它的 chatId 去开当前账号的会话', 0, (): void => {
      expect(notifySlotAction('slot_gone', 'slot_b', ['slot_b'])).assertEqual(NOTIFY_DROP);
    });
    it('老通知没带槽位（升级前发出的）：按当前账号打开，与改动前一致', 0, (): void => {
      expect(notifySlotAction('', 'slot_b', ['slot_a', 'slot_b'])).assertEqual(NOTIFY_OPEN);
    });
  });
}
