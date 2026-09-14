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

export function queueTgsOpen(path: string, width: number, height: number): Promise<TgsOpenResult | null> {
  return enqueue((): Promise<TgsOpenResult | null> => nativeTgs.tgsOpen(path, width, height));
}

export function queueTgsRender(handle: number, frameIndex: number): Promise<image.PixelMap | null> {
  return enqueue((): Promise<image.PixelMap | null> => nativeTgs.tgsRenderFrame(handle, frameIndex));
}

// 关闭是同步的、不进队：它只是从 map 里摘一条，不碰渲染线程。
export function tgsClose(handle: number): void {
  nativeTgs.tgsClose(handle);
}
