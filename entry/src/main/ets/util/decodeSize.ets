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
const DECODE_DOWNSCALE_MIN: number = 2;

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
  // 缩得不够多，不值得拿画质换。
  if (scale > 1 / DECODE_DOWNSCALE_MIN) {
    return undefined;
  }
  return {
    width: Math.max(1, Math.round(srcW * scale)),
    height: Math.max(1, Math.round(srcH * scale))
  };
}
