// 向下翻页追加行时要不要保住视口（记住顶行 + 发布后补一次差值 scrollBy）。
//
// **前提是列表此刻真的底部锚定**。底部锚定时往下追加会改变「离底部的距离」，
// 可见内容整体上骑、进度条跑到底——那时必须手动补。
//
// 但 stackFromEnd 不是常开的：`util/stackFromEnd.ets` 是 `!hasMoreNewer`，而
// **往下翻历史时 hasMoreNewer 恰恰是 true**，列表是**顶部锚定**的。顶部锚定下
// 在视口**下方**追加行，可见内容根本不动，这一次补偿就是纯多余——它唯一的效果
// 是把采样到测量之间用户自己滑的那一段位移（anchorRestore 的 dy 里没有滚动偏移
// 项）反向抵消掉，表现为「往下每翻一页回弹/顿一下」。用户报的「上下翻动都有」，
// 向下那一半就出在这里。
//
// 所以判据里必须带上 stackFromEnd：只有底部锚定时这套补偿才有意义。
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
  // 列表此刻是不是底部锚定（List.stackFromEnd）。false = 顶部锚定，视口下方
  // 追加不动内容，补偿多余且有害。见文件头。
  stackFromEnd: boolean;
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
  // 顶部锚定下追加不动视口，补了反而抵消用户的滑动。排在最前：它比别的条件更
  // 根本——不满足它时这套补偿整个没有立足点。
  if (!input.stackFromEnd) {
    return false;
  }
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
