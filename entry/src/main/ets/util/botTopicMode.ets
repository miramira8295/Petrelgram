import { TdObject } from '../tdkit/TdTypes';

// Bot 私聊的「话题模式」（issue #206，2026-09-17）。
//
// Bot API 9.3 起 Bot 可以在私聊里开论坛话题，9.4 起还能自己建话题。TDLib 1.8.65 在
// userTypeBot 上给出两个标志：has_topics（开没开）、allows_users_to_create_topics
// （用户能不能自己建/删话题）。开了的私聊，消息都带 topic_id: messageTopicForum，
// getForumTopics / getForumTopicHistory / createForumTopic 都写明支持「chat with a bot
// with topics」——所以论坛群那一整套（横条、话题内消息流）直接可用，缺的只是识别。

export interface BotTopicFlags {
  hasTopics: boolean;
  allowsUserTopics: boolean;
}

export function botTopicFlagsOf(user: TdObject | null | undefined): BotTopicFlags {
  const none: BotTopicFlags = { hasTopics: false, allowsUserTopics: false };
  if (user === undefined || user === null) {
    return none;
  }
  const type = user['type'] as TdObject | null | undefined;
  if (type === undefined || type === null || (type['@type'] as string | undefined) !== 'userTypeBot') {
    return none;
  }
  const hasTopics: boolean = (type['has_topics'] as boolean | undefined) === true;
  // 没开话题模式时「允许用户建话题」没有意义，不给入口。
  const allows: boolean = hasTopics && (type['allows_users_to_create_topics'] as boolean | undefined) === true;
  return { hasTopics: hasTopics, allowsUserTopics: allows };
}
