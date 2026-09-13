// 小图同步解码的准入（#137）。
//
// 发送者头像走 CachedImage → pixelCache → taskpool 异步解码，行又不复用（消息重复
// 那个 bug 的代价），于是某个发送者在本次会话里第一次出现时首帧必然是首字母圆底，
// 解码落地才换成照片——翻得越快"第一次"越多，看起来一直在闪。
// 官方对"图片刷新时闪烁"的处方是 Image.syncLoad（同步、阻塞主线程、只建议小图）。
// 我们的对应做法：目标很小（头像 38vp×3 ≈ 114px）就在主线程同步解码，160px 的头像
// JPEG 按 desiredSize 降采样解一次约 1ms；缩略图和大图仍走异步。
export const SYNC_DECODE_MAX_PX: number = 160;

export function syncDecodeEligible(width: number, height: number): boolean {
  return width > 0 && height > 0 && width <= SYNC_DECODE_MAX_PX && height <= SYNC_DECODE_MAX_PX;
}
