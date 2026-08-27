import { describe, expect, it } from '@ohos/hypium';
import { stackFromEndWanted } from '../main/ets/util/stackFromEnd';

export default function stackFromEndTest() {
  describe('stackFromEnd', () => {
    // 往下翻历史时不能底部锚定：追加会把视口拽到新的末尾。
    it('paging_newer_uses_top_anchoring', 0, () => {
      expect(stackFromEndWanted(true)).assertFalse();
    });
    it('at_the_live_tail_uses_bottom_anchoring', 0, () => {
      expect(stackFromEndWanted(false)).assertTrue();
    });
  });
}
