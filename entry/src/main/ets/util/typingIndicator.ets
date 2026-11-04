// 对方操作状态，用于聊天页顶部标题栏副标题提示。动作与到期时间一起保存。
import { TdObject } from '../tdkit/TdTypes';
import { plural, str } from './strings';

export const TYPING_ACTION_TTL_MS: number = 6000;

export interface TypingAction {
  kind: string;
  expiresAt: number;
}

// 明确支持的动作白名单；未知或缺失动作不伪装成“正在输入”。
export function typingActionKind(type: string): string {
  switch (type) {
    case 'chatActionTyping': return 'typing';
    case 'chatActionRecordingVideo': return 'record_video';
    case 'chatActionRecordingVoiceNote': return 'record_voice';
    case 'chatActionRecordingVideoNote': return 'record_video_note';
    case 'chatActionUploadingVideo': return 'upload_video';
    case 'chatActionUploadingVoiceNote': return 'upload_voice';
    case 'chatActionUploadingVideoNote': return 'upload_video_note';
    case 'chatActionUploadingPhoto': return 'upload_photo';
    case 'chatActionUploadingDocument': return 'upload_document';
    case 'chatActionChoosingSticker': return 'choose_sticker';
    case 'chatActionChoosingLocation': return 'choose_location';
    case 'chatActionChoosingContact': return 'choose_contact';
    case 'chatActionStartPlayingGame': return 'play_game';
    case 'chatActionWatchingAnimations': return 'watch_animation';
    default: return '';
  }
}

// updateChatAction 的 thread 在 topic_id 内，与 message 的顶层字段不同。
// 普通会话也不接收其他话题的状态，防止话题取消误清普通会话的提示。
export function typingActionInScope(update: TdObject, threadRootId: number,
  forumTopicId: number, directMessagesTopicId: number): boolean {
  const topic = update['topic_id'] as TdObject | undefined;
  if (directMessagesTopicId > 0) {
    return topic !== undefined && topic['@type'] === 'messageTopicDirectMessages' &&
      topic['direct_messages_chat_topic_id'] === directMessagesTopicId;
  }
  if (forumTopicId > 0) {
    return topic !== undefined && topic['@type'] === 'messageTopicForum' &&
      topic['forum_topic_id'] === forumTopicId;
  }
  if (threadRootId > 0) {
    return topic !== undefined && topic['@type'] === 'messageTopicThread' &&
      topic['message_thread_id'] === threadRootId;
  }
  return topic === undefined || topic === null;
}

export function applyTypingUpdate(senders: Map<number, TypingAction>, update: TdObject, nowMs: number,
  chatId: number, threadRootId: number, forumTopicId: number, directMessagesTopicId: number,
  myUserId: number = 0, ignoreTopicScope: boolean = false): number {
  if (((update['chat_id'] as number | undefined) ?? 0) !== chatId ||
    (!ignoreTopicScope && !typingActionInScope(update, threadRootId, forumTopicId, directMessagesTopicId))) { return 0; }
  const sender = update['sender_id'] as TdObject | undefined;
  if (sender === undefined || sender['@type'] !== 'messageSenderUser') { return 0; }
  const uid = (sender['user_id'] as number | undefined) ?? 0;
  if (uid <= 0 || (myUserId > 0 && uid === myUserId)) { return 0; }
  const action = update['action'] as TdObject | undefined;
  const type = action !== undefined ? ((action['@type'] as string | undefined) ?? '') : '';
  if (type === 'chatActionCancel') {
    senders.delete(uid);
    return uid;
  }
  const kind = typingActionKind(type);
  if (kind === '') { return 0; }
  senders.set(uid, { kind: kind, expiresAt: nowMs + TYPING_ACTION_TTL_MS });
  return uid;
}

// 收到该发送者的新消息时立即清除其正在输入状态，避免消息已落屏仍残留数秒提示。
export function clearTypingOnNewMessage(senders: Map<number, TypingAction>, message: TdObject | undefined,
  chatId: number): boolean {
  if (senders.size === 0 || message === undefined) { return false; }
  if (((message['chat_id'] as number | undefined) ?? 0) !== chatId) { return false; }
  const sender = message['sender_id'] as TdObject | undefined;
  if (sender !== undefined && sender['@type'] === 'messageSenderUser') {
    const uid = (sender['user_id'] as number | undefined) ?? 0;
    if (uid > 0 && senders.has(uid)) {
      senders.delete(uid);
      return true;
    }
  }
  return false;
}

export function headerKindForChatKind(kind: string): string {
  if (kind === 'private' || kind === 'secret' || kind === 'channel') {
    return kind;
  }
  return 'group';
}

export function pruneExpiredTyping(senders: Map<number, TypingAction>, nowMs: number): boolean {
  let changed = false;
  for (const key of Array.from(senders.keys())) {
    if ((senders.get(key)?.expiresAt ?? 0) <= nowMs) {
      senders.delete(key);
      changed = true;
    }
  }
  return changed;
}

function actionLabel(kind: string): string {
  switch (kind) {
    case 'record_video': return str('cp_action_record_video');
    case 'record_voice': return str('cp_action_record_voice');
    case 'record_video_note': return str('cp_action_record_video_note');
    case 'upload_video': return str('cp_action_upload_video');
    case 'upload_voice': return str('cp_action_upload_voice');
    case 'upload_video_note': return str('cp_action_upload_video_note');
    case 'upload_photo': return str('cp_action_upload_photo');
    case 'upload_document': return str('cp_action_upload_document');
    case 'choose_sticker': return str('cp_action_choose_sticker');
    case 'choose_location': return str('cp_action_choose_location');
    case 'choose_contact': return str('cp_action_choose_contact');
    case 'play_game': return str('cp_action_play_game');
    case 'watch_animation': return str('cp_action_watch_animation');
    case 'mixed': return str('cp_action_mixed');
    default: return '';
  }
}

export function chatActionLabelOf(headerKind: string, senders: Map<number, TypingAction>,
  displayName: (uid: number) => string): string {
  const ids = Array.from(senders.keys());
  if (ids.length === 0) { return ''; }
  let kind = senders.get(ids[0])?.kind ?? '';
  for (const id of ids) {
    if (senders.get(id)?.kind !== kind) { kind = 'mixed'; break; }
  }
  if (kind === 'typing') { return typingLabelOf(headerKind, ids, displayName); }
  const action = actionLabel(kind);
  if (headerKind === 'private' || headerKind === 'secret') { return action; }
  if (ids.length > 1) { return str('cp_action_members', ids.length, action); }
  const name = displayName(ids[0]).trim();
  return str('cp_action_member', name !== '' ? name.split(' ')[0] : str('cp_someone'), action);
}

// 保留原有输入文案及其复数规则。
export function typingLabelOf(headerKind: string, ids: number[],
  displayName: (uid: number) => string): string {
  if (ids.length === 0) {
    return '';
  }
  if (headerKind === 'private' || headerKind === 'secret') {
    return str('cp_typing');
  }
  if (ids.length > 1) {
    return plural('cp_n_typing', ids.length, ids.length);
  }
  const name = displayName(ids[0]);
  return str('cp_someone_typing', name !== '' ? name.split(' ')[0] : str('cp_someone'));
}

// 顶栏左侧已有三颗蓝点（•••），去掉文案末尾的省略号（"正在输入…" → "正在输入"）。
export function headerTypingTextOf(label: string): string {
  if (label === '') {
    return '';
  }
  return label.replace(/(?:…|\.{3})\s*$/, '');
}
