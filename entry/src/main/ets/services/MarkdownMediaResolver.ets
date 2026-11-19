import { common } from '@kit.AbilityKit';
import { request } from '@kit.BasicServicesKit';
import { fileIo } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { url } from '@kit.ArkTS';
import { TdClient } from '../tdkit/TdClient';
import { TdObject } from '../tdkit/TdTypes';
import { MarkdownImageResolver, MarkdownResolvedImage } from '../util/markdownRichInput';

export interface MarkdownMediaResolverOptions {
  // One resolver belongs to one explicit send attempt. A chat/account/draft
  // owner can additionally invalidate it without sharing a mutable context.
  isCurrent?: () => boolean;
  maxImageBytes?: number;
  maxTotalBytes?: number;
  maxPixels?: number;
  downloadTimeoutMs?: number;
}
interface ImageHeader {
  width: number;
  height: number;
  mime: string;
  animation: boolean;
  duration: number;
}
let markdownMediaSerial: number = 0;
const MIME_EXTENSIONS: Map<string, string> = new Map([
  ['image/jpeg', '.jpg'], ['image/png', '.png'], ['image/apng', '.png'], ['image/webp', '.webp'],
  ['image/gif', '.gif'], ['image/heif', '.heif'], ['image/heic', '.heic'], ['image/bmp', '.bmp'], ['image/tiff', '.tiff']
]);
function mediaError(reason: string): Error { return new Error(`MARKDOWN_IMAGE_${reason}`); }
export function markdownImageUrl(value: string): string {
  const trimmed = value.trim();
  if (trimmed === '' || trimmed.length > 8192 || /[\u0000-\u0020\u007f]/.test(trimmed)) { throw mediaError('URL'); }
  let parsed: url.URL;
  try { parsed = new url.URL(trimmed); } catch (_error) { throw mediaError('URL'); }
  if ((parsed.protocol !== 'http:' && parsed.protocol !== 'https:') || parsed.hostname === '' || parsed.username !== '' || parsed.password !== '') {
    throw mediaError('URL');
  }
  parsed.hash = ''; return parsed.href;
}
function positiveLimit(value: number | undefined, fallback: number): number {
  return value !== undefined && Number.isFinite(value) && value > 0 ? value : fallback;
}
class MarkdownDownload {
  path: string;
  task: request.DownloadTask | null = null;
  bytes: number = 0;
  cancelled: boolean = false;
  ready: boolean = false;
  work: Promise<void> | null = null;
  promise: Promise<MarkdownResolvedImage>;
  resolve: (image: MarkdownResolvedImage) => void = (_image: MarkdownResolvedImage): void => {};
  reject: (error: Error) => void = (_error: Error): void => {};
  abort: (() => void) | null = null;
  complete: (() => void) | null = null;
  paused: (() => void) | null = null;
  removed: (() => void) | null = null;
  fail: ((code: number) => void) | null = null;
  progress: ((received: number, total: number) => void) | null = null;
  constructor(path: string) {
    this.path = path;
    this.promise = new Promise<MarkdownResolvedImage>((resolve, reject): void => { this.resolve = resolve; this.reject = reject; });
  }
}

// No fetch/ArrayBuffer/PixelMap: the system downloader streams to our unique
// cache directory; ImageSource reads headers only. The Markdown compiler owns
// worker concurrency, while this owner memoizes duplicate HTTP URLs in O(1).
export class MarkdownMediaResolver implements MarkdownImageResolver {
  private context: common.UIAbilityContext;
  private directory: string;
  private options: MarkdownMediaResolverOptions;
  private directoryReady: Promise<void> | null = null;
  private jobs: Map<string, MarkdownDownload> = new Map();
  private serial: number = 0;
  private bytes: number = 0;
  private retained: number = 0;
  private disposed: boolean = false;
  private disposing: Promise<void> | null = null;
  private cleaning: Promise<void> | null = null;
  private maxImageBytes: number;
  private maxTotalBytes: number;
  private maxPixels: number;
  private downloadTimeoutMs: number;
  constructor(context: common.UIAbilityContext, options: MarkdownMediaResolverOptions = {}) {
    this.context = context; this.options = options;
    this.directory = `${context.cacheDir}/markdown-media-${Date.now()}-${++markdownMediaSerial}`;
    this.maxImageBytes = positiveLimit(options.maxImageBytes, 20 * 1024 * 1024);
    this.maxTotalBytes = positiveLimit(options.maxTotalBytes, 64 * 1024 * 1024);
    this.maxPixels = positiveLimit(options.maxPixels, 100000000);
    this.downloadTimeoutMs = positiveLimit(options.downloadTimeoutMs, 60000);
  }
  private current(job?: MarkdownDownload): boolean {
    return !this.disposed && job?.cancelled !== true && (this.options.isCurrent?.() ?? true);
  }
  private assertCurrent(job?: MarkdownDownload): void { if (!this.current(job)) { throw mediaError('CANCELLED'); } }
  private updateSize(job: MarkdownDownload, size: number): void {
    if (!Number.isFinite(size) || size < 0) { return; }
    if (size > this.maxImageBytes) { throw mediaError('SIZE'); }
    if (size > job.bytes) { this.bytes += size - job.bytes; job.bytes = size; }
    if (this.bytes > this.maxTotalBytes) { throw mediaError('TOTAL_SIZE'); }
  }
  resolve(value: string): Promise<MarkdownResolvedImage> {
    try { this.assertCurrent(); } catch (error) { return Promise.reject(error); }
    let key: string;
    try { key = markdownImageUrl(value); } catch (error) { return Promise.reject(error); }
    const cached = this.jobs.get(key); if (cached !== undefined) { return cached.promise; }
    const job = new MarkdownDownload(`${this.directory}/${++this.serial}.part`); this.jobs.set(key, job);
    job.work = this.download(key, job); return job.promise;
  }
  private detach(job: MarkdownDownload): void {
    if (job.task === null) { return; }
    try {
      if (job.complete !== null) { job.task.off('complete', job.complete); }
      if (job.paused !== null) { job.task.off('pause', job.paused); }
      if (job.removed !== null) { job.task.off('remove', job.removed); }
      if (job.fail !== null) { job.task.off('fail', job.fail); }
      if (job.progress !== null) { job.task.off('progress', job.progress); }
    } catch (_error) { /* A terminal system task can already be gone. delete() below also releases its listeners. */ }
    job.complete = null; job.paused = null; job.removed = null; job.fail = null; job.progress = null; job.abort = null;
  }
  private waitForDownload(job: MarkdownDownload): Promise<void> {
    return new Promise<void>((resolve, reject): void => {
      let terminal: boolean = false; let timer: number = -1;
      const end = (error?: Error): void => {
        if (terminal) { return; } terminal = true;
        if (timer !== -1) { clearTimeout(timer); timer = -1; }
        if (error === undefined) { resolve(); } else { reject(error); }
      };
      job.abort = (): void => end(mediaError('CANCELLED'));
      job.complete = (): void => end();
      job.paused = (): void => end(mediaError('DOWNLOAD_PAUSED'));
      job.removed = (): void => end(mediaError('CANCELLED'));
      job.fail = (code: number): void => end(mediaError(`DOWNLOAD_${code}`));
      job.progress = (received: number, total: number): void => {
        if (terminal) { return; }
        try { this.assertCurrent(job); this.updateSize(job, Math.max(received, total)); }
        catch (error) { end(error as Error); }
      };
      const task = job.task;
      if (task === null) { end(mediaError('DOWNLOAD')); return; }
      try {
        task.on('complete', job.complete); task.on('pause', job.paused); task.on('remove', job.removed);
        task.on('fail', job.fail); task.on('progress', job.progress);
        if (!terminal) { timer = setTimeout((): void => end(mediaError('TIMEOUT')), this.downloadTimeoutMs); }
        // A small cached response can finish before listeners are installed.
        task.getTaskInfo().then((info: request.DownloadInfo): void => {
          if (terminal) { return; }
          try {
            this.assertCurrent(job); this.updateSize(job, Math.max(info.downloadedBytes, info.downloadTotalBytes));
            if (info.status === request.SESSION_SUCCESSFUL) { end(); }
            else if (info.status === request.SESSION_FAILED) { end(mediaError(`DOWNLOAD_${info.failedReason}`)); }
            else if (info.status === request.SESSION_PAUSED) { end(mediaError('DOWNLOAD_PAUSED')); }
          } catch (error) { end(error as Error); }
        }).catch((error: Error): void => { if (!terminal) { end(error); } });
      } catch (error) { end(error as Error); }
    });
  }
  private async header(job: MarkdownDownload): Promise<ImageHeader> {
    let source: image.ImageSource | null = null;
    try {
      source = image.createImageSource(job.path);
      if (source === undefined || source === null) { throw mediaError('FORMAT'); }
      const info = await source.getImageInfo(); this.assertCurrent(job);
      const width = info.size.width, height = info.size.height, mime = info.mimeType.toLowerCase();
      if (!Number.isSafeInteger(width) || !Number.isSafeInteger(height) || width <= 0 || height <= 0 || width * height > this.maxPixels) {
        throw mediaError('DIMENSIONS');
      }
      if (!MIME_EXTENSIONS.has(mime)) { throw mediaError('FORMAT'); }
      const frames = await source.getFrameCount(); this.assertCurrent(job);
      if (!Number.isSafeInteger(frames) || frames < 1) { throw mediaError('FORMAT'); }
      const animation = frames > 1; let duration: number = 0;
      // Duration metadata is optional; native/server inspection remains final.
      // Avoid copying an unbounded frame-delay array into ArkTS for large GIFs.
      if (animation && frames <= 4096) {
        try {
          const times = await source.getDelayTimeList();
          let milliseconds: number = 0;
          for (const time of times) { if (Number.isFinite(time) && time >= 0) { milliseconds += time; } }
          duration = Math.ceil(milliseconds / 1000);
        } catch (_error) { /* Some multi-frame formats expose no timing metadata; do not freeze them into photos. */ }
      }
      this.assertCurrent(job); return { width, height, mime, animation, duration };
    } finally { await source?.release(); }
  }
  private async download(value: string, job: MarkdownDownload): Promise<void> {
    try {
      if (this.directoryReady === null) { this.directoryReady = fileIo.mkdir(this.directory); }
      await this.directoryReady; this.assertCurrent(job);
      job.task = await request.downloadFile(this.context, { url: value, filePath: job.path, background: false }); this.assertCurrent(job);
      await this.waitForDownload(job); this.detach(job); this.assertCurrent(job);
      const stat = await fileIo.stat(job.path); this.assertCurrent(job); this.updateSize(job, stat.size);
      if (stat.size <= 0) { throw mediaError('EMPTY'); }
      const header = await this.header(job); this.assertCurrent(job);
      const named = job.path.substring(0, job.path.length - 5) + (MIME_EXTENSIONS.get(header.mime) ?? '.image');
      await fileIo.rename(job.path, named); job.path = named; this.assertCurrent(job);
      job.ready = true;
      const file: Record<string, Object> = {}; file['@type'] = 'inputFileLocal'; file['path'] = job.path;
      const resolved: MarkdownResolvedImage = { file, width: header.width, height: header.height,
        animation: header.animation, duration: header.duration };
      job.resolve(resolved);
    } catch (error) {
      this.detach(job); job.reject(error as Error); await this.cleanJob(job);
    }
  }
  private async cleanJob(job: MarkdownDownload): Promise<void> {
    this.detach(job);
    if (job.task !== null) {
      const task = job.task; job.task = null;
      try { await task.delete(); } catch (_error) { /* Already-terminal task removal is best effort. */ }
    }
    try { await fileIo.unlink(job.path); } catch (_error) { /* Missing partial files are normal on download/create/cancel failure. */ }
  }
  private async clean(): Promise<void> {
    if (this.retained !== 0) { return; }
    if (this.cleaning !== null) { return this.cleaning; }
    this.cleaning = (async (): Promise<void> => {
      for (const job of this.jobs.values()) { await this.cleanJob(job); }
      try { await fileIo.rmdir(this.directory); } catch (_error) { /* An empty/missing cache directory can already be removed by the OS. */ }
    })();
    await this.cleaning;
  }
  // Call after resolving all media and before sending. sendMessage returning a
  // pending message does not mean TDLib has finished reading inputFileLocal.
  retainUntilConsumed(): () => Promise<void> {
    this.assertCurrent();
    for (const job of this.jobs.values()) { if (!job.ready) { throw mediaError('NOT_READY'); } }
    this.retained++; let released: boolean = false;
    return async (): Promise<void> => {
      if (released) { return; } released = true; this.retained--;
      if (this.disposed) { await this.clean(); }
    };
  }
  beginSend(client: TdClient): MarkdownMediaSendLease {
    const release = this.retainUntilConsumed();
    try { return new MarkdownMediaSendLease(client, release); }
    catch (error) { release(); throw error as Error; }
  }
  cancel(): Promise<void> { return this.dispose(); }
  dispose(): Promise<void> {
    if (this.disposing !== null) { return this.disposing; }
    this.disposed = true;
    for (const job of this.jobs.values()) { if (!job.ready) { job.cancelled = true; job.abort?.(); } }
    this.disposing = (async (): Promise<void> => {
      for (const job of this.jobs.values()) { await job.work; }
      await this.clean();
    })();
    return this.disposing;
  }
}

// Success can race the caller's adopt() after sendMessage resolves. Listen
// before send, then narrow to its pending ID. Failed sends retain source files
// for TDLib retry; explicit cancellation or a closed client releases them.
export class MarkdownMediaSendLease {
  private releaseFiles: () => Promise<void>;
  private offSuccess: (() => void) | null = null;
  private offClose: (() => void) | null = null;
  private adopted: number = 0;
  private early: Set<number> = new Set();
  private released: Promise<void> | null = null;
  constructor(client: TdClient, releaseFiles: () => Promise<void>) {
    this.releaseFiles = releaseFiles;
    try {
      this.offSuccess = client.onUpdate('updateMessageSendSucceeded', (update: TdObject): void => {
        const id = (update['old_message_id'] as number | undefined) ?? 0;
        if (id === 0) { return; }
        if (this.adopted === id) { this.release(); }
        else if (this.adopted === 0) {
          this.early.add(id);
          // Only a short pre-response window is retained. If a pathological
          // burst evicts an ID, files stay leased rather than being deleted early.
          if (this.early.size > 512) { this.early.delete(this.early.values().next().value as number); }
        }
      });
      this.offClose = client.onUpdate('updateAuthorizationState', (update: TdObject): void => {
        if ((update['authorization_state'] as TdObject | undefined)?.['@type'] === 'authorizationStateClosed') { this.release(); }
      });
    } catch (error) { this.offSuccess?.(); this.offSuccess = null; releaseFiles(); throw error as Error; }
  }
  adopt(id: number): void {
    if (this.released !== null) { return; }
    if (!Number.isSafeInteger(id) || id === 0 || (this.adopted !== 0 && this.adopted !== id)) { throw mediaError('SEND_ID'); }
    this.adopted = id;
    const consumed = this.early.has(id); this.early.clear();
    if (consumed) { this.release(); }
  }
  // A timed-out send may already be consuming inputFileLocal. Without a
  // pending ID there is no safe success match. Leave files to OS cache eviction,
  // but drop listeners and the resolver closure rather than retaining a whole
  // send attempt indefinitely. This is deliberately not a timed deletion.
  abandon(): void {
    if (this.released !== null) { return; }
    this.offSuccess?.(); this.offSuccess = null; this.offClose?.(); this.offClose = null; this.early.clear();
    this.releaseFiles = async (): Promise<void> => {};
    this.released = Promise.resolve();
  }
  release(): Promise<void> {
    if (this.released !== null) { return this.released; }
    this.offSuccess?.(); this.offSuccess = null; this.offClose?.(); this.offClose = null; this.early.clear();
    this.released = this.releaseFiles(); return this.released;
  }
}
