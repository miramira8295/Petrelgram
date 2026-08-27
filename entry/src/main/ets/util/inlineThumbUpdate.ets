import { MessageEntry } from '../store/MessageEntry';

// 内联缩略图的 updateFile 到底有没有改动条目？
//
// TDLib 每秒发很多次 updateFile，其中大量是「同一个百分比又报了一遍」。
// applyFile 的内联缩略图分支已经不再 notify（进度和路径都走旁路通道），
// 但它仍然要把 photoPath / photoProgress 记进条目，供缓存落盘和全尺寸
// 分支的回填判定使用。没有实际改动时连克隆都不必做——一次 map 会给整条
// 消息列表（真机上 400+ 条）重新建数组、给命中的条目做深拷贝。
//
// landed 表示「这一次 updateFile 带来了已下载完成的真实路径」。
export function inlineThumbEntryChanged(
  entry: MessageEntry,
  percent: number,
  landed: boolean,
  path: string
): boolean {
  if (entry.photoProgress !== percent) {
    return true;
  }
  if (landed && (entry.photoPath !== path || entry.photoFailed)) {
    return true;
  }
  return false;
}
