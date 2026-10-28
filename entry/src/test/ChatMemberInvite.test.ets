import { describe, it, expect } from '@ohos/hypium';
import { TdObject, TdRequest, TdError } from '../main/ets/tdkit/TdTypes';
import { canInviteChatMembers, loadMemberInviteContext, parseMemberInviteResult,
  submitMemberInvites } from '../main/ets/util/chatMemberInvite';

class InviteFixture {
  requests: TdRequest[] = [];
  active: boolean = true;
  stopAfter: string = '';
  failMember: boolean = false;
  failAdd: boolean = false;
  allowed: boolean = true;
  basic: boolean = false;
  existing: number[] = [2];
  async send(req: TdRequest): Promise<TdObject> {
    this.requests.push(req);
    const type = req['@type'];
    if (type === this.stopAfter) { this.active = false; }
    if (type === 'getChat') {
      const groupType: TdObject = { '@type': this.basic ? 'chatTypeBasicGroup' : 'chatTypeSupergroup',
        'basic_group_id': 7, 'supergroup_id': 8 };
      const permissions: TdObject = { 'can_invite_users': this.allowed };
      return { 'title': 'Test', 'type': groupType, 'permissions': permissions };
    }
    if (type === 'getSupergroup' || type === 'getBasicGroup') {
      const status: TdObject = { '@type': 'chatMemberStatusMember' };
      return { 'status': status, 'is_channel': false, 'member_count': 198 };
    }
    if (type === 'getMe') { return { 'id': 1 }; }
    if (type === 'getOption') { return { 'value': '200' }; }
    if (type === 'getChatMember') {
      if (this.failMember) { throw new TdError(500, 'NETWORK_ERROR'); }
      const sender = req['member_id'] as TdObject;
      const status: TdObject = { '@type': this.existing.indexOf(sender['user_id'] as number) >= 0
        ? 'chatMemberStatusMember' : 'chatMemberStatusLeft' };
      return { 'status': status };
    }
    if (this.failAdd) { throw new TdError(-1, 'request timeout'); }
    const failure: TdObject = { 'user_id': 4 };
    return { '@type': 'failedToAddMembers', 'failed_to_add_members': [failure] };
  }
}

async function submit(f: InviteFixture, ids: number[]): Promise<string> {
  try {
    await submitMemberInvites((r: TdRequest, _ms: number): Promise<TdObject> => f.send(r), 99, ids,
      (): boolean => f.active);
    return '';
  } catch (error) { return (error as Error).message; }
}

export default function chatMemberInviteTest(): void {
  describe('ChatMemberInvite', (): void => {
    it('ordinary_members_respect_group_permission_and_channel', 0, (): void => {
      const member: TdObject = { '@type': 'chatMemberStatusMember' };
      const allow: TdObject = { 'can_invite_users': true };
      expect(canInviteChatMembers(member, allow, false)).assertTrue();
      expect(canInviteChatMembers(member, allow, true)).assertFalse();
      expect(canInviteChatMembers(member, undefined, false)).assertFalse();
    });
    it('admin_requires_invite_right_while_creator_can_invite', 0, (): void => {
      const rights: TdObject = { 'can_invite_users': true };
      const admin: TdObject = { '@type': 'chatMemberStatusAdministrator', 'rights': rights };
      expect(canInviteChatMembers(admin, undefined, true)).assertTrue();
      rights['can_invite_users'] = false;
      expect(canInviteChatMembers(admin, undefined, false)).assertFalse();
      const creator: TdObject = { '@type': 'chatMemberStatusCreator', 'is_member': true };
      expect(canInviteChatMembers(creator, undefined, true)).assertTrue();
    });
    it('restricted_and_departed_members_cannot_bypass_permissions', 0, (): void => {
      const own: TdObject = { 'can_invite_users': false };
      const status: TdObject = { '@type': 'chatMemberStatusRestricted', 'is_member': true, 'permissions': own };
      const allow: TdObject = { 'can_invite_users': true };
      expect(canInviteChatMembers(status, allow, false)).assertFalse();
      own['can_invite_users'] = true;
      expect(canInviteChatMembers(status, allow, false)).assertTrue();
      status['is_member'] = false;
      expect(canInviteChatMembers(status, allow, false)).assertFalse();
    });
    it('partial_result_preserves_only_actual_failures', 0, (): void => {
      const failure: TdObject = { 'user_id': 4 };
      const unrelated: TdObject = { 'user_id': 100 };
      const result: TdObject = { '@type': 'failedToAddMembers', 'failed_to_add_members': [failure, failure, unrelated] };
      const parsed = parseMemberInviteResult(result, [3, 4], [2]);
      expect(parsed.addedUserIds.join(',')).assertEqual('3');
      expect(parsed.failedUserIds.join(',')).assertEqual('4');
      expect(parsed.existingUserIds.join(',')).assertEqual('2');
    });
    it('unknown_response_does_not_report_success', 0, (): void => {
      let message = '';
      const result: TdObject = { '@type': 'unexpected' };
      try { parseMemberInviteResult(result, [3], []); } catch (error) { message = (error as Error).message; }
      expect(message).assertEqual('INVITE_RESULT_UNKNOWN');
    });
    it('submit_removes_self_duplicates_and_existing_members', 0, async (): Promise<void> => {
      const f = new InviteFixture();
      expect(await submit(f, [1, 2, 3, 3, 4])).assertEqual('');
      const adds = f.requests.filter((r: TdRequest): boolean => r['@type'] === 'addChatMembers');
      expect(adds.length).assertEqual(1);
      expect((adds[0]['user_ids'] as number[]).join(',')).assertEqual('3,4');
      expect(adds[0]['chat_id']).assertEqual(99);
    });
    it('permission_revocation_stops_submission', 0, async (): Promise<void> => {
      const f = new InviteFixture(); f.allowed = false;
      expect(await submit(f, [3])).assertEqual('CHAT_ADMIN_REQUIRED');
      expect(f.requests.length).assertEqual(2);
    });
    it('session_change_after_lookup_prevents_add', 0, async (): Promise<void> => {
      const f = new InviteFixture(); f.stopAfter = 'getChatMember';
      expect(await submit(f, [3])).assertEqual('INVITE_SESSION_CHANGED');
      expect(f.requests.some((r: TdRequest): boolean => r['@type'] === 'addChatMembers')).assertFalse();
    });
    it('network_error_in_member_lookup_does_not_add', 0, async (): Promise<void> => {
      const f = new InviteFixture(); f.failMember = true;
      expect(await submit(f, [3])).assertEqual('NETWORK_ERROR');
      expect(f.requests.some((r: TdRequest): boolean => r['@type'] === 'addChatMembers')).assertFalse();
    });
    it('basic_group_capacity_accounts_for_existing_members', 0, async (): Promise<void> => {
      const f = new InviteFixture(); f.basic = true;
      const context = await loadMemberInviteContext((r: TdRequest, _ms: number): Promise<TdObject> => f.send(r),
        99, (): boolean => f.active);
      expect(context.maxSelectable).assertEqual(2);
      expect(await submit(f, [3, 4, 5])).assertEqual('USERS_TOO_MUCH');
    });
    it('timeout_is_propagated_without_retry', 0, async (): Promise<void> => {
      const f = new InviteFixture(); f.failAdd = true;
      expect(await submit(f, [3])).assertEqual('request timeout');
      expect(f.requests.filter((r: TdRequest): boolean => r['@type'] === 'addChatMembers').length).assertEqual(1);
    });
    it('already_present_selection_skips_mutation', 0, async (): Promise<void> => {
      const f = new InviteFixture();
      expect(await submit(f, [1, 2])).assertEqual('');
      expect(f.requests.some((r: TdRequest): boolean => r['@type'] === 'addChatMembers')).assertFalse();
    });
  });
}
