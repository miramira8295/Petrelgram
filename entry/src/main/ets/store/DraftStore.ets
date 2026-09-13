import { DraftCache, draftPreviewOf } from '../util/draftCache';
import { KEY_DRAFT_CACHE, setString } from './AppSettings';

// 本地草稿的单一入口（见 util/draftCache 的说明）。
//
// 一份进程内缓存 + 一次落盘。落盘走 AppSettings.setString（preferences），
// 所以它在 initSettings 里被一并读回来；这里在首次使用时 load 一次。
const cache: DraftCache = new DraftCache();
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

export function rememberLocalDraft(chatId: number, text: string): void {
  ensureLoaded();
  if (cache.get(chatId) === text) {
    return;
  }
  cache.put(chatId, text);
  setString(KEY_DRAFT_CACHE, cache.serialize());
}

export function localDraftPreview(chatId: number): string {
  return draftPreviewOf(localDraft(chatId), DRAFT_PREVIEW_MAX);
}

// 会话列表整体重绘的依据：草稿变了要让行重新算预览。
export const DRAFT_EPOCH: string = 'draftEpoch';

export function bumpDraftEpoch(): void {
  AppStorage.setOrCreate(DRAFT_EPOCH, (AppStorage.get<number>(DRAFT_EPOCH) ?? 0) + 1);
}
