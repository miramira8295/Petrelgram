import { DrawContext, UIContext } from '@kit.ArkUI';
import { common2D, drawing } from '@kit.ArkGraphics2D';
import { DrawnTextUnits } from '../../util/drawnTextUnits';
import { DrawnTextLine, DrawnTextLineCache, drawnColor } from './DrawnTextLine';
import { DrawnMediaControl } from './DrawnMediaControl';
import { chatEnv } from '../../util/chatEnvMirror';
import { textMeasureEnvironment } from '../../util/textMeasureCache';
import { str } from '../../util/strings';

// Per failure placeholder, never per loaded tile. No subscriptions, timers or
// click handlers: the existing media host keeps retry/selection/viewer intent.
export class DrawnRetryDecoration extends DrawModifier {
  private units: DrawnTextUnits = new DrawnTextUnits();
  private cache: DrawnTextLineCache = new DrawnTextLineCache();
  private label: DrawnTextLine | null = null;
  private icon: DrawnMediaControl = new DrawnMediaControl();
  private brush: drawing.Brush = new drawing.Brush();
  private background: common2D.Color = { alpha: 0, red: 0, green: 0, blue: 0 };
  private shape: drawing.RoundRect | null = null;
  private density: number = 0;
  private iconSize: number = 0;
  private paddingY: number = 0;
  private environment: string = '';
  private tone: ResourceColor = '';
  private foregroundKey: ResourceColor = '';
  private foregroundColor: common2D.Color = { alpha: 255, red: 255, green: 255, blue: 255 };
  width: number = 0;
  height: number = 0;
  constructor() { super(); this.brush.setAntiAlias(true); }
  bind(ui: UIContext, environment: string, content: string, maxWidth: number, iconSize: number,
    paddingX: number, paddingY: number, tone: ResourceColor, foreground: ResourceColor): DrawnRetryDecoration {
    const units = this.units.prepare(ui, environment), d = units.density;
    const colorDirty = this.environment !== environment || this.foregroundKey !== foreground;
    if (colorDirty) { this.foregroundKey = foreground; this.foregroundColor = drawnColor(foreground); }
    const label = content === '' ? null : this.cache.prepare(content, Math.max(1, maxWidth - 2 * paddingX) * d,
      units.fp2px(11), this.foregroundColor, environment);
    const width = Math.min(Math.max(1, maxWidth), Math.max(iconSize, (label?.widthPx ?? 0) / d) + 2 * paddingX);
    const height = iconSize + (label ? 3 + label.heightPx / d : 0) + 2 * paddingY;
    this.icon.bind(ui, environment, 32, '#00000000', foreground, 'retry');
    const dirty = colorDirty || this.label !== label || this.width !== width || this.height !== height || this.density !== d ||
      this.iconSize !== iconSize || this.paddingY !== paddingY || this.environment !== environment || this.tone !== tone;
    if (!dirty) { return this; }
    this.background = drawnColor(tone);
    this.shape = new drawing.RoundRect({ left: 0, top: 0, right: width * d, bottom: height * d }, 18 * d, 18 * d);
    this.label = label; this.width = width; this.height = height; this.density = d;
    this.iconSize = iconSize; this.paddingY = paddingY; this.environment = environment; this.tone = tone;
    this.invalidate(); return this;
  }
  drawBehind(context: DrawContext): void {
    const c = context.canvas, d = this.density;
    if (this.shape && this.background.alpha > 0) {
      this.brush.setColor(this.background); c.attachBrush(this.brush); c.drawRoundRect(this.shape); c.detachBrush();
    }
    // The retained retry path occupies 20 units of its 32-unit transparent box.
    const scale = this.iconSize / 20;
    c.save(); c.translate((this.width - 32 * scale) * d / 2, (this.paddingY + (this.iconSize - 32 * scale) / 2) * d);
    c.scale(scale, scale); this.icon.drawBehind(context); c.restore();
    this.label?.paragraph.paint(c, (this.width * d - this.label.widthPx) / 2, (this.paddingY + this.iconSize + 3) * d);
  }
}

@ComponentV2
export struct DrawnMediaRetry {
  @Param labelKey: string = 'settings_retry';
  @Param iconSize: number = 17;
  @Param paddingX: number = 7;
  @Param paddingY: number = 7;
  @Param maxWidth: number = 160;
  @Param tone: ResourceColor = '#80000000';
  @Param foreground: ResourceColor = '#FFFFFF';
  private env = chatEnv;
  private painter: DrawnRetryDecoration = new DrawnRetryDecoration();
  private forPaint(): DrawnRetryDecoration {
    return this.painter.bind(this.getUIContext(), `${this.env.appearanceEpoch}:${this.env.langEpoch}:${textMeasureEnvironment.epoch}`,
      this.labelKey ? str(this.labelKey) : '', this.maxWidth, this.iconSize, this.paddingX, this.paddingY, this.tone, this.foreground);
  }
  build() {
    Row().width(this.forPaint().width).height(this.forPaint().height)
      .drawModifier(this.forPaint()).hitTestBehavior(HitTestMode.None).accessibilityLevel('no');
  }
}
