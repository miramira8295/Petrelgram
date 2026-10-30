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
  iconCustomEmojiId?: string;
  iconCustomEmojiPath?: string;
  iconEmoji?: string;
  isGeneral: boolean;
  isClosed: boolean;
  isPinned: boolean;
  unreadCount: number;
  lastMessageText: string;
  lastMessageDate?: number;
  lastSenderName?: string;
  lastMessageThumb?: string;
  isMuted?: boolean;
}

// 服务端给了六色之外的值也要画得出来：空串会让胶囊变透明。
export function topicIconColor(colorValue: number): string {
  return TOPIC_COLORS.get(colorValue) ?? TOPIC_COLOR_FALLBACK;
}

function normalizeCustomEmojiId(raw: Object | undefined): string {
  if (raw === undefined || raw === null) {
    return '';
  }
  const strVal: string = `${raw}`.trim();
  return strVal === '' || strVal === '0' ? '' : strVal;
}

function topicIsMuted(notificationSettings: TdObject | undefined): boolean {
  if (notificationSettings === undefined) {
    return false;
  }
  return ((notificationSettings['mute_for'] as number | undefined) ?? 0) > 0;
}

// 话题名本身已经以 Emoji / 特殊符号开头时（例如 "📣 公告"、"⁉️ 常见问题"），
// 在无自定义 emoji 图标时不再重复叠加首字母彩色方框。
export function startsWithEmojiSymbol(name: string): boolean {
  const trimmed: string = name.trim();
  if (trimmed === '') {
    return false;
  }
  const cp: number = trimmed.codePointAt(0) ?? 0;
  return cp >= 0x1F000 || (cp >= 0x2000 && cp <= 0x3300);
}

// 半份 update、老版本服务端都可能缺字段：缺了就给中性值，threadId=0 由调用方过滤，
// 绝不能让一条坏数据把整条横条搞崩。
export function parseForumTopic(
  topic: TdObject, fallbackName: string, preview: string,
  lastSenderName: string = '', lastMessageThumb: string = ''
): ForumTopicRow {
  const info = topic['info'] as TdObject | undefined;
  const threadId: number = info !== undefined
    ? ((info['forum_topic_id'] as number | undefined) ?? 0) : 0;
  const name: string = info !== undefined
    ? ((info['name'] as string | undefined) ?? '') : '';
  const icon = info !== undefined ? info['icon'] as TdObject | undefined : undefined;
  const colorValue: number = icon !== undefined
    ? ((icon['color'] as number | undefined) ?? 0) : 0;
  const customEmojiId: string = icon !== undefined
    ? normalizeCustomEmojiId(icon['custom_emoji_id']) : '';
  const lastMsg = topic['last_message'] as TdObject | undefined;
  const lastDate: number = lastMsg !== undefined && lastMsg !== null
    ? ((lastMsg['date'] as number | undefined) ?? 0) : 0;
  const notif = topic['notification_settings'] as TdObject | undefined;
  return {
    threadId: threadId,
    name: name !== '' ? name : fallbackName,
    iconColor: topicIconColor(colorValue),
    iconCustomEmojiId: customEmojiId,
    iconCustomEmojiPath: '',
    iconEmoji: '',
    isGeneral: info !== undefined
      ? ((info['is_general'] as boolean | undefined) ?? false) : false,
    isClosed: info !== undefined
      ? ((info['is_closed'] as boolean | undefined) ?? false) : false,
    isPinned: (topic['is_pinned'] as boolean | undefined) ?? false,
    unreadCount: (topic['unread_count'] as number | undefined) ?? 0,
    lastMessageText: preview,
    lastMessageDate: lastDate,
    lastSenderName: lastSenderName,
    lastMessageThumb: lastMessageThumb,
    isMuted: topicIsMuted(notif)
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
  const icon = info['icon'] as TdObject | undefined;
  return sortTopicRows(rows.map((row: ForumTopicRow): ForumTopicRow => {
    if (row.threadId !== topicId) {
      return row;
    }
    const nextCustomId: string = icon !== undefined && icon['custom_emoji_id'] !== undefined
      ? normalizeCustomEmojiId(icon['custom_emoji_id'])
      : (row.iconCustomEmojiId ?? '');
    const sameCustomId: boolean = nextCustomId === (row.iconCustomEmojiId ?? '');
    const next: ForumTopicRow = {
      threadId: row.threadId,
      name: (info['name'] as string | undefined) ?? row.name,
      iconColor: icon !== undefined && icon['color'] !== undefined
        ? topicIconColor((icon['color'] as number | undefined) ?? 0)
        : row.iconColor,
      iconCustomEmojiId: nextCustomId,
      iconCustomEmojiPath: sameCustomId ? (row.iconCustomEmojiPath ?? '') : '',
      iconEmoji: sameCustomId ? (row.iconEmoji ?? '') : '',
      isGeneral: row.isGeneral,
      isClosed: (info['is_closed'] as boolean | undefined) ?? row.isClosed,
      isPinned: row.isPinned,
      unreadCount: row.unreadCount,
      lastMessageText: row.lastMessageText,
      lastMessageDate: row.lastMessageDate ?? 0,
      lastSenderName: row.lastSenderName ?? '',
      lastMessageThumb: row.lastMessageThumb ?? '',
      isMuted: row.isMuted ?? false
    };
    return next;
  }));
}

// updateForumTopic：置顶状态与未读数/静音状态。
export function applyTopicUpdate(
  rows: ForumTopicRow[], chatId: number, u: TdObject
): ForumTopicRow[] {
  if (((u['chat_id'] as number | undefined) ?? 0) !== chatId) {
    return rows;
  }
  const topicId: number = (u['forum_topic_id'] as number | undefined) ?? 0;
  const isPinned: boolean = (u['is_pinned'] as boolean | undefined) ?? false;
  const unreadRaw = u['unread_count'] as number | undefined;
  const notifRaw = u['notification_settings'] as TdObject | undefined;
  return sortTopicRows(rows.map((row: ForumTopicRow): ForumTopicRow => {
    if (row.threadId !== topicId) {
      return row;
    }
    const next: ForumTopicRow = {
      threadId: row.threadId, name: row.name, iconColor: row.iconColor,
      iconCustomEmojiId: row.iconCustomEmojiId ?? '',
      iconCustomEmojiPath: row.iconCustomEmojiPath ?? '',
      iconEmoji: row.iconEmoji ?? '',
      isGeneral: row.isGeneral, isClosed: row.isClosed,
      isPinned: isPinned,
      unreadCount: unreadRaw !== undefined ? unreadRaw : row.unreadCount,
      lastMessageText: row.lastMessageText,
      lastMessageDate: row.lastMessageDate ?? 0,
      lastSenderName: row.lastSenderName ?? '',
      lastMessageThumb: row.lastMessageThumb ?? '',
      isMuted: notifRaw !== undefined ? topicIsMuted(notifRaw) : (row.isMuted ?? false)
    };
    return next;
  }));
}

// 自定义 emoji 图标解析回调后就地更新对应行；没有任何行变化时返回原数组引用。
export function applyTopicCustomEmoji(
  rows: ForumTopicRow[], customEmojiId: string, path: string, emoji: string
): ForumTopicRow[] {
  if (customEmojiId === '') {
    return rows;
  }
  let changed: boolean = false;
  const next: ForumTopicRow[] = rows.map((row: ForumTopicRow): ForumTopicRow => {
    if ((row.iconCustomEmojiId ?? '') !== customEmojiId) {
      return row;
    }
    const nextPath: string = path !== '' ? path : (row.iconCustomEmojiPath ?? '');
    const nextEmoji: string = emoji !== '' ? emoji : (row.iconEmoji ?? '');
    if (nextPath === (row.iconCustomEmojiPath ?? '') && nextEmoji === (row.iconEmoji ?? '')) {
      return row;
    }
    changed = true;
    return {
      threadId: row.threadId,
      name: row.name,
      iconColor: row.iconColor,
      iconCustomEmojiId: row.iconCustomEmojiId ?? '',
      iconCustomEmojiPath: nextPath,
      iconEmoji: nextEmoji,
      isGeneral: row.isGeneral,
      isClosed: row.isClosed,
      isPinned: row.isPinned,
      unreadCount: row.unreadCount,
      lastMessageText: row.lastMessageText,
      lastMessageDate: row.lastMessageDate ?? 0,
      lastSenderName: row.lastSenderName ?? '',
      lastMessageThumb: row.lastMessageThumb ?? '',
      isMuted: row.isMuted ?? false
    };
  });
  return changed ? next : rows;
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
