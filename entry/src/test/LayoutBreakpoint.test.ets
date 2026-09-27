import { describe, expect, it } from '@ohos/hypium';
import {
  BreakpointType, HEIGHT_BP_LG, HEIGHT_BP_MD, HEIGHT_BP_SM, WIDTH_BP_LG, WIDTH_BP_MD,
  WIDTH_BP_SM, WIDTH_BP_XL, WIDTH_BP_XS, dockModeForBreakpoint, heightBreakpointOfSize,
  isSplitByBreakpoint, widthBreakpointOfVp, allowsRotationForDisplay
} from '../main/ets/util/layoutBreakpoint';
import { DOCK_MODE_BOTTOM, DOCK_MODE_LEFT_FLOATING } from '../main/ets/util/splitMetrics';

// 尺寸 → 断点 → 判据，整条链一起测（原 SplitMetrics.test 里 isSplitLayout 的具体尺寸用例）。
function splitAt(w: number, h: number, force: boolean = false): boolean {
  return isSplitByBreakpoint(widthBreakpointOfVp(w), heightBreakpointOfSize(w, h), force, !(w > h));
}

function dockAt(w: number, h: number, force: boolean): string {
  return dockModeForBreakpoint(widthBreakpointOfVp(w), heightBreakpointOfSize(w, h), force, !(w > h));
}

// 分栏判据用系统断点（官方《断点系统》8 种屏幕形态），每种形态一条。
// 2026-09-27 起纵向窗口（平板竖屏）改为单栏。
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
      expect(isSplitByBreakpoint(WIDTH_BP_SM, HEIGHT_BP_LG, false, false)).assertFalse();
    });

    // #125：手机横过来宽度就进了 md，只看宽度会整个应用进分栏。
    it('直板机横屏（md/sm）单栏——#125', 0, () => {
      expect(isSplitByBreakpoint(WIDTH_BP_MD, HEIGHT_BP_SM, false, false)).assertFalse();
    });

    it('小方形屏（sm/md，Pura X 外屏）单栏', 0, () => {
      expect(isSplitByBreakpoint(WIDTH_BP_SM, HEIGHT_BP_MD, false, false)).assertFalse();
    });

    // 折叠屏展开态横竖都是 md/md，断点分不出，看窗口横竖：竖着直板，横着分栏。
    it('大方形屏（md/md，折叠屏展开）竖单栏、横分栏', 0, () => {
      expect(isSplitByBreakpoint(WIDTH_BP_MD, HEIGHT_BP_MD, false, false)).assertTrue();
      expect(isSplitByBreakpoint(WIDTH_BP_MD, HEIGHT_BP_MD, false, true)).assertFalse();
    });

    // 纵向窗口压过一切断点组合。
    it('窗口纵向时一律单栏', 0, () => {
      expect(isSplitByBreakpoint(WIDTH_BP_XL, HEIGHT_BP_SM, false, true)).assertFalse();
      expect(isSplitByBreakpoint(WIDTH_BP_LG, HEIGHT_BP_MD, false, true)).assertFalse();
    });

    // 2026-09-27：平板竖屏按直板机走单栏，宽度再大也一样。
    it('大屏竖屏（md/lg、lg/lg，平板竖屏）单栏', 0, () => {
      expect(isSplitByBreakpoint(WIDTH_BP_MD, HEIGHT_BP_LG, false, false)).assertFalse();
      expect(isSplitByBreakpoint(WIDTH_BP_LG, HEIGHT_BP_LG, false, false)).assertFalse();
      expect(isSplitByBreakpoint(WIDTH_BP_XL, HEIGHT_BP_LG, false, false)).assertFalse();
    });

    it('大屏横屏（lg/sm，平板横屏）分栏', 0, () => {
      expect(isSplitByBreakpoint(WIDTH_BP_LG, HEIGHT_BP_SM, false, false)).assertTrue();
    });

    it('超大屏（xl/sm，PC）分栏', 0, () => {
      expect(isSplitByBreakpoint(WIDTH_BP_XL, HEIGHT_BP_SM, false, false)).assertTrue();
    });

    // 手机锁竖屏、大屏可转：看物理屏短边，600vp 为界。
    it('转屏：物理屏短边 ≥ 600vp 才放开', 0, () => {
      // 直板机 1260×2720px @3.5 → 短边 360vp
      expect(allowsRotationForDisplay(1260, 2720, 3.5)).assertFalse();
      // 平板横放 2800×1840px @2.3 → 短边 800vp
      expect(allowsRotationForDisplay(2800, 1840, 2.3)).assertTrue();
      expect(allowsRotationForDisplay(600, 900, 1)).assertTrue();
      expect(allowsRotationForDisplay(599, 900, 1)).assertFalse();
      // 读不到尺寸按手机处理
      expect(allowsRotationForDisplay(0, 0, 3)).assertFalse();
      expect(allowsRotationForDisplay(1200, 2000, 0)).assertFalse();
    });

    it('圆形屏（xs）单栏', 0, () => {
      expect(isSplitByBreakpoint(WIDTH_BP_XS, HEIGHT_BP_SM, false, false)).assertFalse();
    });

    // 设置里的「强制单栏」：用户说了算，任何形态都不分栏。
    it('强制单栏压过一切', 0, () => {
      expect(isSplitByBreakpoint(WIDTH_BP_XL, HEIGHT_BP_SM, true, false)).assertFalse();
      expect(isSplitByBreakpoint(WIDTH_BP_MD, HEIGHT_BP_LG, true, false)).assertFalse();
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
    // 横向窗口宽度 600 起才可能分栏；md 宽 + 横向窗口（直板机横屏那一档）仍单栏。
    it('横向窗口的宽度下限', 0, () => {
      expect(splitAt(599, 400)).assertFalse();
      expect(splitAt(840, 700)).assertTrue();
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

    // 2026-09-27 用户定：平板竖屏单栏（与直板机一样），横屏分栏。
    it('平板竖屏单栏、横屏分栏', 0, () => {
      expect(splitAt(632, 924)).assertFalse();
      expect(splitAt(924, 632)).assertTrue();
      expect(splitAt(880, 1400)).assertFalse();
      expect(splitAt(1400, 880)).assertTrue();
    });

    // Mate X 量级展开态约 720×800vp：竖着单栏，横过来 800×720 分栏；合上回单栏。
    it('折叠屏展开竖着单栏、横着分栏，合上单栏', 0, () => {
      expect(splitAt(720, 830)).assertFalse();
      expect(splitAt(830, 720)).assertTrue();
      expect(splitAt(700, 700)).assertFalse();
      expect(splitAt(380, 850)).assertFalse();
    });

    // 高度读不到时纵向断点给 lg，按纵向窗口判单栏（只影响 loadContent 之前的初值，
    // 回调里立刻被系统断点覆盖）。
    it('高度读不到时按纵向窗口单栏', 0, () => {
      expect(splitAt(1000, 0)).assertFalse();
      expect(splitAt(1000, Number.NaN)).assertFalse();
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
      expect(dockAt(830, 720, false)).assertEqual(DOCK_MODE_LEFT_FLOATING);
      expect(dockAt(720, 830, false)).assertEqual(DOCK_MODE_BOTTOM);
      expect(dockAt(700, 900, false)).assertEqual(DOCK_MODE_BOTTOM);
      expect(dockAt(1280, 800, true)).assertEqual(DOCK_MODE_BOTTOM);
      expect(dockAt(700, 900, true)).assertEqual(DOCK_MODE_BOTTOM);
      expect(dockAt(400, 860, false)).assertEqual(DOCK_MODE_BOTTOM);
      expect(dockAt(809, 376, false)).assertEqual(DOCK_MODE_BOTTOM);
      expect(dockAt(Number.NaN, 860, false)).assertEqual(DOCK_MODE_BOTTOM);
    });
  });
}
