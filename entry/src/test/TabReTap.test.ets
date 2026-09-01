import { describe, expect, it } from '@ohos/hypium';
import { isPriorityUnread, nextUnreadIndex, reTapAction } from '../main/ets/util/tabReTap';

export default function tabReTapTest() {
  describe('tabReTap', () => {
    it('从当前位置往后找未读', 0, (): void => {
      const unread = [false, true, false, true, false];
      expect(nextUnreadIndex(unread, -1)).assertEqual(1);
      expect(nextUnreadIndex(unread, 1)).assertEqual(3);
    });
    it('找到末尾后不回绕', 0, (): void => {
      const unread = [true, false, false];
      expect(nextUnreadIndex(unread, 2)).assertEqual(-1);
      expect(nextUnreadIndex(unread, 0)).assertEqual(-1);
    });
    it('没有未读或空列表返回 -1', 0, (): void => {
      expect(nextUnreadIndex([false, false], 0)).assertEqual(-1);
      expect(nextUnreadIndex([], 0)).assertEqual(-1);
    });
    it('越界的起点也能用', 0, (): void => {
      const unread = [false, true];
      expect(nextUnreadIndex(unread, 99)).assertEqual(-1);
      expect(nextUnreadIndex(unread, -99)).assertEqual(1);
    });
    it('未静音未读优先于回顶', 0, (): void => {
      expect(reTapAction(false, true)).assertEqual('unread');
      expect(reTapAction(false, false)).assertEqual('top');
      expect(reTapAction(true, true)).assertEqual('unread');
      expect(reTapAction(true, false)).assertEqual('none');
    });
    it('静音未读不参与定位', 0, (): void => {
      expect(isPriorityUnread(3, false, false)).assertTrue();
      expect(isPriorityUnread(0, true, false)).assertTrue();
      expect(isPriorityUnread(3, false, true)).assertFalse();
      expect(isPriorityUnread(0, true, true)).assertFalse();
      expect(isPriorityUnread(0, false, false)).assertFalse();
    });
  });
}
