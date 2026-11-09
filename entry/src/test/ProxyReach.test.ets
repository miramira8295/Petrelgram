import { describe, expect, it } from '@ohos/hypium';
import { connection, socket } from '@kit.NetworkKit';
import {
  measureProxyConnectMs, ProxyReachEnvironment, ProxyReachNetwork, ProxyReachSocket
} from '../main/ets/util/proxyReach';

class ReachAction {
  kind: string;
  ms: number;
  constructor(kind: string = 'ok', ms: number = 17) { this.kind = kind; this.ms = ms; }
}

class ReachTimer {
  at: number;
  callback: () => void;
  constructor(at: number, callback: () => void) { this.at = at; this.callback = callback; }
}

class ReachSocket implements ProxyReachSocket {
  closes: number = 0;
  complete: () => void = (): void => {};
  private env: ReachEnvironment;
  private action: ReachAction;
  constructor(env: ReachEnvironment, action: ReachAction) { this.env = env; this.action = action; }

  connect(options: socket.TCPConnectOptions): Promise<void> {
    this.env.attempts.push(options);
    this.env.time += this.action.ms;
    if (this.action.kind === 'error') { return Promise.reject(new Error('unreachable')); }
    if (this.action.kind === 'pending') {
      return new Promise<void>((resolve): void => { this.complete = resolve; });
    }
    return Promise.resolve();
  }

  close(): Promise<void> {
    this.closes++;
    if (this.env.closeMode === 'pending') { return new Promise<void>((): void => {}); }
    if (this.env.closeMode === 'error') { return Promise.reject(new Error('close failed')); }
    return Promise.resolve();
  }
}

class ReachNetwork implements ProxyReachNetwork {
  private env: ReachEnvironment;
  constructor(env: ReachEnvironment) { this.env = env; }
  resolve(host: string): Promise<connection.NetAddress[]> {
    this.env.resolvedHost = host;
    this.env.time += this.env.dnsMs;
    if (this.env.dnsMode === 'pending') { return new Promise<connection.NetAddress[]>((): void => {}); }
    if (this.env.dnsMode === 'error') { return Promise.reject(new Error('dns failed')); }
    return Promise.resolve(this.env.addresses);
  }
  localFamilies(): Promise<number[]> {
    this.env.localReads++;
    if (this.env.localMode === 'pending') { return new Promise<number[]>((): void => {}); }
    if (this.env.localMode === 'error') { return Promise.reject(new Error('capabilities unavailable')); }
    return Promise.resolve(this.env.families);
  }
}

class ReachEnvironment implements ProxyReachEnvironment {
  time: number = 0;
  addresses: connection.NetAddress[] = [
    { address: '192.0.2.1', family: 1 }, { address: '2001:db8::1', family: 2 }
  ];
  families: number[] = [1, 2];
  forced: boolean = false;
  actions: ReachAction[] = [];
  sockets: ReachSocket[] = [];
  attempts: socket.TCPConnectOptions[] = [];
  timers: Map<number, ReachTimer> = new Map();
  nextTimer: number = 0;
  networkReads: number = 0;
  localReads: number = 0;
  resolvedHost: string = '';
  dnsMs: number = 0;
  dnsMode: string = '';
  localMode: string = '';
  closeMode: string = '';

  getNetwork(): Promise<ProxyReachNetwork> {
    this.networkReads++;
    return Promise.resolve(new ReachNetwork(this));
  }
  createSocket(): ProxyReachSocket {
    const tcp = new ReachSocket(this, this.actions.shift() ?? new ReachAction());
    this.sockets.push(tcp);
    return tcp;
  }
  preferIpv6(): boolean { return this.forced; }
  now(): number { return this.time; }
  setTimeout(callback: () => void, ms: number): number {
    const id = ++this.nextTimer;
    this.timers.set(id, new ReachTimer(this.time + ms, callback));
    return id;
  }
  clearTimeout(id: number): void { this.timers.delete(id); }
  advance(ms: number): void {
    this.time += ms;
    this.timers.forEach((timer: ReachTimer, id: number): void => {
      if (timer.at <= this.time) { this.timers.delete(id); timer.callback(); }
    });
  }
  measure(host: string = 'proxy.example.test'): Promise<number> {
    return measureProxyConnectMs(host, 443, 5000, this);
  }
}

async function settleReach(): Promise<void> {
  for (let i = 0; i < 16; i++) { await Promise.resolve(); }
}

function reachError(promise: Promise<number>): Promise<string> {
  return promise.then((): string => 'unexpected success', (error: Error): string => error.message);
}

export default function proxyReachTest() {
  describe('ProxyReach', (): void => {
    it('ipv6_only_local_network_ignores_ipv4_dns_precedence', 0, async (): Promise<void> => {
      const env = new ReachEnvironment();
      env.families = [2];
      expect(await env.measure()).assertEqual(17);
      expect(env.attempts[0].address.family).assertEqual(2);
      expect(env.attempts[0].address.address).assertEqual('2001:db8::1');
      expect(env.networkReads).assertEqual(1);
      expect(env.localReads).assertEqual(1);
      expect(env.sockets[0].closes).assertEqual(1);
      expect(env.timers.size).assertEqual(0);
    });

    it('user_ipv6_preference_applies_on_dual_stack', 0, async (): Promise<void> => {
      const env = new ReachEnvironment();
      env.forced = true;
      await env.measure();
      expect(env.attempts[0].address.family).assertEqual(2);
    });

    it('dual_stack_defaults_to_ipv4_even_when_aaaa_is_first', 0, async (): Promise<void> => {
      const env = new ReachEnvironment();
      env.addresses.reverse();
      await env.measure();
      expect(env.attempts[0].address.family).assertEqual(1);
    });

    it('failed_first_address_uses_other_family_and_reports_only_winning_handshake', 0, async (): Promise<void> => {
      const env = new ReachEnvironment();
      env.dnsMs = 200;
      env.actions = [new ReachAction('error', 300), new ReachAction('ok', 23)];
      expect(await env.measure()).assertEqual(23);
      expect(env.attempts.length).assertEqual(2);
      expect(env.attempts[1].address.family).assertEqual(2);
      expect(env.attempts[1].timeout).assertEqual(4500);
      expect(env.sockets[0].closes).assertEqual(1);
      expect(env.sockets[1].closes).assertEqual(1);
      expect(env.timers.size).assertEqual(0);
    });

    it('ipv6_preference_can_fall_back_to_ipv4', 0, async (): Promise<void> => {
      const env = new ReachEnvironment();
      env.forced = true;
      env.actions = [new ReachAction('error', 1), new ReachAction('ok', 20)];
      expect(await env.measure()).assertEqual(20);
      expect(env.attempts[0].address.family).assertEqual(2);
      expect(env.attempts[1].address.family).assertEqual(1);
    });

    it('unknown_or_failed_local_probe_keeps_candidates_available', 0, async (): Promise<void> => {
      const env = new ReachEnvironment();
      env.localMode = 'error';
      await env.measure();
      expect(env.attempts[0].address.family).assertEqual(1);
      const unknown = new ReachEnvironment();
      unknown.families = [0];
      await unknown.measure();
      expect(unknown.attempts[0].address.family).assertEqual(1);
    });

    it('stuck_optional_probe_uses_only_250ms_of_total_budget', 0, async (): Promise<void> => {
      const env = new ReachEnvironment();
      env.localMode = 'pending';
      const result = env.measure();
      await settleReach();
      env.advance(250);
      expect(await result).assertEqual(17);
      expect(env.attempts[0].timeout).assertEqual(2375);
      expect(env.timers.size).assertEqual(0);
    });

    it('ipv6_literal_strips_brackets_and_skips_dns', 0, async (): Promise<void> => {
      const env = new ReachEnvironment();
      await env.measure(' [2001:db8::5] ');
      expect(env.networkReads).assertEqual(0);
      expect(env.attempts[0].address.address).assertEqual('2001:db8::5');
      expect(env.attempts[0].address.family).assertEqual(2);
      expect(env.attempts[0].timeout).assertEqual(5000);
    });

    it('ipv4_literal_keeps_its_family_even_with_ipv6_preference', 0, async (): Promise<void> => {
      const env = new ReachEnvironment();
      env.forced = true;
      await env.measure('192.0.2.4');
      expect(env.networkReads).assertEqual(0);
      expect(env.attempts[0].address.family).assertEqual(1);
    });

    it('empty_dns_result_does_not_open_socket', 0, async (): Promise<void> => {
      const env = new ReachEnvironment();
      env.addresses = [];
      expect(await reachError(env.measure())).assertEqual('dns: no proxy address');
      expect(env.sockets.length).assertEqual(0);
      expect(env.timers.size).assertEqual(0);
    });

    it('dns_failure_does_not_start_capability_probe_or_socket', 0, async (): Promise<void> => {
      const env = new ReachEnvironment();
      env.dnsMode = 'error';
      expect(await reachError(env.measure())).assertEqual('dns failed');
      expect(env.localReads).assertEqual(0);
      expect(env.sockets.length).assertEqual(0);
      expect(env.timers.size).assertEqual(0);
    });

    it('stuck_dns_is_bounded_by_total_deadline', 0, async (): Promise<void> => {
      const env = new ReachEnvironment();
      env.dnsMode = 'pending';
      const result = reachError(env.measure());
      await settleReach();
      env.advance(5000);
      expect(await result).assertEqual('proxy reach timeout');
      expect(env.sockets.length).assertEqual(0);
      expect(env.timers.size).assertEqual(0);
    });

    it('stuck_first_connect_leaves_time_for_fallback', 0, async (): Promise<void> => {
      const env = new ReachEnvironment();
      env.actions = [new ReachAction('pending', 0), new ReachAction('ok', 11)];
      const result = env.measure();
      await settleReach();
      expect(env.attempts.length).assertEqual(1);
      env.advance(2500);
      expect(await result).assertEqual(11);
      expect(env.attempts[1].timeout).assertEqual(2500);
      expect(env.sockets[0].closes).assertEqual(1);
      env.sockets[0].complete(); // A late native success must be closed too.
      await settleReach();
      expect(env.sockets[0].closes).assertEqual(2);
      expect(env.timers.size).assertEqual(0);
    });

    it('all_hanging_connects_share_one_deadline_and_are_closed', 0, async (): Promise<void> => {
      const env = new ReachEnvironment();
      env.actions = [new ReachAction('pending', 0), new ReachAction('pending', 0)];
      const result = reachError(env.measure());
      await settleReach();
      env.advance(2500);
      await settleReach();
      env.advance(2500);
      expect(await result).assertEqual('proxy reach timeout');
      expect(env.time).assertEqual(5000);
      expect(env.sockets[0].closes).assertEqual(1);
      expect(env.sockets[1].closes).assertEqual(1);
      expect(env.timers.size).assertEqual(0);
    });

    it('multiple_same_family_addresses_do_not_starve_other_family', 0, async (): Promise<void> => {
      const env = new ReachEnvironment();
      env.addresses = [
        { address: '192.0.2.1', family: 1 }, { address: '192.0.2.2', family: 1 },
        { address: '2001:db8::1', family: 2 }
      ];
      env.actions = [new ReachAction('error', 5), new ReachAction('ok', 12)];
      expect(await env.measure()).assertEqual(12);
      expect(env.attempts[1].address.family).assertEqual(2);
    });

    it('duplicate_dns_addresses_are_not_retried', 0, async (): Promise<void> => {
      const env = new ReachEnvironment();
      env.addresses = [
        { address: '192.0.2.1', family: 1 }, { address: '192.0.2.1', family: 1 },
        { address: '192.0.2.2', family: 1 }
      ];
      env.actions = [new ReachAction('error', 5), new ReachAction('ok', 12)];
      await env.measure();
      expect(env.attempts[1].address.address).assertEqual('192.0.2.2');
    });

    it('single_aaaa_result_uses_explicit_family_even_when_metadata_is_missing', 0, async (): Promise<void> => {
      const env = new ReachEnvironment();
      env.addresses = [{ address: '2001:db8::1' }];
      env.families = [];
      await env.measure();
      expect(env.attempts[0].address.family).assertEqual(2);
      expect(env.attempts[0].timeout).assertEqual(5000);
    });

    it('close_failure_or_hang_cannot_hide_success_or_extend_deadline', 0, async (): Promise<void> => {
      const env = new ReachEnvironment();
      env.closeMode = 'error';
      expect(await env.measure()).assertEqual(17);
      const pending = new ReachEnvironment();
      pending.closeMode = 'pending';
      expect(await pending.measure()).assertEqual(17);
      expect(pending.sockets[0].closes).assertEqual(1);
    });

    it('all_rejected_addresses_are_closed_and_failure_is_returned', 0, async (): Promise<void> => {
      const env = new ReachEnvironment();
      env.actions = [new ReachAction('error', 1), new ReachAction('error', 2)];
      expect(await reachError(env.measure())).assertEqual('unreachable');
      expect(env.sockets[0].closes).assertEqual(1);
      expect(env.sockets[1].closes).assertEqual(1);
      expect(env.timers.size).assertEqual(0);
    });
  });
}
