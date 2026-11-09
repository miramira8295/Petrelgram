import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { accountRegistry } from '../tdkit/AccountRegistry';
import {
  addTrackToCollection, createMusicCollection, deleteMusicCollection, MusicCollection,
  parseMusicCollections, removeTrackFromCollection, renameMusicCollection, serializeMusicCollections,
  toggleTrackInCollection
} from '../util/musicCollectionModel';
import { logE } from '../util/log';

// 「我的合集」的存取（2026-09-18，音乐中心）。数据模型与全部判断在 util/musicCollectionModel，
// 这里只管三件事：按账号读写 preferences、写入去抖、变更广播。
//
// 【为什么是模块级单例】合集是**账号级**的东西（换会话不变、换页面不丢），和 FavoriteStickers
// 同一类；挂在某个页面或 store 实例上，退出那个页面就得重新读盘。
//
// 【为什么按槽位分键】多账号共用一个 preferences 文件，键里带 slot（同 CacheRegistry 的
// records@<slot>）。切账号时 syncSlot() 换出另一份，不会把甲的合集显示给乙。

const STORE_NAME: string = 'petrel_music_collections';
const PERSIST_DEBOUNCE_MS: number = 400;

let collections: MusicCollection[] = [];
let loadedSlot: string = '';
let prefs: preferences.Preferences | null = null;
let loading: Promise<void> | null = null;
let persistTimer: number = -1;
const listeners: Set<() => void> = new Set<() => void>();

function slotKey(slot: string): string {
  return `collections@${slot}`;
}

function notifyListeners(): void {
  listeners.forEach((listener: () => void): void => {
    try {
      listener();
    } catch (e) {
      logE(`MusicCollectionStore listener failed: ${e}`);
    }
  });
}

function readSlot(p: preferences.Preferences, slot: string): MusicCollection[] {
  return parseMusicCollections(p.getSync(slotKey(slot), '') as string);
}

function schedulePersist(): void {
  const p: preferences.Preferences | null = prefs;
  if (p === null) {
    return;
  }
  if (persistTimer !== -1) {
    clearTimeout(persistTimer);
  }
  const slot: string = loadedSlot;
  persistTimer = setTimeout((): void => {
    persistTimer = -1;
    p.putSync(slotKey(slot), serializeMusicCollections(collections));
    p.flush().catch((e: Object): void => {
      logE(`MusicCollectionStore flush failed: ${JSON.stringify(e)}`);
    });
  }, PERSIST_DEBOUNCE_MS);
}

// 账号变了就换一份。**先把手上这份落盘**，否则切账号会吞掉去抖窗口里的最后一次改动。
function syncSlot(): void {
  const p: preferences.Preferences | null = prefs;
  const slot: string = accountRegistry.activeSlotId();
  if (p === null || slot === loadedSlot) {
    return;
  }
  if (persistTimer !== -1) {
    clearTimeout(persistTimer);
    persistTimer = -1;
    p.putSync(slotKey(loadedSlot), serializeMusicCollections(collections));
  }
  loadedSlot = slot;
  collections = readSlot(p, slot);
  notifyListeners();
}

export function ensureMusicCollections(context: common.Context): Promise<void> {
  if (prefs !== null) {
    syncSlot();
    return Promise.resolve();
  }
  if (loading !== null) {
    return loading;
  }
  loading = preferences.getPreferences(context, STORE_NAME).then((p: preferences.Preferences): void => {
    prefs = p;
    loadedSlot = accountRegistry.activeSlotId();
    collections = readSlot(p, loadedSlot);
    notifyListeners();
  }).catch((e: Object): void => {
    logE(`MusicCollectionStore init failed: ${JSON.stringify(e)}`);
  });
  return loading;
}

export function musicCollections(): MusicCollection[] {
  syncSlot();
  return collections;
}

// 订阅并**立刻回调一次**：界面可能在读盘完成之后才挂上来（同 nowPlayingChannel 的理由）。
export function subscribeMusicCollections(listener: () => void): () => void {
  listeners.add(listener);
  listener();
  return (): void => { listeners.delete(listener); };
}

function apply(next: MusicCollection[]): void {
  collections = next;
  schedulePersist();
  notifyListeners();
}

// 建好了返回新合集，重名或空名返回 null（判据在 musicCollectionModel）。
export function createCollection(name: string): MusicCollection | null {
  syncSlot();
  const created: MusicCollection | null =
    createMusicCollection(collections, name, `c${Date.now()}`, Date.now());
  if (created === null) {
    return null;
  }
  apply(collections.concat([created]));
  return created;
}

export function renameCollection(collectionId: string, name: string): void {
  apply(renameMusicCollection(musicCollections(), collectionId, name));
}

export function deleteCollection(collectionId: string): void {
  apply(deleteMusicCollection(musicCollections(), collectionId));
}

export function addTrackToCollectionById(collectionId: string, trackKey: string): void {
  apply(addTrackToCollection(musicCollections(), collectionId, trackKey));
}

export function removeTrackFromCollectionById(collectionId: string, trackKey: string): void {
  apply(removeTrackFromCollection(musicCollections(), collectionId, trackKey));
}

export function toggleTrackInCollectionById(collectionId: string, trackKey: string): void {
  apply(toggleTrackInCollection(musicCollections(), collectionId, trackKey));
}

export function collectionById(collectionId: string): MusicCollection | null {
  return musicCollections().find((c: MusicCollection): boolean => c.id === collectionId) ?? null;
}

// 这首歌在不在任一合集里——播放页那个「添加到合集」按钮要据此换图标。
export function trackInAnyCollection(trackKey: string): boolean {
  return musicCollections().some((c: MusicCollection): boolean => c.trackKeys.indexOf(trackKey) >= 0);
}
