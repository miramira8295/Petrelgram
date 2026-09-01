export const PROXY_SWITCH_DELAYS: number[] = [5, 10, 15, 30, 60];
export const PROXY_SWITCH_DELAY_DEFAULT: number = 10;

export interface ProxySwitchCandidate {
  id: number;
}

export function normalizeProxySwitchDelay(value: number): number {
  return PROXY_SWITCH_DELAYS.indexOf(value) >= 0 ? value : PROXY_SWITCH_DELAY_DEFAULT;
}

// TDLib keeps the saved proxy order. Start immediately after the active item
// and wrap once, which matches the user's "next proxy" expectation.
export function orderedProxyCandidateIds(
  entries: ProxySwitchCandidate[], activeProxyId: number
): number[] {
  if (entries.length === 0) { return []; }
  const activeIndex = entries.findIndex(
    (entry: ProxySwitchCandidate): boolean => entry.id === activeProxyId
  );
  if (activeIndex < 0) {
    return entries.filter((entry: ProxySwitchCandidate): boolean => entry.id > 0)
      .map((entry: ProxySwitchCandidate): number => entry.id);
  }
  const result: number[] = [];
  for (let offset = 1; offset < entries.length; offset++) {
    const entry = entries[(activeIndex + offset) % entries.length];
    if (entry.id > 0) { result.push(entry.id); }
  }
  return result;
}
