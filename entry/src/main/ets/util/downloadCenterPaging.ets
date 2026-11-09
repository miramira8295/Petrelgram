import { DC_STATE_COMPLETE, DownloadCenterItem } from './downloadCenterModel';

// 下载中心分页的纯逻辑（2026-09-15 第四版）。
//
// 三路来源各自分页、各自按时间新到旧。「已完成」段是三路按时间合并的：某一路还没翻到的旧条目，可能比别路
// 已经显示的还新——全显示的话，续拉一页时新条目会插进已显示的行中间。
// 做法：每一路记下已加载部分里最旧的时间（前沿）；还有下一页的那几路里，最新的前沿就是水位线，
// 「已完成」只显示水位线以上的。续拉之后水位线下移，新露出的条目只会接在末尾。进行中的不受水位线限制。

export interface DcSourceWindow {
  hasMore: boolean;
  loadedCount: number;
  oldestLoadedMtime: number; // 毫秒
}

export function doneWatermark(windows: DcSourceWindow[]): number {
  let mark: number = Number.NEGATIVE_INFINITY;
  for (const w of windows) {
    if (!w.hasMore) {
      continue;
    }
    // 还有下一页却一条都没加载：什么都保证不了，整段先压住。
    const frontier: number = w.loadedCount > 0 ? w.oldestLoadedMtime : Number.POSITIVE_INFINITY;
    mark = Math.max(mark, frontier);
  }
  return mark;
}

export function applyDoneWatermark(items: DownloadCenterItem[], watermark: number): DownloadCenterItem[] {
  if (watermark === Number.NEGATIVE_INFINITY) {
    return items;
  }
  return items.filter((it: DownloadCenterItem): boolean => it.state !== DC_STATE_COMPLETE || it.mtime >= watermark);
}

export function oldestMtime(items: DownloadCenterItem[]): number {
  let oldest: number = Number.POSITIVE_INFINITY;
  for (const it of items) {
    oldest = Math.min(oldest, it.mtime);
  }
  return oldest;
}

// 当前页签条目太少（筛选后的页签、搜索）又还有下一页：自动续拉，不等滑到底——内容撑不满一屏时根本滑不动。
export const DC_MIN_VISIBLE_ITEMS: number = 30;

export function shouldTopUp(visibleItems: number, hasMore: boolean, busy: boolean): boolean {
  return hasMore && !busy && visibleItems < DC_MIN_VISIBLE_ITEMS;
}
