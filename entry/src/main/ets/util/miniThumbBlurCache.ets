import { taskpool } from '@kit.ArkTS';
import { blurMiniThumb } from './miniThumbBlurTask';
import { logW } from './log';

type MiniThumbBlurListener = (uri: string) => void;
type MiniThumbBlurRender = (source: string, w: number, h: number, contain: boolean) => Promise<string>;
interface MiniThumbBlurJob {
  key: string;
  source: string;
  w: number;
  h: number;
  contain: boolean;
  listeners: Set<MiniThumbBlurListener>;
}

// O(1) map lookup/LRU/queued cancellation (plus O(source length) key hashing).
// One worker, at most 32 jobs and 128/2MiB cached strings. No UI pixel loops,
// array shifting, full-cache scans or native PixelMap retained under Image.
export class MiniThumbBlurCache {
  private cache: Map<string, string> = new Map<string, string>();
  private jobs: Map<string, MiniThumbBlurJob> = new Map<string, MiniThumbBlurJob>();
  private queue: Map<string, MiniThumbBlurJob> = new Map<string, MiniThumbBlurJob>();
  private busy: boolean = false;
  private bytes: number = 0;
  private render: MiniThumbBlurRender;
  constructor(render: MiniThumbBlurRender) { this.render = render; }

  request(source: string, w: number, h: number, contain: boolean, ready: MiniThumbBlurListener): () => void {
    if (source.length > 65536 || !source.startsWith('data:image/') || !(w > 0 && h > 0)) { return (): void => {}; }
    const key = `${Math.round(w * 10)}:${Math.round(h * 10)}:${contain}:${source}`;
    const hit = this.cache.get(key);
    if (hit !== undefined) {
      this.cache.delete(key); this.cache.set(key, hit);
      if (hit !== '') { ready(hit); }
      return (): void => {};
    }
    let job = this.jobs.get(key);
    if (job === undefined) {
      if (this.jobs.size >= 32) { return (): void => {}; }
      job = { key, source, w, h, contain, listeners: new Set<MiniThumbBlurListener>() };
      this.jobs.set(key, job); this.queue.set(key, job);
    }
    job.listeners.add(ready);
    const owned = job;
    this.pump();
    return (): void => {
      owned.listeners.delete(ready);
      if (owned.listeners.size === 0 && this.queue.get(key) === owned) {
        this.queue.delete(key); this.jobs.delete(key);
      }
    };
  }

  private pump(): void {
    if (this.busy || this.queue.size === 0) { return; }
    const job = this.queue.values().next().value as MiniThumbBlurJob;
    this.queue.delete(job.key); this.busy = true;
    this.run(job);
  }

  private async run(job: MiniThumbBlurJob): Promise<void> {
    let uri = '';
    try { uri = await this.render(job.source, job.w, job.h, job.contain); }
    catch (error) { logW(`[MiniThumb] static blur failed: ${(error as Error).message}`); }
    // Cache failures too, so scrolling does not repeatedly retry unsupported input.
    if (uri.length > 262144) { uri = ''; }
    this.cache.set(job.key, uri); this.bytes += (job.key.length + uri.length) * 2;
    while (this.cache.size > 128 || this.bytes > 2 * 1024 * 1024) {
      const key = this.cache.keys().next().value as string;
      const old = this.cache.get(key) ?? '';
      this.bytes -= (key.length + old.length) * 2; this.cache.delete(key);
    }
    this.jobs.delete(job.key);
    try {
      // Set iteration tolerates cancellation during delivery; no callback array allocation.
      if (uri !== '') {
        for (const listener of job.listeners) {
          try { listener(uri); } catch (error) { logW(`[MiniThumb] delivery failed: ${(error as Error).message}`); }
        }
      }
    } finally {
      job.listeners.clear(); this.busy = false; this.pump();
    }
  }
}

export const miniThumbBlurCache: MiniThumbBlurCache = new MiniThumbBlurCache(
  async (source: string, w: number, h: number, contain: boolean): Promise<string> => {
    const task = new taskpool.Task(blurMiniThumb, source, w, h, contain);
    return await taskpool.execute(task, taskpool.Priority.LOW) as string;
  });
