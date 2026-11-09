import { describe, expect, it } from '@ohos/hypium';
import { ColorModeBaseline, colorModeChanged } from '../main/ets/util/configChange';

// 深浅色基准（issue #194，2026-09-18 用户日志坐实）。
//
// 用户症状：从深色切回浅色，壁纸的深色遮罩撤不掉。日志：
//
//   colorMode 1->0  changed=true     ← 进深色
//   colorMode 1->1  changed=false    ← 切回浅色，"从"值居然还是 1
//
// 真因是基准被写了两遍：onConfigurationUpdate 按**参数** config 记下 0（对的），
// 紧接着 applyImmersiveStatusBar 又按 **this.context.config** 记了一遍（那一刻
// 还是旧值 1），把 0 盖回 1。于是切回浅色算成「1→1 没变」直接 return，
// 状态栏反色 / KEY_APP_DARK / 外观 epoch 全不执行。
//
// 这组用例钉的就是「一来一回都必须被认出来」。

const DARK: number = 0;
const LIGHT: number = 1;

export default function colorModeBaselineTest() {
  describe('ColorModeBaseline', () => {
    it('detects_the_round_trip_back_to_the_seeded_mode', 0, () => {
      // 这一条就是 #194：去程认出来了，**回程也必须认出来**。
      const b: ColorModeBaseline = new ColorModeBaseline();
      b.seed(LIGHT);
      expect(b.observe(DARK)).assertTrue();
      expect(b.current()).assertEqual(DARK);
      expect(b.observe(LIGHT)).assertTrue();
      expect(b.current()).assertEqual(LIGHT);
    });

    it('ignores_repeats', 0, () => {
      // 字号、转屏、回前台都会触发 onConfigurationUpdate，颜色没变就不该重绘全应用。
      const b: ColorModeBaseline = new ColorModeBaseline();
      b.seed(LIGHT);
      expect(b.observe(LIGHT)).assertFalse();
      expect(b.observe(LIGHT)).assertFalse();
      expect(b.current()).assertEqual(LIGHT);
    });

    it('treats_missing_mode_as_unknown_and_only_reports_once', 0, () => {
      const b: ColorModeBaseline = new ColorModeBaseline();
      b.seed(undefined);
      // 未知 → 未知不算变化。
      expect(b.observe(undefined)).assertFalse();
      expect(b.observe(DARK)).assertTrue();
    });

    it('seed_does_not_report_a_change', 0, () => {
      // 播种只是记基准，不该被当成一次切换（启动时会调）。
      const b: ColorModeBaseline = new ColorModeBaseline();
      b.seed(DARK);
      expect(b.current()).assertEqual(DARK);
      expect(b.observe(DARK)).assertFalse();
    });

    it('colorModeChanged_still_compares_plainly', 0, () => {
      expect(colorModeChanged(LIGHT, DARK)).assertTrue();
      expect(colorModeChanged(LIGHT, LIGHT)).assertFalse();
      expect(colorModeChanged(LIGHT, undefined)).assertTrue();
    });
  });
}
