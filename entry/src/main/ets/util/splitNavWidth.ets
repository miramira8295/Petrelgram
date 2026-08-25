import { KEY_SPLIT_NAV_WIDTH, setNumber } from '../store/AppSettings';

// 平板分栏下左栏宽度的记忆（issue #106：重启后要重新拖分割线）。
//
// HdsNavigation 只有 navBarWidth 一个写入口，没有"用户拖到了多宽"的回调。
// 但三个页签本来就在用 onAreaChange 量 navBar 宽（dock 要跟着走），量到的
// 就是拖动结果——在那里记下来即可。

// 启动时该给 navBarWidth 的值。
//
// 没记过（saved ≤ 0）时给 min：HdsNavigation 内部默认 240vp，被 range 一夹落在
// 离 240 最近的那一端，宽屏上就是 min——这正是此前的静息宽度，行为不变。
// 记过则夹进当前区间：窗口尺寸变了（转屏、分屏）区间跟着变，上次的值可能
// 越界，越界直接喂进去 HDS 会按默认值处理，等于白记。
export function resolveSplitNavWidth(savedVp: number, minVp: number, maxVp: number): number {
  if (!(savedVp > 0)) {
    return minVp;
  }
  return Math.max(minVp, Math.min(maxVp, savedVp));
}

// 拖动过程中 onAreaChange 每帧都来。**松手后再写**：写入会经 AppStorage 回到
// navBarWidth，拖到一半就回写等于每帧把 navBarWidth 设成当前值，和拖拽手势
// 打架。停 400ms 没再变才算松手。
const SETTLE_MS: number = 400;
let settleTimer: number = -1;
let lastSeen: number = 0;

// 只在分栏下记：单栏时 navBar 铺满整个窗口，那个宽度不是用户选的。
export function rememberSplitNavWidth(widthVp: number, splitLayout: boolean): void {
  if (!splitLayout || !(widthVp > 0)) {
    return;
  }
  lastSeen = Math.round(widthVp);
  if (settleTimer !== -1) {
    clearTimeout(settleTimer);
  }
  settleTimer = setTimeout((): void => {
    settleTimer = -1;
    if (AppStorage.get<number>(KEY_SPLIT_NAV_WIDTH) !== lastSeen) {
      setNumber(KEY_SPLIT_NAV_WIDTH, lastSeen);
    }
  }, SETTLE_MS);
}
