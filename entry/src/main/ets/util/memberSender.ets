import { TdObject } from '../tdkit/TdTypes';

// chatMember.member_id 是 MessageSender，有两种形态：
//   messageSenderUser —— 普通用户**和机器人**都走这一支（机器人就是
//     user.type = userTypeBot 的用户，member_id 里没有任何特殊标记）；
//   messageSenderChat —— 匿名管理员、以频道身份入群的那种成员。
//
// 取标识这一步必须显式区分：把两者混在一起读 'user_id' 会在 chat 形态上
// 静默拿到 0，调用方再拿 0 去做守卫判断，整条操作就会无声地消失。

export const MEMBER_SENDER_USER: string = 'user';
export const MEMBER_SENDER_CHAT: string = 'chat';
export const MEMBER_SENDER_UNKNOWN: string = 'unknown';

export interface MemberSenderRef {
  // MEMBER_SENDER_USER / MEMBER_SENDER_CHAT / MEMBER_SENDER_UNKNOWN
  kind: string;
  // user_id 或 chat_id；取不到合法值时为 0。
  id: number;
}

// user_id 必须是正数：TDLib 不会给 0 或负的 user_id，出现就说明这条数据坏了。
function positiveId(raw: Object | undefined): number {
  const n: number = (raw as number | undefined) ?? 0;
  return typeof n === 'number' && isFinite(n) && n > 0 ? n : 0;
}

// chat_id 反过来——超级群/频道的 id 本来就是负数，只能排掉 0。
function nonZeroId(raw: Object | undefined): number {
  const n: number = (raw as number | undefined) ?? 0;
  return typeof n === 'number' && isFinite(n) ? n : 0;
}

export function readMemberSender(sender: TdObject | undefined): MemberSenderRef {
  if (sender === undefined) {
    return { kind: MEMBER_SENDER_UNKNOWN, id: 0 };
  }
  const type: string = (sender['@type'] as string | undefined) ?? '';
  if (type === 'messageSenderUser') {
    return { kind: MEMBER_SENDER_USER, id: positiveId(sender['user_id']) };
  }
  if (type === 'messageSenderChat') {
    return { kind: MEMBER_SENDER_CHAT, id: nonZeroId(sender['chat_id']) };
  }
  return { kind: MEMBER_SENDER_UNKNOWN, id: 0 };
}

// 便捷形式：只有用户（含机器人）成员才给出 user_id，其余一律 0。
export function memberSenderUserId(sender: TdObject | undefined): number {
  const ref: MemberSenderRef = readMemberSender(sender);
  return ref.kind === MEMBER_SENDER_USER ? ref.id : 0;
}

// 供日志用的简短描述，别把整条 TdObject 打进日志。
export function describeMemberSender(ref: MemberSenderRef): string {
  return `${ref.kind}:${ref.id}`;
}
