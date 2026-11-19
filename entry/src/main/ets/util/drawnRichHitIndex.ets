import { DrawnRichHit } from './drawnRichTextPolicy';

interface DrawnRichIndexedHit { hit: DrawnRichHit; order: number; top: number; bottom: number; }
class DrawnRichIntervalNode {
  center: number;
  byTop: DrawnRichIndexedHit[];
  byBottom: DrawnRichIndexedHit[];
  left: DrawnRichIntervalNode | null = null;
  right: DrawnRichIntervalNode | null = null;
  constructor(center: number, crossing: DrawnRichIndexedHit[]) {
    this.center = center; this.byTop = crossing;
    this.byBottom = crossing.slice().sort((a: DrawnRichIndexedHit, b: DrawnRichIndexedHit): number => b.bottom - a.bottom);
  }
}

// Centered interval tree: O(H log H) preparation, O(H) retained space and
// O(log H + K) lookup for K rectangles intersecting the queried horizontal line.
// A single tall rectangle cannot force a scan of every preceding glyph line.
// Original paint order remains the overlap tie-breaker. No text-size cap needed.
export class DrawnRichHitIndex {
  readonly regions: Rectangle[] = [];
  private root: DrawnRichIntervalNode | null = null;

  constructor(hits: DrawnRichHit[]) {
    const sorted: DrawnRichIndexedHit[] = [];
    for (let i: number = 0; i < hits.length; i++) {
      const hit = hits[i];
      if (!Number.isFinite(hit.x) || !Number.isFinite(hit.y) || !Number.isFinite(hit.widthVp) ||
        !Number.isFinite(hit.heightVp) || !Number.isFinite(hit.x + hit.widthVp) ||
        !Number.isFinite(hit.y + hit.heightVp) || !(hit.widthVp > 0 && hit.heightVp > 0)) { continue; }
      this.regions.push({ x: hit.x, y: hit.y, width: hit.widthVp, height: hit.heightVp });
      sorted.push({ hit, order: i, top: hit.y, bottom: hit.y + hit.heightVp });
    }
    sorted.sort((a: DrawnRichIndexedHit, b: DrawnRichIndexedHit): number => a.top - b.top);
    this.root = this.build(sorted);
  }

  private build(sorted: DrawnRichIndexedHit[]): DrawnRichIntervalNode | null {
    if (sorted.length === 0) { return null; }
    const center = sorted[sorted.length >>> 1].top;
    const left: DrawnRichIndexedHit[] = [], right: DrawnRichIndexedHit[] = [], crossing: DrawnRichIndexedHit[] = [];
    for (const item of sorted) {
      if (item.bottom <= center) { left.push(item); }
      else if (item.top > center) { right.push(item); }
      else { crossing.push(item); }
    }
    const node = new DrawnRichIntervalNode(center, crossing);
    node.left = this.build(left); node.right = this.build(right);
    return node;
  }

  find(x: number, y: number): DrawnRichHit | null {
    if (!Number.isFinite(x) || !Number.isFinite(y)) { return null; }
    let node = this.root;
    let found: DrawnRichHit | null = null;
    let order: number = -1;
    while (node !== null) {
      const upper = y < node.center;
      const candidates = upper ? node.byTop : node.byBottom;
      for (const item of candidates) {
        if (upper ? item.top > y : item.bottom <= y) { break; }
        const hit = item.hit;
        if (item.order > order && x >= hit.x && x < hit.x + hit.widthVp) { found = hit; order = item.order; }
      }
      node = upper ? node.left : node.right;
    }
    return found;
  }
}
