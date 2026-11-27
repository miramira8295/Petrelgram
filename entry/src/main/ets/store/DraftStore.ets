import { DraftCache, draftPreviewOf } from '../util/draftCache';
import { KEY_DRAFT_CACHE, setString } from './AppSettings';

// 本地草稿的单一入口（见 util/draftCache 的说明）。
//
// 一份进程内缓存 + 一次落盘。落盘走 AppSettings.setString（preferences），
// 所以它在 initSettings 里被一并读回来；这里在首次使用时 load 一次。
const cache: DraftCache = new DraftCache();
// 进程内记录每条草稿的最近时间戳（秒），用于打开会话时和云端 draft.date 比新旧。
const draftDates: Map<number, number> = new Map<number, number>();
let loaded: boolean = false;

// 会话列表里最多显示多少个字。
const DRAFT_PREVIEW_MAX: number = 40;

function ensureLoaded(): void {
  if (loaded) {
    return;
  }
  loaded = true;
  cache.load(AppStorage.get<string>(KEY_DRAFT_CACHE) ?? '');
}

export function localDraft(chatId: number): string {
  ensureLoaded();
  return cache.get(chatId);
}

export function localDraftDate(chatId: number): number {
  ensureLoaded();
  return draftDates.get(chatId) ?? 0;
}

export function rememberLocalDraft(chatId: number, text: string, dateSec: number = 0): boolean {
  ensureLoaded();
  const effectiveDate: number = dateSec > 0 ? Math.floor(dateSec) : Math.floor(Date.now() / 1000);
  if (text === '') {
    draftDates.delete(chatId);
  } else {
    draftDates.set(chatId, effectiveDate);
  }
  if (cache.get(chatId) === text) {
    return false;
  }
  cache.put(chatId, text);
  setString(KEY_DRAFT_CACHE, cache.serialize());
  return true;
}

// 收到 TDLib 实时推送的 updateChatDraftMessage：云端为准，更新本地缓存并刷新会话列表。
export function syncCloudDraft(chatId: number, text: string, dateSec: number): boolean {
  const changed: boolean = rememberLocalDraft(chatId, text, dateSec);
  if (changed) {
    bumpDraftEpoch();
  }
  return changed;
}

// 收到 updateNewChat 时的初始草稿种子：只采用非空且不早于本地时间的云端草稿。
export function seedCloudDraft(chatId: number, text: string, dateSec: number): boolean {
  if (text === '') {
    return false;
  }
  const existingDate: number = localDraftDate(chatId);
  if (existingDate > 0 && dateSec > 0 && dateSec < existingDate) {
    return false;
  }
  return syncCloudDraft(chatId, text, dateSec);
}

export function localDraftPreview(chatId: number): string {
  return draftPreviewOf(localDraft(chatId), DRAFT_PREVIEW_MAX);
}

// 会话列表整体重绘的依据：草稿变了要让行重新算预览。
export const DRAFT_EPOCH: string = 'draftEpoch';

export function bumpDraftEpoch(): void {
  AppStorage.setOrCreate(DRAFT_EPOCH, (AppStorage.get<number>(DRAFT_EPOCH) ?? 0) + 1);
}
