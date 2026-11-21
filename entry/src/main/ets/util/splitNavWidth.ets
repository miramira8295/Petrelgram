import { KEY_SPLIT_NAV_WIDTH, setNumber } from '../store/AppSettings';

// 平板分栏下左栏宽度的记忆（issue #106：重启后要重新拖分割线）。
//
// HdsNavigation 只有 navBarWidth 一个写入口，没有"用户拖到了多宽"的回调。
// 但三个页签本来就在用 onAreaChange 量 navBar 宽（dock 要跟着走），量到的
// 就是拖动结果——在那里记下来即可。

// 启动时该给 navBarWidth 的值。
//
// 未设置时取窗口的 40%，已有宽度则限制在当前窗口的可拖范围内。
export function resolveSplitNavWidth(savedVp: number, minVp: number, maxVp: number): number {
  if (!(savedVp > 0)) {
    return maxVp;
  }
  return Math.max(minVp, Math.min(maxVp, savedVp));
}

// 拖动过程中 onAreaChange 每帧都来。**松手后再写**：写入会经 AppStorage 回到
// navBarWidth，拖到一半就回写等于每帧把 navBarWidth 设成当前值，和拖拽手势
// 打架。停 400ms 没再变才算松手。
const SETTLE_MS: number = 400;
let settleTimer: number = -1;

// 只在分栏下记：单栏时 navBar 铺满整个窗口，那个宽度不是用户选的。
export function rememberSplitNavWidth(widthVp: number, splitLayout: boolean, minVp: number, maxVp: number): void {
  if (!splitLayout || !(widthVp > 0)) {
    return;
  }
  if (settleTimer !== -1) {
    clearTimeout(settleTimer);
    settleTimer = -1;
  }
  const measured = Math.round(widthVp);
  const saved = AppStorage.get<number>(KEY_SPLIT_NAV_WIDTH) ?? 0;
  // 自适应布局也会触发测量，只有偏离指定宽度才是新的拖动位置。
  if (measured < minVp || measured > maxVp ||
    Math.abs(widthVp - resolveSplitNavWidth(saved, minVp, maxVp)) < 1) { return; }
  settleTimer = setTimeout((): void => {
    settleTimer = -1;
    if (AppStorage.get<number>(KEY_SPLIT_NAV_WIDTH) !== measured) {
      setNumber(KEY_SPLIT_NAV_WIDTH, measured);
    }
  }, SETTLE_MS);
}
