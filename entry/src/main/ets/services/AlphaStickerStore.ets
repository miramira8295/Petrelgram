import { fileIo } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import nativeWebm, { StickerFramesInfo } from 'libentry.so';
import {
  ALPHA_EMOJI_CHAT_MAX_BYTES, ALPHA_STICKER_MAX_BYTES, ALPHA_TOTAL_MAX_BYTES, AlphaDecodePlan, planAlphaDecode
} from '../util/webm/AlphaStickerBudget';
import { alphaCacheKey, alphaKeyBucket, alphaKeyHighBudget, alphaSizeBucket } from '../util/webm/alphaCacheKey';
import { logW } from '../util/log';
import { packAlphaStreams, WebmAlphaClip } from '../util/webm/WebmAlphaDemuxer';
import { demuxWebmAlphaOffThread } from '../util/webm/webmDemuxTask';
import { ALPHA_STICKER_CACHE_MAX_BYTES } from '../util/NativePixelBudget';
import { registerAlphaPixelUsage } from '../util/nativePixelArbiter';
import {
  FRAME_CACHE_MAX_BYTES, FrameCacheEntry, frameCacheFileName, planFrameCachePrune
} from '../util/stickerFrameCache';
import {
  cachedFramesPathFor, noteFrameCacheRemoved, noteFrameCacheWritten, stickerFrameCacheDir, uidFramesWritePath
} from './stickerFrameIndex';

// 透明 webm 贴纸的解码结果仓库。
//
// 一段贴纸解码成一串 PixelMap 常驻内存，播放时只是换图——不这么做就得为
// 每张贴纸常驻一个 VP9 解码器，贴纸面板一屏几十张会把解码器耗光。
// 代价是内存，所以这里同时管三件事：按路径+显示尺寸复用（面板里同一张贴纸
// 反复出现）、全局字节预算 + LRU 回收、以及边解边播（第一帧到了就交出去，
// 后面的帧陆续追加；调度在原生侧，见 cpp/sticker_decode_queue）。
//
// 失败分两类（见 AlphaAcquireStatus）：文件/设备走不了这条路的，调用方才回退；
// 只是这一刻内存预算不够的，调用方等着，别回退。

// 边解边播（2026-10-09）：拿到第一帧就把 clip 交给播放组件，后面的帧由解码线程
// 一批批追加进 **同一个** frames 数组（这里是有意的原地追加——播放组件每拍按
// frames.length 取「已经到手的帧」，换数组就得通知每个持有者）。complete 之前
// timesMs 已是全长，播放时间轴照常走，帧没追上就停在最新那一帧
// （util/webm/alphaPlayback.alphaPlayableIndex）。
export interface AlphaClip {
  key: string;
  frames: image.PixelMap[];
  // 每帧的呈现时刻（毫秒，从 0 起）。complete 之前就是全长，与「最终的」frames 一一对应。
  timesMs: number[];
  durationMs: number;
  width: number;
  height: number;
  // 全部帧都到了。之前不进 LRU（不会被回收），没人用了就直接取消解码。
  complete: boolean;
  // 中途解坏了：已到的帧随即释放，播放组件看到就回退。
  failed: boolean;
}

// 解码的结局。permanent=true 表示"这个文件本身就走不了这条路"（不带 alpha、
// 不是 VP9、容器写法不认），可以永久拉黑；预算不够这类是暂时的，下次内存
// 松了还该再试一次。
interface DecodeOutcome {
  clip: AlphaClip | null;
  permanent: boolean;
  // 这一刻内存预算不够（不是文件的问题）：调用方该等，不该回退。
  busy: boolean;
}

// 调用方拿到的结局。busy：内存预算这一刻被在播的占满了，等别人还掉再试；
// unsupported：这个文件或这台设备这次走不了这条路。
// **只有 unsupported 才值得退回播放器**——busy 也回退的话，预算一满每个新格子
// 都会各开一个 ijk 播放器（2026-09-15 第二次崩溃：预算只剩 1KB，半秒 40 个）。
export type AlphaAcquireStatus = 'ok' | 'busy' | 'unsupported';

export interface AlphaAcquireResult {
  clip: AlphaClip | null;
  status: AlphaAcquireStatus;
}

interface CacheEntry {
  clip: AlphaClip;
  // 预留的字节（按计划帧数算）；解完按实际帧数校正。
  bytes: number;
  refs: number;
  lastUsed: number;
  // 原生解码任务号；0 = 已结束。
  jobId: number;
}

// 贴纸文件本来就只有几十 KB；比这大的多半不是贴纸，别读进内存。
const MAX_FILE_BYTES: number = 4 * 1024 * 1024;
// 失败过的路径不再重试：解不了的贴纸每次挂载都重试一遍，等于把开销翻倍。
const MAX_REJECTED: number = 400;
// 一段贴纸可能有 90 多张 PixelMap；低内存回调里整段同步 release 仍会卡主线程。
const RELEASE_BATCH_FRAMES: number = 8;
// 最小一帧（MIN_DIM 见 AlphaStickerBudget）占的字节。预算剩得比这还少，什么都解不了。
const MIN_DECODE_BYTES: number = 96 * 96 * 4;

const cache: Map<string, CacheEntry> = new Map();
const inFlight: Map<string, Promise<DecodeOutcome>> = new Map();
const rejected: Set<string> = new Set();
let totalBytes: number = 0;
// 生命周期内存压力会临时收紧；回前台恢复为统一预算里的 32MiB。
let budgetBytes: number = ALPHA_STICKER_CACHE_MAX_BYTES;
const pendingFrameReleases: image.PixelMap[] = [];
let frameReleaseTimer: number = -1;
// 原来这里有一条 promise 链把所有解码串成一队（「一次只解一张」）：一屏十几张新贴纸，
// 第十张要等前九张**整段**解完才轮到——用户反馈的「贴纸会卡」。现在调度在原生侧
// （cpp/sticker_decode_queue）：一条线程上轮转，每张先拿到第一帧。预算的准入改成
// 在发起时同步预留，不再需要排队来防「两张同时算预算各自以为还有空」。
let nativeSupported: boolean | null = null;

// ── 磁盘帧缓存 ────────────────────────────────────────────────────────
//
// 内存那份只够两三段；面板一屏几十张，LRU 一抖就要重走「读文件 → 拆 WebM →
// libvpx 逐帧软解」。落盘之后第二次只剩「读文件 → 解压」。写在原生侧（帧还是
// 裸 RGBA 的那一刻，见 cpp/sticker_frame_cache.cpp），这里只管路径与淘汰。
let prunePending: boolean = false;

// 目录归 stickerFrameIndex 管（按 ID 的索引要和它一起建）。
function ensureFrameCacheDir(): string {
  return stickerFrameCacheDir();
}

function frameCachePathFor(path: string, fileSize: number, bucketPx: number, highBudget: boolean): string {
  const dir: string = ensureFrameCacheDir();
  return dir === '' ? '' : `${dir}/${frameCacheFileName(path, fileSize, bucketPx, highBudget)}`;
}

// 写过缓存之后收一次尾。**去抖**：一屏贴纸会连着写几十次，每次都去 listFile +
// stat 一遍等于把省下来的又花掉。
function scheduleFrameCachePrune(): void {
  if (prunePending) {
    return;
  }
  prunePending = true;
  setTimeout((): void => {
    prunePending = false;
    pruneFrameCache();
  }, 30000);
}

async function pruneFrameCache(): Promise<void> {
  const dir: string = ensureFrameCacheDir();
  if (dir === '') {
    return;
  }
  try {
    const names: string[] = await fileIo.listFile(dir);
    const entries: FrameCacheEntry[] = [];
    for (const name of names) {
      try {
        const st = await fileIo.stat(`${dir}/${name}`);
        entries.push({ name: name, bytes: st.size, mtimeMs: st.mtime * 1000 });
      } catch (e) {
        // 刚被别人删掉的，跳过
      }
    }
    const doomed: string[] = planFrameCachePrune(entries, FRAME_CACHE_MAX_BYTES);
    for (const name of doomed) {
      try {
        await fileIo.unlink(`${dir}/${name}`);
        noteFrameCacheRemoved(name);
      } catch (e) {
        console.error(`AlphaStickerStore: prune unlink failed: ${e}`);
      }
    }
    if (doomed.length > 0) {
      console.warn(`[AlphaDiag] frame cache pruned ${doomed.length} file(s)`);
    }
  } catch (e) {
    console.error(`AlphaStickerStore: prune failed: ${e}`);
  }
}

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
// 这条链路能不能用。
//
// 只剩一个条件：原生模块加载成功。原来还有一条"设备 API ≥ 23"（系统 VP9 是
// 那个版本才有的），随解码器换成随包自带的 libvpx 一并拆掉——现在 20 上和 26
// 上跑的是同一份解码器，设备有没有 VP9 与本功能无关。
export function alphaStickerPipelineAvailable(): boolean {
  const native: boolean = nativeAvailable();
  if (!probeLogged) {
    probeLogged = true;
    console.warn(`[AlphaDiag] pipeline native=${native}`);
  }
  return native;
}

let probeLogged: boolean = false;

// 拼键/拆键在 util/webm/alphaCacheKey（纯函数、有单测）；这里只是转接。
export function alphaStickerCacheKey(path: string, boxPx: number, highBudget: boolean = false): string {
  return alphaCacheKey(path, alphaSizeBucket(boxPx), highBudget);
}

function bucketOf(key: string): number {
  return alphaKeyBucket(key);
}

function markRejected(path: string): void {
  if (rejected.size >= MAX_REJECTED) {
    rejected.clear();
  }
  rejected.add(path);
}

function releaseFrame(frame: image.PixelMap): void {
  try {
    frame.release();
  } catch (e) {
    console.error(`AlphaStickerStore: pixelmap release failed: ${e}`);
  }
}

function releaseFrames(frames: image.PixelMap[]): void {
  for (const frame of frames) {
    releaseFrame(frame);
  }
}

function drainFrameReleases(): void {
  frameReleaseTimer = -1;
  const count: number = Math.min(RELEASE_BATCH_FRAMES, pendingFrameReleases.length);
  for (let i = 0; i < count; i++) {
    const frame = pendingFrameReleases.shift();
    if (frame !== undefined) {
      releaseFrame(frame);
    }
  }
  if (pendingFrameReleases.length > 0) {
    frameReleaseTimer = setTimeout(drainFrameReleases, 0);
  }
}

function deferFrameReleases(frames: image.PixelMap[]): void {
  for (const frame of frames) {
    pendingFrameReleases.push(frame);
  }
  if (frameReleaseTimer === -1 && pendingFrameReleases.length > 0) {
    frameReleaseTimer = setTimeout(drainFrameReleases, 0);
  }
}

function releaseEntry(entry: CacheEntry, deferred: boolean): void {
  if (deferred) {
    deferFrameReleases(entry.clip.frames);
  } else {
    releaseFrames(entry.clip.frames);
  }
  totalBytes -= entry.bytes;
  if (totalBytes < 0) {
    totalBytes = 0;
  }
}

// 只回收没人引用的条目。正在播的贴纸被回收会当场变成破图，宁可暂时超预算，
// 也不能让屏幕上的东西消失——真正的闸门是 planAlphaDecode 那一层的准入。
function evictDownTo(limit: number, maxEntries: number = Number.MAX_SAFE_INTEGER,
  deferred: boolean = false): number {
  let evicted: number = 0;
  while (totalBytes > limit && evicted < maxEntries) {
    let victimKey = '';
    let victimAt = Number.MAX_SAFE_INTEGER;
    cache.forEach((entry: CacheEntry, key: string) => {
      if (entry.refs === 0 && entry.clip.complete && entry.lastUsed < victimAt) {
        victimAt = entry.lastUsed;
        victimKey = key;
      }
    });
    if (victimKey === '') {
      return evicted;
    }
    const victim = cache.get(victimKey);
    if (victim !== undefined) {
      releaseEntry(victim, deferred);
      cache.delete(victimKey);
      evicted++;
    }
  }
  return evicted;
}

function evictUntilFits(need: number): void {
  evictDownTo(Math.max(0, budgetBytes - need));
}

export function alphaStickerFreeBytes(): number {
  let reclaimable = 0;
  cache.forEach((entry: CacheEntry) => {
    if (entry.refs === 0 && entry.clip.complete) {
      reclaimable += entry.bytes;
    }
  });
  return Math.max(0, budgetBytes - totalBytes + reclaimable);
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

function outcome(clip: AlphaClip | null, permanent: boolean, busy: boolean = false): DecodeOutcome {
  return { clip: clip, permanent: permanent, busy: busy };
}

function acquired(clip: AlphaClip | null, status: AlphaAcquireStatus): AlphaAcquireResult {
  return { clip: clip, status: status };
}

// 从缓存里摘掉一段（取消还在跑的解码、帧延后释放、退还预算）。
function dropEntry(entry: CacheEntry): void {
  if (cache.get(entry.clip.key) === entry) {
    cache.delete(entry.clip.key);
  }
  if (entry.jobId > 0) {
    nativeWebm.stickerDecodeCancel(entry.jobId);
    entry.jobId = 0;
  }
  releaseEntry(entry, true);
  entry.clip.frames = [];
}

// 一批帧到了（解码线程经线程安全函数排回主线程）。settle 在拿到第一帧或失败时
// 兑现 acquire 的那个 promise，之后再调是空操作。
function onStreamFrames(entry: CacheEntry, frames: image.PixelMap[], done: boolean, ok: boolean,
  settle: (o: DecodeOutcome) => void, cachePathOnFail: string): void {
  if (cache.get(entry.clip.key) !== entry) {
    // 已经被取消 / 摘掉了：取消之前排好的批次还会陆续到，帧原地还掉。
    deferFrameReleases(frames);
    settle(outcome(null, false));
    return;
  }
  for (const frame of frames) {
    entry.clip.frames.push(frame);
  }
  if (done) {
    entry.jobId = 0;
    const clip: AlphaClip = entry.clip;
    if (!ok || clip.frames.length === 0) {
      console.warn(`[AlphaDiag] stream failed after ${clip.frames.length} frame(s)`);
      clip.failed = true;
      dropEntry(entry);
      if (cachePathOnFail !== '') {
        // 读缓存读坏了：删掉，免得下次又从这份坏缓存起播、播到一半回退。
        fileIo.unlink(cachePathOnFail).catch((): void => {});
        noteFrameCacheRemoved(cachePathOnFail.substring(cachePathOnFail.lastIndexOf('/') + 1));
      }
      settle(outcome(null, false));
      return;
    }
    // 解码器可能比计划少吐几帧：时间戳表与预算都按实际帧数校正。
    if (clip.timesMs.length > clip.frames.length) {
      clip.timesMs = clip.timesMs.slice(0, clip.frames.length);
    }
    const actual: number = clip.width * clip.height * 4 * clip.frames.length;
    totalBytes = Math.max(0, totalBytes + actual - entry.bytes);
    entry.bytes = actual;
    clip.complete = true;
  }
  if (entry.clip.frames.length > 0) {
    settle(outcome(entry.clip, false));
  }
}

function newClip(key: string, timesMs: number[], durationMs: number, width: number, height: number): AlphaClip {
  return {
    key: key, frames: [], timesMs: timesMs, durationMs: durationMs, width: width, height: height,
    complete: false, failed: false
  };
}

// 预算 -> 预留 -> 交给原生解码线程。拿到第一帧（或失败）时兑现。
//
// 预留必须和计划在同一拍里做完（中间不能有 await）：两张贴纸同时算预算，会各自
// 看到"还有 20MB"，加起来就超了。原来靠一条串行队列防这个，现在靠同步预留。
// cachePath：解完写到哪（'' = 不写）。有唯一 ID 时按 ID 命名，下载之前就能查到。
function startDecode(clip: WebmAlphaClip, key: string, cachePath: string): Promise<DecodeOutcome> {
  const free: number = alphaStickerFreeBytes();
  const highBudget: boolean = alphaKeyHighBudget(key);
  const plan: AlphaDecodePlan = planAlphaDecode(
    clip.track.width, clip.track.height, bucketOf(key), clip.frames.length, free,
    highBudget ? ALPHA_EMOJI_CHAT_MAX_BYTES : ALPHA_STICKER_MAX_BYTES);
  if (highBudget) {
    // 会话大表情的解码计划，上机时确认放宽预算真的生效（帧数、步长、尺寸）。
    logW(`[AlphaPlan] emoji decode bucket=${bucketOf(key)} frames=${clip.frames.length} free=${free} `
      + `accept=${plan.accept} ${plan.targetW}x${plan.targetH} step=${plan.frameStep}`);
  }
  if (!plan.accept) {
    return Promise.resolve(outcome(null, false, true)); // 只是这一刻没预算，别永久拉黑
  }
  const payload = packAlphaStreams(clip.frames, plan.frameStep);
  if (payload === null) {
    return Promise.resolve(outcome(null, true));
  }
  // 时间戳表打包成 Int32 交过去：原生落盘时要把它一起写进缓存头，否则命中
  // 缓存那条路没有拆包过程，拿不到每帧的呈现时刻。
  const times: Int32Array = new Int32Array(payload.keptTimesMs.length);
  const timesMs: number[] = [];
  for (let i = 0; i < payload.keptTimesMs.length; i++) {
    times[i] = Math.round(payload.keptTimesMs[i]);
    timesMs.push(times[i]);
  }
  const bytes: number = plan.targetW * plan.targetH * 4 * timesMs.length;
  evictUntilFits(bytes);
  if (totalBytes + bytes > budgetBytes) {
    return Promise.resolve(outcome(null, false, true));
  }
  const lastMs: number = timesMs.length > 0 ? timesMs[timesMs.length - 1] : 0;
  const entry: CacheEntry = {
    clip: newClip(key, timesMs, Math.max(clip.durationMs, lastMs), plan.targetW, plan.targetH),
    bytes: bytes, refs: 0, lastUsed: Date.now(), jobId: 0
  };
  totalBytes += bytes;
  cache.set(key, entry);
  return new Promise<DecodeOutcome>((resolve: (o: DecodeOutcome) => void): void => {
    let settled: boolean = false;
    const startedAt: number = Date.now();
    const settle = (o: DecodeOutcome): void => {
      if (!settled) {
        settled = true;
        // 上机对比用：从发起到第一帧（或失败）的耗时。
        console.warn(`[AlphaStream] decode first=${o.clip !== null} busy=${o.busy} ms=${Date.now() - startedAt}`);
        resolve(o);
      }
    };
    const id: number = nativeWebm.webmAlphaDecodeStream(
      payload.colorData, payload.colorLengths, payload.alphaData, payload.alphaLengths,
      clip.track.width, clip.track.height, plan.targetW, plan.targetH, plan.frameStep,
      cachePath, times.buffer as ArrayBuffer, Math.round(clip.durationMs),
      (frames: image.PixelMap[], done: boolean, ok: boolean): void => {
        onStreamFrames(entry, frames, done, ok, settle, '');
        if (done && ok && cachePath !== '') {
          noteFrameCacheWritten(cachePath.substring(cachePath.lastIndexOf('/') + 1));
          scheduleFrameCachePrune();
        }
      });
    if (id === 0) {
      console.warn('[AlphaDiag] native decode refused to start');
      // 原生拒绝的原因分不清是文件还是参数，按暂时处理：拉黑的代价是这张贴纸
      // 永远白底，重试的代价只是多一次解码。
      dropEntry(entry);
      settle(outcome(null, false));
      return;
    }
    entry.jobId = id;
  });
}

// 磁盘命中这条路：不读 webm、不拆包、不解码，只把压缩帧逐帧解出来。帧数和尺寸
// 要等原生读完头部（第一批回调）才知道，所以预算在那一刻预留；放不下就取消。
function startCacheLoad(cachePath: string, key: string): Promise<DecodeOutcome> {
  const free: number = alphaStickerFreeBytes();
  if (free <= 0) {
    return Promise.resolve(outcome(null, false, true));
  }
  return new Promise<DecodeOutcome>((resolve: (o: DecodeOutcome) => void): void => {
    let settled: boolean = false;
    const startedAt: number = Date.now();
    const settle = (o: DecodeOutcome): void => {
      if (!settled) {
        settled = true;
        // 上机对比用：从发起到第一帧（或失败）的耗时。
        console.warn(`[AlphaStream] cache first=${o.clip !== null} busy=${o.busy} ms=${Date.now() - startedAt}`);
        resolve(o);
      }
    };
    let entry: CacheEntry | null = null;
    let jobId: number = 0;
    jobId = nativeWebm.stickerFramesLoadStream(cachePath, free,
      (frames: image.PixelMap[], done: boolean, ok: boolean, info: StickerFramesInfo | undefined): void => {
        if (entry !== null) {
          onStreamFrames(entry, frames, done, ok, settle, cachePath);
          return;
        }
        if (!ok || info === undefined) {
          deferFrameReleases(frames);
          // 带着 info 失败 = 磁盘上有，只是内存不够；不带 = 没有缓存，照常去解码。
          settle(outcome(null, false, info !== undefined));
          return;
        }
        const bytes: number = info.width * info.height * 4 * info.timesMs.length;
        evictUntilFits(bytes);
        if (totalBytes + bytes > budgetBytes || cache.has(key)) {
          if (!done) {
            nativeWebm.stickerDecodeCancel(jobId);
          }
          deferFrameReleases(frames);
          settle(outcome(null, false, true));
          return;
        }
        const reserved: CacheEntry = {
          clip: newClip(key, info.timesMs, info.durationMs, info.width, info.height),
          bytes: bytes, refs: 0, lastUsed: Date.now(), jobId: done ? 0 : jobId
        };
        entry = reserved;
        totalBytes += bytes;
        cache.set(key, reserved);
        onStreamFrames(reserved, frames, done, ok, settle, cachePath);
      });
    if (jobId === 0) {
      settle(outcome(null, false));
    }
  });
}

async function decodeClip(path: string, key: string, uid: string): Promise<DecodeOutcome> {
  // 预算已经见底：连最小的一帧都放不下，就别去读文件、拆包（读整个文件、占一个 worker）。
  // 排队等内存的格子每轮到一次就重试一次，这条短路让重试几乎不花钱。
  if (alphaStickerFreeBytes() < MIN_DECODE_BYTES) {
    return outcome(null, false, true);
  }
  const highBudget: boolean = alphaKeyHighBudget(key);
  // 先按唯一 ID 查（不需要源文件，调用方可能根本没下载）。
  const uidCache: string = cachedFramesPathFor(uid, bucketOf(key), highBudget);
  if (uidCache !== '') {
    const hit: DecodeOutcome = await startCacheLoad(uidCache, key);
    if (hit.clip !== null || hit.busy) {
      return hit;   // busy：磁盘上有，只是内存不够——再去软解一遍也一样不够
    }
  }
  if (path === '') {
    // 只给了 ID、缓存却没了（刚被淘汰或读坏）：没有源文件可解，交回调用方去下载。
    return outcome(null, false);
  }
  // 再看按路径命名的旧缓存。stat 一次就能拼出身份（文件名+字节数+尺寸桶），比读整个文件
  // 再拆包便宜得多；命中就完全跳过软解。
  let sourceSize: number = 0;
  try {
    const st = await fileIo.stat(path);
    sourceSize = st.size;
  } catch (e) {
    return outcome(null, true);
  }
  const legacyCache: string = frameCachePathFor(path, sourceSize, bucketOf(key), highBudget);
  if (legacyCache !== '') {
    const hit: DecodeOutcome = await startCacheLoad(legacyCache, key);
    if (hit.clip !== null || hit.busy) {
      if (hit.clip !== null && highBudget) {
        logW(`[AlphaPlan] emoji cache hit frames=${hit.clip.timesMs.length} ${hit.clip.width}x${hit.clip.height}`);
      }
      return hit;
    }
  }
  const bytes = await readFileBytes(path);
  if (bytes === null) {
    return outcome(null, true);
  }
  // 拆包在 TaskPool 上跑（见 util/webm/webmDemuxTask）。
  const clip: WebmAlphaClip | null = await demuxWebmAlphaOffThread(bytes);
  if (clip === null) {
    console.warn(`[AlphaDiag] demux refused ${path.substring(path.lastIndexOf('/') + 1)}`);
    // 不带 alpha、不是 VP9、或者容器里有我们不处理的写法——文件不会变，拉黑。
    return outcome(null, true);
  }
  // 有唯一 ID 就按 ID 写，下次下载之前就能命中；没有才退回按路径命名。
  const writePath: string = uid !== ''
    ? uidFramesWritePath(uid, bucketOf(key), highBudget) : legacyCache;
  return startDecode(clip, key, writePath);
}

// 取一段可播的透明贴纸。拿到之后必须配对调用 releaseAlphaSticker。
//
// uid：贴纸文件的 remote.unique_id（可空）。给了它，path 可以是 ''——调用方查过
// stickerFramesCached 命中、没下载源文件的情况。
export async function acquireAlphaSticker(path: string, boxPx: number,
  highBudget: boolean = false, uid: string = ''): Promise<AlphaAcquireResult> {
  if ((path === '' && uid === '') || !alphaStickerPipelineAvailable() || (path !== '' && rejected.has(path))) {
    return acquired(null, 'unsupported');
  }
  // 有 ID 就按 ID 认人：同一张贴纸在不同会话里路径一样，但重新下载后路径可能变。
  const key = alphaStickerCacheKey(uid !== '' ? `uid:${uid}` : path, boxPx, highBudget);
  const cached = cache.get(key);
  if (cached !== undefined) {
    cached.refs++;
    cached.lastUsed = Date.now();
    return acquired(cached.clip, 'ok');
  }
  const pending = inFlight.get(key);
  if (pending !== undefined) {
    await pending;
    const entry = cache.get(key);
    if (entry === undefined) {
      return acquired(null, 'busy');   // 别人解的那份没进缓存或刚被回收
    }
    entry.refs++;
    entry.lastUsed = Date.now();
    return acquired(entry.clip, 'ok');
  }
  const task = decodeClip(path, key, uid);
  inFlight.set(key, task);
  let result: DecodeOutcome = outcome(null, false);
  try {
    result = await task;
  } catch (e) {
    console.error(`AlphaStickerStore: decode threw: ${e}`);
  }
  inFlight.delete(key);
  if (result.clip === null) {
    if (result.permanent && path !== '') {
      markRejected(path);
    }
    return acquired(null, result.busy ? 'busy' : 'unsupported');
  }
  // 预算在发起解码时已经预留（startDecode / startCacheLoad），这里只认领引用。
  const entry = cache.get(key);
  if (entry === undefined) {
    return acquired(null, 'busy'); // 极端情况下刚解完就被回收了：内存紧，让调用方等
  }
  entry.refs++;
  entry.lastUsed = Date.now();
  return acquired(entry.clip, 'ok');
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
  if (entry.refs === 0 && !entry.clip.complete) {
    // 没解完、也没人看了（滑出屏幕 / 组件销毁）：取消解码，已到的帧丢掉。
    // 半截的帧序列留着没用——下次出现时从磁盘缓存或重新解码，都是从第一帧起播。
    dropEntry(entry);
    return;
  }
  if (entry.refs === 0) {
    // 如果预算已被生命周期回调收紧，组件消失这一拍也不能同步释放整段帧。
    evictDownTo(budgetBytes, Number.MAX_SAFE_INTEGER, true);
  }
}

export function setAlphaStickerCacheBudget(bytes: number): void {
  budgetBytes = Math.max(0, Math.min(ALPHA_TOTAL_MAX_BYTES, Math.floor(bytes)));
}

// 只碰 refs===0 的 LRU 条目，正在播放的贴纸不会被释放。一个条目可能包含很多
// 帧，因此生命周期回调默认可以用 maxEntries=1 分批执行。
export function trimAlphaStickerCache(targetBytes: number = 0,
  maxEntries: number = Number.MAX_SAFE_INTEGER): number {
  const target: number = Math.max(0, Math.floor(targetBytes));
  const batch: number = Math.max(0, Math.floor(maxEntries));
  return evictDownTo(target, batch, true);
}

export function alphaStickerCacheBytes(): number {
  return totalBytes;
}

// 向图片缓存报数：贴纸没用满的部分借给它（见 util/nativePixelArbiter）。
// **不反向 import**——这里是 service 层，pixelCache 是 util 层。
// 本模块被加载过才会注册；纯图片会话里它根本不加载，图片那边按 0 算，
// 正好是我们想要的。
registerAlphaPixelUsage(alphaStickerCacheBytes);
