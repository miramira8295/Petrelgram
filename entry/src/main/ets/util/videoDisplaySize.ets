// 视频「容器里的宽高」→「真正显示出来的宽高」。
//
// 【为什么需要它】mp4 容器存的是**旋转前**的宽高，外加一个旋转角。竖着拍的
// 视频在容器里是 1920×1080 + rotation=90，真正显示是 1080×1920。
//
// TDLib 的 inputMessageVideo.width/height 要的是**显示尺寸**——填错了接收端就
// 按错误的比例排版（用户报过「打开后也是横向的 90 度旋转了」）。实况照片这条路
// 上原来是拿**静图**的宽高去顶这个位置：静图确实是旋转后的真实朝向，但它的
// **分辨率是全传感器的几千万像素**，而动态部分只有 1080p 级别。于是我们告诉
// 接收端「这段视频有 4096×3072」，它就把 1080p 放大铺开——正是用户报的
// 「保存的动态图片分辨率会降低，特模糊，感觉不是同一个图片一样」（issue #193）。
//
// 所以要的是「视频自己的分辨率 + 正确的朝向」，两者都要，这个函数负责后半。

export interface DisplaySize {
  width: number;
  height: number;
}

export const NO_DISPLAY_SIZE: DisplaySize = { width: 0, height: 0 };

// 旋转角归一到 [0, 360)。容器里可能是 -90，也可能是 450。
export function normalizeRotation(degrees: number): number {
  if (!Number.isFinite(degrees)) {
    return 0;
  }
  const wrapped: number = Math.round(degrees) % 360;
  return wrapped < 0 ? wrapped + 360 : wrapped;
}

// 90 / 270 度要把宽高对调；0 / 180 原样。
// 非直角的旋转角（理论上存在、实际几乎见不到）按最近的直角判定：只有
// "要不要对调"这一个决定，没有中间态。
export function swapsAxes(degrees: number): boolean {
  const r: number = normalizeRotation(degrees);
  return r >= 45 && r < 135 || r >= 225 && r < 315;
}

// 显示尺寸。任一边非正就返回 NO_DISPLAY_SIZE——调用方据此退回旧行为，
// 而不是把 0 填进协议字段（那会让接收端按容器原始值排版，等于没修）。
export function videoDisplaySize(
  containerWidth: number, containerHeight: number, rotationDegrees: number
): DisplaySize {
  if (!(containerWidth > 0) || !(containerHeight > 0)) {
    return NO_DISPLAY_SIZE;
  }
  const w: number = Math.round(containerWidth);
  const h: number = Math.round(containerHeight);
  return swapsAxes(rotationDegrees) ? { width: h, height: w } : { width: w, height: h };
}
