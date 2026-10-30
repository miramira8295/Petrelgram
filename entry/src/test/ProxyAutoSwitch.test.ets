import { ProxyCandidateRace } from '../main/ets/services/ProxyCandidateRace';
import { ProxyProbeCancellation } from '../main/ets/util/ProxyProbeCancellation';
import { afterEach, beforeEach, describe, expect, it } from '@ohos/hypium';
import {
  normalizeProxySwitchDelay, orderedProxyCandidateIds, ProxySwitchCandidate
} from '../main/ets/util/proxyAutoSwitch';
import { ProxyHealthSource } from '../main/ets/util/proxyHealth';

import { ProxyAutoSwitchEntry, ProxyAutoSwitchService } from '../main/ets/services/ProxyAutoSwitchService';
import { TdClient, TimerFns } from '../main/ets/tdkit/TdClient';
import { TdBridge, TdObject } from '../main/ets/tdkit/TdTypes';
import {
  KEY_CURRENT_NETWORK_TYPE, KEY_PROXY_AUTO_SWITCH, KEY_PROXY_SWITCH_DELAY_SEC
} from '../main/ets/store/AppSettings';

class ProxySwitchClock implements TimerFns {
  callbacks: Map<number, () => void> = new Map();
  scheduled: number = 0;
  lastDelay: number = 0;
  lastCallback: () => void = (): void => {};

  setTimeout(callback: () => void, ms: number): number {
    this.lastDelay = ms;
    this.lastCallback = callback;
    this.callbacks.set(++this.scheduled, callback);
    return this.scheduled;
  }

  clearTimeout(id: number): void { this.callbacks.delete(id); }

  fire(): void {
    const ids = Array.from(this.callbacks.keys());
    if (ids.length === 0) { throw new Error('No proxy switch timer scheduled'); }
    const callback = this.callbacks.get(ids[0])!;
    this.callbacks.delete(ids[0]);
    callback();
  }
}

class ProxySwitchBridge implements TdBridge {
  pending: TdObject[] = [];
  sent: TdObject[] = [];
  receive: (json: string) => void = (): void => {};

  init(callback: (json: string) => void): void { this.receive = callback; }
  send(json: string): void {
    const request = JSON.parse(json) as TdObject;
    this.pending.push(request);
    this.sent.push(request);
  }

  reply(type: string, response: TdObject): void {
    this.replyAt(0, type, response);
  }

  replyAt(index: number, type: string, response: TdObject): void {
    const request = this.pending.splice(index, 1)[0];
    if (request === undefined || request['@type'] !== type) {
      throw new Error(`Expected pending ${type}, got ${request?.['@type']}`);
    }
    response['@extra'] = request['@extra'];
    this.receive(JSON.stringify(response));
  }

  count(type: string): number {
    return this.sent.filter((request: TdObject): boolean => request['@type'] === type).length;
  }
}

class ProxySwitchNetwork {
  listeners: Set<(network: string) => void> = new Set<(network: string) => void>();

  subscribe(listener: (network: string) => void): () => void {
    this.listeners.add(listener);
    return (): void => { this.listeners.delete(listener); };
  }

  change(network: string): void {
    // NetworkStateService publishes AppStorage before notifying listeners.
    AppStorage.setOrCreate(KEY_CURRENT_NETWORK_TYPE, network);
    this.listeners.forEach((listener: (network: string) => void): void => listener(network));
  }
}

// Drain Promise continuations only; failover time is controlled by ProxySwitchClock.
async function settleProxySwitch(): Promise<void> {
  for (let i = 0; i < 30; i++) { await Promise.resolve(); }
}

// 单测里没有真实网卡，也不该真去 tcping：喂一张空表就等价于"全都还没测过"，
// 顺序保持 TDLib 原样、usable 恒为 true —— 和换 tcping 之前的用例期望一致。
class ProxySwitchHealth implements ProxyHealthSource {
  started: number = 0;
  stopped: number = 0;
  // 被判为"tcping 不通"的代理 id。空集合 = 巡检还没测出任何问题。
  failing: Set<number> = new Set<number>();
  start(): void { this.started++; }
  stop(): void { this.stopped++; }
  // 直链恒可用：它没有 tcping 目标，判死它等于把自己锁死在代理上。
  usable(id: number): boolean { return id === 0 || !this.failing.has(id); }
  sortedForSwitch(entries: ProxySwitchCandidate[]): ProxySwitchCandidate[] { return entries; }
}

class ProxySwitchFixture {
  ids: number[] = [1, 2];
  clock: ProxySwitchClock = new ProxySwitchClock();
  bridge: ProxySwitchBridge = new ProxySwitchBridge();
  client: TdClient = new TdClient(this.bridge);
  network: ProxySwitchNetwork = new ProxySwitchNetwork();
  health: ProxySwitchHealth = new ProxySwitchHealth();
  service: ProxyAutoSwitchService;

  constructor(realProbe: boolean = false) {
    this.service = new ProxyAutoSwitchService(this.clock,
      (listener: (network: string) => void): () => void => this.network.subscribe(listener),
      realProbe ? undefined : async (_id: number): Promise<boolean> => true,
      // 生产环境这个功能是关的（PROXY_AUTO_SWITCH_AVAILABLE = false），单测要
      // 继续覆盖状态机就得显式打开它。
      (): boolean => true,
      this.health);
    this.client.start();
    this.service.attach(this.client);
    this.publishList();
  }

  publishList(): void {
    this.service.proxyListChanged(this.ids.map((id: number): ProxyAutoSwitchEntry => ({ id: id, isEnabled: id === 1 })));
  }

  state(state: string): void {
    const connection: TdObject = { '@type': state };
    const update: TdObject = { '@type': 'updateConnectionState' };
    update['state'] = connection;
    this.client.deliverParsed(update);
  }

  listResponse(enabledId: number): TdObject {
    const response: TdObject = { '@type': 'proxies' };
    response['proxies'] = this.ids.map((id: number): TdObject => {
      const entry: TdObject = { '@type': 'addedProxy' };
      entry['id'] = id;
      entry['is_enabled'] = id === enabledId;
      return entry;
    });
    return response;
  }

  async listReply(enabled: boolean = true): Promise<void> {
    this.bridge.reply('getProxies', this.listResponse(enabled ? 1 : 0));
    await settleProxySwitch();
  }

  async replySelection(id: number): Promise<void> {
    this.bridge.reply('getProxies', this.listResponse(id));
    await settleProxySwitch();
  }

  async nextEnable(activeId: number): Promise<void> {
    this.clock.fire();
    await this.replySelection(activeId);
    await this.replySelection(activeId);
  }

  async enableReply(): Promise<void> {
    this.bridge.reply('enableProxy', { '@type': 'ok' } as TdObject);
    await settleProxySwitch();
  }

  async reject(type: string, message: string): Promise<void> {
    const error: TdObject = { '@type': 'error' };
    error['code'] = 500;
    error['message'] = message;
    this.bridge.reply(type, error);
    await settleProxySwitch();
  }

  async startEnable(): Promise<void> {
    await this.startListCheck();
    await this.listReply();
  }

  async ready(): Promise<void> {
    this.state('connectionStateReady');
    await this.listReply();
  }

  async startListCheck(): Promise<void> {
    this.state('connectionStateConnectingToProxy');
    this.clock.fire();
    await this.listReply();
  }

  close(): void {
    this.service.detach();
    this.client.dispose();
  }
}

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
      expect(ordered.join(',')).assertEqual('44,0,11,22');
    });

    it('never_retries_the_active_proxy', 0, (): void => {
      expect(orderedProxyCandidateIds(candidates([7]), 7).join(',')).assertEqual('0');
      expect(orderedProxyCandidateIds(candidates([7, 8]), 7).join(','))
        .assertEqual('8,0');
    });

    it('continues_after_failed_candidate_without_retrying_active', 0, (): void => {
      expect(orderedProxyCandidateIds(candidates([1, 2, 3]), 1, 2).join(',')).assertEqual('3,0,2');
    });

    it('removed_cursor_falls_back_to_current_saved_order', 0, (): void => {
      expect(orderedProxyCandidateIds(candidates([1, 3, 4]), 1, 2).join(',')).assertEqual('3,4,0');
    });

    it('single_alternative_can_be_retried_on_a_later_round', 0, (): void => {
      expect(orderedProxyCandidateIds(candidates([1, 2]), 1, 2).join(',')).assertEqual('0,2');
    });

    it('keeps_saved_order_when_active_proxy_is_stale', 0, (): void => {
      expect(orderedProxyCandidateIds(candidates([4, 5, 6]), 99).join(','))
        .assertEqual('4,5,6,0');
    });
  });

  describe('ProxyCandidateRace', (): void => {
    it('bounds concurrency and includes direct in the first wave', 0, async (): Promise<void> => {
      const clock = new ProxySwitchClock(); const race = new ProxyCandidateRace(clock); const started: number[] = [];
      const resolve = new Map<number, (usable: boolean) => void>();
      const pending = race.run([2, 3, 4, 5, 0], (id: number): Promise<boolean> => {
        started.push(id); return new Promise<boolean>((finish): void => { resolve.set(id, finish); });
      });
      await settleProxySwitch(); expect(started.join(',')).assertEqual('2,3,0');
      resolve.get(0)!(true); expect(await pending).assertEqual(0);
      resolve.get(2)!(true); resolve.get(3)!(false); await settleProxySwitch();
      expect(started.length).assertEqual(3); expect(clock.callbacks.size).assertEqual(0);
    });
    it('failed probes release slots and the first successful candidate wins', 0, async (): Promise<void> => {
      const race = new ProxyCandidateRace(new ProxySwitchClock()); const started: number[] = [];
      const result = await race.run([2, 3, 4, 5], async (id: number): Promise<boolean> => {
        started.push(id); return id === 5;
      });
      expect(result).assertEqual(5); expect(started.length).assertEqual(4);
    });
    it('cancellation ignores late success and stops queued probes', 0, async (): Promise<void> => {
      const clock = new ProxySwitchClock(); const race = new ProxyCandidateRace(clock); let started = 0;
      let finish: (value: boolean) => void = (_value: boolean): void => {};
      const pending = race.run([1, 2, 3, 4], (_id: number): Promise<boolean> => {
        started++; return new Promise<boolean>((resolve): void => { finish = resolve; });
      });
      await settleProxySwitch(); race.cancel(); finish(true); await settleProxySwitch();
      expect(await pending === undefined).assertTrue(); expect(started).assertEqual(3);
      expect(clock.callbacks.size).assertEqual(0);
    });
    it('hung probes time out and allow a queued usable route to run', 0, async (): Promise<void> => {
      const clock = new ProxySwitchClock(); const race = new ProxyCandidateRace(clock);
      const pending = race.run([1, 2, 3, 4], (id: number): Promise<boolean> =>
        id === 4 ? Promise.resolve(true) : new Promise<boolean>(() => {}));
      await settleProxySwitch(); clock.fire(); await settleProxySwitch();
      expect(await pending).assertEqual(4); expect(clock.callbacks.size).assertEqual(0);
    });
    it('all failures preserve the active route instead of picking an unusable node', 0, async (): Promise<void> => {
      const race = new ProxyCandidateRace(new ProxySwitchClock());
      expect(await race.run([1, 0], async (_id: number): Promise<boolean> => false) === undefined).assertTrue();
    });
    it('synchronous probe exceptions do not block the next candidate', 0, async (): Promise<void> => {
      const race = new ProxyCandidateRace(new ProxySwitchClock());
      expect(await race.run([1, 0], (id: number): Promise<boolean> => {
        if (id === 1) { throw new Error('probe failed'); } return Promise.resolve(true);
      })).assertEqual(0);
    });
    it('cancelling before launch creates no native probes', 0, async (): Promise<void> => {
      const race = new ProxyCandidateRace(new ProxySwitchClock()); let calls = 0;
      const pending = race.run([1, 0], async (_id: number): Promise<boolean> => { calls++; return true; });
      race.cancel(); expect(await pending === undefined).assertTrue(); await settleProxySwitch();
      expect(calls).assertEqual(0);
    });
    it('winner cancels every probe resource including pending siblings', 0, async (): Promise<void> => {
      const race = new ProxyCandidateRace(new ProxySwitchClock());
      const cancelled: number[] = []; let win: () => void = (): void => {};
      const result = race.run([1, 2, 3, 4], (id: number, cancellation?: ProxyProbeCancellation): Promise<boolean> => {
        cancellation!.subscribe((): void => { cancelled.push(id); });
        return new Promise<boolean>((resolve): void => { if (id === 2) { win = (): void => resolve(true); } });
      });
      await settleProxySwitch(); win();
      expect(await result).assertEqual(2); expect(cancelled.sort().join(',')).assertEqual('1,2,3');
    });
    it('timeout cancels a hung probe before reusing its concurrency slot', 0, async (): Promise<void> => {
      const clock = new ProxySwitchClock(); const race = new ProxyCandidateRace(clock);
      const cancelled: number[] = []; let checked = false;
      const result = race.run([1, 2, 3, 4], (id: number, cancellation?: ProxyProbeCancellation): Promise<boolean> => {
        if (id === 4) { checked = cancelled.length >= 1; return Promise.resolve(true); }
        cancellation!.subscribe((): void => { cancelled.push(id); });
        return new Promise<boolean>(() => {});
      });
      await settleProxySwitch(); clock.fire(); await settleProxySwitch();
      expect(await result).assertEqual(4); expect(checked).assertTrue(); expect(cancelled.length).assertEqual(3);
    });
    it('manual cancellation releases active probe resources once', 0, async (): Promise<void> => {
      const race = new ProxyCandidateRace(new ProxySwitchClock()); let closed = 0;
      const result = race.run([1, 2, 3, 4], (_id: number, cancellation?: ProxyProbeCancellation): Promise<boolean> => {
        cancellation!.subscribe((): void => { closed++; }); return new Promise<boolean>(() => {});
      });
      await settleProxySwitch(); race.cancel(); race.cancel();
      expect(await result === undefined).assertTrue(); expect(closed).assertEqual(3);
    });
    it('one failing cancellation callback cannot leave sibling resources live', 0, () => {
      const cancellation = new ProxyProbeCancellation(); let closed = 0;
      cancellation.subscribe((): void => { throw new Error('cleanup failed'); });
      cancellation.subscribe((): void => { closed++; }); cancellation.cancel(); cancellation.cancel();
      cancellation.subscribe((): void => { closed++; }); expect(closed).assertEqual(2);
    });
  });

  describe('ProxyAutoSwitchService timing', (): void => {
    let fixture: ProxySwitchFixture;
    let previousAuto: boolean | undefined;
    let previousDelay: number | undefined;
    let previousNetwork: string | undefined;

    beforeEach((): void => {
      previousAuto = AppStorage.get<boolean>(KEY_PROXY_AUTO_SWITCH);
      previousDelay = AppStorage.get<number>(KEY_PROXY_SWITCH_DELAY_SEC);
      previousNetwork = AppStorage.get<string>(KEY_CURRENT_NETWORK_TYPE);
      AppStorage.setOrCreate(KEY_PROXY_AUTO_SWITCH, true);
      AppStorage.setOrCreate(KEY_PROXY_SWITCH_DELAY_SEC, 10);
      AppStorage.setOrCreate(KEY_CURRENT_NETWORK_TYPE, 'wifi');
      fixture = new ProxySwitchFixture();
    });

    afterEach((): void => {
      fixture.close();
      if (previousAuto === undefined) { AppStorage.delete(KEY_PROXY_AUTO_SWITCH); }
      else { AppStorage.setOrCreate(KEY_PROXY_AUTO_SWITCH, previousAuto); }
      if (previousDelay === undefined) { AppStorage.delete(KEY_PROXY_SWITCH_DELAY_SEC); }
      else { AppStorage.setOrCreate(KEY_PROXY_SWITCH_DELAY_SEC, previousDelay); }
      if (previousNetwork === undefined) { AppStorage.delete(KEY_CURRENT_NETWORK_TYPE); }
      else { AppStorage.setOrCreate(KEY_CURRENT_NETWORK_TYPE, previousNetwork); }
    });

    // 下面这几条原来测的是 pingProxy 的并发探测/取消。判据换成 tcping 表之后，
    // 探测不再发任何 TDLib 请求，但"谁能被选中、迟到的回复要作废"这些约束仍然成立，
    // 所以用例保留、判据换成 health 表。
    it('skips_a_proxy_tcping_says_is_dead_and_selects_direct', 0, async (): Promise<void> => {
      fixture.close(); fixture = new ProxySwitchFixture(true);
      fixture.health.failing = new Set<number>([2]);
      fixture.state('connectionStateConnecting');
      // 生产路径不该再出现 pingProxy（issue #31 的假阴性就是它，且卡住时发不出去）。
      expect(fixture.bridge.count('pingProxy')).assertEqual(0);
      fixture.clock.fire(); await fixture.listReply();
      // 候选 [2, 0]：2 判死，落到直链。
      await fixture.listReply();
      expect(fixture.bridge.count('disableProxy')).assertEqual(1);
      expect(fixture.bridge.count('enableProxy')).assertEqual(0);
      expect(fixture.bridge.count('pingProxy')).assertEqual(0);
    });
    it('ready_before_the_list_reply_prevents_every_later_selection', 0, async (): Promise<void> => {
      fixture.close(); fixture = new ProxySwitchFixture(true); fixture.state('connectionStateConnecting');
      fixture.clock.fire();
      fixture.state('connectionStateReady');
      await fixture.listReply();
      await settleProxySwitch();
      expect(fixture.bridge.count('enableProxy')).assertEqual(0); expect(fixture.bridge.count('disableProxy')).assertEqual(0);
      expect(fixture.clock.callbacks.size).assertEqual(0);
    });
    it('automatic switching disabled means no candidate probes even during default failure', 0, async (): Promise<void> => {
      fixture.close(); fixture = new ProxySwitchFixture(true);
      AppStorage.setOrCreate(KEY_PROXY_AUTO_SWITCH, false); fixture.service.settingsChanged();
      fixture.state('connectionStateConnecting'); await settleProxySwitch();
      expect(fixture.clock.callbacks.size).assertEqual(0); expect(fixture.bridge.count('pingProxy')).assertEqual(0);
    });
    it('manual_selection_during_the_list_request_ignores_its_late_reply', 0, async (): Promise<void> => {
      fixture.close(); fixture = new ProxySwitchFixture(true); fixture.state('connectionStateConnecting');
      fixture.clock.fire(); fixture.service.proxySelectionChanged(2);
      await fixture.listReply();
      await settleProxySwitch();
      expect(fixture.bridge.count('enableProxy')).assertEqual(0); expect(fixture.bridge.count('disableProxy')).assertEqual(0);
    });
    it('skips_a_dead_proxy_and_switches_to_the_next_one', 0, async (): Promise<void> => {
      fixture.close(); fixture = new ProxySwitchFixture(true);
      fixture.ids = [1, 2, 3]; fixture.publishList();
      fixture.health.failing = new Set<number>([2]);
      fixture.state('connectionStateConnecting');
      fixture.clock.fire(); await fixture.listReply();
      await fixture.listReply();
      // 候选顺序 [2, 3, 0]，2 判死 → 3。
      expect(fixture.bridge.pending[0]['@type']).assertEqual('enableProxy');
      expect(fixture.bridge.pending[0]['proxy_id']).assertEqual(3);
    });
    it('changing_networks_cancels_an_attempt_from_the_previous_network', 0, async (): Promise<void> => {
      fixture.close(); fixture = new ProxySwitchFixture(true); fixture.state('connectionStateConnecting');
      fixture.clock.fire(); fixture.network.change('cellular');
      await fixture.listReply();
      await settleProxySwitch();
      expect(fixture.bridge.count('enableProxy')).assertEqual(0); expect(fixture.bridge.count('disableProxy')).assertEqual(0);
      expect(fixture.clock.callbacks.size).assertEqual(1);
    });
    it('single_proxy_direct_failure_returns_to_proxy_after_full_delay', 0, async (): Promise<void> => {
      fixture.ids = [1];
      fixture.publishList();
      fixture.state('connectionStateConnecting');
      await fixture.nextEnable(1);
      expect(fixture.bridge.pending[0]['@type']).assertEqual('disableProxy');
      fixture.bridge.reply('disableProxy', { '@type': 'ok' } as TdObject);
      await settleProxySwitch();
      expect(fixture.clock.lastDelay).assertEqual(10000);
      await fixture.nextEnable(0);
      expect(fixture.bridge.pending[0]['proxy_id']).assertEqual(1);
    });

    it('direct_ready_before_ack_publishes_direct_and_stops_rotation', 0, async (): Promise<void> => {
      fixture.ids = [1];
      fixture.publishList();
      let selected: number = -1;
      fixture.service.subscribeSelection(fixture.client, (id: number): void => { selected = id; });
      fixture.state('connectionStateConnecting');
      await fixture.nextEnable(1);
      fixture.state('connectionStateReady');
      fixture.bridge.reply('disableProxy', { '@type': 'ok' } as TdObject);
      await settleProxySwitch();
      await fixture.replySelection(0);
      expect(selected).assertEqual(0);
      expect(fixture.clock.callbacks.size).assertEqual(0);
    });

    it('disable_timeout_actual_direct_gets_full_window', 0, async (): Promise<void> => {
      fixture.ids = [1];
      fixture.publishList();
      fixture.state('connectionStateConnecting');
      await fixture.nextEnable(1);
      await fixture.reject('disableProxy', 'request timeout');
      expect(fixture.clock.callbacks.size).assertEqual(0);
      await fixture.replySelection(0);
      expect(fixture.clock.lastDelay).assertEqual(10000);
      expect(fixture.bridge.count('enableProxy')).assertEqual(0);
      await fixture.nextEnable(0);
      expect(fixture.bridge.pending[0]['proxy_id']).assertEqual(1);
    });

    it('manual_selection_during_disable_ignores_late_ack', 0, async (): Promise<void> => {
      fixture.ids = [1];
      fixture.publishList();
      fixture.state('connectionStateConnecting');
      await fixture.nextEnable(1);
      fixture.service.proxySelectionChanged(1);
      fixture.bridge.reply('disableProxy', { '@type': 'ok' } as TdObject);
      await settleProxySwitch();
      expect(fixture.clock.callbacks.size).assertEqual(1);
      await fixture.nextEnable(1);
      expect(fixture.bridge.count('disableProxy')).assertEqual(2);
    });

    it('auto_switch_off_prevents_direct_fallback', 0, async (): Promise<void> => {
      fixture.ids = [1];
      fixture.publishList();
      await fixture.startListCheck();
      AppStorage.setOrCreate(KEY_PROXY_AUTO_SWITCH, false);
      fixture.service.settingsChanged();
      await fixture.replySelection(1);
      expect(fixture.bridge.count('disableProxy')).assertEqual(0);
      expect(fixture.clock.callbacks.size).assertEqual(0);
    });

    it('network_loss_prevents_direct_fallback', 0, async (): Promise<void> => {
      fixture.ids = [1];
      fixture.publishList();
      await fixture.startListCheck();
      fixture.network.change('none');
      await fixture.replySelection(1);
      expect(fixture.bridge.count('disableProxy')).assertEqual(0);
      expect(fixture.clock.callbacks.size).assertEqual(0);
    });

    it('direct_with_no_saved_proxy_does_not_schedule', 0, (): void => {
      fixture.ids = [];
      fixture.publishList();
      fixture.state('connectionStateConnecting');
      expect(fixture.clock.callbacks.size).assertEqual(0);
    });

    it('direct_with_saved_proxy_recovers_after_network_returns', 0, async (): Promise<void> => {
      fixture.service.proxyListChanged([{ id: 1, isEnabled: false }]);
      fixture.state('connectionStateConnecting');
      fixture.network.change('none');
      expect(fixture.clock.callbacks.size).assertEqual(0);
      fixture.network.change('wifi');
      expect(fixture.clock.lastDelay).assertEqual(10000);
      await fixture.nextEnable(0);
      expect(fixture.bridge.pending[0]['proxy_id']).assertEqual(1);
    });

    it('selects_one_verified_candidate_per_window_with_injected_successful_probes', 0, async (): Promise<void> => {
      fixture.ids = [1, 2, 3];
      fixture.publishList();
      fixture.state('connectionStateConnectingToProxy');
      // 只走一圈：第二个循环会被"绕完就停手"的闸挡下，见下面那条用例。
      const activeIds: number[] = [1, 2, 3];
      const targetIds: number[] = [2, 3, 0];
      for (let i = 0; i < activeIds.length; i++) {
        await fixture.nextEnable(activeIds[i]);
        expect((fixture.bridge.pending[0]['proxy_id'] as number | undefined) ?? 0).assertEqual(targetIds[i]);
        expect(fixture.clock.callbacks.size).assertEqual(0);
        fixture.state('connectionStateConnecting');
        expect(fixture.clock.callbacks.size).assertEqual(0);
        fixture.bridge.reply(targetIds[i] === 0 ? 'disableProxy' : 'enableProxy', { '@type': 'ok' } as TdObject);
        await settleProxySwitch();
        expect(fixture.bridge.count('enableProxy') + fixture.bridge.count('disableProxy')).assertEqual(i + 1);
        expect(fixture.clock.callbacks.size).assertEqual(1);
        expect(fixture.clock.lastDelay).assertEqual(10000);
      }
      expect(fixture.bridge.count('pingProxy')).assertEqual(0);
    });

    it('rejected_enables_advance_instead_of_starving_later_candidates', 0, async (): Promise<void> => {
      fixture.ids = [1, 2, 3];
      fixture.publishList();
      fixture.state('connectionStateConnecting');
      const targets: number[] = [2, 3, 0];
      for (let i = 0; i < targets.length; i++) {
        await fixture.nextEnable(1);
        expect((fixture.bridge.pending[0]['proxy_id'] as number | undefined) ?? 0).assertEqual(targets[i]);
        await fixture.reject(targets[i] === 0 ? 'disableProxy' : 'enableProxy', 'proxy rejected');
        expect(fixture.clock.callbacks.size).assertEqual(0);
        await fixture.replySelection(1);
        expect(fixture.bridge.count('enableProxy') + fixture.bridge.count('disableProxy')).assertEqual(i + 1);
        expect(fixture.clock.callbacks.size).assertEqual(1);
        expect(fixture.clock.lastDelay).assertEqual(10000);
      }
    });

    it('stops_rotating_after_one_full_cycle_until_the_route_recovers', 0, async (): Promise<void> => {
      fixture.ids = [1, 2, 3];
      fixture.publishList();
      fixture.state('connectionStateConnecting');
      // 3 个代理 + 直链，绕完一圈还连不上就不再重拨：每 10 秒 enableProxy 一次
      // 就是用户抱怨的"一直连接中"。
      const targets: number[] = [2, 3, 0, 2];
      for (let i = 0; i < targets.length; i++) {
        await fixture.nextEnable(1);
        await fixture.reject(targets[i] === 0 ? 'disableProxy' : 'enableProxy', 'proxy rejected');
        await fixture.replySelection(1);
      }
      expect(fixture.clock.callbacks.size).assertEqual(0);
      // 连上之后重新开始计数——下一次断线仍然要能自动切。
      await fixture.ready();
      fixture.state('connectionStateConnecting');
      expect(fixture.clock.callbacks.size).assertEqual(1);
    });

    it('read_only_page_refresh_preserves_progress_after_rejection', 0, async (): Promise<void> => {
      fixture.ids = [1, 2, 3];
      fixture.publishList();
      await fixture.startEnable();
      await fixture.reject('enableProxy', 'proxy rejected');
      await fixture.replySelection(1);
      fixture.service.proxyListLoaded(fixture.client, fixture.service.getSelectionRevision(),
        [{ id: 1, isEnabled: true }, { id: 2, isEnabled: false }, { id: 3, isEnabled: false }]);
      await fixture.nextEnable(1);
      expect(fixture.bridge.pending[0]['proxy_id']).assertEqual(3);
    });

    it('candidate_removed_between_reads_is_not_enabled', 0, async (): Promise<void> => {
      fixture.ids = [1, 2, 3];
      fixture.publishList();
      await fixture.startListCheck();
      fixture.ids = [1, 3];
      await fixture.replySelection(1);
      expect(fixture.bridge.count('enableProxy')).assertEqual(0);
      expect(fixture.clock.callbacks.size).assertEqual(1);
      await fixture.nextEnable(1);
      expect(fixture.bridge.pending[0]['proxy_id']).assertEqual(3);
    });

    it('removing_other_proxies_still_tries_direct', 0, async (): Promise<void> => {
      await fixture.startListCheck();
      fixture.ids = [1];
      await fixture.replySelection(1);
      expect(fixture.bridge.count('disableProxy')).assertEqual(0);
      await fixture.nextEnable(1);
      expect(fixture.bridge.count('disableProxy')).assertEqual(1);
      expect(fixture.bridge.count('enableProxy')).assertEqual(0);
      expect(fixture.clock.callbacks.size).assertEqual(0);
    });

    it('removed_failed_candidate_does_not_block_remaining_nodes', 0, async (): Promise<void> => {
      fixture.ids = [1, 2, 3];
      fixture.publishList();
      await fixture.startEnable();
      await fixture.reject('enableProxy', 'proxy rejected');
      await fixture.replySelection(1);
      fixture.ids = [1, 3];
      await fixture.nextEnable(1);
      expect(fixture.bridge.pending[0]['proxy_id']).assertEqual(3);
    });

    it('timeout_that_enabled_target_gets_full_connection_window', 0, async (): Promise<void> => {
      fixture.ids = [1, 2, 3];
      fixture.publishList();
      await fixture.startEnable();
      await fixture.reject('enableProxy', 'request timeout');
      expect(fixture.clock.callbacks.size).assertEqual(0);
      await fixture.replySelection(2);
      expect(fixture.bridge.count('enableProxy')).assertEqual(1);
      expect(fixture.clock.callbacks.size).assertEqual(1);
      expect(fixture.clock.lastDelay).assertEqual(10000);
      await fixture.nextEnable(2);
      expect(fixture.bridge.pending[0]['proxy_id']).assertEqual(3);
    });

    it('timeout_that_did_not_enable_advances_to_next_candidate', 0, async (): Promise<void> => {
      fixture.ids = [1, 2, 3];
      fixture.publishList();
      await fixture.startEnable();
      await fixture.reject('enableProxy', 'request timeout');
      await fixture.replySelection(1);
      await fixture.nextEnable(1);
      expect(fixture.bridge.pending[0]['proxy_id']).assertEqual(3);
    });

    it('failed_reconciliation_requires_new_read_before_another_enable', 0, async (): Promise<void> => {
      fixture.ids = [1, 2, 3];
      fixture.publishList();
      await fixture.startEnable();
      await fixture.reject('enableProxy', 'request timeout');
      await fixture.reject('getProxies', 'request timeout');
      expect(fixture.clock.callbacks.size).assertEqual(1);
      fixture.clock.fire();
      await fixture.replySelection(2); // Finally learns that the timed-out enable succeeded.
      expect(fixture.bridge.count('enableProxy')).assertEqual(1);
      expect(fixture.bridge.pending.length).assertEqual(0);
      expect(fixture.clock.callbacks.size).assertEqual(1);
      expect(fixture.clock.lastDelay).assertEqual(10000);
      await fixture.nextEnable(2);
      expect(fixture.bridge.pending[0]['proxy_id']).assertEqual(3);
    });

    it('manual_selection_resets_failed_candidate_progress', 0, async (): Promise<void> => {
      fixture.ids = [1, 2, 3];
      fixture.publishList();
      await fixture.startEnable();
      await fixture.reject('enableProxy', 'proxy rejected');
      await fixture.replySelection(1);
      fixture.service.proxySelectionChanged(1);
      await fixture.nextEnable(1);
      expect(fixture.bridge.pending[0]['proxy_id']).assertEqual(2);
    });

    it('ready_resets_failed_candidate_progress_for_next_outage', 0, async (): Promise<void> => {
      fixture.ids = [1, 2, 3];
      fixture.publishList();
      await fixture.startEnable();
      await fixture.reject('enableProxy', 'proxy rejected');
      await fixture.replySelection(1);
      await fixture.ready();
      expect(fixture.clock.callbacks.size).assertEqual(0);
      fixture.state('connectionStateConnecting');
      await fixture.nextEnable(1);
      expect(fixture.bridge.pending[0]['proxy_id']).assertEqual(2);
    });

    it('updating_resets_failed_candidate_progress_for_next_outage', 0, async (): Promise<void> => {
      fixture.ids = [1, 2, 3];
      fixture.publishList();
      await fixture.startEnable();
      await fixture.reject('enableProxy', 'proxy rejected');
      await fixture.replySelection(1);
      fixture.state('connectionStateUpdating');
      expect(fixture.clock.callbacks.size).assertEqual(0);
      fixture.state('connectionStateConnecting');
      await fixture.nextEnable(1);
      expect(fixture.bridge.pending[0]['proxy_id']).assertEqual(2);
    });

    it('runtime_reattach_resets_failed_candidate_progress', 0, async (): Promise<void> => {
      fixture.ids = [1, 2, 3];
      fixture.publishList();
      await fixture.startEnable();
      await fixture.reject('enableProxy', 'proxy rejected');
      await fixture.replySelection(1);
      fixture.service.attach(fixture.client);
      fixture.state('connectionStateConnecting');
      await fixture.nextEnable(1);
      expect(fixture.bridge.pending[0]['proxy_id']).assertEqual(2);
    });

    it('manual_direct_during_reconciliation_cancels_old_rotation_and_waits', 0, async (): Promise<void> => {
      await fixture.startEnable();
      await fixture.reject('enableProxy', 'request timeout');
      fixture.service.proxySelectionChanged(0);
      await fixture.replySelection(2);
      expect(fixture.clock.callbacks.size).assertEqual(1);
      expect(fixture.clock.lastDelay).assertEqual(10000);
      await fixture.nextEnable(0);
      expect(fixture.bridge.pending[0]['proxy_id']).assertEqual(1);
      expect(fixture.bridge.count('enableProxy')).assertEqual(2);
    });

    it('offline_during_final_read_does_not_enable_any_candidate', 0, async (): Promise<void> => {
      await fixture.startListCheck();
      fixture.network.change('none');
      await fixture.replySelection(1);
      expect(fixture.bridge.count('enableProxy')).assertEqual(0);
      expect(fixture.clock.callbacks.size).assertEqual(0);
    });

    it('automatic_enable_publishes_the_actual_selected_proxy', 0, async (): Promise<void> => {
      const selected: number[] = [];
      fixture.service.subscribeSelection(fixture.client, (id: number): void => { selected.push(id); });
      await fixture.startEnable();
      expect(selected.join(',')).assertEqual('1');
      fixture.bridge.reply('enableProxy', { '@type': 'ok' } as TdObject);
      await settleProxySwitch();
      expect(selected.join(',')).assertEqual('1,2');
      expect(fixture.clock.callbacks.size).assertEqual(1);
    });

    it('ready_before_enable_reply_still_publishes_and_rejects_old_refresh', 0, async (): Promise<void> => {
      await fixture.startEnable();
      const selected: number[] = [];
      fixture.service.subscribeSelection(fixture.client, (id: number): void => { selected.push(id); });
      fixture.state('connectionStateReady');
      fixture.bridge.reply('enableProxy', { '@type': 'ok' } as TdObject);
      await settleProxySwitch();
      expect(selected.join(',')).assertEqual('2');
      await fixture.listReply(); // A response taken before the enable acknowledgement.
      expect(selected.join(',')).assertEqual('2');
      expect(fixture.clock.callbacks.size).assertEqual(0);
    });

    it('confirmed_ready_list_can_publish_before_enable_acknowledgement', 0, async (): Promise<void> => {
      await fixture.startEnable();
      const selected: number[] = [];
      fixture.service.subscribeSelection(fixture.client, (id: number): void => { selected.push(id); });
      fixture.state('connectionStateReady');
      fixture.bridge.replyAt(1, 'getProxies', fixture.listResponse(2));
      await settleProxySwitch();
      expect(selected.join(',')).assertEqual('2');
      fixture.bridge.reply('enableProxy', { '@type': 'ok' } as TdObject);
      await settleProxySwitch();
      expect(selected.join(',')).assertEqual('2');
      expect(fixture.clock.callbacks.size).assertEqual(0);
    });

    it('updating_before_enable_reply_updates_selection_without_retrying', 0, async (): Promise<void> => {
      await fixture.startEnable();
      const selected: number[] = [];
      fixture.service.subscribeSelection(fixture.client, (id: number): void => { selected.push(id); });
      fixture.state('connectionStateUpdating');
      fixture.bridge.reply('enableProxy', { '@type': 'ok' } as TdObject);
      await settleProxySwitch();
      expect(selected.join(',')).assertEqual('2');
      expect(fixture.clock.callbacks.size).assertEqual(0);
    });

    it('manual_disable_owns_selection_over_a_late_automatic_ack', 0, async (): Promise<void> => {
      await fixture.startEnable();
      const selected: number[] = [];
      fixture.service.subscribeSelection(fixture.client, (id: number): void => { selected.push(id); });
      fixture.service.proxySelectionChanged(0);
      fixture.bridge.reply('enableProxy', { '@type': 'ok' } as TdObject);
      await settleProxySwitch();
      expect(selected.length).assertEqual(0);
      expect(fixture.service.proxyListLoaded(fixture.client, fixture.service.getSelectionRevision(),
        [{ id: 1, isEnabled: false }, { id: 2, isEnabled: false }])).assertTrue();
      expect(selected.join(',')).assertEqual('0');
      expect(fixture.clock.callbacks.size).assertEqual(1);
      expect(fixture.clock.lastDelay).assertEqual(10000);
      await fixture.nextEnable(0);
      expect(fixture.bridge.pending[0]['proxy_id']).assertEqual(1);
    });

    it('manual_reselection_is_not_overwritten_by_automatic_ack', 0, async (): Promise<void> => {
      await fixture.startEnable();
      const selected: number[] = [];
      fixture.service.subscribeSelection(fixture.client, (id: number): void => { selected.push(id); });
      fixture.service.proxySelectionChanged(1);
      fixture.bridge.reply('enableProxy', { '@type': 'ok' } as TdObject);
      await settleProxySwitch();
      expect(selected.length).assertEqual(0);
      expect(fixture.clock.callbacks.size).assertEqual(1);
    });

    it('page_read_started_before_auto_switch_cannot_restore_old_selection', 0, async (): Promise<void> => {
      const revision = fixture.service.getSelectionRevision();
      await fixture.startEnable();
      fixture.bridge.reply('enableProxy', { '@type': 'ok' } as TdObject);
      await settleProxySwitch();
      const scheduled = fixture.clock.scheduled;
      expect(fixture.service.proxyListLoaded(fixture.client, revision,
        [{ id: 1, isEnabled: true }, { id: 2, isEnabled: false }])).assertFalse();
      const selected: number[] = [];
      fixture.service.subscribeSelection(fixture.client, (id: number): void => { selected.push(id); });
      expect(selected.join(',')).assertEqual('2');
      expect(fixture.clock.scheduled).assertEqual(scheduled);
    });

    it('page_read_during_enable_does_not_steal_selection_ownership', 0, async (): Promise<void> => {
      await fixture.startEnable();
      expect(fixture.service.proxyListLoaded(fixture.client, fixture.service.getSelectionRevision(),
        [{ id: 1, isEnabled: true }, { id: 2, isEnabled: false }])).assertTrue();
      const revision = fixture.service.getSelectionRevision();
      fixture.bridge.reply('enableProxy', { '@type': 'ok' } as TdObject);
      await settleProxySwitch();
      expect(fixture.service.selectionIsCurrent(fixture.client, revision)).assertFalse();
      const selected: number[] = [];
      fixture.service.subscribeSelection(fixture.client, (id: number): void => { selected.push(id); });
      expect(selected.join(',')).assertEqual('2');
    });

    it('reading_unchanged_list_does_not_reset_failover_deadline', 0, async (): Promise<void> => {
      await fixture.ready();
      fixture.state('connectionStateConnecting');
      const scheduled = fixture.clock.scheduled;
      const revision = fixture.service.getSelectionRevision();
      expect(fixture.service.proxyListLoaded(fixture.client, revision,
        [{ id: 1, isEnabled: true }, { id: 2, isEnabled: false }])).assertTrue();
      expect(fixture.service.getSelectionRevision()).assertEqual(revision);
      expect(fixture.clock.scheduled).assertEqual(scheduled);
      expect(fixture.clock.callbacks.size).assertEqual(1);
    });

    it('unsubscribe_stops_notifications_and_new_subscriber_gets_latest', 0, async (): Promise<void> => {
      const selected: number[] = [];
      const unsubscribe = fixture.service.subscribeSelection(fixture.client,
        (id: number): void => { selected.push(id); });
      await fixture.startEnable();
      unsubscribe();
      fixture.bridge.reply('enableProxy', { '@type': 'ok' } as TdObject);
      await settleProxySwitch();
      expect(selected.join(',')).assertEqual('1');
      fixture.service.subscribeSelection(fixture.client, (id: number): void => { selected.push(id); });
      expect(selected.join(',')).assertEqual('1,2');
    });

    it('reattach_invalidates_old_reads_subscribers_and_enable_ack', 0, async (): Promise<void> => {
      await fixture.startEnable();
      const revision = fixture.service.getSelectionRevision();
      const selected: number[] = [];
      fixture.service.subscribeSelection(fixture.client, (id: number): void => { selected.push(id); });
      fixture.service.attach(fixture.client);
      fixture.bridge.reply('enableProxy', { '@type': 'ok' } as TdObject);
      await settleProxySwitch();
      expect(fixture.service.selectionIsCurrent(fixture.client, revision)).assertFalse();
      fixture.state('connectionStateReady');
      await fixture.listReply();
      expect(selected.length).assertEqual(0);
    });

    it('another_runtime_cannot_read_or_subscribe_to_current_selection', 0, async (): Promise<void> => {
      await fixture.ready();
      const other = new TdClient(new ProxySwitchBridge());
      try {
        const selected: number[] = [];
        fixture.service.subscribeSelection(other, (id: number): void => { selected.push(id); });
        expect(fixture.service.proxyListLoaded(other, fixture.service.getSelectionRevision(),
          [{ id: 1, isEnabled: false }])).assertFalse();
        expect(selected.length).assertEqual(0);
      } finally { other.dispose(); }
    });

    it('uncertain_enable_result_is_reconciled_even_after_updating', 0, async (): Promise<void> => {
      await fixture.startEnable();
      fixture.state('connectionStateUpdating');
      const selected: number[] = [];
      fixture.service.subscribeSelection(fixture.client, (id: number): void => { selected.push(id); });
      const error: TdObject = { '@type': 'error' };
      error['code'] = 500;
      error['message'] = 'Request timeout';
      fixture.bridge.reply('enableProxy', error);
      await settleProxySwitch();
      fixture.bridge.reply('getProxies', fixture.listResponse(2));
      await settleProxySwitch();
      expect(selected.join(',')).assertEqual('2');
      expect(fixture.clock.callbacks.size).assertEqual(0);
    });

    it('ready_refresh_publishes_selection_without_an_automatic_attempt', 0, async (): Promise<void> => {
      const selected: number[] = [];
      fixture.service.subscribeSelection(fixture.client, (id: number): void => { selected.push(id); });
      fixture.state('connectionStateReady');
      fixture.bridge.reply('getProxies', fixture.listResponse(2));
      await settleProxySwitch();
      expect(selected.join(',')).assertEqual('2');
      expect(fixture.bridge.count('enableProxy')).assertEqual(0);
    });

    it('ready_before_save_callback_and_list_refresh_does_not_switch', 0, async (): Promise<void> => {
      await fixture.ready();
      fixture.service.proxySelectionChanged(1);
      fixture.publishList();
      fixture.service.settingsChanged();
      expect(fixture.clock.callbacks.size).assertEqual(0);
      expect(fixture.bridge.count('pingProxy')).assertEqual(0);
      expect(fixture.bridge.count('enableProxy')).assertEqual(0);
    });

    it('updating_before_save_callback_does_not_arm', 0, (): void => {
      fixture.state('connectionStateUpdating');
      fixture.service.proxySelectionChanged(1);
      fixture.publishList();
      expect(fixture.clock.callbacks.size).assertEqual(0);
    });

    it('unknown_and_waiting_states_do_not_arm_on_selection', 0, (): void => {
      fixture.service.proxySelectionChanged(1);
      expect(fixture.clock.callbacks.size).assertEqual(0);
      fixture.state('connectionStateWaitingForNetwork');
      fixture.service.proxySelectionChanged(1);
      expect(fixture.clock.callbacks.size).assertEqual(0);
    });

    it('ready_after_save_callback_cancels_even_a_queued_timer', 0, async (): Promise<void> => {
      fixture.state('connectionStateConnectingToProxy');
      fixture.service.proxySelectionChanged(1);
      const queued = fixture.clock.lastCallback;
      await fixture.ready();
      queued();
      await settleProxySwitch();
      expect(fixture.clock.callbacks.size).assertEqual(0);
      expect(fixture.bridge.count('getProxies')).assertEqual(1);
      expect(fixture.bridge.count('enableProxy')).assertEqual(0);
    });

    it('manual_selection_waits_for_connecting_then_switches', 0, async (): Promise<void> => {
      await fixture.ready();
      fixture.service.proxySelectionChanged(1);
      expect(fixture.clock.callbacks.size).assertEqual(0);
      fixture.state('connectionStateConnecting');
      expect(fixture.clock.callbacks.size).assertEqual(1);
      expect(fixture.clock.lastDelay).assertEqual(10000);
      fixture.clock.fire();
      await fixture.listReply();
      await fixture.listReply();
      expect(fixture.bridge.count('enableProxy')).assertEqual(1);
      expect(fixture.bridge.pending[0]['proxy_id']).assertEqual(2);
    });

    it('connecting_after_proxy_handshake_keeps_original_deadline', 0, (): void => {
      fixture.state('connectionStateConnectingToProxy');
      const scheduled = fixture.clock.scheduled;
      fixture.state('connectionStateConnecting');
      fixture.state('connectionStateConnecting');
      expect(fixture.clock.scheduled).assertEqual(scheduled);
      expect(fixture.clock.callbacks.size).assertEqual(1);
    });

    it('recovery_during_initial_list_stops_probe', 0, async (): Promise<void> => {
      fixture.state('connectionStateConnectingToProxy');
      fixture.clock.fire();
      fixture.state('connectionStateUpdating');
      await fixture.listReply();
      expect(fixture.bridge.count('pingProxy')).assertEqual(0);
      expect(fixture.clock.callbacks.size).assertEqual(0);
    });

    it('ready_during_list_check_stops_enable', 0, async (): Promise<void> => {
      await fixture.startListCheck();
      fixture.state('connectionStateReady');
      await fixture.listReply(); // Old final check.
      await fixture.listReply(); // Ready refresh, not a switch authorization.
      expect(fixture.bridge.count('enableProxy')).assertEqual(0);
      expect(fixture.clock.callbacks.size).assertEqual(0);
    });

    it('recovery_during_final_list_stops_enable', 0, async (): Promise<void> => {
      await fixture.startListCheck();
      fixture.state('connectionStateUpdating');
      await fixture.listReply();
      expect(fixture.bridge.count('enableProxy')).assertEqual(0);
      expect(fixture.clock.callbacks.size).assertEqual(0);
    });

    it('unknown_state_during_final_list_is_rechecked_before_enable', 0, async (): Promise<void> => {
      await fixture.startListCheck();
      fixture.state('');
      await fixture.listReply();
      expect(fixture.bridge.count('enableProxy')).assertEqual(0);
      expect(fixture.clock.callbacks.size).assertEqual(0);
    });

    it('updating_before_automatic_enable_reply_does_not_restart_timer', 0, async (): Promise<void> => {
      await fixture.startListCheck();
      await fixture.listReply();
      fixture.state('connectionStateUpdating');
      fixture.bridge.reply('enableProxy', { '@type': 'ok' } as TdObject);
      await settleProxySwitch();
      expect(fixture.bridge.count('enableProxy')).assertEqual(1);
      expect(fixture.clock.callbacks.size).assertEqual(0);
    });

    it('manual_direct_selection_cancels_old_attempt_and_starts_full_delay', 0, async (): Promise<void> => {
      await fixture.startListCheck();
      fixture.service.proxySelectionChanged(0);
      await fixture.listReply();
      expect(fixture.bridge.count('enableProxy')).assertEqual(0);
      expect(fixture.clock.callbacks.size).assertEqual(1);
      expect(fixture.clock.lastDelay).assertEqual(10000);
    });

    it('ready_to_connecting_arms_without_manual_selection', 0, async (): Promise<void> => {
      await fixture.ready();
      fixture.state('connectionStateConnecting');
      expect(fixture.clock.callbacks.size).assertEqual(1);
      fixture.clock.fire();
      await fixture.listReply();
      await fixture.listReply();
      expect(fixture.bridge.count('enableProxy')).assertEqual(1);
    });

    it('network_recovers_before_td_connecting', 0, async (): Promise<void> => {
      await fixture.ready();
      fixture.network.change('none');
      fixture.state('connectionStateWaitingForNetwork');
      fixture.network.change('wifi');
      expect(fixture.clock.callbacks.size).assertEqual(0);
      fixture.state('connectionStateConnecting');
      expect(fixture.clock.callbacks.size).assertEqual(1);
      expect(fixture.clock.lastDelay).assertEqual(10000);
    });

    it('td_connecting_arrives_before_network_recovery', 0, async (): Promise<void> => {
      await fixture.ready();
      fixture.network.change('none');
      fixture.state('connectionStateWaitingForNetwork');
      fixture.state('connectionStateConnecting');
      expect(fixture.clock.callbacks.size).assertEqual(0);
      fixture.network.change('mobile');
      expect(fixture.clock.callbacks.size).assertEqual(1);
      expect(fixture.clock.lastDelay).assertEqual(10000);
    });

    it('network_recovery_rearms_without_another_td_update', 0, (): void => {
      fixture.state('connectionStateConnectingToProxy');
      const oldCallback = fixture.clock.lastCallback;
      fixture.network.change('none');
      expect(fixture.clock.callbacks.size).assertEqual(0);
      oldCallback(); // already queued when cancellation happened
      expect(fixture.bridge.count('getProxies')).assertEqual(0);
      fixture.network.change('wifi');
      expect(fixture.clock.callbacks.size).assertEqual(1);
      expect(fixture.clock.lastDelay).assertEqual(10000);
    });

    it('offline_never_schedules_probes_or_busy_retries', 0, (): void => {
      fixture.network.change('none');
      fixture.state('connectionStateConnectingToProxy');
      fixture.state('connectionStateConnecting');
      fixture.service.settingsChanged();
      expect(fixture.clock.scheduled).assertEqual(0);
      expect(fixture.bridge.sent.length).assertEqual(0);
    });

    it('available_network_updates_do_not_reset_the_delay', 0, (): void => {
      fixture.state('connectionStateConnectingToProxy');
      const scheduled = fixture.clock.scheduled;
      fixture.network.change('mobile');
      fixture.network.change('wifi');
      expect(fixture.clock.scheduled).assertEqual(scheduled);
      expect(fixture.clock.callbacks.size).assertEqual(1);
    });

    it('cancelled_timer_cannot_erase_recovery_timer', 0, (): void => {
      fixture.state('connectionStateConnectingToProxy');
      const oldCallback = fixture.clock.lastCallback;
      fixture.network.change('none');
      fixture.network.change('wifi');
      oldCallback();
      fixture.state('connectionStateConnecting');
      expect(fixture.clock.callbacks.size).assertEqual(1);
      expect(fixture.clock.scheduled).assertEqual(2);
      fixture.network.change('none');
      expect(fixture.clock.callbacks.size).assertEqual(0);
    });

    it('old_list_cannot_block_or_release_new_attempt_after_recovery', 0, async (): Promise<void> => {
      await fixture.startListCheck();
      fixture.network.change('none');
      fixture.network.change('wifi');
      expect(fixture.clock.callbacks.size).assertEqual(1);
      fixture.clock.fire(); // new attempt starts before old list has replied
      await fixture.listReply(); // reply to old attempt
      expect(fixture.bridge.count('enableProxy')).assertEqual(0);
      expect(fixture.clock.callbacks.size).assertEqual(0);
      await fixture.listReply();
      await fixture.listReply();
      expect(fixture.bridge.count('enableProxy')).assertEqual(1);
    });

    it('manual_direct_selection_ignores_stale_list_and_recovers_with_full_delay', 0, async (): Promise<void> => {
      fixture.state('connectionStateReady'); // list refresh is still in flight
      fixture.service.proxySelectionChanged(0);
      fixture.network.change('none');
      fixture.state('connectionStateConnecting');
      await fixture.listReply(); // stale list still says proxy 1 is enabled
      fixture.network.change('wifi');
      fixture.state('connectionStateConnectingToProxy');
      expect(fixture.clock.callbacks.size).assertEqual(1);
      expect(fixture.clock.lastDelay).assertEqual(10000);
      expect(fixture.bridge.count('pingProxy')).assertEqual(0);
    });

    it('auto_switch_off_during_outage_stays_off_after_recovery', 0, (): void => {
      fixture.state('connectionStateConnectingToProxy');
      fixture.network.change('none');
      AppStorage.setOrCreate(KEY_PROXY_AUTO_SWITCH, false);
      fixture.service.settingsChanged();
      fixture.network.change('wifi');
      fixture.state('connectionStateConnecting');
      expect(fixture.clock.callbacks.size).assertEqual(0);
    });

    it('single_proxy_starts_failover_after_recovery', 0, (): void => {
      fixture.service.proxyListChanged([{ id: 1, isEnabled: true }]);
      fixture.network.change('none');
      fixture.state('connectionStateConnecting');
      fixture.network.change('wifi');
      expect(fixture.clock.callbacks.size).assertEqual(1);
    });

    it('unknown_list_checks_direct_session_before_any_probe', 0, async (): Promise<void> => {
      fixture.service.attach(fixture.client); // clears knowledge of the list
      fixture.state('connectionStateConnecting');
      expect(fixture.clock.callbacks.size).assertEqual(1);
      fixture.clock.fire();
      await fixture.listReply(false);
      await fixture.listReply(false);
      expect(fixture.bridge.count('pingProxy')).assertEqual(0);
      expect(fixture.bridge.count('enableProxy')).assertEqual(1);
      expect(fixture.clock.callbacks.size).assertEqual(0);
    });

    it('unknown_list_can_recover_an_enabled_proxy', 0, async (): Promise<void> => {
      fixture.service.attach(fixture.client);
      fixture.state('connectionStateConnecting');
      fixture.clock.fire();
      await fixture.listReply();
      await fixture.listReply();
      expect(fixture.bridge.count('enableProxy')).assertEqual(1);
    });

    it('late_list_refresh_reconciles_current_connecting_state', 0, async (): Promise<void> => {
      fixture.service.attach(fixture.client);
      fixture.state('connectionStateReady');
      fixture.state('connectionStateConnecting');
      await fixture.listReply();
      expect(fixture.clock.callbacks.size).assertEqual(1);
      fixture.clock.fire();
      await fixture.listReply();
      expect(fixture.bridge.count('pingProxy')).assertEqual(0);
      await fixture.listReply();
      expect(fixture.bridge.count('enableProxy')).assertEqual(1);
    });

    it('recovery_in_ready_or_updating_never_arms_failover', 0, async (): Promise<void> => {
      await fixture.ready();
      fixture.network.change('none');
      fixture.network.change('wifi');
      expect(fixture.clock.callbacks.size).assertEqual(0);
      fixture.state('connectionStateUpdating');
      fixture.network.change('none');
      fixture.network.change('mobile');
      expect(fixture.clock.callbacks.size).assertEqual(0);
    });

    it('detach_and_reattach_keep_exactly_one_network_subscription', 0, (): void => {
      expect(fixture.network.listeners.size).assertEqual(1);
      fixture.service.attach(fixture.client);
      expect(fixture.network.listeners.size).assertEqual(1);
      fixture.publishList();
      fixture.state('connectionStateConnectingToProxy');
      fixture.service.detach();
      expect(fixture.network.listeners.size).assertEqual(0);
      fixture.network.change('none');
      fixture.network.change('wifi');
      expect(fixture.clock.callbacks.size).assertEqual(0);
    });

    it('old_account_probe_does_not_hold_new_account_recovery', 0, async (): Promise<void> => {
      await fixture.startListCheck();
      const nextBridge = new ProxySwitchBridge();
      const nextClient = new TdClient(nextBridge);
      nextClient.start();
      try {
        fixture.service.attach(nextClient);
        fixture.publishList();
        const state: TdObject = { '@type': 'connectionStateConnecting' };
        const update: TdObject = { '@type': 'updateConnectionState' };
        update['state'] = state;
        nextClient.deliverParsed(update);
        expect(fixture.network.listeners.size).assertEqual(1);
        expect(fixture.clock.callbacks.size).assertEqual(1);
        fixture.clock.fire();
        await fixture.listReply(); // old account finally must not alter the new attempt
        expect(fixture.bridge.count('enableProxy')).assertEqual(0);
        expect(nextBridge.count('getProxies')).assertEqual(1);
        expect(fixture.clock.callbacks.size).assertEqual(0);
      } finally {
        fixture.service.detach();
        nextClient.dispose();
      }
    });
  });

}
