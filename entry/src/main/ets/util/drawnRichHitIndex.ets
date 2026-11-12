import { DrawnRichHit } from './drawnRichTextPolicy';

interface DrawnRichIndexedHit { hit: DrawnRichHit; order: number; bottom: number; }

// Built once with the paragraph, never while painting. O(H log H) preparation,
// O(H) space. Lookup skips preceding non-overlapping lines with a prefix bound;
// pathological overlapping rectangles remain bounded by the policy's 1024 cap.
export class DrawnRichHitIndex {
  readonly regions: Rectangle[] = [];
  private sorted: DrawnRichIndexedHit[] = [];
  private bottoms: number[] = [];

  constructor(hits: DrawnRichHit[]) {
    for (let i: number = 0; i < hits.length; i++) {
      const hit = hits[i];
      this.regions.push({ x: hit.x, y: hit.y, width: hit.widthVp, height: hit.heightVp });
      this.sorted.push({ hit, order: i, bottom: hit.y + hit.heightVp });
    }
    this.sorted.sort((a: DrawnRichIndexedHit, b: DrawnRichIndexedHit): number => a.hit.y - b.hit.y);
    let bottom: number = 0;
    for (const item of this.sorted) {
      bottom = Math.max(bottom, item.bottom);
      this.bottoms.push(bottom);
    }
  }

  find(x: number, y: number): DrawnRichHit | null {
    if (!Number.isFinite(x) || !Number.isFinite(y)) { return null; }
    let low: number = 0, high: number = this.sorted.length;
    while (low < high) {
      const mid: number = (low + high) >>> 1;
      if (this.sorted[mid].hit.y <= y) { low = mid + 1; } else { high = mid; }
    }
    let found: DrawnRichHit | null = null;
    let order: number = -1;
    for (let i: number = low - 1; i >= 0 && this.bottoms[i] > y; i--) {
      const item = this.sorted[i], hit = item.hit;
      // Later child wins if glyph rectangles overlap, like the former Stack.
      if (item.order > order && y < item.bottom && x >= hit.x && x < hit.x + hit.widthVp) {
        found = hit; order = item.order;
      }
    }
    return found;
  }
}
