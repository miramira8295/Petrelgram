import { TdClient } from '../tdkit/TdClient';
import { TdError, TdObject, TdRequest } from '../tdkit/TdTypes';
import { QrLink } from './qrSession';

export async function fetchMyUserLink(client: TdClient): Promise<QrLink> {
  const result: TdObject = await client.send({ '@type': 'getUserLink' }, 15000);
  if (result['@type'] !== 'userLink') { throw new TdError(400, 'Invalid user link'); }
  return {
    url: (result['url'] as string | undefined) ?? '',
    expiresIn: (result['expires_in'] as number | undefined) ?? -1
  };
}

export async function resolveUserToken(client: TdClient, token: string): Promise<number> {
  if (token === '') { throw new TdError(400, 'Empty user token'); }
  const search: TdRequest = { '@type': 'searchUserByToken' };
  search['token'] = token;
  const user: TdObject = await client.send(search, 15000);
  const userId: number = (user['id'] as number | undefined) ?? 0;
  if (user['@type'] !== 'user' || userId <= 0) { throw new TdError(404, 'User not found'); }
  const create: TdRequest = { '@type': 'createPrivateChat' };
  create['user_id'] = userId;
  create['force'] = false;
  const chat: TdObject = await client.send(create, 15000);
  const chatId: number = (chat['id'] as number | undefined) ?? 0;
  if (chat['@type'] !== 'chat' || chatId === 0) { throw new TdError(404, 'Chat not found'); }
  return chatId;
}
