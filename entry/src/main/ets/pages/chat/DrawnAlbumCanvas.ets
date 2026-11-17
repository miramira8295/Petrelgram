import { DrawnStage, drawnStageMetrics } from '../../util/drawnStageMetrics';
import { DrawContext, UIContext } from '@kit.ArkUI';
import { drawing } from '@kit.ArkGraphics2D';
import { DrawnBubbleTile, DrawnTileCorners } from './DrawnBubblePlan';
import { DrawnImageSlot } from './DrawnMediaController';
import { DrawnFrameBatch } from '../../util/drawnFrameBatch';
import { OneShotFrameCallback } from '../../util/oneShotFrameCallback';

@ObservedV2
class DrawnAlbumCanvasState {
  @Trace ready: boolean = false;
}

interface DrawnAlbumCanvasClip {
  corners: DrawnTileCorners | undefined;
  x: number;
  y: number;
  width: number;
  height: number;
  density: number;
  round: drawing.RoundRect;
}

// Only fully drawable static albums use this host. Loading/upload/retry/native
// fallback retain the original per-image nodes and their individual progress.
// No bitmap ownership: slots keep using CachedImageSession's ref-counted cache.
export class DrawnAlbumCanvas extends DrawModifier {
  readonly state: DrawnAlbumCanvasState = new DrawnAlbumCanvasState();
  private ui: UIContext | null = null;
  private tiles: DrawnBubbleTile[] | null = null;
  private slots: DrawnImageSlot[] | null = null;
  private density: number = 0;
  // Once a mounted message needs per-image nodes, keep that branch until its
  // owner changes or the row recycles. Late bitmap arrivals must not tear down
  // the grid; cached albums can still enter the canvas path on their next bind.
  private nativeOnly: boolean = false;
  private sendingOwner: string = '';
  private clips: DrawnAlbumCanvasClip[] = [];
  private batch: DrawnFrameBatch = new DrawnFrameBatch();
  private brush: drawing.Brush | null = null;
  private schedule = (task: () => void): void => { this.ui?.postFrameCallback(new OneShotFrameCallback(task)); };
  private publish = (): void => {
    if (this.ui === null) { return; }
    this.updateReady();
    this.invalidate();
  };

  bind(ui: UIContext, tiles: DrawnBubbleTile[], slots: DrawnImageSlot[], density: number, enabled: boolean, forceNative: boolean = false, ownerKey: string = ''): void {
    if (forceNative || this.sendingOwner !== '') {
      const owner = ownerKey || tiles.map((tile: DrawnBubbleTile): string => `${tile.cell.chatId}:${tile.cell.messageId}`).join('|');
      if (forceNative) { this.sendingOwner = owner; }
      else if (this.sendingOwner !== owner) { this.sendingOwner = ''; }
      forceNative = forceNative || (owner !== '' && this.sendingOwner === owner);
    }
    if (!enabled || tiles.length < 2 || tiles.length > 10 || slots.length !== tiles.length) { this.reset(true); return; }
    if (this.ui === ui && this.tiles === tiles && this.slots === slots && this.density === density) {
      if (forceNative && !this.nativeOnly) {
        this.nativeOnly = true;
        if (this.state.ready) { this.state.ready = false; this.invalidate(); }
      }
      return;
    }
    const traced = drawnStageMetrics.begin(DrawnStage.AlbumCanvasBind);
    try {
      for (const tile of tiles) {
        const cell = tile.cell;
        if (cell.isVideo || cell.isLive || cell.uploading || cell.failed || tile.opaque === false) { this.reset(true); return; }
      }
      this.batch.cancel();
      let sameOwner = this.tiles !== null && this.tiles.length === tiles.length;
      if (sameOwner && this.tiles !== null) {
        for (let i = 0; i < tiles.length; i++) {
          if (this.tiles[i].cell.chatId !== tiles[i].cell.chatId ||
            this.tiles[i].cell.messageId !== tiles[i].cell.messageId) {
            sameOwner = false; break;
          }
        }
      }
      if (!sameOwner) { this.nativeOnly = false; }
      if (forceNative) { this.nativeOnly = true; this.state.ready = false; }
      if (this.brush === null) {
        this.brush = new drawing.Brush(); this.brush.setAntiAlias(true);
        this.brush.setColor({ alpha: 255, red: 215, green: 220, blue: 226 });
      }
      this.ui = ui; this.tiles = tiles; this.slots = slots; this.density = density;
      // O(N) on geometry changes; reuse clips across messages of the same size.
      // Coordinates are grid-relative nativeTiles, not the row-relative hit rects.
      for (let i = 0; i < tiles.length; i++) {
        const tile = tiles[i], old = this.clips[i];
        if (old !== undefined && old.x === tile.x * density && old.y === tile.y * density &&
          old.width === tile.width && old.height === tile.height && old.density === density && old.corners === tile.corners) { continue; }
        const radius = Math.min(4, tile.width / 2, tile.height / 2) * density;
        const round = new drawing.RoundRect({ left: 0, top: 0, right: tile.width * density, bottom: tile.height * density }, radius, radius);
        const corners = tile.corners;
        if (corners !== undefined) {
          round.setCorner(drawing.CornerPos.TOP_LEFT_POS, corners.topLeft * density, corners.topLeft * density);
          round.setCorner(drawing.CornerPos.TOP_RIGHT_POS, corners.topRight * density, corners.topRight * density);
          round.setCorner(drawing.CornerPos.BOTTOM_LEFT_POS, corners.bottomLeft * density, corners.bottomLeft * density);
          round.setCorner(drawing.CornerPos.BOTTOM_RIGHT_POS, corners.bottomRight * density, corners.bottomRight * density);
        }
        this.clips[i] = { corners, x: tile.x * density, y: tile.y * density, width: tile.width, height: tile.height, density,
          round };
      }
      this.clips.length = tiles.length;
      this.updateReady();
      this.invalidate();
    } finally { drawnStageMetrics.end(traced); }
  }

  // O(1) per bitmap delivery; readiness scan and invalidation once per frame.
  // Bitmap upgrades need this callback even when the placeholder state is stable.
  imageChanged(): void {
    if (this.ui !== null && !this.nativeOnly) { this.batch.request(this.schedule, this.publish); }
  }

  private updateReady(): void {
    if (this.nativeOnly) { return; }
    let ready = this.tiles !== null && this.slots !== null && this.tiles.length === this.slots.length;
    if (ready && this.slots !== null) {
      for (const slot of this.slots) {
        if (slot.path === '' || slot.pixels === undefined || !slot.receiver.canDraw(slot.pixels, ImageFit.Cover)) {
          ready = false; break;
        }
      }
    }
    if (!ready) { this.nativeOnly = true; }
    if (this.state.ready !== ready) { this.state.ready = ready; }
  }

  drawFront(context: DrawContext): void {
    // ready controls the UI branch, whose replacement may commit after this
    // native paint. Keep covering the outgoing geometry in that interval.
    // reset clears all image references; only its bounded clips/brush survive.
    if (this.brush === null) { return; }
    const traced = drawnStageMetrics.begin(DrawnStage.AlbumCanvasPaint);
    try {
      const canvas = context.canvas;
      // O(N), N <= 10. No allocation, decoding, image metadata queries or layout.
      for (let i = 0; i < this.clips.length; i++) {
        const clip = this.clips[i];
        canvas.save();
        try {
          canvas.translate(clip.x, clip.y);
          canvas.clipRoundRect(clip.round, drawing.ClipOp.INTERSECT, true);
          canvas.attachBrush(this.brush); canvas.drawRoundRect(clip.round); canvas.detachBrush();
          this.slots?.[i]?.receiver.drawFront(context);
        } finally { canvas.restore(); }
      }
    } finally { drawnStageMetrics.end(traced); }
  }

  reset(preserveSendingOwner: boolean = false): void {
    if (!preserveSendingOwner) { this.sendingOwner = ''; }
    this.nativeOnly = false;
    this.batch.cancel(); this.ui = null; this.tiles = null; this.slots = null;
    if (this.state.ready) { this.state.ready = false; this.invalidate(); }
    // Retain at most ten geometry-only clips, never images or message objects.
  }
}
