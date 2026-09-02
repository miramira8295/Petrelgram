import { describe, it, expect } from '@ohos/hypium';
import { TdClient, TimerFns } from '../main/ets/tdkit/TdClient';
import { TdObject, TdRequest, TdBridge, TdError } from '../main/ets/tdkit/TdTypes';

class FakeBridge implements TdBridge {
  onReceive: (json: string) => void;
  sent: string[];

  constructor() {
    this.sent = [];
    this.onReceive = (json: string): void => {};
  }

  init(cb: (json: string) => void): void {
    this.onReceive = cb;
  }

  send(json: string): void {
    this.sent.push(json);
  }
}

function mkObj(): TdObject {
  const result: Record<string, Object> = {};
  return result;
}

function mkReq(type: string): TdRequest {
  const result: TdRequest = { '@type': type };
  return result;
}

function setField(obj: TdObject, key: string, value: Object): void {
  obj[key] = value;
}

function parseJson(json: string): TdObject {
  const parsed = JSON.parse(json) as TdObject;
  return parsed;
}

function getSent(sent: string[]): string {
  return sent[0];
}

export default function tdClientTest() {
  describe('TdClient', () => {
    it('resolves_send_by_extra', 0, async () => {
      const bridge = new FakeBridge();
      const client = new TdClient(bridge);
      client.start();
      const req = mkReq('getOption');
      setField(req, 'name', 'version');
      const p = client.send(req);
      const sentJson: string = getSent(bridge.sent);
      const sent: TdObject = parseJson(sentJson);
      const resp = mkObj();
      setField(resp, '@type', 'optionValueString');
      setField(resp, 'value', '1.8.0');
      setField(resp, '@extra', sent['@extra'] as Object);
      bridge.onReceive(JSON.stringify(resp));
      const result = await p;
      expect(result['value']).assertEqual('1.8.0');
    });

    it('rejects_on_error_object', 0, async () => {
      const bridge = new FakeBridge();
      const client = new TdClient(bridge);
      client.start();
      const req = mkReq('sendMessage');
      const p = client.send(req);
      const sentJson: string = getSent(bridge.sent);
      const sent: TdObject = parseJson(sentJson);
      const errResp = mkObj();
      setField(errResp, '@type', 'error');
      setField(errResp, 'code', 400);
      setField(errResp, 'message', 'CHAT_ID_INVALID');
      setField(errResp, '@extra', sent['@extra'] as Object);
      bridge.onReceive(JSON.stringify(errResp));
      let code: number = 0;
      try { await p; } catch (e) { code = (e as TdError).code; }
      expect(code).assertEqual(400);
    });

    it('dispatches_updates_by_type', 0, () => {
      const bridge = new FakeBridge();
      const client = new TdClient(bridge);
      client.start();
      let got: string = '';
      client.onUpdate('updateAuthorizationState', (u: TdObject) => {
        const st = u['authorization_state'] as TdObject;
        got = st['@type'] as string;
      });
      const authState = mkObj();
      setField(authState, '@type', 'authorizationStateWaitPhoneNumber');
      const update = mkObj();
      setField(update, '@type', 'updateAuthorizationState');
      setField(update, 'authorization_state', authState);
      bridge.onReceive(JSON.stringify(update));
      expect(got).assertEqual('authorizationStateWaitPhoneNumber');
    });

    it('deliverParsed_dispatches_without_parse', 0, () => {
      // worker 桥路径（A 批 1）：对象在 worker 侧解析，UI 侧直接分发。
      const bridge = new FakeBridge();
      const client = new TdClient(bridge);
      client.start();
      let got: string = '';
      client.onUpdate('updateX', (u: TdObject) => { got = u['v'] as string; });
      const update = mkObj();
      setField(update, '@type', 'updateX');
      setField(update, 'v', 'from-worker');
      client.deliverParsed(update);
      expect(got).assertEqual('from-worker');
    });

    it('deliverParsed_resolves_pending_by_extra', 0, async () => {
      const bridge = new FakeBridge();
      const client = new TdClient(bridge);
      client.start();
      const p = client.send(mkReq('getMe'));
      const sent = JSON.parse(bridge.sent[0]) as TdObject;
      const reply = mkObj();
      setField(reply, '@type', 'user');
      setField(reply, '@extra', sent['@extra'] as string);
      client.deliverParsed(reply);
      const got = await p;
      expect(got['@type'] as string).assertEqual('user');
    });

    it('unsubscribe_stops_delivery', 0, () => {
      const bridge = new FakeBridge();
      const client = new TdClient(bridge);
      let count = 0;
      const off = client.onUpdate('updateX', () => { count += 1; });
      client.start();
      bridge.onReceive(JSON.stringify({ '@type': 'updateX' } as TdObject));
      off();
      bridge.onReceive(JSON.stringify({ '@type': 'updateX' } as TdObject));
      expect(count).assertEqual(1);
    });

    it('send_rejects_on_timeout', 0, () => {
      // Manual timer: capture the scheduled callback, fire it by hand.
      let fired: (() => void) | null = null;
      const timer: TimerFns = {
        setTimeout: (cb: () => void, _ms: number): number => { fired = cb; return 1; },
        clearTimeout: (_id: number): void => { fired = null; }
      };
      const bridge = new FakeBridge();
      const client = new TdClient(bridge, timer);
      client.start();
      let rejectedCode = 0;
      client.send({ '@type': 'loadChats' }).catch((e: TdError) => { rejectedCode = e.code; });
      fired!();            // simulate timeout elapsing with no response
      // allow the microtask from catch to run
      return Promise.resolve().then(() => { expect(rejectedCode).assertEqual(-1); });
    });

    it('send_resolve_clears_timeout', 0, () => {
      let cleared = false;
      const timer: TimerFns = {
        setTimeout: (_cb: () => void, _ms: number): number => 7,
        clearTimeout: (_id: number): void => { cleared = true; }
      };
      const bridge = new FakeBridge();
      const client = new TdClient(bridge, timer);
      client.start();
      const p = client.send({ '@type': 'getOption' });
      const sent = parseJson(bridge.sent[bridge.sent.length - 1]);
      const extra = sent['@extra'] as string;
      bridge.onReceive(JSON.stringify({ '@type': 'ok', '@extra': extra } as TdObject));
      return p.then(() => { expect(cleared).assertEqual(true); });
    });

    it('send_keeps_callers_request_untouched', 0, () => {
      const bridge = new FakeBridge();
      const client = new TdClient(bridge);
      client.start();
      const request: TdRequest = { '@type': 'getOption' };
      request['name'] = 'version';
      client.send(request).catch((): void => {});
      expect(request['@extra'] === undefined).assertTrue();
      const sent = parseJson(bridge.sent[0]);
      expect((sent['@extra'] as string).startsWith('req_')).assertTrue();
      client.dispose();
    });

    it('pending_requests_share_one_timeout_timer', 0, () => {
      let scheduled = 0;
      const timer: TimerFns = {
        setTimeout: (_cb: () => void, _ms: number): number => { scheduled += 1; return scheduled; },
        clearTimeout: (_id: number): void => {}
      };
      const bridge = new FakeBridge();
      const client = new TdClient(bridge, timer);
      client.start();
      client.send({ '@type': 'getOption' }).catch((): void => {});
      client.send({ '@type': 'getOption' }).catch((): void => {});
      expect(scheduled).assertEqual(1);
      client.dispose();
    });
  });
}
