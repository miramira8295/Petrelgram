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
