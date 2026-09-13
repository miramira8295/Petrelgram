import { TdRequest } from '../tdkit/TdTypes';

// TDLib only applies remove_caption to copied media. Keep that dependency at
// the request boundary as well as in the UI so a stale/invalid view state can
// never emit a combination TDLib silently ignores.
const CAPTION_CONTENT_TYPES: string[] = [
  'photo', 'video', 'file', 'audio', 'voice', 'paidMedia'
];

export interface ForwardMessagesRequestInput {
  toChatId: number;
  fromChatId: number;
  messageIds: number[];
  threadRootId: number;
  sendCopy: boolean;
  removeCaption: boolean;
  canRemoveCaption: boolean;
}

export interface ForwardCaptionCandidate {
  id: number;
  contentType: string;
  text: string;
}

export function forwardCaptionRemovable(contentType: string, text: string): boolean {
  return text.trim() !== '' && CAPTION_CONTENT_TYPES.indexOf(contentType) >= 0;
}

export function selectionHasRemovableForwardCaption(
  messages: ForwardCaptionCandidate[], messageIds: number[]
): boolean {
  for (const message of messages) {
    if (messageIds.indexOf(message.id) >= 0 &&
      forwardCaptionRemovable(message.contentType, message.text)) {
      return true;
    }
  }
  return false;
}

export function normalizedForwardMessageIds(messageIds: number[]): number[] {
  return [...messageIds]
    .sort((a: number, b: number): number => a - b)
    .filter((id: number, index: number, ids: number[]): boolean =>
      index === 0 || id !== ids[index - 1]);
}

export function buildForwardMessagesRequest(input: ForwardMessagesRequestInput): TdRequest | null {
  const ids: number[] = normalizedForwardMessageIds(input.messageIds);
  if (input.toChatId === 0 || input.fromChatId === 0 || ids.length === 0) {
    return null;
  }
  const req: TdRequest = { '@type': 'forwardMessages' };
  req['chat_id'] = input.toChatId;
  req['message_thread_id'] = input.toChatId === input.fromChatId ? input.threadRootId : 0;
  req['from_chat_id'] = input.fromChatId;
  req['message_ids'] = ids;
  req['send_copy'] = input.sendCopy;
  req['remove_caption'] = input.sendCopy && input.canRemoveCaption && input.removeCaption;
  return req;
}

// TDLib 单次 forwardMessages 最多 100 条（超了在发送时才报错，issue #189 追加 3）。
// 按 100 一批切开，顺序不变、每批字段一致；调用方顺序发送。
export const FORWARD_BATCH_MAX: number = 100;

export function buildForwardMessagesRequests(input: ForwardMessagesRequestInput): TdRequest[] {
  const whole: TdRequest | null = buildForwardMessagesRequest(input);
  if (whole === null) {
    return [];
  }
  const ids: number[] = whole['message_ids'] as number[];
  const out: TdRequest[] = [];
  for (let start = 0; start < ids.length; start += FORWARD_BATCH_MAX) {
    const batch: TdRequest = { '@type': 'forwardMessages' };
    batch['chat_id'] = whole['chat_id'];
    batch['message_thread_id'] = whole['message_thread_id'];
    batch['from_chat_id'] = whole['from_chat_id'];
    batch['message_ids'] = ids.slice(start, start + FORWARD_BATCH_MAX);
    batch['send_copy'] = whole['send_copy'];
    batch['remove_caption'] = whole['remove_caption'];
    out.push(batch);
  }
  return out;
}
