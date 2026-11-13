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
  radius: number;
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
      const radius = single ? 0 : 6;
      for (let i = 0; i < tiles.length; i++) {
        const tile = tiles[i], old = this.frames[i];
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
