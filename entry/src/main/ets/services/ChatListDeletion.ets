import { TdClient } from '../tdkit/TdClient';
import { TdError, TdObject, TdRequest } from '../tdkit/TdTypes';

// 所有步骤使用确认时冻结的client；屏蔽成功后仍需检查账号再删除。
export async function executeChatListDelete(client: TdClient, chatId: number, revoke: boolean,
  block: boolean, active: () => boolean): Promise<boolean> {
  if (!active()) { return false; }
  const load: TdRequest = { '@type': 'getChat' };
  load['chat_id'] = chatId;
  const chat: TdObject = await client.send(load);
  if (!active()) { return false; }
  const type = chat['type'] as TdObject | undefined;
  const secret: boolean = type?.['@type'] === 'chatTypeSecret';
  if (secret) {
    const secretId: number = (type?.['secret_chat_id'] as number | undefined) ?? 0;
    if (secretId <= 0) { throw new TdError(400, 'Invalid secret chat identifier'); }
    // A pending secret chat cannot flush history, and flushing a ready one
    // does not terminate the encrypted session. Close it before removing it.
    const close: TdRequest = { '@type': 'closeSecretChat' };
    close['secret_chat_id'] = secretId;
    await client.send(close);
    if (!active()) { return false; }
  }
  if (block) {
    const req: TdRequest = { '@type': 'setMessageSenderBlockList' };
    req['sender_id'] = { '@type': 'messageSenderUser', 'user_id': chatId } as TdObject;
    req['block_list'] = { '@type': 'blockListMain' } as TdObject;
    await client.send(req);
    if (!active()) { return false; }
  }
  const req: TdRequest = { '@type': 'deleteChatHistory' };
  req['chat_id'] = chatId;
  req['remove_from_chat_list'] = true;
  // Once closed, secret-chat history can only be deleted locally.
  req['revoke'] = secret ? false : revoke;
  await client.send(req);
  return true;
}
