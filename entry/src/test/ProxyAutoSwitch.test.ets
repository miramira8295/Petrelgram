import { describe, expect, it } from '@ohos/hypium';
import {
  normalizeProxySwitchDelay, orderedProxyCandidateIds, ProxySwitchCandidate
} from '../main/ets/util/proxyAutoSwitch';

function candidates(ids: number[]): ProxySwitchCandidate[] {
  return ids.map((id: number): ProxySwitchCandidate => ({ id: id }));
}

export default function proxyAutoSwitchTest() {
  describe('ProxyAutoSwitch', (): void => {
    it('normalizes_delay_to_supported_values', 0, (): void => {
      expect(normalizeProxySwitchDelay(5)).assertEqual(5);
      expect(normalizeProxySwitchDelay(30)).assertEqual(30);
      expect(normalizeProxySwitchDelay(7)).assertEqual(10);
      expect(normalizeProxySwitchDelay(0)).assertEqual(10);
    });

    it('tries_saved_proxies_after_active_and_wraps_once', 0, (): void => {
      const ordered = orderedProxyCandidateIds(candidates([11, 22, 33, 44]), 33);
      expect(ordered.join(',')).assertEqual('44,11,22');
    });

    it('never_retries_the_active_proxy', 0, (): void => {
      expect(orderedProxyCandidateIds(candidates([7]), 7).length).assertEqual(0);
      expect(orderedProxyCandidateIds(candidates([7, 8]), 7).join(','))
        .assertEqual('8');
    });

    it('keeps_saved_order_when_active_proxy_is_stale', 0, (): void => {
      expect(orderedProxyCandidateIds(candidates([4, 5, 6]), 99).join(','))
        .assertEqual('4,5,6');
    });
  });
}
