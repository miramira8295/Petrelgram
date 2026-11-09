import { zlib } from '@kit.BasicServicesKit';
import { fileIo } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { logE } from './log';

const CHUNK: number = 256 * 1024;

// Decoded-JSON cache: scrolling a sticker grid re-mounts the same cells over
// and over — without this every re-entry pays gunzip + decode again.
const TGS_CACHE_MAX: number = 80;
const tgsCache: Map<string, string> = new Map();

function cachePut(path: string, json: string): void {
  if (tgsCache.size >= TGS_CACHE_MAX) {
    // Map iterates in insertion order — evict the oldest entry.
    const oldest = tgsCache.keys().next().value as string | undefined;
    if (oldest !== undefined) {
      tgsCache.delete(oldest);
    }
  }
  tgsCache.set(path, json);
}

// Decompress a Telegram .tgs sticker (gzipped Lottie JSON) into the JSON text.
// Returns '' on any failure so callers can fall back to the static thumbnail.
export async function gunzipTgs(tgsPath: string): Promise<string> {
  const cached = tgsCache.get(tgsPath);
  if (cached !== undefined) {
    tgsCache.delete(tgsPath); // refresh recency (re-insert at the back)
    tgsCache.set(tgsPath, cached);
    return cached;
  }
  try {
    const gz = zlib.createGZipSync();
    await gz.gzopen(tgsPath, 'rb');
    const chunks: Uint8Array[] = [];
    let n = 0;
    do {
      const buf = new ArrayBuffer(CHUNK);
      n = await gz.gzread(buf);
      if (n > 0) {
        chunks.push(new Uint8Array(buf, 0, n).slice());
      }
    } while (n === CHUNK);
    await gz.gzclose();
    let total = 0;
    for (const c of chunks) {
      total += c.length;
    }
    const all = new Uint8Array(total);
    let off = 0;
    for (const c of chunks) {
      all.set(c, off);
      off += c.length;
    }
    const json = util.TextDecoder.create('utf-8').decodeToString(all);
    if (json !== '') {
      cachePut(tgsPath, json);
    }
    return json;
  } catch (e) {
    logE(`gunzipTgs(${tgsPath}) failed: ${e}`);
    return '';
  }
}

// 图案壁纸的文档是 .tgv（gzip 过的 SVG），ArkUI 的 Image 读不了。就地解压成同名
// .svg 并返回新路径；不是 .tgv 就原样返回。
//
// 【为什么抽出来】ChatBackgroundStore 和「APP 壁纸槽位选原生图案壁纸」这两条路
// 都要它。原来只有 store 里有一份私有实现，另一条路照抄一遍必然走岔——而这种岔
// 的表现是"同一张图案壁纸在聊天里能画、在主界面上是空白"。
//
// 结果记在模块级 Map 里：同一张图案在一次运行里会被反复请求，解压一次就够。
// TDLib 的缓存被清掉时 .svg 也跟着没了，access 那一步会重新生成。
const inflatedPatterns: Map<string, string> = new Map<string, string>();

export async function inflateTgvIfNeeded(path: string): Promise<string> {
  if (!path.endsWith('.tgv')) {
    return path;
  }
  const memo: string | undefined = inflatedPatterns.get(path);
  if (memo !== undefined) {
    return memo;
  }
  const svgPath: string = `${path}.svg`;
  try {
    if (await fileIo.access(svgPath)) {
      inflatedPatterns.set(path, svgPath);
      return svgPath;
    }
    const svg: string = await gunzipTgs(path);
    if (svg === '') {
      return '';
    }
    const file = await fileIo.open(svgPath,
      fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
    await fileIo.write(file.fd, svg);
    await fileIo.close(file);
    inflatedPatterns.set(path, svgPath);
    return svgPath;
  } catch (e) {
    logE(`inflateTgvIfNeeded(${path}) failed: ${e}`);
    return '';
  }
}
