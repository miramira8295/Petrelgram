// The chat navigation bar remains mounted underneath HdsNavDestination on
// phones. Store subscriptions should keep receiving snapshots while it is
// covered, but its LazyForEach lists must not publish them into that hidden
// tree: those notifications schedule cached ChatRow builds in the same frames
// as the incoming conversation.
export const CHAT_LIST_RENDER_ACTIVE_KEY: string = 'chatListRenderActive';

export function setChatListRenderActive(active: boolean): void {
  if (AppStorage.get<boolean>(CHAT_LIST_RENDER_ACTIVE_KEY) !== active) {
    AppStorage.setOrCreate<boolean>(CHAT_LIST_RENDER_ACTIVE_KEY, active);
  }
}

// 一次性「把缓冲着的快照发出去」的信号（issue #159）。
//
// 从会话退回列表时，onNavBarStateChange(true) 在过渡一开始就来了，但闸要等
// 640ms 过渡结束才开。列表在这期间已经露出来了，画的还是进会话前那份快照——
// 群的未读角标还挂着，要等闸开、缓冲刷出来才消失，就是用户说的「慢半拍」。
// 这个纪元每 bump 一次，各列表把缓冲里最新那份**内容变更**（身份顺序没变的）
// 直接发出去；顺序变了的仍等闸开——那种要带动画，也更贵。
export const CHAT_LIST_FLUSH_EPOCH: string = 'chatListFlushEpoch';

export function requestChatListFlush(): void {
  const previous: number = AppStorage.get<number>(CHAT_LIST_FLUSH_EPOCH) ?? 0;
  AppStorage.setOrCreate<number>(CHAT_LIST_FLUSH_EPOCH, previous + 1);
}
