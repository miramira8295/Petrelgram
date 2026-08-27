// 向下翻页追加行时要不要保住视口（记住顶行 + 发布后补一次差值 scrollBy）。
//
// 列表是底部锚定的（stackFromEnd）：往上插历史不改变「离底部的距离」，框架自己
// 就把位置保住了；往下追加会改变它，可见内容整体上骑、进度条跑到底——必须手动补。
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
