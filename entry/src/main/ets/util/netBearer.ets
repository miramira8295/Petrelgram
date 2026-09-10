// 网络承载类型 → 我们内部的网络种类（纯函数，有单测）。
//
// 【为什么单独抽出来】NetworkStateService.classify() 原来只认 Wi-Fi / 蜂窝，
// 默认网络走 VPN 时 bearer 是 BEARER_VPN，落到 'other'。后果两个：
//   1. 视频预取全被 `network=other` 拒掉（2026-09-09 真机日志 30/30，用户状态栏
//      一直挂着 VPN）；
//   2. TDLib 一直被告知 networkTypeOther。
// VPN 只是一层壳，底下不是 Wi-Fi 就是蜂窝。默认网络是 VPN 时去 getAllNets()
// 里找那个物理承载；找不到就如实报 'vpn'——调用方决定怎么对待它。
//
// 【不在这里 import @kit.NetworkKit】枚举值由调用方传进来（BearerIds），本文件
// 只做判定，单测不用碰平台模块。

export interface BearerIds {
  wifi: number;      // connection.NetBearType.BEARER_WIFI
  cellular: number;  // connection.NetBearType.BEARER_CELLULAR
  vpn: number;       // connection.NetBearType.BEARER_VPN
}

export const NET_KIND_WIFI: string = 'wifi';
export const NET_KIND_CELLULAR: string = 'cellular';  // 调用方再分 mobile / roaming
export const NET_KIND_VPN: string = 'vpn';
export const NET_KIND_OTHER: string = 'other';
export const NET_KIND_NONE: string = 'none';

export function bearerKindOf(bearers: number[], ids: BearerIds): string {
  if (bearers.indexOf(ids.wifi) >= 0) {
    return NET_KIND_WIFI;
  }
  if (bearers.indexOf(ids.cellular) >= 0) {
    return NET_KIND_CELLULAR;
  }
  if (bearers.indexOf(ids.vpn) >= 0) {
    return NET_KIND_VPN;
  }
  return bearers.length > 0 ? NET_KIND_OTHER : NET_KIND_NONE;
}

// 默认网络是 VPN 时，从其余可用网络里挑物理承载：Wi-Fi 优先于蜂窝。
// 不是 VPN 就原样返回；VPN 下面什么都没找到也原样返回 'vpn'。
export function resolveThroughVpn(defaultKind: string, otherKinds: string[]): string {
  if (defaultKind !== NET_KIND_VPN) {
    return defaultKind;
  }
  if (otherKinds.indexOf(NET_KIND_WIFI) >= 0) {
    return NET_KIND_WIFI;
  }
  if (otherKinds.indexOf(NET_KIND_CELLULAR) >= 0) {
    return NET_KIND_CELLULAR;
  }
  return NET_KIND_VPN;
}
