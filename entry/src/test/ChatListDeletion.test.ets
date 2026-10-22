import { describe, expect, it } from '@ohos/hypium';
import { ConfirmedChatRemoval } from '../main/ets/util/confirmedChatRemoval';
import { executeChatListDelete } from '../main/ets/services/ChatListDeletion';
import { TdClient } from '../main/ets/tdkit/TdClient';
import { TdBridge, TdObject } from '../main/ets/tdkit/TdTypes';

class ChatDeletionBridge implements TdBridge {
  private receive: (json: string) => void = (): void => {};
  requests: TdObject[] = [];
  active: boolean = true;
  stopAfter: string = '';
  failType: string = '';
  init(receive: (json: string) => void): void { this.receive = receive; }
  send(json: string): void {
    const req = JSON.parse(json) as TdObject;
    this.requests.push(req);
    if (req['@type'] === this.stopAfter) { this.active = false; }
    const result: TdObject = req['@type'] === this.failType
      ? { '@type': 'error', 'code': 400, 'message': 'denied' } : { '@type': 'ok' };
    result['@extra'] = req['@extra'];
    this.receive(JSON.stringify(result));
  }
}

function clientFor(bridge: ChatDeletionBridge): TdClient {
  const client = new TdClient(bridge); client.start(); return client;
}

export default function chatListDeletionTest(): void {
  describe('ChatListDeletion', (): void => {
    it('confirmed_delete_waits_and_ignores_duplicate_confirmation', 0, async (): Promise<void> => {
      const removal = new ConfirmedChatRemoval(); let calls = 0;
      removal.channel.subscribe(11, (): void => {});
      const run = async (): Promise<boolean> => { calls++; return true; };
      const task = removal.perform(11, true, (): boolean => true, run);
      expect(calls).assertEqual(0);
      expect(await removal.perform(11, true, (): boolean => true, run)).assertFalse();
      removal.channel.complete(11);
      expect(await task).assertTrue(); expect(calls).assertEqual(1);
    });
    it('account_switch_during_animation_restores_without_deleting', 0, async (): Promise<void> => {
      const removal = new ConfirmedChatRemoval(); let active = true; let called = false;
      removal.channel.subscribe(11, (): void => {});
      const task = removal.perform(11, true, (): boolean => active,
        async (): Promise<boolean> => { called = true; return true; });
      active = false; removal.channel.complete(11);
      expect(await task).assertFalse(); expect(called).assertFalse();
      expect(removal.channel.value(11)).assertEqual(0);
    });
    it('server_failure_restores_only_the_failed_row', 0, async (): Promise<void> => {
      const removal = new ConfirmedChatRemoval();
      removal.channel.subscribe(11, (): void => {});
      removal.channel.mark([22]);
      const task = removal.perform(11, true, (): boolean => true, async (): Promise<boolean> => false);
      removal.channel.complete(11); expect(await task).assertFalse();
      expect(removal.channel.value(11)).assertEqual(0);
      expect(removal.channel.value(22)).assertEqual(1);
    });
    it('recycling_finishes_the_frozen_target_without_hiding_the_new_row', 0, async (): Promise<void> => {
      const removal = new ConfirmedChatRemoval(); let target = 0;
      const off = removal.channel.subscribe(11, (): void => {});
      const task = removal.perform(11, true, (): boolean => true,
        async (): Promise<boolean> => { target = 11; return true; });
      off(); removal.channel.restore(11);
      removal.channel.subscribe(22, (): void => {});
      expect(await task).assertTrue(); expect(target).assertEqual(11);
      expect(removal.channel.value(22)).assertEqual(0);
    });
    it('disabled_animation_sends_without_marking_the_row', 0, async (): Promise<void> => {
      const removal = new ConfirmedChatRemoval();
      removal.channel.subscribe(11, (): void => {});
      expect(await removal.perform(11, false, (): boolean => true,
        async (): Promise<boolean> => true)).assertTrue();
      expect(removal.channel.value(11)).assertEqual(0);
    });
    it('plain_delete_preserves_revoke_and_remove_from_list', 0, async (): Promise<void> => {
      const bridge = new ChatDeletionBridge();
      expect(await executeChatListDelete(clientFor(bridge), 11, true, false, (): boolean => bridge.active)).assertTrue();
      expect(bridge.requests.length).assertEqual(2);
      const req = bridge.requests[1];
      expect(req['@type']).assertEqual('deleteChatHistory');
      expect(req['chat_id']).assertEqual(11);
      expect(req['revoke']).assertTrue(); expect(req['remove_from_chat_list']).assertTrue();
    });
    it('block_finishes_before_delete_and_uses_the_same_chat', 0, async (): Promise<void> => {
      const bridge = new ChatDeletionBridge();
      await executeChatListDelete(clientFor(bridge), 11, false, true, (): boolean => bridge.active);
      expect(bridge.requests.map((r: TdObject): string => r['@type'] as string).join(','))
        .assertEqual('getChat,setMessageSenderBlockList,deleteChatHistory');
      expect((bridge.requests[1]['sender_id'] as TdObject)['user_id']).assertEqual(11);
      expect(bridge.requests[2]['revoke']).assertFalse();
    });
    it('switch_after_loading_stops_every_mutation', 0, async (): Promise<void> => {
      const bridge = new ChatDeletionBridge(); bridge.stopAfter = 'getChat';
      expect(await executeChatListDelete(clientFor(bridge), 11, false, true, (): boolean => bridge.active)).assertFalse();
      expect(bridge.requests.length).assertEqual(1);
    });
    it('switch_after_blocking_stops_delete', 0, async (): Promise<void> => {
      const bridge = new ChatDeletionBridge(); bridge.stopAfter = 'setMessageSenderBlockList';
      expect(await executeChatListDelete(clientFor(bridge), 11, false, true, (): boolean => bridge.active)).assertFalse();
      expect(bridge.requests.length).assertEqual(2);
    });
    it('failed_block_never_deletes_or_reports_success', 0, async (): Promise<void> => {
      const bridge = new ChatDeletionBridge(); bridge.failType = 'setMessageSenderBlockList';
      let failed = false;
      try { await executeChatListDelete(clientFor(bridge), 11, false, true, (): boolean => bridge.active); }
      catch (_) { failed = true; }
      expect(failed).assertTrue(); expect(bridge.requests.length).assertEqual(2);
    });
  });
}
