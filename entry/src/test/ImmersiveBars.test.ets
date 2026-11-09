import { describe, expect, it } from '@ohos/hypium';
import {
  IMMERSIVE_TOGGLE_VP, ImmersiveBarsState, nextImmersiveBars
} from '../main/ets/util/immersiveBars';
import {
  HEIGHT_BP_LG, HEIGHT_BP_MD, HEIGHT_BP_SM, WIDTH_BP_MD, WIDTH_BP_SM, isSmallSquare
} from '../main/ets/util/layoutBreakpoint';

function run(deltas: number[], start: ImmersiveBarsState = new ImmersiveBarsState()): ImmersiveBarsState {
  let s: ImmersiveBarsState = start;
  for (const d of deltas) {
    s = nextImmersiveBars(s, d, false);
  }
  return s;
}

// 小方形屏上滑隐藏 / 下滑恢复标题栏与底部页签（SPEC-04）。
export default function immersiveBarsTest() {
  describe('ImmersiveBars', () => {
    it('小方形屏 = 宽 sm + 高宽比 md，只有这一档', 0, () => {
      expect(isSmallSquare(WIDTH_BP_SM, HEIGHT_BP_MD)).assertTrue();
      expect(isSmallSquare(WIDTH_BP_SM, HEIGHT_BP_LG)).assertFalse();
      expect(isSmallSquare(WIDTH_BP_MD, HEIGHT_BP_MD)).assertFalse();
      expect(isSmallSquare(WIDTH_BP_MD, HEIGHT_BP_SM)).assertFalse();
    });

    it('往尾部累计滑过阈值才隐藏', 0, () => {
      expect(run([5, 5, 5]).hidden).assertFalse();
      expect(run([10, 10, 10]).hidden).assertTrue();
    });

    it('隐藏后往回累计滑过阈值才恢复', 0, () => {
      const hidden: ImmersiveBarsState = run([IMMERSIVE_TOGGLE_VP]);
      expect(hidden.hidden).assertTrue();
      expect(run([-10], hidden).hidden).assertTrue();
      expect(run([-10, -10, -10], hidden).hidden).assertFalse();
    });

    // 惯性末尾的来回小抖动不能让标题栏闪：方向一反就从零累计。
    it('方向来回抖动不切换', 0, () => {
      expect(run([15, -3, 15, -3, 15]).hidden).assertFalse();
    });

    it('回到顶部一律恢复', 0, () => {
      const hidden: ImmersiveBarsState = run([IMMERSIVE_TOGGLE_VP]);
      expect(nextImmersiveBars(hidden, 5, true).hidden).assertFalse();
    });

    it('零或非法增量不改变状态，也不改入参', 0, () => {
      const hidden: ImmersiveBarsState = run([IMMERSIVE_TOGGLE_VP]);
      expect(nextImmersiveBars(hidden, 0, false).hidden).assertTrue();
      expect(nextImmersiveBars(hidden, Number.NaN, false).hidden).assertTrue();
      const before: number = hidden.accumulated;
      nextImmersiveBars(hidden, -100, false);
      expect(hidden.hidden).assertTrue();
      expect(hidden.accumulated).assertEqual(before);
    });
  });
}
