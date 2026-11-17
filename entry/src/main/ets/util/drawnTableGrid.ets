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

// Occupancy uses one end-row per column, not a rows×columns object matrix.
// Cursor only advances within a row; every tested column is passed once.
// O(cells + occupied column spans + rows×columns), O(columns + cells) memory.
// Bound malformed spans before any allocation or shaping.
export function drawnTableGrid(rows: DrawnRichTableCell[][]): DrawnTableGrid | null {
  if (rows.length > 256) { return null; }
  const until: number[] = [];
  const cells: DrawnTableCellPosition[] = [];
  let columns: number = 0;
  for (let r: number = 0; r < rows.length; r++) {
    let cursor: number = 0;
    for (const cell of rows[r]) {
      if (cells.length >= 2048) { return null; }
      const span = Math.max(1, Math.floor(cell.colspan));
      const height = Math.max(1, Math.min(rows.length - r, Math.floor(cell.rowspan)));
      if (!Number.isFinite(span) || !Number.isFinite(height) || span > 128) { return null; }
      let available: number = 0;
      while (available < span) {
        if (cursor + available >= 128) { return null; }
        if ((until[cursor + available] ?? 0) > r) { cursor += available + 1; available = 0; }
        else { available++; }
      }
      cells.push({ cell, row: r, column: cursor, rows: height, columns: span });
      for (let c: number = cursor; c < cursor + span; c++) { until[c] = r + height; }
      cursor += span; columns = Math.max(columns, cursor);
    }
  }
  return { cells, columns, rows: rows.length };
}
