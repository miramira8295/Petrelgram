import { describe, it, expect } from '@ohos/hypium';
import { TdClient } from '../main/ets/tdkit/TdClient';
import { TdObject, TdBridge } from '../main/ets/tdkit/TdTypes';
import { LiveStreamStore } from '../main/ets/store/LiveStreamStore';

class FakeBridge implements TdBridge {
  onReceive: (json: string) => void = (): void => {};
  sent: string[] = [];
  init(cb: (json: string) => void): void { this.onReceive = cb; }
  send(json: string): void { this.sent.push(json); }
}
function pushGroupCall(b: FakeBridge, id: number, active: boolean, joined: boolean, count: number): void {
  const gc: TdObject = { '@type': 'groupCall', 'id': id as Object, 'is_active': active as Object, 'is_joined': joined as Object, 'participant_count': count as Object, 'need_rejoin': false };
  const u: TdObject = { '@type': 'updateGroupCall', 'group_call': gc as Object };
  b.onReceive(JSON.stringify(u));
}

export default function liveStreamStoreTest() {
  describe('LiveStreamStore', () => {
    it('applies_matching_group_call_update', 0, () => {
      const b = new FakeBridge(); const c = new TdClient(b); c.start();
      const store = new LiveStreamStore(c, 42);
      pushGroupCall(b, 42, true, true, 5);
      const s = store.getState();
      expect(s.isActive).assertEqual(true);
      expect(s.isJoined).assertEqual(true);
      expect(s.participantCount).assertEqual(5);
    });

    it('ignores_other_group_call_id', 0, () => {
      const b = new FakeBridge(); const c = new TdClient(b); c.start();
      const store = new LiveStreamStore(c, 42);
      pushGroupCall(b, 99, true, true, 5);
      expect(store.getState().participantCount).assertEqual(0);
    });

    it('notifies_subscribers_immutably', 0, () => {
      const b = new FakeBridge(); const c = new TdClient(b); c.start();
      const store = new LiveStreamStore(c, 42);
      const before = store.getState();
      let count = 0;
      store.subscribe(() => { count += 1; });
      pushGroupCall(b, 42, true, false, 3);
      const after = store.getState();
      expect(count).assertEqual(1);
      expect(before === after).assertEqual(false); // 新对象,未原地修改
    });
  });
}
