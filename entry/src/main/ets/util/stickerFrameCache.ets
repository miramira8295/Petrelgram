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
// highBudget：会话大表情放宽预算后的解码结果（抽帧步长不同），必须与普通档分开存，
// 否则会命中之前按普通档隔帧写下的缓存（见 util/webm/alphaCacheKey）。
export function frameCacheFileName(sourcePath: string, fileSize: number, bucketPx: number,
  highBudget: boolean = false): string {
  const slash: number = sourcePath.lastIndexOf('/');
  const base: string = slash < 0 ? sourcePath : sourcePath.substring(slash + 1);
  const dot: number = base.lastIndexOf('.');
  const stem: string = dot > 0 ? base.substring(0, dot) : base;
  return `${sanitize(stem)}_${fileSize}_${bucketPx}${highBudget ? 'h' : ''}_v${FRAME_CACHE_VERSION}.pgsf`;
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

// ── 按 Telegram 文件唯一 ID 存（2026-10-09） ─────────────────────────────
//
// 上面那种「源文件名 + 字节数」的身份要先有本地文件才能拼出来，也就是**下载完
// 才能查缓存**；TDLib 清理缓存（optimizeStorage 的默认 ttl）之后源文件没了，
// 帧缓存明明还在却用不上，只能重下、重解。remote.unique_id 跨账号、跨会话、
// 跨重新下载都不变，下载之前就能拿它来查：命中了就不下载、不解码。

const UID_PREFIX: string = 'u_';

export interface UidFrameCacheVariant {
  bucket: number;
  high: boolean;
}

export interface UidFrameCacheName extends UidFrameCacheVariant {
  uid: string;
}

// 索引里用的 ID 形态：与文件名里的一致（清理过字符、过长截尾），查和存都先过它。
export function normalizeFrameCacheUid(uid: string): string {
  return sanitize(uid);
}

export function uidFrameCacheFileName(uid: string, bucketPx: number, highBudget: boolean): string {
  return `${UID_PREFIX}${sanitize(uid)}_${bucketPx}${highBudget ? 'h' : ''}_v${FRAME_CACHE_VERSION}.pgsf`;
}

// uidFrameCacheFileName 的反函数。不是这个版本、不是按 ID 命名的，一律 null。
// uid 里本身可能有 '_'，所以从右边拆：最后两段是尺寸桶和版本。
export function parseUidFrameCacheFileName(name: string): UidFrameCacheName | null {
  const suffix: string = `_v${FRAME_CACHE_VERSION}.pgsf`;
  if (!name.startsWith(UID_PREFIX) || !name.endsWith(suffix)) {
    return null;
  }
  const body: string = name.substring(UID_PREFIX.length, name.length - suffix.length);
  const cut: number = body.lastIndexOf('_');
  if (cut <= 0) {
    return null;
  }
  const uid: string = body.substring(0, cut);
  let bucketText: string = body.substring(cut + 1);
  const high: boolean = bucketText.endsWith('h');
  if (high) {
    bucketText = bucketText.substring(0, bucketText.length - 1);
  }
  if (!/^[0-9]+$/.test(bucketText)) {
    return null;
  }
  const bucket: number = Number(bucketText);
  return bucket > 0 ? { uid: uid, bucket: bucket, high: high } : null;
}

// 从这个 ID 已有的几份缓存里挑一份来用：尺寸桶不小于要的（放大会糊），挑最接近的；
// 要高帧率那档（会话大表情）就只认高帧率档；普通贴纸两档都行，同尺寸先挑普通档
// （帧少、占内存少）。都不合适返回 null——宁可重新下载解码。
export function pickUidFrameCache(have: UidFrameCacheVariant[], wantBucket: number,
  wantHigh: boolean): UidFrameCacheVariant | null {
  let best: UidFrameCacheVariant | null = null;
  for (const v of have) {
    if (v.bucket < wantBucket || (wantHigh && !v.high)) {
      continue;
    }
    if (best === null || v.bucket < best.bucket || (v.bucket === best.bucket && best.high && !v.high)) {
      best = v;
    }
  }
  return best;
}
