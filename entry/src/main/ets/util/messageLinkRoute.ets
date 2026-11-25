import { TdObject } from '../tdkit/TdTypes';

// Temporary link diagnostics: fixed fields only, never URL, text or full JSON.
// O(1) work per resolution; no message/window traversal.
export function messageLinkRouteDiagnostic(info: TdObject, route: Record<string, Object> | null): string {
  const chatId = (info['chat_id'] as number | undefined) ?? 0;
  const topic = info['topic_id'] as TdObject | undefined;
  const type = topic === undefined || topic === null ? 'none' :
    String(topic['@type'] ?? 'missing').slice(0, 64);
  const message = info['message'] as TdObject | undefined;
  const messageId = message === undefined || message === null ? 0 :
    ((message['id'] as number | undefined) ?? 0);
  let topicId: number = 0;
  let reason: string = 'ok';
  if (topic !== undefined && topic !== null) {
    switch (type) {
      case 'messageTopicThread': topicId = (topic['message_thread_id'] as number | undefined) ?? 0; break;
      case 'messageTopicForum': topicId = (topic['forum_topic_id'] as number | undefined) ?? 0; break;
      case 'messageTopicDirectMessages':
        topicId = (topic['direct_messages_chat_topic_id'] as number | undefined) ?? 0; break;
      default: reason = 'unsupported-topic'; break;
    }
    if (reason === 'ok' && (!Number.isSafeInteger(topicId) || topicId <= 0)) {
      reason = 'invalid-topic-id';
    }
  }
  if (!Number.isSafeInteger(chatId) || chatId === 0) { reason = 'invalid-chat-id'; }
  if (route !== null) {
    reason = Number.isSafeInteger(messageId) && messageId > 0 ? 'ok' : 'no-message';
  } else if (reason === 'ok') { reason = 'route-rejected'; }
  return `chat=${chatId} msg=${messageId} topic=${type} topicId=${topicId}` +
    ` accepted=${route !== null} reason=${reason}`;
}

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
