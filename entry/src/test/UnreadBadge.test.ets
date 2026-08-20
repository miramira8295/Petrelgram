import { describe, expect, it } from '@ohos/hypium';
import {
  BADGE_RIGHT_EDGE, unreadBadgeOffsetX, unreadBadgeText, unreadBadgeWidth
} from '../main/ets/util/unreadBadge';

export default function unreadBadgeTest() {
  describe('unreadBadge', () => {
    it('宽度分三档：1 位 / 2 位 / 99+', 0, () => {
      expect(unreadBadgeWidth(1)).assertEqual(22);
      expect(unreadBadgeWidth(9)).assertEqual(22);
      expect(unreadBadgeWidth(10)).assertEqual(27);
      expect(unreadBadgeWidth(99)).assertEqual(27);
      expect(unreadBadgeWidth(100)).assertEqual(34);
      expect(unreadBadgeWidth(9999)).assertEqual(34);
    });

    it('右边缘恒定——宽度和落点必须一起变', 0, () => {
      // 这条是这个文件存在的理由：改宽度表而忘了改位置，角标就往右溢出。
      for (const n of [1, 9, 10, 99, 100, 5000]) {
        expect(unreadBadgeOffsetX(n) + unreadBadgeWidth(n)).assertEqual(BADGE_RIGHT_EDGE);
      }
    });

    it('落点永远为正，角标不会被挤出左边', 0, () => {
      for (const n of [1, 10, 100, 99999]) {
        expect(unreadBadgeOffsetX(n) > 0).assertTrue();
      }
    });

    it('超过 99 显示 99+', 0, () => {
      expect(unreadBadgeText(1)).assertEqual('1');
      expect(unreadBadgeText(99)).assertEqual('99');
      expect(unreadBadgeText(100)).assertEqual('99+');
    });

    it('位数增加时宽度只增不减', 0, () => {
      let prev: number = 0;
      for (const n of [1, 9, 10, 99, 100, 1000]) {
        const w: number = unreadBadgeWidth(n);
        expect(w >= prev).assertTrue();
        prev = w;
      }
    });
  });
}
