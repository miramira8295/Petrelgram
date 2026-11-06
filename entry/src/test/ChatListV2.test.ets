import { describe, expect, it } from '@ohos/hypium';
import { pickEntry } from '../main/ets/util/chatListV2';
import { ChatEntry } from '../main/ets/store/ChatEntry';

function entryOf(id: number, title: string): ChatEntry {
  return {
    id, revision: 0, title, isMuted: false, usesDefaultMute: false,
    unreadCount: 0, unreadMentionCount: 0, rawUnreadCount: 0, lastReadInboxId: 0,
    lastReadOutboxId: 0, lastMessageSendState: 'none', typingText: '',
    lastMessageText: '', lastMessageThumb: '', lastMessageDate: 0, lastMessageId: 0,
    lastSenderName: '', photoFileId: 0, avatarPath: '', initials: '', autoDeleteTime: 0,
    kind: 'private', isMarkedUnread: false, actionBar: '', actionBarCanUnarchive: false,
    canDeleteOnlyForSelf: false, canDeleteForAllUsers: false, isSavedMessages: false,
    background: null, themeName: '', liveGroupCallId: 0, isLive: false, isRtmpLive: false
  } as ChatEntry;
}

export default function chatListV2Test() {
  describe('chatListV2', () => {
    it('V1：永远读本地那一份', 0, (): void => {
      const local = entryOf(1, 'local');
      const mirrored = entryOf(1, 'mirror');
      expect(pickEntry(false, local, mirrored)!.title).assertEqual('local');
    });

    it('V2：镜像在就用镜像', 0, (): void => {
      const local = entryOf(1, 'local');
      const mirrored = entryOf(1, 'mirror');
      expect(pickEntry(true, local, mirrored)!.title).assertEqual('mirror');
    });

    it('V2：镜像还没有这条时回退本地（避免列表空一格）', 0, (): void => {
      const local = entryOf(1, 'local');
      expect(pickEntry(true, local, undefined)!.title).assertEqual('local');
      expect(pickEntry(true, undefined, undefined) === undefined).assertTrue();
    });
  });
}
