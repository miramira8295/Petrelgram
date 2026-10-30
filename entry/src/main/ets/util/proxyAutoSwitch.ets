export const PROXY_SWITCH_DELAYS: number[] = [5, 10, 15, 30, 60];
export const PROXY_SWITCH_DELAY_DEFAULT: number = 10;

// 自动切换的总闸。true 时：设置里出现这个开关、按 KEY_PROXY_AUTO_SWITCH 的存储
// 值决定开不开、勾上才启动 tcping 巡检。false 是整体撤回用的（存量的 true 也
// 一概不认、巡检不启动、UI 整块不渲染）。
//
// 【判据】TDLib 没有"连接失败"事件：updateConnectionState 只有五态，代理死了
// 就是永远停在 ConnectingToProxy。所谓失败只能按"停在非 Ready 多久"推断——
// 超过 PROXY_SWITCH_DELAY_SEC（默认 10 秒）就换下一条候选。
//
// 【候选从哪来】util/proxyHealth.ets 的 tcping 表：30 秒一轮、仅前台且勾选时跑、
// 并发 2、单目标 3 秒（services/ProxyHealthMonitor.ets）。快的先试、正在失败的
// 沉底，直链永远兜底。
//
// 【代价与闸门】没有中继层了，换一次 = enableProxy/disableProxy，TDLib 要全量
// 重连。所以切换是**有界**的：绕完一圈（代理数 + 直链）还连不上就停手，等 Ready、
// 换网或用户手动选择再重新计数——见 ProxyAutoSwitchService.canArm。
export const PROXY_AUTO_SWITCH_AVAILABLE: boolean = true;

export interface ProxySwitchCandidate {
  id: number;
}

export function normalizeProxySwitchDelay(value: number): number {
  return PROXY_SWITCH_DELAYS.indexOf(value) >= 0 ? value : PROXY_SWITCH_DELAY_DEFAULT;
}

// TDLib keeps the saved proxy order. Normally start after the active item;
// after a rejected enable, continue after that attempted item without retrying
// the active proxy. A removed cursor falls back to the active item.
export function orderedProxyCandidateIds(
  entries: ProxySwitchCandidate[], activeProxyId: number, afterProxyId: number = activeProxyId
): number[] {
  if (entries.length === 0) { return []; }
  const routes: ProxySwitchCandidate[] = entries.filter((entry: ProxySwitchCandidate): boolean => entry.id > 0);
  routes.push({ id: 0 }); // The proxy adapter selects the direct relay route with disableProxy.
  let startIndex = routes.findIndex(
    (entry: ProxySwitchCandidate): boolean => entry.id === afterProxyId
  );
  if (startIndex < 0) {
    startIndex = routes.findIndex((entry: ProxySwitchCandidate): boolean => entry.id === activeProxyId);
  }
  const result: number[] = [];
  for (let offset = 1; offset <= routes.length; offset++) {
    const entry = routes[(startIndex + offset) % routes.length];
    if (entry.id !== activeProxyId) { result.push(entry.id); }
  }
  return result;
}
