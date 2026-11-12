import { AlbumGroup } from '../../util/collapseAlbums';
import { AlbumCellRenderCache } from '../../util/albumCellRenderData';
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
  private cells: AlbumCellRenderCache = new AlbumCellRenderCache();

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
    const tiles: DrawnBubbleTile[] = [];
    let y = 0;
    // Rows partition the N cells; this is O(N + S), not N squared.
    for (const row of rows) {
      let x = 0;
      for (const cell of row) {
        tiles.push({ cell, x, y, width: cell.width, height: cell.height,
          key: `${data.chatId}:${group.head.rowId}:${cell.messageId}:${cell.idx}:${x}:${y}:${cell.width}:${cell.height}:${cell.isVideo}:${cell.isLive}` });
        x += cell.width + 2;
      }
      y += (row[0]?.height ?? 0) + 2;
    }
    const next: DrawnAlbumGridPlan = { width, height: Math.max(0, y - 2), density, tiles };
    this.source = group; this.selected = data.selectedMemberIds; this.signature = signature; this.previous = next;
    return next;
  }
}
