import { getTdClient } from '../tdkit/Globals';
import { TdObject, TdRequest } from '../tdkit/TdTypes';
import { str } from '../util/strings';

// Group / channel administration. Every call goes straight to TDLib; the
// server rejects anything the current user lacks rights for, so the UI only
// hides what it knows is unavailable and surfaces server errors verbatim.

export interface GroupPermissions {
  sendMessages: boolean;
  sendMedia: boolean;
  sendPolls: boolean;
  sendOther: boolean;
  addLinkPreviews: boolean;
  changeInfo: boolean;
  inviteUsers: boolean;
  pinMessages: boolean;
}

export interface AdminRow {
  userId: number;
  isCreator: boolean;
  customTitle: string;
}

export interface InviteLinkRow {
  link: string;
  name: string;
  memberLimit: number;
  isRevoked: boolean;
  isPrimary: boolean;
}

export interface JoinRequestRow {
  userId: number;
  date: number;
  bio: string;
}

export function defaultPermissions(): GroupPermissions {
  return {
    sendMessages: true, sendMedia: true, sendPolls: true, sendOther: true,
    addLinkPreviews: true, changeInfo: false, inviteUsers: true, pinMessages: false
  };
}

export function permissionsFromTd(raw: TdObject | undefined): GroupPermissions {
  if (raw === undefined) { return defaultPermissions(); }
  const flag = (key: string): boolean => (raw[key] as boolean | undefined) ?? false;
  return {
    sendMessages: flag('can_send_basic_messages'),
    // TDLib splits media into five flags; the UI keeps one switch and writes
    // all of them together.
    sendMedia: flag('can_send_photos') || flag('can_send_videos') || flag('can_send_documents'),
    sendPolls: flag('can_send_polls'),
    sendOther: flag('can_send_other_messages'),
    addLinkPreviews: flag('can_add_link_previews'),
    changeInfo: flag('can_change_info'),
    inviteUsers: flag('can_invite_users'),
    pinMessages: flag('can_pin_messages')
  };
}

function permissionsToTd(value: GroupPermissions): TdObject {
  const out: TdObject = { '@type': 'chatPermissions' };
  out['can_send_basic_messages'] = value.sendMessages;
  out['can_send_audios'] = value.sendMedia;
  out['can_send_documents'] = value.sendMedia;
  out['can_send_photos'] = value.sendMedia;
  out['can_send_videos'] = value.sendMedia;
  out['can_send_video_notes'] = value.sendMedia;
  out['can_send_voice_notes'] = value.sendMedia;
  out['can_send_polls'] = value.sendPolls;
  out['can_send_other_messages'] = value.sendOther;
  out['can_add_link_previews'] = value.addLinkPreviews;
  out['can_change_info'] = value.changeInfo;
  out['can_invite_users'] = value.inviteUsers;
  out['can_pin_messages'] = value.pinMessages;
  out['can_create_topics'] = false;
  return out;
}

export async function setChatTitle(chatId: number, title: string): Promise<void> {
  const request: TdRequest = { '@type': 'setChatTitle' };
  request['chat_id'] = chatId;
  request['title'] = title;
  await getTdClient().send(request, 15000);
}

export async function setChatDescription(chatId: number, description: string): Promise<void> {
  const request: TdRequest = { '@type': 'setChatDescription' };
  request['chat_id'] = chatId;
  request['description'] = description;
  await getTdClient().send(request, 15000);
}

export async function setChatPhotoFromFile(chatId: number, path: string): Promise<void> {
  const inputFile: TdObject = { '@type': 'inputFileLocal' };
  inputFile['path'] = path;
  const photo: TdObject = { '@type': 'inputChatPhotoStatic' };
  photo['photo'] = inputFile;
  const request: TdRequest = { '@type': 'setChatPhoto' };
  request['chat_id'] = chatId;
  request['photo'] = photo;
  await getTdClient().send(request, 30000);
}

export async function setChatPermissions(
  chatId: number, permissions: GroupPermissions
): Promise<void> {
  const request: TdRequest = { '@type': 'setChatPermissions' };
  request['chat_id'] = chatId;
  request['permissions'] = permissionsToTd(permissions);
  await getTdClient().send(request, 15000);
}

export async function setSlowMode(chatId: number, seconds: number): Promise<void> {
  const request: TdRequest = { '@type': 'setChatSlowModeDelay' };
  request['chat_id'] = chatId;
  request['slow_mode_delay'] = seconds;
  await getTdClient().send(request, 15000);
}

export async function getAdministrators(chatId: number): Promise<AdminRow[]> {
  const request: TdRequest = { '@type': 'getChatAdministrators' };
  request['chat_id'] = chatId;
  const result = await getTdClient().send(request, 15000);
  return ((result['administrators'] as TdObject[] | undefined) ?? []).map(
    (row: TdObject): AdminRow => ({
      userId: (row['user_id'] as number | undefined) ?? 0,
      isCreator: (row['is_owner'] as boolean | undefined) ?? false,
      customTitle: (row['custom_title'] as string | undefined) ?? ''
    })
  );
}

function memberSender(userId: number): TdObject {
  const sender: TdObject = { '@type': 'messageSenderUser' };
  sender['user_id'] = userId;
  return sender;
}

// Promote to admin with the common moderation rights, or demote to member.
export async function setAdmin(
  chatId: number, userId: number, promote: boolean
): Promise<void> {
  const status: TdObject = {
    '@type': promote ? 'chatMemberStatusAdministrator' : 'chatMemberStatusMember'
  };
  if (promote) {
    const rights: TdObject = { '@type': 'chatAdministratorRights' };
    rights['can_manage_chat'] = true;
    rights['can_change_info'] = true;
    rights['can_post_messages'] = true;
    rights['can_edit_messages'] = true;
    rights['can_delete_messages'] = true;
    rights['can_invite_users'] = true;
    rights['can_restrict_members'] = true;
    rights['can_pin_messages'] = true;
    rights['can_manage_topics'] = false;
    rights['can_promote_members'] = false;
    rights['can_manage_video_chats'] = true;
    rights['can_post_stories'] = false;
    rights['can_edit_stories'] = false;
    rights['can_delete_stories'] = false;
    rights['can_manage_direct_messages'] = false;
    rights['is_anonymous'] = false;
    status['rights'] = rights;
    status['custom_title'] = '';
  }
  const request: TdRequest = { '@type': 'setChatMemberStatus' };
  request['chat_id'] = chatId;
  request['member_id'] = memberSender(userId);
  request['status'] = status;
  await getTdClient().send(request, 15000);
}

export async function banMember(
  chatId: number, userId: number, revokeMessages: boolean
): Promise<void> {
  const request: TdRequest = { '@type': 'banChatMember' };
  request['chat_id'] = chatId;
  request['member_id'] = memberSender(userId);
  request['banned_until_date'] = 0; // 0 = forever
  request['revoke_messages'] = revokeMessages;
  await getTdClient().send(request, 15000);
}

// 移出群组：把成员状态设成 left。
//
// 和 banMember 是两件事——banChatMember 是**永久封禁**（进黑名单，加不回来），
// 这里只是把人请出去，之后还能重新加入或被邀请。管理员日常要的是后者。
export async function removeMember(chatId: number, userId: number): Promise<void> {
  const status: TdObject = { '@type': 'chatMemberStatusLeft' };
  const request: TdRequest = { '@type': 'setChatMemberStatus' };
  request['chat_id'] = chatId;
  request['member_id'] = memberSender(userId);
  request['status'] = status;
  await getTdClient().send(request, 15000);
}

export async function deleteMessagesFromSender(chatId: number, userId: number): Promise<void> {
  const request: TdRequest = { '@type': 'deleteChatMessagesBySender' };
  request['chat_id'] = chatId;
  request['sender_id'] = memberSender(userId);
  await getTdClient().send(request, 20000);
}

// Add existing contacts to a group. TDLib returns the users it could not add
// (privacy settings) instead of failing the whole call.
export async function addMembers(chatId: number, userIds: number[]): Promise<number> {
  const request: TdRequest = { '@type': 'addChatMembers' };
  request['chat_id'] = chatId;
  request['user_ids'] = userIds;
  const result = await getTdClient().send(request, 20000);
  const failed = (result['failed_to_add_members'] as TdObject[] | undefined) ?? [];
  return userIds.length - failed.length;
}

// Public username for a supergroup/channel ('' makes it private).
export async function setPublicUsername(supergroupId: number, username: string): Promise<void> {
  const request: TdRequest = { '@type': 'setSupergroupUsername' };
  request['supergroup_id'] = supergroupId;
  request['username'] = username;
  await getTdClient().send(request, 15000);
}

export async function checkUsernameAvailable(chatId: number, username: string): Promise<string> {
  const request: TdRequest = { '@type': 'checkChatUsername' };
  request['chat_id'] = chatId;
  request['username'] = username;
  const result = await getTdClient().send(request, 12000);
  const type = (result['@type'] as string | undefined) ?? '';
  if (type === 'checkChatUsernameResultOk') { return ''; }
  if (type === 'checkChatUsernameResultUsernameInvalid') { return str('ca_username_invalid'); }
  if (type === 'checkChatUsernameResultUsernameOccupied') { return str('ae_username_taken'); }
  if (type === 'checkChatUsernameResultPublicChatsTooMany') { return str('ca_public_limit'); }
  if (type === 'checkChatUsernameResultPublicGroupsUnavailable') { return str('ca_cannot_public'); }
  return str('ca_username_unavailable');
}

// Bulk-delete every message in a date range (admins only).
export async function deleteMessagesByDate(
  chatId: number, minDate: number, maxDate: number
): Promise<void> {
  const request: TdRequest = { '@type': 'deleteChatMessagesByDate' };
  request['chat_id'] = chatId;
  request['min_date'] = minDate;
  request['max_date'] = maxDate;
  request['revoke'] = true;
  await getTdClient().send(request, 20000);
}

export async function getInviteLinks(chatId: number, creatorUserId: number): Promise<InviteLinkRow[]> {
  const request: TdRequest = { '@type': 'getChatInviteLinks' };
  request['chat_id'] = chatId;
  request['creator_user_id'] = creatorUserId;
  request['is_revoked'] = false;
  request['offset_date'] = 0;
  request['offset_invite_link'] = '';
  request['limit'] = 30;
  const result = await getTdClient().send(request, 15000);
  return ((result['invite_links'] as TdObject[] | undefined) ?? []).map(
    (row: TdObject): InviteLinkRow => ({
      link: (row['invite_link'] as string | undefined) ?? '',
      name: (row['name'] as string | undefined) ?? '',
      memberLimit: (row['member_limit'] as number | undefined) ?? 0,
      isRevoked: (row['is_revoked'] as boolean | undefined) ?? false,
      isPrimary: (row['is_primary'] as boolean | undefined) ?? false
    })
  );
}

export async function createInviteLink(
  chatId: number, name: string, memberLimit: number, needsApproval: boolean
): Promise<string> {
  const request: TdRequest = { '@type': 'createChatInviteLink' };
  request['chat_id'] = chatId;
  request['name'] = name;
  request['expiration_date'] = 0;
  request['member_limit'] = needsApproval ? 0 : memberLimit;
  request['creates_join_request'] = needsApproval;
  const result = await getTdClient().send(request, 15000);
  return (result['invite_link'] as string | undefined) ?? '';
}

export async function revokeInviteLink(chatId: number, link: string): Promise<void> {
  const request: TdRequest = { '@type': 'revokeChatInviteLink' };
  request['chat_id'] = chatId;
  request['invite_link'] = link;
  await getTdClient().send(request, 15000);
}

export async function getJoinRequests(chatId: number): Promise<JoinRequestRow[]> {
  const request: TdRequest = { '@type': 'getChatJoinRequests' };
  request['chat_id'] = chatId;
  request['invite_link'] = '';
  request['query'] = '';
  request['limit'] = 50;
  const result = await getTdClient().send(request, 15000);
  return ((result['requests'] as TdObject[] | undefined) ?? []).map(
    (row: TdObject): JoinRequestRow => ({
      userId: (row['user_id'] as number | undefined) ?? 0,
      date: (row['date'] as number | undefined) ?? 0,
      bio: (row['bio'] as string | undefined) ?? ''
    })
  );
}

export async function processJoinRequest(
  chatId: number, userId: number, approve: boolean
): Promise<void> {
  const request: TdRequest = { '@type': 'processChatJoinRequest' };
  request['chat_id'] = chatId;
  request['user_id'] = userId;
  request['approve'] = approve;
  await getTdClient().send(request, 15000);
}
