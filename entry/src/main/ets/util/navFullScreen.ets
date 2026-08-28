// 媒体查看器要不要盖住整个窗口（issue #139）。
//
// **问题**：查看器是 ChatPage 内部的一个图层，`height('100%')` 量的是 ChatPage
// 自己。分栏（平板）模式下 ChatPage 只占右栏，于是「全屏」看图/看视频只铺满
// 右栏，左边的会话列表还占着位置。
//
// **解法**：NavDestination.fullScreenOverlay(true) —— 官方语义就是「本页以全屏
// 覆盖模式显示，盖住整个 navigation 容器」，正好跨过分栏。查看器一关就摘掉，
// ChatPage 缩回右栏。
//
// 本文件只放纯判据，**不 import 任何 kit**：deviceInfo 是设备常量，宿主单测里
// 读不到真值（和 diagLogHeader / tdDeviceParams 同一个理由）。真正去读版本号并
// 挂属性的那层在 navFullScreenModifier.ets。

// fullScreenOverlay 的起始版本。本应用底线是 6.0.0(20)，所以必须带闸。
export const FULL_SCREEN_OVERLAY_API: number = 26;

export function fullScreenOverlayWinsAt(apiVersion: number): boolean {
  return apiVersion >= FULL_SCREEN_OVERLAY_API;
}

// 单栏（手机）下 ChatPage 本来就占满窗口，查看器不需要这一手——恒返回 false，
// 免得白挂一个属性、白走一次布局。
export function viewerFullScreenWanted(splitLayout: boolean, viewerOpen: boolean): boolean {
  return splitLayout && viewerOpen;
}
