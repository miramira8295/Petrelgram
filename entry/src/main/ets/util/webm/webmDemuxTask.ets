import { taskpool } from '@kit.ArkTS';
import { demuxWebmAlpha, WebmAlphaClip, WebmAlphaFrame } from './WebmAlphaDemuxer';
import { logE } from '../log';

// WebM 拆包挪到 TaskPool（2026-09-15，扫描报告 P2）。
//
// 拆包是纯 ArkTS 的 EBML 解析，原来在 AlphaStickerStore 里直接跑在主线程上——`await` 只让出
// 调用栈、不离开线程（pixelDecodeTask 的文件头有设备实测）。单个贴纸几十 KB、一次不算重，
// 但贴纸抽屉一滑就是一串。
//
// 【跨线程边界】拆出来的帧里的 Uint8Array 原本是整份文件 buffer 的视图；直接回传，序列化时有
// 按整块 buffer 反复拷贝的风险。所以在 worker 里就把每帧拷成独立的小块——总量就是文件本身
// 那么大。文件字节先复制一份再**转移**过去：失败时还能用原来那份在主线程上兜底拆一次。
@Concurrent
function demuxCompactTask(buffer: ArrayBuffer, length: number): WebmAlphaClip | null {
  const clip: WebmAlphaClip | null = demuxWebmAlpha(new Uint8Array(buffer, 0, length));
  if (clip === null) {
    return null;
  }
  const frames: WebmAlphaFrame[] = clip.frames.map((f: WebmAlphaFrame): WebmAlphaFrame => ({
    timeMs: f.timeMs,
    color: f.color.slice(),
    alpha: f.alpha !== null ? f.alpha.slice() : null
  }));
  return { track: clip.track, frames: frames, durationMs: clip.durationMs };
}

export async function demuxWebmAlphaOffThread(bytes: Uint8Array): Promise<WebmAlphaClip | null> {
  try {
    const copy: ArrayBuffer = bytes.slice().buffer as ArrayBuffer;
    const task: taskpool.Task = new taskpool.Task(demuxCompactTask, copy, bytes.byteLength);
    task.setTransferList([copy]);
    return await taskpool.execute(task) as WebmAlphaClip | null;
  } catch (e) {
    logE(`webmDemuxTask failed, demuxing on the calling thread: ${e}`);
    return demuxWebmAlpha(bytes);
  }
}
