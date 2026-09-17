// 透明贴纸解码结果的缓存键（内存那份），以及从键里拆回尺寸档与预算档位。
//
// 【从 services/AlphaStickerStore 搬出来】那个文件依赖原生库，宿主上跑不了单测；
// 而拼键和拆键恰恰是改一处漏一处的地方（2026-09-17 加预算档位就要两头同时改）。
//
// 【为什么键里要有预算档位】解码结果连抽帧步长一起缓存（内存 + 磁盘，磁盘文件名见
// util/stickerFrameCache）。会话里的大表情放宽了单张预算（AlphaStickerBudget），
// 同一个文件在两个档位下解出来的帧数不同；键不区分的话，之前按普通档隔帧缓存下的
// 会被一直命中，放宽预算等于没改。

// 显示尺寸按 32px 归桶，让"160 和 168"这种细微差别共用同一份解码结果。
export const ALPHA_SIZE_BUCKET: number = 32;
export const ALPHA_MIN_BUCKET: number = 96;
export const ALPHA_MAX_BUCKET: number = 256;
const HIGH_BUDGET_SUFFIX: string = '|hi';

export function alphaSizeBucket(boxPx: number): number {
  const raw: number = Math.ceil(Math.max(1, boxPx) / ALPHA_SIZE_BUCKET) * ALPHA_SIZE_BUCKET;
  return Math.min(ALPHA_MAX_BUCKET, Math.max(ALPHA_MIN_BUCKET, raw));
}

export function alphaCacheKey(path: string, bucketPx: number, highBudget: boolean): string {
  const base: string = `${path}|${bucketPx}`;
  return highBudget ? `${base}${HIGH_BUDGET_SUFFIX}` : base;
}

export function alphaKeyHighBudget(key: string): boolean {
  return key.endsWith(HIGH_BUDGET_SUFFIX);
}

export function alphaKeyBucket(key: string): number {
  const base: string = alphaKeyHighBudget(key)
    ? key.substring(0, key.length - HIGH_BUDGET_SUFFIX.length) : key;
  const at: number = base.lastIndexOf('|');
  if (at < 0) {
    return ALPHA_MIN_BUCKET;
  }
  const bucket: number = Number.parseInt(base.substring(at + 1), 10);
  return Number.isNaN(bucket) ? ALPHA_MIN_BUCKET : bucket;
}
