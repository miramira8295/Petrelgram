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
  console.error(`[probe] ${elapsed}ms ${parts.join(' ')}`);
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

// 一次性的、需要看具体数值的事件（比如整表 RELOAD 带了多少条），直接打出来。
// 这类事件本身应当是低频的——如果它高频到刷屏，那件事本身就是要找的问题。
export function probeEvent(name: string, detail: string): void {
  console.error(`[probe] ${name} ${detail}`);
}
