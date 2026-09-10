import { TdClient } from '../tdkit/TdClient';
import { TdError, TdRequest } from '../tdkit/TdTypes';
import { VIDEO_HEAD_PREFETCH_PRIORITY } from '../util/downloadPriority';
import {
  MAX_CONCURRENT_VIDEO_PREFETCH, VIDEO_PREFETCH_DWELL_MS, VideoPrefetchRange, prefetchRanges,
  prefetchRefusalReason
} from '../util/videoPrefetchPolicy';
import { logW } from '../util/log';

// 视频气泡"出现即缓冲第一块、划走即暂停"的驱动件。
//
// 【信号从哪来】气泡现成的 onMediaRatio(messageId, albumIndex, ratio, centerY) /
// onMediaGone(messageId, albumIndex)——ChatPage 把它们同时喂给 PlaySlotDriver 和
// 本类，各取所需。相册每一格独立上报，所以"图片+视频+文字"的相册里只有视频格
// 会触发下载（非视频的格 videoAt 返回 null，直接忽略）。
//
// 【判据全在 util/videoPrefetchPolicy】本类只做记账：谁可见、谁在下、谁排队。
//
// 【头、尾必须串行】TDLib 对同一个文件**只保留一组 offset/limit**：再发一个
// downloadFile 就把上一个顶掉。第一版并发发了头（20MB）和尾（1MB），结果只下了
// 尾巴（2026-09-09 真机）。VideoStreamSession 把分片一个个 synchronous 发也是这个
// 原因。所以头块用 synchronous:true，应答回来（= 头块已落地）再发尾块；期间文件
// 若被释放或换代（chainSeq 变了），尾块不发。
//
// 【暂停 = cancelDownloadFile(only_if_pending=false)】不删已下的部分；回来再发
// 同一段就是断点续传。**但 suspend() 不取消**：它走的是查看器打开 / 页面隐藏那条
// 路，而查看器自己的流式下载（VideoStreamSession）不经过 MessageStore 的归属集合
// ——第一版在这里取消，把用户刚点开的那条视频掐断了（日志：每次 pause 之后
// 1~2s 就是 StreamingVideoPlayer error -10000 / Network is down）。预取本身有上限，
// 让它自己收尾没有代价。
//
// 【驻留 400ms 再开】快速滑动时气泡进出视口只有几百毫秒，第一版在日志里全是
// "start → 1s 后 pause"。停够 VIDEO_PREFETCH_DWELL_MS 再发，划走时把驻留计时取消。
//
// 【和播放器互不相扰】被认领的文件既不发也不取消，认领状态每次动作时现查；
// ChatPage 的 fileClaimed 还把查看器当前那条的视频文件算作已认领。
//
// 【与 ChatPage 的边界】本类不知道 MessageEntry、不知道会话类型、不读 AppStorage，
// 全部经 host 取——单测用一个 FakeHost 就能覆盖全部分支。
export interface VideoRef {
  fileId: number;
  fileSize: number;   // 0 = 未知
  local: boolean;     // 整份已在本地
}

export interface VideoPrefetchHost {
  client: () => TdClient;
  // (messageId, albumIndex) → 这一格的视频；不是视频给 null。
  videoAt: (messageId: number, albumIndex: number) => VideoRef | null;
  fileClaimed: (fileId: number) => boolean;
  network: () => string;
  powerSaving: () => boolean;
}

// 头块是 synchronous 请求，蜂窝下 20MB 可能要下一阵子；超时只是本地不再等应答，
// TDLib 那边照下不误，代价只是尾块不发。
const HEAD_REQUEST_TIMEOUT_MS: number = 120_000;

function keyOf(messageId: number, albumIndex: number): string {
  return `${messageId}:${albumIndex}`;
}

export class VideoHeadPrefetcher {
  private host: VideoPrefetchHost | null = null;
  private dwellMs: number = VIDEO_PREFETCH_DWELL_MS;
  // 可见的格 → 文件。同一个文件可能被多格引用（理论上），所以下面再做一层计数。
  private visible: Map<string, number> = new Map();
  private refs: Map<number, Set<string>> = new Map();
  // 驻留计时：格 → timer。到点还在可见表里才真的开。
  private dwellTimers: Map<string, number> = new Map();
  // 在途预取。
  private active: Set<number> = new Set();
  // 每个文件的"代次"：释放/暂停后 +1，让还没回来的头块应答不再发尾块。
  private chainSeq: Map<number, number> = new Map();
  // 超过并发上限的排队（FIFO、不重复）。
  private queue: number[] = [];
  private suspended: boolean = false;
  private disposed: boolean = false;
  private skipLogged: boolean = false;

  bind(host: VideoPrefetchHost, dwellMs: number = VIDEO_PREFETCH_DWELL_MS): void {
    this.host = host;
    this.dwellMs = Math.max(0, dwellMs);
  }

  activeCount(): number {
    return this.active.size;
  }

  reportMedia(messageId: number, albumIndex: number, ratio: number): void {
    if (this.disposed || this.host === null) {
      return;
    }
    if (ratio <= 0) {
      this.dropMedia(messageId, albumIndex);
      return;
    }
    const key: string = keyOf(messageId, albumIndex);
    if (this.visible.has(key)) {
      return;
    }
    const ref: VideoRef | null = this.host.videoAt(messageId, albumIndex);
    if (ref === null || ref.fileId === 0) {
      // 不是视频是常态（图片格、文字气泡也在报），不打；只在排查"没感觉被预取"
      // 时需要知道信号到底走没走到这里——打一次即可。
      if (!this.skipLogged) {
        this.skipLogged = true;
        logW(`[VideoPrefetch] signal alive; first non-video key=${key}`);
      }
      return;
    }
    this.visible.set(key, ref.fileId);
    let holders: Set<string> | undefined = this.refs.get(ref.fileId);
    if (holders === undefined) {
      holders = new Set();
      this.refs.set(ref.fileId, holders);
    }
    holders.add(key);
    if (this.suspended) {
      return;
    }
    if (this.dwellMs === 0) {
      this.tryStart(ref);
      return;
    }
    const timer: number = setTimeout((): void => {
      this.dwellTimers.delete(key);
      if (this.disposed || this.suspended || !this.visible.has(key)) {
        return;
      }
      this.tryStart(ref);
    }, this.dwellMs);
    this.dwellTimers.set(key, timer);
  }

  dropMedia(messageId: number, albumIndex: number): void {
    const key: string = keyOf(messageId, albumIndex);
    const timer: number | undefined = this.dwellTimers.get(key);
    if (timer !== undefined) {
      clearTimeout(timer);
      this.dwellTimers.delete(key);
    }
    const fileId: number | undefined = this.visible.get(key);
    if (fileId === undefined) {
      return;
    }
    this.visible.delete(key);
    const holders: Set<string> | undefined = this.refs.get(fileId);
    if (holders !== undefined) {
      holders.delete(key);
      if (holders.size > 0) {
        return;
      }
      this.refs.delete(fileId);
    }
    this.release(fileId, true);
    this.pumpQueue();
  }

  // 页面隐藏 / 查看器打开：不再开新的，在途的**不取消**（理由见文件头），
  // 可见表留着——回来按它重发。
  suspend(): void {
    this.suspended = true;
    this.clearDwellTimers();
    const inflight: number[] = Array.from(this.active);
    this.active.clear();
    this.queue = [];
    for (const fileId of inflight) {
      this.bumpSeq(fileId);
    }
  }

  resume(): void {
    if (this.disposed || this.host === null) {
      return;
    }
    this.suspended = false;
    const seen: Set<number> = new Set();
    this.visible.forEach((fileId: number, key: string): void => {
      if (seen.has(fileId)) {
        return;
      }
      seen.add(fileId);
      const parts: string[] = key.split(':');
      const ref: VideoRef | null = this.host!.videoAt(Number(parts[0]), Number(parts[1]));
      if (ref !== null) {
        this.tryStart(ref);
      }
    });
  }

  // 页面销毁：没被认领的在途预取取消掉（这里没有查看器要保护）。
  dispose(): void {
    this.clearDwellTimers();
    const inflight: number[] = Array.from(this.active);
    this.suspend();
    for (const fileId of inflight) {
      this.cancelUnlessClaimed(fileId);
    }
    this.visible.clear();
    this.refs.clear();
    this.disposed = true;
  }

  private clearDwellTimers(): void {
    this.dwellTimers.forEach((timer: number): void => { clearTimeout(timer); });
    this.dwellTimers.clear();
  }

  private bumpSeq(fileId: number): number {
    const next: number = (this.chainSeq.get(fileId) ?? 0) + 1;
    this.chainSeq.set(fileId, next);
    return next;
  }

  private tryStart(ref: VideoRef): void {
    if (this.host === null || this.active.has(ref.fileId) || this.queue.indexOf(ref.fileId) >= 0) {
      return;
    }
    const reason: string = prefetchRefusalReason({
      network: this.host.network(),
      powerSaving: this.host.powerSaving(),
      alreadyLocal: ref.local,
      fileClaimed: this.host.fileClaimed(ref.fileId),
      fileId: ref.fileId
    });
    if (reason !== '') {
      // 'local' 是常态（看过的视频），不打；其余原因都值得留痕。
      if (reason !== 'local') {
        logW(`[VideoPrefetch] refuse file=${ref.fileId} reason=${reason}`);
      }
      return;
    }
    if (this.active.size >= MAX_CONCURRENT_VIDEO_PREFETCH) {
      logW(`[VideoPrefetch] queue file=${ref.fileId} active=${this.active.size}`);
      this.queue.push(ref.fileId);
      return;
    }
    this.start(ref);
  }

  private start(ref: VideoRef): void {
    if (this.host === null) {
      return;
    }
    this.active.add(ref.fileId);
    const seq: number = this.bumpSeq(ref.fileId);
    const ranges: VideoPrefetchRange[] = prefetchRanges(ref.fileSize);
    logW(`[VideoPrefetch] start file=${ref.fileId} size=${ref.fileSize}` +
      ` ranges=${ranges.map((r: VideoPrefetchRange): string => `${r.offset}+${r.limit}`).join(',')}` +
      ` active=${this.active.size}`);
    this.issueRange(ref.fileId, ranges, 0, seq);
  }

  // 一块一块发：同一文件 TDLib 只保留一组 offset/limit，并发发就是互相顶掉。
  private issueRange(fileId: number, ranges: VideoPrefetchRange[], index: number, seq: number): void {
    if (this.host === null || index >= ranges.length) {
      return;
    }
    const r: VideoPrefetchRange = ranges[index];
    const req: TdRequest = { '@type': 'downloadFile' };
    req['file_id'] = fileId;
    req['priority'] = VIDEO_HEAD_PREFETCH_PRIORITY;
    req['offset'] = r.offset;
    req['limit'] = r.limit;
    // synchronous：应答 = 这一块已落地。要的就是这个时刻，好接着发下一块。
    req['synchronous'] = true;
    this.host.client().send(req, HEAD_REQUEST_TIMEOUT_MS).then((): void => {
      // 期间被释放/暂停过（代次变了）或已不在途：不发下一块。
      if (this.chainSeq.get(fileId) !== seq || !this.active.has(fileId)) {
        return;
      }
      if (index + 1 < ranges.length) {
        logW(`[VideoPrefetch] tail file=${fileId} offset=${ranges[index + 1].offset}`);
        this.issueRange(fileId, ranges, index + 1, seq);
      }
    }).catch((e: TdError): void => {
      logW(`VideoHeadPrefetcher.downloadFile ${fileId}@${r.offset}+${r.limit} failed: ${e.message}`);
    });
  }

  private release(fileId: number, cancel: boolean): void {
    const qi: number = this.queue.indexOf(fileId);
    if (qi >= 0) {
      this.queue.splice(qi, 1);
    }
    if (!this.active.has(fileId)) {
      return;
    }
    this.active.delete(fileId);
    this.bumpSeq(fileId);
    if (cancel) {
      this.cancelUnlessClaimed(fileId);
    }
  }

  private cancelUnlessClaimed(fileId: number): void {
    if (this.host === null || this.host.fileClaimed(fileId)) {
      return;
    }
    logW(`[VideoPrefetch] pause file=${fileId}`);
    const req: TdRequest = { '@type': 'cancelDownloadFile' };
    req['file_id'] = fileId;
    req['only_if_pending'] = false;
    this.host.client().send(req).catch((e: TdError): void => {
      logW(`VideoHeadPrefetcher.cancelDownloadFile ${fileId} failed: ${e.message}`);
    });
  }

  private pumpQueue(): void {
    if (this.host === null || this.suspended) {
      return;
    }
    while (this.active.size < MAX_CONCURRENT_VIDEO_PREFETCH && this.queue.length > 0) {
      const fileId: number = this.queue.shift() as number;
      // 排队期间它可能已经划走（refs 空）——那就不发了。
      const holders: Set<string> | undefined = this.refs.get(fileId);
      if (holders === undefined || holders.size === 0) {
        continue;
      }
      const anyKey: string = Array.from(holders)[0];
      const parts: string[] = anyKey.split(':');
      const ref: VideoRef | null = this.host.videoAt(Number(parts[0]), Number(parts[1]));
      if (ref === null) {
        continue;
      }
      this.start(ref);
    }
  }
}
