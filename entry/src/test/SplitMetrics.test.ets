import { describe, it, expect } from '@ohos/hypium';
import {
  splitNavMinWidth, splitNavMaxWidth, splitContentMinWidth
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
  });
}
