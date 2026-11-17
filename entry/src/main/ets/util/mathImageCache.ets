import { image } from '@kit.ImageKit';
import { LatexMathColorFormat, TeXParseResult, TeXResultCode, latexStringToImageWithError } from '@cangjie-tpc/formula_hybrid';
import { KEY_APP_DARK } from './theme';
import { logW } from './log';

export interface MathImage { pixel: image.PixelMap; width: number; height: number; }
export interface MathImageMetrics { width: number; height: number; }
interface MathImageJob {
  key: string;
  expression: string;
  size: number;
  color: number;
  listeners: Set<() => void>;
  running: boolean;
  epoch: number;
}
const MAX_ENTRIES: number = 64;
const MAX_BYTES: number = 24 * 1024 * 1024;
const MAX_PENDING: number = 256;
const cache: Map<string, MathImage> = new Map<string, MathImage>();
const metrics: Map<string, MathImageMetrics> = new Map<string, MathImageMetrics>();
const failed: Set<string> = new Set<string>();
const jobs: Map<string, MathImageJob> = new Map<string, MathImageJob>();
const queue: MathImageJob[] = [];
let queueHead: number = 0;
let running: number = 0;
let cachedBytes: number = 0;
let epoch: number = 0;

export function mathForegroundColor(): number {
  return (AppStorage.get<boolean>(KEY_APP_DARK) ?? false) ? 0xFFFFFFFF : 0xFF0E1621;
}
export function mathKeyOf(expression: string, fontSize: number, colorArgb: number): string {
  return `${expression}|${fontSize}|${colorArgb}`;
}
export function mathImageFor(key: string): MathImage | undefined { return cache.get(key); }
export function mathMetricsFor(key: string): MathImageMetrics | undefined { return metrics.get(key); }
export function mathImageFailed(key: string): boolean { return failed.has(key); }
function rememberFailure(key: string): void {
  failed.add(key);
  if (failed.size > MAX_ENTRIES * 2) { failed.delete(failed.keys().next().value as string); }
}
function remember(key: string, entry: MathImage): void {
  metrics.delete(key); metrics.set(key, { width: entry.width, height: entry.height });
  if (metrics.size > MAX_ENTRIES * 8) { metrics.delete(metrics.keys().next().value as string); }
  const previous = cache.get(key);
  if (previous !== undefined) { cachedBytes -= previous.width * previous.height * 4; }
  cache.delete(key); cache.set(key, entry); cachedBytes += entry.width * entry.height * 4;
  while (cache.size > MAX_ENTRIES || cachedBytes > MAX_BYTES) {
    const oldest = cache.keys().next().value as string | undefined;
    if (oldest === undefined) { break; }
    const removed = cache.get(oldest)!;
    cachedBytes -= removed.width * removed.height * 4; cache.delete(oldest);
    // Active drawing layers may still hold the PixelMap. Do not explicitly
    // release a shared pixel under them; dropping this cache reference is safe.
  }
}
async function render(job: MathImageJob): Promise<void> {
  let source: image.ImageSource | null = null;
  try {
    const result: TeXParseResult = await latexStringToImageWithError(job.expression, job.size,
      job.color, 0x00000000, LatexMathColorFormat.COLOR_FORMAT_BGRA_8888);
    if (result.resultCode !== TeXResultCode.Success) { throw new Error(`formula code=${result.resultCode}`); }
    source = image.createImageSource(result.imageBytes);
    const info = await source.getImageInfo();
    if (!(info.size.width > 0 && info.size.height > 0) || info.size.width * info.size.height > MAX_BYTES / 4) {
      throw new Error('formula image exceeds budget');
    }
    const pixel = await source.createPixelMap();
    if (job.epoch === epoch) { remember(job.key, { pixel, width: info.size.width, height: info.size.height }); }
  } catch (error) {
    if (job.epoch === epoch) { rememberFailure(job.key); logW(`[Math] render failed: ${(error as Error).message}`); }
  } finally {
    source?.release();
    if (job.epoch === epoch) {
      running--; jobs.delete(job.key);
      // Snapshot allows listeners to detach/rebind while delivery is in progress.
      const listeners = Array.from(job.listeners);
      for (const listener of listeners) {
        if (!job.listeners.has(listener)) { continue; }
        try { listener(); } catch (error) { logW(`[Math] listener failed: ${(error as Error).message}`); }
      }
      job.listeners.clear();
      pump();
    }
  }
}
function pump(): void {
  while (running < 2 && queueHead < queue.length) {
    const job = queue[queueHead++];
    if (jobs.get(job.key) !== job) { continue; }
    if (job.listeners.size === 0) { jobs.delete(job.key); continue; }
    job.running = true; running++;
    render(job);
  }
  // Amortized O(1) deque; never shift the remaining queue for every completion.
  if (queueHead === queue.length) { queue.length = 0; queueHead = 0; }
  else if (queueHead > 128) { queue.splice(0, queueHead); queueHead = 0; }
}

// One render per key, all active consumers notified. A recycled row can cancel
// its listener without cancelling another row's request. Cache/queue are bounded.
// Terminal failures retain the readable source formula, never a blank rectangle.
export function ensureMathImage(expression: string, fontSize: number, colorArgb: number,
  onReady: () => void): () => void {
  const trimmed = expression.trim();
  const key = mathKeyOf(trimmed, fontSize, colorArgb);
  if (trimmed === '' || !(fontSize > 0) || !Number.isFinite(fontSize) || fontSize > 512 || trimmed.length > 8192 ||
    cache.has(key) || failed.has(key)) { return (): void => {}; }
  let job = jobs.get(key);
  if (job === undefined) {
    if (jobs.size >= MAX_PENDING) { rememberFailure(key); return (): void => {}; }
    job = { key, expression: trimmed, size: fontSize, color: colorArgb, listeners: new Set<() => void>(), running: false, epoch };
    jobs.set(key, job); queue.push(job);
  }
  job.listeners.add(onReady); pump();
  const owned = job;
  return (): void => {
    owned.listeners.delete(onReady);
    if (!owned.running && owned.listeners.size === 0 && jobs.get(key) === owned) { jobs.delete(key); }
    if (queue.length > MAX_PENDING * 2) {
      const active = queue.slice(queueHead).filter((item: MathImageJob): boolean => jobs.get(item.key) === item);
      queue.length = 0; queueHead = 0;
      for (const item of active) { queue.push(item); }
    }
  };
}
export function resetMathImageCacheForTest(): void {
  epoch++; cache.clear(); metrics.clear(); failed.clear(); jobs.clear(); queue.length = 0;
  queueHead = 0; running = 0; cachedBytes = 0;
}
