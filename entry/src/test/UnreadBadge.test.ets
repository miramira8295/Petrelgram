import { describe, expect, it } from '@ohos/hypium';
import {
  BADGE_RIGHT_EDGE, unreadBadgeOffsetX, unreadBadgeText, unreadBadgeWidth
} from '../main/ets/util/unreadBadge';

export default function unreadBadgeTest() {
  describe('unreadBadge', () => {
    // 2026-09-23 上限从 99+ 提到 999+（用户要求），多出一档 4 字符宽。
    it('宽度分四档：1 位 / 2 位 / 3 位 / 4 字符缩写', 0, () => {
      expect(unreadBadgeWidth(1)).assertEqual(22);
      expect(unreadBadgeWidth(9)).assertEqual(22);
      expect(unreadBadgeWidth(10)).assertEqual(27);
      expect(unreadBadgeWidth(99)).assertEqual(27);
      expect(unreadBadgeWidth(100)).assertEqual(34);
      expect(unreadBadgeWidth(999)).assertEqual(34);
      expect(unreadBadgeWidth(1000)).assertEqual(41);
      expect(unreadBadgeWidth(99999)).assertEqual(41);
    });

    it('右边缘恒定——宽度和落点必须一起变', 0, () => {
      // 这条是这个文件存在的理由：改宽度表而忘了改位置，角标就往右溢出。
      for (const n of [1, 9, 10, 99, 100, 999, 1000, 5000]) {
        expect(unreadBadgeOffsetX(n) + unreadBadgeWidth(n)).assertEqual(BADGE_RIGHT_EDGE);
      }
    });

    it('落点永远为正，角标不会被挤出左边', 0, () => {
      for (const n of [1, 10, 100, 99999]) {
        expect(unreadBadgeOffsetX(n) > 0).assertTrue();
      }
    });

    // #225：超过 999 不再封顶，改成与浏览量同一种缩写（1.2K / 52K / 1.2M）。
    it('超过 999 缩写为 K / M，三位数原样', 0, () => {
      expect(unreadBadgeText(1)).assertEqual('1');
      expect(unreadBadgeText(99)).assertEqual('99');
      expect(unreadBadgeText(100)).assertEqual('100');
      expect(unreadBadgeText(999)).assertEqual('999');
      expect(unreadBadgeText(1000)).assertEqual('1K');
      expect(unreadBadgeText(1234)).assertEqual('1.2K');
      expect(unreadBadgeText(52345)).assertEqual('52K');
      expect(unreadBadgeText(123456)).assertEqual('123K');
      expect(unreadBadgeText(1234567)).assertEqual('1.2M');
    });

    it('缩写后不超过 4 个字符，装得进最宽那档', 0, () => {
      for (const n of [1000, 1999, 9999, 99999, 999999, 1000000, 99999999]) {
        expect(unreadBadgeText(n).length <= 4).assertTrue();
      }
    });

    it('位数增加时宽度只增不减', 0, () => {
      let prev: number = 0;
      for (const n of [1, 9, 10, 99, 100, 999, 1000, 10000]) {
        const w: number = unreadBadgeWidth(n);
        expect(w >= prev).assertTrue();
        prev = w;
      }
    });
  });
}
