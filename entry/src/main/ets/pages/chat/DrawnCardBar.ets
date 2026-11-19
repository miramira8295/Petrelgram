import { DrawContext, UIContext } from '@kit.ArkUI';
import { common2D, drawing } from '@kit.ArkGraphics2D';
import { DrawnTextUnits } from '../../util/drawnTextUnits';
import { DrawnTextLine, DrawnTextLineCache, drawnColor } from './DrawnTextLine';

export interface DrawnCardBarSpec {
  width: number;
  height: number;
  environment: string;
  left?: string;
  leftPrepared?: DrawnTextLine;
  leftFont?: number;
  leftColor?: ResourceColor;
  right?: string;
  rightFont?: number;
  rightColor?: ResourceColor;
  center?: string;
  centerPrepared?: DrawnTextLine;
  centerFont?: number;
  centerColor?: ResourceColor;
  background?: ResourceColor;
  radius?: number;
  paddingLeft?: number;
  paddingRight?: number;
  paddingBottom?: number;
}

// One small surface for card headers/footers/buttons. Each text slot retains its
// own paragraph; changing a status never reshapes the adjacent stable caption.
export class DrawnCardBar extends DrawModifier {
  private units: DrawnTextUnits = new DrawnTextUnits();
  private leftCache: DrawnTextLineCache = new DrawnTextLineCache();
  private rightCache: DrawnTextLineCache = new DrawnTextLineCache();
  private centerCache: DrawnTextLineCache = new DrawnTextLineCache();
  private left: DrawnTextLine | null = null;
  private right: DrawnTextLine | null = null;
  private center: DrawnTextLine | null = null;
  private brush: drawing.Brush = new drawing.Brush();
  private shape: drawing.RoundRect | null = null;
  private background: common2D.Color = { alpha: 0, red: 0, green: 0, blue: 0 };
  private colorEnvironment: string = '';
  private leftKey: ResourceColor = '';
  private rightKey: ResourceColor = '';
  private centerKey: ResourceColor = '';
  private backgroundKey: ResourceColor = '';
  private leftColor: common2D.Color = { alpha: 0, red: 0, green: 0, blue: 0 };
  private rightColor: common2D.Color = { alpha: 0, red: 0, green: 0, blue: 0 };
  private centerColor: common2D.Color = { alpha: 0, red: 0, green: 0, blue: 0 };
  private density: number = 0;
  private width: number = 0;
  private height: number = 0;
  private radius: number = -1;
  private xLeft: number = 0;
  private xRight: number = 0;
  private bottom: number = 0;

  constructor() { super(); this.brush.setAntiAlias(true); }

  bind(ui: UIContext, spec: DrawnCardBarSpec): DrawnCardBar {
    const units = this.units.prepare(ui, spec.environment), d = units.density;
    const width = Math.max(1, spec.width) * d, height = Math.max(0.01, spec.height) * d;
    const xLeft = (spec.paddingLeft ?? 0) * d, xRight = (spec.paddingRight ?? 0) * d;
    const bottom = (spec.paddingBottom ?? 0) * d;
    const radius = (spec.radius ?? 0) * d;
    let dirty = this.xLeft !== xLeft || this.xRight !== xRight || this.bottom !== bottom;
    const leftKey = spec.leftColor ?? '#000000', rightKey = spec.rightColor ?? '#000000';
    const centerKey = spec.centerColor ?? '#000000', backgroundKey = spec.background ?? '#00000000';
    if (this.leftKey !== leftKey || this.rightKey !== rightKey || this.centerKey !== centerKey ||
      this.backgroundKey !== backgroundKey || this.colorEnvironment !== spec.environment) {
      this.leftKey = leftKey; this.rightKey = rightKey; this.centerKey = centerKey; this.backgroundKey = backgroundKey;
      this.colorEnvironment = spec.environment;
      this.leftColor = drawnColor(leftKey); this.rightColor = drawnColor(rightKey); this.centerColor = drawnColor(centerKey);
      this.background = drawnColor(backgroundKey); dirty = true;
    }
    if (this.width !== width || this.height !== height || this.radius !== radius || this.density !== d) {
      this.width = width; this.height = height; this.radius = radius; this.density = d;
      this.shape = new drawing.RoundRect({ left: 0, top: 0, right: width, bottom: height }, radius, radius); dirty = true;
    }
    this.xLeft = xLeft; this.xRight = xRight; this.bottom = bottom;
    const usable = Math.max(1, width - xLeft - xRight);
    const leftText = spec.left ?? '', rightText = spec.right ?? '', centerText = spec.center ?? '';
    const sideWidth = rightText !== '' && leftText !== '' ? Math.max(1, (usable - 7 * d) / 2) : usable;
    const left = spec.leftPrepared ?? (leftText === '' ? null : this.leftCache.prepare(leftText, sideWidth,
      units.fp2px(spec.leftFont ?? 11), this.leftColor, spec.environment));
    const right = rightText === '' ? null : this.rightCache.prepare(rightText, sideWidth,
      units.fp2px(spec.rightFont ?? 11), this.rightColor, spec.environment);
    const center = spec.centerPrepared ?? (centerText === '' ? null : this.centerCache.prepare(centerText, usable,
      units.fp2px(spec.centerFont ?? 13), this.centerColor, spec.environment, true));
    if (this.left !== left || this.right !== right || this.center !== center) { dirty = true; }
    this.left = left; this.right = right; this.center = center;
    if (dirty) { this.invalidate(); }
    return this;
  }

  drawBehind(context: DrawContext): void {
    const c = context.canvas;
    if (this.shape !== null && this.background.alpha > 0) {
      this.brush.setColor(this.background); c.attachBrush(this.brush); c.drawRoundRect(this.shape); c.detachBrush();
    }
    const available = Math.max(0, this.height - this.bottom);
    this.left?.paragraph.paint(c, this.xLeft, Math.max(0, (available - this.left.heightPx) / 2));
    this.right?.paragraph.paint(c, this.width - this.xRight - this.right.widthPx, Math.max(0, (available - this.right.heightPx) / 2));
    this.center?.paragraph.paint(c, Math.max(this.xLeft, (this.width - this.center.widthPx) / 2),
      Math.max(0, (available - this.center.heightPx) / 2));
  }
}
