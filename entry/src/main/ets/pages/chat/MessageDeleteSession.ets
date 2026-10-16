import { UIContext } from '@kit.ArkUI';
import { TdObject } from '../../tdkit/TdTypes';
import { TdClient } from '../../tdkit/TdClient';
import { MessageEntry } from '../../store/MessageEntry';
import { loadMessageModeration, executeMessageDelete, loadMessageDeleteProperties } from '../../services/MessageModeration';
import {
  DeleteMessageChoice, ModerationOptions, ModerationTarget, moderationTarget, noModeration, messageDeleteScope, MessageDeleteScope
} from '../../util/messageModeration';
import { str } from '../../util/strings';
import { openDeleteMessagesDialog } from './DeleteMessagesDialog';

export interface MessageDeleteHost {
  ui: () => UIContext;
  client: () => TdClient;
  chatId: () => number;
  selfId: () => number;
  markLeaving: (ids: number[]) => void;
  clearLeaving: () => void;
  onDeleted: () => void;
}

function stepLabel(step: string): string {
  if (step === 'report') { return str('ab_report_spam'); }
  if (step === 'ban') { return str('ga_ban'); }
  if (step === 'remove') { return str('ga_remove_member'); }
  if (step === 'deleteAll') { return str('ga_delete_all'); }
  if (step === 'scope') { return str('delete'); }
  if (step === 'permissions') { return str('dm_permissions_changed'); }
  return str('delete');
}

export class MessageDeleteSession {
  private host: MessageDeleteHost | null = null;
  private seq: number = 0;
  private preparing: boolean = false;
  private busy: boolean = false;
  private closeDialog: (() => void) | null = null;

  bind(host: MessageDeleteHost): void { this.host = host; }

  async open(ids: number[], entries: MessageEntry[], peerName: string, isGroup: boolean): Promise<void> {
    const host: MessageDeleteHost | null = this.host;
    if (host === null || ids.length === 0 || this.preparing || this.busy) { return; }
    this.closeDialog?.();
    const seq: number = ++this.seq;
    const client: TdClient = host.client();
    const chatId: number = host.chatId();
    const selfId: number = host.selfId();
    const frozenIds: number[] = Array.from(new Set(ids));
    const target: ModerationTarget | null = isGroup ? moderationTarget(frozenIds, entries, selfId) : null;
    const active = (): boolean => seq === this.seq && host.chatId() === chatId &&
      host.selfId() === selfId && host.client() === client;
    let options: ModerationOptions = noModeration();
    let scope: MessageDeleteScope = { self: false, all: false };
    this.preparing = true;
    const loadingTimer: number = setTimeout((): void => {
      if (active() && this.preparing) {
        host.ui().getPromptAction().showToast({ message: str('loading_short'), duration: 2000 });
      }
    }, 600);
    try {
      const properties: TdObject[] = await loadMessageDeleteProperties(client, chatId, frozenIds);
      if (!active()) { return; }
      scope = messageDeleteScope(properties);
      if (!scope.self && !scope.all) {
        host.ui().getPromptAction().showToast({ message: str('dm_scope_unavailable'), duration: 3500 });
        return;
      }
      if (target !== null) {
        try { options = await loadMessageModeration(client, chatId, selfId, target, frozenIds, properties); }
        catch (_) { options = noModeration(); }
      }
    } catch (_) {
      if (active()) {
        host.ui().getPromptAction().showToast({ message: str('dm_scope_unavailable'), duration: 3500 });
      }
      return;
    } finally {
      clearTimeout(loadingTimer);
      if (seq === this.seq) { this.preparing = false; }
    }
    if (!active()) { return; }
    this.closeDialog = openDeleteMessagesDialog(host.ui(), peerName, scope, (choice: DeleteMessageChoice): void => {
      if (!active() || this.busy) { return; }
      this.busy = true;
      executeMessageDelete(client, chatId, selfId, frozenIds, target, choice, active,
        (): void => { if (active()) { host.markLeaving(frozenIds); } }).then((result): void => {
        if (!active()) { return; }
        this.busy = false;
        if (result.failed === '') {
          host.onDeleted();
          return;
        }
        host.clearLeaving();
        const message: string = result.completed.length === 0
          ? str('cp_delete_failed_msg', `${stepLabel(result.failed)}: ${result.error}`)
          : str('dm_moderation_partial', result.completed.map(stepLabel).join(' / '),
            stepLabel(result.failed), result.error);
        host.ui().getPromptAction().showToast({ message, duration: 3500 });
      }).catch((): void => {
        if (!active()) { return; }
        this.busy = false;
        host.clearLeaving();
        host.ui().getPromptAction().showToast({ message: str('ga_failed'), duration: 2000 });
      });
    }, options, target?.name || target?.userId.toString() || '');
  }

  dispose(): void {
    this.seq++;
    this.preparing = false;
    this.busy = false;
    this.closeDialog?.();
    this.closeDialog = null;
  }
}
