// 定时给代理列表做 tcping，填 proxyHealth 那张表。
//
// 只在前台跑，而且只在"自动切换"勾着的时候跑：后台的定时器在 HarmonyOS 上本来
// 就不可靠，跑了也白耗电；没勾自动切换的人，这张表没有任何读者。
//
// 直链不在这里测——TDLib 不把 DC 地址交给应用层，没有合法的目标。直链的健康判据
// 就是 TDLib 自己的连接状态。
import { ProxyEntry, listProxies } from '../store/ProxyApi';
import { ProxySwitchCandidate } from '../util/proxyAutoSwitch';
import {
  ProxyHealthEntry, ProxyHealthSource, ProxyHealthTarget, proxyHealthUsable, proxyHealthOf,
  recordProxyHealth, sortProxyCandidates
} from '../util/proxyHealth';
import { measureProxyConnectMs } from '../util/proxyReach';
import { logI, logW } from '../util/log';

// 30 秒一轮。快到这个量级才有意义：从"卡住"到"决定换"之间最多等一轮。
export const PROXY_HEALTH_INTERVAL_MS: number = 30000;
// 单个目标的握手上限。3s 已经比绝大多数可用代理的实际握手时间长了，再放宽只会
// 让一轮巡检拖过 30 秒，表反而更旧。
export const PROXY_HEALTH_TIMEOUT_MS: number = 3000;
// 同时两个。串行的话十个代理一轮就是 30 秒，等于没有间隔；再高就是在跟自己抢带宽，
// 测出来的 RTT 也不准。
export const PROXY_HEALTH_CONCURRENCY: number = 2;

export interface ProxyHealthEnvironment {
  list(): Promise<ProxyHealthTarget[]>;
  measure(host: string, port: number, timeoutMs: number): Promise<number>;
  foreground(): boolean;
  now(): number;
  setTimeout(callback: () => void, ms: number): number;
  clearTimeout(id: number): void;
}

class SystemProxyHealthEnvironment implements ProxyHealthEnvironment {
  async list(): Promise<ProxyHealthTarget[]> {
    const entries = await listProxies();
    return entries.map((entry: ProxyEntry): ProxyHealthTarget => ({
      id: entry.id, server: entry.server, port: entry.port
    }));
  }
  measure(host: string, port: number, timeoutMs: number): Promise<number> {
    return measureProxyConnectMs(host, port, timeoutMs);
  }
  foreground(): boolean { return AppStorage.get<boolean>('appIsForeground') ?? true; }
  now(): number { return Date.now(); }
  setTimeout(callback: () => void, ms: number): number { return setTimeout(callback, ms); }
  clearTimeout(id: number): void { clearTimeout(id); }
}

export class ProxyHealthMonitor implements ProxyHealthSource {
  private env: ProxyHealthEnvironment;
  private table: ProxyHealthEntry[] = [];
  private timer: number = -1;
  private generation: number = 0;
  private polling: boolean = false;

  constructor(env?: ProxyHealthEnvironment) {
    this.env = env ?? new SystemProxyHealthEnvironment();
  }

  // 重复 start 不该多出一条定时器链：勾选框每拨一次都会调进来。
  start(): void {
    if (this.timer !== -1) { return; }
    const token = ++this.generation;
    // 立刻来一轮，别让用户先空等 30 秒——刚开自动切换的人往往正是连不上的时候。
    this.pollOnce();
    this.schedule(token);
  }

  stop(): void {
    this.generation++;
    if (this.timer !== -1) {
      this.env.clearTimeout(this.timer);
      this.timer = -1;
    }
  }

  running(): boolean { return this.timer !== -1; }

  snapshot(): ProxyHealthEntry[] { return this.table; }

  usable(id: number): boolean { return proxyHealthUsable(this.table, id); }

  sortedForSwitch(entries: ProxySwitchCandidate[]): ProxySwitchCandidate[] {
    return sortProxyCandidates(entries, this.table);
  }

  // 一轮巡检。并发受 PROXY_HEALTH_CONCURRENCY 限制，全部走完才算结束。
  async pollOnce(): Promise<void> {
    if (this.polling || !this.env.foreground()) { return; }
    const token = this.generation;
    this.polling = true;
    try {
      const targets = await this.env.list();
      if (token !== this.generation) { return; }
      let next = 0;
      const worker = async (): Promise<void> => {
        while (next < targets.length && token === this.generation) {
          const target = targets[next++];
          await this.probe(target, token);
        }
      };
      const workers: Promise<void>[] = [];
      for (let i = 0; i < Math.min(PROXY_HEALTH_CONCURRENCY, targets.length); i++) {
        workers.push(worker());
      }
      await Promise.all(workers);
    } catch (caught) {
      // 列代理失败（刚切账号、TDLib 还没就绪）不是错误，下一轮重来。
      logW(`[proxy-health] poll failed: ${(caught as Error).message}`);
    } finally {
      this.polling = false;
    }
  }

  private async probe(target: ProxyHealthTarget, token: number): Promise<void> {
    let rttMs: number | null = null;
    try {
      rttMs = await this.env.measure(target.server, target.port, PROXY_HEALTH_TIMEOUT_MS);
    } catch (_caught) {
      rttMs = null;
    }
    if (token !== this.generation) { return; }
    const changed = proxyHealthOf(this.table, target.id);
    this.table = recordProxyHealth(this.table, target, rttMs, this.env.now());
    // 只在状态翻面时打一行。每次巡检都打会把日志刷满，而且这里有服务器地址，
    // 只留 id 和结果。
    const after = proxyHealthOf(this.table, target.id);
    if (changed === undefined || (changed.failCount > 0) !== (after !== undefined && after.failCount > 0)) {
      logI(`[proxy-health] proxy ${target.id} ${rttMs === null ? 'unreachable' : `rtt=${Math.round(rttMs)}ms`}`);
    }
  }

  private schedule(token: number): void {
    this.timer = this.env.setTimeout((): void => {
      if (token !== this.generation) { return; }
      this.timer = -1;
      this.pollOnce();
      if (token === this.generation) { this.schedule(token); }
    }, PROXY_HEALTH_INTERVAL_MS);
  }
}

export const proxyHealthMonitor: ProxyHealthMonitor = new ProxyHealthMonitor();
