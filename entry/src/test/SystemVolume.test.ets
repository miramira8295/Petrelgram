import { describe, it, expect } from '@ohos/hypium';
import { fractionOf, volumeLevelFor } from '../main/ets/util/systemVolume';

export default function systemVolumeTest() {
  describe('systemVolume', () => {
    // 系统音量是**整数档**（典型 0..15），手势给的是 0..1 的比例，两边要来回换。
    it('maps_the_fraction_onto_the_device_levels', 0, () => {
      expect(volumeLevelFor(0, 0, 15)).assertEqual(0);
      expect(volumeLevelFor(1, 0, 15)).assertEqual(15);
      expect(volumeLevelFor(0.5, 0, 15)).assertEqual(8);  // 7.5 → 就近取整
    });

    it('clamps_out_of_range_fractions', 0, () => {
      expect(volumeLevelFor(-3, 0, 15)).assertEqual(0);
      expect(volumeLevelFor(9, 0, 15)).assertEqual(15);
    });

    // 有些设备的最小档不是 0。
    it('respects_a_non_zero_minimum', 0, () => {
      expect(volumeLevelFor(0, 3, 15)).assertEqual(3);
      expect(volumeLevelFor(1, 3, 15)).assertEqual(15);
    });

    it('fraction_is_the_inverse', 0, () => {
      expect(fractionOf(0, 0, 15)).assertEqual(0);
      expect(fractionOf(15, 0, 15)).assertEqual(1);
      expect(Math.abs(fractionOf(8, 0, 15) - 8 / 15) < 0.001).assertTrue();
    });

    // 读不到档位范围时不能除以 0——那会让 HUD 显示 NaN。
    it('is_safe_when_the_range_is_degenerate', 0, () => {
      expect(volumeLevelFor(0.5, 7, 7)).assertEqual(7);
      expect(fractionOf(7, 7, 7)).assertEqual(0);
    });
  });
}
