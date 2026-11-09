// 代理的"通不通、多快"表，由定时 tcping 填。
//
// 【为什么不用 TDLib 的 pingProxy】
// pingProxy 验的是"经这个代理到 Telegram DC"的端到端路径，判据更真，但有两个
// 硬伤：一是**假阴性**很常见（issue #31 就是代理明明能用、pingProxy 报错），
// 二是它要 TDLib 客户端活着、一次好几秒，做不了 30 秒一轮的常态巡检。
//
// 【这张表能得出什么、不能得出什么】
// TCP 握手成功只证明**端口开着**。SOCKS5 认证失败、认证过了但出不了网、流量
// 跑超——这三种 tcping 全绿。所以这张表只负责**排序**：出问题时第一个去试谁。
// "这个代理真的能用"这件事仍然只有 TDLib 连上以后才知道。
//
// 直链（id 0）不在表里：TDLib 不把 DC 地址交给应用层，没有合法的 tcping 目标。
// 直链的健康判据就是 TDLib 自己的连接状态，表里只把它排在最后当兜底。
import { ProxySwitchCandidate } from './proxyAutoSwitch';

// 新样本占三成。取 0.3 而不是 0.5：一次抖动（比如切基站）不该把好代理挤下去，
// 但连续两次变慢要能反映出来。
export const PROXY_HEALTH_EWMA_ALPHA: number = 0.3;

export interface ProxyHealthTarget {
  id: number;
  server: string;
  port: number;
}

export interface ProxyHealthEntry {
  id: number;
  // server:port。id 换账号会变，键不会，所以"这台服务器上次多快"能跨账号沿用。
  key: string;
  // 成功握手的 EWMA；-1 = 还没有成功样本。
  rttMs: number;
  okAt: number;
  failAt: number;
  // 连续失败次数。成功一次清零。
  failCount: number;
}

// 自动切换只依赖这四件事，具体怎么测（真实 tcping / 单测里的假表）由实现方决定。
export interface ProxyHealthSource {
  start(): void;
  stop(): void;
  usable(id: number): boolean;
  sortedForSwitch(entries: ProxySwitchCandidate[]): ProxySwitchCandidate[];
}

export const HEALTH_OK: number = 0;
export const HEALTH_UNKNOWN: number = 1;
export const HEALTH_FAILING: number = 2;

export function proxyHealthKey(server: string, port: number): string {
  return `${server}:${port}`;
}

export function proxyHealthOf(table: ProxyHealthEntry[], id: number): ProxyHealthEntry | undefined {
  return table.find((entry: ProxyHealthEntry): boolean => entry.id === id);
}

// rttMs 为 null 表示这次握手失败或超时。失败**不覆盖** EWMA：一个代理偶发超时
// 不代表它一直慢，把成功样本抹掉会让它再也排不回来。
export function recordProxyHealth(
  table: ProxyHealthEntry[], target: ProxyHealthTarget, rttMs: number | null, now: number
): ProxyHealthEntry[] {
  const key = proxyHealthKey(target.server, target.port);
  const previous = proxyHealthOf(table, target.id);
  const base: ProxyHealthEntry = previous ?? {
    id: target.id, key: key, rttMs: -1, okAt: 0, failAt: 0, failCount: 0
  };
  let next: ProxyHealthEntry;
  if (rttMs === null || !Number.isFinite(rttMs) || rttMs < 0) {
    next = {
      id: base.id, key: key, rttMs: base.rttMs,
      okAt: base.okAt, failAt: now, failCount: base.failCount + 1
    };
  } else {
    const rtt = base.rttMs < 0
      ? rttMs
      : PROXY_HEALTH_EWMA_ALPHA * rttMs + (1 - PROXY_HEALTH_EWMA_ALPHA) * base.rttMs;
    next = { id: base.id, key: key, rttMs: rtt, okAt: now, failAt: base.failAt, failCount: 0 };
  }
  // 改变数组长度会让 ArkUI 按新的总量重新绑定，代理页每轮都在刷这张表。
  if (previous === undefined) {
    return [...table, next];
  }
  return table.map((entry: ProxyHealthEntry): ProxyHealthEntry => entry.id === target.id ? next : entry);
}

export function proxyHealthRank(entry: ProxyHealthEntry | undefined): number {
  if (entry === undefined) { return HEALTH_UNKNOWN; }
  if (entry.failCount > 0) { return HEALTH_FAILING; }
  if (entry.rttMs < 0) { return HEALTH_UNKNOWN; }
  return HEALTH_OK;
}

interface RankedCandidate {
  entry: ProxySwitchCandidate;
  rank: number;
  rttMs: number;
  order: number;
}

// 先按档位（好的 → 没测过 → 正在失败的），同档按 EWMA 从快到慢，再同就按 TDLib
// 给的原始顺序。用原始下标而不是 id 兜底：TDLib 的 getProxies 顺序就是用户在
// 列表里看到的顺序，排序结果不该在两份同样健康的数据之间把它打乱。
function compareRanked(a: RankedCandidate, b: RankedCandidate): number {
  if (a.rank !== b.rank) { return a.rank - b.rank; }
  if (a.rank === HEALTH_OK && a.rttMs !== b.rttMs) { return a.rttMs - b.rttMs; }
  return a.order - b.order;
}

// 把候选代理按"值得先试"的顺序重排，交给 orderedProxyCandidateIds 做环形轮转。
//
// 只重排、不增删：轮转（从当前/上次的下一项开始、绕一圈、跳过正在用的那个）
// 由既有的 orderedProxyCandidateIds 负责，这里只回答"谁排前面"。直链不在这张
// 表里，它的位置仍由轮转决定——会勾自动切换的人本来就是直链不通才配的代理，
// 但把所有代理试完之前不该掉回直链，这一点由 usable() 保证：表里没有的 id 不算死。
export function sortProxyCandidates(
  entries: ProxySwitchCandidate[], table: ProxyHealthEntry[]
): ProxySwitchCandidate[] {
  const candidates: RankedCandidate[] = entries.map(
    (entry: ProxySwitchCandidate, index: number): RankedCandidate => {
      const health = proxyHealthOf(table, entry.id);
      return {
        entry: entry, rank: proxyHealthRank(health), rttMs: health === undefined ? -1 : health.rttMs,
        order: index
      };
    });
  candidates.sort(compareRanked);
  return candidates.map((candidate: RankedCandidate): ProxySwitchCandidate => candidate.entry);
}

// 这个 id 现在值不值得去试。没测过算"值得"：巡检刚开始时表是空的，把它判死
// 就等于自动切换永不生效。
export function proxyHealthUsable(table: ProxyHealthEntry[], id: number): boolean {
  if (id === 0) { return true; }
  return proxyHealthRank(proxyHealthOf(table, id)) !== HEALTH_FAILING;
}
