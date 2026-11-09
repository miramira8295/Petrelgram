// 会话一条消息都没有时，那张卡片上写什么。
//
// 三个维度交叉：是不是话题（评论区）、成员身份（可写/待加入/被挡/确认中）、
// 会话类型（频道/群/单聊）。抽出来是因为三者的**优先级**不一样，而且标题和
// 副标题的优先级并不相同——话题在标题里最高，在副标题里也最高；但"被挡"在
// 标题里排第二，在副标题里却排在"待加入"之后。这种不对称写在两串 if 里没人
// 看得出来，只有并排测才说得清。
//
// 返回 str() 的结果：宿主单测里没装文案源，str() 原样返回 key，于是断言落在
// "选了哪条文案"上而不是文案本身。

import { str } from './strings';

export function emptyHistoryTitle(
  threadRootId: number, membershipState: string, isChannel: boolean, isGroup: boolean
): string {
  if (threadRootId > 0) {
    return str('cp_no_replies');
  }
  if (membershipState === 'blocked') {
    return str('cp_cannot_show');
  }
  if (isChannel) {
    return str('cp_channel_empty');
  }
  if (isGroup) {
    return str('cp_group_empty');
  }
  return str('cp_no_messages');
}

export function emptyHistoryIcon(
  threadRootId: number, membershipState: string
): string {
  if (membershipState === 'blocked') {
    return 'sys.symbol.lock_fill';
  }
  if (membershipState === 'joinable') {
    return 'sys.symbol.person_badge_plus';
  }
  if (threadRootId > 0) {
    return 'sys.symbol.arrowshape_turn_up_left';
  }
  return 'sys.symbol.message';
}

export function emptyHistoryHint(
  threadRootId: number, membershipState: string, isChannel: boolean, isGroup: boolean
): string {
  if (threadRootId > 0) {
    return membershipState === 'writable' ? str('cp_send_first_reply') : str('cp_no_replies_sub');
  }
  if (membershipState === 'joinable') {
    return str('cp_join_to_chat');
  }
  if (membershipState === 'blocked') {
    return str('cp_maybe_removed');
  }
  if (membershipState === 'checking') {
    return str('cp_confirming_membership');
  }
  if (isChannel) {
    return str('cp_posts_appear_here');
  }
  if (isGroup) {
    return str('cp_send_first_group');
  }
  return str('cp_send_to_start');
}
