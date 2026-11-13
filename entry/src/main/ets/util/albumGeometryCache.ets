import { AlbumCell, packAlbumRows } from './packAlbumRows';

// Pure vp geometry, shared across physical row owners. Never retains messages,
// paths, bitmaps, selection or playback state. Consumers must not mutate cells.
// At most 64 entries AND 512 cells; oversized/malformed input is not retained.
// The owner's warm path bypasses this pool. A cold key costs O(N); packing and
// cell binding stay O(N), with no scan through all cached albums.
export class AlbumGeometryCache {
  private entries: Map<string, AlbumCell[][]> = new Map<string, AlbumCell[][]>();
  private cells: number = 0;

  prepare(ratios: number[], width: number): AlbumCell[][] {
    if (ratios.length === 0 || ratios.length > 32 || !Number.isFinite(width) ||
      !ratios.every((ratio: number): boolean => Number.isFinite(ratio))) {
      return packAlbumRows(ratios, width);
    }
    const key = `${width}:${ratios.join(',')}`;
    const hit = this.entries.get(key);
    if (hit !== undefined) {
      this.entries.delete(key); this.entries.set(key, hit);
      return hit;
    }
    const rows = packAlbumRows(ratios, width);
    this.entries.set(key, rows); this.cells += ratios.length;
    while (this.entries.size > 64 || this.cells > 512) {
      const oldest = this.entries.keys().next().value as string;
      const removed = this.entries.get(oldest);
      this.entries.delete(oldest);
      if (removed !== undefined) {
        for (const row of removed) { this.cells -= row.length; }
      }
    }
    return rows;
  }
}

export const albumGeometryCache: AlbumGeometryCache = new AlbumGeometryCache();
