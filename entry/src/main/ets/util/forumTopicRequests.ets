import { TdRequest } from '../tdkit/TdTypes';

// 新建/删除话题的请求（纯函数，有单测）。话题列表页和详情页的话题横条都会发。
// 返回 null = 参数不成立，调用方不要发。

export function forumTopicCreateRequest(chatId: number, name: string): TdRequest | null {
  const trimmed: string = name.trim();
  if (chatId === 0 || trimmed === '') {
    return null;
  }
  const req: TdRequest = { '@type': 'createForumTopic' };
  req['chat_id'] = chatId;
  req['name'] = trimmed;
  return req;
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
