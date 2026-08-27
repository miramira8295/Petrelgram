// 聊天列表什么时候用底部锚定（List.stackFromEnd）。
//
// stackFromEnd 的语义是"保住离底部的距离"。官方给它的场景是直播评论/即时聊天：
// 底部插入一条，内容自动上滚把它露出来。这对**实时新消息**正好，对**往下翻历史**
// 正好相反：用户停在已加载窗口的末尾触发翻页，追加 28 行进来，"离底部的距离 = 0"
// 被保住，视口就跟着跑到新的末尾——真机上「往下拉新消息进度条很快到底、然后刷出
// 一屏、进度条依然在最底下」就是它。手动补偿也救不了：补偿量到的是重排前的
// 矩形（[AnchorRestore] dy=0），重排在那之后。
//
// 所以按「窗口有没有取到实时尾部」切换：
//   还有更新的页（hasMoreNewer）→ 顶部锚定，两个方向的翻页都交给
//     maintainVisibleContentPosition 保位置；
//   已到实时尾部 → 底部锚定，新消息自动上滚、短会话贴底对齐。
export function stackFromEndWanted(hasMoreNewer: boolean): boolean {
  return !hasMoreNewer;
}
