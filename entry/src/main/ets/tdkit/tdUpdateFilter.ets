// worker 内的可交换更新合并（A 批 2，勘探 docs/superpowers/specs/
// 2026-09-02-tdlib-worker-survey.md 问题 2）。
//
// 顺序语义是铁律：只有「同 key 后写覆盖先写」成立的更新类型才允许合并，
// **默认一律直通**。任何直通事件发出前必须先冲掉积压的合并项（见
// TdWorker.ets），保证与不可交换事件的相对顺序不变。
//
// 目前白名单只有 updateFile：同一 file.id 的下载进度流只有最新一条有意义，
// 而进度风暴正是滚动中最大的更新来源（媒体页翻动时每文件每秒可达十几条）。

import { TdObject } from './TdTypes';

// 返回合并键；'' 表示不可合并、必须直通。
export function coalesceKeyOf(update: TdObject): string {
  if (update['@type'] !== 'updateFile') {
    return '';
  }
  const file = update['file'] as TdObject | undefined;
  if (file === undefined) {
    return '';
  }
  const id = file['id'] as number | undefined;
  return id !== undefined ? `file:${id}` : '';
}
