// util/videoPoster 的磁盘那一半：内存表 + 按**路径**索引的旁路通道 + 串行抽帧队列。
//
// 【为什么按路径索引而不是 fileId】mediaThumbChannel 是按 TDLib 的 fileId 索引的，
// 而下载中心磁盘扫出来的条目 fileId 恒为 0（没有「路径 → fileId」的接口）。本地文件
// 的身份只有路径，所以这条通道按路径走。形状与 mediaThumbChannel 逐条对齐：
// 取现值 / 订阅 / 发布三件套，组件自己订阅、自己换图，海报落地不会导致行重建。
//
// 【为什么要串行】抽帧是解码（AVImageGenerator）。一滚动就并发几十个，等于拿解码器
// 去抢资源；而用户真正在看的只有可视区那几格。所以：一次只抽一个，其余排队。
// 调用点全在 LazyForEach 的可视格里，天然只为看得见的条目排队。

import { fileIo } from '@kit.CoreFileKit';
import { extractFirstFrame } from './livePhotoSave';
import { VIDEO_POSTER_DIR, posterPathFor, posterSignature } from './videoPoster';
import { logE } from './log';

interface PosterJob {
  videoPath: string;
  dest: string;
}

// 进程级：同一个文件在列表里、查看器里都是同一张海报。
const posters: Map<string, string> = new Map<string, string>();
const subs: Map<string, Set<(path: string) => void>> = new Map<string, Set<(path: string) => void>>();
const queued: Set<string> = new Set<string>();
const queue: PosterJob[] = [];
let running: boolean = false;
let cacheRoot: string = '';
let dirReady: boolean = false;

// 由页面在 aboutToAppear 里调一次（组件自己不去取 context）。
export function initVideoPosterStore(cacheDir: string): void {
  if (cacheDir !== '' && cacheRoot !== cacheDir) {
    cacheRoot = cacheDir;
    dirReady = false;
  }
}

export function posterFor(videoPath: string): string {
  return posters.get(videoPath) ?? '';
}

export function subscribePoster(videoPath: string, cb: (path: string) => void): () => void {
  let listeners: Set<(path: string) => void> | undefined = subs.get(videoPath);
  if (listeners === undefined) {
    listeners = new Set<(path: string) => void>();
    subs.set(videoPath, listeners);
  }
  listeners.add(cb);
  return (): void => {
    const current: Set<(path: string) => void> | undefined = subs.get(videoPath);
    if (current !== undefined) {
      current.delete(cb);
      if (current.size === 0) {
        subs.delete(videoPath);
      }
    }
  };
}

function publish(videoPath: string, poster: string): void {
  if (poster === '' || posters.get(videoPath) === poster) {
    return;
  }
  posters.set(videoPath, poster);
  const listeners: Set<(path: string) => void> | undefined = subs.get(videoPath);
  if (listeners !== undefined) {
    listeners.forEach((cb: (path: string) => void): void => cb(poster));
  }
}

// 要一张海报。命中内存/磁盘就地发布；否则排队抽帧。多次请求同一个文件是幂等的
// （复用的行每次 aboutToReuse 都会来一次）。
export function requestPoster(videoPath: string, size: number, mtimeMs: number): void {
  if (videoPath === '' || cacheRoot === '' || posters.has(videoPath) || queued.has(videoPath)) {
    return;
  }
  const dest: string = posterPathFor(cacheRoot, posterSignature(videoPath, size, mtimeMs));
  try {
    if (fileIo.accessSync(dest)) {
      // 上次启动抽过了。**只缓存命中结果**：未命中不写进表，否则刚写好的那张会被
      // 负缓存挡住（教训见 util/chatBackgroundRaster.cachedRaster）。
      publish(videoPath, dest);
      return;
    }
  } catch (e) {
    // 盘上没有或不可读都按未命中处理，重新抽即可。
  }
  queued.add(videoPath);
  queue.push({ videoPath: videoPath, dest: dest });
  pump();
}

function ensureDir(): boolean {
  if (dirReady) {
    return true;
  }
  const dir: string = `${cacheRoot}/${VIDEO_POSTER_DIR}`;
  try {
    if (!fileIo.accessSync(dir)) {
      fileIo.mkdirSync(dir, true);
    }
    dirReady = true;
    return true;
  } catch (e) {
    logE(`videoPosterStore.ensureDir ${dir} failed: ${e}`);
    return false;
  }
}

function pump(): void {
  if (running || queue.length === 0) {
    return;
  }
  const job: PosterJob | undefined = queue.shift();
  if (job === undefined) {
    return;
  }
  if (!ensureDir()) {
    queued.delete(job.videoPath);
    return;
  }
  running = true;
  extractFirstFrame(job.videoPath, job.dest).then((ok: boolean): void => {
    queued.delete(job.videoPath);
    if (ok) {
      publish(job.videoPath, job.dest);
    }
  }).catch((e: Object): void => {
    queued.delete(job.videoPath);
    logE(`videoPosterStore.extract ${job.videoPath} failed: ${JSON.stringify(e)}`);
  }).finally((): void => {
    running = false;
    pump();
  });
}
