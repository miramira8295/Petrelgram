import { describe, it, expect } from '@ohos/hypium';
import { TdClient } from '../main/ets/tdkit/TdClient';
import { TdObject, TdBridge } from '../main/ets/tdkit/TdTypes';
import { getGroupCallStreams, joinVideoChat } from '../main/ets/tdkit/GroupCallApi';

class FakeBridge implements TdBridge {
  onReceive: (json: string) => void = (): void => {};
  sent: string[] = [];
  init(cb: (json: string) => void): void { this.onReceive = cb; }
  send(json: string): void { this.sent.push(json); }
}
function extraOf(json: string): string {
  const o = JSON.parse(json) as TdObject;
  return o['@extra'] as string;
}

export default function groupCallApiTest() {
  describe('GroupCallApi', () => {
    it('getGroupCallStreams_parses_streams', 0, async () => {
      const b = new FakeBridge(); const c = new TdClient(b); c.start();
      const p = getGroupCallStreams(c, 42);
      const extra = extraOf(b.sent[0]);
      const s0: TdObject = { '@type': 'groupCallStream', 'channel_id': 1, 'scale': 0, 'time_offset': 20000 };
      const resp: TdObject = { '@type': 'groupCallStreams', 'streams': [s0], '@extra': extra };
      b.onReceive(JSON.stringify(resp));
      const streams = await p;
      expect(streams.length).assertEqual(1);
      expect(streams[0].channelId).assertEqual(1);
      expect(streams[0].scale).assertEqual(0);
      expect(streams[0].timeOffset).assertEqual(20000);
    });

    it('getGroupCallStreams_sends_correct_request', 0, async () => {
      const b = new FakeBridge(); const c = new TdClient(b); c.start();
      getGroupCallStreams(c, 42);
      const req = JSON.parse(b.sent[0]) as TdObject;
      expect(req['@type']).assertEqual('getGroupCallStreams');
      expect(req['group_call_id']).assertEqual(42);
    });

    it('joinVideoChat_returns_text_and_sends_params', 0, async () => {
      const b = new FakeBridge(); const c = new TdClient(b); c.start();
      const p = joinVideoChat(c, 42, 0, '', true);
      const req = JSON.parse(b.sent[0]) as TdObject;
      expect(req['@type']).assertEqual('joinVideoChat');
      const jp = req['join_parameters'] as TdObject;
      expect(jp['is_muted']).assertEqual(true);
      expect(jp['is_my_video_enabled']).assertEqual(false);
      const extra = req['@extra'] as string;
      b.onReceive(JSON.stringify({ '@type': 'text', 'text': 'JOINRESP', '@extra': extra } as TdObject));
      const text = await p;
      expect(text).assertEqual('JOINRESP');
    });
  });
}
