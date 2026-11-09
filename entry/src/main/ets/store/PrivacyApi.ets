import { getTdClient } from '../tdkit/Globals';
import { TdClient } from '../tdkit/TdClient';
import { TdObject, TdRequest } from '../tdkit/TdTypes';
import { str } from '../util/strings';

export const RULE_EVERYBODY: string = 'everybody';
export const RULE_CONTACTS: string = 'contacts';
export const RULE_NOBODY: string = 'nobody';

const BASE_RULE_TYPES: string[] = [
  'userPrivacySettingRuleAllowAll',
  'userPrivacySettingRuleAllowContacts',
  'userPrivacySettingRuleRestrictAll'
];

export interface PrivacyValue {
  base: string;
  exceptions: number;
  allowExceptions: number;
  restrictExceptions: number;
  // All non-base rules are carried through verbatim. This deliberately also
  // preserves bot, Premium and restrict-contact rules introduced by TDLib.
  extra: TdObject[];
}

export interface ArchiveChatSettings {
  archiveUnknown: boolean;
  keepUnmutedArchived: boolean;
  keepFolderChatsArchived: boolean;
}

export interface NewChatPrivacySettings {
  allowUnknown: boolean;
  paidStars: number;
}

export interface ConnectedWebsite {
  id: number;
  domain: string;
  botUserId: number;
  browser: string;
  platform: string;
  logInDate: number;
  lastActiveDate: number;
  ipAddress: string;
  location: string;
}

function runtimeClient(client?: TdClient): TdClient {
  return client !== undefined ? client : getTdClient();
}

function baseOf(rules: TdObject[]): string {
  for (const rule of rules) {
    const type = (rule['@type'] as string | undefined) ?? '';
    if (type === 'userPrivacySettingRuleAllowAll') { return RULE_EVERYBODY; }
    if (type === 'userPrivacySettingRuleAllowContacts') { return RULE_CONTACTS; }
    if (type === 'userPrivacySettingRuleRestrictAll') { return RULE_NOBODY; }
  }
  return RULE_NOBODY;
}

function namedCount(rule: TdObject): number {
  const users = (rule['user_ids'] as number[] | undefined) ?? [];
  const chats = (rule['chat_ids'] as number[] | undefined) ?? [];
  return users.length + chats.length;
}

export function parsePrivacyRules(rules: TdObject[]): PrivacyValue {
  const extra = rules.filter((rule: TdObject): boolean =>
    BASE_RULE_TYPES.indexOf((rule['@type'] as string | undefined) ?? '') < 0);
  let allowExceptions = 0;
  let restrictExceptions = 0;
  for (const rule of extra) {
    const type = (rule['@type'] as string | undefined) ?? '';
    const count = namedCount(rule);
    if (type.indexOf('Allow') >= 0) { allowExceptions += count; }
    if (type.indexOf('Restrict') >= 0) { restrictExceptions += count; }
  }
  return {
    base: baseOf(rules),
    exceptions: allowExceptions + restrictExceptions,
    allowExceptions,
    restrictExceptions,
    extra
  };
}

function makeBaseRule(base: string): TdObject {
  if (base === RULE_EVERYBODY) {
    return { '@type': 'userPrivacySettingRuleAllowAll' } as TdObject;
  }
  if (base === RULE_CONTACTS) {
    return { '@type': 'userPrivacySettingRuleAllowContacts' } as TdObject;
  }
  return { '@type': 'userPrivacySettingRuleRestrictAll' } as TdObject;
}

export function composePrivacyRules(base: string, preserved: TdObject[]): TdObject[] {
  const clean = preserved.filter((rule: TdObject): boolean =>
    BASE_RULE_TYPES.indexOf((rule['@type'] as string | undefined) ?? '') < 0);
  return [...clean, makeBaseRule(base)];
}

export function ruleLabel(value: PrivacyValue): string {
  const base = value.base === RULE_EVERYBODY
    ? str('privacy_everybody') : (value.base === RULE_CONTACTS ? str('privacy_contacts') : str('privacy_nobody'));
  const parts: string[] = [];
  if (value.allowExceptions > 0) { parts.push(`+${value.allowExceptions}`); }
  if (value.restrictExceptions > 0) { parts.push(`−${value.restrictExceptions}`); }
  return parts.length > 0 ? `${base} · ${parts.join(' / ')}` : base;
}

export async function getPrivacy(setting: string, client?: TdClient): Promise<PrivacyValue> {
  const request: TdRequest = { '@type': 'getUserPrivacySettingRules' };
  request['setting'] = { '@type': setting } as TdObject;
  const result = await runtimeClient(client).send(request);
  return parsePrivacyRules((result['rules'] as TdObject[] | undefined) ?? []);
}

export async function setPrivacy(
  setting: string, base: string, preserved: TdObject[], client?: TdClient
): Promise<void> {
  const request: TdRequest = { '@type': 'setUserPrivacySettingRules' };
  request['setting'] = { '@type': setting } as TdObject;
  request['rules'] = {
    '@type': 'userPrivacySettingRules',
    'rules': composePrivacyRules(base, preserved)
  } as TdObject;
  await runtimeClient(client).send(request);
}

export async function getPasswordState(client?: TdClient): Promise<TdObject> {
  return runtimeClient(client).send({ '@type': 'getPasswordState' } as TdRequest);
}

export async function hasPassword(client?: TdClient): Promise<boolean> {
  const result = await getPasswordState(client);
  return (result['has_password'] as boolean | undefined) ?? false;
}

export async function setPassword(
  oldPassword: string, newPassword: string, hint: string,
  setRecoveryEmail: boolean, recoveryEmail: string, client?: TdClient
): Promise<TdObject> {
  const request: TdRequest = { '@type': 'setPassword' };
  request['old_password'] = oldPassword;
  request['new_password'] = newPassword;
  request['new_hint'] = hint;
  request['set_recovery_email_address'] = setRecoveryEmail;
  request['new_recovery_email_address'] = recoveryEmail;
  return runtimeClient(client).send(request);
}

export async function setRecoveryEmail(
  password: string, email: string, client?: TdClient
): Promise<TdObject> {
  const request: TdRequest = { '@type': 'setRecoveryEmailAddress' };
  request['password'] = password;
  request['new_recovery_email_address'] = email;
  return runtimeClient(client).send(request);
}

export async function checkRecoveryEmailCode(code: string, client?: TdClient): Promise<TdObject> {
  const request: TdRequest = { '@type': 'checkRecoveryEmailAddressCode' };
  request['code'] = code;
  return runtimeClient(client).send(request);
}

export async function resendRecoveryEmailCode(client?: TdClient): Promise<TdObject> {
  return runtimeClient(client).send({ '@type': 'resendRecoveryEmailAddressCode' } as TdRequest);
}

export async function cancelRecoveryEmailVerification(client?: TdClient): Promise<TdObject> {
  return runtimeClient(client).send({ '@type': 'cancelRecoveryEmailAddressVerification' } as TdRequest);
}

export async function requestPasswordRecovery(client?: TdClient): Promise<TdObject> {
  return runtimeClient(client).send({ '@type': 'requestPasswordRecovery' } as TdRequest);
}

export async function recoverPassword(
  code: string, newPassword: string, hint: string, client?: TdClient
): Promise<TdObject> {
  const request: TdRequest = { '@type': 'recoverPassword' };
  request['recovery_code'] = code;
  request['new_password'] = newPassword;
  request['new_hint'] = hint;
  return runtimeClient(client).send(request);
}

export async function getAutoDeleteSeconds(client?: TdClient): Promise<number> {
  const result = await runtimeClient(client).send(
    { '@type': 'getDefaultMessageAutoDeleteTime' } as TdRequest);
  return (result['time'] as number | undefined) ?? 0;
}

export async function setAutoDeleteSeconds(seconds: number, client?: TdClient): Promise<void> {
  const request: TdRequest = { '@type': 'setDefaultMessageAutoDeleteTime' };
  request['message_auto_delete_time'] = {
    '@type': 'messageAutoDeleteTime', 'time': seconds
  } as TdObject;
  await runtimeClient(client).send(request);
}

export async function getBlockedCount(client?: TdClient): Promise<number> {
  const request: TdRequest = { '@type': 'getBlockedMessageSenders' };
  request['block_list'] = { '@type': 'blockListMain' } as TdObject;
  request['offset'] = 0;
  request['limit'] = 100;
  const result = await runtimeClient(client).send(request);
  const loaded = ((result['senders'] as TdObject[] | undefined) ?? []).length;
  return Math.max((result['total_count'] as number | undefined) ?? 0, loaded);
}

export async function getSessionCount(client?: TdClient): Promise<number> {
  const result = await runtimeClient(client).send({ '@type': 'getActiveSessions' } as TdRequest);
  return ((result['sessions'] as TdObject[] | undefined) ?? []).length;
}

export async function getConnectedWebsiteCount(client?: TdClient): Promise<number> {
  const result = await runtimeClient(client).send({ '@type': 'getConnectedWebsites' } as TdRequest);
  return ((result['websites'] as TdObject[] | undefined) ?? []).length;
}

export async function getConnectedWebsites(client?: TdClient): Promise<ConnectedWebsite[]> {
  const result = await runtimeClient(client).send({ '@type': 'getConnectedWebsites' } as TdRequest);
  const websites = (result['websites'] as TdObject[] | undefined) ?? [];
  return websites.map((website: TdObject): ConnectedWebsite => ({
    id: (website['id'] as number | undefined) ?? 0,
    domain: (website['domain_name'] as string | undefined) ?? '',
    botUserId: (website['bot_user_id'] as number | undefined) ?? 0,
    browser: (website['browser'] as string | undefined) ?? '',
    platform: (website['platform'] as string | undefined) ?? '',
    logInDate: (website['log_in_date'] as number | undefined) ?? 0,
    lastActiveDate: (website['last_active_date'] as number | undefined) ?? 0,
    ipAddress: (website['ip_address'] as string | undefined) ?? '',
    location: (website['location'] as string | undefined) ?? ''
  }));
}

export async function disconnectWebsite(id: number, client?: TdClient): Promise<void> {
  const request: TdRequest = { '@type': 'disconnectWebsite' };
  request['website_id'] = id;
  await runtimeClient(client).send(request);
}

export async function disconnectAllWebsites(client?: TdClient): Promise<void> {
  await runtimeClient(client).send({ '@type': 'disconnectAllWebsites' } as TdRequest);
}

export async function getAccountTtlDays(client?: TdClient): Promise<number> {
  const result = await runtimeClient(client).send({ '@type': 'getAccountTtl' } as TdRequest);
  return (result['days'] as number | undefined) ?? 0;
}

export async function setAccountTtlDays(days: number, client?: TdClient): Promise<void> {
  const request: TdRequest = { '@type': 'setAccountTtl' };
  request['ttl'] = { '@type': 'accountTtl', 'days': days } as TdObject;
  await runtimeClient(client).send(request);
}

export async function getBoolOption(name: string, client?: TdClient): Promise<boolean> {
  const request: TdRequest = { '@type': 'getOption' };
  request['name'] = name;
  const result = await runtimeClient(client).send(request);
  return (result['value'] as boolean | undefined) ?? false;
}

export async function setBoolOption(name: string, value: boolean, client?: TdClient): Promise<void> {
  const request: TdRequest = { '@type': 'setOption' };
  request['name'] = name;
  request['value'] = { '@type': 'optionValueBoolean', 'value': value } as TdObject;
  await runtimeClient(client).send(request);
}

export async function getArchiveSettings(client?: TdClient): Promise<ArchiveChatSettings> {
  const result = await runtimeClient(client).send({ '@type': 'getArchiveChatListSettings' } as TdRequest);
  return {
    archiveUnknown: (result['archive_and_mute_new_chats_from_unknown_users'] as boolean | undefined) ?? false,
    keepUnmutedArchived: (result['keep_unmuted_chats_archived'] as boolean | undefined) ?? false,
    keepFolderChatsArchived: (result['keep_chats_from_folders_archived'] as boolean | undefined) ?? false
  };
}

export async function setArchiveSettings(settings: ArchiveChatSettings, client?: TdClient): Promise<void> {
  const request: TdRequest = { '@type': 'setArchiveChatListSettings' };
  request['settings'] = {
    '@type': 'archiveChatListSettings',
    'archive_and_mute_new_chats_from_unknown_users': settings.archiveUnknown,
    'keep_unmuted_chats_archived': settings.keepUnmutedArchived,
    'keep_chats_from_folders_archived': settings.keepFolderChatsArchived
  } as TdObject;
  await runtimeClient(client).send(request);
}

export async function getReadDatePrivacy(client?: TdClient): Promise<boolean> {
  const result = await runtimeClient(client).send({ '@type': 'getReadDatePrivacySettings' } as TdRequest);
  return (result['show_read_date'] as boolean | undefined) ?? true;
}

export async function setReadDatePrivacy(show: boolean, client?: TdClient): Promise<void> {
  const request: TdRequest = { '@type': 'setReadDatePrivacySettings' };
  request['settings'] = { '@type': 'readDatePrivacySettings', 'show_read_date': show } as TdObject;
  await runtimeClient(client).send(request);
}

export async function getNewChatPrivacy(client?: TdClient): Promise<NewChatPrivacySettings> {
  const result = await runtimeClient(client).send({ '@type': 'getNewChatPrivacySettings' } as TdRequest);
  return {
    allowUnknown: (result['allow_new_chats_from_unknown_users'] as boolean | undefined) ?? true,
    paidStars: (result['incoming_paid_message_star_count'] as number | undefined) ?? 0
  };
}

export async function setNewChatPrivacy(
  settings: NewChatPrivacySettings, client?: TdClient
): Promise<void> {
  const request: TdRequest = { '@type': 'setNewChatPrivacySettings' };
  request['settings'] = {
    '@type': 'newChatPrivacySettings',
    'allow_new_chats_from_unknown_users': settings.allowUnknown,
    'incoming_paid_message_star_count': settings.paidStars
  } as TdObject;
  await runtimeClient(client).send(request);
}
