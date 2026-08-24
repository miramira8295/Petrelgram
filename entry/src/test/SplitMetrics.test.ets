import { describe, it, expect } from '@ohos/hypium';
import {
  splitNavMinWidth, splitNavMaxWidth, splitContentMinWidth,
  isSplitLayout, SPLIT_BREAKPOINT_VP
} from '../main/ets/util/splitMetrics';

// 分栏起作用的最窄窗口（NavigationMode.Auto 的断点）。
const SPLIT_MIN_W: number = 600;
// HdsNavigation 内部的默认 navBar 宽度。它被 navBarWidthRange 一夹，落在哪里
// 就是用户不拖分割线时看到的静息宽度。
const HDS_DEFAULT_NAV_W: number = 240;

// 静息宽度 = 内部默认值被区间夹一次的结果。
function restingWidth(w: number): number {
  const min: number = splitNavMinWidth(w);
  const max: number = splitNavMaxWidth(w);
  return Math.min(Math.max(HDS_DEFAULT_NAV_W, min), max);
}

export default function splitMetricsTest(): void {
  describe('splitMetrics', (): void => {

    // 约束 1：官方大屏 UX 标准 3.2.2.4——navBar 不超过窗口宽的 40%。
    it('左栏上限不越窗口宽的 40%', 0, (): void => {
      const widths: number[] = [600, 667, 720, 800, 900, 1137, 1440, 2560];
      for (let i = 0; i < widths.length; i++) {
        const w: number = widths[i];
        expect(splitNavMaxWidth(w) <= Math.ceil(w * 0.4)).assertTrue();
      }
    });

    // 约束 2：maxWidth + minContentWidth 必须放得下，否则两个约束互相打架，
    // HdsNavigation 怎么裁决没有文档。这是本次修的第二个问题。
    it('左栏上限加右栏下限永远不超过窗口宽', 0, (): void => {
      for (let w = SPLIT_MIN_W; w <= 2560; w += 1) {
        expect(splitNavMaxWidth(w) + splitContentMinWidth(w) <= w).assertTrue();
      }
    });

    // 约束 3：enableDragBar(true) 必须真拖得动。这是本次修的第一个问题：
    // 老取值在 600–800vp 上 minWidth === maxWidth，把手画得出、拖不动。
    it('分栏区间内始终有可拖行程', 0, (): void => {
      for (let w = SPLIT_MIN_W; w <= 2560; w += 1) {
        expect(splitNavMaxWidth(w) - splitNavMinWidth(w) >= 40).assertTrue();
      }
    });

    it('区间合法：minWidth 不大于 maxWidth（含不分栏的手机宽度）', 0, (): void => {
      for (let w = 240; w <= 2560; w += 1) {
        expect(splitNavMinWidth(w) <= splitNavMaxWidth(w)).assertTrue();
      }
    });

    // 四个断点的验算。600 是分栏临界点，667 是右栏能拿满 400 的最窄窗口，
    // 720/800 是折叠屏内屏与平板分屏的常见值。
    it('W=600（分栏临界点）', 0, (): void => {
      expect(splitNavMinWidth(600)).assertEqual(200);
      expect(splitNavMaxWidth(600)).assertEqual(240);
      expect(splitContentMinWidth(600)).assertEqual(360);
      // 静息 240 = 正好 40%，右栏 360。
      expect(restingWidth(600)).assertEqual(240);
    });

    it('W=667（右栏刚好够 400 的最窄窗口）', 0, (): void => {
      expect(splitNavMinWidth(667)).assertEqual(226);
      expect(splitNavMaxWidth(667)).assertEqual(266);
      expect(splitContentMinWidth(667)).assertEqual(400);
      expect(restingWidth(667)).assertEqual(240);
    });

    it('W=720', 0, (): void => {
      expect(splitNavMinWidth(720)).assertEqual(248);
      expect(splitNavMaxWidth(720)).assertEqual(288);
      expect(splitContentMinWidth(720)).assertEqual(400);
      expect(restingWidth(720)).assertEqual(248);
    });

    it('W=800', 0, (): void => {
      expect(splitNavMinWidth(800)).assertEqual(280);
      expect(splitNavMaxWidth(800)).assertEqual(320);
      expect(splitContentMinWidth(800)).assertEqual(400);
      expect(restingWidth(800)).assertEqual(280);
    });

    // 平板不许退化：Task 8 在 1137vp 真机上确认的是左栏 33%，静息宽度 379。
    // 新取值必须一模一样地落回 379。
    it('W=1137（平板真机）静息宽度仍是 379，占 33%', 0, (): void => {
      expect(restingWidth(1137)).assertEqual(379);
      expect(splitContentMinWidth(1137)).assertEqual(400);
    });

    it('超宽屏被 480/560 兜住，不会一路拉白边', 0, (): void => {
      expect(restingWidth(2560)).assertEqual(480);
      expect(splitNavMaxWidth(2560)).assertEqual(560);
    });

    // isSplitLayout 是 ContactsPage 决定「点联系人开会话还是开资料页」的那条线。
    // 它必须与本文件里那三个宽度函数的输入前提（≥600 才分栏）用同一个数，否则
    // 会出现「组件已经分栏、代码还以为是手机」的半拉状态。
    it('分栏断点就是 600，边界含等号', 0, (): void => {
      expect(SPLIT_BREAKPOINT_VP).assertEqual(SPLIT_MIN_W);
      // 高度一律给一个平板量级的值，先只考察宽度这条边。
      expect(isSplitLayout(599, 900)).assertFalse();
      expect(isSplitLayout(600, 900)).assertTrue();
      expect(isSplitLayout(601, 900)).assertTrue();
      // 手机竖屏 / 平板真机两个常见值，各站一边。
      expect(isSplitLayout(360, 780)).assertFalse();
      expect(isSplitLayout(1137, 800)).assertTrue();
    });

    // **这条钉的是 issue #125。** 只看宽度的旧版本把「手机横过来」判成平板：
    // 点视频全屏会把窗口转成横屏，宽度一下越过 600，整个应用进分栏。
    it('手机横屏不分栏——短边没过线', 0, (): void => {
      // Mate70 Pro+ 实测量级：竖屏 376×809，横屏 809×376。
      expect(isSplitLayout(376, 809)).assertFalse();
      expect(isSplitLayout(809, 376)).assertFalse();
      // 高度正好卡在断点上，含等号。
      expect(isSplitLayout(800, 599)).assertFalse();
      expect(isSplitLayout(800, 600)).assertTrue();
    });

    it('平板横竖屏都分栏', 0, (): void => {
      // Pad 量级：632×924 与 924×632，两条边都过线，转屏不改变结论。
      expect(isSplitLayout(632, 924)).assertTrue();
      expect(isSplitLayout(924, 632)).assertTrue();
    });

    it('折叠屏展开进分栏、合上回单栏', 0, (): void => {
      // 不需要判机型：短边判据天然覆盖折叠屏的两种姿势。
      expect(isSplitLayout(720, 830)).assertTrue();
      expect(isSplitLayout(380, 850)).assertFalse();
    });

    it('高度读不到时退回只看宽度', 0, (): void => {
      // 冷启动早期 windowSizeChange 还没填过 AppStorage。此时按宽度判断，
      // 至少不会比一律拒绝分栏更差。
      expect(isSplitLayout(1000, 0)).assertTrue();
      expect(isSplitLayout(1000, Number.NaN)).assertTrue();
      expect(isSplitLayout(400, 0)).assertFalse();
    });
  });
}
