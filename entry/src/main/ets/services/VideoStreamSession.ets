import fileIo from '@ohos.file.fs';
import { TdClient } from '../tdkit/TdClient';
import { TdObject, TdRequest, TdError } from '../tdkit/TdTypes';
import { logE, logW } from '../util/log';

const STREAM_PRIORITY: number = 32;
const CHUNK_SIZE: number = 1024 * 1024;
const LOW_WATER_BYTES: number = 2 * CHUNK_SIZE;
const HIGH_WATER_BYTES: number = 6 * CHUNK_SIZE;
const PREPARE_HEAD_BYTES: number = 2 * CHUNK_SIZE;
const PREPARE_TAIL_BYTES: number = CHUNK_SIZE;
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
    } else {
      this.requestQueue.push(offset);
    }
    this.pumpQueue();
  }

  private pumpQueue(): void {
    if (this.closed || this.activeStart >= 0 || this.requestQueue.length === 0) {
      return;
    }
    const offset = this.requestQueue.shift() as number;
    const length = this.requestLengths.get(offset) ?? 0;
    this.activeStart = offset;
    const req: TdRequest = { '@type': 'downloadFile' };
    req['file_id'] = this.fileId;
    req['priority'] = STREAM_PRIORITY;
    req['offset'] = offset;
    req['limit'] = length;
    req['synchronous'] = true;
    this.client.send(req, STREAM_REQUEST_TIMEOUT_MS).then((f: TdObject) => {
      this.activeStart = -1;
      this.pendingStarts.delete(offset);
      this.requestLengths.delete(offset);
      this.requestAttempts.delete(offset);
      this.applyFile(f);
      this.addRange(offset, this.limitEnd(offset + length));
      this.pumpQueue();
    }).catch((e: TdError) => {
      this.activeStart = -1;
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
