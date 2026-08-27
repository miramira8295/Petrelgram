// 时间层（正文 + 时间戳那个 Stack）该兜多宽的最小宽度。
//
// 气泡里可能比正文更宽的兄弟有三个：转发标签、发送者名字行、评论行。它们都在
// 时间 Stack 外面，各自用 onAreaChange 量出宽度；时间层取其中最宽的做 minWidth，
// 时间戳的 BottomEnd 才落在气泡真正的右下角，引用块的 alignSelf(Stretch) 才能
// 拉到气泡边缘。
//
// **量到的宽度不清零，按「此刻显不显示」来门控。** 曾经的做法是换消息/复用时
// 把三个宽度清成 0，防止"标签消失后旧值残留"。可 onAreaChange 只在面积**变化**
// 时触发：新消息的名字行和上一条一样宽（两条都顶到上限就是这样），回调根本不来，
// 宽度就一直是 0——时间停在正文末尾、引用块也够不到边（用户报的）。
// 门控把两种情况都覆盖了：显示着的节点要么面积变了（回调带来新值），要么没变
// （旧值恰好就是对的）；不显示的节点，值根本不参与。

export interface SiblingLabelWidths {
  forwardShown: boolean;
  forwardW: number;
  senderShown: boolean;
  senderW: number;
  commentsShown: boolean;
  commentsW: number;
}

function shownWidth(shown: boolean, w: number): number {
  return shown && w > 0 ? w : 0;
}

// 返回 0 表示不兜（让正文自己定宽）。结果封顶在 inlineMaxW，量到偏大的值
// 不会把气泡撑出上限。
export function timeLayerMinWidth(inlineMaxW: number, labels: SiblingLabelWidths): number {
  const widest: number = Math.max(
    shownWidth(labels.forwardShown, labels.forwardW),
    Math.max(shownWidth(labels.senderShown, labels.senderW),
      shownWidth(labels.commentsShown, labels.commentsW)));
  if (widest <= 0 || inlineMaxW <= 0) {
    return 0;
  }
  return Math.min(inlineMaxW, widest);
}
