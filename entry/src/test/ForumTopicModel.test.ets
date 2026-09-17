import { describe, it, expect } from '@ohos/hypium';
import { TdObject, TdRequest } from '../main/ets/tdkit/TdTypes';
import {
  ForumTopicRow, applyTopicInfoUpdate, applyTopicUpdate, parseForumTopic, sortTopicRows,
  topicAfterDelete, topicBarShown, topicIconColor
} from '../main/ets/util/forumTopicModel';
import { BotTopicFlags, botTopicFlagsOf } from '../main/ets/util/botTopicMode';
import { forumTopicCreateRequest, forumTopicDeleteRequest } from '../main/ets/util/forumTopicRequests';

// 话题模型（2026-09-16）。原来这三件事（配色表、解析、排序）长在
// pages/chat/ForumTopicsPage 里，只有那一个页面能用。
//
// 【为什么现在要抽出来】用户要把话题列表做成**聊天详情页顶栏里的一条横条**
// （形态同首页文件夹条，挂在标题行下面、共用同一块玻璃）。横条和话题列表页要吃
// 同一份数据、同一套排序，否则两处顺序不一致就是 bug。抽成纯函数还顺带让它们
// 第一次有了单测——页面里那份一条覆盖都没有。
//
// 解析刻意**不碰 str() / formatPreview()**：那两个一个读资源、一个是另一层的
// 格式化，进了纯函数就没法单测了。调用方把结果传进来。

function topicObject(id: number, name: string, color: number, pinned: boolean,
  unread: number, general: boolean = false, closed: boolean = false): TdObject {
  const info: TdObject = {};
  info['forum_topic_id'] = id;
  info['name'] = name;
  info['is_general'] = general;
  info['is_closed'] = closed;
  const icon: TdObject = {};
  icon['color'] = color;
  info['icon'] = icon;
  const topic: TdObject = {};
  topic['info'] = info;
  topic['is_pinned'] = pinned;
  topic['unread_count'] = unread;
  return topic;
}

export default function forumTopicModelTest() {
  describe('forumTopicModel', () => {
    it('parses_the_fields_the_bar_needs', 0, () => {
      const row: ForumTopicRow = parseForumTopic(
        topicObject(7, '公告', 0xFFD67E, true, 3), '话题', '最后一条');
      expect(row.threadId).assertEqual(7);
      expect(row.name).assertEqual('公告');
      expect(row.iconColor).assertEqual('#FFD67E');
      expect(row.isPinned).assertTrue();
      expect(row.unreadCount).assertEqual(3);
      expect(row.lastMessageText).assertEqual('最后一条');
    });

    // 名字为空时用调用方给的兜底（页面传 str('ft_topics')）——纯函数自己不读资源。
    it('falls_back_to_the_given_name', 0, () => {
      const row: ForumTopicRow = parseForumTopic(topicObject(1, '', 0, false, 0), '话题', '');
      expect(row.name).assertEqual('话题');
    });

    // TDLib 只发六种固定色；给了别的值不能画成透明/空串。
    it('unknown_icon_color_falls_back', 0, () => {
      expect(topicIconColor(0x6FB9F0)).assertEqual('#6FB9F0');
      expect(topicIconColor(0x123456)).assertEqual('#6FB9F0');
    });

    // 缺字段的对象不能把整条横条搞崩（半份 update、老版本服务端）。
    it('a_malformed_topic_yields_an_ignorable_row', 0, () => {
      const row: ForumTopicRow = parseForumTopic({}, '话题', '');
      expect(row.threadId).assertEqual(0);
      expect(row.name).assertEqual('话题');
    });

    // 置顶在前，其余保持服务端给的顺序（getForumTopics 已按活跃度排好）。
    it('pinned_first_others_keep_server_order', 0, () => {
      const rows: ForumTopicRow[] = [
        parseForumTopic(topicObject(1, 'a', 0, false, 0), '话题', ''),
        parseForumTopic(topicObject(2, 'b', 0, true, 0), '话题', ''),
        parseForumTopic(topicObject(3, 'c', 0, false, 0), '话题', ''),
        parseForumTopic(topicObject(4, 'd', 0, true, 0), '话题', '')
      ];
      const sorted: ForumTopicRow[] = sortTopicRows(rows);
      expect(sorted.map((r: ForumTopicRow): number => r.threadId).join(',')).assertEqual('2,4,1,3');
    });

    // ── 实时更新（updateForumTopicInfo / updateForumTopic）────────────────
    // 这两段原来长在 ForumTopicsPage 里，逐字搬成纯函数：横条和列表页要吃同一套
    // 更新逻辑，两处各写一份必然漂移。

    // 别的会话的话题更新必须**原样返回同一个数组引用**：调用方据此跳过发布，
    // 否则每个论坛群的每条 update 都会惊动所有打开着的话题横条。
    it('an_update_for_another_chat_returns_the_same_array', 0, () => {
      const rows: ForumTopicRow[] = [parseForumTopic(topicObject(1, 'a', 0, false, 0), '话题', '')];
      const info: TdObject = {};
      info['chat_id'] = 999;
      info['forum_topic_id'] = 1;
      info['name'] = '改了';
      const u: TdObject = {};
      u['info'] = info;
      expect(applyTopicInfoUpdate(rows, 7, u) === rows).assertTrue();
    });

    it('renames_only_the_matching_row', 0, () => {
      const rows: ForumTopicRow[] = [
        parseForumTopic(topicObject(1, 'a', 0, false, 0), '话题', ''),
        parseForumTopic(topicObject(2, 'b', 0, false, 0), '话题', '')
      ];
      const info: TdObject = {};
      info['chat_id'] = 7;
      info['forum_topic_id'] = 2;
      info['name'] = '新名字';
      info['is_closed'] = true;
      const u: TdObject = {};
      u['info'] = info;
      const next: ForumTopicRow[] = applyTopicInfoUpdate(rows, 7, u);
      expect(next[1].name).assertEqual('新名字');
      expect(next[1].isClosed).assertTrue();
      // 没被改的那一行必须还是**同一个对象**，否则 LazyForEach 会白重建它。
      expect(next[0] === rows[0]).assertTrue();
    });

    it('pinning_reorders_the_rows', 0, () => {
      const rows: ForumTopicRow[] = [
        parseForumTopic(topicObject(1, 'a', 0, false, 0), '话题', ''),
        parseForumTopic(topicObject(2, 'b', 0, false, 0), '话题', '')
      ];
      const u: TdObject = {};
      u['chat_id'] = 7;
      u['forum_topic_id'] = 2;
      u['is_pinned'] = true;
      const next: ForumTopicRow[] = applyTopicUpdate(rows, 7, u);
      expect(next[0].threadId).assertEqual(2);
      expect(next[0].isPinned).assertTrue();
    });

    // 认不出的话题 id 不能把别的行改坏，也不该白发布。
    it('an_unknown_topic_id_changes_nothing', 0, () => {
      const rows: ForumTopicRow[] = [parseForumTopic(topicObject(1, 'a', 0, false, 0), '话题', '')];
      const u: TdObject = {};
      u['chat_id'] = 7;
      u['forum_topic_id'] = 404;
      u['is_pinned'] = true;
      const next: ForumTopicRow[] = applyTopicUpdate(rows, 7, u);
      expect(next[0] === rows[0]).assertTrue();
    });

    // 排序不得就地改调用方的数组：横条与列表页吃同一份数据。
    it('sorting_does_not_mutate_the_input', 0, () => {
      const rows: ForumTopicRow[] = [
        parseForumTopic(topicObject(1, 'a', 0, false, 0), '话题', ''),
        parseForumTopic(topicObject(2, 'b', 0, true, 0), '话题', '')
      ];
      sortTopicRows(rows);
      expect(rows[0].threadId).assertEqual(1);
    });
    // Bot 私聊的话题模式（issue #206，2026-09-17）。Bot API 9.3 起 Bot 可以在私聊里开话题，
    // TDLib 1.8.65 在 userTypeBot 上给出两个标志。
    it('reads_bot_topic_mode_flags', 0, () => {
      const type: TdObject = { '@type': 'userTypeBot' };
      type['has_topics'] = true;
      type['allows_users_to_create_topics'] = true;
      const bot: TdObject = { '@type': 'user' };
      bot['type'] = type;
      const flags: BotTopicFlags = botTopicFlagsOf(bot);
      expect(flags.hasTopics).assertTrue();
      expect(flags.allowsUserTopics).assertTrue();
      const plainType: TdObject = { '@type': 'userTypeBot' };
      const plainBot: TdObject = { '@type': 'user' };
      plainBot['type'] = plainType;
      expect(botTopicFlagsOf(plainBot).hasTopics).assertFalse();
      // 普通用户就算带着同名字段也不算
      const regularType: TdObject = { '@type': 'userTypeRegular' };
      regularType['has_topics'] = true;
      const human: TdObject = { '@type': 'user' };
      human['type'] = regularType;
      expect(botTopicFlagsOf(human).hasTopics).assertFalse();
      // 没开话题却允许用户建话题：没有意义，一律不给入口
      const oddType: TdObject = { '@type': 'userTypeBot' };
      oddType['allows_users_to_create_topics'] = true;
      const odd: TdObject = { '@type': 'user' };
      odd['type'] = oddType;
      expect(botTopicFlagsOf(odd).allowsUserTopics).assertFalse();
      expect(botTopicFlagsOf(undefined).hasTopics).assertFalse();
    });

    // 允许用户建话题的会话，一个话题都还没有时横条也要在——「新建」入口就在横条上。
    it('topic_bar_shows_when_there_are_topics_or_creation_is_allowed', 0, () => {
      expect(topicBarShown(0, false)).assertFalse();
      expect(topicBarShown(3, false)).assertTrue();
      expect(topicBarShown(0, true)).assertTrue();
    });

    it('builds_create_and_delete_topic_requests', 0, () => {
      const create: TdRequest | null = forumTopicCreateRequest(42, '  新会话  ');
      expect(create !== null).assertTrue();
      expect(create!['@type'] as string).assertEqual('createForumTopic');
      expect(create!['chat_id'] as number).assertEqual(42);
      expect(create!['name'] as string).assertEqual('新会话');
      expect(forumTopicCreateRequest(42, '   ') === null).assertTrue();
      expect(forumTopicCreateRequest(0, 'x') === null).assertTrue();
      const del: TdRequest | null = forumTopicDeleteRequest(42, 9);
      expect(del !== null).assertTrue();
      expect(del!['@type'] as string).assertEqual('deleteForumTopic');
      expect(del!['forum_topic_id'] as number).assertEqual(9);
      expect(forumTopicDeleteRequest(42, 0) === null).assertTrue();
    });

    // 删掉的是正在看的那个话题：落到剩下的第一个；都删光了回到整段会话（0）。
    it('lands_on_a_remaining_topic_after_deleting_the_current_one', 0, () => {
      const rows: ForumTopicRow[] = [
        parseForumTopic(topicObject(5, 'A', 0, true, 0), '', ''),
        parseForumTopic(topicObject(6, 'B', 0, false, 0), '', ''),
        parseForumTopic(topicObject(7, 'C', 0, false, 0), '', '')
      ];
      expect(topicAfterDelete(rows, 6, 7)).assertEqual(7);
      expect(topicAfterDelete(rows, 5, 5)).assertEqual(6);
      expect(topicAfterDelete([rows[1]], 6, 6)).assertEqual(0);
    });
  });
}
