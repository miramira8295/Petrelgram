// Repeat needs its insertion delta bounded by the smallest active cache.
export const TIMELINE_SCROLL_CACHE_ROWS: number = 3;

// LazyForEach retains keyed entries across index shifts. Keep a bounded batch
// during motion; drain faster at rest, without changing the media admission gate.
export function timelinePrependRows(configured: number, lazy: boolean = false,
  moving: boolean = true): number {
  const limit: number = lazy ? (moving ? 8 : 16) : TIMELINE_SCROLL_CACHE_ROWS;
  return Math.max(1, Math.min(limit, Math.floor(configured) * (lazy && !moving ? 2 : 1)));
}
