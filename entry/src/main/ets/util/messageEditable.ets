import { getTdClient } from '../tdkit/Globals';
import { TdObject, TdRequest, TdError } from '../tdkit/TdTypes';
import { logE } from './log';

// 「这条消息能不能编辑」的权威答案。
//
// 【为什么不能自己算】原来四处写的都是同一条启发式：
//     isOutgoing && (now - date) < 172800        // 48 小时
// 它至少在三种情形下是错的（issue #179「过早的消息无法编辑」）：
//
//   1. **频道帖子管理员可以无限期编辑**，根本没有 48 小时这条线——超时之后我们
//      就把「编辑」藏了，正是用户报的现象；
//   2. 频道里能编辑的帖子往往 `isOutgoing = false`（发出者是频道，不是你），
//      第一个条件就直接否掉了；
//   3. 反过来，48 小时内也有不能编辑的（转发来的、服务消息、某些投票），
//      我们照样显示，用户点了才失败。
//
// TDLib 有权威判据：`getMessageProperties` → `messageProperties.can_be_edited`。
// 这份数据在旧版里本来就是 `Message` 上的一个普通字段，新版把它挪进了按需查询的
// properties 里——**挪的是同一份本地计算，不是变成了网络调用**，所以量级是一次
// IPC 往返而不是网络 RTT。
//
// 【但设计上不依赖它快】菜单是同步构建的，答案来不及就先用旧的启发式，
// 到货之后菜单自己重绘（调用方把结果写进 @Local）。最坏情况 = 与现状一致，
// 中间没有"菜单卡住等网络"这一档。

// 会话内缓存：同一条消息长按第二次直接命中，不再发请求。
// 值只有三态：未知（不在表里）/ 能 / 不能。
const cache: Map<number, boolean> = new Map<number, boolean>();
// 在途去重：菜单重绘会再问一遍，别叠着发。
const inFlight: Set<number> = new Set<number>();

// 缓存里的答案。undefined = 还不知道，调用方退回启发式。
export function editableCached(messageId: number): boolean | undefined {
  return cache.get(messageId);
}

// 换会话时清空：messageId 在别的会话里是另一条消息。
// 由 ChatPage 在切会话时调用（和其它按会话作用域的缓存同一时机）。
export function clearEditableCache(): void {
  cache.clear();
  inFlight.clear();
}

// 供单测用：喂一个已知答案进去，不碰 TDLib。
export function seedEditableForTest(messageId: number, editable: boolean): void {
  cache.set(messageId, editable);
}

// 问一次并缓存。已经知道答案、或正在问的，直接返回不重复发。
// onResolved 只在**这一次真的拿到新答案**时回调，调用方据此触发重绘。
export function ensureEditable(chatId: number, messageId: number,
  onResolved: (editable: boolean) => void): void {
  if (chatId === 0 || messageId <= 0) {
    return;
  }
  if (cache.has(messageId) || inFlight.has(messageId)) {
    return;
  }
  inFlight.add(messageId);
  const req: TdRequest = { '@type': 'getMessageProperties' };
  req['chat_id'] = chatId;
  req['message_id'] = messageId;
  getTdClient().send(req, 10000).then((props: TdObject): void => {
    inFlight.delete(messageId);
    const editable: boolean = (props['can_be_edited'] as boolean | undefined) ?? false;
    cache.set(messageId, editable);
    onResolved(editable);
  }).catch((e: TdError): void => {
    inFlight.delete(messageId);
    // 查不到就一直退回启发式，不缓存 false——否则一次网络抖动会把「编辑」
    // 永久藏起来，比现状更糟。
    logE(`messageEditable(${messageId}) failed: ${e.message}`);
  });
}
