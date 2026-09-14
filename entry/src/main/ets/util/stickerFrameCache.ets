// 贴纸帧缓存的命名与淘汰规则。纯数据，可单测；真正的读写在原生侧
// （cpp/sticker_frame_cache.cpp），落盘的是 zlib 压过的 RGBA 帧。
//
// 【为什么值得落盘】内存那份只有 32MiB、单段上限 12MiB，同时驻留不下三段；
// 贴纸面板一屏几十张，LRU 一抖就要重走「读文件 → 拆 WebM → libvpx 逐帧软解」。
// 落盘之后第二次只剩「读文件 → 解压」。

// 缓存文件的格式版本。改了原生那边的排布就 +1——旧文件名认不出来，等于自动失效。
export const FRAME_CACHE_VERSION: number = 1;
export const FRAME_CACHE_DIR: string = 'sticker_frames';
// 磁盘预算。压缩后一段贴纸通常几百 KB 到两三 MB。
export const FRAME_CACHE_MAX_BYTES: number = 96 * 1024 * 1024;

// 文件名里只留这些字符，其余一律换成 '_'：源文件名来自 TDLib，不该假设它
// 只有安全字符。
function sanitize(name: string): string {
  let out: string = '';
  for (let i = 0; i < name.length; i++) {
    const ch: string = name.charAt(i);
    const ok: boolean = (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z')
      || (ch >= '0' && ch <= '9') || ch === '-' || ch === '_';
    out += ok ? ch : '_';
  }
  return out.length > 64 ? out.substring(out.length - 64) : out;
}

// 身份 = 源文件名 + 字节数 + 显示尺寸桶 + 格式版本。
//
// 带**字节数**是因为 TDLib 会复用文件名：同名文件换了内容（重新下载、清理后
// 重下）时，长度几乎必然不同，缓存随之失效。带**尺寸桶**是因为解码是按显示
// 尺寸做的，桶不同就是另一份像素。
export function frameCacheFileName(sourcePath: string, fileSize: number, bucketPx: number): string {
  const slash: number = sourcePath.lastIndexOf('/');
  const base: string = slash < 0 ? sourcePath : sourcePath.substring(slash + 1);
  const dot: number = base.lastIndexOf('.');
  const stem: string = dot > 0 ? base.substring(0, dot) : base;
  return `${sanitize(stem)}_${fileSize}_${bucketPx}_v${FRAME_CACHE_VERSION}.pgsf`;
}

export interface FrameCacheEntry {
  name: string;
  bytes: number;
  // 最后修改时间（毫秒）。用它当"最近用过"的近似：命中时原生只读不写，
  // 所以严格说这是"最后写入"——对淘汰来说够了，反正重解一次也只是几十毫秒。
  mtimeMs: number;
}

// 超预算时该删哪些（从最老的开始）。返回要删的文件名，顺序即删除顺序。
export function planFrameCachePrune(
  entries: FrameCacheEntry[], budgetBytes: number = FRAME_CACHE_MAX_BYTES
): string[] {
  let total: number = 0;
  for (const e of entries) {
    total += e.bytes;
  }
  if (total <= budgetBytes) {
    return [];
  }
  const sorted: FrameCacheEntry[] = entries.slice()
    .sort((a: FrameCacheEntry, b: FrameCacheEntry): number => a.mtimeMs - b.mtimeMs);
  const doomed: string[] = [];
  for (const e of sorted) {
    if (total <= budgetBytes) {
      break;
    }
    doomed.push(e.name);
    total -= e.bytes;
  }
  return doomed;
}
