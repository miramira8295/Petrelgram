import { describe, expect, it } from '@ohos/hypium';
import {
  BreakpointType, HEIGHT_BP_LG, HEIGHT_BP_MD, HEIGHT_BP_SM, WIDTH_BP_LG, WIDTH_BP_MD,
  WIDTH_BP_SM, WIDTH_BP_XL, WIDTH_BP_XS, dockModeForBreakpoint, heightBreakpointOfSize,
  isSplitByBreakpoint, widthBreakpointOfVp
} from '../main/ets/util/layoutBreakpoint';
import { DOCK_MODE_BOTTOM, DOCK_MODE_LEFT_FLOATING } from '../main/ets/util/splitMetrics';

// 尺寸 → 断点 → 判据，整条链一起测（原 SplitMetrics.test 里 isSplitLayout 的具体尺寸用例）。
function splitAt(w: number, h: number, force: boolean = false): boolean {
  return isSplitByBreakpoint(widthBreakpointOfVp(w), heightBreakpointOfSize(w, h), force);
}

function dockAt(w: number, h: number, force: boolean): string {
  return dockModeForBreakpoint(widthBreakpointOfVp(w), heightBreakpointOfSize(w, h), force);
}

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

    // ── 从尺寸推断点（只用于 loadContent 之前的初值），阈值照官方表 ──────────
    it('横向断点阈值 320/600/840/1440，左闭右开', 0, () => {
      expect(widthBreakpointOfVp(319)).assertEqual(WIDTH_BP_XS);
      expect(widthBreakpointOfVp(320)).assertEqual(WIDTH_BP_SM);
      expect(widthBreakpointOfVp(599)).assertEqual(WIDTH_BP_SM);
      expect(widthBreakpointOfVp(600)).assertEqual(WIDTH_BP_MD);
      expect(widthBreakpointOfVp(839)).assertEqual(WIDTH_BP_MD);
      expect(widthBreakpointOfVp(840)).assertEqual(WIDTH_BP_LG);
      expect(widthBreakpointOfVp(1439)).assertEqual(WIDTH_BP_LG);
      expect(widthBreakpointOfVp(1440)).assertEqual(WIDTH_BP_XL);
      expect(widthBreakpointOfVp(Number.NaN)).assertEqual(WIDTH_BP_XS);
    });

    it('纵向断点按高宽比 0.8 / 1.2', 0, () => {
      expect(heightBreakpointOfSize(1000, 799)).assertEqual(HEIGHT_BP_SM);
      expect(heightBreakpointOfSize(1000, 800)).assertEqual(HEIGHT_BP_MD);
      expect(heightBreakpointOfSize(1000, 1199)).assertEqual(HEIGHT_BP_MD);
      expect(heightBreakpointOfSize(1000, 1200)).assertEqual(HEIGHT_BP_LG);
    });

    // ── 原 isSplitLayout 的具体尺寸用例，结论不变的照搬 ──────────────────
    it('宽度 600 为界，含等号', 0, () => {
      expect(splitAt(599, 900)).assertFalse();
      expect(splitAt(600, 900)).assertTrue();
      expect(splitAt(601, 900)).assertTrue();
      expect(splitAt(360, 780)).assertFalse();
      expect(splitAt(1137, 800)).assertTrue();
    });

    // #125：Mate70 Pro+ 量级，竖屏 376×809，横屏 809×376。
    it('手机横竖屏都不分栏——#125', 0, () => {
      expect(splitAt(376, 809)).assertFalse();
      expect(splitAt(809, 376)).assertFalse();
      expect(splitAt(800, 599)).assertFalse();
    });

    // **与旧规则唯一的差异**：宽在 600–840、高宽比 < 0.8、但高度 ≥ 600 的窗口
    // （例如 800×600）。旧规则看短边，≥600 就分栏；官方分类里它属于「直板机横屏」
    // 那一档（md 宽 + 横向窗口），判单栏。8 种标准形态都不落在这里，实际多见于
    // 悬浮窗或 PC 上拖出来的窗口。
    it('md 宽 + 横向窗口一律单栏（800×600 与旧规则不同）', 0, () => {
      expect(splitAt(800, 600)).assertFalse();
      expect(splitAt(839, 660)).assertFalse();
    });

    it('平板横竖屏都分栏', 0, () => {
      expect(splitAt(632, 924)).assertTrue();
      expect(splitAt(924, 632)).assertTrue();
    });

    it('折叠屏展开进分栏、合上回单栏', 0, () => {
      expect(splitAt(720, 830)).assertTrue();
      expect(splitAt(380, 850)).assertFalse();
    });

    it('高度读不到时退回只看宽度', 0, () => {
      expect(splitAt(1000, 0)).assertTrue();
      expect(splitAt(1000, Number.NaN)).assertTrue();
      expect(splitAt(400, 0)).assertFalse();
    });

    it('强制单栏压过几何', 0, () => {
      expect(splitAt(1280, 800, true)).assertFalse();
      expect(splitAt(1280, 800, false)).assertTrue();
      expect(splitAt(376, 809, true)).assertFalse();
    });

    // 2026-09-17 用户定：只分两种 dock。平板分栏 = 左栏底部自绘胶囊，其余 = 底部胶囊。
    it('dock 只有两种，与分栏同源', 0, () => {
      expect(dockAt(1280, 800, false)).assertEqual(DOCK_MODE_LEFT_FLOATING);
      expect(dockAt(700, 900, false)).assertEqual(DOCK_MODE_LEFT_FLOATING);
      expect(dockAt(1280, 800, true)).assertEqual(DOCK_MODE_BOTTOM);
      expect(dockAt(700, 900, true)).assertEqual(DOCK_MODE_BOTTOM);
      expect(dockAt(400, 860, false)).assertEqual(DOCK_MODE_BOTTOM);
      expect(dockAt(809, 376, false)).assertEqual(DOCK_MODE_BOTTOM);
      expect(dockAt(Number.NaN, 860, false)).assertEqual(DOCK_MODE_BOTTOM);
    });
  });
}
