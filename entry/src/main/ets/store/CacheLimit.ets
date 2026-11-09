import { TdObject } from '../tdkit/TdTypes';

// 缓存上限。取代旧的 21 个自动下载开关：用户只需回答"最多占多少"，
// 超出后由 TDLib 按最久未使用顺序淘汰。
//
// optimizeStorage 的语义要小心：size 传 0 是"删干净"而不是"不限"
// （StorageApi.clearCacheSelection 正是靠这一点做一键清理）。所以这里
// 用 0 表示"不限"并在调用前拦截，绝不把 0 传给 TDLib。
export const CACHE_LIMIT_UNLIMITED: number = 0;
const GB: number = 1024 * 1024 * 1024;
export const CACHE_LIMIT_DEFAULT: number = 4 * GB;
export const CACHE_LIMIT_OPTIONS: number[] = [GB, 2 * GB, 4 * GB, 8 * GB, CACHE_LIMIT_UNLIMITED];

export function shouldTrimCache(limitBytes: number): boolean {
  return Number.isFinite(limitBytes) && limitBytes > 0;
}

// 切前台就收缩一次会让频繁切换的用户反复跑重操作，加最小间隔。
export const CACHE_TRIM_MIN_INTERVAL_MS: number = 30 * 60 * 1000;

export function shouldTrimNow(limitBytes: number, lastTrimAt: number, now: number): boolean {
  if (!shouldTrimCache(limitBytes)) {
    return false;
  }
  return lastTrimAt <= 0 || now - lastTrimAt >= CACHE_TRIM_MIN_INTERVAL_MS;
}

// ttl / count / immunity_delay 传 -1 = 用 TDLib 默认值，只由 size 施加约束。
export function buildCacheTrimRequest(limitBytes: number): TdObject {
  const request: TdObject = { '@type': 'optimizeStorage' };
  request['size'] = limitBytes;
  request['ttl'] = -1;
  request['count'] = -1;
  request['immunity_delay'] = -1;
  request['file_types'] = [];
  request['chat_ids'] = [];
  request['exclude_chat_ids'] = [];
  request['return_deleted_file_statistics'] = false;
  request['chat_limit'] = 0;
  return request;
}
