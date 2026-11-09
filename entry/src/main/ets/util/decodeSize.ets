// 解码目标尺寸的取舍：什么时候值得让解码器缩，什么时候该原样解出来。

// 只有源图比目标大到这个倍数以上，才交给解码器缩。
//
// **为什么要有下限。** desiredSize 是在解码阶段重采样的，ImageKit 那一步的
// 采样质量远不如渲染阶段的 ImageInterpolation.High。对一张 1280px 的照片缩到
// 225px，省下的内存和解码时间远大于画质损失，值得；但对一张 160px 的头像缩到
// 130px，省不下什么，换来的是**斜边一格一格的锯齿**——用户拿官方客户端对比过
// 头像里那架纸飞机的斜边（issue #92）。
//
// 2 这个值：源图不到目标两倍时原样解出来，让 Image 带着 interpolation(High)
// 去做最后那一点缩放；超过两倍才让解码器接手，那时省下的像素是数量级的。
const DECODE_DOWNSCALE_MIN_SMALL: number = 2;

// **但这条门槛只对小图（头像那一档）成立。**
//
// 2026-09-20 真机实测：会话里往上翻 220 行历史，15 秒解出 216 张图，其中
// 67 次是「解过、被挤出缓存、又解一次」——每一次重解都是用户看到的图片闪一下
// （issue #137 / #140 的同一面，相册尤其明显因为一条消息就 6–9 张）。
//
// 根因是这条 2 倍门槛：相册格子目标约 273×420 px，而 Telegram 的缩略图源常见
// 320–800 px，绝大多数落在 1×–2× 这个区间 → 一律「原样解码」→ 每张按**源分辨率**
// 占内存，而不是按显示尺寸。48 MiB 的图片预算（NativePixelBudget）被刷两遍。
//
// 对大目标把门槛降到 1.2：这一档的图本来就要被 ImageFit.Cover 裁掉一部分，
// 轻微的采样差异看不出来，而省下的内存是成倍的。头像那一档保持 2 倍不动——
// #92 那圈斜边锯齿是拿官方客户端逐像素比出来的，不能为了内存回退。
const DECODE_DOWNSCALE_MIN_LARGE: number = 1.2;

// 「小图」的边界。**不能用 pixelSyncPolicy 的 160**：那条线划的是「值不值得
// 在主线程同步解」，而这里划的是「缩放会不会看出锯齿」，两件事。
//
// 200 的来历：会话行宽松档的头像是 56vp，3 倍屏上 168 px —— 160 会把它误判成
// 大图而降采样，正好踩回 #92 那圈斜边锯齿。取 200 把所有列表头像都圈在小图这边，
// 而相册格子（91vp × 3 ≈ 273 px）和单张媒体都在另一边。
const SMALL_TARGET_MAX_PX: number = 200;

function downscaleMin(targetW: number, targetH: number): number {
  return targetW <= SMALL_TARGET_MAX_PX && targetH <= SMALL_TARGET_MAX_PX
    ? DECODE_DOWNSCALE_MIN_SMALL : DECODE_DOWNSCALE_MIN_LARGE;
}

export interface DecodeSize {
  width: number;
  height: number;
}

// 解码时该给的 desiredSize；undefined 表示"别设，原样解码"。
//
// 缩放比取两个维度里**大**的那个（不是小的）：结果要能盖住目标框，剩下的由
// ImageFit.Cover 裁掉。取小的那个会让图片在某一维上不够、Cover 只能拉伸。
export function decodeDesiredSize(
  srcW: number, srcH: number, targetW: number, targetH: number
): DecodeSize | undefined {
  if (!(srcW > 0) || !(srcH > 0) || !(targetW > 0) || !(targetH > 0)) {
    return undefined;
  }
  const scale: number = Math.max(targetW / srcW, targetH / srcH);
  // 源图本来就不比目标大：放大没有意义，原样解出来最清楚。
  if (scale >= 1) {
    return undefined;
  }
  // 缩得不够多，不值得拿画质换。门槛按目标大小分两档（见上面的说明）。
  if (scale > 1 / downscaleMin(targetW, targetH)) {
    return undefined;
  }
  return {
    width: Math.max(1, Math.round(srcW * scale)),
    height: Math.max(1, Math.round(srcH * scale))
  };
}
