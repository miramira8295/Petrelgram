import { TdObject } from '../tdkit/TdTypes';

// Which TDLib chat kind this is — decides whether the context menu offers
// 退出群组 / 退出频道 / 删除聊天, and whether "清空聊天记录" is even possible.
export type ChatKind = 'private' | 'secret' | 'basicGroup' | 'supergroup' | 'channel';

export interface ChatEntry {
  id: number;
  // Monotonic render revision. ForEach can use this compact value instead of
  // embedding every mutable field (and the row index) in its identity.
  revision: number;
  title: string;
  isMuted: boolean;
  // 是否跟随作用域默认静音设置（见 effectiveMuted）。
  usesDefaultMute: boolean;
  unreadCount: number;
  // TDLib 原始值。unreadCount 是把"幽灵未读"抑制掉之后的展示值，而抑制要拿
  // 读水位和末条 id 比——这三个数分别从不同的 update 来、到达顺序不保证，
  // 所以原始值必须留着，任何一个变了都能重算（见 ChatStore.refreshUnread）。
  rawUnreadCount: number;
  lastReadInboxId: number;
  lastMessageText: string;
  lastMessageDate: number;
  lastMessageId: number;   // newest message — 标记为已读 reads up to it
  lastSenderName: string;
  photoFileId: number;
  avatarPath: string;
  initials: string;
  autoDeleteTime: number;
  kind: ChatKind;
  isMarkedUnread: boolean; // manually flagged unread (unread_count may be 0)
  // 和自己的私聊 —— Telegram 的「我的收藏」。TDLib 对它没有任何特殊标记：
  // 标题就是自己的昵称、头像就是自己的头像（issue #8 的截图即此）。判据是
  // chat.id === 自己的 user id，只能由客户端自己认。展示成什么样交给渲染层，
  // 这里只记"是不是"，标题文案才能跟着语言走。
  isSavedMessages: boolean;
  // Per-chat wallpaper/theme background supplied by TDLib. Kept as the
  // original immutable object so ChatPage can render new background variants
  // without making the chat-list store depend on ArkUI types.
  background: TdObject | null;
  themeName: string;
  liveGroupCallId: number; // current video chat/group call bound to this chat
  isLive: boolean;        // true only after groupCall.is_active is confirmed
  isRtmpLive: boolean;
}

export function cloneEntry(e: ChatEntry): ChatEntry {
  return {
    id: e.id, revision: e.revision + 1,
    title: e.title, isMuted: e.isMuted, usesDefaultMute: e.usesDefaultMute,
    unreadCount: e.unreadCount,
    rawUnreadCount: e.rawUnreadCount, lastReadInboxId: e.lastReadInboxId,
    lastMessageText: e.lastMessageText, lastMessageDate: e.lastMessageDate,
    lastMessageId: e.lastMessageId,
    lastSenderName: e.lastSenderName, photoFileId: e.photoFileId,
    avatarPath: e.avatarPath, initials: e.initials, autoDeleteTime: e.autoDeleteTime,
    kind: e.kind, isMarkedUnread: e.isMarkedUnread,
    isSavedMessages: e.isSavedMessages,
    background: e.background, themeName: e.themeName,
    liveGroupCallId: e.liveGroupCallId, isLive: e.isLive, isRtmpLive: e.isRtmpLive
  };
}

// A supergroup with is_channel set is a broadcast channel; without it, a group.
export function chatKindOf(type: TdObject | undefined): ChatKind {
  if (type === undefined) {
    return 'private';
  }
  const t = (type['@type'] as string | undefined) ?? '';
  if (t === 'chatTypeSupergroup') {
    return ((type['is_channel'] as boolean | undefined) ?? false) ? 'channel' : 'supergroup';
  }
  if (t === 'chatTypeBasicGroup') {
    return 'basicGroup';
  }
  if (t === 'chatTypeSecret') {
    return 'secret';
  }
  return 'private';
}

export interface PositionInfo {
  order: string;
  isPinned: boolean;
}

export function computeInitials(title: string): string {
  const trimmed = title.trim();
  if (trimmed === '') {
    return '?';
  }
  const words = trimmed.split(/\s+/);
  if (words.length >= 2) {
    return (words[0].charAt(0) + words[1].charAt(0)).toUpperCase();
  }
  return words[0].charAt(0).toUpperCase();
}

// Descending order for non-negative int64 stored as string.
export function compareOrderDesc(a: string, b: string): number {
  if (a.length !== b.length) {
    return b.length - a.length;
  }
  if (a === b) {
    return 0;
  }
  return a < b ? 1 : -1;
}

export function isMutedFrom(notificationSettings: TdObject | undefined): boolean {
  if (notificationSettings === undefined) {
    return false;
  }
  const muteFor = (notificationSettings['mute_for'] as number | undefined) ?? 0;
  return muteFor > 0;
}

// 该会话是否跟随作用域默认值。为 true 时 mute_for 不代表真实状态 —— 必须去看
// 私聊/群组/频道的默认设置，否则跟随默认且默认为静音的会话会被当成未静音。
export function usesDefaultMuteFrom(notificationSettings: TdObject | undefined): boolean {
  if (notificationSettings === undefined) {
    return true;
  }
  return (notificationSettings['use_default_mute_for'] as boolean | undefined) ?? true;
}

// 会话最终是否静音：自身设置优先，否则回落到作用域默认。
export function effectiveMuted(entry: ChatEntry, scopeMuted: boolean): boolean {
  return entry.usesDefaultMute ? scopeMuted : entry.isMuted;
}
