// 下载中心视频的首帧海报：签名与路径（纯逻辑，有单测）。
//
// 【为什么要自己生成】用户 2026-09-16 报「视频不显示缩略图」。DC 条目模型里**没有**
// 缩略图来源：`preview` 是来源消息的摘要文本；磁盘扫出来的条目连 fileId 都是 0
// （TDLib 没有「路径 → fileId」的接口），所以 mediaThumbChannel 那条通道也够不着。
// 唯一能用的是本地文件自己 —— util/livePhotoSave 里现成的 extractFirstFrame 抽首帧。
//
// 【文件名完全由签名决定】抽帧是解码，贵。签名定名之后，上次启动写下的那张这次
// 直接命中磁盘，不用再解一遍（配方与 util/chatBackgroundRaster 的 rasterPathFor 一致）。
//
// 磁盘那一半（内存表、通道、串行抽帧队列）在 util/videoPosterStore —— 本文件被单测
// 直接引用，不能把 @kit.CoreFileKit 拖进宿主测试包。

import { DC_KIND_VIDEO, DC_STATE_COMPLETE } from './downloadCenterModel';

export const VIDEO_POSTER_DIR: string = 'vposter';

// djb2 → base36。**不用 crypto**：这只是缓存键，要的是稳定 + 文件名安全，
// 不是抗碰撞强度；而签名里还带着大小与修改时间，撞上的概率可以忽略。
function hashString(input: string): string {
  let h: number = 5381;
  for (let i = 0; i < input.length; i++) {
    // |0 保持 32 位，否则长路径会滑进浮点、不同路径算出同一个值。
    h = ((h * 33) ^ input.charCodeAt(i)) | 0;
  }
  return Math.abs(h).toString(36);
}

// 同名不同内容（重新下载、被覆盖）必须换一张海报，所以大小与修改时间都进签名。
export function posterSignature(path: string, size: number, mtimeMs: number): string {
  const s: number = Math.max(0, Math.floor(size));
  const m: number = Math.max(0, Math.floor(mtimeMs));
  return `${hashString(path)}_${s}_${m}`;
}

export function posterPathFor(cacheDir: string, sig: string): string {
  return `${cacheDir}/${VIDEO_POSTER_DIR}/${sig}.jpg`;
}

// 只给「完整的本地视频」抽帧：没下完的抽不出首帧；图片自己就是自己的缩略图。
export function posterEligible(kind: string, state: string, path: string): boolean {
  return kind === DC_KIND_VIDEO && state === DC_STATE_COMPLETE && path !== '';
}
