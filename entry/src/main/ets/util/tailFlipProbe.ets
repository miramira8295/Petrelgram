// 【临时探针，验完就删】玻璃气泡的「量到尺寸」往返计数。
//
// 要回答的问题：一次「打开会话 + 图片陆续到达」的过程里，同一行的
// glassW/glassH 从 0 到有值的往返发生**几次**？是每行一次（只有首次挂载和
// 复用），还是每次重新测量都来一次？
//
// 这条往返就是横向抖动的成因（见 bubbleGlassPath.glassPaintReady 的注释）：
// 没量到时玻璃档的 clipShape 挂不上，气泡画成没裁剪的矩形，左边缘外扩 7vp。
// 修复已经让「没量到」这一档退回实心渲染，形状不再跳；但**往返本身还在**，
// 次数决定了还会不会看到「玻璃闪一下」。这个探针数的就是它。
//
// 日志纪律：logW 攒够 300 行才落盘，绝不能每帧刷屏。所以
//   1. 按 messageId 去重 —— 每行只在第 1、2、5、10、20…次往返时各打一行；
//   2. 全局总数每 PROBE_SUMMARY_EVERY 次打一行汇总；
//   3. 整体封顶 PROBE_MAX_LINES 行，打满就彻底闭嘴。
// 日志文本全英文（本仓库不允许中文字符串字面量）。
//
// ── 删除清单 ──────────────────────────────────────────────────────
// 1. 本文件；
// 2. MessageBubble.ets / LightweightPlainTextBubble.ets 里的 import 与
//    onMeasured 回调里的 probeGlassMeasure(...) 调用（各一处）。

import { logW } from './log';

// 总开关。验完直接置 false 即可让所有调用变成一次布尔判断。
const PROBE_ON: boolean = true;

// 整个进程最多打这么多行，防止长时间挂机把日志缓冲冲干净。
const PROBE_MAX_LINES: number = 200;

// 每多少次全局往返打一行汇总。
const PROBE_SUMMARY_EVERY: number = 25;

// 每行消息各自的往返计数。第 1、2、5、10、20、50、100… 次各打一行。
const PROBE_MILESTONES: number[] = [1, 2, 5, 10, 20, 50, 100];

// messageId -> 该行已经历的 0 → 有值 往返次数。
const roundTrips: Map<number, number> = new Map<number, number>();

// messageId -> 上一次量到的尺寸是不是 0（用于识别「回到 0」这一半的往返）。
const wasZero: Map<number, boolean> = new Map<number, boolean>();

let linesPrinted: number = 0;
let totalRoundTrips: number = 0;

function emit(text: string): void {
  if (linesPrinted >= PROBE_MAX_LINES) {
    return;
  }
  linesPrinted += 1;
  logW(text);
}

function isMilestone(count: number): boolean {
  return PROBE_MILESTONES.indexOf(count) >= 0;
}

// 每次 onAreaChange 把尺寸交回组件时调一次。
//
// messageId 只用于去重与定位，不进任何持久化；kind 区分两支气泡
// （'rich' = MessageBubble，'plain' = LightweightPlainTextBubble）。
export function probeGlassMeasure(kind: string, messageId: number, w: number, h: number): void {
  if (!PROBE_ON) {
    return;
  }
  const zeroNow: boolean = w <= 0 || h <= 0;
  const zeroBefore: boolean = wasZero.get(messageId) ?? true;
  wasZero.set(messageId, zeroNow);
  if (zeroNow || !zeroBefore) {
    // 要么这次仍然没量到，要么上一次就已经量到了 —— 都不是一次新的往返。
    return;
  }
  const count: number = (roundTrips.get(messageId) ?? 0) + 1;
  roundTrips.set(messageId, count);
  totalRoundTrips += 1;
  if (isMilestone(count)) {
    emit(`[TailFlip] measured kind=${kind} msg=${messageId} roundTrip=${count} ` +
      `w=${Math.round(w)} h=${Math.round(h)}`);
  }
  if (totalRoundTrips % PROBE_SUMMARY_EVERY === 0) {
    emit(`[TailFlip] summary totalRoundTrips=${totalRoundTrips} rows=${roundTrips.size}`);
  }
}

// 判读方法（把日志导出来后按 [TailFlip] 过滤）：
//
// * 每行都只有 roundTrip=1 ⇒ 往返只发生在挂载/复用那一次。修复之后那一帧是
//   实心渲染，用户应当完全看不到跳动，玻璃在下一帧点亮。
// * 同一个 msg= 反复出现 roundTrip=2、5、10 ⇒ 尺寸在**反复回到 0**。那只可能
//   来自 aboutToReuse 的清零，也就是这一行被 Repeat 反复删旧插新（行 key 里
//   那些异步字段每落地一个就变一次 key）。真是这样的话，第二步要治的是
//   collapseAlbums 的行 key，而不是气泡本身。
// * rows= 远大于屏幕行数而每行 roundTrip=1 ⇒ 是滚动复用，属正常。
