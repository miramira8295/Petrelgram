import { zlib } from '@kit.BasicServicesKit';
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
