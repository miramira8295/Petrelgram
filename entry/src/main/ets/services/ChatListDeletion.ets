import { TdClient } from '../tdkit/TdClient';
import { TdObject, TdRequest } from '../tdkit/TdTypes';

// 所有步骤使用确认时冻结的client；屏蔽成功后仍需检查账号再删除。
export async function executeChatListDelete(client: TdClient, chatId: number, revoke: boolean,
  block: boolean, active: () => boolean): Promise<boolean> {
  if (!active()) { return false; }
  const load: TdRequest = { '@type': 'getChat' };
  load['chat_id'] = chatId;
  await client.send(load);
  if (!active()) { return false; }
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
  req['revoke'] = revoke;
  await client.send(req);
  return true;
}
