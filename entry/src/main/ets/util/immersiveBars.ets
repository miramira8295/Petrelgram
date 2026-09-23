// 小方形屏的沉浸式浏览（官方 SPEC-04 [P1] 第 6 条，2026-09-23 用户确认实施）：
// 上滑临时隐藏标题栏和底部页签，下滑恢复。
//
// 只看**同一方向累计**的滑动量，不看单帧：惯性末尾和手指微抖会在正负之间来回，
// 按单帧判会让标题栏一闪一闪。方向一反就从零重新累计。

export const KEY_IMMERSIVE_BARS_HIDDEN: string = 'immersiveBarsHidden';

// 同方向累计滑过这么多才切换。
export const IMMERSIVE_TOGGLE_VP: number = 24;

export class ImmersiveBarsState {
  hidden: boolean = false;
  // 当前方向的累计量：正 = 内容往上走（往列表尾部滑），负 = 往回滑。
  accumulated: number = 0;
}

// delta：本帧滚动偏移的变化量（List.onDidScroll 的第一个参数），正数 = 往尾部滑。
// atTop：列表是否已经在最顶上——那时一律恢复显示，否则用户回到顶部还看不到标题。
// 返回新状态，不改入参。
export function nextImmersiveBars(prev: ImmersiveBarsState, delta: number,
  atTop: boolean): ImmersiveBarsState {
  const next: ImmersiveBarsState = new ImmersiveBarsState();
  if (atTop) {
    next.hidden = false;
    next.accumulated = 0;
    return next;
  }
  if (!Number.isFinite(delta) || delta === 0) {
    next.hidden = prev.hidden;
    next.accumulated = prev.accumulated;
    return next;
  }
  const sameDirection: boolean = (delta > 0) === (prev.accumulated > 0) || prev.accumulated === 0;
  const acc: number = sameDirection ? prev.accumulated + delta : delta;
  next.hidden = prev.hidden;
  next.accumulated = acc;
  if (!prev.hidden && acc >= IMMERSIVE_TOGGLE_VP) {
    next.hidden = true;
    next.accumulated = 0;
  } else if (prev.hidden && acc <= -IMMERSIVE_TOGGLE_VP) {
    next.hidden = false;
    next.accumulated = 0;
  }
  return next;
}
