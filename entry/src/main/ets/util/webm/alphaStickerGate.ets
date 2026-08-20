import { deviceInfo } from '@kit.BasicServicesKit';

// 系统 VP9 解码器（OH_AVCODEC_MIMETYPE_VIDEO_VP9）是 API 23 才有的。
// 低于这个版本，透明贴纸整条新链路都不存在，一律走原来的 ijkplayer。
export const VP9_STICKER_API: number = 23;

export function vp9StickerWinsAt(apiVersion: number): boolean {
  return apiVersion >= VP9_STICKER_API;
}

// deviceInfo 是常量，官方建议只读一次；这个判定又在挂载路径上。
const gateOpen: boolean = vp9StickerWinsAt(deviceInfo.sdkApiVersion);

export function vp9StickerApiAvailable(): boolean {
  return gateOpen;
}

// 带 alpha 的素材只有贴纸和各类表情。GIF、视频本来就不透明，让它们也去试一次
// 自解封装只是白花一次读文件 + 拆包。
export function alphaStickerCandidate(powerCategory: string): boolean {
  return powerCategory === 'sticker' || powerCategory === 'emojiChat'
    || powerCategory === 'emojiPicker' || powerCategory === 'emoji'
    || powerCategory === 'emojiReaction' || powerCategory === 'emojiStatus';
}
