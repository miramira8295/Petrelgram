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
