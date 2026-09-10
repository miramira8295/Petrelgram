import { AlbumGroup } from './collapseAlbums';
import { MessageEntry } from '../store/MessageEntry';

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
// 【为什么按会话嵌套而不是一张 `${chatId}:${rowId}` 的扁平表】
// 发布是热路径：2026-09-10 真机实测，1368 行的会话里这一趟要 7ms（三段中最贵
// 的一段），平均每行 5µs——对"一次 map 查找 + 十几个字段比较"来说贵得离谱，
// 大头是**每行拼一个字符串 key** 带来的分配与 GC。数字键的嵌套表把这笔开销
// 整个去掉。
//
// 淘汰改成两层：会话数有上限（只留最近用过的几个），每个会话内的行数各自有
// 上限。语义和原来的全局 2048 一致——保住"离屏行稍后上屏时能拿到最新快照"。
interface ChatRows {
  rows: Map<number, AlbumGroup>;
  subs: Map<number, Set<(group: AlbumGroup) => void>>;
}

const ROW_PRESENTATION_CACHE_LIMIT: number = 2048;
const CHAT_CACHE_LIMIT: number = 6;
const chats: Map<number, ChatRows> = new Map<number, ChatRows>();

function chatRows(chatId: number, create: boolean): ChatRows | undefined {
  const existing: ChatRows | undefined = chats.get(chatId);
  if (existing !== undefined) {
    // 刷新 LRU 次序：最近用过的会话排到末尾。
    chats.delete(chatId);
    chats.set(chatId, existing);
    return existing;
  }
  if (!create) {
    return undefined;
  }
  const fresh: ChatRows = {
    rows: new Map<number, AlbumGroup>(),
    subs: new Map<number, Set<(group: AlbumGroup) => void>>()
  };
  chats.set(chatId, fresh);
  while (chats.size > CHAT_CACHE_LIMIT) {
    const oldest: number | undefined = chats.keys().next().value as number | undefined;
    if (oldest === undefined || oldest === chatId) {
      break;
    }
    // 还有人订阅的会话不能丢：那些行还挂在屏幕上。
    const victim: ChatRows | undefined = chats.get(oldest);
    if (victim !== undefined && victim.subs.size > 0) {
      chats.delete(oldest);
      chats.set(oldest, victim);
      break;
    }
    chats.delete(oldest);
  }
  return fresh;
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
function sameHeadPresentation(x: MessageEntry, y: MessageEntry): boolean {
  return x.photoPath === y.photoPath && x.photoFailed === y.photoFailed &&
    x.linkPhotoPath === y.linkPhotoPath && x.linkPhotoFailed === y.linkPhotoFailed &&
    x.linkPhotoDownloadActive === y.linkPhotoDownloadActive &&
    x.videoPath === y.videoPath && x.videoFailed === y.videoFailed &&
    x.mediaDownloadActive === y.mediaDownloadActive &&
    x.stickerPath === y.stickerPath && x.stickerFailed === y.stickerFailed &&
    x.stickerDownloadActive === y.stickerDownloadActive &&
    x.translatedText === y.translatedText && x.translatedLang === y.translatedLang &&
    x.translationHidden === y.translationHidden;
}

function samePresentation(a: AlbumGroup, b: AlbumGroup): boolean {
  // head 是不可变的：MessageStore.patch 只给变了的那一条造新对象，其余原样
  // 传递（collapseAlbums 非相册那支就是 `head: m`）。所以**引用相同 ⇒ 上面
  // 那十几个字段一个都没变**，整段比较可以跳过。稳态下绝大多数行走这条路。
  // 相册的 head 是 albumHead() 克隆出来的，每次发布都是新对象，走不到这条
  // 捷径——但相册是少数。
  if (a.head !== b.head && !sameHeadPresentation(a.head, b.head)) {
    return false;
  }
  return sameStrings(a.photoPaths, b.photoPaths) && sameBooleans(a.photoFailed, b.photoFailed);
}

function remember(owner: ChatRows, rowId: number, group: AlbumGroup): void {
  if (owner.rows.has(rowId)) {
    owner.rows.delete(rowId); // refresh insertion order for bounded LRU eviction
  }
  owner.rows.set(rowId, group);
  if (owner.rows.size > ROW_PRESENTATION_CACHE_LIMIT) {
    const oldest: number | undefined = owner.rows.keys().next().value as number | undefined;
    if (oldest !== undefined) {
      owner.rows.delete(oldest);
    }
  }
}

export function publishMessageRowPresentations(chatId: number, groups: AlbumGroup[]): void {
  const owner: ChatRows = chatRows(chatId, true) as ChatRows;
  for (const group of groups) {
    const rowId: number = group.head.rowId;
    const previous: AlbumGroup | undefined = owner.rows.get(rowId);
    if (previous === undefined) {
      remember(owner, rowId, group);
      continue;
    }
    // 最便宜的一刀：整个行对象就是上次那个（reuseUnchangedRows 之外也可能
    // 发生），什么都不用比。
    if (previous === group) {
      continue;
    }
    if (previous.key !== group.key) {
      remember(owner, rowId, group);
      continue;
    }
    if (samePresentation(previous, group)) {
      // The usual download tick lands here: no map churn and, crucially, no
      // whole-bubble wake-up. The tiny progress view owns that update.
      continue;
    }
    remember(owner, rowId, group);
    const listeners: Set<(group: AlbumGroup) => void> | undefined = owner.subs.get(rowId);
    if (listeners !== undefined) {
      listeners.forEach((cb: (group: AlbumGroup) => void): void => cb(group));
    }
  }
}

export function messageRowPresentationFor(chatId: number, rowId: number): AlbumGroup | null {
  return chatRows(chatId, false)?.rows.get(rowId) ?? null;
}

export function subscribeMessageRowPresentation(
  chatId: number, rowId: number, cb: (group: AlbumGroup) => void
): () => void {
  const owner: ChatRows = chatRows(chatId, true) as ChatRows;
  let listeners: Set<(group: AlbumGroup) => void> | undefined = owner.subs.get(rowId);
  if (listeners === undefined) {
    listeners = new Set<(group: AlbumGroup) => void>();
    owner.subs.set(rowId, listeners);
  }
  listeners.add(cb);
  return (): void => {
    const current: Set<(group: AlbumGroup) => void> | undefined = owner.subs.get(rowId);
    if (current !== undefined) {
      current.delete(cb);
      if (current.size === 0) {
        owner.subs.delete(rowId);
      }
    }
  };
}
