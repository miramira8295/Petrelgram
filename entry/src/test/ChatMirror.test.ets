import { describe, expect, it } from '@ohos/hypium';
import { ChatMirror } from '../main/ets/store/chatMirror';
import { ChatEntry } from '../main/ets/store/ChatEntry';

// 镜像的合并规则（第二层 B4b-3）：remote 覆盖一切，除了三样本地独有字段。
// 这些规则将来直接决定"切权威之后界面上显示什么"，所以逐条钉住。
function entryOf(id: number, title: string, photoId: number): ChatEntry {
  return {
    id, revision: 0, title, isMuted: false, usesDefaultMute: false,
    unreadCount: 0, unreadMentionCount: 0, rawUnreadCount: 0, lastReadInboxId: 0,
    lastReadOutboxId: 0, lastMessageSendState: 'none', typingText: '',
    lastMessageText: '', lastMessageThumb: '', lastMessageDate: 0, lastMessageId: 0,
    lastSenderName: '', photoFileId: photoId, avatarPath: '', initials: '', autoDeleteTime: 0,
    kind: 'private', isMarkedUnread: false, actionBar: '', actionBarCanUnarchive: false,
    canDeleteOnlyForSelf: false, canDeleteForAllUsers: false, isSavedMessages: false,
    background: null, themeName: '', liveGroupCallId: 0, isLive: false, isRtmpLive: false
  } as ChatEntry;
}

export default function chatMirrorTest() {
  describe('chatMirror', () => {
    it('首次合并落库，revision 从 0 开始', 0, (): void => {
      const mirror = new ChatMirror();
      expect(mirror.apply([entryOf(1, 'a', 10)]).length).assertEqual(1);
      expect(mirror.size()).assertEqual(1);
      expect(mirror.get(1)!.revision).assertEqual(0);
    });

    it('数据没变时不算变化，对象身份保持', 0, (): void => {
      const mirror = new ChatMirror();
      mirror.apply([entryOf(1, 'a', 10)]);
      const before = mirror.get(1);
      expect(mirror.apply([entryOf(1, 'a', 10)]).length).assertEqual(0);
      expect(mirror.get(1) === before).assertTrue();
    });

    it('字段变化时覆盖并推进 revision', 0, (): void => {
      const mirror = new ChatMirror();
      mirror.apply([entryOf(1, 'a', 10)]);
      const next = entryOf(1, 'b', 10);
      expect(mirror.apply([next]).length).assertEqual(1);
      expect(mirror.get(1)!.title).assertEqual('b');
      expect(mirror.get(1)!.revision).assertEqual(1);
    });

    it('头像路径：照片没换就保住，换了就清空', 0, (): void => {
      const mirror = new ChatMirror();
      mirror.apply([entryOf(1, 'a', 10)]);
      mirror.get(1)!.avatarPath = '/cache/a.jpg';
      mirror.apply([entryOf(1, 'a', 10)]);
      expect(mirror.get(1)!.avatarPath).assertEqual('/cache/a.jpg');
      mirror.apply([entryOf(1, 'a', 11)]);
      expect(mirror.get(1)!.avatarPath).assertEqual('');
    });

    it('输入中与直播位保留，其余以 worker 为准', 0, (): void => {
      const mirror = new ChatMirror();
      mirror.apply([entryOf(1, 'a', 10)]);
      mirror.get(1)!.typingText = '正在输入…';
      mirror.get(1)!.isLive = true;
      const incoming = entryOf(1, 'a2', 10);
      incoming.isLive = false;
      mirror.apply([incoming]);
      expect(mirror.get(1)!.typingText).assertEqual('正在输入…');
      expect(mirror.get(1)!.isLive).assertTrue();
      expect(mirror.get(1)!.title).assertEqual('a2');
    });

    it('clear 之后可以重新收', 0, (): void => {
      const mirror = new ChatMirror();
      mirror.apply([entryOf(1, 'a', 10)]);
      mirror.clear();
      expect(mirror.size()).assertEqual(0);
      expect(mirror.apply([entryOf(2, 'c', 0)]).length).assertEqual(1);
    });
  });
}
