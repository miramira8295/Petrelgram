import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { accountRegistry } from '../tdkit/AccountRegistry';
import {
  CACHE_REGISTRY_CAP, CacheRecord, parseCacheRecords, removeCacheRecord, serializeCacheRecords, upsertCacheRecord,
  withCacheAllowCellular, withCachePaused
} from '../util/cacheRegistryModel';
import { logE, logI } from '../util/log';

// 缓存记录的存取（2026-09-15）。为什么要有它见 util/cacheRegistryModel 的文件头。
//
// 持久化用 preferences：条目上限 300、每条几百字节，一整串 JSON 足够；写入去抖，连着登记不会连着落盘。
// 初始化前登记的条目先留在内存里，初始化时并进磁盘上的旧记录，不会被旧值盖掉。
//
// 【按账号分开】fileId 只在一个 TDLib 实例里有效，同一个数字在另一个账号里是别的文件。记录按账号槽位各存一份
// （键 records@<槽位>）；每次存取先核对当前槽位，切过账号就把上一个账号的立刻落盘、换成当前账号的，
// 「正在后台缓存」的集合一并清空。老版本不分账号存的 records 并进第一次加载到的那个账号。

const STORE_NAME: string = 'petrel_cache_registry';
const LEGACY_KEY_RECORDS: string = 'records';
const PERSIST_DEBOUNCE_MS: number = 400;

let records: CacheRecord[] = [];
let recordsSlot: string = '';
let prefs: preferences.Preferences | null = null;
let loading: Promise<void> | null = null;
let persistTimer: number = -1;
// 正在「后台缓存」的文件：MessageStore 的自动取消（播放结束、滑出可见窗口）必须跳过它们。
const backgroundActive: Set<number> = new Set<number>();

function slotKey(slot: string): string {
  return `records@${slot}`;
}

export function currentCacheSlot(): string {
  return accountRegistry.activeSlotId();
}

export function ensureCacheRegistry(context: common.Context): Promise<void> {
  if (prefs !== null) {
    syncSlot();
    return Promise.resolve();
  }
  if (loading !== null) {
    return loading;
  }
  loading = preferences.getPreferences(context, STORE_NAME).then((p: preferences.Preferences): void => {
    prefs = p;
    const slot: string = currentCacheSlot();
    let merged: CacheRecord[] = loadSlotRecords(p, slot);
    // 内存里的是更新的：倒着并进去，保持它们原来的先后。
    for (const r of records.slice().reverse()) {
      merged = upsertCacheRecord(merged, r, CACHE_REGISTRY_CAP);
    }
    records = merged;
    recordsSlot = slot;
    logI(`[DC] registry loaded ${records.length} record(s)`);
    schedulePersist();
  }).catch((e: Object): void => {
    logE(`CacheRegistry init failed: ${JSON.stringify(e)}`);
    loading = null;
  });
  return loading;
}

// 读一个账号的记录；老版本不分账号存的那份并进来之后删掉。
function loadSlotRecords(p: preferences.Preferences, slot: string): CacheRecord[] {
  let list: CacheRecord[] = parseCacheRecords(p.getSync(slotKey(slot), '') as string);
  const legacy: string = p.getSync(LEGACY_KEY_RECORDS, '') as string;
  if (legacy !== '') {
    for (const r of parseCacheRecords(legacy).reverse()) {
      list = upsertCacheRecord(list, r, CACHE_REGISTRY_CAP);
    }
    p.deleteSync(LEGACY_KEY_RECORDS);
  }
  return list;
}

// 切过账号：上一个账号的记录立刻落盘，换成当前账号的。
function syncSlot(): void {
  const p: preferences.Preferences | null = prefs;
  if (p === null) {
    return;
  }
  const slot: string = currentCacheSlot();
  if (slot === recordsSlot) {
    return;
  }
  try {
    if (recordsSlot !== '') {
      p.putSync(slotKey(recordsSlot), serializeCacheRecords(records));
    }
    records = loadSlotRecords(p, slot);
    p.flush().catch((e: Object): void => { logE(`CacheRegistry flush failed: ${JSON.stringify(e)}`); });
  } catch (e) {
    logE(`CacheRegistry account switch failed: ${e}`);
    records = [];
  }
  recordsSlot = slot;
  backgroundActive.clear();
  logI(`[DC] registry switched account (${records.length} record(s))`);
}

export function cachedMediaRecords(): CacheRecord[] {
  syncSlot();
  return records.slice();
}

export function cacheRecordFor(fileId: number): CacheRecord | undefined {
  syncSlot();
  return records.find((r: CacheRecord): boolean => r.fileId === fileId);
}

export function noteCachedMedia(rec: CacheRecord): void {
  syncSlot();
  logI(`[DC] note file=${rec.fileId} kind=${rec.kind} bg=${rec.background} ready=${prefs !== null}`);
  records = upsertCacheRecord(records, rec, CACHE_REGISTRY_CAP);
  schedulePersist();
}

export function forgetCachedMedia(fileId: number): void {
  syncSlot();
  records = removeCacheRecord(records, fileId);
  backgroundActive.delete(fileId);
  schedulePersist();
}

// 用户在下载中心暂停 / 继续了一条后台缓存：落盘，重启后据此决定续不续（services/BackgroundCache）。
export function setCachePaused(fileId: number, paused: boolean): void {
  syncSlot();
  records = withCachePaused(records, fileId, paused);
  schedulePersist();
}

// 「用流量继续」：这一条不再受「只在 Wi‑Fi 下后台缓存」限制。
export function setCacheAllowCellular(fileId: number, allow: boolean): void {
  syncSlot();
  records = withCacheAllowCellular(records, fileId, allow);
  schedulePersist();
}

export function setBackgroundCaching(fileId: number, active: boolean): void {
  syncSlot();
  if (active) {
    backgroundActive.add(fileId);
  } else {
    backgroundActive.delete(fileId);
  }
}

export function isBackgroundCaching(fileId: number): boolean {
  syncSlot();
  return backgroundActive.has(fileId);
}

export function backgroundCachingFileIds(): number[] {
  syncSlot();
  return Array.from(backgroundActive);
}

function schedulePersist(): void {
  if (prefs === null || persistTimer !== -1) {
    return;
  }
  persistTimer = setTimeout((): void => {
    persistTimer = -1;
    const p: preferences.Preferences | null = prefs;
    if (p === null || recordsSlot === '') {
      return;
    }
    try {
      p.putSync(slotKey(recordsSlot), serializeCacheRecords(records));
      p.flush().catch((e: Object): void => { logE(`CacheRegistry flush failed: ${JSON.stringify(e)}`); });
    } catch (e) {
      logE(`CacheRegistry persist failed: ${e}`);
    }
  }, PERSIST_DEBOUNCE_MS);
}
