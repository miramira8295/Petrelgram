import { describe, expect, it } from '@ohos/hypium';
import { ChatListRowState, ChatRowFlags, NO_ROW_FLAGS } from '../main/ets/pages/chatlist/ChatListRowState';
import { ChatEntry } from '../main/ets/store/ChatEntry';

// 行快照的更新判据（第二层 B3）：flags 与 contentKey 任一变化都必须换快照。
// 只看 key 的话，置顶/归档/分组归属变化不会改 ChatEntry.revision，行会停在
// 旧图标上——这正是这几个测试要钉住的东西。
function entryOf(id: number, revision: number): ChatEntry {
  const entry: ChatEntry = {
    id, revision, title: `chat-${id}`, isMuted: false, usesDefaultMute: false,
    unreadCount: 0, unreadMentionCount: 0, rawUnreadCount: 0, lastReadInboxId: 0,
    lastMessageText: '', lastMessageThumb: '', lastMessageDate: 0, lastMessageId: 0,
    lastSenderName: '', photoFileId: 0, avatarPath: '', initials: '', autoDeleteTime: 0,
    kind: 'private', isMarkedUnread: false, actionBar: '', actionBarCanUnarchive: false,
    canDeleteOnlyForSelf: false, canDeleteForAllUsers: false
  } as ChatEntry;
  return entry;
}

function flagsOf(pinned: boolean, archived: boolean, folders: number[]): ChatRowFlags {
  return { pinned, archived, folderIds: folders };
}

export default function chatListRowStateTest() {
  describe('chatListRowState', () => {
    it('key 与 flags 都没变时不换快照（保持对象身份）', 0, (): void => {
      const row = new ChatListRowState(entryOf(1, 3), 'k1', flagsOf(false, false, []));
      const before = row.snapshot;
      row.update(entryOf(1, 3), 'k1', flagsOf(false, false, []));
      expect(row.snapshot === before).assertTrue();
    });

    it('key 不变但置顶变了也要换快照', 0, (): void => {
      const row = new ChatListRowState(entryOf(1, 3), 'k1', flagsOf(false, false, []));
      const before = row.snapshot;
      row.update(entryOf(1, 3), 'k1', flagsOf(true, false, []));
      expect(row.snapshot === before).assertFalse();
      expect(row.snapshot.flags.pinned).assertTrue();
    });

    it('归档与分组归属变化同样换快照', 0, (): void => {
      const row = new ChatListRowState(entryOf(1, 3), 'k1', flagsOf(false, false, [2, 3]));
      const before = row.snapshot;
      row.update(entryOf(1, 3), 'k1', flagsOf(false, true, [2, 3]));
      expect(row.snapshot === before).assertFalse();
      expect(row.snapshot.flags.archived).assertTrue();
      const afterArchive = row.snapshot;
      row.update(entryOf(1, 3), 'k1', flagsOf(false, true, [2, 4]));
      expect(row.snapshot === afterArchive).assertFalse();
      expect(row.snapshot.flags.folderIds.join(',')).assertEqual('2,4');
    });

    it('key 变化照旧换快照，并带上新的 flags', 0, (): void => {
      const row = new ChatListRowState(entryOf(1, 3), 'k1', flagsOf(false, false, []));
      row.update(entryOf(1, 4), 'k2', flagsOf(true, false, [7]));
      expect(row.snapshot.contentKey).assertEqual('k2');
      expect(row.snapshot.chat.revision).assertEqual(4);
      expect(row.snapshot.flags.folderIds.join(',')).assertEqual('7');
    });

    it('不传 flags 时退化成空标记', 0, (): void => {
      const row = new ChatListRowState(entryOf(1, 1), 'k');
      expect(row.snapshot.flags === NO_ROW_FLAGS).assertTrue();
    });

    it('身份变化必须抛错', 0, (): void => {
      const row = new ChatListRowState(entryOf(1, 1), 'k');
      let threw: boolean = false;
      try {
        row.update(entryOf(2, 1), 'k');
      } catch (_e) {
        threw = true;
      }
      expect(threw).assertTrue();
    });
  });
}
