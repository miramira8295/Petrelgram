import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { fileIo as fs } from '@kit.CoreFileKit';
import {
  parseSavedLocal, SAVED_LOCAL_CAP, SavedLocalRecord, savedLocalBytes, serializeSavedLocal, upsertSavedLocal
} from '../util/savedLocalModel';
import { logE } from '../util/log';

// 「已存本地」记录的存取（2026-09-15）。为什么要有它见 util/savedLocalModel 的文件头。
// 记录的入口在 util/mediaSaver（存相册 / 另存为 / 存下载目录成功之后），所以聊天里存的也算数。
// 持久化用 preferences，写入去抖；初始化前记下的先留在内存里，初始化时并进磁盘上的旧记录。

const STORE_NAME: string = 'petrel_saved_local';
const KEY_RECORDS: string = 'records';
const PERSIST_DEBOUNCE_MS: number = 400;

let records: SavedLocalRecord[] = [];
let paths: Set<string> = new Set<string>();
let prefs: preferences.Preferences | null = null;
let loading: Promise<void> | null = null;
let persistTimer: number = -1;
const listeners: Set<() => void> = new Set<() => void>();

function reindex(): void {
  paths = new Set<string>(records.map((r: SavedLocalRecord): string => r.path));
}

function notifyListeners(): void {
  listeners.forEach((listener: () => void): void => {
    try {
      listener();
    } catch (e) {
      logE(`SavedLocalRegistry listener failed: ${e}`);
    }
  });
}

export function ensureSavedLocalRegistry(context: common.Context): Promise<void> {
  if (prefs !== null) {
    return Promise.resolve();
  }
  if (loading !== null) {
    return loading;
  }
  loading = preferences.getPreferences(context, STORE_NAME).then((p: preferences.Preferences): void => {
    prefs = p;
    let merged: SavedLocalRecord[] = parseSavedLocal(p.getSync(KEY_RECORDS, '') as string);
    // 内存里的是更新的：倒着并进去，保持它们原来的先后。
    for (const r of records.slice().reverse()) {
      merged = upsertSavedLocal(merged, r, SAVED_LOCAL_CAP);
    }
    records = merged;
    reindex();
    schedulePersist();
    notifyListeners();
  }).catch((e: Object): void => {
    logE(`SavedLocalRegistry init failed: ${JSON.stringify(e)}`);
    loading = null;
  });
  return loading;
}

export function noteSavedLocal(context: common.Context, path: string): void {
  if (path === '') {
    return;
  }
  let size: number = 0;
  try {
    size = fs.statSync(path).size;
  } catch (e) {
    size = 0;
  }
  records = upsertSavedLocal(records, { path: path, size: size, savedAt: Date.now() }, SAVED_LOCAL_CAP);
  reindex();
  notifyListeners();
  if (prefs === null) {
    ensureSavedLocalRegistry(context);
  } else {
    schedulePersist();
  }
}

export function isSavedLocal(path: string): boolean {
  return path !== '' && paths.has(path);
}

export function savedLocalTotalBytes(): number {
  return savedLocalBytes(records);
}

export function subscribeSavedLocal(listener: () => void): () => void {
  listeners.add(listener);
  return (): void => {
    listeners.delete(listener);
  };
}

function schedulePersist(): void {
  if (prefs === null || persistTimer !== -1) {
    return;
  }
  persistTimer = setTimeout((): void => {
    persistTimer = -1;
    const p: preferences.Preferences | null = prefs;
    if (p === null) {
      return;
    }
    try {
      p.putSync(KEY_RECORDS, serializeSavedLocal(records));
      p.flush().catch((e: Object): void => { logE(`SavedLocalRegistry flush failed: ${JSON.stringify(e)}`); });
    } catch (e) {
      logE(`SavedLocalRegistry persist failed: ${e}`);
    }
  }, PERSIST_DEBOUNCE_MS);
}
