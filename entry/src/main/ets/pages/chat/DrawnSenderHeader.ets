import { UIContext } from '@kit.ArkUI';
import { common2D, drawing } from '@kit.ArkGraphics2D';
import { DrawnTextLine, DrawnTextLineCache, drawnColor } from './DrawnTextLine';

export class DrawnSenderHeader {
  name: DrawnTextLine;
  role: DrawnTextLine | null;
  widthPx: number;
  heightPx: number;
  roleX: number;
  roleY: number;
  density: number;
  background: common2D.Color;
  pill: drawing.RoundRect | null;

  constructor(name: DrawnTextLine, role: DrawnTextLine | null, density: number, background: common2D.Color) {
    this.name = name; this.role = role; this.density = density; this.background = background;
    this.heightPx = Math.max(name.heightPx, role !== null ? role.heightPx + 2 * density : 0);
    this.roleX = name.widthPx + 5 * density;
    this.roleY = role !== null ? (this.heightPx - role.heightPx - 2 * density) / 2 : 0;
    this.widthPx = role !== null ? this.roleX + role.widthPx + 12 * density : name.widthPx;
    this.pill = role !== null ? new drawing.RoundRect({ left: this.roleX, top: this.roleY,
      right: this.widthPx, bottom: this.heightPx - this.roleY }, 7 * density, 7 * density) : null;
  }

  paint(canvas: drawing.Canvas, brush: drawing.Brush): void {
    this.name.paragraph.paint(canvas, 0, (this.heightPx - this.name.heightPx) / 2);
    if (this.role !== null && this.pill !== null) {
      brush.setColor(this.background);
      canvas.attachBrush(brush); canvas.drawRoundRect(this.pill); canvas.detachBrush();
      this.role.paragraph.paint(canvas, this.roleX + 6 * this.density, this.roleY + this.density);
    }
  }
}

export class DrawnSenderHeaderCache {
  private name: DrawnTextLineCache = new DrawnTextLineCache();
  private role: DrawnTextLineCache = new DrawnTextLineCache();
  private current: DrawnSenderHeader | null = null;
  private appearance: string = '';
  private nameColor: ResourceColor = '';
  private tagColor: ResourceColor = '';
  private tagFill: ResourceColor = '';

  prepare(ui: UIContext, name: string, role: string, maxPx: number, nameColor: ResourceColor,
    tagColor: ResourceColor, tagFill: ResourceColor, textEnvironment: string, appearance: string): DrawnSenderHeader {
    const density: number = ui.vp2px(1);
    // Match the native header: the tag keeps its space (55% cap); the name shrinks.
    const tag = role !== '' ? this.role.prepare(role, Math.max(1, maxPx * 0.55 - 12 * density),
      ui.fp2px(11), drawnColor(tagColor), textEnvironment) : null;
    const nameMax: number = maxPx - (tag !== null ? tag.widthPx + 17 * density : 0);
    const sender = this.name.prepare(name, nameMax, ui.fp2px(14), drawnColor(nameColor), textEnvironment, true);
    if (this.current !== null && this.current.name === sender && this.current.role === tag &&
      this.current.density === density && this.appearance === appearance && this.nameColor === nameColor &&
      this.tagColor === tagColor && this.tagFill === tagFill) { return this.current; }
    this.current = new DrawnSenderHeader(sender, tag, density, drawnColor(tagFill));
    this.appearance = appearance; this.nameColor = nameColor; this.tagColor = tagColor; this.tagFill = tagFill;
    return this.current;
  }
}
