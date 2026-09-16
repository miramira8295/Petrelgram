// 停在实时末尾时，新消息到来的"贴底跟随"该不该排、该不该点火（纯函数，有单测）。
//
// 【背景】可滚动的消息列表不再用 List.stackFromEnd（官方写明它在底部插入时会把
// 上方可见项整体上移——那就是停在末尾附近来新消息时整屏闪动的来源）。跟随改由
// ChatPage.scheduleBottomAfterLayout 显式做：延后一帧、等 Repeat 看见新长度，
// 再 scrollEdge(Bottom)。
//
// 【这里修的坑，2026-09-09 真机日志】
//   [Follow62] atBottom=true  endIdx=29 rows=31   ← 第一条新消息，排了跟随
//   [Follow62] atBottom=false endIdx=30 rows=32   ← 之后每条：atBottom 已翻假
//   ……视口卡在 31，行数一路涨到 42，全程没有一条 apply tag=L1242
// 原因是跟随**自己把自己否了**：stackFromEnd 关掉后，新行落在视口下方，
// isAtEnd() 立刻变假、atBottom 翻成 false；32ms 后定时器点火时再看一眼
// atBottom，"不在底了"就放弃。后面每条消息在**排期那一刻**就看到 false，连排都
// 不排。用户报："消息在最底下，但是不会往上顶消息列表了，需要手滑动了"。
//
// 【两条规则】
//   1. 跟随的决定在**排期那一刻**就做了。点火时只看"用户有没有接管"（手指按着、
//      列表在滚）、"有没有更强的意图"（查看器开着、还有更新的页没拉）、"有没有
//      被更新的一次排期取代"。**不再看 atBottom**——它翻假正是这次追加造成的，
//      恰恰是要跟随的那件事。
//   2. 跟随在途期间又来了新消息，视为**仍在底**：那一刻 atBottom 是假的，是因为
//      上一条还没贴过去，不是用户离开了底部。

export interface BottomFollowFireInput {
  superseded: boolean;   // 排期后又排了更新的一次（代次不等）
  touchActive: boolean;  // 手指仍按在列表上
  scrollActive: boolean; // 列表在滚（拖动或惯性）
  viewerOpen: boolean;
  hasMoreNewer: boolean; // 窗口还没到实时尾部
  // 跳转刚落地，位置归这次跳转所有（util/jumpLandingOwner）。
  //
  // 【为什么这条也要问】排期发生在 applyInitialOrFollowLanding，而它跑在
  // landPendingJump **之前**——排期那一刻用的是跳转前的 atBottom，看到的是"用户
  // 在底部"。等 32ms 后点火时，跳转其实已经落地了，这一发 scrollEdge(Bottom) 就
  // 把用户从目标拽回底部。用户 2026-09-16 报的"第一次像是过去了又被抓去了别的
  // 地方"，这是四个嫌疑之一。
  jumpLanding: boolean;
}

export function bottomFollowShouldApply(input: BottomFollowFireInput): boolean {
  return !input.superseded && !input.touchActive && !input.scrollActive &&
    !input.viewerOpen && !input.hasMoreNewer && !input.jumpLanding;
}

export function bottomFollowShouldSchedule(
  atBottom: boolean, followPending: boolean, viewerOpen: boolean
): boolean {
  if (viewerOpen) {
    return false;
  }
  return atBottom || followPending;
}
