import { describe, it, expect } from '@ohos/hypium';
import { foldUnreadBadge, UnreadBadgeCounts, UnreadBadgeSource } from '../main/ets/util/unreadBadgeRule';

// issue #155：文件夹角标 = 有未读的会话数（含静音）；有未静音的才蓝。
function src(unread: number, muted: boolean): UnreadBadgeSource { return { unreadCount: unread, muted }; }

export default function unreadBadgeRuleTest(): void {
  describe('unreadBadgeRule', (): void => {
    it('静音的也计入总数，未静音单独数', 0, (): void => {
      const c: UnreadBadgeCounts = foldUnreadBadge([src(3, true), src(0, false), src(1, false), src(5, true)]);
      expect(c.total).assertEqual(3);
      expect(c.unmuted).assertEqual(1);
    });
    it('全静音 → unmuted 0；没有未读 → 全 0', 0, (): void => {
      expect(foldUnreadBadge([src(2, true)]).unmuted).assertEqual(0);
      expect(foldUnreadBadge([src(2, true)]).total).assertEqual(1);
      expect(foldUnreadBadge([]).total).assertEqual(0);
      expect(foldUnreadBadge([src(0, false)]).total).assertEqual(0);
    });
  });
}
