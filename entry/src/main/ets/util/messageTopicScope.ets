import { TdObject, TdRequest } from '../tdkit/TdTypes';

export function messageTopicObject(
  threadRootId: number, forumTopicId: number, directMessagesTopicId: number
): TdObject | undefined {
  if (directMessagesTopicId > 0) {
    const topic: TdObject = { '@type': 'messageTopicDirectMessages' };
    topic['direct_messages_chat_topic_id'] = directMessagesTopicId;
    return topic;
  }
  if (forumTopicId > 0) {
    const topic: TdObject = { '@type': 'messageTopicForum' };
    topic['forum_topic_id'] = forumTopicId;
    return topic;
  }
  if (threadRootId > 0) {
    const topic: TdObject = { '@type': 'messageTopicThread' };
    topic['message_thread_id'] = threadRootId;
    return topic;
  }
  return undefined;
}

export function applyMessageTopicScope(
  request: TdRequest, threadRootId: number, forumTopicId: number,
  directMessagesTopicId: number
): void {
  const topic = messageTopicObject(threadRootId, forumTopicId, directMessagesTopicId);
  if (topic !== undefined) {
    request['topic_id'] = topic;
  }
}

export function messageOutsideTopicScope(
  message: TdObject, threadRootId: number, forumTopicId: number,
  directMessagesTopicId: number
): boolean {
  if (directMessagesTopicId > 0) {
    const topic = message['topic_id'] as TdObject | undefined;
    return topic === undefined ||
      ((topic['direct_messages_chat_topic_id'] as number | undefined) ?? 0) !== directMessagesTopicId;
  }
  if (forumTopicId > 0) {
    const topic = message['topic_id'] as TdObject | undefined;
    return topic === undefined ||
      ((topic['forum_topic_id'] as number | undefined) ?? 0) !== forumTopicId;
  }
  if (threadRootId > 0) {
    return ((message['message_thread_id'] as number | undefined) ?? 0) !== threadRootId;
  }
  return false;
}

export function routeTopicId(params: Record<string, Object> | undefined): number {
  if (params === undefined) {
    return 0;
  }
  const directId = (params['directMessagesTopicId'] as number | undefined) ?? 0;
  return directId > 0 ? directId : ((params['forumTopicId'] as number | undefined) ?? 0);
}

export function conversationScopeId(
  threadRootId: number, forumTopicId: number, directMessagesTopicId: number
): number {
  if (directMessagesTopicId > 0) {
    return directMessagesTopicId;
  }
  if (forumTopicId > 0) {
    return forumTopicId;
  }
  return threadRootId;
}

// Navigation/subscriptions need a typed identity: a discussion root, forum
// topic and direct-message topic with the same numeric ID are different pages.
export function conversationScopeKey(
  threadRootId: number = 0, forumTopicId: number = 0, directMessagesTopicId: number = 0
): string {
  if (directMessagesTopicId > 0) { return `direct:${directMessagesTopicId}`; }
  if (forumTopicId > 0) { return `forum:${forumTopicId}`; }
  if (threadRootId > 0) { return `thread:${threadRootId}`; }
  return 'chat';
}

export function routeScopeKey(params: Record<string, Object> | undefined): string {
  return conversationScopeKey((params?.['threadRootId'] as number | undefined) ?? 0,
    (params?.['forumTopicId'] as number | undefined) ?? 0,
    (params?.['directMessagesTopicId'] as number | undefined) ?? 0);
}
