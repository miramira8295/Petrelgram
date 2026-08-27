// 浮动日期条的两道节流判据。
//
// onDidScroll 每渲染一帧就来一次。原来这两件事是搅在同一段早退里的：
//
//   if (start === floatDateIndex && floatDateShown) {
//     if (now - floatDateTimerArmedAt < 180) { return; }   // ← 续期节流
//     armFloatDateHide(now); return;                       // ← 只续期不重扫
//   }
//
// 把日期条拆到独立组件之后，这两件事的归属不一样，必须先分清：
//
//   · **要不要重新扫 groups 算日期**：只看顶行下标变没变。groups 是 ChatPage
//     的数据，扫描留在 ChatPage，全程不碰任何响应式字段。
//   · **要不要给显示续期**：只看距上次上定时器过了多久。这一条连同 820ms 的
//     隐藏定时器一起下沉到日期条自己那边，ChatPage 不再参与。
//
// 两条都是纯判据，抽出来是为了拆分时不把语义搞丢——尤其是"顶行没变但手指还在
// 拖"那一支：日期条必须继续亮着，靠的正是这道 180ms 一次的粗粒度续期。

// 停止滚动后日期条淡出的等待时长。ChatPage 的 listUserScrollActive 也是在这
// 个时刻翻假的（见 ChatPage.onFloatDateHidden 的注释）。
export const FLOAT_DATE_HIDE_MS: number = 820;

// 顶行没变时，续期最快每 180ms 一次。再密就是白跑定时器的建/拆。
export const FLOAT_DATE_REARM_MS: number = 180;

// 顶行下标变了才值得重新扫 groups、重新格式化日期、重新写状态。
// currentIndex 为负 = 当前没有在显示日期条（还没显示，或者刚隐藏复位过）。
export function floatDateNeedsRescan(topIndex: number, currentIndex: number): boolean {
  return topIndex !== currentIndex;
}

// 顶行没变时要不要给隐藏定时器续期。armedAt 为 0 表示还没上过定时器。
export function floatDateShouldRearm(now: number, armedAt: number): boolean {
  if (armedAt <= 0) {
    return true;
  }
  return now - armedAt >= FLOAT_DATE_REARM_MS;
}
