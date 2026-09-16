// 「已存本地」记录的纯逻辑（2026-09-15，下载中心设计稿的「仅缓存 / 已存本地」）。
//
// 用户把缓存里的文件存到相册或下载目录后，TDLib 并不知道。我们按源文件路径记一笔，下载中心据此打标记、
// 算「已存本地」占用。只是索引：相册里的副本被用户删了我们不知道，数字的含义是「存过多少」。

export const SAVED_LOCAL_CAP: number = 500;

export interface SavedLocalRecord {
  path: string;    // 源文件（TDLib 缓存里的）路径
  size: number;    // 字节
  savedAt: number; // 毫秒
}

// 同一路径只留一条，新存的排最前；超出上限丢最旧的。
export function upsertSavedLocal(list: SavedLocalRecord[], rec: SavedLocalRecord, cap: number): SavedLocalRecord[] {
  if (rec.path === '') {
    return list;
  }
  const rest: SavedLocalRecord[] = list.filter((r: SavedLocalRecord): boolean => r.path !== rec.path);
  return [rec, ...rest].slice(0, Math.max(1, cap));
}

export function removeSavedLocal(list: SavedLocalRecord[], path: string): SavedLocalRecord[] {
  return list.filter((r: SavedLocalRecord): boolean => r.path !== path);
}

export function savedLocalBytes(list: SavedLocalRecord[]): number {
  let total: number = 0;
  for (const r of list) {
    total += Math.max(0, r.size);
  }
  return total;
}

// 读坏了就当没有：只是索引，丢了不影响文件本身。
export function parseSavedLocal(json: string): SavedLocalRecord[] {
  if (json === '') {
    return [];
  }
  try {
    const arr = JSON.parse(json) as Array<Record<string, Object>>;
    if (!Array.isArray(arr)) {
      return [];
    }
    const out: SavedLocalRecord[] = [];
    for (const raw of arr) {
      const path = raw['path'] as string | undefined;
      if (typeof path !== 'string' || path === '') {
        continue;
      }
      const size = raw['size'] as number | undefined;
      const savedAt = raw['savedAt'] as number | undefined;
      out.push({
        path: path,
        size: size !== undefined && Number.isFinite(size) ? size : 0,
        savedAt: savedAt !== undefined && Number.isFinite(savedAt) ? savedAt : 0
      });
    }
    return out;
  } catch (e) {
    return [];
  }
}

export function serializeSavedLocal(list: SavedLocalRecord[]): string {
  return JSON.stringify(list);
}
