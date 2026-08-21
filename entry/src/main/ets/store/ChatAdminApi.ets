import { getTdClient } from '../tdkit/Globals';
import { TdObject, TdRequest } from '../tdkit/TdTypes';
import { str } from '../util/strings';
import {
  AdminRights, adminRightsFromTd, adminRightsToTd, allAdminRights
} from '../util/adminRights';
import {
  GroupPermissions, allPermissions, permissionsFromTd, permissionsToTd
} from '../util/chatPermissions';

// Group / channel administration. Every call goes straight to TDLib; the
// server rejects anything the current user lacks rights for, so the UI only
// hides what it knows is unavailable and surfaces server errors verbatim.

// 一位成员当前的状态。提权/限制面板都必须先读它再回填，绝不能凭空写一组
// 权限上去——那会把对方原有的头衔和勾选冲掉。
export interface MemberStatusInfo {
  type: string;            // chatMemberStatus* 的 @type，'' 表示读不到
  customTitle: string;
  rights: AdminRights;
  permissions: GroupPermissions;
  isMember: boolean;
  restrictedUntil: number; // 绝对秒级时间戳，0 = 永久
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

// 读出一位成员当前的状态。提权/限制面板开场就调它——先读后写是这条路径上
// 唯一安全的做法：TDLib 的 setChatMemberStatus 是整体覆盖，没有"只改一项"。
export async function getMemberStatus(
  chatId: number, userId: number
): Promise<MemberStatusInfo> {
  const request: TdRequest = { '@type': 'getChatMember' };
  request['chat_id'] = chatId;
  request['member_id'] = memberSender(userId);
  const result = await getTdClient().send(request, 15000);
  const status = result['status'] as TdObject | undefined;
  const type = (status?.['@type'] as string | undefined) ?? '';
  const isCreator = type === 'chatMemberStatusCreator';
  return {
    type,
    customTitle: (status?.['custom_title'] as string | undefined) ?? '',
    rights: isCreator
      ? allAdminRights(true)
      : adminRightsFromTd(status?.['rights'] as TdObject | undefined),
    // 只有 restricted 带 permissions；其余状态下这个字段没有意义，交给
    // 调用方拿群默认权限兜底。
    permissions: type === 'chatMemberStatusRestricted'
      ? permissionsFromTd(status?.['permissions'] as TdObject | undefined)
      : allPermissions(true),
    isMember: type === 'chatMemberStatusRestricted'
      ? ((status?.['is_member'] as boolean | undefined) ?? false)
      : (type === 'chatMemberStatusMember' || type === 'chatMemberStatusAdministrator' ||
        isCreator),
    restrictedUntil: (status?.['restricted_until_date'] as number | undefined) ?? 0
  };
}

// 只有「邀请用户」一项权限——这是当年"给普通成员挂头衔"实验造出的空壳
// 管理员的特征。清头衔时顺手把这种空壳降回普通成员。
function isTitleOnlyRights(rights: AdminRights): boolean {
  return rights.inviteUsers &&
    !rights.manageChat && !rights.changeInfo && !rights.postMessages &&
    !rights.editMessages && !rights.deleteMessages && !rights.restrictMembers &&
    !rights.pinMessages && !rights.manageTopics && !rights.promoteMembers &&
    !rights.manageVideoChats && !rights.postStories && !rights.editStories &&
    !rights.deleteStories && !rights.manageDirectMessages && !rights.isAnonymous;
}

// 提为管理员 / 改管理员权限。头衔和权限都由调用方给全，因为这是一次整体覆盖。
export async function promoteMember(
  chatId: number, userId: number, customTitle: string, rights: AdminRights
): Promise<void> {
  const status: TdObject = { '@type': 'chatMemberStatusAdministrator' };
  status['custom_title'] = customTitle;
  status['rights'] = adminRightsToTd(rights);
  const request: TdRequest = { '@type': 'setChatMemberStatus' };
  request['chat_id'] = chatId;
  request['member_id'] = memberSender(userId);
  request['status'] = status;
  await getTdClient().send(request, 15000);
}

// 撤销管理员：退回普通成员，人还在群里。
// 只改头衔，别的一概不动。
//
// TDLib 的 setChatMemberStatus 是**整体覆盖**，没有"只改一项"，所以必须先读
// 回当前状态、把 rights 原样带回去。少了这一步，改个称呼会把这位管理员的权限
// 全部重置——这正是旧 setAdmin() 的毛病。
export async function setMemberTitle(
  chatId: number, userId: number, title: string
): Promise<void> {
  const current: MemberStatusInfo = await getMemberStatus(chatId, userId);
  const next: string = title.trim();
  if (current.type === 'chatMemberStatusAdministrator') {
    if (next === '' && isTitleOnlyRights(current.rights)) {
      // 由"给普通成员挂头衔"造出来的最小权限管理员，头衔一清就降回普通
      // 成员——别留一个空壳管理员在名单里。真正的管理员清头衔不受影响。
      await demoteMember(chatId, userId);
      return;
    }
    await promoteMember(chatId, userId, next, current.rights);
    return;
  }
  // 头衔是管理员状态的字段，普通成员无处可挂。曾试过零权限提权（服务端当
  // 普通成员、头衔静默丢）和最小权限提权（真把人提成管理员），都不是"设个
  // 标签"该有的样子——入口已退回仅管理员，走到这里说明期间身份变了。
  throw new Error('member is not an administrator');
}

export async function demoteMember(chatId: number, userId: number): Promise<void> {
  const status: TdObject = { '@type': 'chatMemberStatusMember' };
  const request: TdRequest = { '@type': 'setChatMemberStatus' };
  request['chat_id'] = chatId;
  request['member_id'] = memberSender(userId);
  request['status'] = status;
  await getTdClient().send(request, 15000);
}

// 限制一位成员。untilDate = 0 表示永久；isMember=false 会把人踢出去，所以
// 面板上一律传 true——限制的语义是"留在群里但受限"。
export async function restrictMember(
  chatId: number, userId: number, permissions: GroupPermissions,
  untilDate: number, isMember: boolean
): Promise<void> {
  const status: TdObject = { '@type': 'chatMemberStatusRestricted' };
  status['is_member'] = isMember;
  status['restricted_until_date'] = untilDate;
  status['permissions'] = permissionsToTd(permissions);
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
