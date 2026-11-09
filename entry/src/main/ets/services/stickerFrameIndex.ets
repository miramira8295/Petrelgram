import { fileIo } from '@kit.CoreFileKit';
import { appFilesDir } from '../tdkit/Globals';
import {
  FRAME_CACHE_DIR, normalizeFrameCacheUid, parseUidFrameCacheFileName, pickUidFrameCache,
  uidFrameCacheFileName, UidFrameCacheName, UidFrameCacheVariant
} from '../util/stickerFrameCache';
import { alphaSizeBucket } from '../util/webm/alphaCacheKey';

// 按唯一 ID 存的贴纸帧缓存的内存索引（2026-10-09）。
//
// 「下载之前先查缓存」要在渲染路径和下载路径上同步回答，不能每次去 stat 文件：
// 启动后扫一遍目录建表，之后写入 / 淘汰 / 读坏时随手更新。表没建好之前一律答
// 「没有」，照旧下载——最坏只是少省一次，不会出错。

const index: Map<string, UidFrameCacheVariant[]> = new Map();
let dirPath: string = '';
let warming: Promise<void> | null = null;

export function stickerFrameCacheDir(): string {
  if (dirPath !== '') {
    return dirPath;
  }
  const base: string = appFilesDir();
  if (base === '') {
    return '';
  }
  const dir: string = `${base}/${FRAME_CACHE_DIR}`;
  try {
    if (!fileIo.accessSync(dir)) {
      fileIo.mkdirSync(dir);
    }
    dirPath = dir;
  } catch (e) {
    console.error(`stickerFrameIndex: cache dir failed: ${e}`);
  }
  return dirPath;
}

function add(parsed: UidFrameCacheName): void {
  const list: UidFrameCacheVariant[] = index.get(parsed.uid) ?? [];
  if (!list.some((v: UidFrameCacheVariant): boolean => v.bucket === parsed.bucket && v.high === parsed.high)) {
    index.set(parsed.uid, [...list, { bucket: parsed.bucket, high: parsed.high }]);
  }
}

// 扫一遍缓存目录。多次调用只扫一次。
export function warmStickerFrameIndex(): Promise<void> {
  if (warming !== null) {
    return warming;
  }
  warming = (async (): Promise<void> => {
    const dir: string = stickerFrameCacheDir();
    if (dir === '') {
      warming = null;   // 应用目录还没就绪（启动太早）：下次再扫
      return;
    }
    try {
      const names: string[] = await fileIo.listFile(dir);
      for (const name of names) {
        const parsed: UidFrameCacheName | null = parseUidFrameCacheFileName(name);
        if (parsed !== null) {
          add(parsed);
        }
      }
      console.warn(`[AlphaDiag] frame index warmed ids=${index.size}`);
    } catch (e) {
      console.error(`stickerFrameIndex: list failed: ${e}`);
    }
  })();
  return warming;
}

// 原生那边写完一份按 ID 命名的缓存之后调用。
export function noteFrameCacheWritten(fileName: string): void {
  const parsed: UidFrameCacheName | null = parseUidFrameCacheFileName(fileName);
  if (parsed !== null) {
    add(parsed);
  }
}

// 淘汰或读坏删掉之后调用。不是按 ID 命名的文件名直接忽略。
export function noteFrameCacheRemoved(fileName: string): void {
  const parsed: UidFrameCacheName | null = parseUidFrameCacheFileName(fileName);
  if (parsed === null) {
    return;
  }
  const list: UidFrameCacheVariant[] = index.get(parsed.uid) ?? [];
  const kept: UidFrameCacheVariant[] = list.filter((v: UidFrameCacheVariant): boolean =>
    !(v.bucket === parsed.bucket && v.high === parsed.high));
  if (kept.length === 0) {
    index.delete(parsed.uid);
  } else {
    index.set(parsed.uid, kept);
  }
}

// 这个 ID、这个显示尺寸有没有能直接用的缓存；有就返回完整路径，没有返回 ''。
export function cachedFramesPathFor(uid: string, boxPx: number, highBudget: boolean): string {
  if (uid === '') {
    return '';
  }
  const key: string = normalizeFrameCacheUid(uid);
  const pick: UidFrameCacheVariant | null =
    pickUidFrameCache(index.get(key) ?? [], alphaSizeBucket(boxPx), highBudget);
  const dir: string = stickerFrameCacheDir();
  if (pick === null || dir === '') {
    return '';
  }
  return `${dir}/${uidFrameCacheFileName(key, pick.bucket, pick.high)}`;
}

// 渲染 / 下载两条路上用：命中了就不必等源文件。
export function stickerFramesCached(uid: string, boxPx: number, highBudget: boolean): boolean {
  return cachedFramesPathFor(uid, boxPx, highBudget) !== '';
}

// 解码时把结果写到哪（按 ID 命名）。
export function uidFramesWritePath(uid: string, bucketPx: number, highBudget: boolean): string {
  const dir: string = stickerFrameCacheDir();
  return uid === '' || dir === '' ? '' : `${dir}/${uidFrameCacheFileName(uid, bucketPx, highBudget)}`;
}
