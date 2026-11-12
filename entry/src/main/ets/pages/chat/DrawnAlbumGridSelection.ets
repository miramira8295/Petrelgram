import { DrawContext } from '@kit.ArkUI';
import { common2D, drawing } from '@kit.ArkGraphics2D';
import { DrawnAlbumGridPlan } from './DrawnAlbumGridLayout';
import { drawnColor } from './DrawnTextLine';

// Selection is a single overlay. No Circle/Symbol subtree for each photo and
// no native objects or geometry allocation in the draw callback.
export class DrawnAlbumGridSelection extends DrawModifier {
  private plan: DrawnAlbumGridPlan | null = null;
  private brush: drawing.Brush = new drawing.Brush();
  private pen: drawing.Pen = new drawing.Pen();
  private accent: common2D.Color = { alpha: 0, red: 0, green: 0, blue: 0 };
  private environment: number = -1;
  private readonly white: common2D.Color = { alpha: 255, red: 255, green: 255, blue: 255 };
  private readonly empty: common2D.Color = { alpha: 77, red: 0, green: 0, blue: 0 };

  bind(plan: DrawnAlbumGridPlan, environment: number): DrawnAlbumGridSelection {
    let dirty = false;
    if (environment !== this.environment) {
      this.environment = environment; this.accent = drawnColor($r('app.color.primary')); dirty = true;
    }
    if (plan !== this.plan) { this.plan = plan; dirty = true; }
    if (dirty) { this.invalidate(); }
    return this;
  }
  drawBehind(context: DrawContext): void {
    const p = this.plan;
    if (p === null || !p.tiles[0]?.cell.selectionActive) { return; }
    const c = context.canvas, d = p.density;
    this.brush.setAntiAlias(true); this.pen.setAntiAlias(true);
    this.pen.setStrokeWidth(1.5 * d); this.pen.setColor(this.white);
    for (const tile of p.tiles) {
      const x = (tile.x + tile.width - 16) * d, y = (tile.y + 16) * d;
      this.brush.setColor(tile.cell.selected ? this.accent : this.empty);
      c.attachBrush(this.brush); c.drawCircle(x, y, 10 * d); c.detachBrush();
      c.attachPen(this.pen); c.drawCircle(x, y, 10 * d);
      if (tile.cell.selected) {
        c.drawLine(x - 5 * d, y, x - d, y + 4 * d); c.drawLine(x - d, y + 4 * d, x + 5 * d, y - 4 * d);
      }
      c.detachPen();
    }
  }
}
