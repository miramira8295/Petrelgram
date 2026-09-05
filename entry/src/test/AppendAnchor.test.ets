import { describe, it, expect } from '@ohos/hypium';
import {
  APPEND_ANCHOR_RESTORE_BYPASSED, AppendAnchorInput, newerPageIsUserDriven,
  shouldHoldAppendAnchor, useUserDrivenAppendMark
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
    // 真机：around-unread 的媒体窗口在顶部锚定下从 15 行追加到 19 行，Repeat 仍
    // 重排了整个窗口。用户位移现在由 anchorYAfterUserScroll 单独保留，所以这条
    // 保护不再反向抵消手势。
    it('top_anchored_media_append_still_holds', 0, () => {
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
    // 止血开关默认必须是关的：它被改成 true 意味着向下翻页的锚点复位被整条旁路，
    // 只应在排查时临时开启。上面所有 bypassed=false 的断言都建立在这个默认值上——
    // 真机上一旦被留成 true，往下翻页时可见内容会被追加的新页顶走，而单测全绿。
    it('止血开关默认关闭：留成 true 等于整条旁路向下翻页的锚点复位', 0, (): void => {
      expect(APPEND_ANCHOR_RESTORE_BYPASSED).assertFalse();
    });
  });
}
