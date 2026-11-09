// 缓存记录的纯逻辑（2026-09-15，下载中心「已缓存（未下完）」的数据来源）。
//
// TDLib 没有"列出缓存文件"的接口（td_api.tl 里只有 getFile / searchFileDownloads / getStorageStatistics 统计），
// 而边看边缓存的视频、「后台缓存」下的文件又不进下载管理器——不自己记一笔，下载中心就不知道它们存在。
// 这里只记"是哪个文件、来自哪条消息"，缓存了多少由下载中心打开时向 TDLib getFile 现查。

export const CACHE_REGISTRY_CAP: number = 300;

export interface CacheRecord {
  fileId: number;
  chatId: number;
  messageId: number;
  kind: string;       // util/downloadCenterModel 的 DC_KIND_*
  name: string;
  size: number;       // 总字节，0 = 未知
  mimeType: string;
  preview: string;
  // 用户点过「后台缓存」：播放结束、滑出可见窗口时不许被自动取消。一旦为真就保持为真。
  background: boolean;
  addedAt: number;    // 毫秒
  // 用户在下载中心暂停了这条后台缓存：重启应用后不自动续上。只由 withCachePaused 改，upsert 沿用旧值。
  paused?: boolean;
  // 用户对这一条点过「用流量继续」：「只在 Wi‑Fi 下后台缓存」对它不生效。只由 withCacheAllowCellular 改。
  allowCellular?: boolean;
}

function pickText(next: string, prev: string): string {
  return next !== '' ? next : prev;
}

function pickNumber(next: number, prev: number): number {
  return next > 0 ? next : prev;
}

// 同一 fileId 只留一条，最新登记的排最前；新记录缺的字段沿用旧的。超出上限丢最旧的。
export function upsertCacheRecord(list: CacheRecord[], rec: CacheRecord, cap: number): CacheRecord[] {
  if (rec.fileId === 0) {
    return list;
  }
  const prev: CacheRecord | undefined = list.find((r: CacheRecord): boolean => r.fileId === rec.fileId);
  const merged: CacheRecord = prev === undefined ? rec : {
    fileId: rec.fileId,
    chatId: pickNumber(rec.chatId, prev.chatId),
    messageId: pickNumber(rec.messageId, prev.messageId),
    kind: pickText(rec.kind, prev.kind),
    name: pickText(rec.name, prev.name),
    size: pickNumber(rec.size, prev.size),
    mimeType: pickText(rec.mimeType, prev.mimeType),
    preview: pickText(rec.preview, prev.preview),
    background: rec.background || prev.background,
    addedAt: rec.addedAt,
    paused: prev.paused,
    allowCellular: prev.allowCellular
  };
  const rest: CacheRecord[] = list.filter((r: CacheRecord): boolean => r.fileId !== rec.fileId);
  return [merged, ...rest].slice(0, Math.max(1, cap));
}

export function removeCacheRecord(list: CacheRecord[], fileId: number): CacheRecord[] {
  return list.filter((r: CacheRecord): boolean => r.fileId !== fileId);
}

function numberField(raw: Record<string, Object>, key: string): number {
  const v = raw[key] as number | undefined;
  return v !== undefined && Number.isFinite(v) ? v : 0;
}

function stringField(raw: Record<string, Object>, key: string): string {
  const v = raw[key] as string | undefined;
  return typeof v === 'string' ? v : '';
}

// 读坏了就当没有：缓存记录只是索引，丢了不影响文件本身。
export function parseCacheRecords(json: string): CacheRecord[] {
  if (json === '') {
    return [];
  }
  try {
    const arr = JSON.parse(json) as Array<Record<string, Object>>;
    if (!Array.isArray(arr)) {
      return [];
    }
    const out: CacheRecord[] = [];
    for (const raw of arr) {
      const fileId: number = numberField(raw, 'fileId');
      if (fileId <= 0) {
        continue;
      }
      out.push({
        fileId: fileId,
        chatId: numberField(raw, 'chatId'),
        messageId: numberField(raw, 'messageId'),
        kind: stringField(raw, 'kind'),
        name: stringField(raw, 'name'),
        size: numberField(raw, 'size'),
        mimeType: stringField(raw, 'mimeType'),
        preview: stringField(raw, 'preview'),
        background: (raw['background'] as boolean | undefined) === true,
        addedAt: numberField(raw, 'addedAt'),
        paused: (raw['paused'] as boolean | undefined) === true,
        allowCellular: (raw['allowCellular'] as boolean | undefined) === true
      });
    }
    return out;
  } catch (e) {
    return [];
  }
}

export function serializeCacheRecords(list: CacheRecord[]): string {
  return JSON.stringify(list);
}

function copyCacheRecord(r: CacheRecord): CacheRecord {
  return {
    fileId: r.fileId, chatId: r.chatId, messageId: r.messageId, kind: r.kind, name: r.name, size: r.size,
    mimeType: r.mimeType, preview: r.preview, background: r.background, addedAt: r.addedAt, paused: r.paused,
    allowCellular: r.allowCellular
  };
}

// 改暂停标记，其余字段不动；找不到这条就原样返回。
export function withCachePaused(list: CacheRecord[], fileId: number, paused: boolean): CacheRecord[] {
  return list.map((r: CacheRecord): CacheRecord => {
    if (r.fileId !== fileId) {
      return r;
    }
    const next: CacheRecord = copyCacheRecord(r);
    next.paused = paused;
    return next;
  });
}

// 改「用流量继续」标记，其余字段不动。
export function withCacheAllowCellular(list: CacheRecord[], fileId: number, allow: boolean): CacheRecord[] {
  return list.map((r: CacheRecord): CacheRecord => {
    if (r.fileId !== fileId) {
      return r;
    }
    const next: CacheRecord = copyCacheRecord(r);
    next.allowCellular = allow;
    return next;
  });
}
