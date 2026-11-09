// 可见范围的两个换算：视口行号的兜底，和媒体预载窗口的边界。
//
// 都很短，但夹逼的边界一旦写错就静默出事——媒体窗口算窄了，滑过去的图片
// 现取现下；算宽了，一屏之外的东西白白占带宽。

// 视口行号。首帧之前还没有滚动事件，curStart/curEnd 是 -1，此时用"末尾一屏"
// 兜底——聊天默认停在底部，猜末尾比猜开头准；滚动事件一到就会纠正。
export interface VisibleRange {
  start: number;
  end: number;
}

export function visibleRangeOrFallback(
  curStart: number, curEnd: number, rowCount: number, cachedCount: number
): VisibleRange {
  // curEnd < curStart 也算无效：onScrollIndex 还没给过一对有意义的值。
  const hasViewport: boolean = curStart >= 0 && curEnd >= curStart;
  if (hasViewport) {
    return { start: curStart, end: curEnd };
  }
  return {
    start: Math.max(0, rowCount - cachedCount - 1),
    end: Math.max(0, rowCount - 1)
  };
}

// 媒体预载窗口：把可见行区间外扩几行再换算成消息 id 区间。
//
// 外扩是为了滑动时不因一行之差反复取消又重下。上界取**末行的最后一个成员**
// 而不是行首：相册是一整行多条消息，取行首会把同一行里更新的那几条漏在窗外。
export const MEDIA_WINDOW_PAD: number = 3;

export interface MediaWindow {
  valid: boolean;
  fromId: number;
  toId: number;
}

export function mediaWindowRange(
  startIdx: number, endIdx: number, rowCount: number,
  headIdAt: (index: number) => number,
  lastMemberIdAt: (index: number) => number
): MediaWindow {
  if (rowCount <= 0) {
    return { valid: false, fromId: 0, toId: 0 };
  }
  const from: number = Math.max(0, startIdx - MEDIA_WINDOW_PAD);
  const to: number = Math.min(rowCount - 1, endIdx + MEDIA_WINDOW_PAD);
  if (from > to) {
    return { valid: false, fromId: 0, toId: 0 };
  }
  return { valid: true, fromId: headIdAt(from), toId: lastMemberIdAt(to) };
}
