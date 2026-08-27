import { describe, it, expect } from '@ohos/hypium';
import {
  AppendAnchorInput, newerPageIsUserDriven, shouldHoldAppendAnchor
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

    // 手指按在列表上时发出的请求算用户主动翻页。
    it('touch_active_request_is_user_driven', 0, () => {
      expect(newerPageIsUserDriven(true, false)).assertTrue();
    });

    // 手指已经离开但惯性滑动还在走，同样算——一次轻扫打出的页往往在抬手之后
    // 才回来，只认 touch 会把它误判成程序性追加。
    it('inertial_scroll_request_is_user_driven', 0, () => {
      expect(newerPageIsUserDriven(false, true)).assertTrue();
    });

    // 列表静止时发出的请求（首屏布局后的自动预取）不是用户打的。
    it('idle_list_request_is_not_user_driven', 0, () => {
      expect(newerPageIsUserDriven(false, false)).assertFalse();
    });
  });
}
