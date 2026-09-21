// 小图同步解码的准入（#137）。
//
// 发送者头像走 CachedImage → pixelCache → taskpool 异步解码，行又不复用（消息重复
// 那个 bug 的代价），于是某个发送者在本次会话里第一次出现时首帧必然是首字母圆底，
// 解码落地才换成照片——翻得越快"第一次"越多，看起来一直在闪。
// 官方对"图片刷新时闪烁"的处方是 Image.syncLoad（同步、阻塞主线程、只建议小图）。
// 我们的对应做法：目标很小（头像 38vp×3 ≈ 114px）就在主线程同步解码，头像 JPEG
// 按 desiredSize 降采样解一次约 1ms；缩略图和大图仍走异步。
//
// 【2026-09-21：160 → 176。差一个像素让整条路白建了】
// 本机 DPR 是 2.875（不是 3.0），会话列表行的 56vp 头像 = 56 × 2.875 = **161px**，
// 比 160 大一个像素，于是 syncDecodeEligible 恒为 false——真机探针里 `sync` 从头到尾
// 是 0，这条为 #137 建的路一次都没走过。
//
// 176 的来历：覆盖 56vp 在本机 2.875x（161）与 3.0x（168）下的两种结果，再留一点
// 余量给别处的 56–58vp 头像；同时**仍然远小于**相册格（~300px）和单张媒体，
// 那两档必须留在异步侧——它们一张 1–2ms 打不住，而且一屏有 6–9 张。
//
// 别再往上抬：每抬一档就是把更大的图拽进主线程，而这里省的只是"首帧是首字母
// 还是照片"，不值得拿滑动掉帧去换。
export const SYNC_DECODE_MAX_PX: number = 176;

export function syncDecodeEligible(width: number, height: number): boolean {
  return width > 0 && height > 0 && width <= SYNC_DECODE_MAX_PX && height <= SYNC_DECODE_MAX_PX;
}
