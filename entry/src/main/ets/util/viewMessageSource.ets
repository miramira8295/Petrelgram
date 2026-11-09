// viewMessages 的 source 该传哪一个。
//
// 【为什么必须传】td_api 原文：`@source Source of the message view; pass null to
// guess the source based on chat open state`。传 null 时 TDLib 只能按"整个会话
// 打开着"去猜，于是**读到的账记不到话题头上**——进话题群组读完退出，未读仍在
// （issue #190，反复多次都错）。
//
// 【四个值的来源】tdlib/td 的 td/generate/scheme/td_api.tl：
//   messageSourceChatHistory
//   messageSourceMessageThreadHistory
//   messageSourceForumTopicHistory
//   messageSourceDirectMessagesChatTopicHistory
// 不是猜的——这个仓库在 inputMessageVideo 上刚吃过一次"字段名对不上就被静默
// 忽略"的亏，类型名一律以 td_api.tl 为准。
//
// 【为什么不需要额外的 topic 参数】viewMessages 的签名只有
// `chat_id / message_ids / source / force_read`，没有 topic_id；话题由消息 id
// 自己带出来。TDLib 里也**没有** openForumTopic 这类"打开话题"的方法，所以
// 不存在"话题没打开导致读不生效"这条路。
//
// 优先级：私聊话题 > 论坛话题 > 消息话题 > 整个会话。三种作用域在
// MessageStore 里互斥（构造时只会传其中一个），但排个序好过依赖调用方自觉。

export const SOURCE_CHAT_HISTORY: string = 'messageSourceChatHistory';
export const SOURCE_MESSAGE_THREAD: string = 'messageSourceMessageThreadHistory';
export const SOURCE_FORUM_TOPIC: string = 'messageSourceForumTopicHistory';
export const SOURCE_DM_TOPIC: string = 'messageSourceDirectMessagesChatTopicHistory';

export function viewMessageSourceType(
  threadRootId: number, forumTopicId: number, directMessagesTopicId: number
): string {
  if (directMessagesTopicId > 0) {
    return SOURCE_DM_TOPIC;
  }
  if (forumTopicId > 0) {
    return SOURCE_FORUM_TOPIC;
  }
  if (threadRootId > 0) {
    return SOURCE_MESSAGE_THREAD;
  }
  return SOURCE_CHAT_HISTORY;
}
