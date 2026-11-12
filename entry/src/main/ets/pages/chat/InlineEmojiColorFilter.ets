import { ColorMetrics } from '@kit.ArkUI';
import { drawing } from '@kit.ArkGraphics2D';

// Two text colors at most (body/link) per owner. Rebuild on appearance epoch,
// including same Resource references resolving to a different dark-mode color.
export class InlineEmojiColorFilters {
  private epoch: number = -1;
  private filters: Map<ResourceColor, drawing.ColorFilter> = new Map<ResourceColor, drawing.ColorFilter>();
  private identity: ColorFilter | null = null;

  get(repaint: boolean, color: ResourceColor, epoch: number): ColorFilter | drawing.ColorFilter {
    if (!repaint) {
      if (this.identity === null) {
        this.identity = new ColorFilter([1, 0, 0, 0, 0, 0, 1, 0, 0, 0,
          0, 0, 1, 0, 0, 0, 0, 0, 1, 0]);
      }
      return this.identity;
    }
    if (this.epoch !== epoch) { this.epoch = epoch; this.filters.clear(); }
    const cached = this.filters.get(color);
    if (cached !== undefined) { return cached; }
    const c = ColorMetrics.resourceColor(color);
    const filter = drawing.ColorFilter.createBlendModeColorFilter(
      { alpha: c.alpha, red: c.red, green: c.green, blue: c.blue }, drawing.BlendMode.SRC_IN);
    if (this.filters.size >= 2) { this.filters.clear(); }
    this.filters.set(color, filter);
    return filter;
  }
}
