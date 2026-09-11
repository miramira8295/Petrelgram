import fileIo from '@ohos.file.fs';
import { TdClient } from '../tdkit/TdClient';
import { TdObject, TdRequest, TdError } from '../tdkit/TdTypes';
import { logE, logW } from '../util/log';

const STREAM_PRIORITY: number = 32;
const CHUNK_SIZE: number = 1024 * 1024;
const LOW_WATER_BYTES: number = 2 * CHUNK_SIZE;
// **导出**给 util/videoPrefetchPolicy：start() 起手就 ensureRange(0, HIGH_WATER)，
// 预取的头块对齐到它，起播的整个请求集才都命中本地。
export const HIGH_WATER_BYTES: number = 6 * CHUNK_SIZE;
// **导出**给 util/videoPrefetchPolicy：气泡出现时预取的就是这两块，两边必须
// 是同一个数——复制一份早晚漂移，漂了预取就白做。
export const PREPARE_HEAD_BYTES: number = 2 * CHUNK_SIZE;
export const PREPARE_TAIL_BYTES: number = CHUNK_SIZE;
// 一次 downloadFile 的 limit 上限。
//
// 【为什么必须远大于 CHUNK_SIZE —— 2026-09-11 读 TDLib 源码得出】
// TDLib 的 PartsManager.get_estimated_extra() 在流式模式下**用 streaming_limit_
// （就是我们传的 limit）给向 ResourceManager 的申请量封顶**
// （PartsManager.cpp:425-450 → ResourceManager.cpp:103-120）。而它的分片是
// 64KB（250MB 以内的文件，PartsManager.cpp:132-135），在飞预算是 2MB
// （FileDownloadManager.h:70）。
//   limit = 1MB  ⇒ 在飞最多 16 片，**池子只用了一半**
//   limit ≥ 2MB  ⇒ 不再被 limit 卡住，能吃满 32 片
// 取 HIGH_WATER_BYTES：那本来就是"我们想缓冲到多远"，一次要到位，别让 TDLib
// 下完 1MB 就空转等我们发下一个。
const STREAM_REQUEST_LIMIT_BYTES: number = HIGH_WATER_BYTES;
const STREAM_REQUEST_TIMEOUT_MS: number = 60000;
const MAX_REQUEST_RETRIES: number = 5;

interface ByteRange {
  start: number;
  end: number;
}

export type VideoStreamProgressListener = (buffered: number, total: number) => void;

export class VideoStreamSession {
  private client: TdClient;
  private fileId: number;
  private totalSize: number;
  private localPath: string = '';
  private ranges: ByteRange[] = [];
  private pendingStarts: Set<number> = new Set();
  private requestQueue: number[] = [];
  private requestLengths: Map<number, number> = new Map();
  private requestAttempts: Map<number, number> = new Map();
  private activeStart: number = -1;
  // 当前在途请求覆盖到哪（抢占判据用）。
  private activeEnd: number = -1;
  // 抢占计数：seek 之后旧请求的回调要认得出自己已经作废。
  private requestSeq: number = 0;
  private closed: boolean = false;
  private readHead: number = 0;
  private prefetching: boolean = false;
  private progressListeners: VideoStreamProgressListener[] = [];
  private unsubFile: (() => void) | null = null;

  constructor(client: TdClient, fileId: number, totalSize: number) {
    this.client = client;
    this.fileId = fileId;
    this.totalSize = totalSize;
    this.unsubFile = this.client.onUpdate('updateFile', (u: TdObject) => this.onFileUpdate(u));
  }

  subscribeProgress(l: VideoStreamProgressListener): () => void {
    this.progressListeners = [...this.progressListeners, l];
    l(this.bufferedFrom(0), this.totalSize);
    return (): void => {
      this.progressListeners = this.progressListeners.filter((x: VideoStreamProgressListener) => x !== l);
    };
  }

  start(): void {
    this.ensurePrepareRanges();
    this.ensureRange(0, HIGH_WATER_BYTES);
    this.pumpPrefetch();
  }

  async waitForReady(timeoutMs: number): Promise<boolean> {
    const headBytes = this.totalSize > 0 ? Math.min(PREPARE_HEAD_BYTES, this.totalSize) : PREPARE_HEAD_BYTES;
    const headReady = await this.waitForBuffered(0, headBytes, timeoutMs);
    if (!headReady || this.totalSize <= PREPARE_HEAD_BYTES) {
      return headReady;
    }
    const tailBytes = Math.min(PREPARE_TAIL_BYTES, this.totalSize);
    const tailOffset = Math.max(0, this.totalSize - tailBytes);
    return this.waitForBuffered(tailOffset, tailBytes, timeoutMs);
  }

  waitForBuffered(offset: number, minBytes: number, timeoutMs: number): Promise<boolean> {
    if (this.hasRange(offset, minBytes)) {
      return Promise.resolve(true);
    }
    return new Promise<boolean>((resolve) => {
      let done = false;
      let unsub: () => void = (): void => {};
      const finish = (ok: boolean): void => {
        if (done) {
          return;
        }
        done = true;
        unsub();
        resolve(ok);
      };
      unsub = this.subscribeProgress(() => {
        if (this.hasRange(offset, minBytes)) {
          finish(true);
        }
      });
      setTimeout(() => finish(this.hasRange(offset, minBytes)), timeoutMs);
    });
  }

  close(): void {
    this.closed = true;
    if (this.unsubFile !== null) {
      this.unsubFile();
      this.unsubFile = null;
    }
    this.progressListeners = [];
  }

  fileSizeForPlayer(): number {
    return this.totalSize > 0 ? this.totalSize : -1;
  }

  async readRange(offset: number, length: number, timeoutMs: number): Promise<ArrayBuffer | null> {
    if (this.closed) {
      return null;
    }
    const wanted = this.clampLength(offset, length);
    if (wanted <= 0) {
      return new ArrayBuffer(0);
    }
    this.readHead = offset + wanted;
    this.ensureRange(offset, wanted, true);
    // 首次打开时存在多个瞬时竞态：TDLib 可能先报告已缓冲字节、稍后才给出
    // 本地文件路径；写盘也可能略滞后于范围上报，导致短读。这些都不是真正的
    // 失败——在截止时间内重试，否则一次瞬时 null 会让 serve 直接断流，
    // 表现为"视频第一次点开概率性加载失败"。
    const deadline: number = Date.now() + timeoutMs;
    let attempt: number = 0;
    while (!this.closed) {
      const remaining: number = deadline - Date.now();
      if (remaining <= 0) {
        return null;
      }
      if (!await this.waitForBuffered(offset, wanted, remaining)) {
        return null;
      }
      if (this.localPath !== '') {
        try {
          const buffer = new ArrayBuffer(wanted);
          const fd = fileIo.openSync(this.localPath, fileIo.OpenMode.READ_ONLY).fd;
          const readBytes = fileIo.readSync(fd, buffer, { offset, length: wanted });
          fileIo.closeSync(fd);
          if (readBytes === wanted) {
            this.keepAhead(offset + readBytes);
            return buffer;
          }
        } catch (e) {
          // 文件刚被 TDLib 创建/截断时可能瞬时打开失败，同样重试。
          logW(`VideoStreamSession.readRange retry(${attempt}): ${e}`);
        }
      }
      attempt++;
      if (attempt > 40) {
        return null;
      }
      await new Promise<void>((resolve: (v: void) => void): void => {
        setTimeout((): void => resolve(), 50);
      });
    }
    return null;
  }

  read(buffer: ArrayBuffer, length: number, pos?: number): number {
    if (this.closed) {
      return -2;
    }
    const offset = pos !== undefined ? pos : this.readHead;
    this.readHead = Math.max(this.readHead, offset + Math.max(0, length));
    this.keepAhead(offset);
    const wanted = this.clampLength(offset, length);
    if (wanted <= 0) {
      return -1;
    }
    if (this.localPath === '') {
      this.ensureRange(offset, Math.max(wanted, CHUNK_SIZE), true);
      return 0;
    }
    const buffered = this.bufferedFrom(offset);
    if (buffered <= 0) {
      this.ensureRange(offset, Math.max(wanted, CHUNK_SIZE), true);
      return 0;
    }
    try {
      const fd = fileIo.openSync(this.localPath, fileIo.OpenMode.READ_ONLY).fd;
      const readable = Math.min(wanted, buffered);
      const readBytes = fileIo.readSync(fd, buffer, { offset, length: readable });
      fileIo.closeSync(fd);
      this.keepAhead(offset + readBytes);
      return readBytes;
    } catch (e) {
      logE(`VideoStreamSession.read failed: ${e}`);
      return -2;
    }
  }

  ensureRange(offset: number, length: number, urgent: boolean = false): void {
    if (this.closed || this.fileId === 0 || length <= 0) {
      return;
    }
    const start = Math.max(0, Math.floor(offset / CHUNK_SIZE) * CHUNK_SIZE);
    const end = this.limitEnd(start + Math.max(length, CHUNK_SIZE));
    let cur = start;
    while (cur < end) {
      const next = this.limitEnd(cur + CHUNK_SIZE);
      if (!this.hasRange(cur, next - cur) && !this.pendingStarts.has(cur)) {
        this.requestChunk(cur, next - cur, urgent);
      }
      cur = next;
    }
  }

  private keepAhead(offset: number): void {
    this.ensureRange(offset, LOW_WATER_BYTES);
    const buffered = this.bufferedFrom(offset);
    if (buffered < LOW_WATER_BYTES) {
      this.ensureRange(offset + buffered, HIGH_WATER_BYTES - buffered);
    }
  }

  private ensurePrepareRanges(): void {
    this.ensureRange(0, PREPARE_HEAD_BYTES);
    if (this.totalSize > PREPARE_HEAD_BYTES) {
      const tailBytes = Math.min(PREPARE_TAIL_BYTES, this.totalSize);
      const tailOffset = Math.max(0, this.totalSize - tailBytes);
      this.ensureRange(tailOffset, tailBytes);
    }
  }

  private pumpPrefetch(): void {
    if (this.closed || this.prefetching) {
      return;
    }
    this.prefetching = true;
    const tick = (): void => {
      this.prefetching = false;
      if (this.closed) {
        return;
      }
      const buffered = this.bufferedFrom(this.readHead);
      if (buffered < HIGH_WATER_BYTES) {
        this.ensureRange(this.readHead + buffered, HIGH_WATER_BYTES - buffered);
      }
      setTimeout(() => this.pumpPrefetch(), 700);
    };
    setTimeout(tick, 700);
  }

  private requestChunk(offset: number, length: number, urgent: boolean = false): void {
    if (this.closed || length <= 0) {
      return;
    }
    if (this.pendingStarts.has(offset)) {
      const prev = this.requestLengths.get(offset) ?? 0;
      if (length > prev) {
        this.requestLengths.set(offset, length);
      }
      return;
    }
    this.pendingStarts.add(offset);
    this.requestLengths.set(offset, length);
    if (urgent) {
      this.requestQueue.unshift(offset);
      this.preemptIfOutsideWindow(offset);
    } else {
      this.requestQueue.push(offset);
    }
    this.pumpQueue();
  }

  // seek / 读未命中时抢占当前在途请求。
  //
  // TDLib 对同一文件只保留一组 offset/limit，发一个新的即取代旧的——td_api 自己
  // 写明 synchronous 请求会在"收到 offset/limit 不同的新请求"时结束。所以抢占
  // 不需要先 cancelDownloadFile（那会真的停掉下载），也不会丢已下好的分片：
  // 已完成的分片记在 PartialLocalFileLocation 的 bitmask 里，跨 offset 变更保留
  // （FileDownloader.cpp:458-476 只取消"窗口外仍在飞"的请求）。
  //
  // 【为什么非有不可】limit 放大到 6MB 之后，一个在途请求可能要跑好几秒。原来
  // pumpQueue 在 activeStart >= 0 时一律早退，seek 就得排在它后面——窗口越大越
  // 难受。现在落在当前窗口内的等它，落在窗口外的立刻取代。
  private preemptIfOutsideWindow(offset: number): void {
    if (this.activeStart < 0) {
      return;
    }
    if (offset >= this.activeStart && offset < this.activeEnd) {
      return;
    }
    this.requestSeq++;
    this.activeStart = -1;
    this.activeEnd = -1;
  }

  private pumpQueue(): void {
    if (this.closed || this.activeStart >= 0) {
      return;
    }
    // 窗口放大之后一次请求常常顺手把后面几块也带下来了，把已到手的从队首丢掉。
    while (this.requestQueue.length > 0) {
      const head: number = this.requestQueue[0];
      const headLen: number = this.requestLengths.get(head) ?? 0;
      if (headLen > 0 && !this.hasRange(head, headLen)) {
        break;
      }
      this.requestQueue.shift();
      this.pendingStarts.delete(head);
      this.requestLengths.delete(head);
      this.requestAttempts.delete(head);
    }
    if (this.requestQueue.length === 0) {
      return;
    }
    const offset = this.requestQueue.shift() as number;
    const chunkLength = this.requestLengths.get(offset) ?? 0;
    // 记账仍按 1MB 一块（对齐细、seek 时少重下），但**请求本身要到 6MB**，
    // 理由见 STREAM_REQUEST_LIMIT_BYTES。
    const length = Math.max(chunkLength,
      this.limitEnd(offset + STREAM_REQUEST_LIMIT_BYTES) - offset);
    const seq: number = this.requestSeq;
    this.activeStart = offset;
    this.activeEnd = offset + length;
    const req: TdRequest = { '@type': 'downloadFile' };
    req['file_id'] = this.fileId;
    req['priority'] = STREAM_PRIORITY;
    req['offset'] = offset;
    req['limit'] = length;
    req['synchronous'] = true;
    this.client.send(req, STREAM_REQUEST_TIMEOUT_MS).then((f: TdObject) => {
      this.pendingStarts.delete(offset);
      this.requestLengths.delete(offset);
      this.requestAttempts.delete(offset);
      // **不再盲目 addRange(offset, offset+length)**：请求被 seek 取代时它照样
      // 会结束，那时窗口里多半只下了一部分，标满就是骗自己。真实到手的字节由
      // applyFile 从 downloaded_prefix_size 增量推进（起播就绪判据本来也只看它）。
      this.applyFile(f);
      if (seq !== this.requestSeq) {
        return;   // 已被抢占：新请求自己会推进队列
      }
      this.activeStart = -1;
      this.activeEnd = -1;
      this.pumpQueue();
    }).catch((e: TdError) => {
      if (seq !== this.requestSeq) {
        this.pendingStarts.delete(offset);
        this.requestLengths.delete(offset);
        this.requestAttempts.delete(offset);
        return;
      }
      this.activeStart = -1;
      this.activeEnd = -1;
      if (this.closed) {
        this.pendingStarts.delete(offset);
        this.requestLengths.delete(offset);
        this.requestAttempts.delete(offset);
        return;
      }
      const attempt = (this.requestAttempts.get(offset) ?? 0) + 1;
      if (attempt <= MAX_REQUEST_RETRIES) {
        this.requestAttempts.set(offset, attempt);
        const delayMs = Math.min(4000, 300 * Math.pow(2, attempt - 1));
        logW(`VideoStreamSession.download ${this.fileId}@${offset}+${length} retry ${attempt}: ${e.message}`);
        setTimeout(() => {
          if (this.closed) {
            return;
          }
          this.requestQueue.unshift(offset);
          this.pumpQueue();
        }, delayMs);
        this.pumpQueue();
        return;
      }
      this.pendingStarts.delete(offset);
      this.requestLengths.delete(offset);
      this.requestAttempts.delete(offset);
      logE(`VideoStreamSession.download ${this.fileId}@${offset}+${length} failed after retries: ${e.message}`);
      this.pumpQueue();
    });
  }

  private onFileUpdate(update: TdObject): void {
    const f = update['file'] as TdObject | undefined;
    if (f !== undefined) {
      this.applyFile(f);
    }
  }

  private applyFile(file: TdObject): void {
    const id = file['id'] as number | undefined;
    if (id !== this.fileId) {
      return;
    }
    if (this.totalSize <= 0) {
      this.totalSize = ((file['size'] as number | undefined) ?? 0) || ((file['expected_size'] as number | undefined) ?? 0);
    }
    const local = file['local'] as TdObject | undefined;
    if (local === undefined) {
      return;
    }
    const path = (local['path'] as string | undefined) ?? '';
    if (path !== '') {
      this.localPath = path;
    }
    const downloadOffset = (local['download_offset'] as number | undefined) ?? 0;
    const prefix = (local['downloaded_prefix_size'] as number | undefined) ?? 0;
    if (prefix > 0) {
      this.addRange(downloadOffset, downloadOffset + prefix);
    }
    const downloaded = (local['downloaded_size'] as number | undefined) ?? 0;
    const done = (local['is_downloading_completed'] as boolean | undefined) ?? false;
    if (done && this.totalSize > 0) {
      this.addRange(0, this.totalSize);
    } else if (downloaded > 0 && prefix <= 0 && downloadOffset === 0 && this.ranges.length === 0) {
      // Older TDLib payloads may omit downloaded_prefix_size for a regular
      // contiguous download from byte zero.
      this.addRange(0, downloaded);
    }
  }

  private addRange(start: number, end: number): void {
    if (end <= start) {
      return;
    }
    const range: ByteRange = { start, end: this.limitEnd(end) };
    const merged: ByteRange[] = [];
    let inserted = false;
    for (const r of this.ranges) {
      if (r.end < range.start) {
        merged.push(r);
      } else if (range.end < r.start) {
        if (!inserted) {
          merged.push(range);
          inserted = true;
        }
        merged.push(r);
      } else {
        range.start = Math.min(range.start, r.start);
        range.end = Math.max(range.end, r.end);
      }
    }
    if (!inserted) {
      merged.push(range);
    }
    this.ranges = merged;
    this.notifyProgress();
  }

  private hasRange(offset: number, length: number): boolean {
    const end = this.limitEnd(offset + length);
    for (const r of this.ranges) {
      if (r.start <= offset && r.end >= end) {
        return true;
      }
    }
    return false;
  }

  private bufferedFrom(offset: number): number {
    for (const r of this.ranges) {
      if (r.start <= offset && r.end > offset) {
        return r.end - offset;
      }
    }
    return 0;
  }

  private clampLength(offset: number, length: number): number {
    if (this.totalSize > 0) {
      return Math.max(0, Math.min(length, this.totalSize - offset));
    }
    return length;
  }

  private limitEnd(end: number): number {
    return this.totalSize > 0 ? Math.min(end, this.totalSize) : end;
  }

  private notifyProgress(): void {
    const buffered = this.bufferedFrom(0);
    for (const l of this.progressListeners) {
      l(buffered, this.totalSize);
    }
  }
}
