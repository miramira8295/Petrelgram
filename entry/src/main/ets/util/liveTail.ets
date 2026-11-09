// 已加载的窗口是不是已经追到会话的实时尾部。
//
// **为什么需要这个判据**（issue #62，2026-08-22 平板实测）：
// hasMoreNewer 原本只由分页自己维护——loadNewer 取不到更新的消息才置假。在有
// 大量积压的活跃会话里这个条件很难成立：
//
//   · 本地库里带洞时，loadNewer 只收与窗口连续的那一段，剩下的留到下次，
//     hasMoreNewer 被显式置回 true（见 MessageStore 里 "inner gap" 那一支）；
//   · 而群里每几秒就有新消息，尾部一直在后退。
//
// 结果是用户手滑往下追，rows 一直涨（实测 402 → 414 → 442），246 行处那个 8 条
// 的洞始终不合，hasMoreNewer 恒为真。而 atBottom 的判定里带着 !hasMoreNewer，
// 于是 atBottom 恒为假，"新消息自动跟随"永远不启用——用户看到的就是
// "我明明在最底下，新消息却不滚动"。
//
// 点右下角箭头为什么就正常：那条路走 jumpToLatest()，里面有一行显式的
// `this.hasMoreNewer = false`，直接从尾部重新装载。用户观察到的三种现象
//   点箭头→会滚 / 手滑到底→不滚 / 未读很少打开就在底部→会滚
// 全部由这一处不对称解释。
//
// **判据本身**：会话的最后一条消息 id 是权威的（TDLib 的 updateChatLastMessage
// 直接给），窗口最新一条追上它就是真尾部，与分页取没取完无关。
//
// 用 >= 而不是 ===：新消息可能先经 updateNewMessage 进了窗口，
// updateChatLastMessage 慢一拍，这半拍里窗口比会话记录的还新。用 === 会在这
// 半拍里翻回"没到底"，跟随随之抖动。
//
// **两个 0 都必须返回 false**：不知道就不下结论。误判成"到底了"会把分页关掉，
// 用户再也翻不到更新的消息——那比多翻几页严重得多。
export function reachedLiveTail(windowNewestId: number, chatLastMessageId: number): boolean {
  if (windowNewestId <= 0 || chatLastMessageId <= 0) {
    return false;
  }
  return windowNewestId >= chatLastMessageId;
}

// TDLib 的消息 id 每条加 2^20（服务端 id 左移 20 位），相邻两条的差就是 1 步。
export const MESSAGE_ID_STEP: number = 1048576;

// 实时到达的消息离窗口尾巴几步。0 = 没有窗口或不比尾巴新。
export function liveArrivalStep(windowNewestId: number, arrivalId: number): number {
  if (windowNewestId <= 0 || arrivalId <= windowNewestId) {
    return 0;
  }
  return Math.round((arrivalId - windowNewestId) / MESSAGE_ID_STEP);
}

// 实时到达的消息是不是**紧接着**窗口尾巴——收下它不会在窗口里留洞。
//
// issue #62 的根因就在这一步的缺失：窗口向下翻到底之后 hasMoreNewer 没关（短页
// 不算到头，syncTailFromChatLast 又要靠 chatLastMessageId），闸门把 id 只比尾巴
// 大一步的实时消息当成"跨洞"扔掉，窗口从此永远追不上；报告人日志里十次
// live arrival skipped 全是这个形状（差正好一步，之后每条都丢）。
//
// 容差和 loadNewer 的页连续性检查用同一个数：被删的消息、服务消息会让相邻 id
// 差不止一步，那边算连续的这里也算。
export function liveArrivalContiguous(
  windowNewestId: number, arrivalId: number, tolerance: number
): boolean {
  const step: number = liveArrivalStep(windowNewestId, arrivalId);
  return step >= 1 && step <= tolerance;
}

// ── 向下分页到底了没有 ─────────────────────────────────────────────────────
//
// 【这条判据要挡的谎】
// loadNewer 原来用「这一页里没有比窗口更新的消息」当作"到达实时尾部"的证据，
// 连续两次拿到这样的页就置 hasMoreNewer=false / newerState='end'。
//
// 但这两件事不是一回事：
//
//   · 「服务端这一页没给出更新的消息」——只说明**此刻这次请求**没拿到东西。
//     getChatHistory 带负 offset 时常常只吃本地库（loadNewer 里那条 cache-warm
//     重问的注释就是为这个加的），本地库冷着的时候它照样返回空。
//   · 「会话真的没有更新的消息了」——只有 chatLastMessageId 说了算。
//
// 真机实测（2026-08-27）：store 报 newerState=end / hasMoreNewer=false，用户
// 怎么拖都不取页（started=false，在旧逻辑下"正确"——没东西可拿），可**过一会儿
// 那条更新的消息自己从实时推送冒出来了**。用户原话：「闪的时候底下确实没有数据
// 了，但是闪完之后后面会出来一条」。数据本身是通的，是 loadNewer 这条路把它判
// 丢了。用户主诉的"推不动"，到这一层已经不是闸挡的，是 store 谎报到底。
//
// 【正确的依据】
// 沿用 reachedLiveTail 那一套，不另发明：窗口最新一条追上 chatLastMessageId 才
// 是真尾部。页里返回了多少条只是旁证，且**过滤后为 0 ≠ 到达尾部**——过滤后为 0
// 说明这一页与窗口不连续、或者整页都是窗口已有的重复条目，那是"这次没拿到"，
// 不是"没有了"。
//
// 【为什么不会死循环】
// 判成"还有"只是把 hasMoreNewer 留在真，**不触发任何自动重试**。下一次请求要么
// 由用户再拖够 PAGE_GATE_REARM_DRAG_VP（见 util/pageGate，一页一个位移配额），
// 要么由 loadNewer 自己那条一次性的 cache-warm 重问发出——两条都是有限的。
//
// 【为什么不会把 issue #62 放回来】
// 那个 issue 的形状是 hasMoreNewer 恒真 ⇒ atBottom 恒假 ⇒ 新消息不自动跟随。
// 这里留真之后仍有两条独立的关闸路径：syncTailFromChatLast（窗口追上 chatLast）
// 和实时到达守卫里 liveArrivalContiguous 那一支（紧接着尾巴的实时消息证明窗口
// 就在尾部）。而且留真恰恰让后者能生效——hasMoreNewer 为假时那条守卫整个被跳过。
// 万一 chatLastMessageId 指向一条永远取不回来的消息（已删、受限），emptyStreak
// 到 NEWER_TAIL_DOUBT_LIMIT 就认输收摊，判据因此是全函数的，不会卡死。
export const NEWER_TAIL_DOUBT_LIMIT: number = 3;

export interface NewerPageOutcome {
  // 服务端这一页给回来多少条（**未过滤**）。
  serverCount: number;
  // 过滤后真正比窗口更新、且与窗口连续、合进了窗口的有多少条。
  mergedCount: number;
  // 合并之后窗口最新一条的 id。
  windowNewestId: number;
  // 会话最后一条的 id（TDLib updateChatLastMessage 给的权威值）。0 = 还不知道。
  chatLastMessageId: number;
  // 同一个锚点上"服务端没给出更新的消息"已经连续发生了几次。
  emptyStreak: number;
}

export interface NewerTailVerdict {
  hasMoreNewer: boolean;
  // 'idle' | 'end'
  state: string;
  // 探针用，英文，一眼看出这一票是凭什么投的。
  reason: string;
}

function verdict(hasMore: boolean, state: string, reason: string): NewerTailVerdict {
  const value: NewerTailVerdict = { hasMoreNewer: hasMore, state: state, reason: reason };
  return value;
}

export function decideNewerTail(outcome: NewerPageOutcome): NewerTailVerdict {
  // 1) 权威判据：窗口追上会话最后一条。这是唯一能证明"真的没有了"的证据。
  if (reachedLiveTail(outcome.windowNewestId, outcome.chatLastMessageId)) {
    return verdict(false, 'end', 'window-reached-chat-last');
  }
  // 2) 这一页确实往前走了：还有没有更多，交给下一次请求判。
  if (outcome.mergedCount > 0) {
    return verdict(true, 'idle', 'merged-rows');
  }
  // 3) 一行都没合进来。chatLast 已知且窗口还落在它后面 —— 会话里**明确还有**
  //    更新的消息，这次只是没拿到。绝不能关闸。
  const behindChatLast: boolean = outcome.chatLastMessageId > 0 &&
    outcome.windowNewestId > 0 && outcome.windowNewestId < outcome.chatLastMessageId;
  if (behindChatLast) {
    if (outcome.emptyStreak >= NEWER_TAIL_DOUBT_LIMIT) {
      // 认输：chatLast 指着一条怎么都取不回来的消息（已删 / 受限）。再挂着
      // 只会让 atBottom 恒假、新消息不跟随，那比少翻几页更糟。
      return verdict(false, 'end', 'gave-up-behind-chat-last');
    }
    return outcome.serverCount === 0
      ? verdict(true, 'idle', 'empty-page-behind-chat-last')
      : verdict(true, 'idle', 'filtered-empty-behind-chat-last');
  }
  // 4) chatLast 还不知道（0），只能看这一页本身。
  //    服务端一条都没给 —— 当作到尾部（旧行为，也是唯一合理的推断）。
  if (outcome.serverCount === 0) {
    return verdict(false, 'end', 'server-empty-tail-unknown');
  }
  // 5) 服务端给了 N 条，过滤后一条都不剩：整页是重复条目、或与窗口不连续。
  //    这是"这次没拿到"，不是"没有了"——正是被误判成到底的那一格。
  return verdict(true, 'idle', 'filtered-empty-tail-unknown');
}
