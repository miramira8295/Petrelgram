export const PROXY_SWITCH_DELAYS: number[] = [5, 10, 15, 30, 60];
export const PROXY_SWITCH_DELAY_DEFAULT: number = 10;

// 自动切换的总闸。false 时：设置里不出现这个开关、存量的 true 也不生效、
// tcping 巡检不会启动。
//
// 【为什么当初关掉】它以前能做到"换上备用代理不掉线"，靠的是中继层在内部换
// 路由——一个 TDLib 请求都不用发。中继层删掉之后，每次切换都等于
// enableProxy/disableProxy，TDLib 要全量重连；弱网下连切几次就是用户抱怨的
// "一直连接中"。
//
// 【重做成了什么样】判据从"TDLib 端到端 ping（pingProxy）"换成"本机对代理
// 服务器做 tcping"，30 秒一轮、只在前台且勾选时跑；规则见 util/proxyHealth.ets
// 和 services/ProxyHealthMonitor.ets。切换仍然只在"连接持续失败"时发生，
// 但候选的取舍变成"最快的先试、正在失败的沉底"。
//
// 【翻成 true 之前还欠什么】真机验证一件事：从"卡住"到"切换"这段延迟
// （PROXY_SWITCH_DELAY_SEC，默认 10 秒）在弱网下会不会太早——TDLib 慢速重连
// 时本来就该多等一会儿。判据是 [Conn] 日志里的 held= 值。
export const PROXY_AUTO_SWITCH_AVAILABLE: boolean = false;

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
