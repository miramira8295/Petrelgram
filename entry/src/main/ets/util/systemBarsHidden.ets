// 「系统栏（状态栏 + 导航条）藏不藏」的仲裁。
//
// 【为什么需要仲裁】setWindowSystemBarEnable 是窗口上的**一个**开关，谁最后调谁
// 说了算。原来只有直播全屏在用；2026-09-29 媒体查看器也要跟着控制栏藏/显系统栏
// （用户：「图片全屏显示的时候没有把那个状态栏覆盖」，要求状态栏和导航条全藏）。
// 两边各调各的会互相掐：一个退场时一句「恢复」就把另一个的全屏也破了。
//
// 做法同 util/screenAwake：记**持有者集合**，有人要藏就藏，全部放开才恢复；只有
// 集合空/非空翻转时才碰窗口。持有者名字按实例取，免得两个同类实例共用一个名字、
// 先退场的把后来的一起放掉。
//
// 本文件**纯记账、不碰窗口**（单测直接引它）；真正调窗口的在 util/systemBarsWindow。
const owners: Set<string> = new Set<string>();
// 最后一次真正推给窗口的值。
let applied: boolean = false;

export const SYSTEM_BARS_OWNER_LIVE: string = 'live';
let viewerOwnerSeq: number = 0;

export function viewerSystemBarsOwner(): string {
  viewerOwnerSeq++;
  return `viewer:${viewerOwnerSeq}`;
}

// 登记/注销一个持有者，返回需要推给窗口的新状态，不需要推时返回 null。
// 调用方照这个返回值决定要不要碰窗口，别自己判断。
export function requestSystemBarsHidden(owner: string, hidden: boolean): boolean | null {
  if (owner === '') {
    return null;
  }
  if (hidden) {
    owners.add(owner);
  } else {
    owners.delete(owner);
  }
  const wanted: boolean = owners.size > 0;
  if (wanted === applied) {
    return null;
  }
  applied = wanted;
  return wanted;
}

// 窗口调用失败时回滚记账，否则 applied 会一直声称推成功过，下一次同方向的
// 请求被当成"没变化"而永远不再重试。
export function systemBarsApplyFailed(attempted: boolean): void {
  if (applied === attempted) {
    applied = !attempted;
  }
}

export function systemBarsOwnerCount(): number {
  return owners.size;
}

// 单测用：把记账清零。
export function resetSystemBarsHiddenForTest(): void {
  owners.clear();
  applied = false;
  viewerOwnerSeq = 0;
}
