// 首屏落在哪里：未读分界，还是直接到底。
//
// 规则本身两行，但两个分支各自挂着一段实测教训，写在下面。抽出来是为了让这
// 两条不再只活在注释里——尤其是"第一条未读不在已加载窗口内"那一支，它决定了
// 未读很多时用户看到的是分界线还是最新消息。

export const ANCHOR_UNREAD: string = 'unread';   // 停在未读分界
export const ANCHOR_BOTTOM: string = 'bottom';   // 直接到底

export interface InitialAnchor {
  kind: string;
  // ANCHOR_UNREAD 时要滚到的行号，其余为 -1。
  index: number;
  // 画未读分界线的那条消息 id；不显示分界时为 0。
  dividerId: number;
}

// firstUnreadId：TDLib 给的第一条未读消息 id，0 表示全读完了。
// unreadIndex：它在**当前已加载窗口**里的行号，不在窗口里则为负。
// headIdAt：取该行的首条消息 id（相册行以头条代表整行）。
//
// 注意 unreadIndex 是"在已加载窗口里"而不是"在会话里"。未读很多时首屏只装
// 得下最新的十几条，第一条未读远在窗口之外，于是落到底部且不画分界线——
// 这是既有行为，不是这里新加的判断。
export function initialAnchorOf(
  firstUnreadId: number, unreadIndex: number, headIdAt: (index: number) => number
): InitialAnchor {
  if (firstUnreadId <= 0 || unreadIndex < 0) {
    return { kind: ANCHOR_BOTTOM, index: -1, dividerId: 0 };
  }
  return {
    kind: ANCHOR_UNREAD,
    index: unreadIndex,
    // 分界线画在**行首**那条上：相册是一整行，画在成员身上会落到行中间。
    dividerId: headIdAt(unreadIndex)
  };
}

// 停在未读分界时，两个标志必须一起动，各自挡一个已经发生过的问题：
//
// atBottom 要强制置假——它默认为真，而"在底部就贴底"那一支会把视口从分界
// 拽到最新，顺带把每一页更新的历史都链式加载一遍。
//
// stayAtUnread 要闩住——未读只有几条时 ScrollAlign.START 抬不起分界线（下面
// 内容不够），落点靠近底部，最后一组进入可见区，onScrollIndex 随即把 atBottom
// 翻回真；此后任何一次原地通知（缩略图、引用摘要填充）都会贴底，把分界线滑过去。
// 闩到用户真正触摸列表为止。
export function anchorLatchesBottom(anchor: InitialAnchor): boolean {
  return anchor.kind === ANCHOR_UNREAD;
}
