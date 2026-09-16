import { image } from '@kit.ImageKit';
import nativeTgs from 'libentry.so';

// 所有对原生 TGS 的调用排成一条队。
//
// 【为什么必须有这条队】原生侧的 rlottie 调用全在自己那一条线程上跑
// （cpp/tgs_render.cpp 里的 RenderThread，起因见那里的崩溃说明），而调用方是
// napi 的 async work——它跑在 **FFRT 线程池**上，会在那里**阻塞等结果**。
// 同屏五张贴纸各自 30fps 地要帧，就是五个 FFRT worker 同时被我们占住；而那个
// 池子是全应用共用的（TDLib 回包、图片解码、文件 IO 都在上面排队）。占满了
// 表现出来不是"贴纸慢"，而是**整个界面卡**。
//
// 排成一条之后，任何时刻最多一个 worker 被占住。代价是各视图的帧互相排队——
// 但反正原生那头本来就是串行的，排在这边还是那边总时长一样，区别只是"堵在
// 我们自己的队列里"还是"堵在系统的线程池里"。
//
// 【可取消】（2026-09-15）排进队的请求原来一定会执行：格子滑出屏幕、暂停、换了贴纸之后，
// 已经排着的帧照样去调 native，回来才丢掉——trace 里 515 次 tgsRenderFrame 平均 7ms，
// 120 次等了超过一帧。现在请求可以带一张票，真正轮到执行前先看票有没有作废，作废的直接
// 跳过。一个视图同一时刻最多只有一帧在途（见 TgsNativeStickerView.pump 的 rendering），
// 所以"只保留最新帧号"已经天然成立，要补的只是取消。
let chain: Promise<void> = Promise.resolve();

function enqueue<T>(job: () => Promise<T>): Promise<T> {
  const run: Promise<T> = chain.then(job);
  // 链条不能因为某一次失败断掉，否则后面的永远排不进来。
  chain = run.then((): void => {}, (): void => {});
  return run;
}

export interface TgsOpenResult {
  handle: number;
  totalFrames: number;
  frameRate: number;
  width: number;
  height: number;
}

// 调用方持有；不再需要这次请求时把 cancelled 置 true。
export class TgsRenderTicket {
  cancelled: boolean = false;
}

export interface TgsOpenOutcome {
  info: TgsOpenResult | null;
  // 轮到执行时票已作废，根本没去调 native——不是失败。
  skipped: boolean;
}

export interface TgsRenderResult {
  frame: image.PixelMap | null;
  skipped: boolean;
}

export function queueTgsOpenTicketed(path: string, width: number, height: number,
  ticket?: TgsRenderTicket): Promise<TgsOpenOutcome> {
  return enqueue(async (): Promise<TgsOpenOutcome> => {
    if (ticket !== undefined && ticket.cancelled) {
      return { info: null, skipped: true };
    }
    const info: TgsOpenResult | null = await nativeTgs.tgsOpen(path, width, height);
    return { info: info, skipped: false };
  });
}

export function queueTgsRenderTicketed(handle: number, frameIndex: number,
  ticket?: TgsRenderTicket): Promise<TgsRenderResult> {
  return enqueue(async (): Promise<TgsRenderResult> => {
    if (ticket !== undefined && ticket.cancelled) {
      return { frame: null, skipped: true };
    }
    const frame: image.PixelMap | null = await nativeTgs.tgsRenderFrame(handle, frameIndex);
    return { frame: frame, skipped: false };
  });
}

export function queueTgsOpen(path: string, width: number, height: number): Promise<TgsOpenResult | null> {
  return queueTgsOpenTicketed(path, width, height).then((outcome: TgsOpenOutcome): TgsOpenResult | null => outcome.info);
}

export function queueTgsRender(handle: number, frameIndex: number): Promise<image.PixelMap | null> {
  return queueTgsRenderTicketed(handle, frameIndex).then((result: TgsRenderResult): image.PixelMap | null => result.frame);
}

// 关闭是同步的、不进队：它只是从 map 里摘一条，不碰渲染线程。
export function tgsClose(handle: number): void {
  nativeTgs.tgsClose(handle);
}
