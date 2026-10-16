import { TdObject } from '../tdkit/TdTypes';
import { MessageEntry } from '../store/MessageEntry';

export interface ModerationTarget { userId: number; name: string; }
export interface ModerationOptions {
  supergroupId: number;
  report: boolean;
  deleteAll: boolean;
  ban: boolean;
  remove: boolean;
}
export interface DeleteMessageChoice {
  revoke: boolean;
  report: boolean;
  deleteAll: boolean;
  memberAction: string; // '' | ban | remove
}

export function noModeration(): ModerationOptions {
  return { supergroupId: 0, report: false, deleteAll: false, ban: false, remove: false };
}

export function hasModeration(o: ModerationOptions): boolean {
  return o.report || o.deleteAll || o.ban || o.remove;
}

export function moderationTarget(ids: number[], entries: MessageEntry[], selfId: number): ModerationTarget | null {
  if (selfId <= 0 || ids.length === 0) { return null; }
  let target: ModerationTarget | null = null;
  for (const id of ids) {
    const row: MessageEntry | undefined = entries.find((entry: MessageEntry): boolean => entry.id === id);
    if (row === undefined || id <= 0 || row.isOutgoing || !row.senderIsUser ||
      row.senderId <= 0 || row.senderId === selfId || row.contentType === 'system') { return null; }
    if (target !== null && target.userId !== row.senderId) { return null; }
    target = { userId: row.senderId, name: row.senderName };
  }
  return target;
}

export function moderationOptions(
  chatType: TdObject, viewer: TdObject, target: TdObject, allReportable: boolean
): ModerationOptions {
  const group: boolean = chatType['@type'] === 'chatTypeSupergroup' && chatType['is_channel'] !== true;
  const basic: boolean = chatType['@type'] === 'chatTypeBasicGroup';
  const owner: boolean = viewer['@type'] === 'chatMemberStatusCreator' && viewer['is_member'] !== false;
  const admin: boolean = viewer['@type'] === 'chatMemberStatusAdministrator';
  const type: string = (target['@type'] as string | undefined) ?? '';
  if ((!group && !basic) || (!owner && !admin) ||
    (type !== 'chatMemberStatusMember' && type !== 'chatMemberStatusRestricted' &&
      type !== 'chatMemberStatusLeft' && type !== 'chatMemberStatusBanned')) { return noModeration(); }
  const rights: TdObject | undefined = viewer['rights'] as TdObject | undefined;
  const restrict: boolean = owner || basic || rights?.['can_restrict_members'] === true;
  const remove: boolean = restrict && (type === 'chatMemberStatusMember' ||
    (type === 'chatMemberStatusRestricted' && target['is_member'] === true));
  return {
    supergroupId: group ? ((chatType['supergroup_id'] as number | undefined) ?? 0) : 0,
    report: group && allReportable,
    deleteAll: group && (owner || rights?.['can_delete_messages'] === true),
    // Basic groups support removing members, but not a persistent ban list.
    ban: group && restrict && type !== 'chatMemberStatusBanned', remove
  };
}

export function moderationChoiceAllowed(choice: DeleteMessageChoice, options: ModerationOptions): boolean {
  return (!choice.report || options.report) && (!choice.deleteAll || options.deleteAll) &&
    (choice.memberAction === '' || (choice.memberAction === 'ban' && options.ban) ||
      (choice.memberAction === 'remove' && options.remove));
}

// TDLib's messageProperties also handles local/failed messages and Saved
// Messages. Chat type alone cannot describe their deletion scope.
export interface MessageDeleteScope { self: boolean; all: boolean; }

export function messageDeleteScope(properties: TdObject[]): MessageDeleteScope {
  return {
    self: properties.length > 0 && properties.every((p: TdObject): boolean => p['can_be_deleted_only_for_self'] === true),
    all: properties.length > 0 && properties.every((p: TdObject): boolean => p['can_be_deleted_for_all_users'] === true)
  };
}

export function messageDeleteRevoke(scope: MessageDeleteScope, selected: boolean, deleteAll: boolean): boolean {
  return deleteAll || !scope.self || (scope.all && selected);
}
