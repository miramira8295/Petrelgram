import tgcallsNative from 'libentry.so';
import { CallMediaBridge, CallMediaConfig } from './CallMediaBridge';
import { logE } from '../util/log';

// 原生 state int → CallMediaBridge 状态字符串（见 Index.d.ts callCreate 注释）。
function mapNativeState(state: number): string {
  if (state === 1) {
    return 'ready';
  }
  if (state === 2) {
    return 'failed';
  }
  if (state === 3) {
    return 'reconnecting';
  }
  return 'connecting';
}

// CallMediaBridge 的真实实现：libtgcalls_ohos.so 的 1:1 会话（NAPI 封装）。
export class NativeCallMedia implements CallMediaBridge {
  onState: (state: string) => void = (): void => {};
  onSignalingData: (dataBase64: string) => void = (): void => {};
  onRemoteMedia: (audioMuted: boolean, videoActive: boolean) => void = (): void => {};
  private active: boolean = false;

  start(config: CallMediaConfig): boolean {
    if (this.active) {
      logE('NativeCallMedia.start: session already active');
      return false;
    }
    try {
      const ok: boolean = tgcallsNative.callCreate(
        config.encryptionKeyBase64, config.isOutgoing, config.serversJson,
        config.isVideo, config.remoteVersionsJson,
        (state: number): void => { this.onState(mapNativeState(state)); },
        (dataBase64: string): void => { this.onSignalingData(dataBase64); },
        (audioMuted: boolean, videoActive: boolean): void => {
          this.onRemoteMedia(audioMuted, videoActive);
        });
      this.active = ok;
      return ok;
    } catch (e) {
      logE(`NativeCallMedia.start failed: ${(e as Error).message}`);
      return false;
    }
  }

  stop(): void {
    if (!this.active) {
      return;
    }
    this.active = false;
    try {
      tgcallsNative.callDestroy();
    } catch (e) {
      logE(`NativeCallMedia.stop failed: ${(e as Error).message}`);
    }
  }

  receiveSignaling(dataBase64: string): void {
    if (this.active) {
      tgcallsNative.callReceiveSignaling(dataBase64);
    }
  }

  setMuted(muted: boolean): void {
    if (this.active) {
      tgcallsNative.callSetMuted(muted);
    }
  }

  setVideo(mode: number): void {
    if (this.active) {
      tgcallsNative.callSetVideo(mode);
    }
  }

  setAudioOutput(speaker: boolean): void {
    if (this.active) {
      tgcallsNative.callSetAudioOutput(speaker);
    }
  }

  setLocalSurface(surfaceId: string): void {
    if (this.active) {
      tgcallsNative.callSetLocalVideoSurface(surfaceId);
    }
  }

  setRemoteSurface(surfaceId: string): void {
    if (this.active) {
      tgcallsNative.callSetRemoteVideoSurface(surfaceId);
    }
  }
}

// 原生库注册的协议版本（JSON 数组）；异常时返回空数组字符串。
export function nativeCallVersionsJson(): string {
  try {
    return tgcallsNative.callVersions();
  } catch (e) {
    logE(`nativeCallVersionsJson failed: ${(e as Error).message}`);
    return '[]';
  }
}
