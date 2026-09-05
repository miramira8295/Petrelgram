// Live "typing…" from peers (updateChatAction). Entries expire after 6s —
// TDLib sends chatActionCancel, but a dropped cancel must not stick forever.
//
// 这里只放"给定字段算结果"的那部分：过滤/解析一条 updateChatAction、到期裁剪、
// 文案合成。副作用留在 ChatPage 的薄包装里——`getUserStore().ensure(uid)`、
// 1500ms 的 setInterval 轮询、写 @Local typingLabel。
//
// 依赖只有 messageTopicScope（同为纯 util）与 strings（单测可 installStrings
// 换成假实现），不碰 ArkUI 类型，所以本地单测能直接跑。

import { TdObject } from '../tdkit/TdTypes';
import { messageOutsideTopicScope } from './messageTopicScope';
import { plural, str } from './strings';

// 一条 chatAction 的有效期。TDLib 侧 chatAction 本身就是"最多维持几秒"的瞬时
// 状态：正常情况下对端停手会补一条 chatActionCancel，但那条 cancel 可能因为
// 断线/丢更新而永远不到。到期时间戳让"正在输入…"最迟 6s 后自己消失，而不是
// 一直挂在输入栏占位符上。
export const TYPING_ACTION_TTL_MS: number = 6000;

// 处理一条 updateChatAction，就地更新 senders（uid → 到期时间戳）。
//
// 返回受影响的 uid；0 表示这条更新被忽略（不是本会话/本话题、发送方不是用户、
// uid 非法），调用方应当原样早退，既不重建文案也不启动轮询定时器。
//
// **cancel 与 typing 的区分交给调用方看 map**：本函数返回后 `senders.has(uid)`
// 为 true 即"记下了一次输入"（页面这时才 `getUserStore().ensure(uid)`），为
// false 即 chatActionCancel 把它删掉了。原代码里 ensure 只在非 cancel 分支、
// 且紧跟在 set 之后，这个顺序保持不变。
//
// 【话题作用域判定放在本函数内】原代码的守卫是
//   (forumTopicId > 0 || directMessagesTopicId > 0) && messageOutsideTopicScope(...)
// 逐字搬进来，而不是让调用方先判再调：messageOutsideTopicScope 本身就是纯
// util，搬进来不引入任何新依赖，却能让"threadRootId 单独存在时**不**过滤"这条
// 容易被顺手'简化'掉的细节被单测钉住——外层的 || 只看 forum/direct 两个 id，
// 纯话题（thread）会话里的 chatAction 是不做话题过滤的。
export function applyTypingUpdate(senders: Map<number, number>, update: TdObject, nowMs: number,
  chatId: number, threadRootId: number, forumTopicId: number, directMessagesTopicId: number): number {
  if (((update['chat_id'] as number | undefined) ?? 0) !== chatId) {
    return 0;
  }
  if ((forumTopicId > 0 || directMessagesTopicId > 0) &&
    messageOutsideTopicScope(update, threadRootId, forumTopicId, directMessagesTopicId)) {
    return 0;
  }
  const sender = update['sender_id'] as TdObject | undefined;
  if (sender === undefined || sender['@type'] !== 'messageSenderUser') {
    return 0;
  }
  const uid = (sender['user_id'] as number | undefined) ?? 0;
  if (uid <= 0) {
    return 0;
  }
  const action = update['action'] as TdObject | undefined;
  const actionType = action !== undefined ? ((action['@type'] as string | undefined) ?? '') : '';
  if (actionType === 'chatActionCancel') {
    senders.delete(uid);
  } else {
    senders.set(uid, nowMs + TYPING_ACTION_TTL_MS);
  }
  return uid;
}

// 清掉已过期的项，返回是否真的删掉了什么（调用方据此决定要不要重建文案）。
//
// 判据是 `到期时间戳 < nowMs`，与原轮询回调逐字一致：正好等于 nowMs 的那一条
// 还留着，下一轮才走。
export function pruneExpiredTyping(senders: Map<number, number>, nowMs: number): boolean {
  let changed = false;
  // 先快照 keys 再删：边遍历边 delete 同一个 Map 不是这里想赌的行为。
  for (const key of Array.from(senders.keys())) {
    if ((senders.get(key) ?? 0) < nowMs) {
      senders.delete(key);
      changed = true;
    }
  }
  return changed;
}

// 合成输入栏占位符里的那句话（不是顶栏副标题，见 ChatPage.composerPlaceholder）。
//
// 三档文案，原样保留：
//  · 私聊/密聊只说"正在输入…"——对面是谁本来就写在顶栏，再报一次名字是废话；
//  · 群里多人时走 plural（英文 1/n 两种形式，中文一种，交给 plural.json 挑）；
//  · 群里一人时报名字的第一段（split(' ')[0]），名字取不到时退到"某人"。
//
// displayName 做成回调：纯函数因此不依赖 UserStore，单测直接给一张假名字表。
export function typingLabelOf(headerKind: string, ids: number[],
  displayName: (uid: number) => string): string {
  if (ids.length === 0) {
    return '';
  }
  if (headerKind === 'private' || headerKind === 'secret') {
    return str('cp_typing');
  }
  if (ids.length > 1) {
    return plural('cp_n_typing', ids.length, ids.length);
  }
  const name = displayName(ids[0]);
  return str('cp_someone_typing', name !== '' ? name.split(' ')[0] : str('cp_someone'));
}
