import { fileIo } from '@kit.CoreFileKit';
import { appFilesDir } from '../tdkit/Globals';
import { FrameCacheEntry, planFrameCachePrune } from '../util/stickerFrameCache';

// TGS 帧缓存的目录与淘汰（2026-10-10）。读写在原生侧（cpp/tgs_frame_cache.cpp），
// 这里只给目录、按修改时间删最老的。和 webm 的 sticker_frames 分开放、分开算预算：
// 两边的文件格式不同，混在一起淘汰会互相挤占。
const TGS_FRAME_CACHE_DIR: string = 'tgs_frames';
// 256px 一张 90 帧压缩后约两三 MB；表情状态那种小图标只有几百 KB。
export const TGS_FRAME_CACHE_MAX_BYTES: number = 128 * 1024 * 1024;
// 去抖：一屏贴纸连着打开几十次，每次都 listFile + stat 一遍不值得。
const PRUNE_DELAY_MS: number = 30000;

let dirPath: string = '';
let prunePending: boolean = false;

export function tgsFrameCacheDir(): string {
  if (dirPath !== '') {
    return dirPath;
  }
  const base: string = appFilesDir();
  if (base === '') {
    return '';
  }
  const dir: string = `${base}/${TGS_FRAME_CACHE_DIR}`;
  try {
    if (!fileIo.accessSync(dir)) {
      fileIo.mkdirSync(dir);
    }
    dirPath = dir;
  } catch (e) {
    console.error(`tgsFrameCacheDisk: cache dir failed: ${e}`);
  }
  return dirPath;
}

export function scheduleTgsFrameCachePrune(): void {
  if (prunePending) {
    return;
  }
  prunePending = true;
  setTimeout((): void => {
    prunePending = false;
    pruneTgsFrameCache();
  }, PRUNE_DELAY_MS);
}

async function pruneTgsFrameCache(): Promise<void> {
  const dir: string = tgsFrameCacheDir();
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
    const doomed: string[] = planFrameCachePrune(entries, TGS_FRAME_CACHE_MAX_BYTES);
    for (const name of doomed) {
      try {
        await fileIo.unlink(`${dir}/${name}`);
      } catch (e) {
        console.error(`tgsFrameCacheDisk: prune unlink failed: ${e}`);
      }
    }
    if (doomed.length > 0) {
      console.warn(`[TgsCache] pruned ${doomed.length} file(s)`);
    }
  } catch (e) {
    console.error(`tgsFrameCacheDisk: prune failed: ${e}`);
  }
}
