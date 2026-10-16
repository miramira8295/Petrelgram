import { promptAction } from '@kit.ArkUI';
import { TdClient } from '../tdkit/TdClient';
import { TdObject, TdRequest, TdError } from '../tdkit/TdTypes';
import { GroupPermissions, allPermissions } from '../util/chatPermissions';
import { effectiveSendPermissions, firstDeniedPermission, sendPermissionForType } from '../util/sendPermissions';
import { str } from '../util/strings';

export type SendPermissionPort = (request: TdRequest) => Promise<TdObject>;

export class SendPermissionError extends TdError {
  constructor(message: string) { super(403, message); }
}

export function sendPermissionMessage(key: string): string {
  let label: string = 'ga_send_messages';
  if (key === 'sendPhotos') { label = 'mm_photos'; }
  else if (key === 'sendVideos') { label = 'mm_videos'; }
  else if (key === 'sendDocuments') { label = 'mm_files'; }
  else if (key === 'sendAudios') { label = 'mm_music'; }
  else if (key === 'sendVoiceNotes') { label = 'mm_voice_messages'; }
  else if (key === 'sendVideoNotes') { label = 'mm_round_videos'; }
  else if (key === 'sendOtherMessages') { label = 'mm_stickers_gifs'; }
  else if (key === 'sendPolls') { label = 'ga_send_polls'; }
  return str('cp_send_permission_denied', str(label));
}

export function showSendPermissionError(error: Error): void {
  if (error instanceof SendPermissionError) {
    promptAction.showToast({ message: error.message, duration: 2500 });
  }
}

// getChat/getSupergroup/getBasicGroup read TDLib's current local state, without polling.
export async function readSendPermissions(port: SendPermissionPort, chatId: number): Promise<GroupPermissions> {
  const chatRequest: TdRequest = { '@type': 'getChat' };
  chatRequest['chat_id'] = chatId;
  const chat: TdObject = await port(chatRequest);
  const type = chat['type'] as TdObject | undefined;
  const name: string = (type?.['@type'] as string | undefined) ?? '';
  if (name === 'chatTypePrivate' || name === 'chatTypeSecret') { return allPermissions(true); }
  if (name !== 'chatTypeSupergroup' && name !== 'chatTypeBasicGroup') {
    throw new SendPermissionError(str('cp_send_permission_check_failed'));
  }
  const groupRequest: TdRequest = { '@type': name === 'chatTypeSupergroup' ? 'getSupergroup' : 'getBasicGroup' };
  if (name === 'chatTypeSupergroup') { groupRequest['supergroup_id'] = type!['supergroup_id']; }
  else { groupRequest['basic_group_id'] = type!['basic_group_id']; }
  const group: TdObject = await port(groupRequest);
  const status = group['status'] as TdObject | undefined;
  if (status === undefined) { throw new SendPermissionError(str('cp_send_permission_check_failed')); }
  return effectiveSendPermissions(chat['permissions'] as TdObject | undefined, status, type?.['is_channel'] === true);
}

export async function requireSendPermissions(port: SendPermissionPort, chatId: number,
  keys: string[]): Promise<void> {
  let value: GroupPermissions;
  try { value = await readSendPermissions(port, chatId); }
  catch (_error) { throw new SendPermissionError(str('cp_send_permission_check_failed')); }
  const denied: string = firstDeniedPermission(value, keys);
  if (denied !== '') { throw new SendPermissionError(sendPermissionMessage(denied)); }
}

export async function requireForwardPermissions(port: SendPermissionPort, toChatId: number,
  fromChatId: number, ids: number[]): Promise<void> {
  const keys: string[] = [];
  try {
    for (let start: number = 0; start < ids.length; start += 100) {
      const batch: number[] = ids.slice(start, start + 100);
      const request: TdRequest = { '@type': 'getMessages' };
      request['chat_id'] = fromChatId;
      request['message_ids'] = batch;
      const response = await port(request);
      const messages = (response['messages'] as (TdObject | null)[] | undefined) ?? [];
      if (messages.length !== batch.length || messages.some((m: TdObject | null): boolean => m === null)) {
        throw new Error('missing source message');
      }
      for (const message of messages) {
        const content = message!['content'] as TdObject | undefined;
        keys.push(sendPermissionForType((content?.['@type'] as string | undefined) ?? ''));
      }
    }
  } catch (_error) { throw new SendPermissionError(str('cp_send_permission_check_failed')); }
  await requireSendPermissions(port, toChatId, keys);
}

export async function sendWithChatPermissions(client: TdClient, request: TdRequest,
  explicitKeys?: string[], active: () => boolean = (): boolean => true): Promise<TdObject> {
  const port: SendPermissionPort = (req: TdRequest): Promise<TdObject> => client.send(req, 15000);
  try {
    const chatId: number = request['chat_id'] as number;
    if (request['@type'] === 'forwardMessages') {
      await requireForwardPermissions(port, chatId, request['from_chat_id'] as number,
        request['message_ids'] as number[]);
    } else {
      const contents: TdObject[] = request['@type'] === 'sendMessageAlbum'
        ? request['input_message_contents'] as TdObject[]
        : [(request['input_message_content'] as TdObject | undefined) ?? {}];
      const keys: string[] = explicitKeys ?? contents.map((c: TdObject): string =>
        sendPermissionForType((c['@type'] as string | undefined) ?? ''));
      await requireSendPermissions(port, chatId, keys);
    }
  } catch (error) {
    showSendPermissionError(error as Error);
    throw error as Error;
  }
  if (!active()) { throw new Error('send session ended'); }
  try { return await client.send(request); }
  catch (error) {
    const message: string = (error as Error).message ?? '';
    if (/CHAT_SEND_[A-Z_]+_FORBIDDEN|CHAT_WRITE_FORBIDDEN|CHAT_RESTRICTED/.test(message)) {
      const content = request['input_message_content'] as TdObject | undefined;
      const denied = new SendPermissionError(sendPermissionMessage(explicitKeys?.[0] ??
        sendPermissionForType((content?.['@type'] as string | undefined) ?? '')));
      showSendPermissionError(denied as Error);
      throw denied;
    }
    throw error as Error;
  }
}
