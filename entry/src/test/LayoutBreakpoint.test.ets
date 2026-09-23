import { describe, expect, it } from '@ohos/hypium';
import {
  BreakpointType, HEIGHT_BP_LG, HEIGHT_BP_MD, HEIGHT_BP_SM, WIDTH_BP_LG, WIDTH_BP_MD,
  WIDTH_BP_SM, WIDTH_BP_XL, WIDTH_BP_XS, isSplitByBreakpoint
} from '../main/ets/util/layoutBreakpoint';

// 分栏判据改用系统断点（官方《断点系统》8 种屏幕形态）。每种形态一条，结论必须
// 与原来的「短边 ≥ 600vp」规则逐一相同——这次只换判据来源，不改行为。
export default function layoutBreakpointTest() {
  describe('LayoutBreakpoint', () => {
    // 与系统枚举数值一致：写入端存的是 getWindowWidthBreakpoint() 的原值。
    it('常量与系统枚举数值一致', 0, () => {
      expect(WIDTH_BP_XS).assertEqual(0);
      expect(WIDTH_BP_SM).assertEqual(1);
      expect(WIDTH_BP_MD).assertEqual(2);
      expect(WIDTH_BP_LG).assertEqual(3);
      expect(WIDTH_BP_XL).assertEqual(4);
      expect(HEIGHT_BP_SM).assertEqual(0);
      expect(HEIGHT_BP_MD).assertEqual(1);
      expect(HEIGHT_BP_LG).assertEqual(2);
    });

    it('直板机竖屏（sm/lg）单栏', 0, () => {
      expect(isSplitByBreakpoint(WIDTH_BP_SM, HEIGHT_BP_LG, false)).assertFalse();
    });

    // #125：手机横过来宽度就进了 md，只看宽度会整个应用进分栏。
    it('直板机横屏（md/sm）单栏——#125', 0, () => {
      expect(isSplitByBreakpoint(WIDTH_BP_MD, HEIGHT_BP_SM, false)).assertFalse();
    });

    it('小方形屏（sm/md，Pura X 外屏）单栏', 0, () => {
      expect(isSplitByBreakpoint(WIDTH_BP_SM, HEIGHT_BP_MD, false)).assertFalse();
    });

    it('大方形屏（md/md，折叠屏展开）分栏', 0, () => {
      expect(isSplitByBreakpoint(WIDTH_BP_MD, HEIGHT_BP_MD, false)).assertTrue();
    });

    it('大屏竖屏（md/lg，平板竖屏）分栏', 0, () => {
      expect(isSplitByBreakpoint(WIDTH_BP_MD, HEIGHT_BP_LG, false)).assertTrue();
    });

    it('大屏横屏（lg/sm，平板横屏）分栏', 0, () => {
      expect(isSplitByBreakpoint(WIDTH_BP_LG, HEIGHT_BP_SM, false)).assertTrue();
    });

    it('超大屏（xl/sm，PC）分栏', 0, () => {
      expect(isSplitByBreakpoint(WIDTH_BP_XL, HEIGHT_BP_SM, false)).assertTrue();
    });

    it('圆形屏（xs）单栏', 0, () => {
      expect(isSplitByBreakpoint(WIDTH_BP_XS, HEIGHT_BP_SM, false)).assertFalse();
    });

    // 设置里的「强制单栏」：用户说了算，任何形态都不分栏。
    it('强制单栏压过一切', 0, () => {
      expect(isSplitByBreakpoint(WIDTH_BP_XL, HEIGHT_BP_SM, true)).assertFalse();
      expect(isSplitByBreakpoint(WIDTH_BP_MD, HEIGHT_BP_LG, true)).assertFalse();
    });

    // 官方 BreakpointType：缺的档位向下回退到最近的一档。
    it('BreakpointType 按断点取值，缺档向下回退', 0, () => {
      const full: BreakpointType<number> = new BreakpointType<number>(10, 20, 30, 40);
      expect(full.getValue(WIDTH_BP_XS)).assertEqual(10);
      expect(full.getValue(WIDTH_BP_SM)).assertEqual(10);
      expect(full.getValue(WIDTH_BP_MD)).assertEqual(20);
      expect(full.getValue(WIDTH_BP_LG)).assertEqual(30);
      expect(full.getValue(WIDTH_BP_XL)).assertEqual(40);
      const twoTier: BreakpointType<number> = new BreakpointType<number>(12, 24);
      expect(twoTier.getValue(WIDTH_BP_LG)).assertEqual(24);
      expect(twoTier.getValue(WIDTH_BP_XL)).assertEqual(24);
    });
  });
}
