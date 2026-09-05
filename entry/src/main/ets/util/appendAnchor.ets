// 向下翻页追加行时要不要保住视口（记住顶行 + 发布后补一次差值 scrollBy）。
//
// 底部锚定时往下追加会改变「离底部的距离」，可见内容整体上移、进度条跑到底，
// 必须手动补。顶部锚定原本被认为不需要补，但媒体会话的真机日志推翻了这个前提：
// around-unread 的 14 条原始消息折叠成 2 个超高相册行，第一次拖动触发 newer 后，
// 28 条媒体消息又让 Repeat 从 15 行变成 19 行；即使 stackFromEnd=false，整个可见
// 窗口仍然换了位置。普通短文本追加通常由 maintainVisibleContentPosition 守住，
// 此时发布前后的同一行 y 相等，下面的差值复位自然是 noop。
//
// 以前顶部锚定不能补，是因为异步测量把采样后的用户拖动也算进 dy，结果反向抵消
// 手势。现在 ChatPage 把用户来源的 onDidScroll 位移单独累计，anchorRestore 的
// targetY 会随手势一起移动，只消掉数据/布局位移；因此两种锚定方向都可以安全保位。
//
// 曾经只对「用户拖出来的那一页」补（reqUserDriven），自动填充的页不补，是为了打断
// 「复位把视口按住 → 又进触发区 → 再取一页」的循环。那个循环的根子已经被拖动式
// 闸（pageGate，一次拖 120vp 才放一页）修掉，复位本身也改成只做一次差值 scrollBy
// （anchorRestore），不会再互相打架。于是自动填充的页不补就只剩坏处：真机上
// 「往下拉新消息时进度条经常到底，看历史却很顺滑」就是它。
//
// 现在：只要追加真的动了锚点就补，例外只有两种——用户就在实时尾部（追加的是新
// 消息，该跟着走）、或者有明确的滚动意图在途（点 ↓ / 跳转，别和它抢）。

export interface AppendAnchorInput {
  bypassed: boolean;
  didInitialScroll: boolean;
  prependAnchorHeld: boolean;
  appendBreaksAnchor: boolean;
  // 用户此刻在实时尾部：追加的是新消息，跟随而不是保锚点。
  atLiveTail: boolean;
  // 点 ↓ / 跳转在途：意图优先，不记锚点。
  scrollIntentPending: boolean;
}

export function shouldHoldAppendAnchor(input: AppendAnchorInput): boolean {
  if (input.bypassed || !input.didInitialScroll || input.prependAnchorHeld) {
    return false;
  }
  if (!input.appendBreaksAnchor) {
    return false;
  }
  if (input.scrollIntentPending || input.atLiveTail) {
    return false;
  }
  return true;
}

// 下面两个只服务于诊断（[AppendAnchor] 探针里的 reqUserDriven）和翻页闸：
// 「这一枪是谁扣的扳机」不再决定补不补，但仍然值得记下来。
export function newerPageIsUserDriven(gateArmedByUser: boolean): boolean {
  return gateArmedByUser;
}

export function useUserDrivenAppendMark(markPending: boolean, appendsRows: boolean): boolean {
  return markPending && appendsRows;
}

// 以下止血开关从 pages/chat/ChatPage.ets 顶部（原 345–365 行）搬来。放这里是因为它
// 守护的判据 shouldHoldAppendAnchor 就在本文件里——「改回 false 即完全恢复」的止血
// 语义和被它关掉的判据必须放在一起，才不会日后各走各的。注释逐字保留。
// ⚠️ 止血开关（可单独回退）：向下翻页追加时的**手动**锚点复位（260e497）整条
// 旁路掉。true = 旁路（不记锚点、不复位），false = 恢复 260e497 的行为。
//
// 【为什么】真机现象四条：静止/滑动时列表每帧重建（闪）、视口纹丝不动、点右下角
// ↓ 要点好几次才下得去、读到底再进会话仍落在中间。它们指向同一条路径：
// applyMessages 里那道 `!this.atBottom` 闸。atBottomVerdict（util/atBottom）在
// hasMoreNewer 为真时**恒返回 NO**——也就是说只要窗口还没取到会话实时尾部，这道
// 闸就一直开着。于是每次向下翻页的发布都会 scrollToIndex 把视口拽回锚点，视口被
// 按住 → 可见区间不变 → 边界行每帧建了又拆；等窗口终于取到尾部、hasMoreNewer
// 翻假，闸关上，拉锯自行结束——正是用户说的「闪完之后位置会动，然后就正常了」。
// ↓ 按钮那一条同源：restoreScrollAnchor 的 setTimeout 里有
// `this.pendingScrollBottom` 守卫，点 ↓ 恰好是唯一能压过复位的意图。
//
// 【为什么是旁路而不是删】260e497 治的是真问题（stackFromEnd 下追加把可见内容
// 顶走）。这个常量只是把它整条摘出去，好让用户一次装机就能证实/证伪「是不是它
// 按住了列表」。原代码与全部单测（AlbumGroupDataSource.test 里 appendBreaksAnchor
// 那两条）一字未动，改回 false 即完全恢复。
//
// 【结论落地后】若坐实：正确修法不是留着这个常量，而是把 `!this.atBottom` 换成
// 一条真正表达「这次追加是用户主动向下翻页的结果」的判据（见交付说明）。
export const APPEND_ANCHOR_RESTORE_BYPASSED: boolean = false;
