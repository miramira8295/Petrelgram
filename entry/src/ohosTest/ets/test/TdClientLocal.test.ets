import { describe, it, expect } from '@ohos/hypium';
import { TdClient } from '../../../main/ets/tdkit/TdClient';
import { TdObject, TdRequest, TdBridge, TdError } from '../../../main/ets/tdkit/TdTypes';

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

export default function tdClientLocalTestOnDevice() {
  describe('TdClientLocalOnDevice', () => {
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
  });
}
