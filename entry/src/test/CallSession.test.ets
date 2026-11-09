import { describe, it, expect } from '@ohos/hypium';
import { TdClient } from '../main/ets/tdkit/TdClient';
import { TdObject, TdBridge } from '../main/ets/tdkit/TdTypes';
import { UserStore } from '../main/ets/store/UserStore';
import { CallSession, CallSnapshot } from '../main/ets/services/CallSession';
import { CallMediaBridge, CallMediaConfig } from '../main/ets/services/CallMediaBridge';

class FakeBridge implements TdBridge {
  onReceive: (json: string) => void = (): void => {};
  sent: string[] = [];
  init(cb: (json: string) => void): void { this.onReceive = cb; }
  send(json: string): void { this.sent.push(json); }
}

class FakeCallMedia implements CallMediaBridge {
  onState: (state: string) => void = (): void => {};
  onSignalingData: (dataBase64: string) => void = (): void => {};
  onRemoteMedia: (audioMuted: boolean, videoActive: boolean) => void = (): void => {};
  startConfigs: CallMediaConfig[] = [];
  stopCount: number = 0;
  received: string[] = [];
  mutedCalls: boolean[] = [];
  videoModes: number[] = [];
  startResult: boolean = true;

  start(config: CallMediaConfig): boolean {
    this.startConfigs.push(config);
    return this.startResult;
  }

  stop(): void { this.stopCount++; }

  receiveSignaling(dataBase64: string): void { this.received.push(dataBase64); }

  setMuted(muted: boolean): void { this.mutedCalls.push(muted); }

  setVideo(mode: number): void { this.videoModes.push(mode); }

  setAudioOutput(speaker: boolean): void {}

  setLocalSurface(surfaceId: string): void {}

  setRemoteSurface(surfaceId: string): void {}
}

function setup(): Array<Object> {
  const b = new FakeBridge();
  const c = new TdClient(b);
  const u = new UserStore(c);
  const m = new FakeCallMedia();
  const s = new CallSession(c, u, m);
  c.start();
  return [b, s, m];
}

function lastRequest(b: FakeBridge, type: string): TdObject | undefined {
  for (let i = b.sent.length - 1; i >= 0; i--) {
    const o = JSON.parse(b.sent[i]) as TdObject;
    if (o['@type'] === type) {
      return o;
    }
  }
  return undefined;
}

function requestCount(b: FakeBridge, type: string): number {
  return b.sent.filter((json: string): boolean =>
    (JSON.parse(json) as TdObject)['@type'] === type).length;
}

function callState(type: string, extraFields?: TdObject): TdObject {
  const st: TdObject = { '@type': type };
  if (extraFields !== undefined) {
    const keys = Object.keys(extraFields);
    for (const k of keys) {
      st[k] = extraFields[k];
    }
  }
  return st;
}

function feedCall(b: FakeBridge, id: number, userId: number, outgoing: boolean,
  isVideo: boolean, state: TdObject): void {
  const call: TdObject = { '@type': 'call' };
  call['id'] = id;
  call['user_id'] = userId;
  call['is_outgoing'] = outgoing;
  call['is_video'] = isVideo;
  call['state'] = state;
  const upd: TdObject = { '@type': 'updateCall' };
  upd['call'] = call;
  b.onReceive(JSON.stringify(upd));
}

function readyState(): TdObject {
  const server: TdObject = { '@type': 'callServer' };
  server['id'] = 1;
  server['ip_address'] = '1.2.3.4';
  server['port'] = 555;
  const serverType: TdObject = { '@type': 'callServerTypeWebrtc' };
  serverType['username'] = 'u';
  serverType['password'] = 'p';
  serverType['supports_turn'] = true;
  server['type'] = serverType;
  return callState('callStateReady', {
    'encryption_key': 'S0VZ',
    'servers': [server],
    'emojis': ['🐱', '🍎', '🌙', '⚡'],
    'allow_p2p': true
  } as TdObject);
}

function snapshotOf(s: CallSession): CallSnapshot {
  let snap: CallSnapshot | null = null;
  const un = s.subscribe((x: CallSnapshot): void => { snap = x; });
  un();
  return snap!;
}

export default function callSessionTest() {
  describe('CallSession', () => {
    it('start_call_sends_createCall_with_protocol', 0, () => {
      const arr = setup(); const b = arr[0] as FakeBridge; const s = arr[1] as CallSession;
      s.startCall(7, false);
      const req = lastRequest(b, 'createCall');
      expect(req !== undefined).assertTrue();
      expect(req!['user_id']).assertEqual(7);
      expect(req!['is_video']).assertEqual(false);
      const protocol = req!['protocol'] as TdObject;
      expect(protocol['@type']).assertEqual('callProtocol');
      expect(protocol['udp_p2p']).assertEqual(true);
      expect((protocol['library_versions'] as string[]).length > 0).assertTrue();
      expect(snapshotOf(s).phase).assertEqual('dialing');
    });
    it('ready_state_starts_media_with_encryption_key', 0, () => {
      const arr = setup(); const b = arr[0] as FakeBridge;
      const s = arr[1] as CallSession; const m = arr[2] as FakeCallMedia;
      s.startCall(7, false);
      feedCall(b, 11, 7, true, false, callState('callStatePending'));
      feedCall(b, 11, 7, true, false, callState('callStateExchangingKeys'));
      feedCall(b, 11, 7, true, false, readyState());
      expect(m.startConfigs.length).assertEqual(1);
      expect(m.startConfigs[0].encryptionKeyBase64).assertEqual('S0VZ');
      expect(m.startConfigs[0].isOutgoing).assertEqual(true);
      expect(m.startConfigs[0].serversJson.indexOf('1.2.3.4') >= 0).assertTrue();
      const snap = snapshotOf(s);
      expect(snap.phase).assertEqual('connecting');
      expect(snap.emojis.join('')).assertEqual('🐱🍎🌙⚡');
      m.onState('ready');
      const active = snapshotOf(s);
      expect(active.phase).assertEqual('active');
      expect(active.startedAtMs > 0).assertTrue();
    });
    it('incoming_pending_publishes_ringing', 0, () => {
      const arr = setup(); const b = arr[0] as FakeBridge; const s = arr[1] as CallSession;
      feedCall(b, 21, 9, false, true, callState('callStatePending'));
      const snap = snapshotOf(s);
      expect(snap.phase).assertEqual('ringing');
      expect(snap.peerUserId).assertEqual(9);
      expect(snap.isVideo).assertEqual(true);
      expect(snap.isOutgoing).assertEqual(false);
    });
    it('accept_sends_acceptCall', 0, () => {
      const arr = setup(); const b = arr[0] as FakeBridge; const s = arr[1] as CallSession;
      feedCall(b, 21, 9, false, false, callState('callStatePending'));
      s.accept();
      const req = lastRequest(b, 'acceptCall');
      expect(req !== undefined).assertTrue();
      expect(req!['call_id']).assertEqual(21);
      expect((req!['protocol'] as TdObject)['@type']).assertEqual('callProtocol');
    });
    it('decline_sends_discardCall', 0, () => {
      const arr = setup(); const b = arr[0] as FakeBridge; const s = arr[1] as CallSession;
      feedCall(b, 21, 9, false, false, callState('callStatePending'));
      s.decline();
      const req = lastRequest(b, 'discardCall');
      expect(req !== undefined).assertTrue();
      expect(req!['call_id']).assertEqual(21);
      expect(req!['is_disconnected']).assertEqual(false);
    });
    it('signaling_bridges_both_directions', 0, () => {
      const arr = setup(); const b = arr[0] as FakeBridge;
      const s = arr[1] as CallSession; const m = arr[2] as FakeCallMedia;
      s.startCall(7, false);
      feedCall(b, 11, 7, true, false, callState('callStatePending'));
      feedCall(b, 11, 7, true, false, readyState());
      const upd: TdObject = { '@type': 'updateNewCallSignalingData' };
      upd['call_id'] = 11;
      upd['data'] = 'QUJD';
      b.onReceive(JSON.stringify(upd));
      expect(m.received.join(',')).assertEqual('QUJD');
      m.onSignalingData('REVG');
      const req = lastRequest(b, 'sendCallSignalingData');
      expect(req !== undefined).assertTrue();
      expect(req!['call_id']).assertEqual(11);
      expect(req!['data']).assertEqual('REVG');
    });
    it('remote_discard_tears_down', 0, () => {
      const arr = setup(); const b = arr[0] as FakeBridge;
      const s = arr[1] as CallSession; const m = arr[2] as FakeCallMedia;
      s.startCall(7, false);
      feedCall(b, 11, 7, true, false, callState('callStatePending'));
      feedCall(b, 11, 7, true, false, readyState());
      feedCall(b, 11, 7, true, false, callState('callStateDiscarded', {
        'reason': { '@type': 'callDiscardReasonHungUp' } as TdObject
      } as TdObject));
      const snap = snapshotOf(s);
      expect(snap.phase).assertEqual('ended');
      expect(snap.endReason).assertEqual('hangup');
      expect(m.stopCount).assertEqual(1);
    });
    it('error_state_publishes_error', 0, () => {
      const arr = setup(); const b = arr[0] as FakeBridge; const s = arr[1] as CallSession;
      s.startCall(7, false);
      feedCall(b, 11, 7, true, false, callState('callStatePending'));
      feedCall(b, 11, 7, true, false, callState('callStateError', {
        'error': { '@type': 'error', 'code': 4005000, 'message': 'PARTICIPANT_VERSION_OUTDATED' } as TdObject
      } as TdObject));
      const snap = snapshotOf(s);
      expect(snap.phase).assertEqual('ended');
      expect(snap.endReason).assertEqual('error');
      expect(snap.errorText.length > 0).assertTrue();
    });
    it('hangup_sends_discard_with_duration', 0, () => {
      const arr = setup(); const b = arr[0] as FakeBridge;
      const s = arr[1] as CallSession; const m = arr[2] as FakeCallMedia;
      s.startCall(7, false);
      feedCall(b, 11, 7, true, false, callState('callStatePending'));
      feedCall(b, 11, 7, true, false, readyState());
      m.onState('ready');
      s.hangup();
      const req = lastRequest(b, 'discardCall');
      expect(req !== undefined).assertTrue();
      expect(req!['call_id']).assertEqual(11);
      expect(req!['is_disconnected']).assertEqual(false);
      expect((req!['duration'] as number) >= 0).assertTrue();
    });
    it('busy_rejects_second_incoming', 0, () => {
      const arr = setup(); const b = arr[0] as FakeBridge;
      const s = arr[1] as CallSession; const m = arr[2] as FakeCallMedia;
      s.startCall(7, false);
      feedCall(b, 11, 7, true, false, callState('callStatePending'));
      feedCall(b, 11, 7, true, false, readyState());
      m.onState('ready');
      feedCall(b, 33, 8, false, false, callState('callStatePending'));
      const req = lastRequest(b, 'discardCall');
      expect(req !== undefined).assertTrue();
      expect(req!['call_id']).assertEqual(33);
      const snap = snapshotOf(s);
      expect(snap.callId).assertEqual(11);
      expect(snap.phase).assertEqual('active');
    });
    it('incoming_after_previous_call_ended_rings_again', 0, () => {
      const arr = setup(); const b = arr[0] as FakeBridge;
      const s = arr[1] as CallSession; const m = arr[2] as FakeCallMedia;
      // 第一通：拨出 → 接通 → 对端挂断。
      s.startCall(7, false);
      feedCall(b, 11, 7, true, false, callState('callStatePending'));
      feedCall(b, 11, 7, true, false, readyState());
      m.onState('ready');
      feedCall(b, 11, 7, true, false, callState('callStateDiscarded', {
        'reason': { '@type': 'callDiscardReasonHungUp' } as TdObject
      } as TdObject));
      expect(snapshotOf(s).phase).assertEqual('ended');
      const discardsBefore: number = requestCount(b, 'discardCall');
      // 第二通：新来电必须正常响铃，不能被当成忙线拒接。
      feedCall(b, 44, 9, false, false, callState('callStatePending'));
      const snap = snapshotOf(s);
      expect(snap.phase).assertEqual('ringing');
      expect(snap.peerUserId).assertEqual(9);
      expect(requestCount(b, 'discardCall')).assertEqual(discardsBefore);
    });
    it('toggle_mute_forwards_to_media_and_snapshot', 0, () => {
      const arr = setup(); const b = arr[0] as FakeBridge;
      const s = arr[1] as CallSession; const m = arr[2] as FakeCallMedia;
      s.startCall(7, false);
      feedCall(b, 11, 7, true, false, readyState());
      s.toggleMute();
      expect(m.mutedCalls.join(',')).assertEqual('true');
      expect(snapshotOf(s).muted).assertTrue();
      s.toggleMute();
      expect(m.mutedCalls.join(',')).assertEqual('true,false');
      expect(snapshotOf(s).muted).assertFalse();
    });
  });
}
