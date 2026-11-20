import { TdObject } from '../tdkit/TdTypes';

// TDLib already resolves channel/discussion message IDs and private-link access.
// Preserve its destination topic; never infer a thread from the current page,
// URL path depth, or the linked message's own thread membership.
export function messageLinkRoute(info: TdObject): Record<string, Object> | null {
  const chatId = (info['chat_id'] as number | undefined) ?? 0;
  if (!Number.isSafeInteger(chatId) || chatId === 0) { return null; }
  const params: Record<string, Object> = { 'chatId': chatId };
  const topic = info['topic_id'] as TdObject | undefined;
  if (topic !== undefined && topic !== null) {
    let key: string = '';
    let field: string = '';
    switch (topic['@type']) {
      case 'messageTopicThread': key = 'threadRootId'; field = 'message_thread_id'; break;
      case 'messageTopicForum': key = 'forumTopicId'; field = 'forum_topic_id'; break;
      case 'messageTopicDirectMessages': key = 'directMessagesTopicId'; field = 'direct_messages_chat_topic_id'; break;
      default: return null; // Do not silently open a different scope for unknown topic types.
    }
    const id = (topic[field] as number | undefined) ?? 0;
    if (!Number.isSafeInteger(id) || id <= 0) { return null; }
    params[key] = id;
  }
  const message = info['message'] as TdObject | undefined;
  const messageId = message !== undefined && message !== null ?
    (message['id'] as number | undefined) ?? 0 : 0;
  if (Number.isSafeInteger(messageId) && messageId > 0) { params['jumpTo'] = messageId; }
  return params;
}
