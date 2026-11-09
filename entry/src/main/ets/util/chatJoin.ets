import { TdClient } from '../tdkit/TdClient';
import { TdError, TdObject, TdRequest } from '../tdkit/TdTypes';

export interface ChatJoinOutcome {
  requested: boolean;
  chatId: number;
}

// Current TDLib returns ChatJoinResult; older builds return Chat/Ok or the
// INVITE_REQUEST_SENT error. Approval requirements alone never prove an outcome.
export function chatJoinOutcome(result: TdObject, chatId: number): ChatJoinOutcome {
  const type: string = (result['@type'] as string | undefined) ?? '';
  if (type === 'chatJoinResultRequestSent') {
    return { requested: true, chatId };
  }
  let joinedId: number = 0;
  if (type === 'chatJoinResultSuccess') {
    joinedId = (result['chat_id'] as number | undefined) ?? 0;
  } else if (type === 'chat') {
    joinedId = (result['id'] as number | undefined) ?? 0;
  } else if (type === 'ok') {
    joinedId = chatId;
  }
  if (joinedId !== 0) {
    return { requested: false, chatId: joinedId };
  }
  // Guard-bot approval/declines and unknown results must not unlock the chat.
  throw new TdError(400, `Unsupported chat join result: ${type}`);
}

export async function joinChat(client: TdClient, chatId: number,
  inviteLink: string = ''): Promise<ChatJoinOutcome> {
  const request: TdRequest = { '@type': inviteLink !== '' ? 'joinChatByInviteLink' : 'joinChat' };
  if (inviteLink !== '') { request['invite_link'] = inviteLink; }
  else { request['chat_id'] = chatId; }
  try {
    return chatJoinOutcome(await client.send(request), chatId);
  } catch (error) {
    if ((error as TdError).message === 'INVITE_REQUEST_SENT') {
      return { requested: true, chatId };
    }
    throw error as Error;
  }
}
