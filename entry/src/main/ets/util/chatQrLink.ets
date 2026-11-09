import { TdObject, TdRequest, TdError } from '../tdkit/TdTypes';
import { QrLink } from './qrSession';
import { publicLink } from './telegramLink';

export interface ChatQrClient {
  send: (request: TdRequest, timeout?: number) => Promise<TdObject>;
}

export function validInviteQr(invite: TdObject, nowSeconds: number): QrLink {
  const url = (invite['invite_link'] as string | undefined) ?? '';
  const expires = (invite['expiration_date'] as number | undefined) ?? 0;
  const limit = (invite['member_limit'] as number | undefined) ?? 0;
  const count = (invite['member_count'] as number | undefined) ?? 0;
  if (url === '' || invite['is_revoked'] === true || (expires > 0 && expires <= nowSeconds) ||
    (limit > 0 && count >= limit)) { throw new TdError(403, 'QR invite unavailable'); }
  return { url, expiresIn: expires > 0 ? expires - nowSeconds : 0 };
}

// 只读取现有链接，不自动创建或撤销群邀请。每次打开/到期刷新都重查身份。
export async function fetchChatQrLink(client: ChatQrClient, chatId: number,
  current: () => boolean = (): boolean => true): Promise<QrLink> {
  const read = async (type: string, key: string, value: number | string): Promise<TdObject> => {
    if (!current()) { throw new TdError(499, 'QR closed'); }
    const request: TdRequest = { '@type': type };
    request[key] = value;
    const result = await client.send(request, 15000);
    if (!current()) { throw new TdError(499, 'QR closed'); }
    return result;
  };
  const chat = await read('getChat', 'chat_id', chatId);
  const type = chat['type'] as TdObject | undefined;
  const isSuper = type?.['@type'] === 'chatTypeSupergroup';
  if (!isSuper && type?.['@type'] !== 'chatTypeBasicGroup') { throw new TdError(403, 'QR chat unavailable'); }
  const key = isSuper ? 'supergroup_id' : 'basic_group_id';
  const id = (type?.[key] as number | undefined) ?? 0;
  const group = await read(isSuper ? 'getSupergroup' : 'getBasicGroup', key, id);
  const usernames = group['usernames'] as TdObject | undefined;
  const names = (usernames?.['active_usernames'] as string[] | undefined) ?? [];
  const username = names.length > 0 ? names[0] : '';
  if (username !== '') { return { url: publicLink(username), expiresIn: 0 }; }
  const status = group['status'] as TdObject | undefined;
  const rights = status?.['rights'] as TdObject | undefined;
  const allowed = status?.['@type'] === 'chatMemberStatusCreator' ||
    (status?.['@type'] === 'chatMemberStatusAdministrator' && rights?.['can_invite_users'] === true);
  if (!allowed) { throw new TdError(403, 'QR invite unavailable'); }
  const info = await read(isSuper ? 'getSupergroupFullInfo' : 'getBasicGroupFullInfo', key, id);
  const primary = info['invite_link'] as TdObject | undefined;
  if (primary === undefined || primary === null) { throw new TdError(403, 'QR invite unavailable'); }
  const url = (primary['invite_link'] as string | undefined) ?? '';
  if (url === '') { throw new TdError(403, 'QR invite unavailable'); }
  // fullInfo可缓存一分钟，展示前再核对撤销/到期/人数限制。
  const request: TdRequest = { '@type': 'getChatInviteLink' };
  request['chat_id'] = chatId;
  request['invite_link'] = url;
  if (!current()) { throw new TdError(499, 'QR closed'); }
  const invite = await client.send(request, 15000);
  if (!current()) { throw new TdError(499, 'QR closed'); }
  return validInviteQr(invite, Math.ceil(Date.now() / 1000));
}
