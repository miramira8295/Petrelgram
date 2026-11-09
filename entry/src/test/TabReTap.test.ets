import { describe, expect, it } from '@ohos/hypium';
import {
  isPriorityUnread, nextUnreadIndex, reTapAction, smoothJumpStage
} from '../main/ets/util/tabReTap';

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
    it('远跳先无动画中转到目标同侧一屏内', 0, (): void => {
      // 从 169 回顶：中转到 8，剩下 8 行平滑。
      expect(smoothJumpStage(169, 0, 8)).assertEqual(8);
      // 从顶跳到 169：中转到 161。
      expect(smoothJumpStage(0, 169, 8)).assertEqual(161);
      // 距离在一屏内：不中转。
      expect(smoothJumpStage(5, 0, 8)).assertEqual(-1);
      expect(smoothJumpStage(0, 8, 8)).assertEqual(-1);
      // 两个方向的中转都落在目标同侧 span 行处。
      expect(smoothJumpStage(30, 3, 8)).assertEqual(11);
      expect(smoothJumpStage(3, 30, 8)).assertEqual(22);
      expect(smoothJumpStage(20, 4, 8)).assertEqual(12);
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
