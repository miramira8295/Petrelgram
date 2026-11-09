import { TdRequest } from '../tdkit/TdTypes';

// 「取消全部置顶」发哪一条请求。
//
// 【为什么不是一条】td_api 把"全部"按作用域拆成了三个方法，随包 libtdjson.so
// 里三个字符串都在：
//   unpinAllChatMessages                     整个会话
//   unpinAllForumTopicMessages               论坛群的一个话题
//   unpinAllDirectMessagesChatTopicMessages  频道私信按来信者拆出的一个 topic
// 在话题里发会话级的那一条，会把别的话题的置顶一起抹掉——这是不可撤销的写操作，
// 作用域必须和面板里列出来的那批**完全一致**（面板的数据源 resolvePinned 同样
// 按话题过滤）。
//
// 【评论线程返回 null】resolvePinned 在 threadRootId > 0 时直接把置顶清空
// （讨论组的置顶不属于这条评论线程），面板里本来就一条都没有；td 那边也认
// "Topic messages can't be unpinned"。与其发一条会误伤整个讨论组的请求，
// 不如让调用方什么都不做。
//
// 字段名不是猜的：forum_topic_id / topic_id 分别抄自本仓已经在用的
// getForumTopic 与 getDirectMessagesChatTopic。
export function unpinAllRequest(
  chatId: number, threadRootId: number, forumTopicId: number,
  directMessagesTopicId: number
): TdRequest | null {
  if (chatId === 0) {
    return null;
  }
  if (directMessagesTopicId > 0) {
    const req: TdRequest = { '@type': 'unpinAllDirectMessagesChatTopicMessages' };
    req['chat_id'] = chatId;
    req['topic_id'] = directMessagesTopicId;
    return req;
  }
  if (forumTopicId > 0) {
    const req: TdRequest = { '@type': 'unpinAllForumTopicMessages' };
    req['chat_id'] = chatId;
    req['forum_topic_id'] = forumTopicId;
    return req;
  }
  if (threadRootId > 0) {
    return null;
  }
  const req: TdRequest = { '@type': 'unpinAllChatMessages' };
  req['chat_id'] = chatId;
  return req;
}
