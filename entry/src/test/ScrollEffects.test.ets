import { describe, expect, it } from '@ohos/hypium';
import { animationDurationFor, scrollActiveNow, setScrollActive } from '../main/ets/util/scrollEffects';

export default function scrollEffectsTest() {
  describe('animationDurationFor', () => {
    it('设置关掉时一律 0', 0, (): void => {
      expect(animationDurationFor(false, false, 150)).assertEqual(0);
      expect(animationDurationFor(false, true, 150)).assertEqual(0);
    });
    it('滑动中一律 0，哪怕设置开着', 0, (): void => {
      expect(animationDurationFor(true, true, 150)).assertEqual(0);
    });
    it('设置开着且没在滑动时原样返回', 0, (): void => {
      expect(animationDurationFor(true, false, 150)).assertEqual(150);
      expect(animationDurationFor(true, false, 0)).assertEqual(0);
    });
    it('setScrollActive 往返：置真、置假都能读回', 0, (): void => {
      setScrollActive(true);
      expect(scrollActiveNow()).assertTrue();
      setScrollActive(false);
      expect(scrollActiveNow()).assertFalse();
    });
  });
}
