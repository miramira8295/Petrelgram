// 列表侧打点（2026-11-06，临时仪表）。
//
// 目的：回答"一次列表测量/复用到底建了多少条消息"，把 trace 里 "List 测量 121ms"
// 这个数字落到行数上。只统计、不改行为；每 60 帧（约 0.5s）打一行 hilog：
//
//   RowProbe f=帧数 row=建行数 max=单帧最多行 prep=行准备耗时ms hit=缓存命中
//
// 读法：
//   · max / row  → 单帧峰值建行数（这就是要压的量）
//   · prep/frame → 行准备（prepareMessageBubble）占掉的毫秒
//   · 与 trace 的 List 测量耗时对照，就能算出"每条消息的测量成本"
import { displaySync } from '@kit.ArkGraphics2D';
import { hilog } from '@kit.PerformanceAnalysisKit';

const ENABLED: boolean = true;

class RowProbe {
  private sync: displaySync.DisplaySync | undefined = undefined;
  private frames: number = 0;
  private rowsFrame: number = 0;
  private rowsTotal: number = 0;
  private maxPerFrame: number = 0;
  private prepares: number = 0;
  private prepareNs: number = 0;

  start(): void {
    if (!ENABLED || this.sync !== undefined) {
      return;
    }
    const ds: displaySync.DisplaySync = displaySync.create();
    ds.setExpectedFrameRateRange({ min: 30, max: 120, expected: 120 });
    ds.on('frame', (): void => { this.tick(); });
    ds.start();
    this.sync = ds;
  }

  stop(): void {
    if (this.sync !== undefined) {
      this.sync.stop();
      this.sync = undefined;
    }
  }

  // 建一行（含复用拿走外壳后的重建）。
  rowBuilt(): void {
    if (!ENABLED) {
      return;
    }
    this.rowsFrame += 1;
    this.rowsTotal += 1;
  }

  // 行准备耗时（prepareMessageBubble）。
  recordPrepare(ns: number): void {
    if (!ENABLED) {
      return;
    }
    this.prepares += 1;
    this.prepareNs += ns;
  }

  private tick(): void {
    this.frames += 1;
    if (this.rowsFrame > this.maxPerFrame) {
      this.maxPerFrame = this.rowsFrame;
    }
    this.rowsFrame = 0;
    if (this.frames % 60 !== 0) {
      return;
    }
    if (this.rowsTotal === 0 && this.prepares === 0) {
      return; // 没有行在动就不打，避免静止时刷屏
    }
    hilog.info(0x0000, 'RowProbe',
      'f=%{public}d row=%{public}d max=%{public}d prep=%{public}d prepares=%{public}d',
      this.frames, this.rowsTotal, this.maxPerFrame,
      Math.round(this.prepareNs / 1e6), this.prepares);
    this.frames = 0;
    this.rowsTotal = 0;
    this.maxPerFrame = 0;
    this.prepares = 0;
    this.prepareNs = 0;
  }
}

export const rowProbe: RowProbe = new RowProbe();
