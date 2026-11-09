import { describe, it, expect } from '@ohos/hypium';
import { unpinAllRequest } from '../main/ets/util/unpinAllRequest';
import { TdRequest } from '../main/ets/tdkit/TdTypes';

export default function unpinAllRequestTest() {
  describe('UnpinAllRequest', () => {
    it('普通会话走 unpinAllChatMessages', 0, () => {
      const req = unpinAllRequest(777, 0, 0, 0);
      expect(req !== null).assertTrue();
      expect(req!['@type']).assertEqual('unpinAllChatMessages');
      expect(req!['chat_id']).assertEqual(777);
    });

    // 在话题里发会话级那一条会抹掉别的话题的置顶，而且撤不回来。
    it('论坛话题走 unpinAllForumTopicMessages 并带 forum_topic_id', 0, () => {
      const req: TdRequest | null = unpinAllRequest(777, 0, 42, 0);
      expect(req !== null).assertTrue();
      expect(req!['@type']).assertEqual('unpinAllForumTopicMessages');
      expect(req!['chat_id']).assertEqual(777);
      expect(req!['forum_topic_id']).assertEqual(42);
    });

    it('频道私信 topic 走 unpinAllDirectMessagesChatTopicMessages 并带 topic_id', 0, () => {
      const req: TdRequest | null = unpinAllRequest(777, 0, 0, 9);
      expect(req !== null).assertTrue();
      expect(req!['@type']).assertEqual('unpinAllDirectMessagesChatTopicMessages');
      expect(req!['topic_id']).assertEqual(9);
    });

    // 私信 topic 比论坛话题更专有：两个都有值时不能退回论坛那一条。
    it('两种话题 id 同时存在时以频道私信优先', 0, () => {
      const req: TdRequest | null = unpinAllRequest(777, 0, 42, 9);
      expect(req!['@type']).assertEqual('unpinAllDirectMessagesChatTopicMessages');
    });

    // 评论线程里置顶条本来就是空的，发会话级请求会误伤整个讨论组。
    it('评论线程返回 null，调用方什么都不做', 0, () => {
      expect(unpinAllRequest(777, 555, 0, 0)).assertNull();
    });

    it('话题 id 优先于评论线程：论坛话题里的评论线程仍按话题作用域', 0, () => {
      const req: TdRequest | null = unpinAllRequest(777, 555, 42, 0);
      expect(req!['@type']).assertEqual('unpinAllForumTopicMessages');
    });

    it('没有 chatId 一律返回 null', 0, () => {
      expect(unpinAllRequest(0, 0, 0, 0)).assertNull();
      expect(unpinAllRequest(0, 0, 42, 0)).assertNull();
    });
  });
}
