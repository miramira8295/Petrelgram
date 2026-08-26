import { describe, expect, it } from '@ohos/hypium';
import { nextUnreadIndex, reTapAction } from '../main/ets/util/tabReTap';

export default function tabReTapTest() {
  describe('tabReTap', () => {
    it('从当前位置往后找未读', 0, (): void => {
      const unread = [false, true, false, true, false];
      expect(nextUnreadIndex(unread, -1)).assertEqual(1);
      expect(nextUnreadIndex(unread, 1)).assertEqual(3);
    });
    it('找到末尾绕回开头', 0, (): void => {
      const unread = [true, false, false];
      expect(nextUnreadIndex(unread, 2)).assertEqual(0);
      expect(nextUnreadIndex(unread, 0)).assertEqual(0);
    });
    it('没有未读或空列表返回 -1', 0, (): void => {
      expect(nextUnreadIndex([false, false], 0)).assertEqual(-1);
      expect(nextUnreadIndex([], 0)).assertEqual(-1);
    });
    it('越界的起点也能用', 0, (): void => {
      const unread = [false, true];
      expect(nextUnreadIndex(unread, 99)).assertEqual(1);
      expect(nextUnreadIndex(unread, -99)).assertEqual(1);
    });
    it('不在顶就回顶，在顶且有未读才跳', 0, (): void => {
      expect(reTapAction(false, true)).assertEqual('top');
      expect(reTapAction(false, false)).assertEqual('top');
      expect(reTapAction(true, true)).assertEqual('unread');
      expect(reTapAction(true, false)).assertEqual('none');
    });
  });
}
