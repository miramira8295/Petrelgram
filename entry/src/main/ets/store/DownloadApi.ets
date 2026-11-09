import { TdClient } from '../tdkit/TdClient';
import { TdObject, TdRequest, TdError } from '../tdkit/TdTypes';
import { formatPreview } from '../util/formatPreview';
import { str } from '../util/strings';

// TDLib 的下载管理器（searchFileDownloads 系列）与磁盘扫描是两套数据源：
// 只有下载管理器登记过的文件才能被暂停/继续/移除，所以这里的模型以
// file_id 为主键，UI 侧凡是没有 file_id 的历史文件都不提供操作入口。

const DOWNLOAD_TIMEOUT_MS: number = 15000;
// TDLib 服务端对单页 limit 不设硬上限，但一次拉太多会拖慢首屏，取和列表页一致的 50。
const DEFAULT_PAGE_LIMIT: number = 50;
const MAX_PAGE_LIMIT: number = 200;

export interface DownloadCounts {
  activeCount: number;
  pausedCount: number;
  completedCount: number;
}

export interface DownloadEntry {
  fileId: number;
  chatId: number;
  messageId: number;
  // 来源消息的可读摘要，UI 用它做副标题；消息缺失时为空串。
  preview: string;
  // 原始文件名（document/video/audio 才有），UI 用它做标题；取不到时为空串。
  fileName: string;
  addDate: number;      // 秒
  completeDate: number; // 秒，0 表示尚未完成
  isPaused: boolean;
  // 来源消息的内容类型（message.content['@type']），下载中心据此分类；取不到为空串。
  contentType?: string;
}

export interface DownloadPage {
  counts: DownloadCounts;
  entries: DownloadEntry[];
  // TDLib 的游标分页：空串表示没有下一页。
  nextOffset: string;
}

export interface DownloadQuery {
  query: string;
  onlyActive: boolean;
  onlyCompleted: boolean;
  offset: string;
  limit: number;
}

export function emptyDownloadCounts(): DownloadCounts {
  return { activeCount: 0, pausedCount: 0, completedCount: 0 };
}

export function emptyDownloadPage(): DownloadPage {
  return { counts: emptyDownloadCounts(), entries: [], nextOffset: '' };
}

export function defaultDownloadQuery(): DownloadQuery {
  return { query: '', onlyActive: false, onlyCompleted: false, offset: '', limit: DEFAULT_PAGE_LIMIT };
}

function safeCount(value: Object | undefined): number {
  const parsed = value as number | undefined;
  return parsed !== undefined && Number.isFinite(parsed) && parsed > 0 ? Math.floor(parsed) : 0;
}

function clampLimit(limit: number): number {
  if (!Number.isFinite(limit) || limit <= 0) {
    return DEFAULT_PAGE_LIMIT;
  }
  return Math.min(MAX_PAGE_LIMIT, Math.round(limit));
}

// —— 请求构造（纯函数，便于单测断言 JSON 形状）——

export function buildSearchDownloadsRequest(query: DownloadQuery): TdRequest {
  const request: TdRequest = { '@type': 'searchFileDownloads' };
  request['query'] = query.query;
  request['only_active'] = query.onlyActive;
  request['only_completed'] = query.onlyCompleted;
  request['offset'] = query.offset;
  request['limit'] = clampLimit(query.limit);
  return request;
}

export function buildTogglePausedRequest(fileId: number, isPaused: boolean): TdRequest {
  const request: TdRequest = { '@type': 'toggleDownloadIsPaused' };
  request['file_id'] = fileId;
  request['is_paused'] = isPaused;
  return request;
}

export function buildToggleAllPausedRequest(arePaused: boolean): TdRequest {
  const request: TdRequest = { '@type': 'toggleAllDownloadsArePaused' };
  request['are_paused'] = arePaused;
  return request;
}

export function buildRemoveDownloadRequest(fileId: number, deleteFromCache: boolean): TdRequest {
  const request: TdRequest = { '@type': 'removeFileFromDownloads' };
  request['file_id'] = fileId;
  request['delete_from_cache'] = deleteFromCache;
  return request;
}

export function buildRemoveAllDownloadsRequest(
  onlyActive: boolean, onlyCompleted: boolean, deleteFromCache: boolean
): TdRequest {
  const request: TdRequest = { '@type': 'removeAllFilesFromDownloads' };
  request['only_active'] = onlyActive;
  request['only_completed'] = onlyCompleted;
  request['delete_from_cache'] = deleteFromCache;
  return request;
}

export function buildAddToDownloadsRequest(
  fileId: number, chatId: number, messageId: number, priority: number
): TdRequest {
  const request: TdRequest = { '@type': 'addFileToDownloads' };
  request['file_id'] = fileId;
  request['chat_id'] = chatId;
  request['message_id'] = messageId;
  // TDLib 只接受 1..32 的优先级，越界会直接报错，这里在边界处收敛。
  request['priority'] = Math.max(1, Math.min(32, Math.round(priority)));
  return request;
}

// —— 响应解析 ——

export function parseDownloadCounts(raw: TdObject | undefined): DownloadCounts {
  if (raw === undefined) {
    return emptyDownloadCounts();
  }
  return {
    activeCount: safeCount(raw['active_count']),
    pausedCount: safeCount(raw['paused_count']),
    completedCount: safeCount(raw['completed_count'])
  };
}

// TDLib 把文件名放在具体的媒体子对象里，没有统一字段，只能逐类兜底。
export function downloadFileName(message: TdObject | undefined): string {
  const content = message !== undefined ? (message['content'] as TdObject | undefined) : undefined;
  if (content === undefined) {
    return '';
  }
  const keys: string[] = ['document', 'video', 'audio', 'animation'];
  for (const key of keys) {
    const media = content[key] as TdObject | undefined;
    const name = media !== undefined ? ((media['file_name'] as string | undefined) ?? '') : '';
    if (name !== '') {
      return name;
    }
  }
  return '';
}

export function parseDownloadEntry(raw: TdObject): DownloadEntry {
  const message = raw['message'] as TdObject | undefined;
  const content = message !== undefined ? (message['content'] as TdObject | undefined) : undefined;
  return {
    fileName: downloadFileName(message),
    contentType: content !== undefined ? ((content['@type'] as string | undefined) ?? '') : '',
    fileId: (raw['file_id'] as number | undefined) ?? 0,
    chatId: message !== undefined ? ((message['chat_id'] as number | undefined) ?? 0) : 0,
    messageId: message !== undefined ? ((message['id'] as number | undefined) ?? 0) : 0,
    preview: message !== undefined ? formatPreview(message) : '',
    addDate: safeCount(raw['add_date']),
    completeDate: safeCount(raw['complete_date']),
    isPaused: (raw['is_paused'] as boolean | undefined) ?? false
  };
}

export function parseDownloadPage(res: TdObject): DownloadPage {
  const files = (res['files'] as TdObject[] | undefined) ?? [];
  const entries: DownloadEntry[] = [];
  for (const raw of files) {
    const entry = parseDownloadEntry(raw);
    // file_id 是操作主键，缺失的条目无法暂停/移除，直接丢弃而不是渲染死行。
    if (entry.fileId !== 0) {
      entries.push(entry);
    }
  }
  return {
    counts: parseDownloadCounts(res['total_counts'] as TdObject | undefined),
    entries,
    nextOffset: (res['next_offset'] as string | undefined) ?? ''
  };
}

// 把 TDLib 错误翻译成用户能看懂的中文；未知错误保留原文便于排查。
export function downloadErrorMessage(action: string, error: Object): string {
  const tdError = error as TdError | undefined;
  const raw = tdError !== undefined && tdError.message !== undefined ? tdError.message : '';
  if (raw.includes('FILE_DOWNLOAD_ID_INVALID') || raw.includes('File is not being downloaded')) {
    return str('dl_not_in_list', action);
  }
  if (raw.includes('FILE_ID_INVALID') || raw.includes('Invalid file identifier')) {
    return str('dl_bad_id', action);
  }
  if (raw === '') {
    return str('dl_failed_retry', action);
  }
  return str('dl_failed_msg', action, raw);
}

// —— 网络调用（薄封装，错误原样抛出交由调用方转成 toast）——

export async function searchDownloads(client: TdClient, query: DownloadQuery): Promise<DownloadPage> {
  const res = await client.send(buildSearchDownloadsRequest(query), DOWNLOAD_TIMEOUT_MS);
  return parseDownloadPage(res);
}

export async function setDownloadPaused(client: TdClient, fileId: number, isPaused: boolean): Promise<void> {
  await client.send(buildTogglePausedRequest(fileId, isPaused), DOWNLOAD_TIMEOUT_MS);
}

export async function setAllDownloadsPaused(client: TdClient, arePaused: boolean): Promise<void> {
  await client.send(buildToggleAllPausedRequest(arePaused), DOWNLOAD_TIMEOUT_MS);
}

export async function removeDownload(client: TdClient, fileId: number, deleteFromCache: boolean): Promise<void> {
  await client.send(buildRemoveDownloadRequest(fileId, deleteFromCache), DOWNLOAD_TIMEOUT_MS);
}

export async function removeAllDownloads(
  client: TdClient, onlyActive: boolean, onlyCompleted: boolean, deleteFromCache: boolean
): Promise<void> {
  await client.send(
    buildRemoveAllDownloadsRequest(onlyActive, onlyCompleted, deleteFromCache), DOWNLOAD_TIMEOUT_MS);
}

export async function addToDownloads(
  client: TdClient, fileId: number, chatId: number, messageId: number, priority: number = 1
): Promise<void> {
  await client.send(buildAddToDownloadsRequest(fileId, chatId, messageId, priority), DOWNLOAD_TIMEOUT_MS);
}
