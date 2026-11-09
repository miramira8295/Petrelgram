import { describe, it, expect } from '@ohos/hypium';
import { TdClient, TimerFns } from '../main/ets/tdkit/TdClient';
import { TdBridge, TdObject } from '../main/ets/tdkit/TdTypes';
import { CallsStore } from '../main/ets/store/CallsStore';

class FakeBridge implements TdBridge {
  onReceive: (json: string) => void = (): void => {};
  sent: string[] = [];
  init(cb: (json: string) => void): void { this.onReceive = cb; }
  send(json: string): void { this.sent.push(json); }
}

function createClient(bridge: FakeBridge): TdClient {
  const timer: TimerFns = {
    setTimeout: (_cb: () => void, _ms: number): number => 1,
    clearTimeout: (_id: number): void => {}
  };
  const client = new TdClient(bridge, timer);
  client.start();
  return client;
}

function latestRequest(bridge: FakeBridge, type: string): TdObject {
  for (let index = bridge.sent.length - 1; index >= 0; index--) {
    const request = JSON.parse(bridge.sent[index]) as TdObject;
    if (request['@type'] === type) { return request; }
  }
  return {} as TdObject;
}

function respond(bridge: FakeBridge, request: TdObject, result: TdObject): void {
  result['@extra'] = request['@extra'] as Object;
  bridge.onReceive(JSON.stringify(result));
}

function callMessage(chatId: number, messageId: number, reasonType: string,
  outgoing: boolean = false, date: number = 100): TdObject {
  const reason: TdObject = { '@type': reasonType };
  const content: TdObject = { '@type': 'messageCall' };
  content['discard_reason'] = reason;
  content['is_video'] = false;
  content['duration'] = 0;
  const message: TdObject = { '@type': 'message' };
  message['id'] = messageId;
  message['chat_id'] = chatId;
  message['date'] = date;
  message['is_outgoing'] = outgoing;
  message['content'] = content;
  return message;
}

function foundMessages(messages: TdObject[], total: number, nextOffset: string = ''): TdObject {
  const result: TdObject = { '@type': 'foundMessages' };
  result['messages'] = messages;
  result['total_count'] = total;
  result['next_offset'] = nextOffset;
  return result;
}

export default function callsStoreTest() {
  describe('CallsStore', () => {
    it('keeps_same_message_id_from_different_chats', 0, async () => {
      const bridge = new FakeBridge();
      const store = new CallsStore(createClient(bridge));
      store.open();
      const request = latestRequest(bridge, 'searchCallMessages');
      expect(request['only_missed'] as boolean).assertEqual(false);
      respond(bridge, request, foundMessages([
        callMessage(101, 9, 'callDiscardReasonHungUp', true, 200),
        callMessage(202, 9, 'callDiscardReasonMissed', false, 190)
      ], 2));
      await Promise.resolve();
      expect(store.calls.length).assertEqual(2);
      expect(store.calls[0].key).assertEqual('101:9');
      expect(store.calls[1].key).assertEqual('202:9');
      store.close();
    });

    it('requests_missed_mode_from_tdlib', 0, () => {
      const bridge = new FakeBridge();
      const store = new CallsStore(createClient(bridge));
      store.open();
      store.setMode('missed');
      const request = latestRequest(bridge, 'searchCallMessages');
      expect(request['only_missed'] as boolean).assertEqual(true);
      store.close();
    });

    it('preserves_live_call_arriving_during_refresh', 0, async () => {
      const bridge = new FakeBridge();
      const store = new CallsStore(createClient(bridge));
      store.open();
      const initial = latestRequest(bridge, 'searchCallMessages');
      respond(bridge, initial, foundMessages([], 0));
      await Promise.resolve();
      store.refresh();
      const refresh = latestRequest(bridge, 'searchCallMessages');
      const update: TdObject = { '@type': 'updateNewMessage' };
      update['message'] = callMessage(303, 11, 'callDiscardReasonMissed', false, 300);
      bridge.onReceive(JSON.stringify(update));
      respond(bridge, refresh, foundMessages([], 0));
      await Promise.resolve();
      expect(store.calls.length).assertEqual(1);
      expect(store.calls[0].key).assertEqual('303:11');
      expect(store.totalCount).assertEqual(1);
      store.close();
    });

    it('restores_page_cursor_when_clear_fails', 0, async () => {
      const bridge = new FakeBridge();
      const store = new CallsStore(createClient(bridge));
      store.open();
      const initial = latestRequest(bridge, 'searchCallMessages');
      const item = callMessage(404, 12, 'callDiscardReasonHungUp', true, 400);
      respond(bridge, initial, foundMessages([item], 3, 'next-page'));
      await Promise.resolve();
      expect(store.hasMore).assertTrue();
      const clearPromise = store.clearAll();
      const clearRequest = latestRequest(bridge, 'deleteAllCallMessages');
      const error: TdObject = { '@type': 'error' };
      error['code'] = 500;
      error['message'] = 'TEST_FAILURE';
      respond(bridge, clearRequest, error);
      try { await clearPromise; } catch (_) {}
      expect(store.calls.length).assertEqual(1);
      expect(store.hasMore).assertTrue();
      store.close();
    });
  });
}
