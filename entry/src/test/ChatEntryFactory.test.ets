import { describe, expect, it } from '@ohos/hypium';
import { buildChatEntry, effectiveUnread, ChatEntryBuildInput } from '../main/ets/store/chatEntryFactory';
import { ChatEntry } from '../main/ets/store/ChatEntry';
import { TdObject } from '../main/ets/tdkit/TdTypes';

// ChatEntry 的字段规则（第二层 B4a）。这份工厂将来会原样跑在 worker 里，
// 所以每条规则都钉死在这里，任何一处改动都要有意识地改测试。
function td(type: string): TdObject {
  return { '@type': type };
}

function messageOf(id: number, date: number, outgoing: boolean): TdObject {
  const m = td('message');
  m['id'] = id;
  m['date'] = date;
  m['is_outgoing'] = outgoing;
  return m;
}

function photoOf(fileId: number): TdObject {
  const small = td('file');
  small['id'] = fileId;
  const photo = td('chatPhotoInfo');
  photo['small'] = small;
  return photo;
}

function chatOf(id: number, overrides: (chat: TdObject) => void): TdObject {
  const chat = td('chat');
  chat['id'] = id;
  chat['title'] = `title-${id}`;
  chat['type'] = td('chatTypePrivate');
  chat['unread_count'] = 0;
  chat['last_read_inbox_message_id'] = 0;
  chat['unread_mention_count'] = 0;
  chat['message_auto_delete_time'] = 0;
  overrides(chat);
  return chat;
}

function build(chat: TdObject, previous: ChatEntry | undefined, selfId: number): ChatEntry {
  const input: ChatEntryBuildInput = {
    chat, previous, selfId, senderName: (_m: TdObject | undefined): string => 'sender'
  };
  return buildChatEntry(input);
}

export default function chatEntryFactoryTest() {
  describe('chatEntryFactory', () => {
    it('幽灵未读：读水位越过末条时展示值抹零，原始值保留', 0, (): void => {
      const chat = chatOf(1, (c: TdObject): void => {
        c['unread_count'] = 5;
        c['last_read_inbox_message_id'] = 100;
        c['last_message'] = messageOf(90, 1700000000, false);
      });
      const entry = build(chat, undefined, 0);
      expect(entry.unreadCount).assertEqual(0);
      expect(entry.rawUnreadCount).assertEqual(5);
      expect(entry.lastReadInboxId).assertEqual(100);
      expect(entry.lastMessageId).assertEqual(90);
    });

    it('普通未读照常保留', 0, (): void => {
      const chat = chatOf(2, (c: TdObject): void => {
        c['unread_count'] = 7;
        c['last_read_inbox_message_id'] = 10;
        c['last_message'] = messageOf(20, 1700000000, false);
      });
      expect(build(chat, undefined, 0).unreadCount).assertEqual(7);
    });

    it('自己私聊识别为 Saved Messages，发送者名置空', 0, (): void => {
      const chat = chatOf(42, (c: TdObject): void => {
        c['last_message'] = messageOf(5, 1700000000, false);
      });
      const entry = build(chat, undefined, 42);
      expect(entry.isSavedMessages).assertTrue();
      expect(entry.lastSenderName).assertEqual('');
      const other = build(chat, undefined, 7);
      expect(other.isSavedMessages).assertFalse();
      expect(other.lastSenderName).assertEqual('sender');
    });

    it('revision 随上一版递增；照片没变时保留已解析的头像路径', 0, (): void => {
      const chat = chatOf(3, (c: TdObject): void => {
        c['photo'] = photoOf(11);
      });
      const first = build(chat, undefined, 0);
      expect(first.revision).assertEqual(0);
      expect(first.avatarPath).assertEqual('');
      first.avatarPath = '/cache/avatar.jpg';
      const second = build(chat, first, 0);
      expect(second.revision).assertEqual(1);
      expect(second.avatarPath).assertEqual('/cache/avatar.jpg');
      // 照片换了就清空，等新的落地。
      const changed = chatOf(3, (c: TdObject): void => {
        c['photo'] = photoOf(12);
      });
      expect(build(changed, second, 0).avatarPath).assertEqual('');
    });

    it('末条消息驱动预览字段与日期', 0, (): void => {
      const chat = chatOf(4, (c: TdObject): void => {
        c['last_message'] = messageOf(77, 1700000123, true);
      });
      const entry = build(chat, undefined, 0);
      expect(entry.lastMessageId).assertEqual(77);
      expect(entry.lastMessageDate).assertEqual(1700000123);
      expect(entry.initials).assertEqual('T');
    });

    it('删除能力位直接取 chat 对象上的布尔值', 0, (): void => {
      const chat = chatOf(5, (c: TdObject): void => {
        c['can_be_deleted_only_for_self'] = true;
        c['can_be_deleted_for_all_users'] = false;
      });
      const entry = build(chat, undefined, 0);
      expect(entry.canDeleteOnlyForSelf).assertTrue();
      expect(entry.canDeleteForAllUsers).assertFalse();
    });

    it('effectiveUnread 的边界', 0, (): void => {
      expect(effectiveUnread(0, 0, 0)).assertEqual(0);
      expect(effectiveUnread(3, 0, 0)).assertEqual(3);
      expect(effectiveUnread(3, 5, 5)).assertEqual(0);
      expect(effectiveUnread(3, 4, 5)).assertEqual(3);
    });
  });
}
