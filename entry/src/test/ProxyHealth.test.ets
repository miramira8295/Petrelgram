import { describe, expect, it } from '@ohos/hypium';
import {
  HEALTH_FAILING, HEALTH_OK, HEALTH_UNKNOWN, PROXY_HEALTH_EWMA_ALPHA, ProxyHealthEntry,
  ProxyHealthTarget, proxyHealthKey, proxyHealthOf, proxyHealthRank, proxyHealthUsable,
  recordProxyHealth, sortProxyCandidates
} from '../main/ets/util/proxyHealth';
import { ProxySwitchCandidate } from '../main/ets/util/proxyAutoSwitch';

function target(id: number, server: string = 'p.example', port: number = 1080): ProxyHealthTarget {
  return { id: id, server: server, port: port };
}

function candidates(ids: number[]): ProxySwitchCandidate[] {
  return ids.map((id: number): ProxySwitchCandidate => ({ id: id }));
}

function ranked(table: ProxyHealthEntry[]): string {
  return table.map((entry: ProxyHealthEntry): string => `${entry.id}`).join(',');
}

export default function proxyHealthTest() {
  describe('ProxyHealth', (): void => {
    it('records_first_success_as_the_ewma_seed', 0, (): void => {
      const table = recordProxyHealth([], target(1), 120, 1000);
      const entry = proxyHealthOf(table, 1);
      expect(entry?.rttMs).assertEqual(120);
      expect(entry?.failCount).assertEqual(0);
      expect(proxyHealthRank(entry)).assertEqual(HEALTH_OK);
    });

    it('smooths_later_successes_by_alpha', 0, (): void => {
      let table = recordProxyHealth([], target(1), 100, 1000);
      table = recordProxyHealth(table, target(1), 200, 2000);
      const expected = PROXY_HEALTH_EWMA_ALPHA * 200 + (1 - PROXY_HEALTH_EWMA_ALPHA) * 100;
      expect(Math.round(proxyHealthOf(table, 1)!.rttMs)).assertEqual(Math.round(expected));
    });

    it('failure_keeps_the_ewma_and_clears_on_the_next_success', 0, (): void => {
      let table = recordProxyHealth([], target(1), 90, 1000);
      table = recordProxyHealth(table, target(1), null, 2000);
      // 一次超时不代表它一直慢：成功样本留着，只是先判死。
      expect(proxyHealthOf(table, 1)!.rttMs).assertEqual(90);
      expect(proxyHealthOf(table, 1)!.failCount).assertEqual(1);
      expect(proxyHealthRank(proxyHealthOf(table, 1))).assertEqual(HEALTH_FAILING);
      table = recordProxyHealth(table, target(1), 95, 3000);
      expect(proxyHealthOf(table, 1)!.failCount).assertEqual(0);
      expect(proxyHealthRank(proxyHealthOf(table, 1))).assertEqual(HEALTH_OK);
    });

    it('treats_a_never_measured_proxy_as_unknown_not_failing', 0, (): void => {
      expect(proxyHealthRank(undefined)).assertEqual(HEALTH_UNKNOWN);
      const entry = proxyHealthOf(recordProxyHealth([], target(1), null, 1000), 1);
      // 从没成功过、又刚失败一次：算 failed，不是"没测过"。
      expect(proxyHealthRank(entry)).assertEqual(HEALTH_FAILING);
    });

    it('keeps_the_previous_entry_untouched', 0, (): void => {
      const before = recordProxyHealth([], target(1), 100, 1000);
      const after = recordProxyHealth(before, target(1), null, 2000);
      expect(before[0].failCount).assertEqual(0);
      expect(after[0].failCount).assertEqual(1);
      expect(after === before).assertFalse();
    });

    it('keys_by_server_and_port_so_it_survives_an_account_switch', 0, (): void => {
      expect(proxyHealthKey('1.2.3.4', 443)).assertEqual('1.2.3.4:443');
      const table = recordProxyHealth([], target(7, 'h.example', 443), 88, 1000);
      expect(proxyHealthOf(table, 7)?.key).assertEqual('h.example:443');
    });

    it('orders_healthy_by_rtt_then_unknown_then_failing', 0, (): void => {
      // 1 好且快、2 好但慢、3 没测过、4 正在失败、5 没测过（排在 3 后面，保持原序）
      let table = recordProxyHealth([], target(1), 60, 1000);
      table = recordProxyHealth(table, target(2), 400, 1000);
      table = recordProxyHealth(table, target(4), null, 1000);
      const sorted = sortProxyCandidates(candidates([1, 2, 3, 4, 5]), table);
      expect(sorted.map((entry: ProxySwitchCandidate): number => entry.id).join(','))
        .assertEqual('1,2,3,5,4');
    });

    it('keeps_tdlib_order_when_nothing_has_been_measured', 0, (): void => {
      const sorted = sortProxyCandidates(candidates([9, 3, 7]), []);
      expect(sorted.map((entry: ProxySwitchCandidate): number => entry.id).join(','))
        .assertEqual('9,3,7');
    });

    it('never_marks_an_unmeasured_proxy_unusable', 0, (): void => {
      expect(proxyHealthUsable([], 5)).assertTrue();
      expect(proxyHealthUsable(recordProxyHealth([], target(5), 100, 1000), 5)).assertTrue();
      expect(proxyHealthUsable(recordProxyHealth([], target(5), null, 1000), 5)).assertFalse();
    });

    it('always_keeps_direct_usable', 0, (): void => {
      // 直链没有 tcping 目标，判死它等于把自己锁死在代理上。
      expect(proxyHealthUsable([], 0)).assertTrue();
      const entry: ProxyHealthEntry = {
        id: 0, key: '', rttMs: -1, okAt: 0, failAt: 1000, failCount: 3
      };
      expect(proxyHealthUsable([entry], 0)).assertTrue();
    });

    it('appends_a_new_proxy_without_touching_the_existing_rows', 0, (): void => {
      const before = recordProxyHealth([], target(1), 100, 1000);
      const after = recordProxyHealth(before, target(2), 50, 2000);
      expect(before.length).assertEqual(1);
      expect(after.length).assertEqual(2);
      expect(ranked(after)).assertEqual('1,2');
    });
  });
}
