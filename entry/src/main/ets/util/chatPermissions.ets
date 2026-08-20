import { TdObject } from '../tdkit/TdTypes';

// 群/成员权限集，形状一比一对齐 TDLib 的 chatPermissions。
//
// 为什么每个媒体标志都单独留一个字段：早先这里把 can_send_photos /
// _videos / _documents / _audios / _voice_notes / _video_notes 六个标志压成
// 一个 sendMedia，读的时候只要有一项开着就算开，写的时候一把梭全写成同一个
// 值。这在"读出来再写回去"的路径上就是数据损坏——用户本来只关了语音，保存
// 一次全都被打开。单人限制面板必须逐项回填，所以压缩表示不能再用了。

export interface GroupPermissions {
  sendMessages: boolean;
  sendPhotos: boolean;
  sendVideos: boolean;
  sendDocuments: boolean;
  sendAudios: boolean;
  sendVoiceNotes: boolean;
  sendVideoNotes: boolean;
  sendOtherMessages: boolean; // 贴纸与 GIF
  sendPolls: boolean;
  addLinkPreviews: boolean;
  changeInfo: boolean;
  inviteUsers: boolean;
  pinMessages: boolean;
  createTopics: boolean;
}

export const PERM_SEND_MESSAGES: string = 'sendMessages';
export const PERM_SEND_PHOTOS: string = 'sendPhotos';
export const PERM_SEND_VIDEOS: string = 'sendVideos';
export const PERM_SEND_DOCUMENTS: string = 'sendDocuments';
export const PERM_SEND_AUDIOS: string = 'sendAudios';
export const PERM_SEND_VOICE_NOTES: string = 'sendVoiceNotes';
export const PERM_SEND_VIDEO_NOTES: string = 'sendVideoNotes';
export const PERM_SEND_OTHER: string = 'sendOtherMessages';
export const PERM_SEND_POLLS: string = 'sendPolls';
export const PERM_ADD_LINK_PREVIEWS: string = 'addLinkPreviews';
export const PERM_CHANGE_INFO: string = 'changeInfo';
export const PERM_INVITE_USERS: string = 'inviteUsers';
export const PERM_PIN_MESSAGES: string = 'pinMessages';
export const PERM_CREATE_TOPICS: string = 'createTopics';

// 「发送媒体文件 n/m」那一组的成员。顺序即界面顺序。
export const MEDIA_PERMISSION_KEYS: string[] = [
  PERM_SEND_PHOTOS, PERM_SEND_VIDEOS, PERM_SEND_DOCUMENTS, PERM_SEND_AUDIOS,
  PERM_SEND_VOICE_NOTES, PERM_SEND_VIDEO_NOTES, PERM_SEND_OTHER,
  PERM_ADD_LINK_PREVIEWS, PERM_SEND_POLLS
];

export function allPermissions(value: boolean): GroupPermissions {
  return {
    sendMessages: value, sendPhotos: value, sendVideos: value,
    sendDocuments: value, sendAudios: value, sendVoiceNotes: value,
    sendVideoNotes: value, sendOtherMessages: value, sendPolls: value,
    addLinkPreviews: value, changeInfo: value, inviteUsers: value,
    pinMessages: value, createTopics: value
  };
}

// 新群的出厂设置：能发东西、能拉人，但改群资料和置顶留给管理员。
export function defaultPermissions(): GroupPermissions {
  return {
    sendMessages: true, sendPhotos: true, sendVideos: true,
    sendDocuments: true, sendAudios: true, sendVoiceNotes: true,
    sendVideoNotes: true, sendOtherMessages: true, sendPolls: true,
    addLinkPreviews: true, changeInfo: false, inviteUsers: true,
    pinMessages: false, createTopics: false
  };
}

export function permissionsFromTd(raw: TdObject | undefined): GroupPermissions {
  if (raw === undefined) {
    return defaultPermissions();
  }
  const flag = (key: string): boolean => (raw[key] as boolean | undefined) ?? false;
  return {
    sendMessages: flag('can_send_basic_messages'),
    sendPhotos: flag('can_send_photos'),
    sendVideos: flag('can_send_videos'),
    sendDocuments: flag('can_send_documents'),
    sendAudios: flag('can_send_audios'),
    sendVoiceNotes: flag('can_send_voice_notes'),
    sendVideoNotes: flag('can_send_video_notes'),
    sendOtherMessages: flag('can_send_other_messages'),
    sendPolls: flag('can_send_polls'),
    addLinkPreviews: flag('can_add_link_previews'),
    changeInfo: flag('can_change_info'),
    inviteUsers: flag('can_invite_users'),
    pinMessages: flag('can_pin_messages'),
    createTopics: flag('can_create_topics')
  };
}

export function permissionsToTd(value: GroupPermissions): TdObject {
  const out: TdObject = { '@type': 'chatPermissions' };
  out['can_send_basic_messages'] = value.sendMessages;
  out['can_send_photos'] = value.sendPhotos;
  out['can_send_videos'] = value.sendVideos;
  out['can_send_documents'] = value.sendDocuments;
  out['can_send_audios'] = value.sendAudios;
  out['can_send_voice_notes'] = value.sendVoiceNotes;
  out['can_send_video_notes'] = value.sendVideoNotes;
  out['can_send_other_messages'] = value.sendOtherMessages;
  out['can_send_polls'] = value.sendPolls;
  out['can_add_link_previews'] = value.addLinkPreviews;
  out['can_change_info'] = value.changeInfo;
  out['can_invite_users'] = value.inviteUsers;
  out['can_pin_messages'] = value.pinMessages;
  out['can_create_topics'] = value.createTopics;
  return out;
}

export function permissionValue(p: GroupPermissions, key: string): boolean {
  if (key === PERM_SEND_MESSAGES) { return p.sendMessages; }
  if (key === PERM_SEND_PHOTOS) { return p.sendPhotos; }
  if (key === PERM_SEND_VIDEOS) { return p.sendVideos; }
  if (key === PERM_SEND_DOCUMENTS) { return p.sendDocuments; }
  if (key === PERM_SEND_AUDIOS) { return p.sendAudios; }
  if (key === PERM_SEND_VOICE_NOTES) { return p.sendVoiceNotes; }
  if (key === PERM_SEND_VIDEO_NOTES) { return p.sendVideoNotes; }
  if (key === PERM_SEND_OTHER) { return p.sendOtherMessages; }
  if (key === PERM_SEND_POLLS) { return p.sendPolls; }
  if (key === PERM_ADD_LINK_PREVIEWS) { return p.addLinkPreviews; }
  if (key === PERM_CHANGE_INFO) { return p.changeInfo; }
  if (key === PERM_INVITE_USERS) { return p.inviteUsers; }
  if (key === PERM_PIN_MESSAGES) { return p.pinMessages; }
  if (key === PERM_CREATE_TOPICS) { return p.createTopics; }
  return false;
}

// 不改原对象，返回改过一项的新集合。界面上每个开关都走这里。
export function withPermission(
  p: GroupPermissions, key: string, value: boolean
): GroupPermissions {
  return {
    sendMessages: key === PERM_SEND_MESSAGES ? value : p.sendMessages,
    sendPhotos: key === PERM_SEND_PHOTOS ? value : p.sendPhotos,
    sendVideos: key === PERM_SEND_VIDEOS ? value : p.sendVideos,
    sendDocuments: key === PERM_SEND_DOCUMENTS ? value : p.sendDocuments,
    sendAudios: key === PERM_SEND_AUDIOS ? value : p.sendAudios,
    sendVoiceNotes: key === PERM_SEND_VOICE_NOTES ? value : p.sendVoiceNotes,
    sendVideoNotes: key === PERM_SEND_VIDEO_NOTES ? value : p.sendVideoNotes,
    sendOtherMessages: key === PERM_SEND_OTHER ? value : p.sendOtherMessages,
    sendPolls: key === PERM_SEND_POLLS ? value : p.sendPolls,
    addLinkPreviews: key === PERM_ADD_LINK_PREVIEWS ? value : p.addLinkPreviews,
    changeInfo: key === PERM_CHANGE_INFO ? value : p.changeInfo,
    inviteUsers: key === PERM_INVITE_USERS ? value : p.inviteUsers,
    pinMessages: key === PERM_PIN_MESSAGES ? value : p.pinMessages,
    createTopics: key === PERM_CREATE_TOPICS ? value : p.createTopics
  };
}

export function withAllMedia(p: GroupPermissions, value: boolean): GroupPermissions {
  let next: GroupPermissions = p;
  for (const key of MEDIA_PERMISSION_KEYS) {
    next = withPermission(next, key, value);
  }
  return next;
}

// 「9/10」左边那个数：媒体子组里开着的项数。
export function mediaOnCount(p: GroupPermissions): number {
  let count = 0;
  for (const key of MEDIA_PERMISSION_KEYS) {
    if (permissionValue(p, key)) {
      count++;
    }
  }
  return count;
}

export function anyMedia(p: GroupPermissions): boolean {
  return mediaOnCount(p) > 0;
}

// 成员权限不能超过群本身的默认权限——TDLib 会拒。界面据此把不可能打开的
// 开关直接禁掉，而不是等用户点完再报错。
export function clampToChatPermissions(
  member: GroupPermissions, chat: GroupPermissions
): GroupPermissions {
  return {
    sendMessages: member.sendMessages && chat.sendMessages,
    sendPhotos: member.sendPhotos && chat.sendPhotos,
    sendVideos: member.sendVideos && chat.sendVideos,
    sendDocuments: member.sendDocuments && chat.sendDocuments,
    sendAudios: member.sendAudios && chat.sendAudios,
    sendVoiceNotes: member.sendVoiceNotes && chat.sendVoiceNotes,
    sendVideoNotes: member.sendVideoNotes && chat.sendVideoNotes,
    sendOtherMessages: member.sendOtherMessages && chat.sendOtherMessages,
    sendPolls: member.sendPolls && chat.sendPolls,
    addLinkPreviews: member.addLinkPreviews && chat.addLinkPreviews,
    changeInfo: member.changeInfo && chat.changeInfo,
    inviteUsers: member.inviteUsers && chat.inviteUsers,
    pinMessages: member.pinMessages && chat.pinMessages,
    createTopics: member.createTopics && chat.createTopics
  };
}

export const RESTRICT_FOREVER: number = 0;
export const RESTRICT_DAY_SECONDS: number = 86400;
export const RESTRICT_WEEK_SECONDS: number = 604800;
export const RESTRICT_MONTH_SECONDS: number = 2592000;

// 时限 → TDLib 的 restricted_until_date。0 表示永久，其余是绝对秒级时间戳。
export function restrictUntilDate(nowSeconds: number, durationSeconds: number): number {
  if (durationSeconds <= 0) {
    return RESTRICT_FOREVER;
  }
  return Math.floor(nowSeconds) + durationSeconds;
}
