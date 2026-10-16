import { SharedPayload, SharedItem } from './sharedContent';
import { isAnimationPath } from './mediaPick';
import { TdObject } from '../tdkit/TdTypes';
import { GroupPermissions, allPermissions, permissionsFromTd, clampToChatPermissions,
  permissionValue } from './chatPermissions';

export const SEND_PERMISSION_KEYS: string[] = ['sendMessages', 'sendPhotos', 'sendVideos',
  'sendDocuments', 'sendAudios', 'sendVoiceNotes', 'sendVideoNotes', 'sendOtherMessages', 'sendPolls'];

export function effectiveSendPermissions(raw: TdObject | undefined, status: TdObject | undefined,
  isChannel: boolean): GroupPermissions {
  const type: string = (status?.['@type'] as string | undefined) ?? '';
  if (type === 'chatMemberStatusCreator') { return allPermissions(true); }
  if (type === 'chatMemberStatusAdministrator') {
    const rights = status?.['rights'] as TdObject | undefined;
    return allPermissions(!isChannel || rights?.['can_post_messages'] === true);
  }
  if (type === 'chatMemberStatusBanned' ||
    (type === 'chatMemberStatusRestricted' && status?.['is_member'] !== true)) {
    return allPermissions(false);
  }
  if (isChannel) { return allPermissions(false); }
  const defaults: GroupPermissions = raw === undefined ? allPermissions(true) : permissionsFromTd(raw);
  if (type === 'chatMemberStatusRestricted') {
    const own = status?.['permissions'] as TdObject | undefined;
    return own === undefined ? defaults : clampToChatPermissions(permissionsFromTd(own), defaults);
  }
  // Public groups may permit non-members to send; TDLib remains authoritative.
  return defaults;
}

export function anySendPermission(value: GroupPermissions): boolean {
  return SEND_PERMISSION_KEYS.some((key: string): boolean => permissionValue(value, key));
}

export function sendPermissionForType(type: string): string {
  const name: string = type.replace(/^inputMessage|^message|^inlineQueryResult/, '').toLowerCase();
  if (name === 'photo') { return 'sendPhotos'; }
  if (name === 'video') { return 'sendVideos'; }
  if (name === 'document') { return 'sendDocuments'; }
  if (name === 'audio') { return 'sendAudios'; }
  if (name === 'voicenote') { return 'sendVoiceNotes'; }
  if (name === 'videonote') { return 'sendVideoNotes'; }
  if (name === 'sticker' || name === 'animation' || name === 'dice') { return 'sendOtherMessages'; }
  if (name === 'poll') { return 'sendPolls'; }
  return 'sendMessages';
}

export function attachPermission(key: string): string {
  if (key === 'file') { return 'sendDocuments'; }
  if (key === 'audio') { return 'sendAudios'; }
  if (key === 'videoNote') { return 'sendVideoNotes'; }
  if (key === 'poll') { return 'sendPolls'; }
  if (key === 'dice') { return 'sendOtherMessages'; }
  return 'sendMessages';
}

export function canAttach(value: GroupPermissions, key: string): boolean {
  return key === 'media' ? value.sendPhotos || value.sendVideos : permissionValue(value, attachPermission(key));
}

export function firstDeniedPermission(value: GroupPermissions, keys: string[]): string {
  for (const key of keys) {
    if (!permissionValue(value, key)) { return key; }
  }
  return '';
}

export function sharedSendPermissions(payload: SharedPayload): string[] {
  if (payload.media.length === 0) { return payload.caption === '' ? [] : ['sendMessages']; }
  return payload.media.map((item: SharedItem): string => {
    if (item.kind === 'video') { return 'sendVideos'; }
    if (item.kind === 'audio') { return 'sendAudios'; }
    if (item.kind === 'image') { return isAnimationPath(item.uri) ? 'sendOtherMessages' : 'sendPhotos'; }
    return 'sendDocuments';
  });
}
