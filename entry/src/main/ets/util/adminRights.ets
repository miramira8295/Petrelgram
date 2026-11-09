import { TdObject } from '../tdkit/TdTypes';

// 管理员权限集，形状对齐 TDLib 的 chatAdministratorRights。
//
// 提权面板必须"先读后写"：把成员当前的 rights 读出来回填，改哪一项写哪一
// 项。旧的 setAdmin() 是写死一组常量，谁被它提一次，原有的头衔和权限就全被
// 冲掉了——这里保留全部字段（含界面上不展示的 manageTopics /
// manageDirectMessages），就是为了让读—改—写能原样往返。

export interface AdminRights {
  manageChat: boolean;
  changeInfo: boolean;
  postMessages: boolean;      // 频道专用
  editMessages: boolean;      // 频道专用
  deleteMessages: boolean;
  inviteUsers: boolean;
  restrictMembers: boolean;
  pinMessages: boolean;
  manageTopics: boolean;
  promoteMembers: boolean;
  manageVideoChats: boolean;
  postStories: boolean;
  editStories: boolean;
  deleteStories: boolean;
  manageDirectMessages: boolean;
  manageTags: boolean;
  isAnonymous: boolean;
}

export const RIGHT_CHANGE_INFO: string = 'changeInfo';
export const RIGHT_POST_MESSAGES: string = 'postMessages';
export const RIGHT_EDIT_MESSAGES: string = 'editMessages';
export const RIGHT_DELETE_MESSAGES: string = 'deleteMessages';
export const RIGHT_INVITE_USERS: string = 'inviteUsers';
export const RIGHT_RESTRICT_MEMBERS: string = 'restrictMembers';
export const RIGHT_PIN_MESSAGES: string = 'pinMessages';
export const RIGHT_PROMOTE_MEMBERS: string = 'promoteMembers';
export const RIGHT_MANAGE_VIDEO_CHATS: string = 'manageVideoChats';
export const RIGHT_IS_ANONYMOUS: string = 'isAnonymous';
export const RIGHT_POST_STORIES: string = 'postStories';
export const RIGHT_EDIT_STORIES: string = 'editStories';
export const RIGHT_DELETE_STORIES: string = 'deleteStories';

// 「管理动态 n/m」那一组。
export const STORY_RIGHT_KEYS: string[] = [
  RIGHT_POST_STORIES, RIGHT_EDIT_STORIES, RIGHT_DELETE_STORIES
];

export function allAdminRights(value: boolean): AdminRights {
  return {
    manageChat: value, changeInfo: value, postMessages: value,
    editMessages: value, deleteMessages: value, inviteUsers: value,
    restrictMembers: value, pinMessages: value, manageTopics: value,
    promoteMembers: value, manageVideoChats: value, postStories: value,
    editStories: value, deleteStories: value, manageDirectMessages: value,
    manageTags: value,
    isAnonymous: value
  };
}

// 新提一位管理员时的出厂勾选：日常管理都给，但不给"再提别人"和匿名。
export function defaultAdminRights(): AdminRights {
  return {
    manageChat: true, changeInfo: true, postMessages: true,
    editMessages: true, deleteMessages: true, inviteUsers: true,
    restrictMembers: true, pinMessages: true, manageTopics: false,
    promoteMembers: false, manageVideoChats: true, postStories: false,
    editStories: false, deleteStories: false, manageDirectMessages: false,
    manageTags: false,
    isAnonymous: false
  };
}

export function adminRightsFromTd(raw: TdObject | undefined): AdminRights {
  if (raw === undefined) {
    return allAdminRights(false);
  }
  const flag = (key: string): boolean => (raw[key] as boolean | undefined) ?? false;
  return {
    manageChat: flag('can_manage_chat'),
    changeInfo: flag('can_change_info'),
    postMessages: flag('can_post_messages'),
    editMessages: flag('can_edit_messages'),
    deleteMessages: flag('can_delete_messages'),
    inviteUsers: flag('can_invite_users'),
    restrictMembers: flag('can_restrict_members'),
    pinMessages: flag('can_pin_messages'),
    manageTopics: flag('can_manage_topics'),
    promoteMembers: flag('can_promote_members'),
    manageVideoChats: flag('can_manage_video_chats'),
    postStories: flag('can_post_stories'),
    editStories: flag('can_edit_stories'),
    deleteStories: flag('can_delete_stories'),
    manageDirectMessages: flag('can_manage_direct_messages'),
    manageTags: flag('can_manage_tags'),
    isAnonymous: flag('is_anonymous')
  };
}

export function adminRightsToTd(r: AdminRights): TdObject {
  const out: TdObject = { '@type': 'chatAdministratorRights' };
  // 勾了任意一项就必须带上 can_manage_chat，否则 TDLib 认为这是个"什么都
  // 不能做"的管理员，界面上会退化成普通成员。
  out['can_manage_chat'] = r.manageChat || anyAdminRight(r);
  out['can_change_info'] = r.changeInfo;
  out['can_post_messages'] = r.postMessages;
  out['can_edit_messages'] = r.editMessages;
  out['can_delete_messages'] = r.deleteMessages;
  out['can_invite_users'] = r.inviteUsers;
  out['can_restrict_members'] = r.restrictMembers;
  out['can_pin_messages'] = r.pinMessages;
  out['can_manage_topics'] = r.manageTopics;
  out['can_promote_members'] = r.promoteMembers;
  out['can_manage_video_chats'] = r.manageVideoChats;
  out['can_post_stories'] = r.postStories;
  out['can_edit_stories'] = r.editStories;
  out['can_delete_stories'] = r.deleteStories;
  out['can_manage_direct_messages'] = r.manageDirectMessages;
  out['can_manage_tags'] = r.manageTags;
  out['is_anonymous'] = r.isAnonymous;
  return out;
}

// 群主在 TDLib 里没有 rights 字段，但他什么都能做。
export function adminRightsOfStatus(status: TdObject | undefined): AdminRights {
  const type = (status?.['@type'] as string | undefined) ?? '';
  if (type === 'chatMemberStatusCreator') {
    return allAdminRights(true);
  }
  if (type === 'chatMemberStatusAdministrator') {
    return adminRightsFromTd(status?.['rights'] as TdObject | undefined);
  }
  return allAdminRights(false);
}

export function adminRightValue(r: AdminRights, key: string): boolean {
  if (key === RIGHT_CHANGE_INFO) { return r.changeInfo; }
  if (key === RIGHT_POST_MESSAGES) { return r.postMessages; }
  if (key === RIGHT_EDIT_MESSAGES) { return r.editMessages; }
  if (key === RIGHT_DELETE_MESSAGES) { return r.deleteMessages; }
  if (key === RIGHT_INVITE_USERS) { return r.inviteUsers; }
  if (key === RIGHT_RESTRICT_MEMBERS) { return r.restrictMembers; }
  if (key === RIGHT_PIN_MESSAGES) { return r.pinMessages; }
  if (key === RIGHT_PROMOTE_MEMBERS) { return r.promoteMembers; }
  if (key === RIGHT_MANAGE_VIDEO_CHATS) { return r.manageVideoChats; }
  if (key === RIGHT_IS_ANONYMOUS) { return r.isAnonymous; }
  if (key === RIGHT_POST_STORIES) { return r.postStories; }
  if (key === RIGHT_EDIT_STORIES) { return r.editStories; }
  if (key === RIGHT_DELETE_STORIES) { return r.deleteStories; }
  return false;
}

export function withAdminRight(r: AdminRights, key: string, value: boolean): AdminRights {
  return {
    manageChat: r.manageChat,
    changeInfo: key === RIGHT_CHANGE_INFO ? value : r.changeInfo,
    postMessages: key === RIGHT_POST_MESSAGES ? value : r.postMessages,
    editMessages: key === RIGHT_EDIT_MESSAGES ? value : r.editMessages,
    deleteMessages: key === RIGHT_DELETE_MESSAGES ? value : r.deleteMessages,
    inviteUsers: key === RIGHT_INVITE_USERS ? value : r.inviteUsers,
    restrictMembers: key === RIGHT_RESTRICT_MEMBERS ? value : r.restrictMembers,
    pinMessages: key === RIGHT_PIN_MESSAGES ? value : r.pinMessages,
    manageTopics: r.manageTopics,
    promoteMembers: key === RIGHT_PROMOTE_MEMBERS ? value : r.promoteMembers,
    manageVideoChats: key === RIGHT_MANAGE_VIDEO_CHATS ? value : r.manageVideoChats,
    postStories: key === RIGHT_POST_STORIES ? value : r.postStories,
    editStories: key === RIGHT_EDIT_STORIES ? value : r.editStories,
    deleteStories: key === RIGHT_DELETE_STORIES ? value : r.deleteStories,
    manageDirectMessages: r.manageDirectMessages,
    manageTags: r.manageTags,
    isAnonymous: key === RIGHT_IS_ANONYMOUS ? value : r.isAnonymous
  };
}

export function anyAdminRight(r: AdminRights): boolean {
  return r.changeInfo || r.postMessages || r.editMessages || r.deleteMessages ||
    r.inviteUsers || r.restrictMembers || r.pinMessages || r.manageTopics ||
    r.promoteMembers || r.manageVideoChats || r.postStories || r.editStories ||
    r.deleteStories || r.manageDirectMessages || r.manageTags || r.isAnonymous;
}

// 「管理动态 3/3」左边那个数。
export function storyRightsOnCount(r: AdminRights): number {
  let count = 0;
  for (const key of STORY_RIGHT_KEYS) {
    if (adminRightValue(r, key)) {
      count++;
    }
  }
  return count;
}

// 授不出去比自己还大的权限——TDLib 会拒，界面也不该让用户点了才失败。
// 群主不受限：allAdminRights(true) 与任何集合相交都是原集合。
export function limitAdminRights(desired: AdminRights, allowed: AdminRights): AdminRights {
  return {
    manageChat: desired.manageChat && allowed.manageChat,
    changeInfo: desired.changeInfo && allowed.changeInfo,
    postMessages: desired.postMessages && allowed.postMessages,
    editMessages: desired.editMessages && allowed.editMessages,
    deleteMessages: desired.deleteMessages && allowed.deleteMessages,
    inviteUsers: desired.inviteUsers && allowed.inviteUsers,
    restrictMembers: desired.restrictMembers && allowed.restrictMembers,
    pinMessages: desired.pinMessages && allowed.pinMessages,
    manageTopics: desired.manageTopics && allowed.manageTopics,
    promoteMembers: desired.promoteMembers && allowed.promoteMembers,
    manageVideoChats: desired.manageVideoChats && allowed.manageVideoChats,
    postStories: desired.postStories && allowed.postStories,
    editStories: desired.editStories && allowed.editStories,
    deleteStories: desired.deleteStories && allowed.deleteStories,
    manageDirectMessages: desired.manageDirectMessages && allowed.manageDirectMessages,
    manageTags: desired.manageTags && allowed.manageTags,
    isAnonymous: desired.isAnonymous && allowed.isAnonymous
  };
}
