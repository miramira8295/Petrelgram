import { AlbumGroup } from '../../util/collapseAlbums';
import { AlbumCellRenderCache, AlbumCellRenderData } from '../../util/albumCellRenderData';
import { drawnLiveSurface } from '../../util/drawnContentPolicy';
import { MessageBubbleRenderData } from './ReusableMessageBubble';
import { DrawnBubbleTile } from './DrawnBubblePlan';

export interface DrawnAlbumGridPlan {
  width: number;
  height: number;
  density: number;
  tiles: DrawnBubbleTile[];
}

// Only media inputs participate. Caption/translation/reactions/comments and
// the shell policy cannot send the picture grid back through the old cells.
// Published groups/arrays are immutable. Compare the fixed set of array
// references, never stringify their contents. One bounded snapshot per grid.
export class DrawnAlbumGridLayouts {
  private source: AlbumGroup | null = null;
  private selected: number[] | null = null;
  private signature: string = '';
  private previous: DrawnAlbumGridPlan | null = null;
  private cells: AlbumCellRenderCache = new AlbumCellRenderCache(true);
  private preparedRows: AlbumCellRenderData[][] | null = null;

  private sameMedia(a: AlbumGroup, b: AlbumGroup): boolean {
    return a === b || (a.memberIds === b.memberIds && a.photoRatios === b.photoRatios &&
      a.photoPaths === b.photoPaths && a.photoFileIds === b.photoFileIds && a.photoMinis === b.photoMinis &&
      a.photoProgress === b.photoProgress && a.photoFailed === b.photoFailed && a.photoIsVideo === b.photoIsVideo &&
      a.photoIsLive === b.photoIsLive && a.videoFileIds === b.videoFileIds && a.videoFileSizes === b.videoFileSizes &&
      a.videoDurations === b.videoDurations && a.videoMimeTypes === b.videoMimeTypes &&
      a.inlineFileIds === b.inlineFileIds && a.inlineFileSizes === b.inlineFileSizes);
  }

  prepare(group: AlbumGroup, data: MessageBubbleRenderData, width: number, density: number): DrawnAlbumGridPlan {
    const playing = drawnLiveSurface(group, data);
    const slot = playing ? data.playSlotKey : '';
    const signature = `${width}:${density}:${data.chatId}:${group.head.rowId}:${data.selectionActive}:${group.head.sendState === 'sending'}:` +
      `${slot}:${playing && data.autoplayMuted}:${playing ? data.playSlotStartMs : 0}`;
    if (this.previous !== null && this.source !== null && this.signature === signature &&
      this.selected === data.selectedMemberIds && this.sameMedia(this.source, group)) { return this.previous; }
    const rows = this.cells.prepare(group, { chatId: data.chatId, selectionActive: data.selectionActive,
      selectedMemberIds: data.selectedMemberIds, playSlotKey: slot,
      autoplayMuted: data.autoplayMuted, playSlotStartMs: data.playSlotStartMs }, width);
    // A publisher may replace arrays with equal values. The cell cache already
    // compared them once; do not allocate new tiles or wake every image binding.
    if (this.previous !== null && rows === this.preparedRows && this.signature === signature &&
      this.previous.width === width && this.previous.density === density) {
      this.source = group; this.selected = data.selectedMemberIds;
      return this.previous;
    }
    const tiles: DrawnBubbleTile[] = [];
    let rowY = 0;
    let height = 0;
    // One bounded extent pass handles spanning tiles; never scan neighbours
    // for each corner. Outer contour belongs to the parent grid clip.
    for (const row of rows) {
      for (const cell of row) { height = Math.max(height, (cell.gridY ?? rowY) + cell.height); }
      rowY += (row[0]?.height ?? 0) + 2;
    }
    rowY = 0;
    // Rows partition the N cells; this is O(N + S), not N squared.
    for (const row of rows) {
      let rowX = 0;
      for (const cell of row) {
        const x = cell.gridX ?? rowX;
        const y = cell.gridY ?? rowY;
        const left = x < 0.01, top = y < 0.01;
        const right = Math.abs(x + cell.width - width) < 0.01;
        const bottom = Math.abs(y + cell.height - height) < 0.01;
        const edgeMask = (left ? 1 : 0) | (top ? 2 : 0) | (right ? 4 : 0) | (bottom ? 8 : 0);
        const inner = Math.min(4, cell.width / 2, cell.height / 2);
        const old = this.previous?.tiles[tiles.length];
        if (old !== undefined && this.source?.head.rowId === group.head.rowId && old.cell === cell && old.x === x && old.y === y &&
          old.width === cell.width && old.height === cell.height && old.edgeMask === edgeMask) { tiles.push(old); }
        else { tiles.push({ cell, x, y, edgeMask,
          corners: old?.edgeMask === edgeMask && old.width === cell.width && old.height === cell.height ? old.corners : {
            topLeft: left && top ? 0 : inner, topRight: right && top ? 0 : inner,
            bottomLeft: left && bottom ? 0 : inner, bottomRight: right && bottom ? 0 : inner }, width: cell.width, height: cell.height,
          key: `${data.chatId}:${group.head.rowId}:${cell.messageId}:${cell.idx}:${x}:${y}:${cell.width}:${cell.height}:${cell.isVideo}:${cell.isLive}` }); }
        rowX += cell.width + 2;
      }
      rowY += (row[0]?.height ?? 0) + 2;
    }
    const next: DrawnAlbumGridPlan = { width, height, density, tiles };
    this.source = group; this.selected = data.selectedMemberIds; this.signature = signature; this.previous = next;
    this.preparedRows = rows;
    return next;
  }
}
