// 话题模型：配色表、解析、排序（纯函数，有单测）。
//
// 【为什么抽出来】原来这三件事长在 pages/chat/ForumTopicsPage 里，只有话题列表页
// 能用，也没有任何覆盖。2026-09-16 用户要把话题做成**聊天详情页顶栏里的一条横条**
// （形态同首页文件夹条，挂在标题行下面、共用同一块玻璃），横条与列表页必须吃同一份
// 数据、同一套排序——两处各写一份就是"同一个群两个顺序"的 bug 温床。
//
// 【刻意不碰 str() / formatPreview()】一个读资源、一个是另一层的格式化，进了纯函数
// 就没法单测。名字兜底与最后一条消息的预览都由调用方算好传进来。

import { TdObject } from '../tdkit/TdTypes';

// forumTopicIcon.color 的取值集合（TDLib 固定的六色）。从 ForumTopicsPage 原样搬来。
const TOPIC_COLORS: Map<number, string> = new Map([
  [0x6FB9F0, '#6FB9F0'], [0xFFD67E, '#FFD67E'], [0xCB86DB, '#CB86DB'],
  [0x8EEE98, '#8EEE98'], [0xFF93B2, '#FF93B2'], [0xFB6F5F, '#FB6F5F']
]);

const TOPIC_COLOR_FALLBACK: string = '#6FB9F0';

export interface ForumTopicRow {
  threadId: number;
  name: string;
  iconColor: string;
  isGeneral: boolean;
  isClosed: boolean;
  isPinned: boolean;
  unreadCount: number;
  lastMessageText: string;
}

// 服务端给了六色之外的值也要画得出来：空串会让胶囊变透明。
export function topicIconColor(colorValue: number): string {
  return TOPIC_COLORS.get(colorValue) ?? TOPIC_COLOR_FALLBACK;
}

// 半份 update、老版本服务端都可能缺字段：缺了就给中性值，threadId=0 由调用方过滤，
// 绝不能让一条坏数据把整条横条搞崩。
export function parseForumTopic(
  topic: TdObject, fallbackName: string, preview: string
): ForumTopicRow {
  const info = topic['info'] as TdObject | undefined;
  const threadId: number = info !== undefined
    ? ((info['forum_topic_id'] as number | undefined) ?? 0) : 0;
  const name: string = info !== undefined
    ? ((info['name'] as string | undefined) ?? '') : '';
  const icon = info !== undefined ? info['icon'] as TdObject | undefined : undefined;
  const colorValue: number = icon !== undefined
    ? ((icon['color'] as number | undefined) ?? 0) : 0;
  return {
    threadId: threadId,
    name: name !== '' ? name : fallbackName,
    iconColor: topicIconColor(colorValue),
    isGeneral: info !== undefined
      ? ((info['is_general'] as boolean | undefined) ?? false) : false,
    isClosed: info !== undefined
      ? ((info['is_closed'] as boolean | undefined) ?? false) : false,
    isPinned: (topic['is_pinned'] as boolean | undefined) ?? false,
    unreadCount: (topic['unread_count'] as number | undefined) ?? 0,
    lastMessageText: preview
  };
}

// 置顶在前，其余保持服务端顺序（getForumTopics 已按活跃度排好）。
// **不就地改入参**：横条与列表页吃同一份数组，就地排序会让另一侧莫名换序。
export function sortTopicRows(rows: ForumTopicRow[]): ForumTopicRow[] {
  const pinned: ForumTopicRow[] = rows.filter((row: ForumTopicRow): boolean => row.isPinned);
  const rest: ForumTopicRow[] = rows.filter((row: ForumTopicRow): boolean => !row.isPinned);
  return [...pinned, ...rest];
}

// ── 实时更新 ────────────────────────────────────────────────────────────
// 两段都是从 pages/chat/ForumTopicsPage 的 onTopicInfoUpdate / onTopicUpdate 逐字
// 搬来的语义（只把 this.rows / this.chatId 换成入参）。横条与列表页共用这一套，
// 两处各写一份必然漂移。
//
// **不是本会话的更新原样返回同一个数组引用**：调用方据此跳过发布——否则每个论坛群
// 的每条 update 都会惊动所有打开着的话题横条。同理，命中不到话题 id 时那一行仍是
// 同一个对象，LazyForEach 不会白重建它。

// updateForumTopicInfo：名字与关闭状态。
export function applyTopicInfoUpdate(
  rows: ForumTopicRow[], chatId: number, u: TdObject
): ForumTopicRow[] {
  const info = u['info'] as TdObject | undefined;
  if (info === undefined || ((info['chat_id'] as number | undefined) ?? 0) !== chatId) {
    return rows;
  }
  const topicId: number = (info['forum_topic_id'] as number | undefined) ?? 0;
  return sortTopicRows(rows.map((row: ForumTopicRow): ForumTopicRow => {
    if (row.threadId !== topicId) {
      return row;
    }
    const next: ForumTopicRow = {
      threadId: row.threadId,
      name: (info['name'] as string | undefined) ?? row.name,
      iconColor: row.iconColor,
      isGeneral: row.isGeneral,
      isClosed: (info['is_closed'] as boolean | undefined) ?? row.isClosed,
      isPinned: row.isPinned,
      unreadCount: row.unreadCount,
      lastMessageText: row.lastMessageText
    };
    return next;
  }));
}

// updateForumTopic：置顶状态（未读数由话题列表整体重拉刷新，与原实现一致）。
export function applyTopicUpdate(
  rows: ForumTopicRow[], chatId: number, u: TdObject
): ForumTopicRow[] {
  if (((u['chat_id'] as number | undefined) ?? 0) !== chatId) {
    return rows;
  }
  const topicId: number = (u['forum_topic_id'] as number | undefined) ?? 0;
  const isPinned: boolean = (u['is_pinned'] as boolean | undefined) ?? false;
  return sortTopicRows(rows.map((row: ForumTopicRow): ForumTopicRow => {
    if (row.threadId !== topicId) {
      return row;
    }
    const next: ForumTopicRow = {
      threadId: row.threadId, name: row.name, iconColor: row.iconColor,
      isGeneral: row.isGeneral, isClosed: row.isClosed,
      isPinned: isPinned,
      unreadCount: row.unreadCount, lastMessageText: row.lastMessageText
    };
    return next;
  }));
}

// 顶栏话题横条显不显示：有话题，或者允许用户新建（一个话题都没有时「新建」入口也在横条上）。
export function topicBarShown(rowCount: number, canCreate: boolean): boolean {
  return rowCount > 0 || canCreate;
}

// 删掉一个话题之后该落在哪：删的不是正在看的就不动；是的话落到剩下的第一个（排序已是
// 置顶优先，与横条一致）；删光了回到整段会话（0）。
export function topicAfterDelete(rows: ForumTopicRow[], deletedId: number, currentId: number): number {
  if (deletedId !== currentId) {
    return currentId;
  }
  const next: ForumTopicRow | undefined =
    rows.find((row: ForumTopicRow): boolean => row.threadId !== deletedId);
  return next !== undefined ? next.threadId : 0;
}
