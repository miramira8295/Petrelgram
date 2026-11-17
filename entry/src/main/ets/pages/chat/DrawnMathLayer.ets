import { DrawContext, UIContext } from '@kit.ArkUI';
import { DrawnImageReceiver } from '../common/DrawnImageReceiver';
import { MathImage, ensureMathImage, mathImageFor } from '../../util/mathImageCache';
import { DrawnMathPlacement } from './DrawnMathPlacement';
import { DrawnRichTextLayout } from './DrawnRichTextLayout';

interface DrawnMathAsset {
  image: MathImage | undefined;
  off: () => void;
}
interface DrawnMathPaintItem {
  placement: DrawnMathPlacement;
  asset: DrawnMathAsset;
  receiver: DrawnImageReceiver;
}
class DrawnMathPainter extends DrawModifier {
  private plan: DrawnRichTextLayout | null = null;
  private assets: Map<string, DrawnMathAsset> = new Map<string, DrawnMathAsset>();
  private items: DrawnMathPaintItem[] = [];
  private revision: number = 0;
  private metricsTimer: number = -1;
  private notify: () => void = (): void => {};
  private scheduleMetrics(): void {
    if (this.metricsTimer >= 0) { return; }
    const owner = this.revision;
    this.metricsTimer = setTimeout((): void => {
      this.metricsTimer = -1;
      if (owner === this.revision && this.plan !== null) { this.notify(); }
    }, 0);
  }
  bind(ui: UIContext, plan: DrawnRichTextLayout | null, notify: () => void): void {
    this.notify = notify;
    if (this.plan === plan) { return; }
    this.dispose(); this.plan = plan; this.notify = notify;
    if (plan === null) { return; }
    const owner = this.revision;
    for (const placement of plan.maths) {
      let asset = this.assets.get(placement.key);
      if (asset === undefined) {
        asset = { image: mathImageFor(placement.key), off: (): void => {} };
        this.assets.set(placement.key, asset);
      }
      const receiver = new DrawnImageReceiver();
      receiver.bind(ui, (placement.rect.right - placement.rect.left) / plan.density,
        (placement.rect.bottom - placement.rect.top) / plan.density, ImageFit.Contain, true, plan.density);
      const item: DrawnMathPaintItem = { placement, asset, receiver };
      this.items.push(item);
      if (asset.image !== undefined) {
        receiver.setPixels(asset.image.pixel, asset.image.width, asset.image.height);
        if (!placement.ready) { this.scheduleMetrics(); }
      }
    }
    // Subscribe once per distinct formula, not once per occurrence.
    const groups: Map<string, DrawnMathPaintItem[]> = new Map<string, DrawnMathPaintItem[]>();
    for (const item of this.items) {
      let group = groups.get(item.placement.key);
      if (group === undefined) { group = []; groups.set(item.placement.key, group); }
      group.push(item);
    }
    groups.forEach((group: DrawnMathPaintItem[], key: string): void => {
      const first = group[0], asset = first.asset;
      if (asset.image !== undefined) { return; }
      asset.off = ensureMathImage(first.placement.expression, first.placement.renderSize, first.placement.color, (): void => {
        if (owner !== this.revision || this.plan !== plan) { return; }
        asset.image = mathImageFor(key);
        if (asset.image !== undefined) {
          let changed: boolean = false;
          for (const item of group) {
            item.receiver.setPixels(asset.image.pixel, asset.image.width, asset.image.height);
            if (!item.placement.ready) { changed = true; }
          }
          if (changed) { this.scheduleMetrics(); }
        }
        this.invalidate();
      });
    });
    this.invalidate();
  }
  dispose(): void {
    this.revision++;
    if (this.metricsTimer >= 0) { clearTimeout(this.metricsTimer); this.metricsTimer = -1; }
    for (const item of this.items) { item.receiver.setPixels(undefined); }
    this.items = [];
    this.assets.forEach((asset: DrawnMathAsset): void => asset.off()); this.assets.clear(); this.plan = null;
  }
  drawFront(context: DrawContext): void {
    for (const item of this.items) {
      const p = item.placement;
      if (item.asset.image === undefined) { p.fallback.paint(context.canvas, p.rect.left, p.fallbackY); continue; }
      context.canvas.save(); context.canvas.translate(p.rect.left, p.rect.top);
      item.receiver.drawFront(context); context.canvas.restore();
    }
  }
}

// One drawing node for all formulas in a paragraph/document. Pixel arrival
// paints locally. Only the first measured size requests a cached layout update.
@ComponentV2
export struct DrawnMathLayer {
  @Require @Param plan: DrawnRichTextLayout | null;
  @Event onMetricsChanged: () => void = (): void => {};
  private painter: DrawnMathPainter = new DrawnMathPainter();
  private attached: boolean = false;
  aboutToAppear(): void { this.attached = true; this.sync(); }
  aboutToDisappear(): void { this.attached = false; this.painter.dispose(); }
  @Monitor('plan')
  sync(): void {
    if (this.attached) { this.painter.bind(this.getUIContext(), this.plan, (): void => this.onMetricsChanged()); }
  }
  build() {
    Row().width(this.plan?.widthVp ?? 0).height(this.plan?.heightVp ?? 0)
      .drawModifier(this.painter).hitTestBehavior(HitTestMode.None).accessibilityLevel('no');
  }
}
