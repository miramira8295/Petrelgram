import { TdClient } from '../tdkit/TdClient';
import { getTdClient } from '../tdkit/Globals';
import { TD_SESSION_EPOCH } from '../tdkit/AccountRegistry';
import { TdObject, TdRequest } from '../tdkit/TdTypes';
export interface DocumentLoginPrompt { domain: string; botUserId: number; writeAccess: boolean; }
export interface DocumentLoginActions {
  current: () => boolean;
  // cancel/open/login/write. Write permission is never inferred from opening.
  confirm: (prompt: DocumentLoginPrompt) => Promise<string>;
  open: (url: string, askFirst: boolean) => void;
}
// One request chain per physical row. No render-time work, global cache or logs
// containing signed login URLs. Every await rechecks both owner and account.
export class DocumentLoginUrl {
  private serial: number = 0;
  private busy: boolean = false;
  cancel(): void { this.serial++; this.busy = false; }
  async open(chatId: number, messageId: number, buttonId: number, fallback: string, actions: DocumentLoginActions): Promise<void> {
    if (this.busy || !actions.current()) { return; }
    if (!Number.isSafeInteger(buttonId) || buttonId <= 0) { actions.open(fallback, true); return; }
    let client: TdClient;
    try { client = getTdClient(); } catch (_) { return; }
    const epoch = AppStorage.get<number>(TD_SESSION_EPOCH) ?? 0;
    const token = ++this.serial; this.busy = true;
    const current = (): boolean => {
      try { return token === this.serial && client === getTdClient() &&
        epoch === (AppStorage.get<number>(TD_SESSION_EPOCH) ?? 0) && actions.current(); }
      catch (_) { return false; }
    };
    try {
      const request: TdRequest = { '@type': 'getLoginUrlInfo' };
      request['chat_id'] = chatId; request['message_id'] = messageId; request['button_id'] = buttonId;
      const info = await client.send(request);
      if (!current()) { return; }
      const url = (info['url'] as string | undefined) || fallback;
      if (info['@type'] === 'loginUrlInfoOpen') { actions.open(url, info['skip_confirmation'] !== true); return; }
      if (info['@type'] !== 'loginUrlInfoRequestConfirmation') { actions.open(fallback, true); return; }
      const write = info['request_write_access'] === true;
      const choice = await actions.confirm({ domain: (info['domain'] as string | undefined) ?? '',
        botUserId: (info['bot_user_id'] as number | undefined) ?? 0, writeAccess: write });
      if (!current() || choice === 'cancel') { return; }
      if (choice === 'open') { actions.open(url, true); return; }
      if (choice !== 'login' && choice !== 'write') { return; }
      const authorize: TdRequest = { '@type': 'getLoginUrl' };
      authorize['chat_id'] = chatId; authorize['message_id'] = messageId; authorize['button_id'] = buttonId;
      authorize['allow_write_access'] = choice === 'write' && write;
      const result: TdObject = await client.send(authorize);
      if (current()) { actions.open((result['url'] as string | undefined) || url, false); }
    } catch (_) {
      // TDLib specifies the ordinary URL fallback on authorization errors.
      if (current()) { actions.open(fallback, true); }
    } finally { if (token === this.serial) { this.busy = false; } }
  }
}
