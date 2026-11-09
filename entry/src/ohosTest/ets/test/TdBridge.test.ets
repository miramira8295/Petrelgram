import { describe, it, expect } from '@ohos/hypium';
import testNapi from 'libentry.so';
import { TdClient } from '../../../main/ets/tdkit/TdClient';
import { TdObject } from '../../../main/ets/tdkit/TdTypes';

export default function tdBridgeTest() {
  describe('TdBridgeSmoke', () => {
    it('receives_first_authorization_update', 0, async () => {
      const client = new TdClient({ init: testNapi.tdInit, send: testNapi.tdSend });
      const first = new Promise<string>((resolve) => {
        client.onUpdate('updateAuthorizationState', (u: TdObject) => {
          const st = u['authorization_state'] as TdObject;
          resolve(st['@type'] as string);
        });
      });
      client.start();
      const state = await first;
      // 全新客户端首个状态必为 WaitTdlibParameters
      expect(state).assertEqual('authorizationStateWaitTdlibParameters');
    });
  });
}
