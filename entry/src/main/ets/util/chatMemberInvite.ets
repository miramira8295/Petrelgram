import { TdObject, TdRequest, TdError } from '../tdkit/TdTypes';

export type MemberInviteClient = (request: TdRequest, timeoutMs: number) => Promise<TdObject>;

export interface MemberInviteContext {
  title: string;
  canInvite: boolean;
  selfUserId: number;
  maxSelectable: number;
}

export interface MemberInviteResult {
  addedUserIds: number[];
  failedUserIds: number[];
  existingUserIds: number[];
}

export function isPresentChatMember(status: TdObject | undefined): boolean {
  const type = (status?.['@type'] as string | undefined) ?? '';
  if (type === 'chatMemberStatusCreator' || type === 'chatMemberStatusRestricted') {
    return (status?.['is_member'] as boolean | undefined) ?? false;
  }
  return type === 'chatMemberStatusMember' || type === 'chatMemberStatusAdministrator';
}

export function canInviteChatMembers(status: TdObject | undefined,
  permissions: TdObject | undefined, isChannel: boolean): boolean {
  if (!isPresentChatMember(status)) { return false; }
  const type = (status?.['@type'] as string | undefined) ?? '';
  if (type === 'chatMemberStatusCreator') { return true; }
  if (type === 'chatMemberStatusAdministrator') {
    const rights = status?.['rights'] as TdObject | undefined;
    return (rights?.['can_invite_users'] as boolean | undefined) ?? false;
  }
  if (isChannel || permissions?.['can_invite_users'] !== true) { return false; }
  if (type === 'chatMemberStatusRestricted') {
    const own = status?.['permissions'] as TdObject | undefined;
    return own?.['can_invite_users'] === true;
  }
  return type === 'chatMemberStatusMember';
}

function requireActive(active: () => boolean): void {
  if (!active()) { throw new Error('INVITE_SESSION_CHANGED'); }
}

export async function loadMemberInviteContext(client: MemberInviteClient, chatId: number,
  active: () => boolean): Promise<MemberInviteContext> {
  requireActive(active);
  const chatRequest: TdRequest = { '@type': 'getChat' };
  chatRequest['chat_id'] = chatId;
  const chat = await client(chatRequest, 12000);
  requireActive(active);
  const type = (chat['type'] as TdObject | undefined) ?? {};
  const kind = (type?.['@type'] as string | undefined) ?? '';
  const basic = kind === 'chatTypeBasicGroup';
  if (!basic && kind !== 'chatTypeSupergroup') { throw new Error('CHAT_ADMIN_REQUIRED'); }
  const request: TdRequest = { '@type': basic ? 'getBasicGroup' : 'getSupergroup' };
  request[basic ? 'basic_group_id' : 'supergroup_id'] = type[basic ? 'basic_group_id' : 'supergroup_id'];
  const group = await client(request, 12000);
  requireActive(active);
  const canInvite = canInviteChatMembers(group['status'] as TdObject | undefined,
    chat['permissions'] as TdObject | undefined, !basic && group['is_channel'] === true);
  if (!canInvite) { throw new Error('CHAT_ADMIN_REQUIRED'); }
  const me = await client({ '@type': 'getMe' } as TdRequest, 12000);
  requireActive(active);
  let maxSelectable = 100; // TDLib 超级群/频道单次 addChatMembers 上限。
  if (basic) {
    let sizeMax = 200;
    try {
      const optionRequest: TdRequest = { '@type': 'getOption' };
      optionRequest['name'] = 'basic_group_size_max';
      const option = await client(optionRequest, 12000);
      const value = Number(option['value']);
      if (Number.isFinite(value) && value > 0) { sizeMax = Math.floor(value); }
    } catch (_error) { /* 旧版 TDLib 没有该选项时采用默认容量。 */ }
    requireActive(active);
    maxSelectable = Math.max(0, sizeMax - ((group['member_count'] as number | undefined) ?? sizeMax));
  }
  return { title: (chat['title'] as string | undefined) ?? '', canInvite,
    selfUserId: (me['id'] as number | undefined) ?? 0, maxSelectable };
}

export function parseMemberInviteResult(result: TdObject, userIds: number[],
  existingUserIds: number[]): MemberInviteResult {
  const type = (result['@type'] as string | undefined) ?? '';
  if (type !== 'failedToAddMembers' && type !== 'ok') { throw new Error('INVITE_RESULT_UNKNOWN'); }
  const failed = (result['failed_to_add_members'] as TdObject[] | undefined) ?? [];
  const failedUserIds = Array.from(new Set(failed.map((entry: TdObject): number =>
    (entry['user_id'] as number | undefined) ?? 0))).filter((id: number): boolean => userIds.indexOf(id) >= 0);
  return { failedUserIds, existingUserIds,
    addedUserIds: userIds.filter((id: number): boolean => failedUserIds.indexOf(id) < 0) };
}

// 选人期间权限/成员关系可能变化。提交前重新查询，且在每个 await 后检查原账号/页面。
export async function submitMemberInvites(client: MemberInviteClient, chatId: number, selectedIds: number[],
  active: () => boolean): Promise<MemberInviteResult> {
  const context = await loadMemberInviteContext(client, chatId, active);
  const ids = Array.from(new Set(selectedIds)).filter((id: number): boolean => id > 0 && id !== context.selfUserId);
  const existingUserIds: number[] = [];
  const pending: number[] = [];
  for (let offset = 0; offset < ids.length; offset += 6) {
    requireActive(active);
    const batch = ids.slice(offset, offset + 6);
    const present = await Promise.all(batch.map(async (id: number): Promise<boolean> => {
      try {
        const memberRequest: TdRequest = { '@type': 'getChatMember' };
        memberRequest['chat_id'] = chatId;
        const sender: TdObject = { '@type': 'messageSenderUser', 'user_id': id };
        memberRequest['member_id'] = sender;
        const member = await client(memberRequest, 12000);
        if (member['status'] === undefined) { throw new Error('INVITE_MEMBER_UNKNOWN'); }
        return isPresentChatMember(member['status'] as TdObject | undefined);
      } catch (error) {
        const message = (error as TdError).message.toUpperCase();
        if (message.indexOf('USER_NOT_PARTICIPANT') >= 0 || message.indexOf('MEMBER_NOT_FOUND') >= 0) { return false; }
        throw error as Error;
      }
    }));
    requireActive(active);
    for (let i = 0; i < batch.length; i++) {
      if (present[i]) { existingUserIds.push(batch[i]); } else { pending.push(batch[i]); }
    }
  }
  if (pending.length === 0) { return { addedUserIds: [], failedUserIds: [], existingUserIds }; }
  if (pending.length > context.maxSelectable) { throw new Error('USERS_TOO_MUCH'); }
  requireActive(active);
  const addRequest: TdRequest = { '@type': 'addChatMembers' };
  addRequest['chat_id'] = chatId;
  addRequest['user_ids'] = pending;
  const result = await client(addRequest, 20000);
  requireActive(active);
  return parseMemberInviteResult(result, pending, existingUserIds);
}
