import { TdClient } from '../tdkit/TdClient';
import { TdObject, TdRequest, TdError } from '../tdkit/TdTypes';
import { logE } from '../util/log';

// 不经过选择面板、直接转发到某个已知会话。
//
// 「保存消息」（转到收藏）和「复读」（转回本群）都不需要让用户再选一次目标，
// 但它们和 ForwardSheet 面对的是同一个 TDLib 约束，所以那条约束在这里必须
// 原样再守一遍——**不能因为"我这儿只有一条消息"就省掉**：相册是一次多条，
// 而且将来多选也可能接进来。
//
// TDLib 原话：「Message identifiers must be in a strictly increasing order」。
// 多选是按点击顺序攒的，从下往上选就是递减，请求会被直接拒掉。
export function forwardDirect(
  client: TdClient,
  fromChatId: number,
  toChatId: number,
  messageIds: number[],
  threadRootId: number,
  // true = 发副本，不带"转发自"抬头（「复读」要的就是这个效果）。
  // false = 普通转发，保留来源（「保存消息」用这个：进了收藏之后还得认得出
  // 它是谁在哪儿说的，抬头就是那条线索）。
  asCopy: boolean
): Promise<number> {
  const ids: number[] = [...messageIds]
    .sort((a: number, b: number): number => a - b)
    .filter((id: number, i: number, arr: number[]): boolean => i === 0 || id !== arr[i - 1]);
  if (ids.length === 0 || toChatId === 0) {
    return Promise.resolve(0);
  }
  const req: TdRequest = { '@type': 'forwardMessages' };
  req['chat_id'] = toChatId;
  // 只有转回**同一个会话**时才带话题：跨会话带过去的话题号在目标会话里没有意义。
  // 这一条与 ForwardSheet 的判断保持一致。
  req['message_thread_id'] = toChatId === fromChatId ? threadRootId : 0;
  req['from_chat_id'] = fromChatId;
  req['message_ids'] = ids;
  // send_copy=true 让 TDLib 发一份**副本**而不是转发：没有"转发自"抬头，
  // 看上去就是你自己说的——这正是群里"复读"要的效果。
  //
  // 两个已知限制，都由服务端裁决，这里只负责把失败如实报出去：
  //   · 源会话开了"禁止保存内容"时，send_copy 会被拒（普通转发也一样）；
  //   · 投票之类的消息类型副本语义不同（会创建一个新投票），TDLib 自己处理。
  // remove_caption 保持 false：复读一张带说明的图，说明也该跟着。
  req['send_copy'] = asCopy;
  req['remove_caption'] = false;
  return client.send(req).then((result: TdObject): number => {
    const sent = (result['messages'] as TdObject[] | undefined) ?? [];
    return sent.length;
  }).catch((e: TdError): number => {
    logE(`forwardDirect to=${toChatId} failed: ${e.message}`);
    return 0;
  });
}
