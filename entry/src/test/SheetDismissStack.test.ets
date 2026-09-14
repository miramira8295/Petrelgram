import { describe, it, expect, beforeEach } from '@ohos/hypium';
import {
  pushSheetDismiss, dismissTopSheet, openSheetCount, resetSheetDismissForTest
} from '../main/ets/util/sheetDismissStack';

export default function sheetDismissStackTest() {
  describe('sheetDismissStack', () => {
    beforeEach((): void => { resetSheetDismissForTest(); });

    it('没有面板时不消费返回键', 0, (): void => {
      expect(dismissTopSheet()).assertFalse();
    });

    it('后进先出：先关最上面那个', 0, (): void => {
      const order: string[] = [];
      pushSheetDismiss((): void => { order.push('first'); });
      pushSheetDismiss((): void => { order.push('second'); });
      expect(dismissTopSheet()).assertTrue();
      expect(order.join(',')).assertEqual('second');
      expect(dismissTopSheet()).assertTrue();
      expect(order.join(',')).assertEqual('second,first');
      expect(dismissTopSheet()).assertFalse();
    });

    it('面板自己关掉后注销，返回键不会去关一个不在的面板', 0, (): void => {
      let closed: number = 0;
      const off = pushSheetDismiss((): void => { closed++; });
      off();
      expect(openSheetCount()).assertEqual(0);
      expect(dismissTopSheet()).assertFalse();
      expect(closed).assertEqual(0);
    });

    it('注销的是自己那一条，不影响别人', 0, (): void => {
      const order: string[] = [];
      const offA = pushSheetDismiss((): void => { order.push('a'); });
      pushSheetDismiss((): void => { order.push('b'); });
      offA();
      expect(openSheetCount()).assertEqual(1);
      expect(dismissTopSheet()).assertTrue();
      expect(order.join(',')).assertEqual('b');
    });
  });
}
