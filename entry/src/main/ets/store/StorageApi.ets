import { getTdClient } from '../tdkit/Globals';
import { TdObject, TdRequest, TdError } from '../tdkit/TdTypes';
import { str } from '../util/strings';
import { buildCacheTrimRequest, shouldTrimCache } from './CacheLimit';
import { logE } from '../util/log';

export interface StorageUsage {
  filesSize: number;
  fileCount: number;
  databaseSize: number;
  languagePackDatabaseSize: number;
  logSize: number;
  totalSize: number;
}

export interface StorageCategory {
  key: string;
  label: string;
  size: number;
  count: number;
}

export interface ChatStorageUsage {
  chatId: number;
  size: number;
  count: number;
  categories: StorageCategory[];
}

export interface DetailedStorageUsage {
  size: number;
  count: number;
  categories: StorageCategory[];
  chats: ChatStorageUsage[];
}

export interface NetworkBreakdown {
  key: string;
  label: string;
  sent: number;
  received: number;
  duration: number;
}

export interface NetworkUsage {
  sent: number;
  received: number;
  sinceDate: number;
  callDuration: number;
  byNetwork: NetworkBreakdown[];
  byCategory: NetworkBreakdown[];
}

export interface CacheClearResult {
  remainingSize: number;
  remainingCount: number;
}

function safeNumber(value: Object | undefined): number {
  const parsed = value as number | undefined;
  return parsed !== undefined && Number.isFinite(parsed) && parsed > 0 ? parsed : 0;
}

export function formatBytes(bytes: number): string {
  const safe = Number.isFinite(bytes) && bytes > 0 ? bytes : 0;
  if (safe < 1024) { return `${Math.round(safe)} B`; }
  const kb = safe / 1024;
  if (kb < 1024) { return `${kb.toFixed(1)} KB`; }
  const mb = kb / 1024;
  if (mb < 1024) { return `${mb.toFixed(1)} MB`; }
  const gb = mb / 1024;
  if (gb < 1024) { return `${gb.toFixed(2)} GB`; }
  return `${(gb / 1024).toFixed(2)} TB`;
}

export function formatDuration(seconds: number): string {
  const safe = Number.isFinite(seconds) && seconds > 0 ? Math.floor(seconds) : 0;
  const hours = Math.floor(safe / 3600);
  const minutes = Math.floor((safe % 3600) / 60);
  if (hours > 0) { return str('duration_hours_minutes', hours, minutes); }
  if (minutes > 0) { return str('duration_minutes', minutes); }
  return str('duration_seconds', safe);
}

export async function getStorageUsage(): Promise<StorageUsage> {
  const res = await getTdClient().send({ '@type': 'getStorageStatisticsFast' } as TdRequest, 12000);
  const filesSize = safeNumber(res['files_size']);
  const databaseSize = safeNumber(res['database_size']);
  const languagePackDatabaseSize = safeNumber(res['language_pack_database_size']);
  const logSize = safeNumber(res['log_size']);
  return {
    filesSize,
    fileCount: safeNumber(res['file_count']),
    databaseSize,
    languagePackDatabaseSize,
    logSize,
    totalSize: filesSize + databaseSize + languagePackDatabaseSize + logSize
  };
}

function fileTypeInfo(type: TdObject | undefined): StorageCategory {
  const raw = type !== undefined ? ((type['@type'] as string | undefined) ?? '') : '';
  if (raw === 'fileTypePhoto') { return { key: 'photo', label: str('storage_photo'), size: 0, count: 0 }; }
  if (raw === 'fileTypeVideo' || raw === 'fileTypeVideoNote') {
    return { key: 'video', label: str('storage_video'), size: 0, count: 0 };
  }
  if (raw === 'fileTypeAnimation') { return { key: 'animation', label: 'GIF', size: 0, count: 0 }; }
  if (raw === 'fileTypeAudio') { return { key: 'audio', label: str('storage_audio'), size: 0, count: 0 }; }
  if (raw === 'fileTypeVoiceNote') { return { key: 'voice', label: str('storage_voice'), size: 0, count: 0 }; }
  if (raw === 'fileTypeSticker') { return { key: 'sticker', label: str('storage_sticker'), size: 0, count: 0 }; }
  if (raw === 'fileTypeDocument') { return { key: 'file', label: str('storage_file'), size: 0, count: 0 }; }
  if (raw === 'fileTypeThumbnail') { return { key: 'thumbnail', label: str('storage_thumbnail'), size: 0, count: 0 }; }
  if (raw === 'fileTypeProfilePhoto') { return { key: 'profile', label: str('storage_profile'), size: 0, count: 0 }; }
  if (raw === 'fileTypeWallpaper') { return { key: 'wallpaper', label: str('storage_wallpaper'), size: 0, count: 0 }; }
  if (raw === 'fileTypeSecret') { return { key: 'secret', label: str('storage_secret'), size: 0, count: 0 }; }
  return { key: 'other', label: str('storage_other'), size: 0, count: 0 };
}

function addCategory(target: Map<string, StorageCategory>, item: StorageCategory): void {
  const existing = target.get(item.key);
  if (existing === undefined) {
    target.set(item.key, item);
  } else {
    existing.size += item.size;
    existing.count += item.count;
  }
}

function sortedCategories(map: Map<string, StorageCategory>): StorageCategory[] {
  return Array.from(map.values()).filter((item: StorageCategory): boolean => item.size > 0 || item.count > 0)
    .sort((left: StorageCategory, right: StorageCategory): number => right.size - left.size);
}

function categoriesOf(raw: TdObject[]): StorageCategory[] {
  const map = new Map<string, StorageCategory>();
  for (const entry of raw) {
    const item = fileTypeInfo(entry['file_type'] as TdObject | undefined);
    item.size = safeNumber(entry['size']);
    item.count = safeNumber(entry['count']);
    addCategory(map, item);
  }
  return sortedCategories(map);
}

export async function getDetailedStorageUsage(chatLimit: number = 30): Promise<DetailedStorageUsage> {
  const request: TdRequest = { '@type': 'getStorageStatistics' };
  request['chat_limit'] = Math.max(0, Math.min(100, Math.round(chatLimit)));
  const res = await getTdClient().send(request, 30000);
  const chatsRaw = (res['by_chat'] as TdObject[] | undefined) ?? [];
  const chats: ChatStorageUsage[] = [];
  const totalCategories = new Map<string, StorageCategory>();
  for (const raw of chatsRaw) {
    const categories = categoriesOf((raw['by_file_type'] as TdObject[] | undefined) ?? []);
    for (const item of categories) {
      addCategory(totalCategories, {
        key: item.key, label: item.label, size: item.size, count: item.count
      });
    }
    chats.push({
      chatId: (raw['chat_id'] as number | undefined) ?? 0,
      size: safeNumber(raw['size']),
      count: safeNumber(raw['count']),
      categories
    });
  }
  chats.sort((left: ChatStorageUsage, right: ChatStorageUsage): number => right.size - left.size);
  return {
    size: safeNumber(res['size']), count: safeNumber(res['count']),
    categories: sortedCategories(totalCategories), chats
  };
}

// size/ttl/count are explicit zero targets. Unlike -1 (TDLib defaults), this
// reliably removes every eligible cached media file. TDLib deliberately keeps
// protected classes such as secret thumbnails; the UI describes the result as
// "可清理缓存" rather than promising the whole file database becomes empty.
export async function clearCache(): Promise<CacheClearResult> {
  return clearCacheSelection('', 0);
}

function tdFileTypes(category: string): TdObject[] {
  if (category === 'photo') { return [{ '@type': 'fileTypePhoto' }]; }
  if (category === 'video') {
    return [{ '@type': 'fileTypeVideo' }, { '@type': 'fileTypeVideoNote' }];
  }
  if (category === 'animation') { return [{ '@type': 'fileTypeAnimation' }]; }
  if (category === 'audio') { return [{ '@type': 'fileTypeAudio' }]; }
  if (category === 'voice') { return [{ '@type': 'fileTypeVoiceNote' }]; }
  if (category === 'sticker') { return [{ '@type': 'fileTypeSticker' }]; }
  if (category === 'file') { return [{ '@type': 'fileTypeDocument' }]; }
  if (category === 'thumbnail') { return [{ '@type': 'fileTypeThumbnail' }]; }
  if (category === 'profile') { return [{ '@type': 'fileTypeProfilePhoto' }]; }
  if (category === 'wallpaper') { return [{ '@type': 'fileTypeWallpaper' }]; }
  if (category === 'secret') { return [{ '@type': 'fileTypeSecret' }]; }
  return [];
}

export async function clearCacheSelection(category: string, chatId: number): Promise<CacheClearResult> {
  const request: TdRequest = { '@type': 'optimizeStorage' };
  request['size'] = 0;
  request['ttl'] = 0;
  request['count'] = 0;
  request['immunity_delay'] = 0;
  request['file_types'] = tdFileTypes(category);
  request['chat_ids'] = chatId !== 0 ? [chatId] : [];
  request['exclude_chat_ids'] = [];
  request['return_deleted_file_statistics'] = false;
  request['chat_limit'] = 0;
  const result = await getTdClient().send(request, 60000);
  return { remainingSize: safeNumber(result['size']), remainingCount: safeNumber(result['count']) };
}

function networkInfo(type: TdObject | undefined): NetworkBreakdown {
  const raw = type !== undefined ? ((type['@type'] as string | undefined) ?? '') : '';
  if (raw === 'networkTypeWiFi') { return { key: 'wifi', label: 'Wi‑Fi', sent: 0, received: 0, duration: 0 }; }
  if (raw === 'networkTypeMobile') { return { key: 'mobile', label: str('network_mobile'), sent: 0, received: 0, duration: 0 }; }
  if (raw === 'networkTypeMobileRoaming') { return { key: 'roaming', label: str('network_roaming'), sent: 0, received: 0, duration: 0 }; }
  return { key: 'other', label: str('network_other'), sent: 0, received: 0, duration: 0 };
}

function fileNetworkCategory(type: TdObject | undefined): NetworkBreakdown {
  const storage = fileTypeInfo(type);
  return { key: storage.key, label: storage.label, sent: 0, received: 0, duration: 0 };
}

function addNetwork(target: Map<string, NetworkBreakdown>, item: NetworkBreakdown): void {
  const existing = target.get(item.key);
  if (existing === undefined) { target.set(item.key, item); return; }
  existing.sent += item.sent;
  existing.received += item.received;
  existing.duration += item.duration;
}

function sortedNetwork(map: Map<string, NetworkBreakdown>): NetworkBreakdown[] {
  return Array.from(map.values()).filter((item: NetworkBreakdown): boolean =>
    item.sent > 0 || item.received > 0 || item.duration > 0)
    .sort((left: NetworkBreakdown, right: NetworkBreakdown): number =>
      (right.sent + right.received) - (left.sent + left.received));
}

export async function getNetworkUsage(onlyCurrent: boolean = false): Promise<NetworkUsage> {
  const request: TdRequest = { '@type': 'getNetworkStatistics' };
  request['only_current'] = onlyCurrent;
  const res = await getTdClient().send(request, 15000);
  const entries = (res['entries'] as TdObject[] | undefined) ?? [];
  const byNetwork = new Map<string, NetworkBreakdown>();
  const byCategory = new Map<string, NetworkBreakdown>();
  let sent = 0;
  let received = 0;
  let callDuration = 0;
  for (const entry of entries) {
    const entrySent = safeNumber(entry['sent_bytes']);
    const entryReceived = safeNumber(entry['received_bytes']);
    const duration = safeNumber(entry['duration']);
    sent += entrySent;
    received += entryReceived;
    callDuration += duration;
    const network = networkInfo(entry['network_type'] as TdObject | undefined);
    network.sent = entrySent;
    network.received = entryReceived;
    network.duration = duration;
    addNetwork(byNetwork, network);
    const type = (entry['@type'] as string | undefined) ?? '';
    let category: NetworkBreakdown;
    if (type === 'networkStatisticsEntryCall') {
      category = { key: 'call', label: str('network_calls'), sent: 0, received: 0, duration: 0 };
    } else {
      category = fileNetworkCategory(entry['file_type'] as TdObject | undefined);
    }
    category.sent = entrySent;
    category.received = entryReceived;
    category.duration = duration;
    addNetwork(byCategory, category);
  }
  return {
    sent, received, callDuration,
    sinceDate: safeNumber(res['since_date']),
    byNetwork: sortedNetwork(byNetwork), byCategory: sortedNetwork(byCategory)
  };
}

export async function resetNetworkUsage(): Promise<void> {
  await getTdClient().send({ '@type': 'resetNetworkStatistics' } as TdRequest, 15000);
}

export async function clearAllDrafts(): Promise<void> {
  const request: TdRequest = { '@type': 'clearAllDraftMessages' };
  request['exclude_secret_chats'] = true;
  await getTdClient().send(request, 20000);
}

export async function prepareAutosaveSettings(): Promise<void> {
  await getTdClient().send({ '@type': 'getAutosaveSettings' } as TdRequest, 15000);
}

export async function syncAutosaveSettings(scope: string, enabled: boolean,
  maxVideoSize: number = 64 * 1024 * 1024): Promise<void> {
  const scopeType = scope === 'channel' ? 'autosaveSettingsScopeChannelChats'
    : (scope === 'group' ? 'autosaveSettingsScopeGroupChats' : 'autosaveSettingsScopePrivateChats');
  const settings: TdObject = { '@type': 'scopeAutosaveSettings' };
  settings['autosave_photos'] = enabled;
  settings['autosave_videos'] = enabled;
  settings['max_video_file_size'] = maxVideoSize;
  const request: TdRequest = { '@type': 'setAutosaveSettings' };
  request['scope'] = { '@type': scopeType } as TdObject;
  request['settings'] = settings;
  await getTdClient().send(request, 15000);
}

export async function applyCacheLimit(limitBytes: number): Promise<void> {
  if (!shouldTrimCache(limitBytes)) {
    return;
  }
  try {
    await getTdClient().send(buildCacheTrimRequest(limitBytes) as TdRequest, 60000);
  } catch (e) {
    const error = e as TdError;
    logE(`StorageApi.applyCacheLimit failed: ${error.message}`);
  }
}
