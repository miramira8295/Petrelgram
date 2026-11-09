import { describe, it, expect } from '@ohos/hypium';
import {
  MESSAGE_ID_STEP, NEWER_TAIL_DOUBT_LIMIT, NewerPageOutcome, NewerTailVerdict,
  decideNewerTail, liveArrivalContiguous, liveArrivalStep, reachedLiveTail
} from '../main/ets/util/liveTail';

// 真机日志（2026-08-27）里的两个真实 id，读起来比造的数好对照。
const WINDOW_LAST: number = 11488198656;
const CHAT_LAST: number = 11494490112;

function outcome(serverCount: number, mergedCount: number, windowNewestId: number,
  chatLastMessageId: number, emptyStreak: number): NewerPageOutcome {
  const value: NewerPageOutcome = {
    serverCount: serverCount,
    mergedCount: mergedCount,
    windowNewestId: windowNewestId,
    chatLastMessageId: chatLastMessageId,
    emptyStreak: emptyStreak
  };
  return value;
}

export default function liveTailTest() {
  describe('liveTail', () => {
    // 窗口最新一条就是会话最后一条：确定到底了，分页该关。
    it('window_newest_equals_chat_last_is_tail', 0, () => {
      expect(reachedLiveTail(11472555999232, 11472555999232)).assertTrue();
    });

    // 窗口比会话记录的还新：新消息先进了窗口、updateChatLastMessage 慢一拍。
    // 这同样是尾部——用 >= 而不是 ===，否则这半拍里判定会翻回"没到底"。
    it('window_newer_than_chat_last_is_tail', 0, () => {
      expect(reachedLiveTail(11472556000000, 11472555999232)).assertTrue();
    });

    // 窗口还落在后面：确实有更新的没加载，分页必须继续。
    it('window_older_than_chat_last_is_not_tail', 0, () => {
      expect(reachedLiveTail(11472273932288, 11472555999232)).assertFalse();
    });

    // **不知道会话最后一条是哪条时不能下结论**。返回 false 让分页照常走——
    // 误判成"到底了"会把 hasMoreNewer 关掉，用户就再也翻不到更新的消息，
    // 比多翻几页严重得多。
    it('unknown_chat_last_is_not_conclusive', 0, () => {
      expect(reachedLiveTail(11472555999232, 0)).assertFalse();
    });

    // 空窗口同理，没有判据。
    it('empty_window_is_not_conclusive', 0, () => {
      expect(reachedLiveTail(0, 11472555999232)).assertFalse();
      expect(reachedLiveTail(0, 0)).assertFalse();
    });

    // 负数是脏数据，不能当成"到底了"。
    it('negative_input_is_not_tail', 0, () => {
      expect(reachedLiveTail(-1, 11472555999232)).assertFalse();
      expect(reachedLiveTail(11472555999232, -1)).assertFalse();
    });
    // issue #62：报告人日志里 windowNewest=3182428160、到达 id=3183476736，差正好 2^20。
    it('实时消息紧接窗口尾巴一步，算连续', 0, (): void => {
      expect(liveArrivalStep(3182428160, 3183476736)).assertEqual(1);
      expect(liveArrivalContiguous(3182428160, 3183476736, 5)).assertTrue();
    });
    it('容差内的几步也算连续（被删消息/服务消息让 id 跳格）', 0, (): void => {
      expect(liveArrivalContiguous(3182428160, 3182428160 + 5 * MESSAGE_ID_STEP, 5)).assertTrue();
      expect(liveArrivalContiguous(3182428160, 3182428160 + 6 * MESSAGE_ID_STEP, 5)).assertFalse();
    });
    it('没有窗口、或不比尾巴新，都不算', 0, (): void => {
      expect(liveArrivalStep(0, 3183476736)).assertEqual(0);
      expect(liveArrivalStep(3183476736, 3183476736)).assertEqual(0);
      expect(liveArrivalStep(3183476736, 3182428160)).assertEqual(0);
      expect(liveArrivalContiguous(0, 3183476736, 5)).assertFalse();
    });

    // ── decideNewerTail ────────────────────────────────────────────────
    //
    // 【服务端返回 0 条】
    // chatLast 已知且窗口还落后于它：会话里明确还有更新的消息，这次只是没拿到
    // （getChatHistory 带负 offset 常常只吃本地库）。绝不能关闸——这就是真机上
    // 谎报到底的那一格。
    it('empty_page_while_behind_chat_last_keeps_paging_open', 0, () => {
      const v: NewerTailVerdict = decideNewerTail(outcome(0, 0, WINDOW_LAST, CHAT_LAST, 1));
      expect(v.hasMoreNewer).assertTrue();
      expect(v.state).assertEqual('idle');
      expect(v.reason).assertEqual('empty-page-behind-chat-last');
    });

    // 【返回 N 条但过滤后 0 条】整页都是窗口已有的重复条目，或与窗口不连续。
    // 「这次没拿到」不等于「没有了」——旧逻辑正是在这里置的 end。
    it('filtered_empty_page_while_behind_chat_last_keeps_paging_open', 0, () => {
      const v: NewerTailVerdict = decideNewerTail(outcome(30, 0, WINDOW_LAST, CHAT_LAST, 1));
      expect(v.hasMoreNewer).assertTrue();
      expect(v.state).assertEqual('idle');
      expect(v.reason).assertEqual('filtered-empty-behind-chat-last');
    });

    // 【返回 N 条、过滤后 M 条】往前走了，还有没有更多交给下一次请求判。
    it('a_page_that_merged_rows_keeps_paging_open', 0, () => {
      const v: NewerTailVerdict = decideNewerTail(outcome(30, 12, WINDOW_LAST, CHAT_LAST, 0));
      expect(v.hasMoreNewer).assertTrue();
      expect(v.state).assertEqual('idle');
      expect(v.reason).assertEqual('merged-rows');
    });

    // 【窗口末条已达 chatLast】唯一能证明"真的没有了"的证据。沿用
    // reachedLiveTail，不另发明。
    it('window_reaching_chat_last_is_the_only_proof_of_the_tail', 0, () => {
      const v: NewerTailVerdict = decideNewerTail(outcome(0, 0, CHAT_LAST, CHAT_LAST, 1));
      expect(v.hasMoreNewer).assertFalse();
      expect(v.state).assertEqual('end');
      expect(v.reason).assertEqual('window-reached-chat-last');
    });

    // 窗口比 chatLast 还新（updateNewMessage 先到、updateChatLastMessage 慢半拍）
    // 也算到底：reachedLiveTail 用的是 >=。
    it('window_ahead_of_chat_last_is_still_the_tail', 0, () => {
      const v: NewerTailVerdict =
        decideNewerTail(outcome(0, 0, CHAT_LAST + MESSAGE_ID_STEP, CHAT_LAST, 1));
      expect(v.hasMoreNewer).assertFalse();
      expect(v.state).assertEqual('end');
    });

    // 【chatLast 未知】服务端一条都没给，只能推断到尾部了——旧行为保留。
    it('server_empty_with_unknown_chat_last_ends_paging', 0, () => {
      const v: NewerTailVerdict = decideNewerTail(outcome(0, 0, WINDOW_LAST, 0, 1));
      expect(v.hasMoreNewer).assertFalse();
      expect(v.state).assertEqual('end');
      expect(v.reason).assertEqual('server-empty-tail-unknown');
    });

    // 【chatLast 未知 + 过滤后 0 条】这是"这次没拿到"，不是"没有了"。
    it('filtered_empty_with_unknown_chat_last_keeps_paging_open', 0, () => {
      const v: NewerTailVerdict = decideNewerTail(outcome(30, 0, WINDOW_LAST, 0, 1));
      expect(v.hasMoreNewer).assertTrue();
      expect(v.state).assertEqual('idle');
      expect(v.reason).assertEqual('filtered-empty-tail-unknown');
    });

    // 【认输】chatLast 指着一条怎么都取不回来的消息（已删 / 受限）。无限挂着会
    // 让 atBottom 恒假、新消息不跟随（issue #62 的形状），所以有上限。
    it('gives_up_after_the_doubt_limit', 0, () => {
      const before: NewerTailVerdict =
        decideNewerTail(outcome(0, 0, WINDOW_LAST, CHAT_LAST, NEWER_TAIL_DOUBT_LIMIT - 1));
      expect(before.hasMoreNewer).assertTrue();
      const at: NewerTailVerdict =
        decideNewerTail(outcome(0, 0, WINDOW_LAST, CHAT_LAST, NEWER_TAIL_DOUBT_LIMIT));
      expect(at.hasMoreNewer).assertFalse();
      expect(at.state).assertEqual('end');
      expect(at.reason).assertEqual('gave-up-behind-chat-last');
    });

    // 认输计数不该盖过权威判据：窗口真追上了就是到底，理由仍是 chat-last。
    it('the_doubt_limit_never_overrides_the_authoritative_check', 0, () => {
      const v: NewerTailVerdict =
        decideNewerTail(outcome(0, 0, CHAT_LAST, CHAT_LAST, NEWER_TAIL_DOUBT_LIMIT + 9));
      expect(v.reason).assertEqual('window-reached-chat-last');
    });

    // 合进了行就不认输：streak 再大也先按"往前走了"算。
    it('merged_rows_outrank_the_doubt_limit', 0, () => {
      const v: NewerTailVerdict =
        decideNewerTail(outcome(30, 3, WINDOW_LAST, CHAT_LAST, NEWER_TAIL_DOUBT_LIMIT + 1));
      expect(v.hasMoreNewer).assertTrue();
      expect(v.reason).assertEqual('merged-rows');
    });

    // 两个 0 都不下结论（reachedLiveTail 的既有纪律），窗口 id 未知时不认输。
    it('an_unknown_window_id_does_not_trigger_the_give_up_path', 0, () => {
      const v: NewerTailVerdict =
        decideNewerTail(outcome(0, 0, 0, CHAT_LAST, NEWER_TAIL_DOUBT_LIMIT + 1));
      expect(v.reason).assertEqual('server-empty-tail-unknown');
    });
  });
}
