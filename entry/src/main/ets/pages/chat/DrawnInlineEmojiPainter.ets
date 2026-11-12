import { DrawContext, UIContext } from '@kit.ArkUI';
import { drawing } from '@kit.ArkGraphics2D';
import { CachedImageSpec } from '../../util/cachedImageSpec';
import { CachedImageSession } from '../../util/CachedImageSession';
import { InlineCustomEmojiPaint } from '../../util/inlineCustomEmojiPaint';
import { DrawnImageReceiver } from '../common/DrawnImageReceiver';
import { DrawnInlineEmojiPlacement, DrawnRichTextLayout } from './DrawnRichTextLayout';

// One decoder/cache reference per unique ID, not per occurrence. No PixelMap is
// retained by paragraph caches. The session cancels stale async completions.
class DrawnInlineEmojiAsset {
  readonly receiver: DrawnImageReceiver = new DrawnImageReceiver();
  private session: CachedImageSession;
  private active: boolean = false;
  private disposed: boolean = false;
  ready: boolean = false;
  repaint: boolean = false;

  constructor(invalidate: () => void) {
    this.session = new CachedImageSession((pixels, _ready, width, height): void => {
      if (this.disposed) { return; }
      this.receiver.setPixels(pixels, width, height);
      this.ready = pixels !== undefined && this.receiver.canDraw(pixels, ImageFit.Contain);
      invalidate();
    });
  }

  bind(ui: UIContext, path: string, id: string, plan: DrawnRichTextLayout, repaint: boolean): void {
    this.repaint = repaint;
    this.receiver.bind(ui, plan.emojiSizeVp, plan.emojiSizeVp, ImageFit.Contain, true, plan.density);
    // pixelCache accepts raw local paths, whereas the existing ImageSpan map
    // returns file:// URLs. The shared store still owns download/format mapping.
    const local: string = path.startsWith('file://') ? path.substring(7) : path;
    const spec: CachedImageSpec = { path: local, boxWidth: plan.emojiSizeVp, boxHeight: plan.emojiSizeVp,
      sourceKey: `inline-emoji:${id}`, opaque: false, drawOnCanvas: true, fit: ImageFit.Contain };
    if (this.active) { this.session.update(spec); }
    else { this.active = true; this.session.activate(spec); }
  }

  dispose(): void {
    this.disposed = true; this.ready = false;
    // Clear the drawing reference BEFORE releasing the session's cached handle.
    this.receiver.setPixels(undefined); this.session.dispose();
  }
}

interface DrawnInlineEmojiItem {
  placement: DrawnInlineEmojiPlacement;
  asset: DrawnInlineEmojiAsset;
  tint: drawing.Brush;
}

export class DrawnInlineEmojiPainter extends DrawModifier {
  private plan: DrawnRichTextLayout | null = null;
  private ids: string[] | null = null;
  private paths: string[] | null = null;
  private repaint: boolean[] | null = null;
  private sources: InlineCustomEmojiPaint = new InlineCustomEmojiPaint();
  private assets: Map<string, DrawnInlineEmojiAsset> = new Map();
  private items: DrawnInlineEmojiItem[] = [];
  private repaintLayer = (): void => { this.invalidate(); };

  bind(ui: UIContext, plan: DrawnRichTextLayout | null, ids: string[], paths: string[], repaint: boolean[]): void {
    if (this.plan === plan && this.ids === ids && this.paths === paths && this.repaint === repaint) { return; }
    const changedPlan: boolean = this.plan !== plan;
    this.plan = plan; this.ids = ids; this.paths = paths; this.repaint = repaint;
    this.sources.prepare(ids, paths, repaint);
    if (plan === null) { this.dispose(); return; }
    // O(E + K) on changed input, O(1) for unchanged input. Callback work is O(1),
    // painting O(K), storage O(U + K); E=assets, K=occurrences, U=unique IDs.
    const used = new Set<string>();
    if (changedPlan) { this.items = []; }
    const brushes: Map<string, drawing.Brush> = new Map();
    for (const placement of plan.emojis) {
      let asset = this.assets.get(placement.id);
      if (asset === undefined) { asset = new DrawnInlineEmojiAsset(this.repaintLayer); this.assets.set(placement.id, asset); }
      if (!used.has(placement.id)) {
        used.add(placement.id);
        asset.bind(ui, this.sources.source(placement.id), placement.id, plan,
          this.sources.needsRepainting(placement.id));
      }
      if (changedPlan) {
        const color = placement.color;
        const key: string = `${color.alpha}:${color.red}:${color.green}:${color.blue}`;
        let tint = brushes.get(key);
        if (tint === undefined) {
          tint = new drawing.Brush();
          tint.setColorFilter(drawing.ColorFilter.createBlendModeColorFilter(color, drawing.BlendMode.SRC_IN));
          brushes.set(key, tint);
        }
        this.items.push({ placement, asset, tint });
      }
    }
    this.assets.forEach((asset: DrawnInlineEmojiAsset, id: string): void => {
      if (!used.has(id)) { asset.dispose(); this.assets.delete(id); }
    });
    this.invalidate();
  }

  dispose(): void {
    this.items = []; this.plan = null; this.ids = null; this.paths = null; this.repaint = null;
    this.assets.forEach((asset: DrawnInlineEmojiAsset): void => { asset.dispose(); });
    this.assets.clear(); this.sources = new InlineCustomEmojiPaint();
    this.invalidate();
  }

  drawFront(context: DrawContext): void {
    for (const item of this.items) {
      const p = item.placement;
      if (!item.asset.ready) {
        p.fallback.paint(context.canvas, p.rect.left,
          p.fallbackY);
        continue;
      }
      context.canvas.save(); context.canvas.translate(p.rect.left, p.rect.top);
      if (item.asset.repaint) { context.canvas.attachBrush(item.tint); }
      item.asset.receiver.drawFront(context);
      if (item.asset.repaint) { context.canvas.detachBrush(); }
      context.canvas.restore();
    }
  }
}
