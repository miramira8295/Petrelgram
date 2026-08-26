import { logE } from './log';
// 面板性能探针（诊断用，定位完整体删除）。
//
// 为什么要聚合：贴纸网格一屏几十格，逐格打一行日志会把 hilog 刷爆，光是
// 打印本身就够改变被测对象的行为。这里只累加计数，每秒吐一行汇总，静止时
// 一行都不打。
//
// 用法：在关心的点上调 probeHit('cell.build')，滑动一段时间后看日志里的
// [probe] 行，把各项速率和系统的 jank 事件按时间戳对齐。

const counts: Map<string, number> = new Map();
const FLUSH_MS: number = 1000;
let timer: number = -1;
let windowStart: number = 0;

function flush(): void {
  if (counts.size === 0) {
    // 静止了就把定时器收掉，别留一个永远在转的空转任务。
    if (timer !== -1) {
      clearInterval(timer);
      timer = -1;
    }
    return;
  }
  const elapsed: number = Date.now() - windowStart;
  const parts: string[] = [];
  counts.forEach((n: number, k: string): void => { parts.push(`${k}=${n}`); });
  parts.sort();
  logE(`[probe] ${elapsed}ms ${parts.join(' ')}`);
  counts.clear();
  windowStart = Date.now();
}

export function probeHit(name: string, times: number = 1): void {
  counts.set(name, (counts.get(name) ?? 0) + times);
  if (timer === -1) {
    windowStart = Date.now();
    timer = setInterval((): void => { flush(); }, FLUSH_MS);
  }
}

// [ReuseProbe] 复用语义探针（审计 P2-1，docs/superpowers/specs/2026-08-26-p2-state-audit.md
// 第 4 节 ①-1）。递归复用时子组件 aboutToReuse 收到的 params 到底是新一轮构造
// 参数、上一轮的旧值、还是根本没有，官方文档没有规定，静态代码也判不出来。
// 这条探针是 P0-4 定级的唯一依据：params 恒为新值 → P0-4 是防御性加固；
// 出现旧值或缺失 → P0-4 是真 bug 修复。上机读一次日志后再决定删不删。
//
// 为什么不用 probeHit 的聚合：这里要看的是具体 id 的对比，聚合计数答不了。
//
// **判据必须以 attach 时记下的「上一条」为基准，绝不能拿 this.msg / this.group
// 当基准。** 「aboutToReuse 触发时 @Prop 有没有落地」正是这条探针要回答的那个
// 未知数（代码里两处注释自己写着 "Child @Prop refreshes may land after this
// callback"），拿未知数当基准会把极性判反：params 是新值（健康）时反而与旧的
// this.msg 不等被判成异常，params 是旧值（真 bug）时反而与旧的 this.msg 相等
// 被判成正常、还会被限流静音掉。
// 所以基准取各组件 attach 时记下的 id（probeAttachedRowId / probeAttachedKey）：
//   param id **等于** attached id → params 带的是**上一条**的陈旧值 → STALE（危险）
//   param id **不等于** attached id → params 带的是新值 → fresh（健康）
//   present=0（根本没带这个 key）同样记 STALE。
//
// 限流只静音**健康行**：前 REUSE_PROBE_VERBOSE 行无条件打（看常态），之后
// fresh 行不再打，STALE 行永远打——危险样本一条都不能被刷屏限流吃掉。
const REUSE_PROBE_VERBOSE: number = 200;
let reuseProbeLines: number = 0;

// 调用点先判这个再拼日志串（I-5）：健康且超配额时直接跳过，两个格式化 id 串
// 连构造都不构造，不给滚动热路径加常数开销。
export function reuseProbeSkip(stale: boolean): boolean {
  reuseProbeLines++;
  return !stale && reuseProbeLines > REUSE_PROBE_VERBOSE;
}

export function reuseProbe(component: string, key: string, present: boolean,
    stale: boolean, paramIds: string, attachedIds: string): void {
  logE(`[ReuseProbe] ${component} key=${key} present=${present ? 1 : 0}` +
    ` param(${paramIds}) attached(${attachedIds}) ${stale ? 'STALE' : 'fresh'}`);
}

// 一次性的、需要看具体数值的事件（比如整表 RELOAD 带了多少条），直接打出来。
// 这类事件本身应当是低频的——如果它高频到刷屏，那件事本身就是要找的问题。
export function probeEvent(name: string, detail: string): void {
  logE(`[probe] ${name} ${detail}`);
}
