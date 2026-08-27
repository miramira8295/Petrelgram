import { describe, it, expect } from '@ohos/hypium';
import {
  AppendAnchorInput, newerPageIsUserDriven, shouldHoldAppendAnchor,
  useUserDrivenAppendMark
} from '../main/ets/util/appendAnchor';

// 一次"用户手势翻出来的 newer 页正好落地"的输入；每个用例只翻一个开关，
// 每次都新建对象（不改上一份）。
function input(bypassed: boolean, didInitialScroll: boolean, prependAnchorHeld: boolean,
  appendBreaksAnchor: boolean, userDrivenAppend: boolean): AppendAnchorInput {
  const value: AppendAnchorInput = {
    bypassed: bypassed,
    didInitialScroll: didInitialScroll,
    prependAnchorHeld: prependAnchorHeld,
    appendBreaksAnchor: appendBreaksAnchor,
    userDrivenAppend: userDrivenAppend
  };
  return value;
}

export default function appendAnchorTest() {
  describe('appendAnchor', () => {
    // 用户手势打出来的那一页落地：把他手底下那一行按回原位，这正是 260e497
    // 要修的那个问题（stackFromEnd 下追加把可见内容顶走）。
    it('user_driven_page_holds_the_anchor', 0, () => {
      expect(shouldHoldAppendAnchor(input(false, true, false, true, true))).assertTrue();
    });

    // 程序性追加（首屏自动预取、短页补链、实时新消息）不复位：那是把视口
    // 按住的那条闭合回路的动力来源，且没有"用户手底下那一行"可言。
    it('automatic_append_does_not_hold_the_anchor', 0, () => {
      expect(shouldHoldAppendAnchor(input(false, true, false, true, false))).assertFalse();
    });

    // 这次发布没在末尾追加行（纯编辑 / 纯前插 / 只是分页状态变了）——无事可做。
    it('no_append_no_hold', 0, () => {
      expect(shouldHoldAppendAnchor(input(false, true, false, false, true))).assertFalse();
    });

    // 向上翻页的复位已经接管这次发布：一次发布只允许一个锚点。
    it('prepend_anchor_wins', 0, () => {
      expect(shouldHoldAppendAnchor(input(false, true, true, true, true))).assertFalse();
    });

    // 首次定位还没完成时列表位置归首屏逻辑所有，复位是抢方向盘。
    it('before_initial_scroll_never_holds', 0, () => {
      expect(shouldHoldAppendAnchor(input(false, false, false, true, true))).assertFalse();
    });

    // 快速回退开关：置真时整条旁路，其余输入一概不看。
    it('bypass_switch_disables_everything', 0, () => {
      expect(shouldHoldAppendAnchor(input(true, true, false, true, true))).assertFalse();
    });

    // 手指位移把膛压上去的那一枪算用户主动翻页。
    it('a_user_armed_shot_is_user_driven', 0, () => {
      expect(newerPageIsUserDriven(true)).assertTrue();
    });

    // 会话开局那一发是留给首屏自动补页的，首屏程序性定位把它打掉时没有任何
    // 用户手势参与——真机上正是它烧掉了闸，而且被误判成"用户翻出来的"。
    it('the_startup_shot_is_not_user_driven', 0, () => {
      expect(newerPageIsUserDriven(false)).assertFalse();
    });

    // ── 标记的一次性 ──────────────────────────────────────────────────
    // 用户驱动的那一页真的追加了行：这一次发布用得上标记。
    it('the_mark_applies_to_the_publication_that_appends', 0, () => {
      expect(useUserDrivenAppendMark(true, true)).assertTrue();
    });

    // 标记还在，但这次发布没在末尾追加行（纯编辑 / 分页状态变化 / 纯前插）。
    // 取走了但用不上——关键是取走本身是无条件的，标记不会留到下一次。
    it('the_mark_is_dropped_when_nothing_was_appended', 0, () => {
      expect(useUserDrivenAppendMark(true, false)).assertFalse();
    });

    // 没有标记的追加一律是程序性的：实时新消息、查看器换组、短页补链。
    // 真机上 hold 40 / skip 0 的那批就该落在这一支。
    it('an_append_without_a_mark_is_programmatic', 0, () => {
      expect(useUserDrivenAppendMark(false, true)).assertFalse();
    });

    // 跨页残留的形状：第一页置了标记却一行没追加（loadNewer 的过滤下是常态），
    // 第二次追加是实时新消息。取走无条件，所以第二次拿到的是"没有标记"。
    it('a_wasted_mark_cannot_leak_into_the_next_append', 0, () => {
      // 第 1 次发布：标记在手，但没有追加行 —— 取走、丢弃。
      expect(useUserDrivenAppendMark(true, false)).assertFalse();
      // 第 2 次发布：标记已经被上一次取走了，实时追加读到的是假。
      expect(useUserDrivenAppendMark(false, true)).assertFalse();
    });

    // 程序性追加拿不到标记 ⇒ 不复位锚点 ⇒ 不拽视口、不制造额外重测。
    it('a_programmatic_append_never_holds_the_anchor', 0, () => {
      const mark: boolean = useUserDrivenAppendMark(false, true);
      expect(shouldHoldAppendAnchor(input(false, true, false, true, mark))).assertFalse();
    });

    // 260e497 要保住的那一半：用户手势翻出来的那一页落地时仍然复位。
    it('a_user_driven_append_still_holds_the_anchor', 0, () => {
      const mark: boolean = useUserDrivenAppendMark(true, true);
      expect(shouldHoldAppendAnchor(input(false, true, false, true, mark))).assertTrue();
    });
  });
}
