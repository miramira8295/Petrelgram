import { TdClient } from '../../tdkit/TdClient';
import { TdObject, TdRequest } from '../../tdkit/TdTypes';
import { getTdClient } from '../../tdkit/Globals';
import { navigateToChat } from '../../util/chatNav';
import { navigateToDirectMessagesTopics } from '../../util/profileNav';
import { showToast } from '../../util/toast';
import { str } from '../../util/strings';
import { logW } from '../../util/log';

// Android's channel BUTTON_DIRECT opens the linked monoforum, never the
// discussion group. TDLib exposes that destination as direct_messages_chat_id.
// One full-info read/subscription per active channel; no requests from build().
@ObservedV2
export class ChannelDirectMessagesSession {
  @Trace targetChatId: number = 0;
  private client: TdClient | null = null;
  private sourceChatId: number = 0;
  private supergroupId: number = 0;
  private generation: number = 0;
  private revision: number = 0;
  private targetRevision: number = 0;
  private opening: boolean = false;
  private unsubscribe: (() => void) | null = null;

  sync(client: TdClient, chatId: number, group: TdObject): void {
    const groupId: number = (group['id'] as number | undefined) ?? 0;
    if (group['is_channel'] !== true || group['has_direct_messages_group'] === false ||
      groupId === 0 || chatId === 0) {
      this.dispose();
      return;
    }
    if (client === this.client && chatId === this.sourceChatId && groupId === this.supergroupId) { return; }
    this.dispose();
    this.client = client;
    this.sourceChatId = chatId;
    this.supergroupId = groupId;
    const generation: number = this.generation;
    this.unsubscribe = client.onUpdate('updateSupergroupFullInfo', (update: TdObject): void => {
      if (!this.active(client, generation) || update['supergroup_id'] !== groupId) { return; }
      const info = update['supergroup_full_info'] as TdObject | undefined;
      if (info !== undefined) { this.revision++; this.apply(info); }
    });
    const revision: number = this.revision;
    const request: TdRequest = { '@type': 'getSupergroupFullInfo' };
    request['supergroup_id'] = groupId;
    client.send(request).then((info: TdObject): void => {
      if (this.active(client, generation) && revision === this.revision) { this.apply(info); }
    }).catch((error: Error): void => {
      if (this.active(client, generation)) { logW(`Channel direct messages info: ${error.message}`); }
    });
  }

  private active(client: TdClient, generation: number): boolean {
    return this.client === client && getTdClient() === client && this.generation === generation;
  }

  private apply(info: TdObject): void {
    const id: number = (info['direct_messages_chat_id'] as number | undefined) ?? 0;
    const target: number = Number.isSafeInteger(id) && id < 0 && id !== this.sourceChatId ? id : 0;
    if (this.targetChatId !== target) {
      this.targetRevision++;
      this.targetChatId = target;
    }
  }

  async open(): Promise<void> {
    const client: TdClient | null = this.client;
    const id: number = this.targetChatId;
    const generation: number = this.generation;
    const revision: number = this.targetRevision;
    if (client === null || id === 0 || this.opening || !this.active(client, generation)) { return; }
    this.opening = true;
    const valid = (): boolean => this.active(client, generation) &&
      this.targetChatId === id && this.targetRevision === revision;
    try {
      const chatRequest: TdRequest = { '@type': 'getChat' };
      chatRequest['chat_id'] = id;
      const chat = await client.send(chatRequest);
      if (!valid()) { return; }
      const type = chat['type'] as TdObject | undefined;
      if (type?.['@type'] !== 'chatTypeSupergroup' || chat['id'] !== id) {
        throw new Error('Invalid channel direct messages destination');
      }
      const groupRequest: TdRequest = { '@type': 'getSupergroup' };
      groupRequest['supergroup_id'] = type['supergroup_id'];
      const group = await client.send(groupRequest);
      if (!valid()) { return; }
      if (group['is_direct_messages_group'] !== true) { throw new Error('Channel direct messages unavailable'); }
      const params: Record<string, Object> = { 'chatId': id, 'title': (chat['title'] as string | undefined) ?? '' };
      if (group['is_administered_direct_messages_group'] === true) {
        navigateToDirectMessagesTopics(params, 'content');
      } else {
        await navigateToChat(params, 'content');
      }
    } catch (error) {
      if (valid()) {
        showToast(str('cp_channel_direct_unavailable'), 2000);
        logW(`Channel direct messages open: ${(error as Error).message}`);
      }
    } finally {
      if (this.active(client, generation)) { this.opening = false; }
    }
  }

  dispose(): void {
    this.generation++;
    this.unsubscribe?.();
    this.unsubscribe = null;
    this.client = null;
    this.sourceChatId = 0;
    this.supergroupId = 0;
    this.revision = 0;
    this.targetChatId = 0;
    this.opening = false;
  }
}
