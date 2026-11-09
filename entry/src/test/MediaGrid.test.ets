import { describe, expect, it } from '@ohos/hypium';
import {
  GLASS_BORDER_W,
  MEDIA_CARD_MARGIN,
  MEDIA_GRID_COLS,
  MEDIA_GRID_GAP,
  MEDIA_GRID_MIN_CELL,
  mediaCellSize,
  mediaFallbackContentWidth
} from '../main/ets/util/mediaGrid';

// 一行必须放得下 MEDIA_GRID_COLS 格。每格自带一条右外边距，所以占位是
// (格宽 + 间隙)。这是本模块唯一要守住的不变式——原来的 bug 正是它破了。
function rowFits(contentWidth: number): boolean {
  const cell: number = mediaCellSize(contentWidth);
  return MEDIA_GRID_COLS * (cell + MEDIA_GRID_GAP) <= contentWidth;
}

export default function mediaGridTest() {
  describe('mediaGrid', () => {
    // 真机上报的那一版：391vp 窗口，卡片 calc(100% - 24vp) + 0.7vp 描边。
    // 老写法 (screenW - 30) / 3 算出的三格合计正好 = screenW - 24，比内容区
    // 宽 1.4vp，第三格被挤到下一行 —— 每行只剩两格，右边空掉三分之一。
    it('three_cells_fit_on_the_reported_device', 0, () => {
      const content: number = mediaFallbackContentWidth(391);
      expect(rowFits(content)).assertTrue();
    });

    // 回归守卫：老写法在同一台设备上确实装不下，别再退回去。
    it('old_screen_width_math_overflowed', 0, () => {
      const content: number = mediaFallbackContentWidth(391);
      const legacyCell: number = (391 - 30) / MEDIA_GRID_COLS;
      expect(MEDIA_GRID_COLS * (legacyCell + MEDIA_GRID_GAP) > content).assertTrue();
    });

    // 各种窗口宽都得成立：手机、折叠屏展开、平板、分栏右栏。
    it('three_cells_fit_at_every_width', 0, () => {
      const widths: number[] = [320, 360, 391, 411, 480, 600, 720, 840, 1024, 1280];
      for (const w of widths) {
        expect(rowFits(mediaFallbackContentWidth(w))).assertTrue();
      }
    });

    // 实测宽（onAreaChange）走的是同一条路，同样要成立——包括带小数的。
    // 前提是容器装得下三个最小格（3 * (92 + 2) = 282vp），窄于此见下一条。
    it('three_cells_fit_for_measured_widths', 0, () => {
      const measured: number[] = [365.6, 366, 294.6, 512, 999.9];
      for (const w of measured) {
        expect(rowFits(w)).assertTrue();
      }
    });

    // 兜底宽必须把描边也减掉，否则首帧仍然按老的错宽排一次。
    it('fallback_subtracts_card_margin_and_border', 0, () => {
      const expected: number = 391 - MEDIA_CARD_MARGIN * 2 - GLASS_BORDER_W * 2;
      expect(mediaFallbackContentWidth(391)).assertEqual(expected);
    });

    // 量不到就退到最小格，不能算出 0 或负数把格子塌掉。
    it('unmeasured_width_falls_back_to_min_cell', 0, () => {
      expect(mediaCellSize(0)).assertEqual(MEDIA_GRID_MIN_CELL);
      expect(mediaCellSize(-5)).assertEqual(MEDIA_GRID_MIN_CELL);
    });

    // 窄到放不下三格时保底 —— 宁可横向挤一点，也不要塌成一条线。
    it('narrow_container_clamps_to_min_cell', 0, () => {
      expect(mediaCellSize(120)).assertEqual(MEDIA_GRID_MIN_CELL);
    });

    // 格宽取整，避免亚像素累加又把第三格顶下去。
    it('cell_size_is_a_whole_vp', 0, () => {
      const cell: number = mediaCellSize(mediaFallbackContentWidth(391));
      expect(cell === Math.floor(cell)).assertTrue();
    });
  });
}
