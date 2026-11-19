import { DrawnRichTableCell } from './drawnRichTextPolicy';

export interface DrawnTableCellPosition {
  cell: DrawnRichTableCell;
  row: number;
  column: number;
  rows: number;
  columns: number;
}
export interface DrawnTableGrid {
  cells: DrawnTableCellPosition[];
  columns: number;
  rows: number;
}

// Sparse free-space tree over logical columns. Whole occupied/free ranges are
// represented by one node; a large colspan never allocates one slot per column.
class DrawnTableFreeSpace {
  private left: number;
  private right: number;
  private first: DrawnTableFreeSpace | null = null;
  private second: DrawnTableFreeSpace | null = null;
  private state: number = 0; // 0 free, 1 occupied, -1 mixed
  private prefix: number;
  private suffix: number;
  private longest: number;
  constructor(left: number, right: number) {
    this.left = left; this.right = right;
    this.prefix = this.suffix = this.longest = right - left;
  }
  assign(start: number, end: number, occupied: boolean): void {
    if (end <= this.left || start >= this.right) { return; }
    if (start <= this.left && end >= this.right) {
      this.state = occupied ? 1 : 0; this.first = this.second = null;
      this.prefix = this.suffix = this.longest = occupied ? 0 : this.right - this.left;
      return;
    }
    const mid = this.left + Math.floor((this.right - this.left) / 2);
    if (this.first === null || this.second === null) {
      this.first = new DrawnTableFreeSpace(this.left, mid); this.second = new DrawnTableFreeSpace(mid, this.right);
      if (this.state === 1) { this.first.assign(this.left, mid, true); this.second.assign(mid, this.right, true); }
    }
    const a = this.first, b = this.second;
    a.assign(start, end, occupied); b.assign(start, end, occupied);
    if (a.state === b.state && a.state !== -1) { this.assign(this.left, this.right, a.state === 1); return; }
    this.state = -1;
    this.prefix = a.prefix + (a.prefix === mid - this.left ? b.prefix : 0);
    this.suffix = b.suffix + (b.suffix === this.right - mid ? a.suffix : 0);
    this.longest = Math.max(a.longest, b.longest, a.suffix + b.prefix);
  }
  find(start: number, size: number): number {
    if (this.right <= start || this.longest < size) { return -1; }
    if (this.state === 0) { return Math.max(start, this.left) + size <= this.right ? Math.max(start, this.left) : -1; }
    const a = this.first, b = this.second;
    if (a === null || b === null) { return -1; }
    const inFirst = a.find(start, size);
    if (inFirst >= 0) { return inFirst; }
    const mid = a.right, crossing = Math.max(start, mid - a.suffix);
    if (crossing < mid && crossing + size <= mid + b.prefix) { return crossing; }
    return b.find(start, size);
  }
}

// Normalize once, then place each cell using O(log C) range operations. Rowspan
// expiry is bucketed by row, so no row scans all previous cells/occupied columns.
// C is the sum of logical spans, not a materialized width. Sparse occupancy uses
// O(N log C) space at worst, instead of a rows×columns matrix. Tables with
// no rowspans retain a direct O(N + R) cursor path and allocate no occupancy tree.
export function drawnTableGrid(rows: DrawnRichTableCell[][]): DrawnTableGrid | null {
  const cells: DrawnTableCellPosition[] = [];
  let capacity: number = 0, mergedRows: boolean = false;
  for (let r: number = 0; r < rows.length; r++) {
    for (const cell of rows[r]) {
      if (!Number.isFinite(cell.colspan) || !Number.isFinite(cell.rowspan)) { return null; }
      const span = Math.max(1, Math.floor(cell.colspan));
      const height = Math.max(1, Math.min(rows.length - r, Math.floor(cell.rowspan)));
      if (!Number.isSafeInteger(span) || !Number.isSafeInteger(height) || !Number.isSafeInteger(capacity + span)) { return null; }
      capacity += span; mergedRows = mergedRows || height > 1;
      cells.push({ cell, row: r, column: 0, rows: height, columns: span });
    }
  }
  if (capacity === 0) { return { cells, rows: rows.length, columns: 0 }; }
  if (!mergedRows) {
    let row: number = -1, cursor: number = 0, columns: number = 0;
    for (const pos of cells) {
      if (row !== pos.row) { row = pos.row; cursor = 0; }
      pos.column = cursor; cursor += pos.columns; columns = Math.max(columns, cursor);
    }
    return { cells, columns, rows: rows.length };
  }
  const space = new DrawnTableFreeSpace(0, capacity);
  const expiry: Map<number, DrawnTableCellPosition[]> = new Map<number, DrawnTableCellPosition[]>();
  let index: number = 0, columns: number = 0;
  for (let r: number = 0; r < rows.length; r++) {
    for (const pos of expiry.get(r) ?? []) { space.assign(pos.column, pos.column + pos.columns, false); }
    expiry.delete(r);
    let cursor: number = 0;
    while (index < cells.length && cells[index].row === r) {
      const pos = cells[index++], column = space.find(cursor, pos.columns);
      if (column < 0) { return null; }
      pos.column = column; cursor = column + pos.columns; columns = Math.max(columns, cursor);
      // Single-row cells need no occupancy entry: the row cursor already
      // prevents reuse; only spans surviving into the next row are retained.
      if (pos.rows > 1) {
        space.assign(column, cursor, true);
        const end = r + pos.rows;
        let bucket = expiry.get(end);
        if (bucket === undefined) { bucket = []; expiry.set(end, bucket); }
        bucket.push(pos);
      }
    }
  }
  return { cells, columns, rows: rows.length };
}
