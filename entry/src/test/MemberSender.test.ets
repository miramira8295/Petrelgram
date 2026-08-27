import { describe, expect, it } from '@ohos/hypium';
import { TdObject } from '../main/ets/tdkit/TdTypes';
import {
  MEMBER_SENDER_CHAT, MEMBER_SENDER_UNKNOWN, MEMBER_SENDER_USER, MemberSenderRef,
  describeMemberSender, memberSenderUserId, readMemberSender
} from '../main/ets/util/memberSender';

function userSender(id: number): TdObject {
  const o: TdObject = { '@type': 'messageSenderUser' };
  o['user_id'] = id;
  return o;
}

function chatSender(id: number): TdObject {
  const o: TdObject = { '@type': 'messageSenderChat' };
  o['chat_id'] = id;
  return o;
}

export default function memberSenderTest() {
  describe('memberSender', () => {
    it('普通成员取到 user_id', 0, () => {
      const ref: MemberSenderRef = readMemberSender(userSender(777000));
      expect(ref.kind).assertEqual(MEMBER_SENDER_USER);
      expect(ref.id).assertEqual(777000);
      expect(memberSenderUserId(userSender(777000))).assertEqual(777000);
    });

    it('机器人成员跟普通成员同一支——member_id 里没有机器人标记', 0, () => {
      // 机器人是 user.type = userTypeBot 的用户，member_id 仍是 messageSenderUser。
      // 这条用例锁住的正是"踢机器人静默失败"那次排查的结论：标识没问题。
      const bot: TdObject = userSender(1234567890);
      expect(readMemberSender(bot).kind).assertEqual(MEMBER_SENDER_USER);
      expect(memberSenderUserId(bot)).assertEqual(1234567890);
    });

    it('匿名管理员是 chat 形态，chat_id 是负数也要留住', 0, () => {
      const ref: MemberSenderRef = readMemberSender(chatSender(-1001234567890));
      expect(ref.kind).assertEqual(MEMBER_SENDER_CHAT);
      expect(ref.id).assertEqual(-1001234567890);
      // 但它不是 user，不能当 user_id 用。
      expect(memberSenderUserId(chatSender(-1001234567890))).assertEqual(0);
    });

    it('缺字段/未知类型/undefined 一律 unknown + 0，绝不冒充 user', 0, () => {
      expect(readMemberSender(undefined).kind).assertEqual(MEMBER_SENDER_UNKNOWN);
      expect(readMemberSender(undefined).id).assertEqual(0);
      const weird: TdObject = { '@type': 'messageSenderSomethingElse' };
      expect(readMemberSender(weird).kind).assertEqual(MEMBER_SENDER_UNKNOWN);
      const noType: TdObject = {};
      noType['user_id'] = 42;
      expect(readMemberSender(noType).kind).assertEqual(MEMBER_SENDER_UNKNOWN);
      expect(memberSenderUserId(noType)).assertEqual(0);
    });

    it('坏掉的 user_id 判 0，不让 0 流到调用方的守卫里', 0, () => {
      expect(readMemberSender(userSender(0)).id).assertEqual(0);
      expect(readMemberSender(userSender(-5)).id).assertEqual(0);
      const missing: TdObject = { '@type': 'messageSenderUser' };
      expect(readMemberSender(missing).id).assertEqual(0);
      expect(readMemberSender(chatSender(0)).id).assertEqual(0);
    });

    it('日志描述短且带类型', 0, () => {
      expect(describeMemberSender(readMemberSender(userSender(7)))).assertEqual('user:7');
      expect(describeMemberSender(readMemberSender(undefined))).assertEqual('unknown:0');
    });
  });
}
