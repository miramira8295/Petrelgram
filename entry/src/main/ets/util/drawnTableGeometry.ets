import { DrawnTableGrid } from './drawnTableGrid';

// Only cell boundaries need physical coordinates. A span of a billion logical
// columns contributes two boundaries, never a billion-element width array.
// Range-max constraints accumulate lazily; one O(N) sweep emits final positions.
export class DrawnTableColumnGeometry {
  private boundaries: number[] = [0];
  private indices: Map<number, number> = new Map<number, number>();
  private minimums: number[] = [];
  private positions: number[] = [0];
  private singles: number[] = [];
  constructor(grid: DrawnTableGrid) {
    const points = new Set<number>([0]);
    for (const pos of grid.cells) { points.add(pos.column); points.add(pos.column + pos.columns); }
    const unique = Array.from(points).sort((a: number, b: number): number => a - b);
    this.boundaries = unique;
    for (let i: number = 0; i < unique.length; i++) { this.indices.set(unique[i], i); }
    this.singles = new Array<number>(Math.max(0, unique.length - 1)).fill(48);
    this.minimums = new Array<number>(Math.max(4, unique.length * 4)).fill(48);
  }
  raise(start: number, end: number, width: number): void {
    const left = this.indices.get(start), right = this.indices.get(end);
    if (left === undefined || right === undefined || right <= left) { return; }
    if (right === left + 1) { this.singles[left] = Math.max(this.singles[left], width); return; }
    this.update(1, 0, this.boundaries.length - 1, left, right, width);
  }
  private update(node: number, left: number, right: number, start: number, end: number, width: number): void {
    if (end <= left || start >= right) { return; }
    if (start <= left && end >= right) { this.minimums[node] = Math.max(this.minimums[node], width); return; }
    const mid = (left + right) >>> 1;
    this.update(node * 2, left, mid, start, end, width); this.update(node * 2 + 1, mid, right, start, end, width);
  }
  finish(): void {
    this.positions = [0];
    if (this.boundaries.length > 1) { this.emit(1, 0, this.boundaries.length - 1, 48); }
  }
  private emit(node: number, left: number, right: number, inherited: number): void {
    const width = Math.max(inherited, this.minimums[node]);
    if (right - left === 1) {
      this.positions.push(this.positions[this.positions.length - 1] + Math.max(width, this.singles[left]) * (this.boundaries[right] - this.boundaries[left]));
      return;
    }
    const mid = (left + right) >>> 1;
    this.emit(node * 2, left, mid, width); this.emit(node * 2 + 1, mid, right, width);
  }
  at(column: number): number { return this.positions[this.indices.get(column) ?? 0] ?? 0; }
  get width(): number { return this.positions[this.positions.length - 1]; }
}

// Two Fenwick trees provide range-add/range-sum in O(log R), preserving the
// previous sequential merged-cell height distribution. Difference events make
// final row coordinates O(R), without querying every row through the trees.
export class DrawnTableRowGeometry {
  private base: number[];
  private prefix: number[] = [0];
  private deltas: number[];
  private weighted: number[];
  private events: number[];
  constructor(heights: number[]) {
    this.base = heights;
    for (const height of heights) { this.prefix.push(this.prefix[this.prefix.length - 1] + height); }
    this.deltas = new Array<number>(heights.length + 1).fill(0);
    this.weighted = new Array<number>(heights.length + 1).fill(0);
    this.events = new Array<number>(heights.length + 1).fill(0);
  }
  private add(tree: number[], at: number, delta: number): void {
    for (let i: number = at; i < tree.length; i += i & -i) { tree[i] += delta; }
  }
  private sum(tree: number[], at: number): number {
    let result: number = 0;
    for (let i: number = at; i > 0; i -= i & -i) { result += tree[i]; }
    return result;
  }
  private extra(count: number): number { return count * this.sum(this.deltas, count) - this.sum(this.weighted, count); }
  total(start: number, end: number): number { return this.prefix[end] - this.prefix[start] + this.extra(end) - this.extra(start); }
  grow(start: number, end: number, delta: number): void {
    if (!(delta > 0) || end <= start) { return; }
    this.add(this.deltas, start + 1, delta); this.add(this.deltas, end + 1, -delta);
    this.add(this.weighted, start + 1, delta * start); this.add(this.weighted, end + 1, -delta * end);
    this.events[start] += delta; this.events[end] -= delta;
  }
  coordinates(): number[] {
    const result: number[] = [0]; let delta: number = 0;
    for (let i: number = 0; i < this.base.length; i++) {
      delta += this.events[i]; result.push(result[result.length - 1] + this.base[i] + delta);
    }
    return result;
  }
}
