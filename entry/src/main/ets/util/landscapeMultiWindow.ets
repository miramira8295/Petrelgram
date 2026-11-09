// 横向悬浮窗 / 上下分屏的开关仲裁（官方多设备适配规格 SPEC-15，2026-09-23 用户确认）。
//
// module.json5 的 EntryAbility 声明了 preferMultiWindowOrientation: "landscape_auto"：
// 多窗布局方向**可以动态变为横向**，但要配合 window.enableLandscapeMultiWindow() /
// disableLandscapeMultiWindow() 使用，且只在系统识别应用为横向全屏播放时生效
// （官方《应用声明支持智慧多窗》）。于是这两个调用挂在「进入横屏播放 / 回到竖屏」上。
//
// 与 util/screenAwake 同一种写法：**纯记账，不碰系统**。窗口上只有一个开关，直播全屏和
// 媒体查看器转横屏两处都可能要它；各调各的，先退场的一句 disable 会把另一处也关掉。
// 记持有者集合：有人要就开着，全放开才关；只有空/非空翻转时才需要碰一次窗口。

const owners: Set<string> = new Set<string>();
let applied: boolean = false;

export const LANDSCAPE_OWNER_LIVE: string = 'live';
export const LANDSCAPE_OWNER_MEDIA: string = 'media';

// 返回需要推给窗口的新状态；不需要碰窗口时返回 null。
export function requestLandscapeMultiWindow(owner: string, on: boolean): boolean | null {
  if (owner === '') {
    return null;
  }
  if (on) {
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

// 推给窗口失败时回滚记账，下一次请求会再试一次，而不是以为已经开着。
export function landscapeMultiWindowApplyFailed(wanted: boolean): void {
  if (applied === wanted) {
    applied = !wanted;
  }
}

// 仅供单测复位。
export function resetLandscapeMultiWindowForTest(): void {
  owners.clear();
  applied = false;
}
