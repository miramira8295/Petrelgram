import { AlbumGroup } from './collapseAlbums';

// One immutable publication consumed by ChatTimelineHost. ChatPage may update
// its internal loading, paging, and row fields in any order, but the host sees
// them only after this complete snapshot is committed.
export interface ChatTimelineSnapshot {
  groups: AlbumGroup[];
  visibleGroupCount: number;
  messageLoadState: string;
  messageLoadError: string;
  olderLoadState: string;
  newerLoadState: string;
  isChannel: boolean;
  isGroup: boolean;
}

export function emptyChatTimelineSnapshot(): ChatTimelineSnapshot {
  return {
    groups: [],
    visibleGroupCount: 0,
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
  if (current.groups === next.groups &&
    current.visibleGroupCount === next.visibleGroupCount &&
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
