import { TdClient } from '../tdkit/TdClient';
import { TdError, TdObject, TdRequest } from '../tdkit/TdTypes';
import { computeInitials } from './ChatEntry';
import {
  CallTone, ParsedCallContent, callStatus, formatCallTime as fullCallTime,
  parseCallContent
} from '../util/CallHistoryPresentation';
import { str } from '../util/strings';
import { logE } from '../util/log';

const DOWNLOAD_PRIORITY: number = 1;
const PAGE_LIMIT: number = 50;
const CACHE_REFRESH_AGE_MS: number = 15000;

export type CallsMode = 'all' | 'missed';
export type CallsLoadState = 'loading' | 'ready' | 'empty' | 'error';
export type CallsPageState = 'idle' | 'loading' | 'error' | 'end';

export interface CallItem {
  key: string;
  msgId: number;
  chatId: number;
  date: number;
  name: string;
  initials: string;
  avatarPath: string;
  colorSeed: number;
  outgoing: boolean;
  missed: boolean;
  isVideo: boolean;
  isGroup: boolean;
  active: boolean;
  duration: number;
  reasonType: string;
  participantCount: number;
  statusText: string;
  tone: CallTone;
}

interface CallsCache {
  mode: CallsMode;
  items: CallItem[];
  nextOffset: string;
  totalCount: number;
  loaded: boolean;
  loadedAt: number;
}

interface PeerInfo {
  title: string;
  initials: string;
  avatarPath: string;
}

type Listener = () => void;

function emptyCache(mode: CallsMode): CallsCache {
  return { mode, items: [], nextOffset: '', totalCount: 0, loaded: false, loadedAt: 0 };
}

let sessionClient: TdClient | null = null;
let allCache: CallsCache = emptyCache('all');
let missedCache: CallsCache = emptyCache('missed');

function prepareSession(client: TdClient): void {
  if (sessionClient === client) { return; }
  sessionClient = client;
  allCache = emptyCache('all');
  missedCache = emptyCache('missed');
}

function cacheFor(mode: CallsMode): CallsCache {
  return mode === 'missed' ? missedCache : allCache;
}

function callKey(chatId: number, messageId: number): string {
  return `${chatId}:${messageId}`;
}

function cloneCall(item: CallItem): CallItem {
  return {
    key: item.key, msgId: item.msgId, chatId: item.chatId, date: item.date,
    name: item.name, initials: item.initials, avatarPath: item.avatarPath,
    colorSeed: item.colorSeed, outgoing: item.outgoing, missed: item.missed,
    isVideo: item.isVideo, isGroup: item.isGroup, active: item.active,
    duration: item.duration, reasonType: item.reasonType,
    participantCount: item.participantCount, statusText: item.statusText, tone: item.tone
  };
}

function cloneCache(cache: CallsCache): CallsCache {
  return {
    mode: cache.mode,
    items: cache.items.map((item: CallItem): CallItem => cloneCall(item)),
    nextOffset: cache.nextOffset,
    totalCount: cache.totalCount,
    loaded: cache.loaded,
    loadedAt: cache.loadedAt
  };
}

function callSignature(item: CallItem): string {
  return [item.key, `${item.date}`, item.name, item.initials, item.avatarPath,
    `${item.outgoing}`, `${item.missed}`, `${item.isVideo}`, `${item.isGroup}`,
    `${item.active}`, `${item.duration}`, item.reasonType, `${item.participantCount}`,
    item.statusText, item.tone].join('|');
}

function sortCalls(items: CallItem[]): CallItem[] {
  return items.sort((left: CallItem, right: CallItem): number => {
    if (left.date !== right.date) { return right.date - left.date; }
    if (left.msgId !== right.msgId) { return right.msgId > left.msgId ? 1 : -1; }
    return left.chatId - right.chatId;
  });
}

function mergeCalls(first: CallItem[], second: CallItem[]): CallItem[] {
  const rows = new Map<string, CallItem>();
  for (const item of first) { rows.set(item.key, item); }
  for (const item of second) { if (!rows.has(item.key)) { rows.set(item.key, item); } }
  return sortCalls(Array.from(rows.values()));
}

function countNewCalls(base: CallItem[], candidates: CallItem[]): number {
  let count = 0;
  for (const candidate of candidates) {
    if (base.findIndex((item: CallItem): boolean => item.key === candidate.key) < 0) { count++; }
  }
  return count;
}

function callFromMessage(message: TdObject): CallItem | null {
  const msgId = (message['id'] as number | undefined) ?? 0;
  const chatId = (message['chat_id'] as number | undefined) ?? 0;
  if (msgId === 0 || chatId === 0) { return null; }
  const outgoing = (message['is_outgoing'] as boolean | undefined) ?? false;
  const parsed = parseCallContent(message['content'] as TdObject | undefined, outgoing);
  if (!parsed.valid) { return null; }
  const status = callStatus(parsed, outgoing);
  return {
    key: callKey(chatId, msgId), msgId, chatId,
    date: Math.max(0, (message['date'] as number | undefined) ?? 0),
    name: '', initials: '?', avatarPath: '', colorSeed: chatId,
    outgoing, missed: parsed.missed, isVideo: parsed.isVideo,
    isGroup: parsed.isGroup, active: parsed.active, duration: parsed.duration,
    reasonType: parsed.reasonType, participantCount: parsed.participantCount,
    statusText: status.text, tone: status.tone
  };
}

function withContent(item: CallItem, content: TdObject): CallItem | null {
  const parsed = parseCallContent(content, item.outgoing);
  if (!parsed.valid) { return null; }
  const status = callStatus(parsed, item.outgoing);
  return {
    key: item.key, msgId: item.msgId, chatId: item.chatId, date: item.date,
    name: item.name, initials: item.initials, avatarPath: item.avatarPath,
    colorSeed: item.colorSeed, outgoing: item.outgoing, missed: parsed.missed,
    isVideo: parsed.isVideo, isGroup: parsed.isGroup, active: parsed.active,
    duration: parsed.duration, reasonType: parsed.reasonType,
    participantCount: parsed.participantCount, statusText: status.text, tone: status.tone
  };
}

export function formatCallTime(timestamp: number): string {
  return fullCallTime(timestamp);
}

// Backing store for the call-history page. Search results are cached per mode
// for the lifetime of the TDLib client, while requests and callbacks remain
// scoped to this page instance through requestSequence/active guards.
export class CallsStore {
  private client: TdClient;
  private listeners: Listener[] = [];
  private unsubs: Array<() => void> = [];
  private active: boolean = false;
  private requestSequence: number = 0;
  private resolvingChats: Set<number> = new Set();
  private peers: Map<number, PeerInfo> = new Map();
  private fileChats: Map<number, number[]> = new Map();

  calls: CallItem[] = [];
  mode: CallsMode = 'all';
  loadState: CallsLoadState = 'loading';
  pageState: CallsPageState = 'idle';
  refreshing: boolean = false;
  syncError: string = '';
  totalCount: number = 0;
  hasMore: boolean = false;
  // Kept for old callers while CallsPage migrates to loadState.
  loading: boolean = true;

  constructor(client: TdClient) {
    this.client = client;
    prepareSession(client);
  }

  subscribe(listener: Listener): () => void {
    this.listeners = [...this.listeners, listener];
    listener();
    return (): void => {
      this.listeners = this.listeners.filter((item: Listener): boolean => item !== listener);
    };
  }

  private notify(): void {
    for (const listener of this.listeners) { listener(); }
  }

  private publish(): void {
    const cache = cacheFor(this.mode);
    this.calls = cache.items.slice();
    this.totalCount = cache.totalCount >= 0 ? cache.totalCount : cache.items.length;
    this.hasMore = cache.nextOffset !== '';
    this.loading = this.loadState === 'loading';
    this.notify();
  }

  open(): void {
    if (this.active) { return; }
    this.active = true;
    this.seedPeersFromCache();
    this.unsubs.push(this.client.onUpdate('updateFile', (update: TdObject): void => {
      const file = update['file'] as TdObject | undefined;
      if (file !== undefined) { this.applyFile(file); }
    }));
    this.unsubs.push(this.client.onUpdate('updateNewMessage', (update: TdObject): void => {
      const message = update['message'] as TdObject | undefined;
      if (message !== undefined) { this.onNewMessage(message); }
    }));
    this.unsubs.push(this.client.onUpdate('updateMessageContent', (update: TdObject): void => {
      this.onMessageContent(update);
    }));
    this.unsubs.push(this.client.onUpdate('updateDeleteMessages', (update: TdObject): void => {
      this.onMessagesDeleted(update);
    }));
    this.unsubs.push(this.client.onUpdate('updateChatTitle', (update: TdObject): void => {
      this.onChatTitle(update);
    }));
    this.unsubs.push(this.client.onUpdate('updateChatPhoto', (update: TdObject): void => {
      this.onChatPhoto(update);
    }));

    const cache = cacheFor(this.mode);
    if (cache.loaded) {
      this.loadState = cache.items.length > 0 ? 'ready' : 'empty';
      this.pageState = cache.nextOffset === '' ? 'end' : 'idle';
      this.publish();
      if (Date.now() - cache.loadedAt >= CACHE_REFRESH_AGE_MS) { this.refresh(); }
    } else {
      this.loadState = 'loading';
      this.publish();
      this.requestPage(true);
    }
  }

  close(): void {
    this.active = false;
    this.requestSequence++;
    for (const unsubscribe of this.unsubs) { unsubscribe(); }
    this.unsubs = [];
    this.listeners = [];
    this.fileChats.clear();
    this.resolvingChats.clear();
  }

  setMode(mode: CallsMode): void {
    if (mode === this.mode) { return; }
    this.requestSequence++;
    this.mode = mode;
    this.refreshing = false;
    this.syncError = '';
    const cache = cacheFor(mode);
    if (cache.loaded) {
      this.loadState = cache.items.length > 0 ? 'ready' : 'empty';
      this.pageState = cache.nextOffset === '' ? 'end' : 'idle';
      this.publish();
      if (Date.now() - cache.loadedAt >= CACHE_REFRESH_AGE_MS) { this.refresh(); }
    } else {
      this.loadState = 'loading';
      this.pageState = 'idle';
      this.publish();
      this.requestPage(true);
    }
  }

  refresh(): void {
    if (!this.active || this.refreshing || this.pageState === 'loading') { return; }
    this.requestPage(true);
  }

  retry(): void {
    if (this.pageState === 'error') { this.loadMore(); }
    else { this.refresh(); }
  }

  loadMore(): void {
    const cache = cacheFor(this.mode);
    if (!this.active || this.refreshing || this.pageState === 'loading' || cache.nextOffset === '') { return; }
    this.requestPage(false);
  }

  private requestPage(reset: boolean): void {
    const requestMode = this.mode;
    const cache = cacheFor(requestMode);
    const requestSnapshot = reset ? cache.items.map((item: CallItem): CallItem => cloneCall(item)) : [];
    const sequence = ++this.requestSequence;
    if (reset) {
      this.syncError = '';
      if (cache.items.length > 0 || cache.loaded) { this.refreshing = true; }
      else { this.loadState = 'loading'; }
    } else {
      this.pageState = 'loading';
    }
    this.publish();
    const request: TdRequest = { '@type': 'searchCallMessages' };
    request['offset'] = reset ? '' : cache.nextOffset;
    request['limit'] = PAGE_LIMIT;
    request['only_missed'] = requestMode === 'missed';
    this.client.send(request, 15000).then((result: TdObject): void => {
      if (!this.active || sequence !== this.requestSequence || requestMode !== this.mode) { return; }
      const messages = (result['messages'] as TdObject[] | undefined) ?? [];
      const parsed: CallItem[] = [];
      for (const message of messages) {
        const item = callFromMessage(message);
        if (item !== null && (requestMode === 'all' || item.missed)) { parsed.push(item); }
      }
      if (reset) {
        const snapshotVersions = new Map<string, string>();
        for (const row of requestSnapshot) { snapshotVersions.set(row.key, callSignature(row)); }
        const liveRows = cache.items.filter((row: CallItem): boolean => {
          const previous = snapshotVersions.get(row.key);
          return previous === undefined || previous !== callSignature(row);
        });
        const liveKeys = new Set<string>();
        for (const row of liveRows) { liveKeys.add(row.key); }
        const removedKeys = new Set<string>();
        for (const row of requestSnapshot) {
          if (cache.items.findIndex((current: CallItem): boolean => current.key === row.key) < 0) {
            removedKeys.add(row.key);
          }
        }
        const serverRows = parsed.filter((row: CallItem): boolean =>
          !removedKeys.has(row.key) && !liveKeys.has(row.key));
        cache.items = mergeCalls(liveRows, serverRows);
      } else {
        cache.items = mergeCalls(cache.items, parsed);
      }
      cache.nextOffset = (result['next_offset'] as string | undefined) ?? '';
      cache.totalCount = Math.max(
        (result['total_count'] as number | undefined) ?? cache.items.length,
        cache.items.length
      );
      cache.loaded = true;
      cache.loadedAt = Date.now();
      this.refreshing = false;
      this.syncError = '';
      this.loadState = cache.items.length > 0 ? 'ready' : 'empty';
      this.pageState = cache.nextOffset === '' ? 'end' : 'idle';
      this.publish();
      for (const item of cache.items) { this.resolveChat(item.chatId); }
    }).catch((error: TdError): void => {
      if (!this.active || sequence !== this.requestSequence || requestMode !== this.mode) { return; }
      this.refreshing = false;
      if (reset) {
        if (cache.loaded) {
          this.loadState = cache.items.length > 0 ? 'ready' : 'empty';
          this.syncError = str('cs_sync_failed_tap');
        } else {
          this.loadState = 'error';
          this.syncError = str('calls_load_failed');
        }
      } else {
        this.pageState = 'error';
      }
      this.publish();
      logE(`CallsStore.searchCallMessages failed: ${error.message}`);
    });
  }

  private seedPeersFromCache(): void {
    const combined = mergeCalls(allCache.items, missedCache.items);
    for (const item of combined) {
      if (item.name !== '') {
        this.peers.set(item.chatId, {
          title: item.name, initials: item.initials, avatarPath: item.avatarPath
        });
      }
    }
  }

  private patchChat(chatId: number, peer: PeerInfo): void {
    const patch = (cache: CallsCache): void => {
      let changed = false;
      cache.items = cache.items.map((item: CallItem): CallItem => {
        if (item.chatId !== chatId || (item.name === peer.title && item.initials === peer.initials
          && item.avatarPath === peer.avatarPath)) { return item; }
        changed = true;
        const next = cloneCall(item);
        next.name = peer.title;
        next.initials = peer.initials;
        next.avatarPath = peer.avatarPath;
        return next;
      });
      if (changed) { cache.loadedAt = Date.now(); }
    };
    patch(allCache);
    patch(missedCache);
    if (this.active) { this.publish(); }
  }

  private resolveChat(chatId: number): void {
    const known = this.peers.get(chatId);
    if (known !== undefined) { this.patchChat(chatId, known); return; }
    if (this.resolvingChats.has(chatId)) { return; }
    this.resolvingChats.add(chatId);
    const request: TdRequest = { '@type': 'getChat' };
    request['chat_id'] = chatId;
    this.client.send(request, 10000).then((chat: TdObject): void => {
      this.resolvingChats.delete(chatId);
      if (!this.active) { return; }
      const rawTitle = (chat['title'] as string | undefined) ?? '';
      const title = rawTitle !== '' ? rawTitle : str('deleted_account');
      const photo = chat['photo'] as TdObject | undefined;
      const small = photo?.['small'] as TdObject | undefined;
      const local = small?.['local'] as TdObject | undefined;
      const completed = (local?.['is_downloading_completed'] as boolean | undefined) ?? false;
      const localPath = completed ? ((local?.['path'] as string | undefined) ?? '') : '';
      const peer: PeerInfo = { title, initials: computeInitials(title), avatarPath: localPath };
      this.peers.set(chatId, peer);
      this.patchChat(chatId, peer);
      const fileId = (small?.['id'] as number | undefined) ?? 0;
      if (localPath === '' && fileId > 0) { this.requestAvatar(chatId, fileId); }
    }).catch((error: TdError): void => {
      this.resolvingChats.delete(chatId);
      if (!this.active) { return; }
      const fallback: PeerInfo = { title: str('cs_unknown_chat'), initials: '?', avatarPath: '' };
      this.peers.set(chatId, fallback);
      this.patchChat(chatId, fallback);
      logE(`CallsStore.getChat(${chatId}) failed: ${error.message}`);
    });
  }

  private requestAvatar(chatId: number, fileId: number): void {
    const existing = this.fileChats.get(fileId);
    if (existing !== undefined) {
      if (existing.indexOf(chatId) < 0) { this.fileChats.set(fileId, [...existing, chatId]); }
      return;
    }
    this.fileChats.set(fileId, [chatId]);
    const request: TdRequest = { '@type': 'downloadFile' };
    request['file_id'] = fileId;
    request['priority'] = DOWNLOAD_PRIORITY;
    this.client.send(request).then((file: TdObject): void => this.applyFile(file)).catch((error: TdError): void => {
      this.fileChats.delete(fileId);
      logE(`CallsStore.downloadFile(${fileId}) failed: ${error.message}`);
    });
  }

  private applyFile(file: TdObject): void {
    if (!this.active) { return; }
    const id = (file['id'] as number | undefined) ?? 0;
    const chatIds = this.fileChats.get(id);
    if (id === 0 || chatIds === undefined) { return; }
    const local = file['local'] as TdObject | undefined;
    const completed = (local?.['is_downloading_completed'] as boolean | undefined) ?? false;
    const path = (local?.['path'] as string | undefined) ?? '';
    if (!completed || path === '') { return; }
    this.fileChats.delete(id);
    for (const chatId of chatIds) {
      const current = this.peers.get(chatId) ?? { title: str('cs_unknown_chat'), initials: '?', avatarPath: '' };
      const peer: PeerInfo = { title: current.title, initials: current.initials, avatarPath: path };
      this.peers.set(chatId, peer);
      this.patchChat(chatId, peer);
    }
  }

  private addToCache(cache: CallsCache, item: CallItem): void {
    const index = cache.items.findIndex((row: CallItem): boolean => row.key === item.key);
    if (index >= 0) {
      const next = cache.items.slice();
      const previous = next[index];
      item.name = previous.name; item.initials = previous.initials; item.avatarPath = previous.avatarPath;
      next[index] = item;
      cache.items = sortCalls(next);
      return;
    }
    cache.items = sortCalls([item, ...cache.items]);
    if (cache.loaded && cache.totalCount >= 0) { cache.totalCount++; }
  }

  private onNewMessage(message: TdObject): void {
    const item = callFromMessage(message);
    if (item === null) { return; }
    this.addToCache(allCache, cloneCall(item));
    if (item.missed) { this.addToCache(missedCache, cloneCall(item)); }
    const currentMatches = this.mode === 'all' || item.missed;
    if (currentMatches) {
      this.loadState = 'ready';
      this.publish();
      this.resolveChat(item.chatId);
    }
  }

  private onMessageContent(update: TdObject): void {
    const chatId = (update['chat_id'] as number | undefined) ?? 0;
    const messageId = (update['message_id'] as number | undefined) ?? 0;
    const content = update['new_content'] as TdObject | undefined;
    if (chatId === 0 || messageId === 0 || content === undefined) { return; }
    const key = callKey(chatId, messageId);
    const base = allCache.items.find((item: CallItem): boolean => item.key === key)
      ?? missedCache.items.find((item: CallItem): boolean => item.key === key);
    if (base === undefined) { return; }
    const updated = withContent(base, content);
    this.replaceContent(allCache, key, updated);
    this.replaceContent(missedCache, key, updated !== null && updated.missed ? updated : null);
    this.loadState = cacheFor(this.mode).items.length > 0 ? 'ready' : 'empty';
    this.publish();
  }

  private replaceContent(cache: CallsCache, key: string, item: CallItem | null): void {
    const previousIndex = cache.items.findIndex((row: CallItem): boolean => row.key === key);
    const existed = previousIndex >= 0;
    const next = cache.items.filter((row: CallItem): boolean => row.key !== key);
    if (item !== null) { next.push(cloneCall(item)); }
    cache.items = sortCalls(next);
    if (!cache.loaded || existed === (item !== null)) { return; }
    cache.totalCount = Math.max(0, cache.totalCount + (item !== null ? 1 : -1));
  }

  private removeMessages(chatId: number, ids: number[]): void {
    const remove = (cache: CallsCache): void => {
      const before = cache.items.length;
      cache.items = cache.items.filter((item: CallItem): boolean =>
        item.chatId !== chatId || ids.indexOf(item.msgId) < 0);
      const removed = before - cache.items.length;
      if (removed > 0 && cache.totalCount >= 0) { cache.totalCount = Math.max(0, cache.totalCount - removed); }
    };
    remove(allCache);
    remove(missedCache);
  }

  private onMessagesDeleted(update: TdObject): void {
    const permanent = (update['is_permanent'] as boolean | undefined) ?? false;
    const fromCache = (update['from_cache'] as boolean | undefined) ?? false;
    if (fromCache && !permanent) { return; }
    const chatId = (update['chat_id'] as number | undefined) ?? 0;
    const ids = (update['message_ids'] as number[] | undefined) ?? [];
    this.removeMessages(chatId, ids);
    const current = cacheFor(this.mode);
    this.loadState = current.loaded && current.items.length === 0 ? 'empty' : this.loadState;
    this.publish();
  }

  private onChatTitle(update: TdObject): void {
    const chatId = (update['chat_id'] as number | undefined) ?? 0;
    const title = (update['title'] as string | undefined) ?? '';
    if (chatId === 0 || title === '') { return; }
    const current = this.peers.get(chatId);
    const peer: PeerInfo = {
      title, initials: computeInitials(title), avatarPath: current?.avatarPath ?? ''
    };
    this.peers.set(chatId, peer);
    this.patchChat(chatId, peer);
  }

  private onChatPhoto(update: TdObject): void {
    const chatId = (update['chat_id'] as number | undefined) ?? 0;
    if (chatId === 0) { return; }
    const photo = update['photo'] as TdObject | undefined;
    const small = photo?.['small'] as TdObject | undefined;
    const local = small?.['local'] as TdObject | undefined;
    const completed = (local?.['is_downloading_completed'] as boolean | undefined) ?? false;
    const path = completed ? ((local?.['path'] as string | undefined) ?? '') : '';
    const current = this.peers.get(chatId) ?? { title: str('cs_unknown_chat'), initials: '?', avatarPath: '' };
    const peer: PeerInfo = { title: current.title, initials: current.initials, avatarPath: path };
    this.peers.set(chatId, peer);
    this.patchChat(chatId, peer);
    const fileId = (small?.['id'] as number | undefined) ?? 0;
    if (path === '' && fileId > 0) { this.requestAvatar(chatId, fileId); }
  }

  deleteCall(item: CallItem): Promise<void> {
    this.removeMessages(item.chatId, [item.msgId]);
    this.loadState = cacheFor(this.mode).items.length > 0 ? 'ready' : 'empty';
    this.publish();
    const request: TdRequest = { '@type': 'deleteMessages' };
    request['chat_id'] = item.chatId;
    request['message_ids'] = [item.msgId];
    request['revoke'] = false;
    return this.client.send(request, 12000).then((): void => {}).catch((error: TdError): Promise<void> => {
      this.addToCache(allCache, cloneCall(item));
      if (item.missed) { this.addToCache(missedCache, cloneCall(item)); }
      this.loadState = 'ready';
      this.publish();
      return Promise.reject(error);
    });
  }

  clearAll(): Promise<void> {
    const allSnapshot = cloneCache(allCache);
    const missedSnapshot = cloneCache(missedCache);
    allCache.items = []; allCache.nextOffset = ''; allCache.totalCount = 0; allCache.loaded = true;
    missedCache.items = []; missedCache.nextOffset = ''; missedCache.totalCount = 0; missedCache.loaded = true;
    this.loadState = 'empty'; this.pageState = 'end'; this.publish();
    const request: TdRequest = { '@type': 'deleteAllCallMessages' };
    request['revoke'] = false;
    return this.client.send(request, 15000).then((): void => {
      allCache.loadedAt = Date.now();
      missedCache.loadedAt = allCache.loadedAt;
    }).catch((error: TdError): Promise<void> => {
      const liveAll = allCache.items.map((item: CallItem): CallItem => cloneCall(item));
      const liveMissed = missedCache.items.map((item: CallItem): CallItem => cloneCall(item));
      allCache = cloneCache(allSnapshot);
      missedCache = cloneCache(missedSnapshot);
      const newAllCount = countNewCalls(allCache.items, liveAll);
      const newMissedCount = countNewCalls(missedCache.items, liveMissed);
      allCache.items = mergeCalls(liveAll, allCache.items);
      missedCache.items = mergeCalls(liveMissed, missedCache.items);
      allCache.totalCount = Math.max(allCache.totalCount + newAllCount, allCache.items.length);
      missedCache.totalCount = Math.max(missedCache.totalCount + newMissedCount, missedCache.items.length);
      allCache.loadedAt = Math.max(allCache.loadedAt, Date.now());
      missedCache.loadedAt = Math.max(missedCache.loadedAt, allCache.loadedAt);
      this.loadState = cacheFor(this.mode).items.length > 0 ? 'ready' : 'empty';
      this.pageState = cacheFor(this.mode).nextOffset === '' ? 'end' : 'idle';
      this.publish();
      return Promise.reject(error);
    });
  }
}
