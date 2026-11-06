// ChatEntry 的生产：TDLib 的 chat 对象 → 我们自己的行模型。
//
// 【为什么单独成一个纯函数】第二层 B4 要把「实体生产」搬进 worker。搬之前它必须
// 先是一个**不依赖 store 实例**的纯函数：只吃 chat / 上一条 entry / selfId，外加
// 一个 senderName 回调（worker 侧将来接它自己的 UserStore）。
//
// 【什么留在这里、什么留在 ChatStore】
//   · 这里：字段怎么算（未读抑制、预览、Saved Messages、能力位、封面）。
//   · ChatStore：副作用——写进 chats 表、置顶纪元、群通话登记、位置应用、通知。
// 两者分开之后，worker 可以跑同一份字段计算，而"何时发布"仍由使用方决定。

import { TdObject } from '../tdkit/TdTypes';
import {
  ChatEntry, ChatKind, chatKindOf, computeInitials, isMutedFrom, lastMessageSendStateFrom,
  usesDefaultMuteFrom
} from './ChatEntry';
import { formatPreview, previewThumbOf } from '../util/formatPreview';
import { actionBarCanUnarchiveOf, actionBarKindOf } from '../util/chatActionBar';
import { logW } from '../util/log';

export interface ChatEntryBuildInput {
  chat: TdObject;
  // 同一条会话的上一版。为空 = 第一次见到它。
  previous: ChatEntry | undefined;
  // 自己的 user id；0 = 还不知道（Saved Messages 判定依赖它）。
  selfId: number;
  // 最后一条消息的发送者显示名。注入而不是自己查 UserStore：worker 侧要能用
  // 它自己那份用户表。
  senderName: (message: TdObject | undefined) => string;
}

export function messageIdOf(message: TdObject | null): number {
  return message !== null ? ((message['id'] as number | undefined) ?? 0) : 0;
}

export function smallPhotoIdOf(photo: TdObject | undefined): number {
  if (photo === undefined) {
    return 0;
  }
  const small = photo['small'] as TdObject | undefined;
  if (small === undefined) {
    return 0;
  }
  return (small['id'] as number | undefined) ?? 0;
}

export function videoChatIdOf(videoChat: TdObject | undefined): number {
  return videoChat !== undefined
    ? ((videoChat['group_call_id'] as number | undefined) ?? 0) : 0;
}

export function backgroundOf(value: Object | null | undefined): TdObject | null {
  return value !== undefined && value !== null ? value as TdObject : null;
}

// TDLib 的 unread_count 会「幽灵未读」：读水位已经越过最后一条，计数还没清。
// 展示值在这里抹平，原始值仍留在 rawUnreadCount 里供重算。
export function effectiveUnread(unread: number, lastReadInboxId: number, lastMessageId: number): number {
  const suppressed: boolean = unread > 0 && lastMessageId > 0 && lastReadInboxId >= lastMessageId;
  if (suppressed) {
    // 诊断：反馈过"有些会话不显示未读数"。这里是**唯一**会把非零未读抹成 0
    // 的地方（另外两处是本地摘角标和 TDLib 自己下发），三个数一起打才判断
    // 得出是真幽灵未读还是误伤。只在真抹掉时打。
    logW(`effectiveUnread suppressed unread=${unread}` +
      ` lastRead=${lastReadInboxId} lastMsg=${lastMessageId}`);
    return 0;
  }
  return unread;
}

export function buildChatEntry(input: ChatEntryBuildInput): ChatEntry {
  const chat: TdObject = input.chat;
  const previous: ChatEntry | undefined = input.previous;
  const id: number = chat['id'] as number;
  const title: string = (chat['title'] as string | undefined) ?? '';
  const rawLastMessage = chat['last_message'];
  const lastMsg: TdObject | null = rawLastMessage !== undefined && rawLastMessage !== null
    ? rawLastMessage as TdObject : null;
  const photoFileId: number = smallPhotoIdOf(chat['photo'] as TdObject | undefined);
  // 头像已经落地过时保留解析结果：getChat/updateNewChat 可能在图片完成之后
  // 才把它推过来，照片没变就不该把路径清空。
  const samePhoto: boolean = previous !== undefined && previous.photoFileId === photoFileId;
  const groupCallId: number = videoChatIdOf(chat['video_chat'] as TdObject | undefined);
  const sameGroupCall: boolean = previous !== undefined && previous.liveGroupCallId === groupCallId;
  const lastReadOutboxId: number = (chat['last_read_outbox_message_id'] as number | undefined) ?? 0;
  const isSavedMessages: boolean = input.selfId !== 0 && id === input.selfId;
  const kind: ChatKind = chatKindOf(chat['type'] as TdObject | undefined);
  const lastMessageId: number = messageIdOf(lastMsg);
  const entry: ChatEntry = {
    id,
    revision: previous !== undefined ? previous.revision + 1 : 0,
    title,
    isMuted: isMutedFrom(chat['notification_settings'] as TdObject | undefined),
    usesDefaultMute: usesDefaultMuteFrom(chat['notification_settings'] as TdObject | undefined),
    unreadCount: effectiveUnread(
      (chat['unread_count'] as number | undefined) ?? 0,
      (chat['last_read_inbox_message_id'] as number | undefined) ?? 0,
      lastMessageId),
    unreadMentionCount: (chat['unread_mention_count'] as number | undefined) ?? 0,
    rawUnreadCount: (chat['unread_count'] as number | undefined) ?? 0,
    lastReadInboxId: (chat['last_read_inbox_message_id'] as number | undefined) ?? 0,
    lastReadOutboxId,
    lastMessageSendState: lastMessageSendStateFrom(lastMsg, lastReadOutboxId, isSavedMessages, kind),
    typingText: previous !== undefined ? previous.typingText : '',
    lastMessageText: formatPreview(lastMsg),
    lastMessageThumb: previewThumbOf(lastMsg),
    lastMessageDate: lastMsg !== null ? ((lastMsg['date'] as number | undefined) ?? 0) : 0,
    lastMessageId,
    lastSenderName: isSavedMessages ? '' : input.senderName(lastMsg ?? undefined),
    photoFileId,
    avatarPath: samePhoto ? previous!.avatarPath : '',
    initials: computeInitials(title),
    autoDeleteTime: (chat['message_auto_delete_time'] as number | undefined) ?? 0,
    kind,
    isMarkedUnread: (chat['is_marked_as_unread'] as boolean | undefined) ?? false,
    actionBar: actionBarKindOf(chat['action_bar'] as TdObject | undefined),
    actionBarCanUnarchive: actionBarCanUnarchiveOf(chat['action_bar'] as TdObject | undefined),
    // deleteChatHistory 的两个前置能力位。TDLib 没有针对它们的增量 update，
    // 只随完整 chat 对象到达；缺省取 false —— 宁可少给一个入口，也不要给一个
    // 必然报 "Can't delete history of X only for self" 的入口。
    canDeleteOnlyForSelf: (chat['can_be_deleted_only_for_self'] as boolean | undefined) ?? false,
    canDeleteForAllUsers: (chat['can_be_deleted_for_all_users'] as boolean | undefined) ?? false,
    isSavedMessages,
    background: backgroundOf(chat['background']),
    themeName: (chat['theme_name'] as string | undefined) ?? '',
    liveGroupCallId: groupCallId,
    isLive: sameGroupCall ? previous!.isLive : false,
    isRtmpLive: sameGroupCall ? previous!.isRtmpLive : false
  };
  return entry;
}
