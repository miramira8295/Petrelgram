// 进程内两套 PixelMap 缓存共用的预算表。
//
// 之前普通图片 64MiB、透明贴纸 56MiB，各自都没超自己的线，但合起来 120MiB，
// 已高于设备采样里 100MiB 的 NativeBinding 警戒线。这里把总上限压到 80MiB，
// 并给生命周期/低内存回调提供同一套收缩目标。

const MIB: number = 1024 * 1024;

export const IMAGE_PIXEL_CACHE_MAX_BYTES: number = 48 * MIB;
export const ALPHA_STICKER_CACHE_MAX_BYTES: number = 32 * MIB;
export const NATIVE_PIXEL_CACHE_MAX_BYTES: number =
  IMAGE_PIXEL_CACHE_MAX_BYTES + ALPHA_STICKER_CACHE_MAX_BYTES;
// Upper bound for component-holder PixelMap releases in one event-loop turn.
// Keeping this next to the byte budgets makes both native-memory limits explicit
// and host-testable without loading ImageKit.
export const IMAGE_HOLDER_RELEASE_BATCH: number = 3;

export interface NativePixelBudget {
  imageBytes: number;
  alphaBytes: number;
}

export function fullNativePixelBudget(): NativePixelBudget {
  return {
    imageBytes: IMAGE_PIXEL_CACHE_MAX_BYTES,
    alphaBytes: ALPHA_STICKER_CACHE_MAX_BYTES
  };
}

// MemoryLevel 数值来自 AbilityConstant.MemoryLevel：0 适中、1 低、2 极低；
// API 24 新增的 3..6 都只会发给后台/UI 已隐藏的应用。这里保持纯函数，主机单测
// 不需要加载 AbilityKit。
export function pressuredNativePixelBudget(level: number, appForeground: boolean): NativePixelBudget {
  if (!appForeground || level >= 2) {
    return { imageBytes: 0, alphaBytes: 0 };
  }
  if (level === 1) {
    return { imageBytes: 12 * MIB, alphaBytes: 8 * MIB };
  }
  // MODERATE（以及未知的较轻级别）：保留一半，避免刚回收完又立刻重解整屏。
  return { imageBytes: 24 * MIB, alphaBytes: 16 * MIB };
}
