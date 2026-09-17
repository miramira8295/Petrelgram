import { fileIo } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import nativeWebm from 'libentry.so';
import {
  ALPHA_EMOJI_CHAT_MAX_BYTES, ALPHA_STICKER_MAX_BYTES, ALPHA_TOTAL_MAX_BYTES, AlphaDecodePlan, planAlphaDecode
} from '../util/webm/AlphaStickerBudget';
import { alphaCacheKey, alphaKeyBucket, alphaKeyHighBudget, alphaSizeBucket } from '../util/webm/alphaCacheKey';
import { logW } from '../util/log';
import { packAlphaStreams, WebmAlphaClip } from '../util/webm/WebmAlphaDemuxer';
import { demuxWebmAlphaOffThread } from '../util/webm/webmDemuxTask';
import { ALPHA_STICKER_CACHE_MAX_BYTES } from '../util/NativePixelBudget';
import {
  FRAME_CACHE_DIR, FRAME_CACHE_MAX_BYTES, FrameCacheEntry, frameCacheFileName, planFrameCachePrune
} from '../util/stickerFrameCache';
import { appFilesDir } from '../tdkit/Globals';

// 透明 webm 贴纸的解码结果仓库。
//
// 一段贴纸预解码成一串 PixelMap 常驻内存，播放时只是换图——不这么做就得为
// 每张贴纸常驻一个硬件 VP9 解码器，贴纸面板一屏几十张会把解码器耗光。
// 代价是内存，所以这里同时管三件事：按路径+显示尺寸复用（面板里同一张贴纸
// 反复出现）、全局字节预算 + LRU 回收、以及一次只解一张的排队。
//
// 失败分两类（见 AlphaAcquireStatus）：文件/设备走不了这条路的，调用方才回退；
// 只是这一刻内存预算不够的，调用方等着，别回退。

// 原生 stickerFramesLoad 的回包形状。
export interface CachedStickerFrames {
  frames: image.PixelMap[];
  timesMs: number[];
  width: number;
  height: number;
  durationMs: number;
}

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
  bytes: number;
  refs: number;
  lastUsed: number;
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
// 一次只解一张：解码要开硬件解码器实例，几十个一起开会把设备的解码器占满，
// 也会让工作线程互相抢 CPU。串行反而更快出第一张。
let decodeChain: Promise<void> = Promise.resolve();
let nativeSupported: boolean | null = null;

// ── 磁盘帧缓存 ────────────────────────────────────────────────────────
//
// 内存那份只够两三段；面板一屏几十张，LRU 一抖就要重走「读文件 → 拆 WebM →
// libvpx 逐帧软解」。落盘之后第二次只剩「读文件 → 解压」。写在原生侧（帧还是
// 裸 RGBA 的那一刻，见 cpp/sticker_frame_cache.cpp），这里只管路径与淘汰。
let frameCacheDir: string = '';
let frameCacheDirReady: boolean = false;
let prunePending: boolean = false;

function ensureFrameCacheDir(): string {
  if (frameCacheDirReady) {
    return frameCacheDir;
  }
  frameCacheDirReady = true;
  const base: string = appFilesDir();
  if (base === '') {
    return '';
  }
  frameCacheDir = `${base}/${FRAME_CACHE_DIR}`;
  try {
    if (!fileIo.accessSync(frameCacheDir)) {
      fileIo.mkdirSync(frameCacheDir);
    }
  } catch (e) {
    console.error(`AlphaStickerStore: frame cache dir failed: ${e}`);
    frameCacheDir = '';
  }
  return frameCacheDir;
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
      if (entry.refs === 0 && entry.lastUsed < victimAt) {
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
    if (entry.refs === 0) {
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

// 预算 -> 解码 -> 入账，整段在排队里做。
//
// 拆开会有一个很难查的洞：两张贴纸同时算预算，会各自看到"还有 56MB"，加起来
// 就超了。入账也必须在这里，不能等调用方 await 回来再记——那时下一个任务
// 可能已经开算了。
async function decodeReserved(clip: WebmAlphaClip, key: string,
  sourcePath: string, sourceSize: number): Promise<DecodeOutcome> {
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
    return outcome(null, false, true); // 只是这一刻没预算，别永久拉黑
  }
  const payload = packAlphaStreams(clip.frames, plan.frameStep);
  if (payload === null) {
    return outcome(null, true);
  }
  // 时间戳表打包成 Int32 交过去：原生落盘时要把它一起写进缓存头，否则命中
  // 缓存那条路没有拆包过程，拿不到每帧的呈现时刻。
  const times: Int32Array = new Int32Array(payload.keptTimesMs.length);
  for (let i = 0; i < payload.keptTimesMs.length; i++) {
    times[i] = Math.round(payload.keptTimesMs[i]);
  }
  const cachePath: string = frameCachePathFor(sourcePath, sourceSize, bucketOf(key), highBudget);
  const frames: image.PixelMap[] = await nativeWebm.webmAlphaDecode(
    payload.colorData, payload.colorLengths, payload.alphaData, payload.alphaLengths,
    clip.track.width, clip.track.height, plan.targetW, plan.targetH, plan.frameStep,
    cachePath, times.buffer as ArrayBuffer, Math.round(clip.durationMs));
  if (cachePath !== '' && frames.length > 0) {
    scheduleFrameCachePrune();
  }
  if (frames.length === 0) {
    console.warn('[AlphaDiag] native decode returned 0 frames');
    // 原生失败的原因分不清是文件还是设备，按暂时处理：拉黑的代价是这张贴纸
    // 永远白底，重试的代价只是多一次几十毫秒的解码。
    return outcome(null, false);
  }
  // 原生可能比预期少吐几帧（解码器丢帧），时间戳表按实际帧数截断。
  const timesMs: number[] = payload.keptTimesMs.slice(0, frames.length);
  const durationMs = Math.max(clip.durationMs, timesMs.length > 0 ? timesMs[timesMs.length - 1] : 0);
  const decoded: AlphaClip = {
    key: key, frames: frames, timesMs: timesMs, durationMs: durationMs,
    width: plan.targetW, height: plan.targetH
  };
  const bytes = plan.targetW * plan.targetH * 4 * frames.length;
  evictUntilFits(bytes);
  // 预算可能在原生解码期间因为切后台/低内存回调而收紧。不能把旧计划的结果
  // 强行塞回去；立即释放这批帧并让调用方走现有降级链路。
  if (totalBytes + bytes > budgetBytes) {
    console.warn(`[AlphaDiag] budget shrank mid-decode need=${bytes} total=${totalBytes}`);
    releaseFrames(frames);
    return outcome(null, false, true);
  }
  totalBytes += bytes;
  cache.set(key, { clip: decoded, bytes: bytes, refs: 0, lastUsed: Date.now() });
  return outcome(decoded, false);
}

// 磁盘命中这条路：不读 webm、不拆包、不解码，只把压缩帧解出来建 PixelMap。
// 仍然排在同一条队列里——它同样要占内存预算，两条路一起算账才不会超。
async function loadCachedReserved(cachePath: string, key: string): Promise<DecodeOutcome> {
  const free: number = alphaStickerFreeBytes();
  if (free <= 0) {
    return outcome(null, false, true);
  }
  const loaded: CachedStickerFrames | null =
    await nativeWebm.stickerFramesLoad(cachePath, free);
  if (loaded === null || loaded.frames.length === 0) {
    return outcome(null, false);
  }
  const bytes: number = loaded.width * loaded.height * 4 * loaded.frames.length;
  evictUntilFits(bytes);
  if (totalBytes + bytes > budgetBytes) {
    releaseFrames(loaded.frames);
    return outcome(null, false, true);
  }
  const decoded: AlphaClip = {
    key: key, frames: loaded.frames, timesMs: loaded.timesMs.slice(0, loaded.frames.length),
    durationMs: loaded.durationMs, width: loaded.width, height: loaded.height
  };
  totalBytes += bytes;
  cache.set(key, { clip: decoded, bytes: bytes, refs: 0, lastUsed: Date.now() });
  return outcome(decoded, false);
}

async function decodeClip(path: string, key: string): Promise<DecodeOutcome> {
  // 预算已经见底：连最小的一帧都放不下，就别去读文件、拆包（读整个文件、占一个 worker）。
  // 排队等内存的格子每轮到一次就重试一次，这条短路让重试几乎不花钱。
  if (alphaStickerFreeBytes() < MIN_DECODE_BYTES) {
    return outcome(null, false, true);
  }
  // 先看磁盘。stat 一次就能拼出身份（文件名+字节数+尺寸桶），比读整个文件
  // 再拆包便宜得多；命中就完全跳过软解。
  let sourceSize: number = 0;
  try {
    const st = await fileIo.stat(path);
    sourceSize = st.size;
  } catch (e) {
    return outcome(null, true);
  }
  const cachePath: string = frameCachePathFor(path, sourceSize, bucketOf(key), alphaKeyHighBudget(key));
  if (cachePath !== '') {
    const hit: DecodeOutcome = await serialize(
      (): Promise<DecodeOutcome> => loadCachedReserved(cachePath, key));
    if (hit.clip !== null || hit.busy) {
      if (hit.clip !== null && alphaKeyHighBudget(key)) {
        logW(`[AlphaPlan] emoji cache hit frames=${hit.clip.frames.length} ${hit.clip.width}x${hit.clip.height}`);
      }
      return hit;   // busy：磁盘上有，只是内存不够——再去软解一遍也一样不够
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
  // 读文件和拆包**不**排队：绝大多数 webm 贴纸在上面这一步就被判成"不带
  // alpha"了，让它们排在别人的解码后面才回退，等于白等一轮。
  return serialize((): Promise<DecodeOutcome> => decodeReserved(clip, key, path, sourceSize));
}

function serialize(job: () => Promise<DecodeOutcome>): Promise<DecodeOutcome> {
  const run = decodeChain.then(job);
  // 链条本身不能因为某一次失败而断掉，否则后面的贴纸全部排不进来。
  decodeChain = run.then((): void => {}, (): void => {});
  return run;
}

// 取一段可播的透明贴纸。拿到之后必须配对调用 releaseAlphaSticker。
export async function acquireAlphaSticker(path: string, boxPx: number,
  highBudget: boolean = false): Promise<AlphaAcquireResult> {
  if (path === '' || !alphaStickerPipelineAvailable() || rejected.has(path)) {
    return acquired(null, 'unsupported');
  }
  const key = alphaStickerCacheKey(path, boxPx, highBudget);
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
  const task = decodeClip(path, key);
  inFlight.set(key, task);
  let result: DecodeOutcome = outcome(null, false);
  try {
    result = await task;
  } catch (e) {
    console.error(`AlphaStickerStore: decode threw: ${e}`);
  }
  inFlight.delete(key);
  if (result.clip === null) {
    if (result.permanent) {
      markRejected(path);
    }
    return acquired(null, result.busy ? 'busy' : 'unsupported');
  }
  // 入账已经在 decodeReserved 里做完了，这里只认领引用。
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
