import { TdClient } from '../tdkit/TdClient';
import { TdObject, TdRequest, TdError } from '../tdkit/TdTypes';
import { UserStore } from '../store/UserStore';
import { CallMediaBridge, CallMediaConfig, CALL_VIDEO_OFF } from './CallMediaBridge';
import { str } from '../util/strings';
import { logE } from '../util/log';

// TDLib callProtocol 的 min/max_layer 取官方移动端长期使用的取值。
const CALL_MIN_LAYER: number = 65;
const CALL_MAX_LAYER: number = 92;

// tgcalls 支持的协议版本；应用启动时由 Globals 用原生 callVersions() 覆盖，
// 此静态列表仅作原生不可用时的回退（顺序即偏好，服务端协商取交集）。
export const CALL_LIBRARY_VERSIONS: string[] =
  ['2.7.7', '5.0.0', '7.0.0', '8.0.0', '9.0.0', '10.0.0', '11.0.0'];

let libraryVersions: string[] = CALL_LIBRARY_VERSIONS;

export function setCallLibraryVersions(versions: string[]): void {
  if (versions.length > 0) {
    libraryVersions = versions;
  }
}

export interface CallSnapshot {
  phase: string; // 'idle' | 'dialing' | 'ringing' | 'connecting' | 'active' | 'ended'
  callId: number;
  peerUserId: number;
  peerName: string;
  isVideo: boolean;
  isOutgoing: boolean;
  muted: boolean;
  speakerOn: boolean;
  localVideoMode: number;
  remoteAudioMuted: boolean;
  remoteVideoActive: boolean;
  emojis: string[];
  startedAtMs: number; // 0 = 未接通
  endReason: string;   // '' | 'hangup' | 'declined' | 'missed' | 'busy' | 'error'
  errorText: string;
}

type CallListener = (s: CallSnapshot) => void;

// 1对1 通话信令状态机：TDLib updateCall 驱动，媒体细节委托 CallMediaBridge。
export class CallSession {
  private client: TdClient;
  private users: UserStore;
  private media: CallMediaBridge;
  private subs: CallListener[] = [];
  private unsubs: Array<() => void> = [];

  private phase: string = 'idle';
  private callId: number = 0;
  private peerUserId: number = 0;
  private isVideo: boolean = false;
  private isOutgoing: boolean = false;
  private muted: boolean = false;
  private speakerOn: boolean = false;
  private localVideoMode: number = CALL_VIDEO_OFF;
  private remoteAudioMuted: boolean = false;
  private remoteVideoActive: boolean = false;
  private emojis: string[] = [];
  private startedAtMs: number = 0;
  private endReason: string = '';
  private errorText: string = '';
  private mediaStarted: boolean = false;

  constructor(client: TdClient, users: UserStore, media: CallMediaBridge) {
    this.client = client;
    this.users = users;
    this.media = media;
    this.unsubs.push(client.onUpdate('updateCall', (u: TdObject) => this.onUpdateCall(u)));
    this.unsubs.push(client.onUpdate('updateNewCallSignalingData',
      (u: TdObject) => this.onSignalingData(u)));
    media.onState = (state: string): void => this.onMediaState(state);
    media.onSignalingData = (dataBase64: string): void => this.onOutboundSignaling(dataBase64);
    media.onRemoteMedia = (audioMuted: boolean, videoActive: boolean): void =>
      this.onRemoteMedia(audioMuted, videoActive);
  }

  // 当前状态快照（供回前台等时机做补偿检查，不必临时订阅）。
  current(): CallSnapshot {
    return this.snapshot();
  }

  subscribe(l: CallListener): () => void {
    this.subs = [...this.subs, l];
    l(this.snapshot());
    return (): void => {
      this.subs = this.subs.filter((x: CallListener) => x !== l);
    };
  }

  startCall(userId: number, isVideo: boolean): void {
    if (this.phase !== 'idle' && this.phase !== 'ended') {
      return; // 已有通话在进行
    }
    this.resetState();
    this.phase = 'dialing';
    this.peerUserId = userId;
    this.isVideo = isVideo;
    this.isOutgoing = true;
    const req: TdRequest = { '@type': 'createCall' };
    req['user_id'] = userId;
    req['protocol'] = this.protocol();
    req['is_video'] = isVideo;
    this.client.send(req).catch((e: TdError): void => {
      logE(`CallSession.createCall failed: ${e.message}`);
      this.endWith('error', e.message);
    });
    this.publish();
  }

  accept(): void {
    if (this.phase !== 'ringing' || this.callId === 0) {
      return;
    }
    const req: TdRequest = { '@type': 'acceptCall' };
    req['call_id'] = this.callId;
    req['protocol'] = this.protocol();
    this.client.send(req).catch((e: TdError): void => {
      logE(`CallSession.acceptCall failed: ${e.message}`);
      this.endWith('error', e.message);
    });
    this.phase = 'connecting';
    this.publish();
  }

  decline(): void {
    if (this.phase !== 'ringing' || this.callId === 0) {
      return;
    }
    this.sendDiscard(this.callId, 0);
    this.endWith('declined', '');
  }

  hangup(): void {
    if (this.callId === 0 || this.phase === 'idle' || this.phase === 'ended') {
      return;
    }
    const duration: number = this.startedAtMs > 0
      ? Math.max(0, Math.round((Date.now() - this.startedAtMs) / 1000)) : 0;
    this.sendDiscard(this.callId, duration);
    this.endWith('hangup', '');
  }

  // 指定静音状态（系统来电界面的静音按钮回传时用，避免与本地状态打架）。
  setMuted(muted: boolean): void {
    if (this.muted === muted) {
      return;
    }
    this.muted = muted;
    this.media.setMuted(muted);
    this.publish();
  }

  toggleMute(): void {
    this.muted = !this.muted;
    this.media.setMuted(this.muted);
    this.publish();
  }

  setVideoMode(mode: number): void {
    this.localVideoMode = mode;
    this.media.setVideo(mode);
    this.publish();
  }

  switchCamera(): void {
    if (this.localVideoMode === CALL_VIDEO_OFF) {
      return;
    }
    this.setVideoMode(this.localVideoMode === 1 ? 2 : 1);
  }

  toggleSpeaker(): void {
    this.speakerOn = !this.speakerOn;
    this.media.setAudioOutput(this.speakerOn);
    this.publish();
  }

  setLocalSurface(surfaceId: string): void {
    this.media.setLocalSurface(surfaceId);
  }

  setRemoteSurface(surfaceId: string): void {
    this.media.setRemoteSurface(surfaceId);
  }

  private protocol(): TdObject {
    const p: TdObject = { '@type': 'callProtocol' };
    p['udp_p2p'] = true;
    p['udp_reflector'] = true;
    p['min_layer'] = CALL_MIN_LAYER;
    p['max_layer'] = CALL_MAX_LAYER;
    p['library_versions'] = libraryVersions;
    return p;
  }

  private sendDiscard(callId: number, duration: number): void {
    const req: TdRequest = { '@type': 'discardCall' };
    req['call_id'] = callId;
    req['is_disconnected'] = false;
    req['duration'] = duration;
    req['is_video'] = this.isVideo;
    this.client.send(req).catch((e: TdError): void => {
      logE(`CallSession.discardCall failed: ${e.message}`);
    });
  }

  private onUpdateCall(u: TdObject): void {
    const call = u['call'] as TdObject | undefined;
    if (call === undefined) {
      return;
    }
    const id: number = (call['id'] as number | undefined) ?? 0;
    const state = call['state'] as TdObject | undefined;
    const stateType: string = state !== undefined
      ? ((state['@type'] as string | undefined) ?? '') : '';
    if (id <= 0 || stateType === '') {
      return;
    }
    const isOutgoing: boolean = (call['is_outgoing'] as boolean | undefined) ?? false;
    // 会话绑定：首个与本机相关的 call 进入跟踪；其余来电忙线拒接。
    if (this.callId === 0 && (this.phase === 'dialing' || this.phase === 'idle' ||
      this.phase === 'ended')) {
      if (stateType === 'callStatePending' && !isOutgoing &&
        (this.phase === 'idle' || this.phase === 'ended')) {
        // 来电
        this.resetState();
        this.callId = id;
        this.peerUserId = (call['user_id'] as number | undefined) ?? 0;
        this.isVideo = (call['is_video'] as boolean | undefined) ?? false;
        this.isOutgoing = false;
        this.phase = 'ringing';
        this.publish();
        return;
      }
      if (isOutgoing && this.phase === 'dialing') {
        this.callId = id; // 拨出回执，继续走下方状态处理
      } else {
        return;
      }
    }
    if (id !== this.callId) {
      // 只有真的在通话流程中才按忙线拒接；空闲/已结束时的不匹配事件
      // 是旧通话的迟到更新，直接忽略（防御：callId 已在 endWith 清零）。
      const inCall: boolean = this.phase === 'dialing' || this.phase === 'ringing' ||
        this.phase === 'connecting' || this.phase === 'active';
      if (inCall && stateType === 'callStatePending' && !isOutgoing) {
        this.sendDiscard(id, 0); // 忙线：拒接第二路来电
      }
      return;
    }
    if (stateType === 'callStatePending') {
      return; // 已在 dialing/ringing
    }
    if (stateType === 'callStateExchangingKeys') {
      if (this.phase === 'dialing' || this.phase === 'ringing') {
        this.phase = 'connecting';
        this.publish();
      }
      return;
    }
    if (stateType === 'callStateReady') {
      this.onReady(state!);
      return;
    }
    if (stateType === 'callStateHangingUp') {
      return; // 过渡态，等 discarded
    }
    if (stateType === 'callStateDiscarded') {
      const reason = state!['reason'] as TdObject | undefined;
      const reasonType: string = reason !== undefined
        ? ((reason['@type'] as string | undefined) ?? '') : '';
      let endReason: string = 'hangup';
      if (reasonType === 'callDiscardReasonDeclined') {
        endReason = 'declined';
      } else if (reasonType === 'callDiscardReasonMissed') {
        endReason = 'missed';
      }
      this.endWith(endReason, '');
      return;
    }
    if (stateType === 'callStateError') {
      const err = state!['error'] as TdObject | undefined;
      const message: string = err !== undefined
        ? ((err['message'] as string | undefined) ?? '') : '';
      this.endWith('error', message !== '' ? message : str('svc_call_failed'));
      return;
    }
  }

  private onReady(state: TdObject): void {
    if (this.mediaStarted) {
      return; // ready 重复推送（如 custom_parameters 更新）不重启媒体
    }
    this.emojis = (state['emojis'] as string[] | undefined) ?? [];
    const key: string = (state['encryption_key'] as string | undefined) ?? '';
    const servers: TdObject[] = (state['servers'] as TdObject[] | undefined) ?? [];
    const readyProtocol = state['protocol'] as TdObject | undefined;
    const remoteVersions: string[] = readyProtocol !== undefined
      ? ((readyProtocol['library_versions'] as string[] | undefined) ?? []) : [];
    const config: CallMediaConfig = {
      encryptionKeyBase64: key,
      isOutgoing: this.isOutgoing,
      serversJson: JSON.stringify(servers),
      isVideo: this.isVideo,
      remoteVersionsJson: JSON.stringify(remoteVersions)
    };
    this.phase = 'connecting';
    this.mediaStarted = true;
    if (!this.media.start(config)) {
      this.sendDiscard(this.callId, 0);
      this.endWith('error', str('svc_media_channel_failed'));
      return;
    }
    if (this.isVideo) {
      this.localVideoMode = 1;
      this.media.setVideo(1);
    }
    this.publish();
  }

  private onSignalingData(u: TdObject): void {
    const callId: number = (u['call_id'] as number | undefined) ?? 0;
    if (callId !== this.callId || this.callId === 0) {
      return;
    }
    const data: string = (u['data'] as string | undefined) ?? '';
    if (data !== '') {
      this.media.receiveSignaling(data);
    }
  }

  private onMediaState(state: string): void {
    if (this.phase === 'ended' || this.phase === 'idle') {
      return;
    }
    if (state === 'ready') {
      if (this.startedAtMs === 0) {
        this.startedAtMs = Date.now();
      }
      this.phase = 'active';
      this.publish();
      return;
    }
    if (state === 'reconnecting' || state === 'connecting') {
      this.phase = 'connecting';
      this.publish();
      return;
    }
    if (state === 'failed') {
      if (this.callId !== 0) {
        const duration: number = this.startedAtMs > 0
          ? Math.max(0, Math.round((Date.now() - this.startedAtMs) / 1000)) : 0;
        const req: TdRequest = { '@type': 'discardCall' };
        req['call_id'] = this.callId;
        req['is_disconnected'] = true;
        req['duration'] = duration;
        req['is_video'] = this.isVideo;
        this.client.send(req).catch((e: TdError): void => {
          logE(`CallSession.discardCall(failed) failed: ${e.message}`);
        });
      }
      this.endWith('error', str('svc_connect_failed'));
    }
  }

  private onOutboundSignaling(dataBase64: string): void {
    if (this.callId === 0) {
      return;
    }
    const req: TdRequest = { '@type': 'sendCallSignalingData' };
    req['call_id'] = this.callId;
    req['data'] = dataBase64;
    this.client.send(req).catch((e: TdError): void => {
      logE(`CallSession.sendCallSignalingData failed: ${e.message}`);
    });
  }

  private onRemoteMedia(audioMuted: boolean, videoActive: boolean): void {
    this.remoteAudioMuted = audioMuted;
    this.remoteVideoActive = videoActive;
    this.publish();
  }

  // 统一 teardown：幂等，可从任意阶段进入。
  private endWith(reason: string, errorText: string): void {
    if (this.phase === 'ended' || this.phase === 'idle') {
      return;
    }
    if (this.mediaStarted) {
      this.media.stop();
      this.mediaStarted = false;
    }
    this.phase = 'ended';
    this.endReason = reason;
    this.errorText = errorText;
    // 立即释放会话绑定：callId 残留会让下一通来电误入忙线分支被自动拒接
    // （已结束通话的迟到事件在 onUpdateCall 里按"非 pending 即忽略"处理）。
    this.callId = 0;
    this.publish();
  }

  private resetState(): void {
    this.phase = 'idle';
    this.callId = 0;
    this.peerUserId = 0;
    this.isVideo = false;
    this.isOutgoing = false;
    this.muted = false;
    this.speakerOn = false;
    this.localVideoMode = CALL_VIDEO_OFF;
    this.remoteAudioMuted = false;
    this.remoteVideoActive = false;
    this.emojis = [];
    this.startedAtMs = 0;
    this.endReason = '';
    this.errorText = '';
    this.mediaStarted = false;
  }

  private snapshot(): CallSnapshot {
    return {
      phase: this.phase,
      callId: this.callId,
      peerUserId: this.peerUserId,
      peerName: this.users.displayName(this.peerUserId),
      isVideo: this.isVideo,
      isOutgoing: this.isOutgoing,
      muted: this.muted,
      speakerOn: this.speakerOn,
      localVideoMode: this.localVideoMode,
      remoteAudioMuted: this.remoteAudioMuted,
      remoteVideoActive: this.remoteVideoActive,
      emojis: this.emojis,
      startedAtMs: this.startedAtMs,
      endReason: this.endReason,
      errorText: this.errorText
    };
  }

  private publish(): void {
    const snap = this.snapshot();
    for (const l of this.subs) {
      l(snap);
    }
  }

  close(): void {
    for (const un of this.unsubs) {
      un();
    }
    this.unsubs = [];
  }
}
