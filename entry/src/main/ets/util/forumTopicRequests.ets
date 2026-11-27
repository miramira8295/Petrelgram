import { TdRequest } from '../tdkit/TdTypes';

// 新建/删除话题的请求（纯函数，有单测）。话题列表页和详情页的话题横条都会发。
// 返回 null = 参数不成立，调用方不要发。

// Bot 私聊点「+」后、尚未发出首条消息前的本地占位话题 id。
// 区别于 0（整段会话）与 >0（TDLib 真实 forum_topic_id）；退出或切走时不创建空话题。
export const PENDING_BOT_TOPIC_ID: number = -1;

// TDLib createForumTopic.name 限制：1–128 字符。
const TOPIC_NAME_MAX_LEN: number = 128;

function truncateTopicName(text: string): string {
  if (text.length <= TOPIC_NAME_MAX_LEN) {
    return text;
  }
  let end: number = TOPIC_NAME_MAX_LEN;
  // 避免在 UTF-16 代理对中间截断产生孤立高代理。
  const lastCode: number = text.charCodeAt(end - 1);
  if (lastCode >= 0xD800 && lastCode <= 0xDBFF) {
    end--;
  }
  return text.substring(0, end).trim();
}

// 为 Bot 私聊的隐式话题生成符合 TDLib 1–128 字符约束的初始名称：
// 优先取首条消息文本/说明，否则回退到调用方传入的本地化兜底（如「新话题」）。
export function implicitBotTopicName(hint: string, fallback: string): string {
  const cleanedHint: string = hint.replace(/\s+/g, ' ').trim();
  if (cleanedHint !== '') {
    const truncated: string = truncateTopicName(cleanedHint);
    if (truncated !== '') {
      return truncated;
    }
  }
  const cleanedFallback: string = fallback.replace(/\s+/g, ' ').trim();
  if (cleanedFallback !== '') {
    const truncated: string = truncateTopicName(cleanedFallback);
    if (truncated !== '') {
      return truncated;
    }
  }
  return 'New Topic';
}

export function forumTopicCreateRequest(
  chatId: number, name: string, isNameImplicit: boolean = false
): TdRequest | null {
  const trimmed: string = truncateTopicName(name.trim());
  if (chatId === 0 || trimmed === '') {
    return null;
  }
  const req: TdRequest = { '@type': 'createForumTopic' };
  req['chat_id'] = chatId;
  req['name'] = trimmed;
  if (isNameImplicit) {
    req['is_name_implicit'] = true;
  }
  return req;
}

export function botImplicitTopicCreateRequest(
  chatId: number, hint: string, fallback: string
): TdRequest | null {
  if (chatId === 0) {
    return null;
  }
  return forumTopicCreateRequest(chatId, implicitBotTopicName(hint, fallback), true);
}

export function forumTopicDeleteRequest(chatId: number, forumTopicId: number): TdRequest | null {
  if (chatId === 0 || forumTopicId <= 0) {
    return null;
  }
  const req: TdRequest = { '@type': 'deleteForumTopic' };
  req['chat_id'] = chatId;
  req['forum_topic_id'] = forumTopicId;
  return req;
}
