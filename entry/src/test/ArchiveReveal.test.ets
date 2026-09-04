import { describe, expect, it } from '@ohos/hypium';
import {
  archiveCardScale, archiveIconScale, archiveIconSpin, archiveRevealProgress
} from '../main/ets/util/archiveReveal';

export default function archiveRevealTest() {
  describe('archiveReveal', () => {
    it('进度按下拉深度归一化', 0, () => {
      expect(archiveRevealProgress(0, 72, false)).assertEqual(0);
      expect(archiveRevealProgress(36, 72, false)).assertEqual(0.5);
      expect(archiveRevealProgress(72, 72, false)).assertEqual(1);
    });

    // 拉过头不该让卡片继续放大——上面还有个更硬的钳位在 onDidScroll 里，
    // 这里再钳一次，两处都错才会露出来。
    it('拉过头钳在 1，负数钳在 0', 0, () => {
      expect(archiveRevealProgress(200, 72, false)).assertEqual(1);
      expect(archiveRevealProgress(-30, 72, false)).assertEqual(0);
    });

    it('已锁定展开时恒为 1，不再跟手', 0, () => {
      expect(archiveRevealProgress(0, 72, true)).assertEqual(1);
      expect(archiveRevealProgress(5, 72, true)).assertEqual(1);
    });

    it('行高非法时给 0，不产生 NaN 传进 scale', 0, () => {
      expect(archiveRevealProgress(36, 0, false)).assertEqual(0);
      expect(archiveRevealProgress(36, -1, false)).assertEqual(0);
    });

    it('卡片缩放两端固定：0.86 → 1', 0, () => {
      expect(archiveCardScale(0)).assertEqual(0.86);
      expect(archiveCardScale(1)).assertEqual(1);
      expect(archiveCardScale(0.5) > 0.86 && archiveCardScale(0.5) < 1).assertTrue();
    });

    it('图标从 -90° 转正', 0, () => {
      expect(archiveIconSpin(0)).assertEqual(-90);
      expect(archiveIconSpin(1)).assertEqual(0);
    });

    it('图标缩放比卡片夸张一档：0.6 → 1', 0, () => {
      expect(archiveIconScale(0)).assertEqual(0.6);
      expect(archiveIconScale(1)).assertEqual(1);
    });

    it('越界的进度不会算出越界的形变', 0, () => {
      expect(archiveCardScale(2)).assertEqual(1);
      expect(archiveCardScale(-1)).assertEqual(0.86);
      expect(archiveIconSpin(2)).assertEqual(0);
    });
  });
}
