import { describe, expect, it } from '@ohos/hypium';
import {
  SOURCE_CHAT_HISTORY, SOURCE_DM_TOPIC, SOURCE_FORUM_TOPIC, SOURCE_MESSAGE_THREAD,
  viewMessageSourceType
} from '../main/ets/util/viewMessageSource';

export default function viewMessageSourceTest() {
  describe('viewMessageSource', () => {
    // 这条钉 issue #190：论坛话题不给 source 时 TDLib 按整个会话猜，
    // 读到的账记不到话题头上，退出后未读依旧。
    it('论坛话题给 forumTopicHistory，不是 chatHistory', 0, () => {
      expect(viewMessageSourceType(0, 42, 0)).assertEqual(SOURCE_FORUM_TOPIC);
    });

    it('普通会话给 chatHistory（显式给，不留给 TDLib 猜）', 0, () => {
      expect(viewMessageSourceType(0, 0, 0)).assertEqual(SOURCE_CHAT_HISTORY);
    });

    it('消息话题（评论区）给 messageThreadHistory', 0, () => {
      expect(viewMessageSourceType(777, 0, 0)).assertEqual(SOURCE_MESSAGE_THREAD);
    });

    it('私聊话题给 directMessagesChatTopicHistory', 0, () => {
      expect(viewMessageSourceType(0, 0, 9)).assertEqual(SOURCE_DM_TOPIC);
    });

    it('优先级：私聊话题 > 论坛话题 > 消息话题', 0, () => {
      expect(viewMessageSourceType(1, 2, 3)).assertEqual(SOURCE_DM_TOPIC);
      expect(viewMessageSourceType(1, 2, 0)).assertEqual(SOURCE_FORUM_TOPIC);
    });

    it('负数/0 一律当没有作用域', 0, () => {
      expect(viewMessageSourceType(-1, -1, -1)).assertEqual(SOURCE_CHAT_HISTORY);
    });
  });
}
