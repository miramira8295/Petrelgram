import { TdClient } from '../tdkit/TdClient';
import { getTdClient } from '../tdkit/Globals';
import { TD_SESSION_EPOCH } from '../tdkit/AccountRegistry';
import { TdObject, TdRequest } from '../tdkit/TdTypes';

export interface DocumentSwitchActions {
  current: () => boolean;
  insert: (text: string) => void;
  unavailable: () => void;
}

// Android resolves via_bot_id before sender_id. A forwarded/channel sender is
// not necessarily the inline bot. Resolve only on a click, never during paint.
// Two sequential requests, one active chain per physical row, no global cache.
export class DocumentSwitchInline {
  private serial: number = 0;
  private busy: boolean = false;
  cancel(): void { this.serial++; this.busy = false; }

  async open(chatId: number, messageId: number, query: string, actions: DocumentSwitchActions): Promise<void> {
    if (this.busy || !actions.current()) { return; }
    let client: TdClient;
    try { client = getTdClient(); } catch (_) { actions.unavailable(); return; }
    const epoch = AppStorage.get<number>(TD_SESSION_EPOCH) ?? 0;
    const token = ++this.serial; this.busy = true;
    const current = (): boolean => {
      try { return token === this.serial && client === getTdClient() &&
        epoch === (AppStorage.get<number>(TD_SESSION_EPOCH) ?? 0) && actions.current(); }
      catch (_) { return false; }
    };
    try {
      const request: TdRequest = { '@type': 'getMessage' };
      request['chat_id'] = chatId; request['message_id'] = messageId;
      const message = await client.send(request);
      if (!current()) { return; }
      const sender = message['sender_id'] as TdObject | undefined;
      const botId = (message['via_bot_user_id'] as number | undefined) ||
        (sender?.['@type'] === 'messageSenderUser' ? (sender['user_id'] as number) : 0);
      if (!(botId > 0)) { actions.unavailable(); return; }
      const userRequest: TdRequest = { '@type': 'getUser' }; userRequest['user_id'] = botId;
      const user = await client.send(userRequest);
      if (!current()) { return; }
      const type = user['type'] as TdObject | undefined;
      const names = user['usernames'] as TdObject | undefined;
      const active = names?.['active_usernames'] as string[] | undefined;
      const username = active?.[0] ?? (user['username'] as string | undefined) ?? '';
      if (type?.['@type'] !== 'userTypeBot' || type['is_inline'] !== true ||
        !/^[A-Za-z0-9_]+$/.test(username)) { actions.unavailable(); return; }
      actions.insert(`@${username} ${query}`);
    } catch (_) { if (current()) { actions.unavailable(); } }
    finally { if (token === this.serial) { this.busy = false; } }
  }
}
