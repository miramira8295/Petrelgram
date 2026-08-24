import { image } from '@kit.ImageKit';
import { sendableImage } from '@kit.ImageKit';
import { taskpool } from '@kit.ArkTS';
import { decodeSendable } from './pixelDecodeTask';
import { logE } from './log';
import {
  IMAGE_HOLDER_RELEASE_BATCH, IMAGE_PIXEL_CACHE_MAX_BYTES
} from './NativePixelBudget';

// Decode local images ourselves instead of handing a file path to Image.
//
// Two reasons, both measured on device:
//
// 1. desiredSize downsamples DURING the decode rather than scaling a full-size
//    bitmap afterwards, so an album cell no longer decodes a whole
//    conversation-sized photo to draw it 90vp wide.
// 2. The decode runs on a TaskPool worker (pixelDecodeTask). This module used
//    to decode inline, and a device capture showed every CreatePixelMap on the
//    process's main tid — `await` yields the stack but stays on the thread — so
//    two or three photos entering the viewport in one frame burned ~40ms of it.
//    That was the residual jank while scrolling a media-heavy chat.
//
// The LRU below also caps how much decoded memory is held at once, which a bare
// Image(src) cannot do.

export interface PixelRequest {
  path: string;      // local file path, no file:// prefix
  width: number;     // target size in PHYSICAL pixels
  height: number;
}

// Handed straight back to the caller, so retaining never has to look the entry
// up again.
//
// The lookup version had a race that showed up as images simply not appearing:
// decode() inserted the entry and then ran eviction, which could drop the entry
// it had just created (nothing referenced it yet) and free its pixels; by the
// time the awaiting component called retain, the key was gone from the map, so
// the reference was never taken and the component was left holding a released
// PixelMap. Passing the entry itself removes the window entirely.
export class PixelHandle {
  readonly pixelMap: image.PixelMap;
  bytes: number = 0;
  // One reference is held by the cache itself while the entry is in the map,
  // plus one per component currently showing it. Pixels are freed when the
  // count reaches zero — so eviction alone never frees something on screen.
  refs: number = 1;
  released: boolean = false;
  // Never evicted. For the chat background: one full-screen bitmap that every
  // chat shares and that costs ~20ms to decode, so letting a long scroll push
  // it out of the LRU would just buy that cost back on the next chat open.
  pinned: boolean = false;

  constructor(pixelMap: image.PixelMap, bytes: number) {
    this.pixelMap = pixelMap;
    this.bytes = bytes;
  }
}

// 低内存/后台期间会临时收紧；回前台恢复到统一预算表里的 48MiB。
let budgetBytes: number = IMAGE_PIXEL_CACHE_MAX_BYTES;

// A decode occupies a worker thread and finishes by handing a bitmap to the
// render pipeline. Letting a fling queue up thirty of them at once means the
// rows that actually stopped on screen wait behind rows the user already went
// past. Three at a time keeps the pipe busy without building that backlog.
const MAX_ACTIVE_DECODES: number = 3;

class PendingDecode {
  req: PixelRequest;
  key: string;
  // How many components are still waiting. A row that scrolls away drops its
  // interest; at zero, a decode that has not started yet is dropped entirely —
  // which is the only point where cancelling actually saves work, since
  // createPixelMap itself cannot be interrupted.
  waiters: number = 1;
  started: boolean = false;
  resolvers: ((handle: PixelHandle | undefined) => void)[] = [];

  constructor(req: PixelRequest, key: string) {
    this.req = req;
    this.key = key;
  }
}

const cache: Map<string, PixelHandle> = new Map();
const pending: Map<string, PendingDecode> = new Map();
const queue: PendingDecode[] = [];
let activeDecodes: number = 0;
let usedBytes: number = 0;
// Component teardown can drop many image holders in one navigation frame. Calling
// PixelMap.release synchronously for every holder made those native FreeBufferHandle
// operations part of the chat-page exit frame. Keep reference accounting exact, but
// drain holder releases in small event-loop batches so native frees cannot pile up in
// one frame. Cache eviction still drops its own reference synchronously and therefore
// keeps the byte budget truthful.
const pendingHolderReleases: PixelHandle[] = [];
let holderReleaseTimer: number = -1;

function keyOf(req: PixelRequest): string {
  return `${req.path}@${Math.round(req.width)}x${Math.round(req.height)}`;
}

// Map iterates in insertion order, so the first live entry is the oldest.
// Re-inserting on every hit is what makes that order an LRU.
function touch(key: string, entry: PixelHandle): void {
  cache.delete(key);
  cache.set(key, entry);
}

function decRef(entry: PixelHandle): void {
  entry.refs--;
  if (entry.refs > 0 || entry.released) {
    return;
  }
  entry.released = true;
  try {
    entry.pixelMap.release();
  } catch (e) {
    logE(`pixelCache release failed: ${e}`);
  }
}

function drainHolderReleases(): void {
  holderReleaseTimer = -1;
  const count: number = Math.min(IMAGE_HOLDER_RELEASE_BATCH, pendingHolderReleases.length);
  for (let i = 0; i < count; i++) {
    const entry = pendingHolderReleases.shift();
    if (entry !== undefined) {
      decRef(entry);
    }
  }
  if (pendingHolderReleases.length > 0) {
    holderReleaseTimer = setTimeout(drainHolderReleases, 0);
  }
}

function evictDownTo(limit: number, maxEntries: number = Number.MAX_SAFE_INTEGER): number {
  let evicted: number = 0;
  for (const key of Array.from(cache.keys())) {
    if (usedBytes <= limit || evicted >= maxEntries) {
      return evicted;
    }
    const entry = cache.get(key);
    if (entry === undefined || entry.pinned) {
      continue;
    }
    cache.delete(key);
    usedBytes -= entry.bytes;
    evicted++;
    // Drops the cache's own reference. Anything still on screen survives on
    // the holders' references and is freed when the last one lets go.
    decRef(entry);
  }
  return evicted;
}

// Synchronous hit, for the first build pass of a row that has been shown
// before — going through a Promise there would blank the image for a frame.
export function cachedPixelMap(req: PixelRequest): PixelHandle | undefined {
  const key = keyOf(req);
  const entry = cache.get(key);
  if (entry === undefined) {
    return undefined;
  }
  touch(key, entry);
  return entry;
}

export function loadPixelMap(req: PixelRequest): Promise<PixelHandle | undefined> {
  if (req.path === '' || req.width <= 0 || req.height <= 0) {
    return Promise.resolve(undefined);
  }
  const key = keyOf(req);
  const hit = cache.get(key);
  if (hit !== undefined) {
    touch(key, hit);
    return Promise.resolve(hit);
  }
  // Several rows can ask for the same file in the same frame (an album, or a
  // row rebuilt mid-decode). One decode, shared.
  let task = pending.get(key);
  if (task === undefined) {
    task = new PendingDecode(req, key);
    pending.set(key, task);
    queue.push(task);
    pump();
  } else {
    task.waiters++;
  }
  const waiting = task;
  return new Promise<PixelHandle | undefined>((resolve): void => {
    waiting.resolvers.push(resolve);
  });
}

// Drop this component's interest in a decode. If nobody is left waiting and it
// never started, it leaves the queue and the work is genuinely skipped.
export function cancelPixelMap(req: PixelRequest): void {
  const key = keyOf(req);
  const task = pending.get(key);
  if (task === undefined) {
    return;
  }
  task.waiters--;
  if (task.waiters > 0 || task.started) {
    return;
  }
  const at = queue.indexOf(task);
  if (at >= 0) {
    queue.splice(at, 1);
  }
  pending.delete(key);
  for (const resolve of task.resolvers) {
    resolve(undefined);
  }
}

function settle(task: PendingDecode, handle: PixelHandle | undefined): void {
  pending.delete(task.key);
  for (const resolve of task.resolvers) {
    resolve(handle);
  }
}

// 这里曾经有一个"滑动中暂停解码"的闸门，实测是反效果：滑快了图片整段不显示，
// 而同一次抓取里 ProcessJank 一条都没有 —— 掉帧的前提本来就不成立。真正的开销
// 是解码跑在主线程上，已经由 pixelDecodeTask 挪进 TaskPool 解决。
function pump(): void {
  while (activeDecodes < MAX_ACTIVE_DECODES && queue.length > 0) {
    // First in, first out. Newest-first looked better during a fling — the
    // latest requests are the rows nearest the viewport — but it can starve an
    // early request indefinitely while new ones keep arriving, and a starved
    // request is a bubble that never draws its photo. Stale work is now
    // removed by cancel() rather than by being outrun, so the queue stays close
    // to the visible set and ordering does not have to compensate.
    const task = queue.shift();
    if (task === undefined) {
      return;
    }
    task.started = true;
    activeDecodes++;
    decode(task.req, task.key).then((handle: PixelHandle | undefined): void => {
      settle(task, handle);
    }).catch((): void => {
      settle(task, undefined);
    }).then((): void => {
      activeDecodes--;
      pump();
    });
  }
}

async function decode(req: PixelRequest, key: string): Promise<PixelHandle | undefined> {
  try {
    // Decoding runs on a TaskPool worker (see pixelDecodeTask): a device capture
    // showed every CreatePixelMap landing on the main tid, so two or three
    // photos entering the viewport in one frame spent ~40ms of that frame
    // decoding — the dropped frames seen while scrolling a media-heavy chat.
    // `await` alone does not move work off the thread; TaskPool does.
    const sendablePixelMap = await taskpool.execute(
      decodeSendable, req.path, req.width, req.height
    ) as sendableImage.PixelMap | undefined;
    if (sendablePixelMap === undefined) {
      return undefined;
    }
    const pixelMap: image.PixelMap = sendableImage.convertToPixelMap(sendablePixelMap);
    const decoded = await pixelMap.getImageInfo();
    // stride, not width: DMA rows are padded to a hardware alignment, and the
    // padding is real memory this budget has to account for.
    const bytes = Math.max(1, decoded.stride) * Math.max(1, decoded.size.height);
    const entry = new PixelHandle(pixelMap, bytes);
    cache.set(key, entry);
    usedBytes += bytes;
    // The extra reference covers the hand-off: eviction below (or any eviction
    // before the caller retains) would otherwise free the entry that this very
    // call is about to return. Dropped once the caller has had its chance.
    entry.refs++;
    evictDownTo(budgetBytes);
    setTimeout((): void => { decRef(entry); }, 0);
    return entry;
  } catch (e) {
    logE(`pixelCache decode(${req.path}) failed: ${e}`);
    return undefined;
  }
  // No ImageSource to release here any more — it is created and released inside
  // the TaskPool worker, on the thread that actually used it.
}

// A component that has put a PixelMap on screen retains it, and releases when
// it swaps it out or goes away. Taken on the handle rather than a key, so it
// works even for an entry the LRU has already dropped.
export function retainPixelMap(handle: PixelHandle): void {
  handle.refs++;
}

export function releasePixelMap(handle: PixelHandle): void {
  pendingHolderReleases.push(handle);
  if (holderReleaseTimer === -1) {
    holderReleaseTimer = setTimeout(drainHolderReleases, 0);
  }
}

// Keep this bitmap for the life of the process. Only worth it for something
// both expensive and reused everywhere; anything else should just take the
// normal LRU treatment.
export function pinPixelMap(handle: PixelHandle): void {
  if (!handle.pinned) {
    handle.pinned = true;
    handle.refs++;
  }
}

// 收紧后，新完成的解码也按新上限入账，防止切后台时在途任务把缓存重新灌满。
export function setPixelCacheBudget(bytes: number): void {
  budgetBytes = Math.max(0, Math.min(IMAGE_PIXEL_CACHE_MAX_BYTES, Math.floor(bytes)));
}

// 只回收 LRU 自己持有、且未钉住的引用。maxEntries 让生命周期回调可以分批做，
// 避免在主线程一次 release 几十张 PixelMap。
export function trimPixelCache(targetBytes: number = 0,
  maxEntries: number = Number.MAX_SAFE_INTEGER): number {
  const target: number = Math.max(0, Math.floor(targetBytes));
  const batch: number = Math.max(0, Math.floor(maxEntries));
  return evictDownTo(target, batch);
}

export function pixelCacheBytes(): number {
  return usedBytes;
}
