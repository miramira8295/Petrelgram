import { describe, it, expect } from '@ohos/hypium';
import {
  AppendAnchorInput, newerPageIsUserDriven, shouldHoldAppendAnchor,
  useUserDrivenAppendMark
} from '../main/ets/util/appendAnchor';

function input(bypassed: boolean, didInitialScroll: boolean, prependAnchorHeld: boolean,
  appendBreaksAnchor: boolean, atLiveTail: boolean = false,
  scrollIntentPending: boolean = false): AppendAnchorInput {
  const value: AppendAnchorInput = {
    bypassed: bypassed,
    didInitialScroll: didInitialScroll,
    prependAnchorHeld: prependAnchorHeld,
    appendBreaksAnchor: appendBreaksAnchor,
    atLiveTail: atLiveTail,
    scrollIntentPending: scrollIntentPending
  };
  return value;
}

export default function appendAnchorTest() {
  describe('appendAnchor', () => {
    // 真机：往下拉新消息时进度条经常到底，看历史却顺滑——自动填充的页以前不补锚点。
    it('any_append_mid_history_holds_the_anchor', 0, () => {
      expect(shouldHoldAppendAnchor(input(false, true, false, true))).assertTrue();
    });
    it('at_the_live_tail_new_messages_are_followed_not_held', 0, () => {
      expect(shouldHoldAppendAnchor(input(false, true, false, true, true))).assertFalse();
    });
    it('a_pending_jump_or_scroll_to_bottom_wins_over_the_hold', 0, () => {
      expect(shouldHoldAppendAnchor(input(false, true, false, true, false, true))).assertFalse();
    });
    it('no_append_no_hold', 0, () => {
      expect(shouldHoldAppendAnchor(input(false, true, false, false))).assertFalse();
    });
    it('prepend_anchor_wins', 0, () => {
      expect(shouldHoldAppendAnchor(input(false, true, true, true))).assertFalse();
    });
    it('before_initial_scroll_never_holds', 0, () => {
      expect(shouldHoldAppendAnchor(input(false, false, false, true))).assertFalse();
    });
    it('bypass_switch_disables_everything', 0, () => {
      expect(shouldHoldAppendAnchor(input(true, true, false, true))).assertFalse();
    });
    // 「这一枪是谁扣的」只剩诊断价值，不再决定补不补。
    it('a_user_armed_shot_is_user_driven', 0, () => {
      expect(newerPageIsUserDriven(true)).assertTrue();
      expect(newerPageIsUserDriven(false)).assertFalse();
    });
    it('the_mark_applies_only_to_the_publication_that_appends', 0, () => {
      expect(useUserDrivenAppendMark(true, true)).assertTrue();
      expect(useUserDrivenAppendMark(true, false)).assertFalse();
      expect(useUserDrivenAppendMark(false, true)).assertFalse();
    });
    it('who_pulled_the_trigger_no_longer_decides_the_hold', 0, () => {
      expect(useUserDrivenAppendMark(false, true)).assertFalse();
      expect(shouldHoldAppendAnchor(input(false, true, false, true))).assertTrue();
    });
  });
}
