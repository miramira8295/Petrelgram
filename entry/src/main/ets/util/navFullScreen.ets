// 媒体查看器要不要盖住整个窗口（issue #139）。
//
// **问题**：查看器是 ChatPage 内部的一个图层，`height('100%')` 量的是 ChatPage
// 自己。分栏（平板）模式下 ChatPage 只占右栏，于是「全屏」看图/看视频只铺满
// 右栏，左边的会话列表还占着位置。
//
// **历程**：
//   1. 99633308：NavDestination.fullScreenOverlay(true)（API 26 起），低版本仍只占右栏；
//   2. d53fa690：顶栏迁进 HdsNavDestination，它没有 fullScreenOverlay，改挂
//      bindContentCover 全模态——**全模态里视频画面显示不出来**（issue #201：平板
//      分栏看视频黑屏，取消分栏就能播）；
//   3. 现在：查看器始终留在页面内。分栏下开着时发布 util/viewerWindowCover 的标志，
//      ChatListPage 收左栏（Split + hideNavBar = 单栏）、MainScreen 收 dock / 侧边页签，
//      右栏的 ChatPage 于是铺满窗口。
//
// 本文件只放纯判据，**不 import 任何 kit**：deviceInfo 是设备常量，宿主单测里
// 读不到真值（和 diagLogHeader / tdDeviceParams 同一个理由）。真正去读版本号并
// 挂属性的那层在 navFullScreenModifier.ets。

// fullScreenOverlay 的起始版本。本应用底线是 6.0.0(20)，所以必须带闸。
export const FULL_SCREEN_OVERLAY_API: number = 26;

export function fullScreenOverlayWinsAt(apiVersion: number): boolean {
  return apiVersion >= FULL_SCREEN_OVERLAY_API;
}

// 分栏且查看器开着 → 要收左栏和 dock，让页面内的查看器盖满窗口。
// 单栏（手机）下 ChatPage 本来就占满窗口，恒返回 false——手机上什么都不动。
export function viewerFullScreenWanted(splitLayout: boolean, viewerOpen: boolean): boolean {
  return splitLayout && viewerOpen;
}

// 查看器开着就把标题栏收起来。
//
// 顶栏迁进 HdsNavDestination 的标题栏之后，它是**框架层、永远画在内容区之上**，
// 而查看器在内容区里——不收的话全屏看图时顶栏浮在图上不走。单栏、分栏都一样：
// 分栏原来走 bindContentCover（模态在标题栏之上）才不用收，现在两边都在页面内。
export function viewerHidesTitleBar(viewerOpen: boolean): boolean {
  return viewerOpen;
}
