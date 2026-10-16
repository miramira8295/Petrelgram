import { TdObject, TdRequest, TdError } from '../tdkit/TdTypes';
import { ForwardMessagesRequestInput, buildForwardMessagesRequests } from './forwardMessagesRequest';

// 发送选项属于任务快照；各目标保留未完成批次，重试不重放成功的消息。
export class ForwardSendTask {
  private input: ForwardMessagesRequestInput;
  private pending: Map<number, TdRequest[]> = new Map<number, TdRequest[]>();
  private uncertain: Set<number> = new Set<number>();

  constructor(input: ForwardMessagesRequestInput) {
    this.input = { toChatId: 0, fromChatId: input.fromChatId, messageIds: input.messageIds.slice(),
      threadRootId: input.threadRootId, sendCopy: input.sendCopy,
      removeCaption: input.removeCaption, canRemoveCaption: input.canRemoveCaption };
  }

  hasUncertain(): boolean { return this.uncertain.size > 0; }

  sourceChatId(): number { return this.input.fromChatId; }

  remainingMessageIds(chatId: number): number[] {
    const batches: TdRequest[] | undefined = this.pending.get(chatId);
    if (batches === undefined) { return this.input.messageIds.slice(); }
    const ids: number[] = [];
    for (const batch of batches) { ids.push(...batch['message_ids'] as number[]); }
    return ids;
  }

  async send(chatId: number, port: (request: TdRequest) => Promise<TdObject>,
    active: () => boolean = (): boolean => true): Promise<void> {
    if (this.uncertain.has(chatId)) { throw new TdError(-1, 'send result unknown'); }
    let batches: TdRequest[] | undefined = this.pending.get(chatId);
    if (batches === undefined) {
      const input: ForwardMessagesRequestInput = { toChatId: chatId,
        fromChatId: this.input.fromChatId, messageIds: this.input.messageIds,
        threadRootId: this.input.threadRootId, sendCopy: this.input.sendCopy,
        removeCaption: this.input.removeCaption, canRemoveCaption: this.input.canRemoveCaption };
      batches = buildForwardMessagesRequests(input);
      this.pending.set(chatId, batches);
    }
    while (batches.length > 0) {
      if (!active()) { throw new Error('forward session ended'); }
      const request = batches[0];
      try {
        const result: TdObject = await port(request);
        const ids: number[] = request['message_ids'] as number[];
        const sent = (result['messages'] as (TdObject | null)[] | undefined) ?? [];
        // TDLib 对无法转发的源消息可返回 null；只记成功的索引，不能把整批计成功。
        const remaining: number[] = ids.filter((_id: number, i: number): boolean =>
          sent[i] === null || sent[i] === undefined || (sent[i]!['id'] as number ?? 0) === 0);
        if (remaining.length > 0) {
          request['message_ids'] = remaining;
          throw new Error('some messages were not forwarded');
        }
        batches.shift();
      } catch (error) {
        if ((error as TdError).code === -1) { this.uncertain.add(chatId); }
        throw error as Error;
      }
    }
  }
}
