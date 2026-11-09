import { CrashRecord } from '../services/crashRecordStore';

// #194「切深色卡得要死」那一轮的两个纯件。
//
// 官方《应用深浅色适配》：默认深浅色切换是**全量重绘**，开销随 UI 复杂度线性增加；
// onConfigurationUpdate 的范式是"比较 colorMode 变没变，变了才动"。我们原来对任何
// 配置变化（字号、转屏、回前台）都全量走一遍深浅色重算 + 外观 epoch 重绘。

// prev 用 -2 表示"还没见过"（ConfigurationConstant.ColorMode 是 -1/0/1）。
export const COLOR_MODE_UNKNOWN: number = -2;

export function colorModeChanged(prev: number, next: number | undefined): boolean {
  const mode: number = next ?? -1;
  return prev !== mode;
}

// 深浅色的**基准值**。抽成一个对象是因为 issue #194 的真因就是它被写了两遍：
//
//   onConfigurationUpdate(config) 里按**参数** config 记下新值（对的），
//   紧接着 applyImmersiveStatusBar() 又按 **this.context.config** 记了一遍（错的）——
//   那一刻 ability 缓存的 config 还是旧值。
//
// 结果：进深色记成 1→0 changed=true，基准却被盖回 1；再切回浅色算出 1→1
// changed=false 直接 return，状态栏反色 / KEY_APP_DARK / 外观 epoch 全不执行，
// 壁纸的深色遮罩就撤不掉（用户 2026-09-18 日志逐字对上）。
//
// 规矩：**只有启动时用 context 的当前值 seed 一次**，之后一律 observe 事件送来的值。
export class ColorModeBaseline {
  private value: number = COLOR_MODE_UNKNOWN;

  // 启动播种。这一刻 context.config 是权威的。
  seed(mode: number | undefined): void {
    this.value = mode ?? COLOR_MODE_UNKNOWN;
  }

  // 观察一次配置事件：真的变了返回 true 并推进基准，没变返回 false。
  observe(mode: number | undefined): boolean {
    const next: number = mode ?? COLOR_MODE_UNKNOWN;
    if (next === this.value) {
      return false;
    }
    this.value = next;
    return true;
  }

  current(): number {
    return this.value;
  }
}

// 诊断导出抬头后面附最近几条崩溃：类型 / 异常首行 / 前后台 / 存活秒数。
// 这次 #194 就是因为导出里没有崩溃信息，9 次冷启只能猜。
export function crashSummaryLines(records: CrashRecord[], limit: number): string[] {
  const sorted: CrashRecord[] = records.slice().sort(
    (a: CrashRecord, b: CrashRecord): number => b.time - a.time);
  const out: string[] = [];
  for (const r of sorted.slice(0, Math.max(0, limit))) {
    const firstLine: string = (r.exceptionMessage ?? '').split('\n')[0].trim();
    const what: string = firstLine !== '' ? `${r.exceptionName}: ${firstLine}` : r.exceptionName;
    out.push(`crash: ${new Date(r.time).toISOString()} ${r.crashType} ${what} ` +
      `(${r.foreground ? 'fg' : 'bg'}, life ${r.lifeTimeSec}s, v${r.appVersion})`);
  }
  return out;
}
