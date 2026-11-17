import { cornerPx } from '../../util/bubbleCornerInset';
import { DrawnBubbleTile } from './DrawnBubblePlan';
import { thumbBackdropColor } from '../../util/thumbBackdrop';
import { DrawnStage, drawnStageMetrics } from '../../util/drawnStageMetrics';

// Immutable native anchor attributes, deliberately excluding file path,
// progress, selection and playback. A media update must not dirty geometry.
export interface DrawnMediaFrame {
  width: number;
  height: number;
  position: Position;
  backdrop: string;
  radius: number | BorderRadiuses;
  transition: string;
  messageId: number;
  chatId: number;
}

export class DrawnMediaFrames {
  private tiles: DrawnBubbleTile[] | null = null;
  private chatId: number = 0;
  private single: boolean = false;
  private frames: DrawnMediaFrame[] = [];

  prepare(tiles: DrawnBubbleTile[], chatId: number, single: boolean): DrawnMediaFrame[] {
    if (this.tiles === tiles && this.chatId === chatId && this.single === single) {
      drawnStageMetrics.skip(DrawnStage.TileFrames); return this.frames;
    }
    const traced = drawnStageMetrics.begin(DrawnStage.TileFrames);
    try {
      let next: DrawnMediaFrame[] | null = this.frames.length === tiles.length ? null : [];

      for (let i = 0; i < tiles.length; i++) {
        const tile = tiles[i], old = this.frames[i];
        const radius: number | BorderRadiuses = single ? 0 : tile.corners ?? 4;
        const backdrop = thumbBackdropColor(tile.cell.isVideo);
        const transitionEnabled = !tile.cell.isVideo || single;
        const same = old !== undefined && old.width === tile.width && old.height === tile.height &&
          old.position.x === tile.x && old.position.y === tile.y && old.backdrop === backdrop &&
          old.radius === radius && (transitionEnabled ? old.chatId === chatId &&
          old.messageId === tile.cell.messageId && old.transition !== '' : old.transition === '');
        if (!same && next === null) { next = this.frames.slice(0, i); }
        if (next !== null) {
          next.push(same ? old : { width: tile.width, height: tile.height,
            position: { x: tile.x, y: tile.y }, backdrop, radius,
            transition: transitionEnabled ? `media_${chatId}_${tile.cell.messageId}` : '',
            messageId: tile.cell.messageId, chatId });
        }
      }
      if (next !== null) { this.frames = next; }
      this.tiles = tiles; this.chatId = chatId; this.single = single;
      return this.frames;
    } finally { drawnStageMetrics.end(traced); }
  }
}

// Only the clicked image leaves the parent grid clip during a shared-element
// transition. Bake its effective outer corners into this one transient frame.
export function drawnAlbumTransitionFrame(frame: DrawnMediaFrame, tile: DrawnBubbleTile,
  outer: BorderRadiuses): DrawnMediaFrame {
  const mask = tile.edgeMask ?? 0;
  const cap = Math.min(tile.width, tile.height) / 2;
  const corners: BorderRadiuses = {
    topLeft: Math.min(cap, (mask & 3) === 3 ? cornerPx(outer.topLeft) : tile.corners?.topLeft ?? 4),
    topRight: Math.min(cap, (mask & 6) === 6 ? cornerPx(outer.topRight) : tile.corners?.topRight ?? 4),
    bottomLeft: Math.min(cap, (mask & 9) === 9 ? cornerPx(outer.bottomLeft) : tile.corners?.bottomLeft ?? 4),
    bottomRight: Math.min(cap, (mask & 12) === 12 ? cornerPx(outer.bottomRight) : tile.corners?.bottomRight ?? 4)
  };
  return { width: frame.width, height: frame.height, position: frame.position, backdrop: frame.backdrop,
    radius: corners, transition: frame.transition, messageId: frame.messageId, chatId: frame.chatId };
}
