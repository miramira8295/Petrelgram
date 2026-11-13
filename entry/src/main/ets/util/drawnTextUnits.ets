import { UIContext } from '@kit.ArkUI';

// Owned by one bounded layout engine, not a process-wide UIContext registry.
// Configuration/accepted density changes advance textMeasureEnvironment, which
// callers include in environment. A different UIContext also invalidates it.
// fp conversion can be nonlinear: cache each actual font size, never fp2px(1)*n.
export class DrawnTextUnits {
  density: number = 0;
  private ui: UIContext | null = null;
  private environment: string = '';
  private fonts: Map<number, number> = new Map();

  prepare(ui: UIContext, environment: string): DrawnTextUnits {
    if (this.ui !== ui || this.environment !== environment) {
      const density = ui.vp2px(1);
      if (!Number.isFinite(density) || density <= 0) { throw new Error('invalid drawn density'); }
      this.fonts.clear(); this.density = density;
      this.ui = ui; this.environment = environment;
    }
    return this;
  }

  fp2px(size: number): number {
    const hit = this.fonts.get(size);
    if (hit !== undefined) { return hit; }
    const px = this.ui?.fp2px(size) ?? 0;
    if (!Number.isFinite(px) || px <= 0) { throw new Error('invalid drawn font size'); }
    // Fixed upper bound even while a font-size slider visits many values.
    if (this.fonts.size >= 32) { this.fonts.clear(); }
    this.fonts.set(size, px);
    return px;
  }
}
