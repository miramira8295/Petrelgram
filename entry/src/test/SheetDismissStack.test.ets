import { describe, it, expect, beforeEach } from '@ohos/hypium';
import {
  pushSheetDismiss, dismissTopSheet, dismissAllSheets, openSheetCount, resetSheetDismissForTest
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

    // 分享进来的那一刻要把已经开着的面板全收掉：bindSheet 画在浮层里、盖在
    // Index 那层「分享到…」之上（用户 2026-10-30）。
    it('dismissAllSheets 从最上面往下全关，并返回关了几个', 0, (): void => {
      const order: string[] = [];
      pushSheetDismiss((): void => { order.push('bottom'); });
      pushSheetDismiss((): void => { order.push('middle'); });
      pushSheetDismiss((): void => { order.push('top'); });
      expect(dismissAllSheets()).assertEqual(3);
      expect(order.join(',')).assertEqual('top,middle,bottom');
      expect(openSheetCount()).assertEqual(0);
    });

    it('没有面板时 dismissAllSheets 返回 0', 0, (): void => {
      expect(dismissAllSheets()).assertEqual(0);
    });

    // 面板自己关掉时会调注销函数，而 dismissAllSheets 已经把条目弹走了。
    // 注销必须是幂等的，否则会顺手删掉别人的登记（表现是那个面板按返回关不掉）。
    it('被 dismissAllSheets 关掉后，各自的注销函数仍可安全调用', 0, (): void => {
      const order: string[] = [];
      const offA: () => void = pushSheetDismiss((): void => { order.push('a'); });
      const offB: () => void = pushSheetDismiss((): void => { order.push('b'); });
      expect(dismissAllSheets()).assertEqual(2);
      offA();
      offB();
      expect(openSheetCount()).assertEqual(0);
      expect(order.join(',')).assertEqual('b,a');
      expect(dismissTopSheet()).assertFalse();
    });
  });
}
