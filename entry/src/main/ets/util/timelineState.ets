// 消息列表顶上那颗状态胶囊：正在同步 / 加载更旧 / 加载更新，以及各自的失败态。
//
// 抽出来有两个理由。一是这几档的**优先级**是有讲究的：整段历史的错误盖过分页
// 的错误，错误盖过加载中，否则用户会看到"正在加载更旧"而实际上整个会话都没
// 拉起来。这个顺序原来只体现在一串 if 的先后上，改动时极易被打乱。
//
// 二是判断"这一档是加载还是失败"，原来写的是 mode.indexOf('Loading') >= 0 ——
// 靠名字里带不带某个词来分类。加一档叫 'reloadingTail' 就会被误判成加载中，
// 而且编译器一句话都不会说。现在改成显式列表。

import { str } from './strings';

export const TL_NONE: string = '';
export const TL_SYNC_ERROR: string = 'syncError';
export const TL_SYNC_LOADING: string = 'syncLoading';
export const TL_OLDER_ERROR: string = 'olderError';
export const TL_NEWER_ERROR: string = 'newerError';
export const TL_OLDER_LOADING: string = 'olderLoading';
export const TL_NEWER_LOADING: string = 'newerLoading';

const LOADING_MODES: string[] = [TL_SYNC_LOADING, TL_OLDER_LOADING, TL_NEWER_LOADING];
const ERROR_MODES: string[] = [TL_SYNC_ERROR, TL_OLDER_ERROR, TL_NEWER_ERROR];

// 胶囊上写什么。返回 str() 的结果：宿主单测里没装文案源，str() 原样返回 key，
// 断言因此落在"选了哪条文案"上。
export function timelineStateText(mode: string): string {
  if (mode === TL_SYNC_ERROR) {
    return str('cp_sync_failed');
  }
  if (mode === TL_SYNC_LOADING) {
    return str('cp_syncing_latest');
  }
  if (mode === TL_OLDER_ERROR) {
    return str('cp_older_failed');
  }
  if (mode === TL_NEWER_ERROR) {
    return str('cp_newer_failed');
  }
  return mode === TL_OLDER_LOADING ? str('cp_loading_older') : str('cp_loading_newer');
}

export function timelineLoading(mode: string): boolean {
  return LOADING_MODES.indexOf(mode) >= 0;
}

export function timelineError(mode: string): boolean {
  return ERROR_MODES.indexOf(mode) >= 0;
}

// 列表还空着的时候不出胶囊——那时整块空状态卡片已经在说同样的话了，两处一起
// 出现是重复。
export function timelineStateMode(
  visibleCount: number, messageLoadState: string,
  olderLoadState: string, newerLoadState: string
): string {
  if (visibleCount <= 0) {
    return TL_NONE;
  }
  // 顺序即优先级：整段历史 > 分页；失败 > 加载中。
  if (messageLoadState === 'error') {
    return TL_SYNC_ERROR;
  }
  if (messageLoadState === 'loading') {
    return TL_SYNC_LOADING;
  }
  if (olderLoadState === 'error') {
    return TL_OLDER_ERROR;
  }
  if (newerLoadState === 'error') {
    return TL_NEWER_ERROR;
  }
  if (olderLoadState === 'loading') {
    return TL_OLDER_LOADING;
  }
  if (newerLoadState === 'loading') {
    return TL_NEWER_LOADING;
  }
  return TL_NONE;
}
