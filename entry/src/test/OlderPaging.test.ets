import { describe, it, expect } from '@ohos/hypium';
import { OLDER_TRIGGER_ROWS, olderTriggerHit } from '../main/ets/util/olderPaging';

export default function olderPagingTest() {
  describe('olderPaging', () => {
    // 触发线要够早：一次上滑一秒能走好几屏，4 行（≈230vp）的余量在页落地前就用完了。
    it('trigger_line_is_about_a_screen', 0, () => {
      expect(OLDER_TRIGGER_ROWS >= 10).assertTrue();
    });

    it('hits_inside_the_zone_only', 0, () => {
      expect(olderTriggerHit(0, OLDER_TRIGGER_ROWS)).assertTrue();
      expect(olderTriggerHit(OLDER_TRIGGER_ROWS, OLDER_TRIGGER_ROWS)).assertTrue();
      expect(olderTriggerHit(OLDER_TRIGGER_ROWS + 1, OLDER_TRIGGER_ROWS)).assertFalse();
    });

    // onScrollIndex 在首帧之前可能上报 -1，那不是"到顶了"。
    it('an_unknown_start_index_does_not_fire', 0, () => {
      expect(olderTriggerHit(-1, OLDER_TRIGGER_ROWS)).assertFalse();
    });
  });
}
