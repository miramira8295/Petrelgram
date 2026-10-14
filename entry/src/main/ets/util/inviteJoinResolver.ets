import { TdClient } from '../tdkit/TdClient';
import { TdObject, TdRequest } from '../tdkit/TdTypes';

// A private approval invite can initially have no chat_id. Once TDLib learns
// a new chat, recheck the exact invite and hand over to normal membership updates.
export class InviteJoinResolver {
  private client: TdClient;
  private invite: string;
  private resolved: (chatId: number) => void;
  private off: (() => void) | null = null;
  private offGroup: (() => void) | null = null;
  private active: boolean = false;
  private checking: boolean = false;
  private dirty: boolean = false;

  constructor(client: TdClient, invite: string, resolved: (chatId: number) => void) {
    this.client = client;
    this.invite = invite;
    this.resolved = resolved;
  }

  start(): void {
    if (this.active) { return; }
    this.active = true;
    this.off = this.client.onUpdate('updateNewChat', (): void => { this.refresh(); });
    this.offGroup = this.client.onUpdate('updateSupergroup', (update: TdObject): void => {
      const group = update['supergroup'] as TdObject | undefined;
      const status = group?.['status'] as TdObject | undefined;
      const type: string = (status?.['@type'] as string | undefined) ?? '';
      if (type === 'chatMemberStatusMember' || type === 'chatMemberStatusAdministrator' ||
        type === 'chatMemberStatusCreator' ||
        (type === 'chatMemberStatusRestricted' && status?.['is_member'] === true)) {
        this.refresh();
      }
    });
    this.refresh();
  }

  refresh(): void {
    if (!this.active) { return; }
    if (this.checking) { this.dirty = true; return; }
    this.checking = true;
    this.dirty = false;
    const request: TdRequest = { '@type': 'checkChatInviteLink' };
    request['invite_link'] = this.invite;
    this.client.send(request)
      .then((info: TdObject): void => {
        if (!this.active) { return; }
        const chatId: number = (info['chat_id'] as number | undefined) ?? 0;
        if (chatId !== 0) {
          this.dispose();
          this.resolved(chatId);
        }
      }).catch((): void => {
        // An unavailable preview is not a rejected join request. Retry on the
        // next relevant event or page return, without polling or a failure toast.
      }).finally((): void => {
        this.checking = false;
        if (this.dirty) { this.refresh(); }
      });
  }

  dispose(): void {
    this.active = false;
    this.off?.();
    this.off = null;
    this.offGroup?.();
    this.offGroup = null;
    this.dirty = false;
  }
}
