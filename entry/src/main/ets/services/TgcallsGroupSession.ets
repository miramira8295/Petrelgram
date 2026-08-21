import tgcallsNative from 'libentry.so';
import {
  endGroupCallScreenSharing, getGroupCallStreamSegment, getGroupCallStreams,
  joinVideoChat, startGroupCallScreenSharing, toggleGroupCallIsMyVideoEnabled
} from '../tdkit/GroupCallApi';
import { TdClient } from '../tdkit/TdClient';
import { GroupCallStreamInfo } from '../tdkit/GroupCallTypes';
import { TdRequest } from '../tdkit/TdTypes';
import { parseOptionInteger } from '../store/FolderApi';
import { logE, logI, logW } from '../util/log';

const JOIN_PAYLOAD_TIMEOUT_MS: number = 15000;
const SCREEN_SHARE_JOIN_PAYLOAD_TIMEOUT_MS: number = 15000;
const STREAM_DISCOVERY_ATTEMPTS: number = 5;

interface NativeJoinPayload {
  audioSourceId: number;
  payload: string;
}

export interface TgcallsJoinResult {
  isBroadcast: boolean;
  isUnifiedBroadcast: boolean;
  streams: GroupCallStreamInfo[];
}

interface ParsedJoinResponse {
  isBroadcast: boolean;
  isUnifiedBroadcast: boolean;
}

export type TgcallsNetworkListener = (connected: boolean) => void;
export type TgcallsAudioActivityListener = (audioSourceId: number, speaking: boolean) => void;
export type TgcallsBroadcastStreamsListener = (
  streams: GroupCallStreamInfo[], isUnifiedBroadcast: boolean
) => void;
export type TgcallsBroadcastActivityListener = (received: boolean) => void;
export type TgcallsLocalVideoListener = (
  mode: number, active: boolean, error: number
) => void;
export type TgcallsVideoGeometryListener = (
  endpointId: string, width: number, height: number
) => void;

// Owns one Telegram group-call engine. tgcalls creates the real ICE/DTLS
// credentials consumed by joinVideoChat; fabricated JSON cannot establish a
// group call even when TDLib accepts its shape.
export class TgcallsGroupSession {
  private created: boolean = false;
  private stopped: boolean = false;
  private generation: number = 0;
  private onNetworkState: TgcallsNetworkListener;
  private onAudioActivity: TgcallsAudioActivityListener;
  private onBroadcastStreams: TgcallsBroadcastStreamsListener;
  private onBroadcastActivity: TgcallsBroadcastActivityListener;
  private client: TdClient | null = null;
  private groupCallId: number = 0;
  private broadcastStreams: GroupCallStreamInfo[] = [];
  private isUnifiedBroadcast: boolean = false;
  private serverTimeOffsetMs: number = 0;
  private muted: boolean = true;
  private localVideoMode: number = 0;
  private cameraEnabled: boolean = false;
  private screenShareCreated: boolean = false;
  private screenShareGeneration: number = 0;
  private broadcastConnection: boolean = false;
  private onLocalVideoState: TgcallsLocalVideoListener;
  private onVideoGeometry: TgcallsVideoGeometryListener;

  constructor(
    onNetworkState: TgcallsNetworkListener = (): void => {},
    onAudioActivity: TgcallsAudioActivityListener = (): void => {},
    onBroadcastStreams: TgcallsBroadcastStreamsListener = (): void => {},
    onBroadcastActivity: TgcallsBroadcastActivityListener = (): void => {},
    onLocalVideoState: TgcallsLocalVideoListener = (): void => {},
    onVideoGeometry: TgcallsVideoGeometryListener = (): void => {}
  ) {
    this.onNetworkState = onNetworkState;
    this.onAudioActivity = onAudioActivity;
    this.onBroadcastStreams = onBroadcastStreams;
    this.onBroadcastActivity = onBroadcastActivity;
    this.onLocalVideoState = onLocalVideoState;
    this.onVideoGeometry = onVideoGeometry;
  }

  // Re-targets UI/controller callbacks without recreating the native group-call
  // engine. Live floating uses this only when ownership moves between the full
  // viewer and its overlay; media transport and device state stay intact.
  setListeners(
    onNetworkState: TgcallsNetworkListener = (): void => {},
    onAudioActivity: TgcallsAudioActivityListener = (): void => {},
    onBroadcastStreams: TgcallsBroadcastStreamsListener = (): void => {},
    onBroadcastActivity: TgcallsBroadcastActivityListener = (): void => {},
    onLocalVideoState: TgcallsLocalVideoListener = (): void => {},
    onVideoGeometry: TgcallsVideoGeometryListener = (): void => {}
  ): void {
    this.onNetworkState = onNetworkState;
    this.onAudioActivity = onAudioActivity;
    this.onBroadcastStreams = onBroadcastStreams;
    this.onBroadcastActivity = onBroadcastActivity;
    this.onLocalVideoState = onLocalVideoState;
    this.onVideoGeometry = onVideoGeometry;
  }

  async join(client: TdClient, groupCallId: number, muted: boolean = true): Promise<TgcallsJoinResult> {
    if (this.created || groupCallId <= 0) {
      throw new Error(this.created ? 'tgcalls session already started' : 'invalid group call id');
    }
    this.stopped = false;
    this.client = client;
    this.groupCallId = groupCallId;
    this.broadcastStreams = [];
    this.isUnifiedBroadcast = false;
    this.serverTimeOffsetMs = 0;
    this.muted = muted;
    this.localVideoMode = 0;
    this.cameraEnabled = false;
    this.screenShareCreated = false;
    this.screenShareGeneration += 1;
    this.broadcastConnection = false;
    this.generation += 1;
    const generation = this.generation;
    logI(`[tgcalls] join start gcid=${groupCallId}`);
    tgcallsNative.tgcallsCreate(
      (connected: boolean): void => {
        if (!this.stopped && generation === this.generation) {
          logI(`[tgcalls] network state connected=${connected}`);
          if (connected) { this.resumeMedia(); }
          this.onNetworkState(connected);
        }
      },
      (
        requestId: number, kind: number, timestampMs: number,
        durationMs: number, channelId: number, quality: number
      ): void => {
        this.handleBroadcastRequest(
          generation, requestId, kind, timestampMs, durationMs, channelId, quality
        );
      },
      (audioSourceId: number, speaking: boolean): void => {
        if (!this.stopped && generation === this.generation && audioSourceId !== 0) {
          this.onAudioActivity(audioSourceId, speaking);
        }
      },
      (mode: number, active: boolean, error: number): void => {
        if (this.stopped || generation !== this.generation) { return; }
        if (!active && mode === this.localVideoMode) {
          this.localVideoMode = 0;
        }
        this.onLocalVideoState(mode, active, error);
      },
      (endpointId: string, width: number, height: number): void => {
        if (!this.stopped && generation === this.generation) {
          this.onVideoGeometry(endpointId, width, height);
        }
      }
    );
    this.created = true;
    try {
      const local = await this.emitJoinPayload();
      logI(`[tgcalls] emitJoinPayload ok audioSourceId=${local.audioSourceId} payloadLen=${local.payload.length}`);
      this.ensureCurrent(generation);
      const response = await joinVideoChat(client, groupCallId, local.audioSourceId, local.payload, muted);
      logI(`[tgcalls] joinVideoChat resp len=${response.length} head=${response.substring(0, 100)}`);
      this.ensureCurrent(generation);
      if (response.trim() === '') {
        throw new Error('Telegram returned an empty group-call join response');
      }
      const parsedResponse = this.parseJoinResponse(response);
      logI(
        `[tgcalls] isBroadcast=${parsedResponse.isBroadcast} unified=${parsedResponse.isUnifiedBroadcast}`
      );
      if (parsedResponse.isBroadcast) {
        this.broadcastConnection = true;
        this.isUnifiedBroadcast = parsedResponse.isUnifiedBroadcast;
        await this.getUnixTimeMilliseconds(client);
        this.ensureCurrent(generation);
        const streams = parsedResponse.isUnifiedBroadcast
          ? await this.discoverStreams(client, groupCallId, generation)
          : [];
        this.updateBroadcastStreams(streams);
        // tgcalls' streaming context requests time-aligned OGG parts through
        // the callback registered above, then decodes and A/V-syncs them.
        tgcallsNative.tgcallsSetConnectionMode(2, parsedResponse.isUnifiedBroadcast);
        logI(`[tgcalls] broadcast streams discovered=${streams.length}`);
        this.setMuted(muted);
        return {
          isBroadcast: true,
          isUnifiedBroadcast: parsedResponse.isUnifiedBroadcast,
          streams
        };
      }
      // This order mirrors Telegram Desktop: start RTC transport first, then
      // feed it the server ICE/DTLS response.
      tgcallsNative.tgcallsSetConnectionMode(1, false);
      this.broadcastConnection = false;
      tgcallsNative.tgcallsSetJoinResponse(response);
      this.setMuted(muted);
      logI('[tgcalls] rtc mode set + join response fed; waiting for connection');
      return { isBroadcast: false, isUnifiedBroadcast: false, streams: [] };
    } catch (e) {
      logE(`[tgcalls] join failed: ${e}`);
      this.stop();
      throw new Error(`${e}`);
    }
  }

  setMuted(muted: boolean): boolean {
    if (this.created && !this.stopped) {
      const changed: boolean = tgcallsNative.tgcallsSetMuted(muted);
      if (changed) { this.muted = muted; }
      return changed;
    }
    return false;
  }

  async startCamera(mode: number, width: number = 0, height: number = 0): Promise<boolean> {
    if (!this.created || this.stopped || this.broadcastConnection ||
      (mode !== 1 && mode !== 2) || this.client === null || this.groupCallId <= 0) {
      return false;
    }
    const generation = this.generation;
    const client = this.client;
    const groupCallId = this.groupCallId;
    await toggleGroupCallIsMyVideoEnabled(client, groupCallId, true);
    this.ensureCurrent(generation);
    const changed: boolean = tgcallsNative.tgcallsSetLocalVideo(
      mode, Math.max(0, Math.round(width)), Math.max(0, Math.round(height))
    );
    if (changed) {
      this.cameraEnabled = true;
      this.localVideoMode = mode;
      return true;
    }
    await toggleGroupCallIsMyVideoEnabled(client, groupCallId, false).catch((): void => {});
    return false;
  }

  async stopCamera(): Promise<boolean> {
    if (!this.created || this.stopped) { return false; }
    const wasCameraEnabled = this.cameraEnabled ||
      this.localVideoMode === 1 || this.localVideoMode === 2;
    if (!wasCameraEnabled) { return true; }
    const changed: boolean = tgcallsNative.tgcallsSetLocalVideo(0, 0, 0);
    this.cameraEnabled = false;
    this.localVideoMode = 0;
    if (this.client !== null && this.groupCallId > 0) {
      await toggleGroupCallIsMyVideoEnabled(
        this.client, this.groupCallId, false
      );
    }
    return changed;
  }

  async startScreenSharing(width: number, height: number): Promise<boolean> {
    if (!this.created || this.stopped || this.broadcastConnection ||
      this.client === null || this.groupCallId <= 0) {
      return false;
    }
    if (this.screenShareCreated) {
      await this.stopScreenSharing();
    }

    const client = this.client;
    const groupCallId = this.groupCallId;
    const mainGeneration = this.generation;
    const screenGeneration = ++this.screenShareGeneration;
    let announcedToTelegram = false;
    try {
      tgcallsNative.tgcallsScreenShareCreate(
        (connected: boolean): void => {
          if (this.stopped || mainGeneration !== this.generation ||
            screenGeneration !== this.screenShareGeneration) {
            return;
          }
          logI(`[tgcalls] screen-sharing network connected=${connected}`);
        },
        (mode: number, active: boolean, error: number): void => {
          if (this.stopped || mainGeneration !== this.generation ||
            screenGeneration !== this.screenShareGeneration) {
            return;
          }
          this.onLocalVideoState(mode, active, error);
        },
        Math.max(2, Math.round(width)),
        Math.max(2, Math.round(height))
      );
      this.screenShareCreated = true;
      const local = await this.emitScreenShareJoinPayload(screenGeneration);
      this.ensureCurrent(mainGeneration);
      this.ensureScreenCurrent(screenGeneration);
      const response = await startGroupCallScreenSharing(
        client, groupCallId, local.audioSourceId, local.payload
      );
      announcedToTelegram = true;
      this.ensureCurrent(mainGeneration);
      this.ensureScreenCurrent(screenGeneration);
      if (response.trim() === '') {
        throw new Error('Telegram returned an empty screen-sharing join response');
      }
      tgcallsNative.tgcallsScreenShareSetConnectionMode();
      tgcallsNative.tgcallsScreenShareSetJoinResponse(response);
      logI(
        `[tgcalls] screen-sharing joined audioSourceId=${local.audioSourceId} payloadLen=${local.payload.length}`
      );
      return true;
    } catch (caught) {
      if (screenGeneration === this.screenShareGeneration) {
        this.screenShareGeneration += 1;
        this.screenShareCreated = false;
        tgcallsNative.tgcallsScreenShareDestroy();
      }
      if (announcedToTelegram) {
        await endGroupCallScreenSharing(client, groupCallId).catch((): void => {});
      }
      throw new Error(`${caught}`);
    }
  }

  async stopScreenSharing(): Promise<boolean> {
    if (!this.screenShareCreated) { return true; }
    this.screenShareGeneration += 1;
    this.screenShareCreated = false;
    tgcallsNative.tgcallsScreenShareDestroy();
    if (this.client !== null && this.groupCallId > 0) {
      await endGroupCallScreenSharing(this.client, this.groupCallId);
    }
    return true;
  }

  resumeMedia(): void {
    if (this.created && !this.stopped) {
      tgcallsNative.tgcallsResumeMedia();
      // The recorder can be paused independently from the WebRTC transport.
      // Re-applying the desired mute state restarts it only when needed.
      tgcallsNative.tgcallsSetMuted(this.muted);
    }
  }

  setVideoSurface(endpointId: string, surfaceId: string, surfaceWidth: number = 0, surfaceHeight: number = 0): void {
    if (this.created && !this.stopped && endpointId !== '') {
      tgcallsNative.tgcallsSetVideoSurface(endpointId, surfaceId, surfaceWidth, surfaceHeight);
    }
  }

  setLocalVideoSurface(
    surfaceId: string, surfaceWidth: number = 0, surfaceHeight: number = 0
  ): void {
    if (this.created && !this.stopped) {
      tgcallsNative.tgcallsSetLocalVideoSurface(
        surfaceId, Math.max(0, Math.round(surfaceWidth)),
        Math.max(0, Math.round(surfaceHeight))
      );
    }
  }

  // ssrcGroups encoded as "semantics=ssrc,ssrc;semantics=ssrc,...".
  setVideoChannel(endpointId: string, audioSsrc: number, ssrcGroups: string): void {
    if (this.created && !this.stopped && endpointId !== '') {
      tgcallsNative.tgcallsSetVideoChannel(endpointId, audioSsrc, ssrcGroups);
    }
  }

  removeVideoChannel(endpointId: string): void {
    if (this.created && !this.stopped && endpointId !== '') {
      tgcallsNative.tgcallsRemoveVideoChannel(endpointId);
    }
  }

  clearVideo(): void {
    if (this.created && !this.stopped) {
      tgcallsNative.tgcallsClearVideo();
    }
  }

  stop(): void {
    if (this.stopped) { return; }
    const client = this.client;
    const groupCallId = this.groupCallId;
    const cameraEnabled = this.cameraEnabled;
    const screenShareCreated = this.screenShareCreated;
    this.stopped = true;
    this.generation += 1;
    this.screenShareGeneration += 1;
    if (screenShareCreated) {
      tgcallsNative.tgcallsScreenShareDestroy();
      if (client !== null && groupCallId > 0) {
        endGroupCallScreenSharing(client, groupCallId).catch((caught: Error): void => {
          logW(`[tgcalls] end screen sharing during stop failed: ${caught.message}`);
        });
      }
    }
    if (cameraEnabled && this.created) {
      tgcallsNative.tgcallsSetLocalVideo(0, 0, 0);
      if (client !== null && groupCallId > 0) {
        toggleGroupCallIsMyVideoEnabled(
          client, groupCallId, false
        ).catch((caught: Error): void => {
          logW(`[tgcalls] disable camera during stop failed: ${caught.message}`);
        });
      }
    }
    if (this.created) {
      tgcallsNative.tgcallsDestroy();
      this.created = false;
    }
    this.client = null;
    this.groupCallId = 0;
    this.broadcastStreams = [];
    this.isUnifiedBroadcast = false;
    this.serverTimeOffsetMs = 0;
    this.localVideoMode = 0;
    this.cameraEnabled = false;
    this.screenShareCreated = false;
    this.broadcastConnection = false;
  }

  private emitJoinPayload(): Promise<NativeJoinPayload> {
    return new Promise<NativeJoinPayload>((resolve, reject) => {
      let finished = false;
      const timeoutId = setTimeout((): void => {
        if (finished) { return; }
        finished = true;
        reject(new Error('timed out while generating tgcalls join payload'));
      }, JOIN_PAYLOAD_TIMEOUT_MS);
      tgcallsNative.tgcallsEmitJoinPayload((audioSourceId: number, payload: string): void => {
        if (finished) { return; }
        finished = true;
        clearTimeout(timeoutId);
        if (audioSourceId === 0 || payload.trim() === '') {
          reject(new Error('tgcalls generated an invalid join payload'));
          return;
        }
        resolve({ audioSourceId, payload });
      });
    });
  }

  private emitScreenShareJoinPayload(
    screenGeneration: number
  ): Promise<NativeJoinPayload> {
    return new Promise<NativeJoinPayload>((resolve, reject) => {
      let finished = false;
      const timeoutId = setTimeout((): void => {
        if (finished) { return; }
        finished = true;
        reject(new Error('timed out while generating screen-sharing join payload'));
      }, SCREEN_SHARE_JOIN_PAYLOAD_TIMEOUT_MS);
      tgcallsNative.tgcallsScreenShareEmitJoinPayload(
        (audioSourceId: number, payload: string): void => {
          if (finished) { return; }
          finished = true;
          clearTimeout(timeoutId);
          if (screenGeneration !== this.screenShareGeneration) {
            reject(new Error('screen-sharing session stopped'));
            return;
          }
          if (audioSourceId === 0 || payload.trim() === '') {
            reject(new Error('tgcalls generated an invalid screen-sharing join payload'));
            return;
          }
          resolve({ audioSourceId, payload });
        }
      );
    });
  }

  private parseJoinResponse(response: string): ParsedJoinResponse {
    try {
      const parsed = JSON.parse(response) as Record<string, Object>;
      return {
        isBroadcast: (parsed['stream'] as boolean | undefined) ?? false,
        isUnifiedBroadcast: (parsed['rtmp'] as boolean | undefined) ?? false
      };
    } catch (e) {
      throw new Error(`invalid group-call join response: ${e}`);
    }
  }

  private async discoverStreams(
    client: TdClient, groupCallId: number, generation: number
  ): Promise<GroupCallStreamInfo[]> {
    let lastError: Error | null = null;
    for (let attempt = 0; attempt < STREAM_DISCOVERY_ATTEMPTS; attempt++) {
      this.ensureCurrent(generation);
      try {
        const streams = await getGroupCallStreams(client, groupCallId);
        if (streams.length > 0) { return streams; }
      } catch (e) {
        lastError = e as Error;
      }
      await new Promise<void>((resolve) => setTimeout(resolve, 300 * (attempt + 1)));
    }
    if (lastError !== null) {
      logW(`[tgcalls] initial broadcast stream discovery failed: ${lastError.message}`);
    }
    // An RTMP publisher may not have started yet. Joining still succeeds;
    // tgcalls will request time again once per second until channels appear.
    return [];
  }

  private async handleBroadcastRequest(
    generation: number, requestId: number, kind: number, timestampMs: number,
    durationMs: number, channelId: number, quality: number
  ): Promise<void> {
    const client = this.client;
    const groupCallId = this.groupCallId;
    if (client === null || groupCallId <= 0 || this.stopped || generation !== this.generation) { return; }
    try {
      if (kind === 0) {
        let currentTime = 0;
        if (this.isUnifiedBroadcast) {
          const streams = await getGroupCallStreams(client, groupCallId);
          if (streams.length > 0) {
            this.updateBroadcastStreams(streams);
          }
          for (const stream of streams) {
            if (stream.timeOffset > currentTime) { currentTime = stream.timeOffset; }
          }
        } else {
          currentTime = await this.getUnixTimeMilliseconds(client);
        }
        if (this.stopped || generation !== this.generation) { return; }
        tgcallsNative.tgcallsCompleteBroadcastTime(requestId, currentTime);
        return;
      }
      let streams = this.broadcastStreams;
      if (streams.length === 0) {
        streams = await getGroupCallStreams(client, groupCallId);
        this.updateBroadcastStreams(streams);
        if (streams.length > 0) {
          streams = this.broadcastStreams;
        }
      }
      if (this.stopped || generation !== this.generation) { return; }
      let scale = streams.length > 0 ? streams[0].scale : 0;
      for (const stream of streams) {
        if (stream.channelId === channelId) {
          scale = stream.scale;
          break;
        }
      }
      const qualityType = kind === 1 ? '' : (quality >= 2
        ? 'groupCallVideoQualityFull'
        : (quality === 1 ? 'groupCallVideoQualityMedium' : 'groupCallVideoQualityThumbnail'));
      const bytes = await getGroupCallStreamSegment(
        client, groupCallId, timestampMs, scale, channelId, qualityType
      );
      if (this.stopped || generation !== this.generation) { return; }
      const status = bytes.length > 0 ? 0 : 1;
      this.onBroadcastActivity(status === 0);
      tgcallsNative.tgcallsCompleteBroadcastPart(
        requestId, timestampMs, status, this.approximateServerTimeSeconds(), bytes
      );
    } catch (caught) {
      if (this.stopped || generation !== this.generation) { return; }
      const error = caught as Error;
      const upper = error.message.toUpperCase();
      const status = upper.includes('TIME_TOO_SMALL') || upper.includes('RESYNC') || upper.includes('OFFSET_INVALID')
        ? 2 : 1;
      logE(
        `[tgcalls] broadcast request failed kind=${kind} ts=${timestampMs} duration=${durationMs} ` +
        `channel=${channelId}: ${error.message}`
      );
      this.onBroadcastActivity(false);
      if (kind === 0) {
        tgcallsNative.tgcallsCompleteBroadcastTime(requestId, 0);
        return;
      }
      tgcallsNative.tgcallsCompleteBroadcastPart(
        requestId, timestampMs, status, this.approximateServerTimeSeconds(), new Uint8Array(0)
      );
    }
  }

  private async getUnixTimeMilliseconds(client: TdClient): Promise<number> {
    const request: TdRequest = { '@type': 'getOption' };
    request['name'] = 'unix_time';
    const response = await client.send(request);
    // unix_time 同样是 int64 → JSON 字符串，直接当 number 会恒为 0，
    // 导致服务端时间偏移算不出来。
    const seconds = parseOptionInteger(response['value'], 0);
    if (seconds <= 0) { return 0; }
    const milliseconds = seconds * 1000;
    this.serverTimeOffsetMs = milliseconds - Date.now();
    return milliseconds;
  }

  private updateBroadcastStreams(streams: GroupCallStreamInfo[]): void {
    const before = this.broadcastStreams.map(
      (stream: GroupCallStreamInfo): string => `${stream.channelId}:${stream.scale}`
    ).join(',');
    const after = streams.map(
      (stream: GroupCallStreamInfo): string => `${stream.channelId}:${stream.scale}`
    ).join(',');
    this.broadcastStreams = streams;
    if (before !== after) {
      this.onBroadcastStreams(streams, this.isUnifiedBroadcast);
    }
  }

  private approximateServerTimeSeconds(): number {
    return (Date.now() + this.serverTimeOffsetMs) / 1000;
  }

  private ensureCurrent(generation: number): void {
    if (this.stopped || generation !== this.generation) {
      throw new Error('tgcalls session stopped');
    }
  }

  private ensureScreenCurrent(generation: number): void {
    if (!this.screenShareCreated || generation !== this.screenShareGeneration) {
      throw new Error('screen-sharing session stopped');
    }
  }
}
