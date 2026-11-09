// 1对1 通话媒体桥接口。CallSession（信令状态机）只依赖这个接口：
// 单测注入 fake，真机注入 NativeCallMedia（libtgcalls_ohos.so 的 NAPI 封装）。
export interface CallMediaConfig {
  encryptionKeyBase64: string;
  isOutgoing: boolean;
  serversJson: string; // JSON.stringify(callStateReady.servers)，原生侧解析
  isVideo: boolean;
  // callStateReady.protocol.library_versions（服务端偏好排序），原生据此选协议版本。
  remoteVersionsJson: string;
}

// 视频模式：0=关闭 1=前置 2=后置。
export const CALL_VIDEO_OFF: number = 0;
export const CALL_VIDEO_FRONT: number = 1;
export const CALL_VIDEO_BACK: number = 2;

export interface CallMediaBridge {
  // 返回 false 表示原生会话创建失败（调用方进入 error teardown）。
  start(config: CallMediaConfig): boolean;
  stop(): void;
  receiveSignaling(dataBase64: string): void;
  setMuted(muted: boolean): void;
  setVideo(mode: number): void;
  setAudioOutput(speaker: boolean): void;
  setLocalSurface(surfaceId: string): void;
  setRemoteSurface(surfaceId: string): void;
  // 由实现方在原生事件到达时回调（CallSession 装配这三个钩子）。
  onState: (state: string) => void; // 'connecting' | 'ready' | 'failed' | 'reconnecting'
  onSignalingData: (dataBase64: string) => void;
  onRemoteMedia: (audioMuted: boolean, videoActive: boolean) => void;
}

// 原生桥尚未接入前的占位实现（Globals 在 Task 4 换成 NativeCallMedia）。
export class NullCallMedia implements CallMediaBridge {
  onState: (state: string) => void = (): void => {};
  onSignalingData: (dataBase64: string) => void = (): void => {};
  onRemoteMedia: (audioMuted: boolean, videoActive: boolean) => void = (): void => {};

  start(config: CallMediaConfig): boolean {
    return false;
  }

  stop(): void {}

  receiveSignaling(dataBase64: string): void {}

  setMuted(muted: boolean): void {}

  setVideo(mode: number): void {}

  setAudioOutput(speaker: boolean): void {}

  setLocalSurface(surfaceId: string): void {}

  setRemoteSurface(surfaceId: string): void {}
}
