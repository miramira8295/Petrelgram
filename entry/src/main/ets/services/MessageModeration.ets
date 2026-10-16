import { TdClient } from '../tdkit/TdClient';
import { TdObject, TdRequest, TdError } from '../tdkit/TdTypes';
import { str } from '../util/strings';
import {
  DeleteMessageChoice, ModerationOptions, ModerationTarget,
  moderationOptions, moderationChoiceAllowed, noModeration, messageDeleteScope, MessageDeleteScope
} from '../util/messageModeration';

function member(userId: number): TdObject {
  return { '@type': 'messageSenderUser', 'user_id': userId };
}

export async function loadMessageDeleteProperties(client: TdClient, chatId: number, ids: number[]): Promise<TdObject[]> {
  const properties: TdObject[] = [];
  // These reads are local to TDLib. Bound concurrency for large selections.
  for (let at: number = 0; at < ids.length; at += 8) {
    const batch: TdObject[] = await Promise.all(ids.slice(at, at + 8).map((id: number): Promise<TdObject> => {
      const req: TdRequest = { '@type': 'getMessageProperties' };
      req['chat_id'] = chatId;
      req['message_id'] = id;
      return client.send(req, 10000);
    }));
    properties.push(...batch);
  }
  return properties;
}

export async function loadMessageModeration(
  client: TdClient, chatId: number, selfId: number, target: ModerationTarget, ids: number[],
  properties?: TdObject[]
): Promise<ModerationOptions> {
  const chat: TdRequest = { '@type': 'getChat' };
  chat['chat_id'] = chatId;
  const self: TdRequest = { '@type': 'getChatMember' };
  self['chat_id'] = chatId;
  self['member_id'] = member(selfId);
  const sender: TdRequest = { '@type': 'getChatMember' };
  sender['chat_id'] = chatId;
  sender['member_id'] = member(target.userId);
  const requests: TdRequest[] = [chat, self, sender];
  const values: TdObject[] = await Promise.all(requests.map((request: TdRequest): Promise<TdObject> => client.send(request, 15000)));
  const type: TdObject = (values[0]['type'] as TdObject | undefined) ?? { '@type': '' };
  const viewer: TdObject = (values[1]['status'] as TdObject | undefined) ?? { '@type': '' };
  const status: TdObject = (values[2]['status'] as TdObject | undefined) ?? { '@type': '' };
  const options: ModerationOptions = moderationOptions(type, viewer, status, false);
  const admin: boolean = viewer['@type'] === 'chatMemberStatusAdministrator' ||
    (viewer['@type'] === 'chatMemberStatusCreator' && viewer['is_member'] !== false);
  if (!admin || options.supergroupId <= 0) { return options; }
  let reportable: boolean = false;
  try {
    const values: TdObject[] = properties ?? await loadMessageDeleteProperties(client, chatId, ids);
    reportable = values.length > 0 && values.length === ids.length &&
      values.every((p: TdObject): boolean => p['can_report_supergroup_spam'] === true);
  } catch (_) { /* Failed reads never grant spam-report permission. */ }
  return moderationOptions(type, viewer, status, reportable);
}

export interface MessageDeleteResult { completed: string[]; failed: string; error: string; }

// A confirmed operation is bound to one chat, one sender and frozen message ids.
// Stop on failure, report partial completion, and never automatically retry.
export async function executeMessageDelete(
  client: TdClient, chatId: number, selfId: number, ids: number[], target: ModerationTarget | null,
  choice: DeleteMessageChoice, active: () => boolean,
  beforeDelete: () => void
): Promise<MessageDeleteResult> {
  const completed: string[] = [];
  let step: string = 'scope';
  try {
    const properties: TdObject[] = await loadMessageDeleteProperties(client, chatId, ids);
    const scope: MessageDeleteScope = messageDeleteScope(properties);
    // Never silently promote a confirmed self-only delete to an all-user delete,
    // or downgrade an all-user delete that is no longer available.
    if (!(choice.revoke ? scope.all : scope.self) || (choice.deleteAll && !choice.revoke)) {
      return { completed, failed: step, error: str('dm_scope_unavailable') };
    }
    const extra: boolean = choice.report || choice.deleteAll || choice.memberAction !== '';
    let options: ModerationOptions = noModeration();
    if (extra) {
      step = 'permissions';
      if (target === null || target.userId === selfId || selfId <= 0) {
        return { completed, failed: step, error: str('dm_permissions_changed') };
      }
      options = await loadMessageModeration(client, chatId, selfId, target, ids, properties);
      if (!moderationChoiceAllowed(choice, options)) {
        return { completed, failed: step, error: str('dm_permissions_changed') };
      }
    }
    const steps: string[] = [];
    if (choice.report) { steps.push('report'); }
    if (choice.memberAction !== '') { steps.push(choice.memberAction); }
    steps.push(choice.deleteAll ? 'deleteAll' : 'delete');
    for (const next of steps) {
      step = next;
      if (!active()) { return { completed, failed: step, error: str('cancel') }; }
      let req: TdRequest;
      if (step === 'report') {
        req = { '@type': 'reportSupergroupSpam' };
        req['supergroup_id'] = options.supergroupId;
        req['message_ids'] = ids;
      } else if (step === 'ban') {
        req = { '@type': 'banChatMember' };
        req['chat_id'] = chatId;
        req['member_id'] = member(target!.userId);
        req['banned_until_date'] = 0;
        req['revoke_messages'] = false;
      } else if (step === 'remove') {
        req = { '@type': 'setChatMemberStatus' };
        req['chat_id'] = chatId;
        req['member_id'] = member(target!.userId);
        req['status'] = { '@type': 'chatMemberStatusLeft' } as TdObject;
      } else if (step === 'deleteAll') {
        req = { '@type': 'deleteChatMessagesBySender' };
        req['chat_id'] = chatId;
        req['sender_id'] = member(target!.userId);
        beforeDelete();
      } else {
        req = { '@type': 'deleteMessages' };
        req['chat_id'] = chatId;
        req['message_ids'] = ids;
        req['revoke'] = choice.revoke;
        beforeDelete();
      }
      await client.send(req, 20000);
      completed.push(step);
    }
    return { completed, failed: '', error: '' };
  } catch (error) {
    if (step === 'scope') { return { completed, failed: step, error: str('dm_scope_unavailable') }; }
    return { completed, failed: step, error: (error as TdError).code === -1 ? str('dm_operation_unknown') :
      ((error as TdError).message ?? str('ga_failed')) };
  }
}
