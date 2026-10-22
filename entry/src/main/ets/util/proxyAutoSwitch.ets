export const PROXY_SWITCH_DELAYS: number[] = [5, 10, 15, 30, 60];
export const PROXY_SWITCH_DELAY_DEFAULT: number = 10;

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
