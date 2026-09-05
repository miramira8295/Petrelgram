import { describe, expect, it } from '@ohos/hypium';
import {
  INITIAL_BOTTOM_PRESENT_MIN_MS, INITIAL_MESSAGE_RELEASE_DELAY_MS,
  INITIAL_MESSAGE_TRANSITION_SETTLE_MS, INITIAL_TIMELINE_PRESENT_MIN_MS,
  INITIAL_TIMELINE_REVEAL_ROW_LIMIT, INITIAL_TIMELINE_ROW_FADE_MS,
  INITIAL_TIMELINE_ROW_STAGGER_MS, JUMP_RELOAD_THRESHOLD, MENU_DISMISS_MS,
  REUSE_CAP_MIN_INTERVAL_MS, SEARCH_ENTRY_DELAY_MS
} from '../main/ets/util/chatPageTuning';

// 这些常量在 B1 之前住在 ChatPage.ets 顶部（279–343 行），谁都能顺手改一个数字而不
// 触发任何失败。搬进 util/chatPageTuning.ets 之后补这组断言：钉住的不是"值等于多少"，
// 而是"这个值是从哪条真机观测/哪帧算出来的"，以及首屏分级揭示那几个时长之间必须
// 成立的相对关系——单看一个数字改坏了看不出来，凑在一起才看得出来。

// 真机标定的 90 Hz 一帧 ≈ 11.1 ms（注释里 INITIAL_MESSAGE_RELEASE_DELAY_MS 的依据）。
const FRAME_MS_90HZ: number = 1000 / 90;

export default function chatPageTuningTest() {
  describe('chatPageTuning', () => {
    // 防的回归：有人为了"回底更快"把回底 FAB 的重载阈值调小/调大。40 组是
    // "逐行滚过去" 与 "干脆重载最新一页" 的分界，改动它会让回底要么卡顿要么丢历史。
    it('回底重载阈值仍是 40 组：小于它逐行滚、大于它重载最新页', 0, (): void => {
      expect(JUMP_RELOAD_THRESHOLD).assertEqual(40);
    });

    // 防的回归：把"从全局搜索进会话后再跑会话内搜索"的宽限期删掉或缩到 0，
    // 会让会话内搜索在首屏还没落定时开跑。
    it('全局搜索进会话的宽限期仍是 400ms，不能缩成立即执行', 0, (): void => {
      expect(SEARCH_ENTRY_DELAY_MS).assertEqual(400);
      expect(SEARCH_ENTRY_DELAY_MS > 0).assertTrue();
    });

    // 防的回归：菜单是独立子窗口，收起过程中弹出的对话框会挂死（Promise 既不
    // resolve 也不 reject）。这 150ms 是"等菜单收起"的等待，改成 0 就是复现挂死。
    it('等上下文菜单收起仍留 150ms，改成 0 会让确认框挂死', 0, (): void => {
      expect(MENU_DISMISS_MS).assertEqual(150);
      expect(MENU_DISMISS_MS > 0).assertTrue();
    });

    // 防的回归：把封顶间隔改成 0 或几十毫秒，等于在连续 fling 的每次停手上都给
    // maxCount 赋一次值，每次赋值都会让框架做一次异步清理。
    it('复用池封顶最小间隔够长，不会在每次 fling 停手上都重跑', 0, (): void => {
      expect(REUSE_CAP_MIN_INTERVAL_MS).assertEqual(1000);
    });

    // 防的回归：把放行延迟改到一帧以内（例如 8ms 或 0），延迟帧回调会在同一个
    // VSync 内被再次抽干，上一次放行的那一行来不及完成布局——首屏又回到"一次涌进"。
    it('每行放行延迟必须跨过 90Hz 的一帧边界，否则同一 VSync 内会被再抽干', 0, (): void => {
      expect(INITIAL_MESSAGE_RELEASE_DELAY_MS > FRAME_MS_90HZ).assertTrue();
      expect(INITIAL_MESSAGE_RELEASE_DELAY_MS < FRAME_MS_90HZ * 2).assertTrue();
    });

    // 防的回归：把两个下限调成一样（或把底部的调得更长）。落到底部时下半屏已经稳定，
    // 它要的地板本来就比"未读锚点要备齐整个可见窗口"短，否则回底会白等一拍。
    it('底部落点的呈现下限严格短于未读锚点的呈现下限', 0, (): void => {
      expect(INITIAL_BOTTOM_PRESENT_MIN_MS < INITIAL_TIMELINE_PRESENT_MIN_MS).assertTrue();
      expect(INITIAL_BOTTOM_PRESENT_MIN_MS > 0).assertTrue();
    });

    // 防的回归：把 stagger 调到 ≥ fade。分级揭示要读成"一道波扫过去"，靠的是
    // 相邻两行的淡入有重叠；stagger 一旦追上 fade，就变成一行闪完再闪下一行。
    it('相邻两行的错峰必须短于单行淡入，揭示才是一道波而不是逐行闪', 0, (): void => {
      expect(INITIAL_TIMELINE_ROW_STAGGER_MS < INITIAL_TIMELINE_ROW_FADE_MS).assertTrue();
      expect(INITIAL_TIMELINE_ROW_STAGGER_MS > 0).assertTrue();
    });

    // 防的回归：调大放行行数上限或拉长 stagger/fade，直到整段揭示拖过页面切换围栏
    // （INITIAL_MESSAGE_TRANSITION_SETTLE_MS 同时是空时间线看门狗）。那样用户会先
    // 看见页面停住，再看见消息慢慢亮起来。
    it('整段分级揭示必须在页面切换围栏内跑完', 0, (): void => {
      const revealSpanMs: number = (INITIAL_TIMELINE_REVEAL_ROW_LIMIT - 1)
        * INITIAL_TIMELINE_ROW_STAGGER_MS + INITIAL_TIMELINE_ROW_FADE_MS;
      expect(revealSpanMs < INITIAL_MESSAGE_TRANSITION_SETTLE_MS).assertTrue();
      // 首屏呈现下限之后才开始揭示，两段加起来也不能顶到围栏。
      expect(INITIAL_TIMELINE_PRESENT_MIN_MS + revealSpanMs
        < INITIAL_MESSAGE_TRANSITION_SETTLE_MS).assertTrue();
    });

    // 防的回归：把参与揭示的行数上限设成 0（整屏没有淡入，等于关掉分级揭示）
    // 或设成很大的值（离屏行也排队，最后一行的 stagger 会拖到肉眼可见）。
    it('参与揭示的行数上限覆盖可见窗口且不外溢到离屏行', 0, (): void => {
      expect(INITIAL_TIMELINE_REVEAL_ROW_LIMIT > 0).assertTrue();
      expect(INITIAL_TIMELINE_REVEAL_ROW_LIMIT <= 16).assertTrue();
    });
  });
}
