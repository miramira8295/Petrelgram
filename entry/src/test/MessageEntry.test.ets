import { describe, it, expect } from '@ohos/hypium';
import { TdClient } from '../main/ets/tdkit/TdClient';
import { TdObject, TdBridge } from '../main/ets/tdkit/TdTypes';
import { UserStore } from '../main/ets/store/UserStore';
import { buildMessageEntry, cloneMessage, MessageEntry } from '../main/ets/store/MessageEntry';
import { collapseAlbums, AlbumGroup } from '../main/ets/util/collapseAlbums';

class FakeBridge implements TdBridge {
  onReceive: (json: string) => void = (): void => {};
  sent: string[] = [];
  init(cb: (json: string) => void): void { this.onReceive = cb; }
  send(json: string): void { this.sent.push(json); }
}
function usersOf(): UserStore {
  const b = new FakeBridge(); const c = new TdClient(b); const u = new UserStore(c); c.start();
  const user: TdObject = { '@type': 'user' }; user['id'] = 7; user['first_name'] = 'Ann'; user['last_name'] = '';
  const upd: TdObject = { '@type': 'updateUser' }; upd['user'] = user;
  b.onReceive(JSON.stringify(upd));
  const other: TdObject = { '@type': 'user' };
  other['id'] = 8; other['first_name'] = 'Bob'; other['last_name'] = '';
  const otherUpd: TdObject = { '@type': 'updateUser' }; otherUpd['user'] = other;
  b.onReceive(JSON.stringify(otherUpd));
  return u;
}
function msg(id: number, outgoing: boolean, senderUserId: number, text: string): TdObject {
  const ft: TdObject = { '@type': 'formattedText' }; ft['text'] = text;
  const c: TdObject = { '@type': 'messageText' }; c['text'] = ft;
  const sender: TdObject = { '@type': 'messageSenderUser' }; sender['user_id'] = senderUserId;
  const m: TdObject = { '@type': 'message' };
  m['id'] = id; m['is_outgoing'] = outgoing; m['sender_id'] = sender; m['date'] = 100; m['content'] = c;
  return m;
}

function serviceMsg(id: number, senderUserId: number, content: TdObject,
  outgoing: boolean = false): TdObject {
  const sender: TdObject = { '@type': 'messageSenderUser' }; sender['user_id'] = senderUserId;
  const m: TdObject = { '@type': 'message' };
  m['id'] = id; m['is_outgoing'] = outgoing; m['sender_id'] = sender;
  m['date'] = 100; m['content'] = content;
  return m;
}

export default function messageEntryTest() {
  describe('MessageEntry', () => {
    it('incoming_text', 0, () => {
      const e = buildMessageEntry(msg(10, false, 7, 'hi'), usersOf());
      expect(e.id).assertEqual(10);
      expect(e.isOutgoing).assertEqual(false);
      expect(e.senderName).assertEqual('Ann');
      expect(e.contentType).assertEqual('text');
      expect(e.text).assertEqual('hi');
      expect(e.sendState).assertEqual('none');
    });
    it('outgoing_sending_state', 0, () => {
      const m = msg(11, true, 7, 'yo');
      const st: TdObject = { '@type': 'messageSendingStatePending' }; m['sending_state'] = st;
      const e = buildMessageEntry(m, usersOf());
      expect(e.sendState).assertEqual('sending');
    });
    it('outgoing_sent_when_no_state', 0, () => {
      const e = buildMessageEntry(msg(12, true, 7, 'done'), usersOf());
      expect(e.sendState).assertEqual('sent');
    });
    it('clone_is_independent', 0, () => {
      const e = buildMessageEntry(msg(13, false, 7, 'x'), usersOf());
      const c = cloneMessage(e); c.text = 'changed';
      expect(e.text).assertEqual('x');
    });
    it('edit_date_survives_build_and_clone', 0, () => {
      const m = msg(14, true, 7, 'edited');
      m['edit_date'] = 234;
      const e = buildMessageEntry(m, usersOf());
      expect(e.editDate).assertEqual(234);
      expect(cloneMessage(e).editDate).assertEqual(234);
    });
    it('nearby_sender_messages_form_one_visual_run', 0, () => {
      const first = buildMessageEntry(msg(20, false, 7, 'one'), usersOf());
      const second = buildMessageEntry(msg(21, false, 7, 'two'), usersOf());
      first.date = 100;
      second.date = 160;
      const groups: AlbumGroup[] = collapseAlbums([first, second]);
      expect(groups[0].showSenderName).assertTrue();
      expect(groups[0].showAvatar).assertFalse();
      expect(groups[1].showSenderName).assertFalse();
      expect(groups[1].showAvatar).assertTrue();
    });
    it('distant_sender_messages_start_new_visual_runs', 0, () => {
      const first = buildMessageEntry(msg(22, false, 7, 'one'), usersOf());
      const second = buildMessageEntry(msg(23, false, 7, 'two'), usersOf());
      first.date = 100;
      second.date = 1000;
      const groups: AlbumGroup[] = collapseAlbums([first, second]);
      expect(groups[0].showAvatar).assertTrue();
      expect(groups[1].showSenderName).assertTrue();
    });
    it('hidden_rows_do_not_consume_visible_date_separator', 0, () => {
      const first = buildMessageEntry(msg(24, false, 7, 'one'), usersOf());
      const hidden = buildMessageEntry(msg(25, false, 7, 'hidden'), usersOf());
      const next = buildMessageEntry(msg(26, false, 7, 'next'), usersOf());
      first.date = 100;
      hidden.date = 90000;
      hidden.contentType = 'hidden';
      next.date = 90010;
      const groups: AlbumGroup[] = collapseAlbums([first, hidden, next]);
      expect(groups.length).assertEqual(2);
      expect(groups[1].head.id).assertEqual(26);
      expect(groups[1].dateLabel.length > 0).assertTrue();
    });
    it('sticker_transfer_state_keeps_the_lazy_row_key_stable', 0, () => {
      const sticker = buildMessageEntry(msg(27, false, 7, ''), usersOf());
      sticker.contentType = 'sticker';
      sticker.stickerFileId = 501;
      sticker.stickerFormat = 'tgs';
      const loadingKey = collapseAlbums([sticker])[0].key;
      const updated = cloneMessage(sticker);
      updated.stickerProgress = 65;
      const progressKey = collapseAlbums([updated])[0].key;
      updated.stickerFailed = true;
      const failedKey = collapseAlbums([updated])[0].key;
      expect(progressKey).assertEqual(loadingKey);
      expect(failedKey).assertEqual(progressKey);
    });
    it('member_self_join_and_leave_use_natural_service_copy', 0, () => {
      const joinContent: TdObject = { '@type': 'messageChatAddMembers' };
      joinContent['member_user_ids'] = [7];
      const join = buildMessageEntry(serviceMsg(30, 7, joinContent), usersOf());
      expect(join.contentType).assertEqual('system');
      expect(join.placeholderLabel).assertEqual('sm_joined_group(Ann)');
      expect(join.systemKind).assertEqual('people');

      const leaveContent: TdObject = { '@type': 'messageChatDeleteMember' };
      leaveContent['user_id'] = 7;
      const leave = buildMessageEntry(serviceMsg(31, 7, leaveContent), usersOf());
      expect(leave.placeholderLabel).assertEqual('sm_left_group(Ann)');
    });
    it('own_join_notice_uses_client_copy', 0, () => {
      const content: TdObject = { '@type': 'messageChatJoinByLink' };
      const join = buildMessageEntry(serviceMsg(311, 7, content, true), usersOf());
      expect(join.contentType).assertEqual('system');
      expect(join.placeholderLabel).assertEqual('cp_joined_group');
      expect(join.systemType).assertEqual('messageChatJoinByLink');
    });
    it('member_invite_includes_resolved_names', 0, () => {
      const content: TdObject = { '@type': 'messageChatAddMembers' };
      content['member_user_ids'] = [8];
      const entry = buildMessageEntry(serviceMsg(32, 7, content), usersOf());
      expect(entry.placeholderLabel).assertEqual('sm_invited_names(Ann,Bob)');
    });
    it('video_chat_end_includes_real_duration', 0, () => {
      const content: TdObject = { '@type': 'messageVideoChatEnded' };
      content['duration'] = 125;
      const entry = buildMessageEntry(serviceMsg(33, 7, content), usersOf());
      expect(entry.contentType).assertEqual('system');
      expect(entry.systemKind).assertEqual('call');
      expect(entry.placeholderLabel).assertEqual('sm_call_ended_after(unit_minutes(2,2))');
    });
    it('custom_service_text_is_preserved', 0, () => {
      const content: TdObject = { '@type': 'messageCustomServiceAction' };
      content['text'] = '群组规则已更新';
      const entry = buildMessageEntry(serviceMsg(34, 7, content), usersOf());
      expect(entry.contentType).assertEqual('system');
      expect(entry.placeholderLabel).assertEqual('群组规则已更新');
    });
    it('unknown_message_keeps_position_and_readable_fallback', 0, () => {
      const content: TdObject = { '@type': 'messageSomeFutureType' };
      const entry = buildMessageEntry(serviceMsg(35, 7, content), usersOf());
      expect(entry.contentType).assertEqual('other');
      expect(entry.isUnsupportedMessage).assertTrue();
      expect(entry.placeholderLabel).assertEqual('preview_unsupported');
    });
    it('content_protection_rejection_is_not_reported_as_a_change', 0, () => {
      const content: TdObject = { '@type': 'messageChatHasProtectedContentToggled' };
      content['request_message_id'] = 900;
      content['old_has_protected_content'] = true;
      content['new_has_protected_content'] = true;
      const entry = buildMessageEntry(serviceMsg(36, 7, content), usersOf());
      expect(entry.placeholderLabel).assertEqual('sm_protection_request_denied');
      expect(entry.systemKind).assertEqual('security');
    });
  });

  // 服务消息渲染成系统行，绝不该被当成"不支持的消息"。真机日志里 871 条
  // UNHANDLED_MSG 有 870 条是这么误报的（判据漏了 sys.label === ''）。
  describe('isUnsupportedMessage', () => {
    it('入群/链接入群/置顶都不算不支持', 0, (): void => {
      const types: string[] = [
        'messageChatAddMembers', 'messageChatJoinByLink', 'messagePinMessage',
        'messageChatDeleteMember', 'messageChatSetMessageAutoDeleteTime',
        'messageSupergroupChatCreate', 'messageChatUpgradeFrom'
      ];
      let id: number = 900;
      for (const t of types) {
        const content: TdObject = { '@type': t };
        content['member_user_ids'] = [8];
        content['user_id'] = 8;
        const entry = buildMessageEntry(serviceMsg(id, 7, content), usersOf());
        expect(entry.isUnsupportedMessage).assertFalse();
        expect(entry.contentType).assertEqual('system');
        id++;
      }
    });

    it('真正不认识的类型才算不支持', 0, (): void => {
      const content: TdObject = { '@type': 'messageSomethingFromTheFuture' };
      const entry = buildMessageEntry(serviceMsg(950, 7, content), usersOf());
      expect(entry.isUnsupportedMessage).assertTrue();
      expect(entry.contentType).assertEqual('other');
    });

    it('普通文本不算不支持', 0, (): void => {
      const entry = buildMessageEntry(msg(951, false, 7, 'hi'), usersOf());
      expect(entry.isUnsupportedMessage).assertFalse();
    });
  });
}
