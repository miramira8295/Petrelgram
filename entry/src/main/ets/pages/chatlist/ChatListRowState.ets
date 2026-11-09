import { ChatEntry } from '../../store/ChatEntry';

// 行渲染需要、但不由 ChatEntry 承载的状态（第二层 B3）。
//
// 【为什么要随快照下发】这些值以前是在 build 里直接查 store 的
// （getChatStore().isPinned / isArchived / isInFolder）。store 将来要搬进
// worker，那条路是异步边界，build 里不能再去查——所以改成发布时算好、随快照
// 一起推下来。行组件从此只读自己的 snapshot。
export interface ChatRowFlags {
  pinned: boolean;
  archived: boolean;
  // 这个会话所在的分组 id（仅在开启"分组标签"时计算，否则为空）。
  folderIds: number[];
}

export const NO_ROW_FLAGS: ChatRowFlags = { pinned: false, archived: false, folderIds: [] };

export interface ChatListRowSnapshot {
  chat: ChatEntry;
  contentKey: string;
  flags: ChatRowFlags;
}

function sameFlags(a: ChatRowFlags, b: ChatRowFlags): boolean {
  if (a === b) {
    return true;
  }
  if (a.pinned !== b.pinned || a.archived !== b.archived || a.folderIds.length !== b.folderIds.length) {
    return false;
  }
  for (let i = 0; i < a.folderIds.length; i++) {
    if (a.folderIds[i] !== b.folderIds[i]) {
      return false;
    }
  }
  return true;
}

// Owned by one published list, never by ChatStore. Replace the first-level
// snapshot property so V1 ObjectLink observes even pin-only changes. Mutating
// nested ChatEntry fields would not notify ObjectLink and would break freezing.
@Observed
export class ChatListRowState {
  readonly id: number;
  // Position in the published list. Gesture validation only needs the row's
  // captured position; looking it up in ChatStore would scan the whole list.
  position: number;
  snapshot: ChatListRowSnapshot;

  constructor(chat: ChatEntry, contentKey: string, flags: ChatRowFlags = NO_ROW_FLAGS,
    position: number = -1) {
    this.id = chat.id;
    this.position = position;
    this.snapshot = { chat, contentKey, flags };
  }

  // flags 与 key 都要比：置顶/归档/分组归属变化不一定改 ChatEntry 的 revision，
  // 只看 key 的话行会停在旧图标上。
  update(chat: ChatEntry, contentKey: string, flags: ChatRowFlags = NO_ROW_FLAGS,
    position: number = this.position): void {
    if (chat.id !== this.id) { throw new Error('ChatListRowState identity changed'); }
    this.position = position;
    if (contentKey === this.snapshot.contentKey && sameFlags(flags, this.snapshot.flags)) { return; }
    this.snapshot = { chat, contentKey, flags };
  }
}
