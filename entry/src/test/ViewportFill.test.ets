import { describe, it, expect } from '@ohos/hypium';
import { ViewportFillInput, shouldFillViewport } from '../main/ets/util/viewportFill';

const MAX_ROWS: number = 80;

function input(hasMoreOlder: boolean, rows: number, startIdx: number, endIdx: number,
  indexRows: number): ViewportFillInput {
  const value: ViewportFillInput = {
    hasMoreOlder: hasMoreOlder,
    rows: rows,
    maxRows: MAX_ROWS,
    startIdx: startIdx,
    endIdx: endIdx,
    indexRows: indexRows
  };
  return value;
}

export default function viewportFillTest() {
  describe('viewportFill', () => {
    // ── 原始需求：消息太少，列表根本滚不动 ──────────────────────────────
    // 首行末行同时可见 ⇒ 整份数据都在屏幕上 ⇒ onReachStart / start<=4 永远不来，
    // 必须自己敲门。这是"999+ 却滑不动"和平板铺不满一屏那个 bug 的修法，不能丢。
    it('content_shorter_than_the_viewport_still_asks_for_a_page', 0, () => {
      expect(shouldFillViewport(input(true, 6, 0, 5, 6))).assertTrue();
    });

    it('a_single_row_window_still_asks_for_a_page', 0, () => {
      expect(shouldFillViewport(input(true, 1, 0, 0, 1))).assertTrue();
    });

    // ── 缺陷：stackFromEnd 下"最后一行可见"恒成立 ──────────────────────
    // 真机形态：带未读进会话，around 给了 14 行，一屏 8–9 行，锚点在中间。
    // 末行可见（列表底部锚定），但首行**不**可见——列表是滚得动的，不该补页。
    // 第一版在这里成立，于是每发布一次就往上追加一页，一路到 80 行封顶；用户
    // 正想往下滑，配合 maintainVisibleContentPosition 就被钉住了。
    it('sitting_at_the_bottom_of_a_scrollable_list_does_not_fill', 0, () => {
      expect(shouldFillViewport(input(true, 14, 8, 13, 14))).assertFalse();
    });

    // 那条链的后几步：补到 44 行、74 行，末行照样可见，第一版会一路补到封顶。
    it('the_old_chain_is_broken_at_every_step', 0, () => {
      expect(shouldFillViewport(input(true, 44, 38, 43, 44))).assertFalse();
      expect(shouldFillViewport(input(true, 74, 68, 73, 74))).assertFalse();
    });

    // 首行可见但末行不可见（用户滑到了顶）：也不是"整份数据都在屏幕上"。
    // 向上分页那时该由 onReachStart / start<=4 驱动，不归这里管。
    it('sitting_at_the_top_of_a_scrollable_list_does_not_fill', 0, () => {
      expect(shouldFillViewport(input(true, 14, 0, 8, 14))).assertFalse();
    });

    // ── 各条防呆 ────────────────────────────────────────────────────────
    it('no_older_history_means_nothing_to_do', 0, () => {
      expect(shouldFillViewport(input(false, 6, 0, 5, 6))).assertFalse();
    });

    it('an_empty_window_never_fills', 0, () => {
      expect(shouldFillViewport(input(true, 0, 0, 0, 0))).assertFalse();
    });

    // 封顶：补页不能无限进行。
    it('the_row_cap_stops_filling', 0, () => {
      expect(shouldFillViewport(input(true, MAX_ROWS, 0, MAX_ROWS - 1, MAX_ROWS))).assertFalse();
      expect(shouldFillViewport(input(true, MAX_ROWS - 1, 0, MAX_ROWS - 2, MAX_ROWS - 1)))
        .assertTrue();
    });

    // 首帧之前行号是 -1：还不知道能看见多少，不下结论。
    it('unknown_indices_never_fill', 0, () => {
      expect(shouldFillViewport(input(true, 6, -1, -1, 6))).assertFalse();
      expect(shouldFillViewport(input(true, 6, 0, -1, 6))).assertFalse();
    });

    // 行号属于上一份数据（applyMessages 里数据已经换了新快照，而 indexGroupsLen
    // 要等下一次 onScrollIndex 才更新）。错位的下标不能拿来做决定。
    it('stale_indices_are_refused', 0, () => {
      // 14 行的窗口刚补成 44 行，行号还停在 14 行那一批。
      expect(shouldFillViewport(input(true, 44, 0, 13, 14))).assertFalse();
    });

    // 末行下标比 rows-1 还大（布局抖动报了越界行号）仍按"末行可见"算。
    it('an_overshooting_end_index_still_counts_as_the_last_row', 0, () => {
      expect(shouldFillViewport(input(true, 6, 0, 6, 6))).assertTrue();
    });
  });
}
