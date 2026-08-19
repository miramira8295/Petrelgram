import { describe, expect, it } from '@ohos/hypium';
import {
  PINNED_SEG_MAX, pinnedActiveSeg, pinnedDisplayActive, pinnedSegCount,
  pinnedSegIndices, pinnedSegStart, pinnedShownIndex
} from '../main/ets/util/pinnedSegments';

// 置顶条左侧进度格的滑动窗口。
export default function pinnedSegmentsTest() {
  describe('pinnedSegments', () => {
    it('没有置顶时不画格子', 0, () => {
      expect(pinnedSegCount(0)).assertEqual(0);
      expect(pinnedSegIndices(0).length).assertEqual(0);
      // count 为 0 时不该算出负下标。
      expect(pinnedShownIndex(0, 0)).assertEqual(0);
      expect(pinnedDisplayActive(0, 0)).assertEqual(0);
    });

    it('只有一条时一格，且高亮它', 0, () => {
      expect(pinnedSegCount(1)).assertEqual(1);
      expect(pinnedActiveSeg(0, 1)).assertEqual(0);
    });

    it('格子数封顶在 5', 0, () => {
      expect(pinnedSegCount(4)).assertEqual(4);
      expect(pinnedSegCount(5)).assertEqual(PINNED_SEG_MAX);
      expect(pinnedSegCount(40)).assertEqual(PINNED_SEG_MAX);
      expect(pinnedSegIndices(40).length).assertEqual(PINNED_SEG_MAX);
    });

    it('显示顺序是从旧到新：cycle=0 是最新，落在最后一格', 0, () => {
      // 3 条置顶，窗口装得下，不滑动。
      expect(pinnedSegStart(0, 3)).assertEqual(0);
      expect(pinnedActiveSeg(0, 3)).assertEqual(2);
      expect(pinnedActiveSeg(1, 3)).assertEqual(1);
      expect(pinnedActiveSeg(2, 3)).assertEqual(0);
    });

    it('恰好等于窗口宽度时仍不滑动', 0, () => {
      expect(pinnedSegStart(0, 5)).assertEqual(0);
      expect(pinnedActiveSeg(0, 5)).assertEqual(4);
      expect(pinnedActiveSeg(4, 5)).assertEqual(0);
    });

    it('超过窗口时滑动，且两端都夹住', 0, () => {
      // 10 条：cycle=0（最新）在末尾，窗口右贴边。
      expect(pinnedSegStart(0, 10)).assertEqual(5);
      expect(pinnedActiveSeg(0, 10)).assertEqual(4);
      // 往回翻到最旧一条：窗口左贴边，高亮第一格。
      expect(pinnedSegStart(9, 10)).assertEqual(0);
      expect(pinnedActiveSeg(9, 10)).assertEqual(0);
      // 中间：高亮始终落在窗口末格，直到左端顶住为止。
      expect(pinnedSegStart(3, 10)).assertEqual(2);
      expect(pinnedActiveSeg(3, 10)).assertEqual(4);
    });

    it('高亮格永远落在窗口内', 0, () => {
      for (let count = 1; count <= 12; count++) {
        for (let cycle = 0; cycle < count + 3; cycle++) {
          const seg: number = pinnedActiveSeg(cycle, count);
          expect(seg >= 0).assertTrue();
          expect(seg < pinnedSegCount(count)).assertTrue();
        }
      }
    });

    it('取消置顶后 cycle 越界，夹回最旧一条而不是算出负数', 0, () => {
      // 原本 8 条、翻到第 7 条，用户取消置顶后只剩 3 条：cycle 还停在 7。
      expect(pinnedShownIndex(7, 3)).assertEqual(2);
      expect(pinnedActiveSeg(7, 3)).assertEqual(0);
      expect(pinnedSegStart(7, 3)).assertEqual(0);
    });
  });
}
