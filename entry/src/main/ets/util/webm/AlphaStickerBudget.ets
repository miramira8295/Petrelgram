// 透明贴纸的内存预算。
//
// 这条链路把整段贴纸预解码成 RGBA 帧驻留在内存里——不这么做就得为每张贴纸
// 常驻一个硬件 VP9 解码器实例，贴纸面板一屏几十张直接把解码器耗光。代价是
// 内存：512×512、3 秒、30fps 的原始 RGBA 是 94MB，一张就能把进程打爆。
//
// 所以尺寸/帧数/总量三道闸门都在这里，纯函数，可单测。任何一道过不去就
// accept=false，调用方原样回退到 ijkplayer（白底，但不崩、不卡）。

// 单张贴纸的解码上限。超过就先降帧、再降分辨率，都不行才放弃。
export const ALPHA_STICKER_MAX_BYTES: number = 12 * 1024 * 1024;
// 全进程上限与普通 PixelMap 缓存共用统一预算，见 NativePixelBudget。
export { ALPHA_STICKER_CACHE_MAX_BYTES as ALPHA_TOTAL_MAX_BYTES } from '../NativePixelBudget';
// 贴纸原生 512，但屏幕上从来占不到那么大；再大只是白烧内存。
const MAX_DIM: number = 256;
// 低于这个尺寸就糊得不像贴纸了，宁可回退。
const MIN_DIM: number = 96;
// 帧数上限：Telegram 的视频贴纸约定 ≤3 秒 30fps，也就是 90 帧左右。
const MAX_FRAMES: number = 120;
// 抽帧上限。抽到 1/3 还是 10fps，再稀就看得出卡了。
const MAX_FRAME_STEP: number = 3;
// 逐级缩小的比例，够细以免一步跨过预算。
const SHRINK_STEPS: number[] = [1, 0.875, 0.75, 0.625, 0.5];

export interface AlphaDecodePlan {
  accept: boolean;
  targetW: number;
  targetH: number;
  // 1 = 每帧都要，2 = 隔一帧取一帧，依此类推。
  frameStep: number;
  frameCount: number;
  bytes: number;
}

function reject(): AlphaDecodePlan {
  return { accept: false, targetW: 0, targetH: 0, frameStep: 1, frameCount: 0, bytes: 0 };
}

function evenClamp(v: number): number {
  const r = Math.round(v / 2) * 2;
  return r < 2 ? 2 : r;
}

// 按源比例把画面塞进 box×box，同时不超过 MAX_DIM、不放大到源尺寸以上。
function fitBox(srcW: number, srcH: number, box: number): number[] {
  const longest = Math.max(srcW, srcH);
  const limit = Math.min(box, MAX_DIM, longest);
  const scale = limit / longest;
  return [evenClamp(srcW * scale), evenClamp(srcH * scale)];
}

export function planAlphaDecode(srcW: number, srcH: number, boxPx: number,
  frameCount: number, freeBytes: number): AlphaDecodePlan {
  if (srcW <= 0 || srcH <= 0 || frameCount <= 0 || boxPx <= 0) {
    return reject();
  }
  const budget = Math.min(ALPHA_STICKER_MAX_BYTES, freeBytes);
  if (budget <= 0) {
    return reject();
  }
  // 帧数硬上限先兑现：贴纸再长也不给它无限帧。
  const minStep = Math.max(1, Math.ceil(frameCount / MAX_FRAMES));
  if (minStep > MAX_FRAME_STEP) {
    return reject();
  }
  const box = Math.max(MIN_DIM, Math.ceil(boxPx));
  for (const shrink of SHRINK_STEPS) {
    const fit = fitBox(srcW, srcH, Math.round(box * shrink));
    const w = fit[0];
    const h = fit[1];
    if (Math.max(w, h) < MIN_DIM && Math.max(srcW, srcH) >= MIN_DIM) {
      break; // 已经缩到不能看了，别再往下试
    }
    // 先保画质再保帧率：同样的预算下，糊一点比卡一点更难看。
    for (let step = minStep; step <= MAX_FRAME_STEP; step++) {
      const count = Math.ceil(frameCount / step);
      const bytes = w * h * 4 * count;
      if (bytes <= budget) {
        return {
          accept: true, targetW: w, targetH: h,
          frameStep: step, frameCount: count, bytes: bytes
        };
      }
    }
  }
  return reject();
}
