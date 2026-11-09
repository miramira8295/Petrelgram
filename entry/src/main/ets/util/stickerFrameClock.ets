import { displaySync } from '@kit.ArkGraphics2D';
import { UIContext } from '@kit.ArkUI';
import { TgsRateRange, tgsClockRange } from './tgsPlayback';
import { logE, logW } from './log';

// 动态贴纸共用的出帧时钟（displaySync，跟着屏幕刷新走）：TGS（TgsNativeStickerView）与
// 透明 WebM 帧序列（AlphaWebmStickerView）都挂在这里。
//
// 【为什么换掉 setTimeout】原来每张贴纸画完一帧才 setTimeout(1000/fps) 约下一拍，
// 真实周期是「间隔 + 排队 + 渲染」：实际帧率低于设定、每拍长短不一；帧号又按墙钟
// 算，于是每拍前进的源帧数时 2 时 3——大表情上一顿一顿（用户 2026-09-17 报）。
// displaySync 的回调对齐屏幕刷新，还给出下一帧的上屏时刻 targetTimestamp，按它
// 算帧号，间隔均匀。
//
// 【为什么全应用只建一个】官方文档没写同屏多个实例的开销，而贴纸面板一屏几十张。
// 一个实例、回调里分发给在播的贴纸，开销是确定的。期望帧率取在播里最高的那个
// （tgsClockRange），各贴纸按自己的帧率隔拍要帧（tgsFrameDue）。
//
// 【官方文档里的约束，这里一条条接住】
//   · 回调在 UI 主线程执行，耗时长会卡——这里只做分发，渲染在原生队列上
//     （util/tgsRenderQueue）。
//   · start() 会绑定当前 UI 上下文和窗口；在异步回调里调可能绑错，回调根本不来。
//     贴纸都是在"打开文件完成""渲染完成"这些异步回调里起播的，所以一律经
//     runScopedTask 起。
//   · 不用了必须 stop()：最后一个订阅退掉就停，不让系统空转请求 VSync。

export type StickerFrameListener = (timestampMs: number, targetMs: number) => void;

interface ClockEntry {
  fps: number;
  listener: StickerFrameListener;
}

// 时间戳是纳秒（系统启动以来的单调时间），换成毫秒给上层。
const NS_PER_MS: number = 1000000;

class StickerFrameClock {
  private sync: displaySync.DisplaySync | null = null;
  private entries: Map<number, ClockEntry> = new Map<number, ClockEntry>();
  private nextId: number = 1;
  private running: boolean = false;
  private appliedExpected: number = -1;
  private firstFrameLogged: boolean = false;

  private readonly onFrame = (info: displaySync.IntervalInfo): void => {
    if (!this.firstFrameLogged) {
      this.firstFrameLogged = true;
      logW(`[StickerClock] first frame expected=${this.appliedExpected}`);
    }
    const timestampMs: number = info.timestamp / NS_PER_MS;
    const targetMs: number = info.targetTimestamp / NS_PER_MS;
    // 先拍快照：分发过程中贴纸可能退订（播完、滑出屏幕），不能边改边遍历。
    const list: ClockEntry[] = [];
    this.entries.forEach((entry: ClockEntry): void => { list.push(entry); });
    for (const entry of list) {
      try {
        entry.listener(timestampMs, targetMs);
      } catch (e) {
        logE(`[StickerClock] listener threw: ${JSON.stringify(e)}`);
      }
    }
  };

  // 订阅。返回退订函数，重复调用无副作用。
  subscribe(ui: UIContext, fps: number, listener: StickerFrameListener): () => void {
    const id: number = this.nextId++;
    this.entries.set(id, { fps: fps, listener: listener });
    // 官方：期望帧率建议在 start 之前设，才能立即生效。
    this.applyRange();
    if (!this.running) {
      this.start(ui);
    }
    let active: boolean = true;
    return (): void => {
      if (!active) {
        return;
      }
      active = false;
      this.entries.delete(id);
      if (this.entries.size === 0) {
        this.stop();
      } else {
        this.applyRange();
      }
    };
  }

  private ensureSync(): displaySync.DisplaySync {
    if (this.sync === null) {
      const created: displaySync.DisplaySync = displaySync.create();
      created.on('frame', this.onFrame);
      this.sync = created;
    }
    return this.sync;
  }

  private applyRange(): void {
    const fpsList: number[] = [];
    this.entries.forEach((entry: ClockEntry): void => { fpsList.push(entry.fps); });
    const r: TgsRateRange = tgsClockRange(fpsList);
    if (r.expected <= 0 || r.expected === this.appliedExpected) {
      return;
    }
    try {
      const range: ExpectedFrameRateRange = { expected: r.expected, min: r.min, max: r.max };
      this.ensureSync().setExpectedFrameRateRange(range);
      this.appliedExpected = r.expected;
    } catch (e) {
      // 401：范围越界（设备最大帧率低于期望等）。不设也能跑，只是跟随应用当前帧率。
      logE(`[StickerClock] setExpectedFrameRateRange(${r.expected}) failed: ${JSON.stringify(e)}`);
    }
  }

  private start(ui: UIContext): void {
    const sync: displaySync.DisplaySync = this.ensureSync();
    this.running = true;
    try {
      ui.runScopedTask((): void => {
        sync.start();
      });
    } catch (e) {
      this.running = false;
      logE(`[StickerClock] start failed: ${JSON.stringify(e)}`);
    }
  }

  private stop(): void {
    if (!this.running || this.sync === null) {
      return;
    }
    this.running = false;
    try {
      this.sync.stop();
    } catch (e) {
      logE(`[StickerClock] stop failed: ${JSON.stringify(e)}`);
    }
  }
}

export const stickerFrameClock: StickerFrameClock = new StickerFrameClock();
