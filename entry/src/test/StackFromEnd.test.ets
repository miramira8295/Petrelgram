import { describe, expect, it } from '@ohos/hypium';
import { stackFromEndWanted } from '../main/ets/util/stackFromEnd';

export default function stackFromEndTest() {
  describe('stackFromEnd', () => {
    // 往下翻历史时不能底部锚定：追加会把视口拽到新的末尾。
    it('paging_newer_uses_top_anchoring', 0, () => {
      expect(stackFromEndWanted(true, 0, 4, 5)).assertFalse();
    });

    it('before_first_layout_starts_from_the_end', 0, () => {
      expect(stackFromEndWanted(false, -1, -1, -1)).assertTrue();
    });

    it('short_timeline_keeps_bottom_alignment', 0, () => {
      expect(stackFromEndWanted(false, 0, 4, 5)).assertTrue();
    });

    it('scrollable_timeline_at_live_tail_does_not_anchor_from_end', 0, () => {
      expect(stackFromEndWanted(false, 80, 99, 100)).assertFalse();
    });

    it('scrollable_timeline_near_live_tail_does_not_anchor_from_end', 0, () => {
      expect(stackFromEndWanted(false, 76, 95, 100)).assertFalse();
    });

    it('tail_append_uses_previous_scrollable_layout_evidence', 0, () => {
      // 数据已经变成 102 行，但 indexGroupsLen 仍描述追加前的 100 行。只要旧布局
      // 不是整份同时可见，就必须在这次追加布局前关掉 stackFromEnd。
      expect(stackFromEndWanted(false, 80, 99, 100)).assertFalse();
    });

    // issue #162：评论/话题页顶部对齐——帖子在最上、评论往下长（Telegram 亦然），
    // 整窗可见时也不从底部堆。普通会话行为不变。
    it('thread pages never stack from end, even when the whole window is visible', 0, (): void => {
      expect(stackFromEndWanted(false, 0, 1, 2, true)).assertFalse();
      expect(stackFromEndWanted(false, -1, -1, 0, true)).assertFalse();
      expect(stackFromEndWanted(false, 0, 1, 2, false)).assertTrue();
      expect(stackFromEndWanted(false, 0, 1, 2)).assertTrue();
    });
  });
}
