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
// 为什么要限流：滑动时每行都会打一行，刷爆 hilog 本身就会改变被测对象；
// 前 REUSE_PROBE_VERBOSE 行无条件打（看常态），之后只打异常行（缺 key 或
// 与 @Prop 不一致），这样罕见的旧值/缺失也不会被限流吃掉。
const REUSE_PROBE_VERBOSE: number = 200;
let reuseProbeLines: number = 0;

export function reuseProbe(component: string, key: string, present: boolean,
    paramIds: string, propIds: string): void {
  const mismatch: boolean = !present || paramIds !== propIds;
  reuseProbeLines++;
  if (reuseProbeLines > REUSE_PROBE_VERBOSE && !mismatch) {
    return;
  }
  logE(`[ReuseProbe] ${component} key=${key} present=${present ? 1 : 0}` +
    ` param(${paramIds}) prop(${propIds}) ${mismatch ? 'MISMATCH' : 'match'}`);
}

// 一次性的、需要看具体数值的事件（比如整表 RELOAD 带了多少条），直接打出来。
// 这类事件本身应当是低频的——如果它高频到刷屏，那件事本身就是要找的问题。
export function probeEvent(name: string, detail: string): void {
  logE(`[probe] ${name} ${detail}`);
}
