import { describe, it, expect } from '@ohos/hypium';
import { ChatEntry } from '../main/ets/store/ChatEntry';
import {
  ShareTarget, SHARE_SNAPSHOT_VERSION,
  orderShareTargets, pushRecentOutgoing, serializeShareTargets, parseShareTargets
} from '../main/ets/util/shareTargets';

// 系统分享的目标名单。用户对顺序有明确要求：**第一个必须是我的收藏**，
// 后面按"最近我主动聊天的会话"。这一组把这条顺序钉死。

function chat(id: number, title: string, date: number, saved: boolean = false): ChatEntry {
  return {
    id: id, revision: 0, title: title, isMuted: false, usesDefaultMute: true,
    unreadCount: 0, rawUnreadCount: 0, lastReadInboxId: 0,
    lastMessageText: '', lastMessageDate: date, lastMessageId: 0,
    lastSenderName: '', photoFileId: 0, avatarPath: '', initials: title.substring(0, 1),
    autoDeleteTime: 0, kind: 'private', isMarkedUnread: false,
    canDeleteOnlyForSelf: true, canDeleteForAllUsers: false,
    isSavedMessages: saved, background: null, themeName: '',
    liveGroupCallId: 0, isLive: false, isRtmpLive: false
  };
}

function ids(targets: ShareTarget[]): number[] {
  return targets.map((t: ShareTarget): number => t.chatId);
}

export default function shareTargetsTest() {
  describe('shareTargets', () => {

    // ---- pushRecentOutgoing ----

    it('最近表：新的在最前', 0, (): void => {
      expect(pushRecentOutgoing([2, 3], 1).join(',')).assertEqual('1,2,3');
    });

    it('最近表：重复发同一个会话只保留一份，且提到最前', 0, (): void => {
      expect(pushRecentOutgoing([1, 2, 3], 3).join(',')).assertEqual('3,1,2');
    });

    it('最近表：不修改原数组（不可变）', 0, (): void => {
      const before: number[] = [1, 2];
      pushRecentOutgoing(before, 9);
      expect(before.join(',')).assertEqual('1,2');
    });

    it('最近表：定长截断', 0, (): void => {
      expect(pushRecentOutgoing([1, 2, 3, 4], 9, 3).join(',')).assertEqual('9,1,2');
    });

    it('最近表：chatId 为 0 时原样返回', 0, (): void => {
      expect(pushRecentOutgoing([1], 0).join(',')).assertEqual('1');
    });

    // ---- orderShareTargets ----

    it('收藏永远排第一——哪怕它最久没说话', 0, (): void => {
      const chats: ChatEntry[] = [
        chat(10, 'A', 900), chat(20, 'B', 800), chat(99, '我的收藏', 1, true)
      ];
      expect(ids(orderShareTargets(chats, [10, 20]))[0]).assertEqual(99);
    });

    it('收藏之后按"我主动聊过"的顺序，不是按最后消息时间', 0, (): void => {
      // B 的最后消息更新，但我最近主动发的是 A
      const chats: ChatEntry[] = [
        chat(10, 'A', 100), chat(20, 'B', 999), chat(99, 'Saved', 1, true)
      ];
      expect(ids(orderShareTargets(chats, [10, 20])).join(',')).assertEqual('99,10,20');
    });

    it('收藏不会因为也在最近表里而出现两次', 0, (): void => {
      const chats: ChatEntry[] = [chat(99, 'Saved', 1, true), chat(10, 'A', 100)];
      expect(ids(orderShareTargets(chats, [99, 10])).join(',')).assertEqual('99,10');
    });

    it('最近表里已经不存在的会话被跳过（会话已删除）', 0, (): void => {
      const chats: ChatEntry[] = [chat(10, 'A', 100)];
      expect(ids(orderShareTargets(chats, [777, 10])).join(',')).assertEqual('10');
    });

    it('最近表为空时兜底用会话列表，按最后消息时间从新到旧', 0, (): void => {
      const chats: ChatEntry[] = [chat(10, 'A', 100), chat(20, 'B', 999), chat(30, 'C', 500)];
      expect(ids(orderShareTargets(chats, [])).join(',')).assertEqual('20,30,10');
    });

    it('兜底段不重复已进名单的会话', 0, (): void => {
      const chats: ChatEntry[] = [chat(10, 'A', 100), chat(20, 'B', 999)];
      expect(ids(orderShareTargets(chats, [10])).join(',')).assertEqual('10,20');
    });

    it('占位条目（id=0）不进名单', 0, (): void => {
      const chats: ChatEntry[] = [chat(0, '占位', 999), chat(10, 'A', 1)];
      expect(ids(orderShareTargets(chats, [])).join(',')).assertEqual('10');
    });

    it('数量封顶', 0, (): void => {
      const chats: ChatEntry[] = [chat(1, 'A', 3), chat(2, 'B', 2), chat(3, 'C', 1)];
      expect(orderShareTargets(chats, [], 2).length).assertEqual(2);
    });

    it('limit 为 0 时返回空', 0, (): void => {
      expect(orderShareTargets([chat(1, 'A', 1)], [], 0).length).assertEqual(0);
    });

    it('不修改传入的会话数组顺序（兜底段要排序）', 0, (): void => {
      const chats: ChatEntry[] = [chat(10, 'A', 100), chat(20, 'B', 999)];
      orderShareTargets(chats, []);
      expect(chats[0].id).assertEqual(10);
    });

    // ---- 序列化 ----

    it('往返：写出去再读回来完全一致', 0, (): void => {
      const chats: ChatEntry[] = [chat(99, 'Saved', 1, true), chat(10, '阿三', 100)];
      const targets: ShareTarget[] = orderShareTargets(chats, [10]);
      const back: ShareTarget[] = parseShareTargets(serializeShareTargets(targets));
      expect(back.length).assertEqual(2);
      expect(back[0].chatId).assertEqual(99);
      expect(back[0].isSavedMessages).assertTrue();
      expect(back[1].title).assertEqual('阿三');
    });

    it('版本不符当作没有快照', 0, (): void => {
      const bad: string = `{"version":${SHARE_SNAPSHOT_VERSION + 1},"targets":[{"chatId":1}]}`;
      expect(parseShareTargets(bad).length).assertEqual(0);
    });

    it('坏 JSON 不抛异常，返回空', 0, (): void => {
      expect(parseShareTargets('{截断的').length).assertEqual(0);
      expect(parseShareTargets('').length).assertEqual(0);
      expect(parseShareTargets('null').length).assertEqual(0);
    });

    it('targets 不是数组时返回空', 0, (): void => {
      expect(parseShareTargets(`{"version":${SHARE_SNAPSHOT_VERSION},"targets":"x"}`).length)
        .assertEqual(0);
    });

    it('单行缺字段时跳过该行而不是整份作废', 0, (): void => {
      const text: string =
        `{"version":${SHARE_SNAPSHOT_VERSION},"targets":[{"title":"没有id"},{"chatId":7}]}`;
      const back: ShareTarget[] = parseShareTargets(text);
      expect(back.length).assertEqual(1);
      expect(back[0].chatId).assertEqual(7);
      expect(back[0].title).assertEqual('');
    });
  });
}
