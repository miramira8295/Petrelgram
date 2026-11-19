import { DrawContext } from '@kit.ArkUI';
import { common2D, drawing } from '@kit.ArkGraphics2D';
import { drawnColor } from './DrawnTextLine';

// Like Android's SeekBarWaveform: one retained waveform, with played color
// clipped over the unplayed track. No per-bar ArkUI nodes or progress layouts.
// Source/size changes cost O(W); a progress bind is O(1), with O(W) raster work.
export class DrawnAudioWaveform extends DrawModifier {
  private pen: drawing.Pen = new drawing.Pen();
  private path: drawing.Path = new drawing.Path();
  private bars: number[] | null = null;
  private density: number = 0;
  private progress: number = 0;
  private voice: boolean = true;
  private colorEnvironment: string = '';
  private activeKey: ResourceColor = '';
  private inactiveKey: ResourceColor = '';
  private active: common2D.Color = { alpha: 0, red: 0, green: 0, blue: 0 };
  private inactive: common2D.Color = { alpha: 0, red: 0, green: 0, blue: 0 };
  private shapeWidth: number = -1;
  private shapeHeight: number = -1;
  private pitch: number = 0;
  private barWidth: number = 0;
  private clip: common2D.Rect = { left: 0, top: 0, right: 0, bottom: 0 };

  constructor() {
    super();
    this.pen.setAntiAlias(true);
    this.pen.setCapStyle(drawing.CapStyle.ROUND_CAP);
  }

  bind(bars: number[], progress: number, density: number, active: ResourceColor,
    inactive: ResourceColor, voice: boolean, environment: string = ''): DrawnAudioWaveform {
    const next = Number.isFinite(progress) ? Math.max(0, Math.min(1, progress)) : 0;
    let dirty = this.progress !== next;
    if (this.bars !== bars || this.density !== density || this.voice !== voice) {
      this.bars = bars; this.density = density; this.voice = voice;
      this.shapeWidth = -1;
      dirty = true;
    }
    const colorDirty = this.colorEnvironment !== environment;
    this.colorEnvironment = environment;
    if (colorDirty || this.activeKey !== active) { this.activeKey = active; this.active = drawnColor(active); dirty = true; }
    if (colorDirty || this.inactiveKey !== inactive) { this.inactiveKey = inactive; this.inactive = drawnColor(inactive); dirty = true; }
    this.progress = next;
    if (dirty) { this.invalidate(); }
    return this;
  }

  private prepareShape(width: number, height: number): void {
    if (this.shapeWidth === width && this.shapeHeight === height) { return; }
    this.path.reset();
    this.shapeWidth = width; this.shapeHeight = height;
    const bars = this.bars;
    if (bars === null || bars.length === 0) { return; }
    this.pitch = width / bars.length;
    const gap = Math.min(this.pitch / 2, 2 * this.density);
    this.barWidth = Math.max(0.01, this.pitch - gap);
    this.pen.setStrokeWidth(this.barWidth);
    for (let i = 0; i < bars.length; i++) {
      const sample = Number.isFinite(bars[i]) ? bars[i] : 3;
      const barHeight = Math.max(this.barWidth, Math.min(height, Math.max(3, sample) * this.density));
      const x = i * this.pitch + this.barWidth / 2;
      const halfLine = Math.max(0.01, (barHeight - this.barWidth) / 2);
      this.path.moveTo(x, height / 2 - halfLine);
      this.path.lineTo(x, height / 2 + halfLine);
    }
  }

  drawBehind(context: DrawContext): void {
    const bars = this.bars;
    const size = context.sizeInPixel;
    if (!(this.density > 0) || bars === null || bars.length === 0 || !(size.width > 0) || !(size.height > 0)) { return; }
    this.prepareShape(size.width, size.height);
    const canvas = context.canvas;
    this.pen.setColor(this.inactive);
    canvas.attachPen(this.pen); canvas.drawPath(this.path); canvas.detachPen();
    // Preserve the current voice rounding and music's leading active bar.
    const played = this.voice ? Math.round(this.progress * bars.length)
      : Math.min(bars.length, Math.floor(this.progress * bars.length) + 1);
    if (played <= 0) { return; }
    this.clip.right = Math.min(size.width, (played - 1) * this.pitch + this.barWidth);
    this.clip.bottom = size.height;
    canvas.save(); canvas.clipRect(this.clip);
    this.pen.setColor(this.active);
    canvas.attachPen(this.pen); canvas.drawPath(this.path); canvas.detachPen();
    canvas.restore();
  }
}
