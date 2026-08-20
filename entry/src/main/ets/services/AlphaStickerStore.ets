import { fileIo } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import nativeWebm from 'libentry.so';
import { ALPHA_TOTAL_MAX_BYTES, AlphaDecodePlan, planAlphaDecode } from '../util/webm/AlphaStickerBudget';
import { vp9StickerApiAvailable } from '../util/webm/alphaStickerGate';
import { demuxWebmAlpha, packAlphaStreams, WebmAlphaClip } from '../util/webm/WebmAlphaDemuxer';

// 透明 webm 贴纸的解码结果仓库。
//
// 一段贴纸预解码成一串 PixelMap 常驻内存，播放时只是换图——不这么做就得为
// 每张贴纸常驻一个硬件 VP9 解码器，贴纸面板一屏几十张会把解码器耗光。
// 代价是内存，所以这里同时管三件事：按路径+显示尺寸复用（面板里同一张贴纸
// 反复出现）、全局字节预算 + LRU 回收、以及一次只解一张的排队。
//
// 任何一环失败都返回 null，调用方原样回退到 ijkplayer（白底，但不崩）。

export interface AlphaClip {
  key: string;
  frames: image.PixelMap[];
  // 每帧的呈现时刻（毫秒，从 0 起），与 frames 一一对应。
  timesMs: number[];
  durationMs: number;
  width: number;
  height: number;
}

// 解码的结局。permanent=true 表示"这个文件本身就走不了这条路"（不带 alpha、
// 不是 VP9、容器写法不认），可以永久拉黑；预算不够这类是暂时的，下次内存
// 松了还该再试一次。
interface DecodeOutcome {
  clip: AlphaClip | null;
  permanent: boolean;
}

interface CacheEntry {
  clip: AlphaClip;
  bytes: number;
  refs: number;
  lastUsed: number;
}

// 贴纸文件本来就只有几十 KB；比这大的多半不是贴纸，别读进内存。
const MAX_FILE_BYTES: number = 4 * 1024 * 1024;
// 显示尺寸按 32px 归桶，让"160 和 168"这种细微差别共用同一份解码结果。
const SIZE_BUCKET: number = 32;
const MIN_BUCKET: number = 96;
const MAX_BUCKET: number = 256;
// 失败过的路径不再重试：解不了的贴纸每次挂载都重试一遍，等于把开销翻倍。
const MAX_REJECTED: number = 400;

const cache: Map<string, CacheEntry> = new Map();
const inFlight: Map<string, Promise<DecodeOutcome>> = new Map();
const rejected: Set<string> = new Set();
let totalBytes: number = 0;
// 一次只解一张：解码要开硬件解码器实例，几十个一起开会把设备的解码器占满，
// 也会让工作线程互相抢 CPU。串行反而更快出第一张。
let decodeChain: Promise<void> = Promise.resolve();
let nativeSupported: boolean | null = null;

function nativeAvailable(): boolean {
  if (nativeSupported === null) {
    try {
      nativeSupported = nativeWebm.webmAlphaAvailable();
    } catch (e) {
      console.error(`AlphaStickerStore: capability probe failed: ${e}`);
      nativeSupported = false;
    }
  }
  return nativeSupported === true;
}

// 这台设备能不能走透明贴纸链路。API 门控 + 原生能力探测，都只算一次。
export function alphaStickerPipelineAvailable(): boolean {
  return vp9StickerApiAvailable() && nativeAvailable();
}

export function alphaStickerCacheKey(path: string, boxPx: number): string {
  const raw = Math.ceil(Math.max(1, boxPx) / SIZE_BUCKET) * SIZE_BUCKET;
  const bucket = Math.min(MAX_BUCKET, Math.max(MIN_BUCKET, raw));
  return `${path}|${bucket}`;
}

function bucketOf(key: string): number {
  const at = key.lastIndexOf('|');
  return at < 0 ? MIN_BUCKET : Number.parseInt(key.substring(at + 1), 10);
}

function markRejected(path: string): void {
  if (rejected.size >= MAX_REJECTED) {
    rejected.clear();
  }
  rejected.add(path);
}

function releaseEntry(entry: CacheEntry): void {
  for (const frame of entry.clip.frames) {
    try {
      frame.release();
    } catch (e) {
      console.error(`AlphaStickerStore: pixelmap release failed: ${e}`);
    }
  }
  totalBytes -= entry.bytes;
  if (totalBytes < 0) {
    totalBytes = 0;
  }
}

// 只回收没人引用的条目。正在播的贴纸被回收会当场变成破图，宁可暂时超预算，
// 也不能让屏幕上的东西消失——真正的闸门是 planAlphaDecode 那一层的准入。
function evictUntilFits(need: number): void {
  while (totalBytes + need > ALPHA_TOTAL_MAX_BYTES) {
    let victimKey = '';
    let victimAt = Number.MAX_SAFE_INTEGER;
    cache.forEach((entry: CacheEntry, key: string) => {
      if (entry.refs === 0 && entry.lastUsed < victimAt) {
        victimAt = entry.lastUsed;
        victimKey = key;
      }
    });
    if (victimKey === '') {
      return;
    }
    const victim = cache.get(victimKey);
    if (victim !== undefined) {
      releaseEntry(victim);
      cache.delete(victimKey);
    }
  }
}

export function alphaStickerFreeBytes(): number {
  let reclaimable = 0;
  cache.forEach((entry: CacheEntry) => {
    if (entry.refs === 0) {
      reclaimable += entry.bytes;
    }
  });
  return Math.max(0, ALPHA_TOTAL_MAX_BYTES - totalBytes + reclaimable);
}

async function readFileBytes(path: string): Promise<Uint8Array | null> {
  let file: fileIo.File | null = null;
  try {
    const stat = await fileIo.stat(path);
    if (stat.size <= 0 || stat.size > MAX_FILE_BYTES) {
      return null;
    }
    file = await fileIo.open(path, fileIo.OpenMode.READ_ONLY);
    const buffer = new ArrayBuffer(stat.size);
    const read = await fileIo.read(file.fd, buffer);
    return read > 0 ? new Uint8Array(buffer, 0, read) : null;
  } catch (e) {
    console.error(`AlphaStickerStore: read failed: ${e}`);
    return null;
  } finally {
    if (file !== null) {
      try {
        fileIo.closeSync(file);
      } catch (e) {
        // 关闭失败不影响已读出的字节
      }
    }
  }
}

function outcome(clip: AlphaClip | null, permanent: boolean): DecodeOutcome {
  return { clip: clip, permanent: permanent };
}

async function decodeClip(path: string, key: string): Promise<DecodeOutcome> {
  const bytes = await readFileBytes(path);
  if (bytes === null) {
    return outcome(null, true);
  }
  const clip: WebmAlphaClip | null = demuxWebmAlpha(bytes);
  if (clip === null) {
    // 不带 alpha、不是 VP9、或者容器里有我们不处理的写法——文件不会变，拉黑。
    return outcome(null, true);
  }
  const plan: AlphaDecodePlan = planAlphaDecode(
    clip.track.width, clip.track.height, bucketOf(key), clip.frames.length, alphaStickerFreeBytes());
  if (!plan.accept) {
    return outcome(null, false); // 只是这一刻没预算，别永久拉黑
  }
  const payload = packAlphaStreams(clip.frames, plan.frameStep);
  if (payload === null) {
    return outcome(null, true);
  }
  // 只有真正的解码排队，读文件和拆包不排：绝大多数 webm 贴纸走到这一步之前
  // 就被判成"不带 alpha"了，让它们排在别人的解码后面才回退，等于白等一轮。
  const decoded: Object[] = await serialize((): Promise<Object[]> => nativeWebm.webmAlphaDecode(
    payload.colorData, payload.colorLengths, payload.alphaData, payload.alphaLengths,
    clip.track.width, clip.track.height, plan.targetW, plan.targetH, plan.frameStep));
  if (decoded.length === 0) {
    // 原生失败的原因分不清是文件还是设备，按暂时处理：拉黑的代价是这张贴纸
    // 永远白底，重试的代价只是多一次几十毫秒的解码。
    return outcome(null, false);
  }
  const frames: image.PixelMap[] = [];
  for (const item of decoded) {
    frames.push(item as image.PixelMap);
  }
  // 原生可能比预期少吐几帧（解码器丢帧），时间戳表按实际帧数截断。
  const timesMs: number[] = payload.keptTimesMs.slice(0, frames.length);
  const durationMs = Math.max(clip.durationMs, timesMs.length > 0 ? timesMs[timesMs.length - 1] : 0);
  return outcome({
    key: key, frames: frames, timesMs: timesMs, durationMs: durationMs,
    width: plan.targetW, height: plan.targetH
  }, false);
}

function serialize(job: () => Promise<Object[]>): Promise<Object[]> {
  const run = decodeChain.then(job);
  // 链条本身不能因为某一次失败而断掉，否则后面的贴纸全部排不进来。
  decodeChain = run.then((): void => {}, (): void => {});
  return run;
}

// 取一段可播的透明贴纸。拿到之后必须配对调用 releaseAlphaSticker。
export async function acquireAlphaSticker(path: string, boxPx: number): Promise<AlphaClip | null> {
  if (path === '' || !alphaStickerPipelineAvailable() || rejected.has(path)) {
    return null;
  }
  const key = alphaStickerCacheKey(path, boxPx);
  const cached = cache.get(key);
  if (cached !== undefined) {
    cached.refs++;
    cached.lastUsed = Date.now();
    return cached.clip;
  }
  const pending = inFlight.get(key);
  if (pending !== undefined) {
    await pending;
    const entry = cache.get(key);
    if (entry === undefined) {
      return null;
    }
    entry.refs++;
    entry.lastUsed = Date.now();
    return entry.clip;
  }
  const task = decodeClip(path, key);
  inFlight.set(key, task);
  let result: DecodeOutcome = outcome(null, false);
  try {
    result = await task;
  } catch (e) {
    console.error(`AlphaStickerStore: decode threw: ${e}`);
  }
  inFlight.delete(key);
  const clip = result.clip;
  if (clip === null) {
    if (result.permanent) {
      markRejected(path);
    }
    return null;
  }
  const bytes = clip.width * clip.height * 4 * clip.frames.length;
  evictUntilFits(bytes);
  totalBytes += bytes;
  cache.set(key, { clip: clip, bytes: bytes, refs: 1, lastUsed: Date.now() });
  return clip;
}

export function releaseAlphaSticker(clip: AlphaClip | null): void {
  if (clip === null) {
    return;
  }
  const entry = cache.get(clip.key);
  if (entry === undefined) {
    return;
  }
  entry.refs = Math.max(0, entry.refs - 1);
  entry.lastUsed = Date.now();
  if (entry.refs === 0) {
    evictUntilFits(0);
  }
}
