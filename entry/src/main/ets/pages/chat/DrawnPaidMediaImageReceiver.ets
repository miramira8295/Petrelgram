import { DrawContext } from '@kit.ArkUI';
import { common2D, drawing } from '@kit.ArkGraphics2D';
import { DrawnImageReceiver } from '../common/DrawnImageReceiver';

class DrawnPaidPlayGlyph {
  private background: drawing.Brush = new drawing.Brush();
  private foreground: drawing.Brush = new drawing.Brush();
  private path: drawing.Path = new drawing.Path();
  private width: number = 0;
  private height: number = 0;
  private x: number = 0;
  private y: number = 0;
  private radius: number = 0;
  constructor() {
    const background: common2D.Color = { alpha: 152, red: 0, green: 0, blue: 0 };
    const white: common2D.Color = { alpha: 255, red: 255, green: 255, blue: 255 };
    this.background.setAntiAlias(true); this.background.setColor(background);
    this.foreground.setAntiAlias(true); this.foreground.setColor(white);
  }
  prepare(width: number, height: number, density: number): void {
    const w = width * density, h = height * density;
    if (this.width === w && this.height === h) { return; }
    this.width = w; this.height = h; this.x = w / 2; this.y = h / 2;
    this.radius = Math.min(21 * density, Math.min(w, h) * .2);
    const r = this.radius;
    this.path.buildFromSvgString(`M${this.x - r * .22} ${this.y - r * .42} L${this.x + r * .46} ${this.y} L${this.x - r * .22} ${this.y + r * .42} Z`);
  }
  paint(context: DrawContext): void {
    context.canvas.attachBrush(this.background); context.canvas.drawCircle(this.x, this.y, this.radius); context.canvas.detachBrush();
    context.canvas.attachBrush(this.foreground); context.canvas.drawPath(this.path); context.canvas.detachBrush();
  }
}

export class DrawnPaidMediaImageReceiver extends DrawnImageReceiver {
  private showPlay: boolean = false;
  private glyph: DrawnPaidPlayGlyph | null = null;
  preparePlay(video: boolean, width: number, height: number, density: number): void {
    if (video) {
      if (this.glyph === null) { this.glyph = new DrawnPaidPlayGlyph(); }
      this.glyph.prepare(width, height, density);
    }
    if (this.showPlay !== video) { this.showPlay = video; this.invalidate(); }
  }
  drawFront(context: DrawContext): void {
    super.drawFront(context);
    if (this.showPlay) { this.glyph?.paint(context); }
  }
}
