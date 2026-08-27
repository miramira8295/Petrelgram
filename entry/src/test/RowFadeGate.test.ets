import { describe, it, expect } from '@ohos/hypium';
import {
  rowFadeAnimationActive, rowFadeTransition,
  INITIAL_ROW_FADE_WINDOW_MS, RowFadeTransition
} from '../main/ets/util/rowFadeGate';

export default function rowFadeGateTest() {
  describe('rowFadeAnimationActive', () => {
    it('遮罩期间恒放行——首屏那一波淡入靠它', 0, (): void => {
      expect(rowFadeAnimationActive(true, 10000, 0)).assertTrue();
      expect(rowFadeAnimationActive(true, 10000, 1)).assertTrue();
    });

    it('揭示之后的窗口内仍然放行：逐条淡入要跑完', 0, (): void => {
      // 这一条就是「首屏逐条淡入必须保住」的钉子：masked 翻假的那一帧，
      // armedAt 还是上一帧（masked 期间续的）的时间戳，闩必须是开的。
      expect(rowFadeAnimationActive(false, 10000, 10000)).assertTrue();
      expect(rowFadeAnimationActive(false, 10016, 10000)).assertTrue();
      // 一波 stagger（7 × 14ms）加一段淡入（90ms）都还在窗口里。
      expect(rowFadeAnimationActive(false, 10000 + 98 + 90, 10000)).assertTrue();
      expect(rowFadeAnimationActive(
        false, 10000 + INITIAL_ROW_FADE_WINDOW_MS, 10000)).assertTrue();
    });

    it('窗口之外不放行：常驻动画上下文失效', 0, (): void => {
      expect(rowFadeAnimationActive(
        false, 10000 + INITIAL_ROW_FADE_WINDOW_MS + 1, 10000)).assertFalse();
      // 用户看到的那种「过一会图都加载完了就恢复正常」的场景：进页很久之后
      // 一张缩略图落地引起的 rerender，不该再开动画上下文。
      expect(rowFadeAnimationActive(false, 40000, 10000)).assertFalse();
    });

    it('从没揭示过就不放行', 0, (): void => {
      expect(rowFadeAnimationActive(false, 10000, 0)).assertFalse();
    });
  });

  describe('rowFadeTransition', () => {
    it('闩开着就带上时长和 stagger', 0, (): void => {
      const plan: RowFadeTransition = rowFadeTransition(false, true, 90, 42);
      expect(plan.enabled).assertTrue();
      expect(plan.duration).assertEqual(90);
      expect(plan.delay).assertEqual(42);
    });

    it('闩关了就整个不挂效果——不是把 duration 给 0', 0, (): void => {
      // 这一条是这轮改动的钉子：常驻 .animation() 给 0 挡不住动画上下文，
      // 换成 transition 之后"关掉"的写法必须是 TransitionEffect.IDENTITY。
      const plan: RowFadeTransition = rowFadeTransition(false, false, 90, 42);
      expect(plan.enabled).assertFalse();
      expect(plan.duration).assertEqual(0);
      expect(plan.delay).assertEqual(0);
    });

    it('滑动中一律不做入场动画', 0, (): void => {
      // 原判据照搬：chatTgsScrollActive 为真时 duration / delay 都给 0。
      const plan: RowFadeTransition = rowFadeTransition(true, true, 90, 42);
      expect(plan.enabled).assertFalse();
      expect(plan.duration).assertEqual(0);
    });

    it('两个条件都不成立时也是关的', 0, (): void => {
      expect(rowFadeTransition(true, false, 90, 42).enabled).assertFalse();
    });
  });
}
