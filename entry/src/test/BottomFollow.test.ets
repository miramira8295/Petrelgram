import { describe, it, expect } from '@ohos/hypium';
import {
  BottomFollowFireInput, bottomFollowShouldApply, bottomFollowShouldSchedule
} from '../main/ets/util/bottomFollow';

function fire(over: Partial<BottomFollowFireInput>): BottomFollowFireInput {
  return {
    superseded: over.superseded ?? false,
    touchActive: over.touchActive ?? false,
    scrollActive: over.scrollActive ?? false,
    viewerOpen: over.viewerOpen ?? false,
    hasMoreNewer: over.hasMoreNewer ?? false
  };
}

export default function bottomFollowTest() {
  describe('bottomFollow', () => {
    // ── 点火 ──────────────────────────────────────────────────────────
    // 这就是真机上那次回归：追加把 atBottom 翻成了假，跟随不能因此放弃。
    // 所以点火判据里**根本没有 atBottom 这个入参**——它不该被问。
    it('applies_even_though_the_append_flipped_atBottom', 0, () => {
      expect(bottomFollowShouldApply(fire({}))).assertTrue();
    });

    it('yields_to_the_user_taking_over', 0, () => {
      expect(bottomFollowShouldApply(fire({ touchActive: true }))).assertFalse();
      expect(bottomFollowShouldApply(fire({ scrollActive: true }))).assertFalse();
    });

    it('yields_to_stronger_intents', 0, () => {
      expect(bottomFollowShouldApply(fire({ viewerOpen: true }))).assertFalse();
      expect(bottomFollowShouldApply(fire({ hasMoreNewer: true }))).assertFalse();
    });

    // 排期之后又排了更新的一次：旧的那次让路，由新的去贴。
    it('a_superseded_schedule_does_nothing', 0, () => {
      expect(bottomFollowShouldApply(fire({ superseded: true }))).assertFalse();
    });

    // ── 排期 ──────────────────────────────────────────────────────────
    it('schedules_when_at_bottom', 0, () => {
      expect(bottomFollowShouldSchedule(true, false, false)).assertTrue();
    });

    // 跟随在途时又来一条：这一刻 atBottom 是假的，是因为上一条还没贴过去，
    // 不是用户离开了底部。真机日志里 rows 31→42 那一串就是这么被漏掉的。
    it('schedules_while_a_follow_is_still_pending', 0, () => {
      expect(bottomFollowShouldSchedule(false, true, false)).assertTrue();
    });

    it('does_not_schedule_when_reading_history', 0, () => {
      expect(bottomFollowShouldSchedule(false, false, false)).assertFalse();
    });

    it('never_schedules_under_the_viewer', 0, () => {
      expect(bottomFollowShouldSchedule(true, true, true)).assertFalse();
    });
  });
}
