import { AlbumGroup } from './collapseAlbums';

// Message rows have two kinds of change:
//
// 1. Structural/content changes (message text, entity tree, media kind, poll
//    options, reactions...) still change AlbumGroup.key and go through the
//    LazyForEach data source.
// 2. Presentation-only async state (download completion/failure/active state,
//    translation landing, thumbnail paths) must not rename the LazyForEach
//    item. Renaming it destroys and rebuilds the whole ListItem even though one
//    small child is all that changed.
//
// This channel carries the second class directly to the mounted row wrapper.
// The latest snapshot is retained so an off-screen cached row receives current
// data when it materializes later. Keys include chatId because Telegram message
// ids are only unique inside a chat.
interface RowPresentationEntry {
  group: AlbumGroup;
}

const ROW_PRESENTATION_CACHE_LIMIT: number = 2048;
const rows: Map<string, RowPresentationEntry> = new Map<string, RowPresentationEntry>();
const subs: Map<string, Set<(group: AlbumGroup) => void>> =
  new Map<string, Set<(group: AlbumGroup) => void>>();

function channelKey(chatId: number, rowId: number): string {
  return `${chatId}:${rowId}`;
}

function sameStrings(a: string[], b: string[]): boolean {
  if (a.length !== b.length) {
    return false;
  }
  for (let i = 0; i < a.length; i++) {
    if (a[i] !== b[i]) {
      return false;
    }
  }
  return true;
}

function sameBooleans(a: boolean[], b: boolean[]): boolean {
  if (a.length !== b.length) {
    return false;
  }
  for (let i = 0; i < a.length; i++) {
    if (a[i] !== b[i]) {
      return false;
    }
  }
  return true;
}

// Deliberately excludes byte progress. Progress is much hotter than every
// other field here and already has mediaProgressChannel; waking the whole
// bubble for it would merely move the per-tick rebuild one level down.
function samePresentation(a: AlbumGroup, b: AlbumGroup): boolean {
  const x = a.head;
  const y = b.head;
  return x.photoPath === y.photoPath && x.photoFailed === y.photoFailed &&
    x.linkPhotoPath === y.linkPhotoPath && x.linkPhotoFailed === y.linkPhotoFailed &&
    x.linkPhotoDownloadActive === y.linkPhotoDownloadActive &&
    x.videoPath === y.videoPath && x.videoFailed === y.videoFailed &&
    x.mediaDownloadActive === y.mediaDownloadActive &&
    x.stickerPath === y.stickerPath && x.stickerFailed === y.stickerFailed &&
    x.stickerDownloadActive === y.stickerDownloadActive &&
    x.translatedText === y.translatedText && x.translatedLang === y.translatedLang &&
    x.translationHidden === y.translationHidden &&
    sameStrings(a.photoPaths, b.photoPaths) && sameBooleans(a.photoFailed, b.photoFailed);
}

function remember(key: string, group: AlbumGroup): void {
  if (rows.has(key)) {
    rows.delete(key); // refresh insertion order for bounded LRU eviction
  }
  rows.set(key, { group });
  if (rows.size > ROW_PRESENTATION_CACHE_LIMIT) {
    const oldest: string | undefined = rows.keys().next().value as string | undefined;
    if (oldest !== undefined) {
      rows.delete(oldest);
    }
  }
}

export function publishMessageRowPresentations(chatId: number, groups: AlbumGroup[]): void {
  for (const group of groups) {
    const key: string = channelKey(chatId, group.head.rowId);
    const previous: RowPresentationEntry | undefined = rows.get(key);
    if (previous === undefined) {
      remember(key, group);
      continue;
    }
    if (previous.group.key !== group.key) {
      remember(key, group);
      continue;
    }
    if (samePresentation(previous.group, group)) {
      // The usual download tick lands here: no map churn and, crucially, no
      // whole-bubble wake-up. The tiny progress view owns that update.
      continue;
    }
    remember(key, group);
    const listeners: Set<(group: AlbumGroup) => void> | undefined = subs.get(key);
    if (listeners !== undefined) {
      listeners.forEach((cb: (group: AlbumGroup) => void): void => cb(group));
    }
  }
}

export function messageRowPresentationFor(chatId: number, rowId: number): AlbumGroup | null {
  return rows.get(channelKey(chatId, rowId))?.group ?? null;
}

export function subscribeMessageRowPresentation(
  chatId: number, rowId: number, cb: (group: AlbumGroup) => void
): () => void {
  const key: string = channelKey(chatId, rowId);
  let listeners: Set<(group: AlbumGroup) => void> | undefined = subs.get(key);
  if (listeners === undefined) {
    listeners = new Set<(group: AlbumGroup) => void>();
    subs.set(key, listeners);
  }
  listeners.add(cb);
  return (): void => {
    const current: Set<(group: AlbumGroup) => void> | undefined = subs.get(key);
    if (current !== undefined) {
      current.delete(cb);
      if (current.size === 0) {
        subs.delete(key);
      }
    }
  };
}
