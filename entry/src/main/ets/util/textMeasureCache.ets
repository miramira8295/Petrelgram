// Configuration changes invalidate measurements without renaming timeline rows.
@ObservedV2
class TextMeasureEnvironment {
  @Trace epoch: number = 0;
}
export const textMeasureEnvironment: TextMeasureEnvironment = new TextMeasureEnvironment();
export function invalidateTextMeasurements(): void {
  textMeasureEnvironment.epoch++;
}

// Per component, retained across reuse, bounded to short reaction/time labels.
// Failed measurements are never cached, so the next render can recover.
export class TextMeasureCache {
  private epoch: string = '';
  private values: Map<string, number> = new Map();
  private capacity: number;

  constructor(capacity: number = 64) { this.capacity = capacity; }

  prepare(epoch: string): void {
    if (this.epoch !== epoch) {
      this.epoch = epoch;
      this.values.clear();
    }
  }

  width(text: string, fontSize: number, measure: (text: string, size: number) => number): number {
    const key: string = `${fontSize}:${text}`;
    const hit = this.values.get(key);
    if (hit !== undefined) { return hit; }
    const value = measure(text, fontSize);
    if (text.length <= 128 && Number.isFinite(value) && value >= 0) {
      if (this.values.size >= this.capacity) { this.values.clear(); }
      this.values.set(key, value);
    }
    return value;
  }
}

// Share native measurements only inside a known UI instance. Local component
// caches remain the first tier; this pool is consulted only on their misses.
// Store physical pixels; each caller retains its own px -> vp conversion.
// No UIContext/component/measurement closures are retained by the pool.
export class TextMeasureCachePool {
  private scopes: Map<number, TextMeasureCache> = new Map();

  width(scope: number, environment: string, text: string, fontSize: number,
    measure: (text: string, size: number) => number): number {
    if (!Number.isInteger(scope) || scope < 0) { return measure(text, fontSize); }
    let cache = this.scopes.get(scope);
    if (cache === undefined) {
      if (this.scopes.size >= 4) {
        const oldest: number = this.scopes.keys().next().value;
        this.scopes.delete(oldest);
      }
      cache = new TextMeasureCache(256);
      this.scopes.set(scope, cache);
    }
    cache.prepare(environment);
    return cache.width(text, fontSize, measure);
  }
}

export const sharedTextMeasurements: TextMeasureCachePool = new TextMeasureCachePool();
