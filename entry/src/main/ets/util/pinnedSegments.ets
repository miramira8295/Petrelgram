// 置顶消息条左侧那一列进度格的算法。
//
// 会话可以置顶很多条，条上只画得下 5 格，于是要开一个滑动窗口。这段算术
// 此前是页面里五个互相调用的私有方法，边界全靠脑补：置顶数为 0、只有 1 条、
// 恰好等于窗口宽度、cycle 越过末尾（取消置顶后 pinnedCount 变小而 cycle 没跟着
// 退）——每一种都能画出错误的高亮格或者空列。
//
// 显示顺序要反一次：cycle 是"从最新往回数第几条"，格子却按时间从旧到新排，
// 所以最新的那条对应最后一格。

export const PINNED_SEG_MAX: number = 5;

// 当前显示的是第几条（从最新往回数，0 是最新）。cycle 可能落在 count 之外
// ——取消置顶时 count 会先变小——所以在这里夹一次。
export function pinnedShownIndex(cycle: number, count: number): number {
  return Math.min(Math.max(0, cycle), Math.max(0, count - 1));
}

// 画几格。
export function pinnedSegCount(count: number): number {
  return Math.min(Math.max(0, count), PINNED_SEG_MAX);
}

// 当前条在"从旧到新"这个顺序里的下标。
export function pinnedDisplayActive(cycle: number, count: number): number {
  return Math.max(0, count - 1 - pinnedShownIndex(cycle, count));
}

// 窗口左端。置顶数不超过窗口时不滑动；否则让当前条尽量落在窗口末尾，同时
// 不越过两端。
export function pinnedSegStart(cycle: number, count: number): number {
  const n: number = pinnedSegCount(count);
  if (count <= n) {
    return 0;
  }
  const s: number = pinnedDisplayActive(cycle, count) - (n - 1);
  return Math.max(0, Math.min(s, count - n));
}

// 高亮第几格（窗口内的下标）。
export function pinnedActiveSeg(cycle: number, count: number): number {
  return pinnedDisplayActive(cycle, count) - pinnedSegStart(cycle, count);
}

// 格子的下标序列，给 ForEach 用。
export function pinnedSegIndices(count: number): number[] {
  const n: number = pinnedSegCount(count);
  const a: number[] = [];
  for (let i = 0; i < n; i++) {
    a.push(i);
  }
  return a;
}
