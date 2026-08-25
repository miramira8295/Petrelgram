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
