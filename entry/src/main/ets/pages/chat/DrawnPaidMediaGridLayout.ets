import { PaidMediaSet } from '../../util/paidMediaModel';
import { packAndroidAlbumRows } from '../../util/packAlbumRows';

export interface DrawnPaidMediaGridCell {
  index: number;
  x: number;
  y: number;
  width: number;
  height: number;
  corners: BorderRadiuses;
}
export interface DrawnPaidMediaGridPlan {
  width: number;
  height: number;
  cells: DrawnPaidMediaGridCell[];
}

export function paidSingleArtworkHeight(width: number, sourceWidth: number, sourceHeight: number): number {
  if (!Number.isFinite(sourceWidth) || !Number.isFinite(sourceHeight) || sourceWidth <= 0 || sourceHeight <= 0) { return 156; }
  const maximum = Math.min(360, width * 1.2), minimum = Math.min(96, maximum);
  return Math.max(minimum, Math.min(maximum, width * (sourceHeight / sourceWidth)));
}

// One owner, one geometry. File paths, bytes, lock state and payment state are
// excluded. Replaced content snapshots compare their dimensions once, O(N).
export class DrawnPaidMediaGridLayouts {
  private source: PaidMediaSet | null = null;
  private current: DrawnPaidMediaGridPlan | null = null;
  private dimensions: number[] = [];
  prepare(set: PaidMediaSet, width: number): DrawnPaidMediaGridPlan {
    const previous = this.current;
    if (previous !== null && previous.width === width && this.source === set) { return previous; }
    const dimensions: number[] = [], ratios: number[] = [];
    let equal = previous !== null && previous.width === width && this.dimensions.length === set.items.length * 2;
    if (set.items.length === 1 && previous?.height !== paidSingleArtworkHeight(width, set.items[0].width, set.items[0].height)) { equal = false; }
    for (let i = 0; i < set.items.length; i++) {
      const item = set.items[i];
      const w = Number.isFinite(item.width) && item.width > 0 ? item.width : 1;
      const h = Number.isFinite(item.height) && item.height > 0 ? item.height : 1;
      dimensions.push(w, h); ratios.push(w / h);
      if (this.dimensions[i * 2] / this.dimensions[i * 2 + 1] !== w / h) { equal = false; }
    }
    if (equal && previous !== null) { this.source = set; return previous; }
    const cells: DrawnPaidMediaGridCell[] = [];
    let height = 0;
    if (set.items.length === 1) {
      height = paidSingleArtworkHeight(width, set.items[0].width, set.items[0].height);
      cells.push({ index: 0, x: 0, y: 0, width, height, corners: { topLeft: 0, topRight: 0, bottomLeft: 0, bottomRight: 0 } });
    } else {
      const rows = packAndroidAlbumRows(ratios, width);
      let rowY = 0;
      for (const row of rows) {
        let rowX = 0;
        for (const cell of row) {
          const x = cell.x ?? rowX, y = cell.y ?? rowY;
          cells.push({ index: cell.idx, x, y, width: cell.width, height: cell.height, corners: {} });
          height = Math.max(height, y + cell.height); rowX += cell.width + 2;
        }
        rowY += (row[0]?.height ?? 0) + 2;
      }
      // Outer contour is clipped by the parent; internal corners match albums.
      for (const cell of cells) {
        const left = cell.x < .01, right = Math.abs(cell.x + cell.width - width) < .01;
        const top = cell.y < .01, bottom = Math.abs(cell.y + cell.height - height) < .01;
        cell.corners = { topLeft: left && top ? 0 : 4, topRight: right && top ? 0 : 4,
          bottomLeft: left && bottom ? 0 : 4, bottomRight: right && bottom ? 0 : 4 };
      }
    }
    if (!Number.isFinite(height) || height <= 0) { throw new Error('invalid paid media grid'); }
    this.source = set; this.dimensions = dimensions;
    this.current = { width, height, cells };
    return this.current;
  }
}
