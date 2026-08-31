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
