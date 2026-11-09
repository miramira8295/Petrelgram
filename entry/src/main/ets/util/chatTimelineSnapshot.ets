// One immutable publication consumed by ChatTimelineHost. ChatPage may update
// its internal loading, paging, and row fields in any order, but the host sees
// them only after this complete snapshot is committed.
//
// 【这里**没有** groups，是故意的（2026-09-11）】行数据走的是 ChatPage 自己的
// `@Local timelineRows`（Repeat 直接绑它），快照只负责加载/分页那几个标量。
// 原先带着一份 groups 并把它放在判等第一位，后果是：每次发布都是新数组 ⇒ 判等
// 必不成立 ⇒ 每次发布都换一个新快照对象 ⇒ ChatPage.build() 整个重跑。而
// ChatTimelineHost 根本不读 groups。若要再加字段，先确认宿主真的读它。
export interface ChatTimelineSnapshot {
  // 【布尔而不是行数，是故意的】三个消费点（ChatPage 的 composerSlot 键、
  // ChatTimelineHost 的空态判据与 timelineStateMode）**全都只当 `> 0` 用**。
  // 带精确行数进来的后果是：每翻一页行数就变，快照必换新对象，ChatPage.build()
  // 白跑一遍——而宿主显示的东西一个像素都没动。
  hasVisibleRows: boolean;
  messageLoadState: string;
  messageLoadError: string;
  olderLoadState: string;
  newerLoadState: string;
  isChannel: boolean;
  isGroup: boolean;
}

export function emptyChatTimelineSnapshot(): ChatTimelineSnapshot {
  return {
    hasVisibleRows: false,
    messageLoadState: 'loading',
    messageLoadError: '',
    olderLoadState: 'idle',
    newerLoadState: 'idle',
    isChannel: false,
    isGroup: false
  };
}

export function coalesceChatTimelineSnapshot(
  current: ChatTimelineSnapshot,
  next: ChatTimelineSnapshot
): ChatTimelineSnapshot {
  if (current.hasVisibleRows === next.hasVisibleRows &&
    current.messageLoadState === next.messageLoadState &&
    current.messageLoadError === next.messageLoadError &&
    current.olderLoadState === next.olderLoadState &&
    current.newerLoadState === next.newerLoadState &&
    current.isChannel === next.isChannel &&
    current.isGroup === next.isGroup) {
    return current;
  }
  return next;
}
