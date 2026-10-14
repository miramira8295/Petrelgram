import { describe, expect, it } from '@ohos/hypium';
import { TdClient } from '../main/ets/tdkit/TdClient';
import { TdBridge, TdObject } from '../main/ets/tdkit/TdTypes';
import { chatJoinOutcome, joinChat } from '../main/ets/util/chatJoin';
import { InviteJoinResolver } from '../main/ets/util/inviteJoinResolver';
import { MembershipSession } from '../main/ets/pages/chat/MembershipSession';
import { profileFrameKey } from '../main/ets/util/profileNav';

class JoinBridge implements TdBridge {
  receive: (json: string) => void = (): void => {};
  sent: TdObject[] = [];
  init(cb: (json: string) => void): void { this.receive = cb; }
  send(json: string): void { this.sent.push(JSON.parse(json) as TdObject); }
  reply(index: number, data: TdObject): void {
    data['@extra'] = this.sent[index]['@extra'];
    this.receive(JSON.stringify(data));
  }
}
class JoinHarness {
  bridge: JoinBridge = new JoinBridge();
  client: TdClient = new TdClient(this.bridge);
  session: MembershipSession = new MembershipSession();
  chatId: number = -100;
  state: string = 'joinable';
  joining: boolean = false;
  byRequest: boolean = false;
  joined: number = 0;
  requested: number = 0;
  failed: number = 0;
  folder: number = -1;
  constructor() {
    this.client.start();
    this.session.bind({
      chatId: (): number => this.chatId,
      isChannel: (): boolean => true,
      setMembershipState: (value: string): void => { this.state = value; },
      setJoiningChat: (value: boolean): void => { this.joining = value; },
      setIsGroup: (): void => {}, setIsChannel: (): void => {},
      commitTimelineSnapshot: (): void => {}, closeComposerSurfaces: (): void => {},
      client: (): TdClient => this.client,
      setJoinByRequest: (value: boolean): void => { this.byRequest = value; },
      onJoined: (folder?: number): void => { this.joined++; this.folder = folder ?? -1; },
      onJoinRequested: (): void => { this.requested++; },
      onJoinFailed: (): void => { this.failed++; }
    });
  }
}
async function flushJoin(): Promise<void> {
  for (let i: number = 0; i < 12; i++) { await Promise.resolve(); }
}
function rejectsResult(type: string): boolean {
  try { chatJoinOutcome({ '@type': type }, -100); return false; }
  catch (_) { return true; }
}

export default function chatJoinTest() {
  describe('ChatJoin', () => {
    it('modern_success_reads_chat_id', 0, () => {
      const result = chatJoinOutcome({ '@type': 'chatJoinResultSuccess', 'chat_id': -200 }, -100);
      expect(result.chatId).assertEqual(-200); expect(result.requested).assertFalse();
    });
    it('modern_request_is_not_membership', 0, () => {
      expect(chatJoinOutcome({ '@type': 'chatJoinResultRequestSent' }, 0).requested).assertTrue();
    });
    it('legacy_chat_reads_id', 0, () => {
      expect(chatJoinOutcome({ '@type': 'chat', 'id': -300 }, 0).chatId).assertEqual(-300);
    });
    it('legacy_ok_requires_known_chat', 0, () => {
      expect(chatJoinOutcome({ '@type': 'ok' }, -100).chatId).assertEqual(-100);
      let failed: boolean = false;
      try { chatJoinOutcome({ '@type': 'ok' }, 0); } catch (_) { failed = true; }
      expect(failed).assertTrue();
    });
    it('unknown_declined_and_bot_approval_never_count_as_joined', 0, () => {
      expect(rejectsResult('chatJoinResultDeclined')).assertTrue();
      expect(rejectsResult('chatJoinResultGuardBotApprovalRequired')).assertTrue();
      expect(rejectsResult('unexpected')).assertTrue();
      expect(rejectsResult('chatJoinResultSuccess')).assertTrue();
    });
    it('legacy_request_error_is_successful_submission_and_keeps_exact_invite', 0, async () => {
      const t = new JoinHarness();
      const pending = joinChat(t.client, 0, 'https://t.me/+test');
      expect(t.bridge.sent[0]['@type']).assertEqual('joinChatByInviteLink');
      expect(t.bridge.sent[0]['invite_link']).assertEqual('https://t.me/+test');
      t.bridge.reply(0, { '@type': 'error', 'code': 400, 'message': 'INVITE_REQUEST_SENT' });
      expect((await pending).requested).assertTrue();
    });
    it('real_errors_remain_failures_and_allow_retry', 0, async () => {
      const t = new JoinHarness();
      t.session.join(t.state);
      expect(t.bridge.sent[0]['@type']).assertEqual('joinChat');
      expect(t.bridge.sent[0]['chat_id']).assertEqual(-100);
      t.bridge.reply(0, { '@type': 'error', 'code': 400, 'message': 'INVITE_HASH_EXPIRED' });
      await flushJoin();
      expect(t.failed).assertEqual(1); expect(t.state).assertEqual('joinable');
      t.session.join(t.state);
      expect(t.bridge.sent.length).assertEqual(2);
      t.bridge.reply(1, { '@type': 'chatJoinResultRequestSent' });
      await flushJoin();
    });
    it('pending_approval_prevents_duplicate_join_and_discards_folder', 0, async () => {
      const t = new JoinHarness();
      t.session.join(t.state, 7); t.session.join(t.state, 7);
      expect(t.bridge.sent.length).assertEqual(1);
      t.bridge.reply(0, { '@type': 'chatJoinResultRequestSent' });
      await flushJoin();
      expect(t.state).assertEqual('requested'); expect(t.joined).assertEqual(0);
      expect(t.requested).assertEqual(1); expect(t.joining).assertFalse();
      t.session.applyStatus({ '@type': 'chatMemberStatusLeft' });
      expect(t.state).assertEqual('requested');
      t.session.join('joinable'); expect(t.bridge.sent.length).assertEqual(1);
      t.session.applyStatus({ '@type': 'chatMemberStatusMember' });
      expect(t.state).assertEqual('readonly'); expect(t.joined).assertEqual(1);
      expect(t.folder).assertEqual(-1);
      t.session.applyStatus({ '@type': 'chatMemberStatusMember' });
      expect(t.joined).assertEqual(1);
    });
    it('fast_approval_before_join_reply_does_not_restore_pending', 0, async () => {
      const t = new JoinHarness();
      t.session.join(t.state, 7);
      t.session.applyStatus({ '@type': 'chatMemberStatusMember' });
      t.bridge.reply(0, { '@type': 'chatJoinResultRequestSent' });
      await flushJoin();
      expect(t.requested).assertEqual(0); expect(t.joined).assertEqual(1);
      expect(t.folder).assertEqual(-1);
      // Finish the membership refresh issued after confirmed success.
      t.bridge.reply(1, { '@type': 'chat', 'type': { '@type': 'chatTypeSupergroup', 'supergroup_id': 1 } as TdObject });
      await flushJoin();
      t.bridge.reply(2, { '@type': 'supergroup', 'status': { '@type': 'chatMemberStatusMember' } as TdObject });
      await flushJoin(); expect(t.state).assertEqual('readonly');
    });
    it('late_join_reply_after_navigation_or_disposal_does_not_touch_page', 0, async () => {
      const t = new JoinHarness();
      t.session.join(t.state); t.chatId = -200;
      t.bridge.reply(0, { '@type': 'chatJoinResultRequestSent' });
      await flushJoin(); expect(t.requested).assertEqual(0);
      t.session.join(t.state); t.session.dispose();
      t.bridge.reply(1, { '@type': 'chatJoinResultRequestSent' });
      await flushJoin(); expect(t.requested).assertEqual(0);
    });
    it('banned_update_before_submission_reply_cannot_become_pending', 0, async () => {
      const t = new JoinHarness(); t.session.join(t.state);
      t.session.applyStatus({ '@type': 'chatMemberStatusBanned' });
      t.bridge.reply(0, { '@type': 'chatJoinResultRequestSent' }); await flushJoin();
      expect(t.state).assertEqual('blocked'); expect(t.requested).assertEqual(0);
    });
    it('direct_success_refreshes_real_permissions_without_unlocking_composer', 0, async () => {
      const t = new JoinHarness(); t.session.join(t.state, 5);
      t.bridge.reply(0, { '@type': 'chatJoinResultSuccess', 'chat_id': -100 }); await flushJoin();
      expect(t.joined).assertEqual(1); expect(t.folder).assertEqual(5);
      expect(t.state === 'writable').assertFalse();
      t.bridge.reply(1, { '@type': 'chat',
        'type': { '@type': 'chatTypeSupergroup', 'supergroup_id': 1 } as TdObject }); await flushJoin();
      t.bridge.reply(2, { '@type': 'supergroup',
        'status': { '@type': 'chatMemberStatusMember' } as TdObject }); await flushJoin();
      expect(t.state).assertEqual('readonly');
    });
    it('banned_status_clears_pending_without_join_notice', 0, async () => {
      const t = new JoinHarness(); t.session.join(t.state);
      t.bridge.reply(0, { '@type': 'chatJoinResultRequestSent' }); await flushJoin();
      t.session.applyStatus({ '@type': 'chatMemberStatusBanned' });
      expect(t.state).assertEqual('blocked'); expect(t.joined).assertEqual(0);
    });
    it('approval_flag_comes_from_supergroup_updates', 0, () => {
      const t = new JoinHarness();
      t.session.applySupergroup({ '@type': 'supergroup', 'join_by_request': true,
        'status': { '@type': 'chatMemberStatusLeft' } as TdObject });
      expect(t.byRequest).assertTrue(); expect(t.state).assertEqual('joinable');
      t.session.applySupergroup({ '@type': 'supergroup', 'join_by_request': false });
      expect(t.byRequest).assertFalse();
    });
    it('private_invite_resolves_after_new_chat_without_polling', 0, async () => {
      const t = new JoinHarness(); let resolved: number = 0;
      const watcher = new InviteJoinResolver(t.client, 'https://t.me/+test', (id: number): void => { resolved = id; });
      watcher.start(); watcher.start(); expect(t.bridge.sent.length).assertEqual(1);
      t.bridge.reply(0, { '@type': 'chatInviteLinkInfo', 'chat_id': 0 }); await flushJoin();
      expect(resolved).assertEqual(0); expect(t.bridge.sent.length).assertEqual(1);
      t.bridge.receive(JSON.stringify({ '@type': 'updateNewChat', 'chat': { 'id': -200 } as TdObject }));
      expect(t.bridge.sent[1]['invite_link']).assertEqual('https://t.me/+test');
      t.bridge.reply(1, { '@type': 'chatInviteLinkInfo', 'chat_id': -100 }); await flushJoin();
      expect(resolved).assertEqual(-100);
      t.bridge.receive(JSON.stringify({ '@type': 'updateNewChat' }));
      expect(t.bridge.sent.length).assertEqual(2);
    });
    it('new_chat_during_invite_check_is_not_lost', 0, async () => {
      const t = new JoinHarness(); let resolved: number = 0;
      const watcher = new InviteJoinResolver(t.client, 'https://t.me/+test', (id: number): void => { resolved = id; });
      watcher.start();
      const update: TdObject = { '@type': 'updateSupergroup',
        'supergroup': { 'status': { '@type': 'chatMemberStatusMember' } as TdObject } as TdObject };
      t.bridge.receive(JSON.stringify(update)); watcher.refresh();
      t.bridge.reply(0, { '@type': 'chatInviteLinkInfo', 'chat_id': 0 }); await flushJoin();
      expect(t.bridge.sent.length).assertEqual(2);
      t.bridge.reply(1, { '@type': 'chatInviteLinkInfo', 'chat_id': -100 }); await flushJoin();
      expect(resolved).assertEqual(-100);
    });
    it('disposed_invite_page_ignores_inflight_check', 0, async () => {
      const t = new JoinHarness(); let resolved: number = 0;
      const watcher = new InviteJoinResolver(t.client, 'https://t.me/+test', (id: number): void => { resolved = id; });
      watcher.start(); watcher.dispose();
      t.bridge.reply(0, { '@type': 'chatInviteLinkInfo', 'chat_id': -100 }); await flushJoin();
      expect(resolved).assertEqual(0);
    });
    it('failed_preview_check_can_retry_on_page_return', 0, async () => {
      const t = new JoinHarness(); let resolved: number = 0;
      const watcher = new InviteJoinResolver(t.client, 'https://t.me/+test', (id: number): void => { resolved = id; });
      watcher.start();
      t.bridge.reply(0, { '@type': 'error', 'code': 500, 'message': 'temporary' }); await flushJoin();
      watcher.refresh(); t.bridge.reply(1, { '@type': 'chatInviteLinkInfo', 'chat_id': -100 });
      await flushJoin(); expect(resolved).assertEqual(-100);
    });
    it('different_private_invites_have_distinct_profile_routes', 0, () => {
      expect(profileFrameKey('ChatProfilePage', { 'inviteLink': 'https://t.me/+a' } as TdObject) ===
        profileFrameKey('ChatProfilePage', { 'inviteLink': 'https://t.me/+b' } as TdObject)).assertFalse();
    });
  });
}
