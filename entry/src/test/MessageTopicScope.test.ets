import { describe, expect, it } from '@ohos/hypium';
import { TdObject, TdRequest } from '../main/ets/tdkit/TdTypes';
import {
  applyMessageTopicScope, conversationScopeId, messageOutsideTopicScope, routeTopicId
} from '../main/ets/util/messageTopicScope';

export default function messageTopicScopeTest(): void {
  describe('messageTopicScope', (): void => {
    it('direct_topic_has_priority_and_uses_tdlib_shape', 0, (): void => {
      const request: TdRequest = { '@type': 'sendMessage' };
      applyMessageTopicScope(request, 9, 8, 7);
      const topic = request['topic_id'] as TdObject;
      expect(topic['@type']).assertEqual('messageTopicDirectMessages');
      expect(topic['direct_messages_chat_topic_id']).assertEqual(7);
    });

    it('filters_updates_to_the_selected_direct_topic', 0, (): void => {
      const message: TdObject = { '@type': 'message' };
      const topic: TdObject = { '@type': 'messageTopicDirectMessages' };
      topic['direct_messages_chat_topic_id'] = 77;
      message['topic_id'] = topic;
      expect(messageOutsideTopicScope(message, 0, 0, 77)).assertFalse();
      expect(messageOutsideTopicScope(message, 0, 0, 78)).assertTrue();
    });

    it('uses_direct_topic_for_navigation_and_resume_keys', 0, (): void => {
      const params: Record<string, Object> = {
        'forumTopicId': 3, 'directMessagesTopicId': 42
      };
      expect(routeTopicId(params)).assertEqual(42);
      expect(conversationScopeId(1, 3, 42)).assertEqual(42);
    });
  });
}
