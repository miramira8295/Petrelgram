import { describe, expect, it } from '@ohos/hypium';
import { TdBridge, TdObject } from '../main/ets/tdkit/TdTypes';
import { TdClient } from '../main/ets/tdkit/TdClient';
import { UserStore } from '../main/ets/store/UserStore';
import { MessageEntry, buildMessageEntry } from '../main/ets/store/MessageEntry';
import { loadMessageModeration, executeMessageDelete, loadMessageDeleteProperties } from '../main/ets/services/MessageModeration';
import {
  DeleteMessageChoice, hasModeration, moderationOptions, moderationTarget, messageDeleteScope, messageDeleteRevoke
} from '../main/ets/util/messageModeration';

const GROUP: TdObject = { '@type': 'chatTypeSupergroup', 'supergroup_id': 55, 'is_channel': false };
const MEMBER: TdObject = { '@type': 'chatMemberStatusMember' };
const OWNER: TdObject = { '@type': 'chatMemberStatusCreator', 'is_member': true };
function admin(del: boolean, restrict: boolean): TdObject {
  return { '@type': 'chatMemberStatusAdministrator', 'rights': {
    '@type': 'chatAdministratorRights', 'can_delete_messages': del,
    'can_restrict_members': restrict } as TdObject };
}
function choice(report: boolean = false, all: boolean = false, action: string = ''): DeleteMessageChoice {
  return { revoke: true, report, deleteAll: all, memberAction: action };
}

class ModerationBridge implements TdBridge {
  receive: (json: string) => void = (): void => {};
  requests: TdObject[] = [];
  viewer: TdObject = admin(true, true);
  target: TdObject = MEMBER;
  reportable: boolean = true;
  deleteSelf: boolean = false;
  deleteAll: boolean = true;
  propertiesById: Map<number, TdObject> = new Map();
  failType: string = '';
  failCode: number = 400;
  active: boolean = true;
  stopAfter: string = '';
  init(cb: (json: string) => void): void { this.receive = cb; }
  send(json: string): void {
    const req: TdObject = JSON.parse(json) as TdObject;
    this.requests.push(req);
    const type: string = req['@type'] as string;
    let result: TdObject = { '@type': 'ok' };
    if (type === this.failType) { result = { '@type': 'error', 'code': this.failCode, 'message': 'denied' }; }
    else if (type === 'getChat') { result = { '@type': 'chat', 'type': GROUP }; }
    else if (type === 'getChatMember') {
      result = { '@type': 'chatMember', 'status': (req['member_id'] as TdObject)['user_id'] === 1 ? this.viewer : this.target };
    } else if (type === 'getMessageProperties') {
      result = this.propertiesById.get(req['message_id'] as number) ?? {
        '@type': 'messageProperties', 'can_report_supergroup_spam': this.reportable,
        'can_be_deleted_only_for_self': this.deleteSelf, 'can_be_deleted_for_all_users': this.deleteAll };
    }
    if (type === this.stopAfter) { this.active = false; }
    result['@extra'] = req['@extra'];
    this.receive(JSON.stringify(result));
  }
  mutations(): TdObject[] {
    return this.requests.filter((req: TdObject): boolean => ['deleteMessages', 'reportSupergroupSpam',
      'deleteChatMessagesBySender', 'banChatMember', 'setChatMemberStatus'].indexOf(req['@type'] as string) >= 0);
  }
}
function clientFor(bridge: ModerationBridge): TdClient {
  const client: TdClient = new TdClient(bridge); client.start(); return client;
}
function row(client: TdClient, id: number, userId: number): MessageEntry {
  return buildMessageEntry({ '@type': 'message', 'id': id,
    'sender_id': { '@type': 'messageSenderUser', 'user_id': userId } as TdObject,
    'content': { '@type': 'messageText', 'text': { '@type': 'formattedText', 'text': 'message' } as TdObject } as TdObject
  }, new UserStore(client));
}

function deleteProperties(self: boolean, all: boolean): TdObject {
  return { '@type': 'messageProperties', 'can_be_deleted_only_for_self': self,
    'can_be_deleted_for_all_users': all };
}

export default function messageModerationTest() {
  describe('MessageModeration', () => {
    it('supergroup_channel_and_secret_server_messages_with_all_only_permission_have_no_scope_choice', 0, () => {
      const scope = messageDeleteScope([deleteProperties(false, true)]);
      expect(scope.self).assertFalse(); expect(scope.all).assertTrue();
      expect(messageDeleteRevoke(scope, false, false)).assertTrue();
    });
    it('private_and_basic_group_messages_offer_choice_only_when_both_permissions_exist', 0, () => {
      const scope = messageDeleteScope([deleteProperties(true, true)]);
      expect(scope.self).assertTrue(); expect(scope.all).assertTrue();
      expect(messageDeleteRevoke(scope, false, false)).assertFalse();
      expect(messageDeleteRevoke(scope, true, false)).assertTrue();
    });
    it('saved_and_failed_local_messages_can_remain_self_only_even_in_supergroups', 0, () => {
      const scope = messageDeleteScope([deleteProperties(true, false)]);
      expect(scope.self).assertTrue(); expect(scope.all).assertFalse();
      expect(messageDeleteRevoke(scope, true, false)).assertFalse();
    });
    it('multi_selection_uses_the_intersection_of_all_message_permissions', 0, () => {
      const self = messageDeleteScope([deleteProperties(true, true), deleteProperties(true, false)]);
      expect(self.self).assertTrue(); expect(self.all).assertFalse();
      const all = messageDeleteScope([deleteProperties(true, true), deleteProperties(false, true)]);
      expect(all.self).assertFalse(); expect(all.all).assertTrue();
    });
    it('empty_unknown_forbidden_or_disjoint_permissions_do_not_grant_a_delete_scope', 0, () => {
      for (const props of [[], [deleteProperties(false, false)], [{ '@type': 'messageProperties' } as TdObject],
        [deleteProperties(true, false), deleteProperties(false, true)]]) {
        const scope = messageDeleteScope(props);
        expect(scope.self).assertFalse(); expect(scope.all).assertFalse();
      }
    });
    it('delete_all_sender_history_always_uses_all_scope_without_changing_the_previous_checkbox_choice', 0, () => {
      const scope = messageDeleteScope([deleteProperties(true, true)]);
      expect(messageDeleteRevoke(scope, false, true)).assertTrue();
      expect(messageDeleteRevoke(scope, false, false)).assertFalse();
    });
    it('confirmed_self_scope_is_not_silently_upgraded_and_no_moderation_runs', 0, async () => {
      const b = new ModerationBridge(); b.deleteSelf = true;
      const c = clientFor(b);
      const initial = messageDeleteScope(await loadMessageDeleteProperties(c, -100, [10]));
      expect(initial.self).assertTrue();
      b.deleteSelf = false;
      const selected = choice(true, false, 'ban'); selected.revoke = false;
      const result = await executeMessageDelete(c, -100, 1, [10], { userId: 7, name: 'Ann' },
        selected, (): boolean => true, (): void => {});
      expect(result.failed).assertEqual('scope'); expect(b.mutations().length).assertEqual(0);
    });
    it('confirmed_all_scope_is_not_silently_downgraded_when_one_selected_message_loses_permission', 0, async () => {
      const b = new ModerationBridge(); const c = clientFor(b);
      b.propertiesById.set(20, deleteProperties(true, false));
      const result = await executeMessageDelete(c, -100, 1, [10, 20], null,
        choice(), (): boolean => true, (): void => {});
      expect(result.failed).assertEqual('scope'); expect(b.mutations().length).assertEqual(0);
    });
    it('unreadable_message_permissions_prevent_every_write_and_do_not_start_row_fading', 0, async () => {
      const b = new ModerationBridge(); const c = clientFor(b);
      b.failType = 'getMessageProperties'; b.failCode = -1; let faded: boolean = false;
      const result = await executeMessageDelete(c, -100, 1, [10], { userId: 7, name: 'Ann' },
        choice(true, true, 'ban'), (): boolean => true, (): void => { faded = true; });
      expect(result.failed).assertEqual('scope'); expect(b.mutations().length).assertEqual(0);
      expect(faded).assertFalse();
      expect(result.error).assertEqual('dm_scope_unavailable');
    });
    it('scope_and_spam_checks_share_one_property_read_per_message', 0, async () => {
      const b = new ModerationBridge(); const c = clientFor(b);
      const result = await executeMessageDelete(c, -100, 1, [10, 20], { userId: 7, name: 'Ann' },
        choice(true), (): boolean => true, (): void => {});
      expect(result.failed).assertEqual('');
      expect(b.requests.filter((r: TdObject): boolean => r['@type'] === 'getMessageProperties').length).assertEqual(2);
      expect(b.mutations()[1]['revoke']).assertTrue();
    });
    it('ordinary_members_and_broadcast_channels_have_no_admin_shortcuts', 0, () => {
      expect(hasModeration(moderationOptions(GROUP, MEMBER, MEMBER, true))).assertFalse();
      expect(hasModeration(moderationOptions({ '@type': 'chatTypeSupergroup', 'is_channel': true },
        OWNER, MEMBER, true))).assertFalse();
    });
    it('rights_are_independent_and_spam_requires_message_permission', 0, () => {
      const deleter = moderationOptions(GROUP, admin(true, false), MEMBER, false);
      expect(deleter.deleteAll).assertTrue(); expect(deleter.ban).assertFalse();
      expect(deleter.remove).assertFalse(); expect(deleter.report).assertFalse();
      const moderator = moderationOptions(GROUP, admin(false, true), MEMBER, true);
      expect(moderator.deleteAll).assertFalse(); expect(moderator.ban).assertTrue();
      expect(moderator.remove).assertTrue(); expect(moderator.report).assertTrue();
    });
    it('owners_admins_and_unknown_targets_are_not_moderated_from_delete_dialog', 0, () => {
      expect(hasModeration(moderationOptions(GROUP, OWNER, OWNER, true))).assertFalse();
      expect(hasModeration(moderationOptions(GROUP, OWNER, admin(false, false), true))).assertFalse();
      expect(hasModeration(moderationOptions(GROUP, OWNER, { '@type': '' }, true))).assertFalse();
    });
    it('basic_groups_offer_removal_without_supergroup_only_operations', 0, () => {
      const options = moderationOptions({ '@type': 'chatTypeBasicGroup' }, admin(false, false), MEMBER, true);
      expect(options.remove).assertTrue(); expect(options.ban).assertFalse();
      expect(options.report).assertFalse(); expect(options.deleteAll).assertFalse();
    });
    it('left_and_banned_members_are_not_offered_remove_again', 0, () => {
      const left = moderationOptions(GROUP, OWNER, { '@type': 'chatMemberStatusLeft' }, false);
      expect(left.ban).assertTrue(); expect(left.remove).assertFalse();
      const banned = moderationOptions(GROUP, OWNER, { '@type': 'chatMemberStatusBanned' }, false);
      expect(banned.ban).assertFalse(); expect(banned.remove).assertFalse(); expect(banned.deleteAll).assertTrue();
    });
    it('same_sender_selection_is_required_including_offscreen_snapshots', 0, () => {
      const client: TdClient = clientFor(new ModerationBridge());
      const a: MessageEntry = row(client, 10, 7); const b: MessageEntry = row(client, 20, 7);
      expect(moderationTarget([10, 20], [a, b], 1)?.userId).assertEqual(7);
      b.senderId = 8;
      expect(moderationTarget([10, 20], [a, b], 1)).assertEqual(null);
      expect(moderationTarget([10, 20], [a], 1)).assertEqual(null);
      expect(moderationTarget([10], [a], 7)).assertEqual(null);
      a.senderIsUser = false;
      expect(moderationTarget([10], [a], 1)).assertEqual(null);
    });
    it('outgoing_and_system_messages_only_use_regular_deletion', 0, () => {
      const client: TdClient = clientFor(new ModerationBridge()); const a: MessageEntry = row(client, 10, 7);
      a.isOutgoing = true; expect(moderationTarget([10], [a], 1)).assertEqual(null);
      a.isOutgoing = false; a.contentType = 'system';
      expect(moderationTarget([10], [a], 1)).assertEqual(null);
    });
    it('reportability_is_read_from_message_properties', 0, async () => {
      const b: ModerationBridge = new ModerationBridge(); const c: TdClient = clientFor(b);
      b.reportable = false;
      const o = await loadMessageModeration(c, -100, 1, { userId: 7, name: 'Ann' }, [10, 20]);
      expect(o.report).assertFalse(); expect(o.deleteAll).assertTrue();
      expect(b.requests.some((r: TdObject): boolean => r['@type'] === 'getMessageProperties')).assertTrue();
    });
    it('unchecked_extras_only_delete_selected_messages_with_chosen_scope', 0, async () => {
      const b: ModerationBridge = new ModerationBridge(); const c: TdClient = clientFor(b);
      b.deleteSelf = true;
      const selected: DeleteMessageChoice = choice(); selected.revoke = false;
      const result = await executeMessageDelete(c, -100, 1, [10], null, selected, (): boolean => true, (): void => {});
      expect(result.failed).assertEqual(''); expect(b.mutations().length).assertEqual(1);
      expect(b.mutations()[0]['@type']).assertEqual('deleteMessages');
      expect(b.mutations()[0]['revoke']).assertFalse();
    });
    it('report_runs_before_removal_and_delete_all_replaces_selected_delete', 0, async () => {
      const b: ModerationBridge = new ModerationBridge(); const c: TdClient = clientFor(b);
      const result = await executeMessageDelete(c, -100, 1, [10, 20], { userId: 7, name: 'Ann' },
        choice(true, true, 'remove'), (): boolean => true, (): void => {});
      expect(result.completed.join(',')).assertEqual('report,remove,deleteAll');
      const calls: TdObject[] = b.mutations();
      expect(calls[0]['@type']).assertEqual('reportSupergroupSpam');
      expect(calls[0]['supergroup_id']).assertEqual(55);
      expect((calls[0]['message_ids'] as number[]).join(',')).assertEqual('10,20');
      expect((calls[1]['status'] as TdObject)['@type']).assertEqual('chatMemberStatusLeft');
      expect(calls[2]['@type']).assertEqual('deleteChatMessagesBySender');
      expect((calls[2]['sender_id'] as TdObject)['user_id']).assertEqual(7);
    });
    it('ban_uses_permanent_ban_without_implicit_delete_all_request', 0, async () => {
      const b: ModerationBridge = new ModerationBridge(); const c: TdClient = clientFor(b);
      await executeMessageDelete(c, -100, 1, [10], { userId: 7, name: 'Ann' },
        choice(false, false, 'ban'), (): boolean => true, (): void => {});
      const calls: TdObject[] = b.mutations();
      expect(calls.length).assertEqual(2); expect(calls[0]['@type']).assertEqual('banChatMember');
      expect(calls[0]['banned_until_date']).assertEqual(0);
      expect(calls[1]['@type']).assertEqual('deleteMessages');
    });
    it('lost_permissions_prevent_every_mutating_request', 0, async () => {
      const b: ModerationBridge = new ModerationBridge(); const c: TdClient = clientFor(b);
      await loadMessageModeration(c, -100, 1, { userId: 7, name: 'Ann' }, [10]);
      b.viewer = MEMBER;
      const result = await executeMessageDelete(c, -100, 1, [10], { userId: 7, name: 'Ann' },
        choice(false, true, 'ban'), (): boolean => true, (): void => {});
      expect(result.failed).assertEqual('permissions'); expect(b.mutations().length).assertEqual(0);
    });
    it('partial_failure_stops_before_deletion_and_records_completed_actions', 0, async () => {
      const b: ModerationBridge = new ModerationBridge(); const c: TdClient = clientFor(b);
      b.failType = 'setChatMemberStatus';
      const result = await executeMessageDelete(c, -100, 1, [10], { userId: 7, name: 'Ann' },
        choice(true, true, 'remove'), (): boolean => true, (): void => {});
      expect(result.completed.join(',')).assertEqual('report'); expect(result.failed).assertEqual('remove');
      expect(b.mutations().length).assertEqual(2);
    });
    it('timeout_does_not_retry_or_claim_success', 0, async () => {
      const b: ModerationBridge = new ModerationBridge(); const c: TdClient = clientFor(b);
      b.failType = 'reportSupergroupSpam'; b.failCode = -1;
      const result = await executeMessageDelete(c, -100, 1, [10], { userId: 7, name: 'Ann' },
        choice(true, true), (): boolean => true, (): void => {});
      expect(result.completed.length).assertEqual(0); expect(result.failed).assertEqual('report');
      expect(result.error).assertEqual('dm_operation_unknown'); expect(b.mutations().length).assertEqual(1);
    });
    it('closing_or_switching_chat_stops_unstarted_actions', 0, async () => {
      const b: ModerationBridge = new ModerationBridge(); const c: TdClient = clientFor(b);
      b.stopAfter = 'reportSupergroupSpam';
      const result = await executeMessageDelete(c, -100, 1, [10], { userId: 7, name: 'Ann' },
        choice(true, true, 'ban'), (): boolean => b.active, (): void => {});
      expect(result.completed.join(',')).assertEqual('report'); expect(result.failed).assertEqual('ban');
      expect(b.mutations().length).assertEqual(1);
    });
  });
}
