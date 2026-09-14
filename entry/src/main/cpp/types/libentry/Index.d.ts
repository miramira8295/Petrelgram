import { image } from '@kit.ImageKit';

export const tdInit: (onReceive: (json: string) => void) => void;
export const tdSend: (json: string) => void;
export const tdExecute: (json: string) => string;
export const tdDestroy: () => void;
export const tgcallsCreate: (
  onState: (connected: boolean) => void,
  onBroadcastRequest: (
    requestId: number, kind: number, timestampMs: number,
    durationMs: number, channelId: number, quality: number
  ) => void,
  onAudioActivity: (audioSourceId: number, speaking: boolean) => void,
  onLocalVideoState: (mode: number, active: boolean, error: number) => void,
  onVideoGeometry: (endpointId: string, width: number, height: number) => void
) => boolean;
export const tgcallsEmitJoinPayload: (onPayload: (audioSourceId: number, payload: string) => void) => void;
export const tgcallsSetJoinResponse: (payload: string) => void;
export const tgcallsSetConnectionMode: (mode: number, isUnifiedBroadcast: boolean) => void;
export const tgcallsScreenShareCreate: (
  onState: (connected: boolean) => void,
  onLocalVideoState: (mode: number, active: boolean, error: number) => void,
  width: number,
  height: number
) => boolean;
export const tgcallsScreenShareEmitJoinPayload: (
  onPayload: (audioSourceId: number, payload: string) => void
) => void;
export const tgcallsScreenShareSetJoinResponse: (payload: string) => void;
export const tgcallsScreenShareSetConnectionMode: () => void;
export const tgcallsScreenShareDestroy: () => void;
export const tgcallsCompleteBroadcastTime: (requestId: number, timestampMs: number) => void;
export const tgcallsCompleteBroadcastPart: (
  requestId: number, timestampMs: number, status: number,
  responseTimestamp: number, data: Uint8Array
) => void;
export const tgcallsSetMuted: (muted: boolean) => boolean;
// mode: 0=off, 1=front camera, 2=back camera, 3=screen capture.
export const tgcallsSetLocalVideo: (mode: number, width: number, height: number) => boolean;
export const tgcallsSetLocalVideoSurface: (
  surfaceId: string, surfaceWidth: number, surfaceHeight: number
) => void;
export const tgcallsResumeMedia: () => void;
export const tgcallsSetVideoSurface: (
  endpointId: string, surfaceId: string, surfaceWidth: number, surfaceHeight: number
) => void;
export const tgcallsSetVideoChannel: (endpointId: string, audioSsrc: number, ssrcGroups: string) => void;
export const tgcallsRemoveVideoChannel: (endpointId: string) => void;
export const tgcallsClearVideo: () => void;
export const tgcallsDestroy: () => void;

// --- 1对1 通话（tgcalls Instance/InstanceV2） ---
// state: 0=connecting 1=ready 2=failed 3=reconnecting
export const callCreate: (
  encryptionKeyBase64: string, isOutgoing: boolean, serversJson: string, isVideo: boolean,
  remoteVersionsJson: string,
  onState: (state: number) => void,
  onSignalingData: (dataBase64: string) => void,
  onRemoteMedia: (audioMuted: boolean, videoActive: boolean) => void
) => boolean;
export const callDestroy: () => void;
export const callReceiveSignaling: (dataBase64: string) => void;
export const callSetMuted: (muted: boolean) => void;
// mode: 0=off, 1=front camera, 2=back camera.
export const callSetVideo: (mode: number) => void;
export const callSetAudioOutput: (speaker: boolean) => void;
export const callSetLocalVideoSurface: (surfaceId: string) => void;
export const callSetRemoteVideoSurface: (surfaceId: string) => void;
export const callVersions: () => string;

// --- 透明 webm 贴纸（VP9 + BlockAdditional alpha） ---
// 设备有没有系统 VP9 解码器。系统 VP9 是 API 23 起才有的能力。
export const webmAlphaAvailable: () => boolean;
// 两路 VP9 码流 -> 一串 PixelMap（非预乘 RGBA，已缩到 dstW x dstH）。
// 码流按"拼接字节 + int32 长度表"两块 ArrayBuffer 传，只跨一次 NAPI。
// frameStep 是保留步长：VP9 帧间预测，包必须全喂，只是解出来每 step 帧留一帧。
// 失败时 resolve 成空数组，调用方据此回退到 ijkplayer。
// cachePath 非空时，解出来的帧会压成一份磁盘缓存（zlib，见
// cpp/sticker_frame_cache.cpp）；timesMs 是每帧呈现时刻的 Int32 缓冲，要一并
// 写进缓存头——命中缓存那条路没有拆包过程，时间戳只能从缓存里取。
export const webmAlphaDecode: (
  colorData: ArrayBuffer, colorLengths: ArrayBuffer,
  alphaData: ArrayBuffer, alphaLengths: ArrayBuffer,
  srcWidth: number, srcHeight: number, dstWidth: number, dstHeight: number,
  frameStep: number, cachePath: string, timesMs: ArrayBuffer, durationMs: number
) => Promise<image.PixelMap[]>;

// 读一份磁盘帧缓存。没有 / 坏了 / 解出来超过 maxBytes 都 resolve null，
// 调用方照常去解码。
export const stickerFramesLoad: (cachePath: string, maxBytes: number) => Promise<{
  frames: image.PixelMap[];
  timesMs: number[];
  width: number;
  height: number;
  durationMs: number;
} | null>;

// --- TGS 贴纸的原生渲染（rlottie） ---
//
// 为什么不继续用 @ohos/lottie：它的 renderer 只能是 'canvas'，每帧在 UI 线程上
// 重算形状再画一遍——会话同时只允许 4 张动起来、面板 14 张，超出的是静态图。
// 这里改成 native 按帧渲染：UI 线程只负责把一张已经渲好的 PixelMap 画出去。
//
// 打开一个 .tgs（读文件 + gunzip + 解析 JSON 全在 worker 上）。
// width/height 是**渲染尺寸**，内存按它的平方走，不要传贴纸原生的 512。
// 失败返回 null。
export const tgsOpen: (path: string, width: number, height: number) => Promise<{
  handle: number;
  totalFrames: number;
  frameRate: number;
  width: number;
  height: number;
} | null>;

// 渲染第 frameIndex 帧（越界自动取模）。失败返回 null。
export const tgsRenderFrame: (handle: number, frameIndex: number) => Promise<image.PixelMap | null>;

// 关掉。**必须配对调用**，否则解析后的模型会一直留在 native。
export const tgsClose: (handle: number) => void;

// 还开着几个（诊断用）。
export const tgsOpenCount: () => number;
