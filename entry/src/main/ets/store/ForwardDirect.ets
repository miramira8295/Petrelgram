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
  threadRootId: number
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
  // send_copy=false 保留"转发自"抬头。「复读」按理该去掉抬头（那才是复读），
  // 但去掉之后就是伪造他人发言的原创副本；保留来源是更诚实的默认，
  // 也和官方客户端的转发一致。
  req['send_copy'] = false;
  req['remove_caption'] = false;
  return client.send(req).then((result: TdObject): number => {
    const sent = (result['messages'] as TdObject[] | undefined) ?? [];
    return sent.length;
  }).catch((e: TdError): number => {
    logE(`forwardDirect to=${toChatId} failed: ${e.message}`);
    return 0;
  });
}
