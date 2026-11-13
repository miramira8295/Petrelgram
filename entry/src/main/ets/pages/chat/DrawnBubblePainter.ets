import { DrawnInvalidation, DrawnStage, drawnStageMetrics } from '../../util/drawnStageMetrics';
import { DrawContext } from '@kit.ArkUI';
import { common2D, drawing } from '@kit.ArkGraphics2D';
import { DrawnBubblePlan } from './DrawnBubblePlan';
import { DrawnMediaController } from './DrawnMediaController';
import { DrawnRichHit } from '../../util/drawnRichTextPolicy';
import { DrawnChromePainter } from './DrawnChromePainter';
import { DrawnReactionChip } from './DrawnReactionLayout';

// Two paint passes around the native transition anchors: background before
// photos, text/status after photos. Neither pass builds paragraphs or geometry.
export class DrawnBubblePainter extends DrawModifier {
  private plan: DrawnBubblePlan | null = null;
  private brush: drawing.Brush = new drawing.Brush();
  private shadow: drawing.Brush = new drawing.Brush();
  private shadowOn: boolean = false;

  constructor() {
    super();
    this.brush.setAntiAlias(true); this.shadow.setAntiAlias(true);
    this.shadow.setColor({ alpha: 20, red: 0, green: 0, blue: 0 });
  }

  bind(plan: DrawnBubblePlan | null, shadowOn: boolean): DrawnBubblePainter {
    if (plan === this.plan && this.shadowOn === shadowOn) { drawnStageMetrics.skip(DrawnStage.Background); return this; }
    const traced = drawnStageMetrics.begin(DrawnStage.Background);
    try {
      if (plan !== null && plan.density !== this.plan?.density) {
        this.shadow.setMaskFilter(drawing.MaskFilter.createBlurMaskFilter(drawing.BlurType.NORMAL,
          (2 * .57735 + .5) * plan.density));
      }
      drawnStageMetrics.invalidated(plan !== this.plan ? DrawnInvalidation.BackgroundPlan : DrawnInvalidation.Shadow);
      this.plan = plan; this.shadowOn = shadowOn;
      this.invalidate(); return this;
    } finally { drawnStageMetrics.end(traced); }
  }

  drawBehind(context: DrawContext): void {
    const p = this.plan;
    if (p === null) { return; }
    const traced = drawnStageMetrics.begin(DrawnStage.BackgroundPaint);
    try {
      const c = context.canvas, d = p.density;
      c.save(); c.translate(p.bubbleX * d, p.bubbleY * d);
      if (this.shadowOn) {
        c.save(); c.translate(0, d); c.attachBrush(this.shadow);
        c.drawPath(p.outline); c.detachBrush(); c.restore();
      }
      this.brush.setColor(p.fill); c.attachBrush(this.brush);
      c.drawPath(p.outline); c.detachBrush(); c.restore();
    } finally { drawnStageMetrics.end(traced); }
  }
}

// Avatar stays outside the bubble's jump/delete transform, matching the native
// row. Still a plain draw modifier: no LiveSenderAvatar/CachedImage components.
export class DrawnBubbleAvatar extends DrawModifier {
  private plan: DrawnBubblePlan | null = null;
  private media: DrawnMediaController | null = null;
  private brush: drawing.Brush = new drawing.Brush();
  constructor() { super(); this.brush.setAntiAlias(true); }
  bind(plan: DrawnBubblePlan | null, media: DrawnMediaController): DrawnBubbleAvatar {
    if (plan !== this.plan || media !== this.media) {
      const traced = drawnStageMetrics.begin(DrawnStage.Avatar);
      try {
        if (plan !== null && plan.avatar.width > 0) { this.avatarClip(plan); }
        this.plan = plan; this.media = media;
        drawnStageMetrics.invalidated(DrawnInvalidation.AvatarPlan); this.invalidate();
      } finally { drawnStageMetrics.end(traced); }
    } else { drawnStageMetrics.skip(DrawnStage.Avatar); }
    return this;
  }
  drawBehind(context: DrawContext): void {
    const p = this.plan;
    if (p === null) { return; }
    const traced = drawnStageMetrics.begin(DrawnStage.AvatarPaint);
    try {
      const c = context.canvas, d = p.density;
      if (p.avatar.width > 0) {
        c.save(); c.translate(p.avatar.x * d, p.avatar.y * d);
        this.brush.setColor(p.avatarColor); c.attachBrush(this.brush);
        c.drawCircle(19 * d, 19 * d, 19 * d); c.detachBrush();
        if (p.initials !== null && !this.media?.avatarHasPath) {
          p.initials.paragraph.paint(c, (38 * d - p.initials.widthPx) / 2,
            (38 * d - p.initials.heightPx) / 2);
        }
        // The clip is prepared during bind, never during painting.
        if (this.avatarRound !== null) { c.clipRoundRect(this.avatarRound); }
        this.media?.avatar.drawFront(context);
        c.restore();
      }
    } finally { drawnStageMetrics.end(traced); }
  }

  private avatarRound: drawing.RoundRect | null = null;
  private avatarDensity: number = 0;
  private avatarClip(p: DrawnBubblePlan): drawing.RoundRect {
    // Prepared before painting; draw never allocates a native clip.
    if (this.avatarRound === null || this.avatarDensity !== p.density) {
      this.avatarDensity = p.density;
      this.avatarRound = new drawing.RoundRect({ left: 0, top: 0,
        right: 38 * p.density, bottom: 38 * p.density }, 19 * p.density, 19 * p.density);
    }
    return this.avatarRound;
  }
}

export class DrawnBubbleForeground extends DrawModifier {
  private chromePainter: DrawnChromePainter = new DrawnChromePainter();
  private pressedReaction: DrawnReactionChip | null = null;
  private plan: DrawnBubblePlan | null = null;
  private sendState: string = '';
  private footerPaintKey: string = '';
  private brush: drawing.Brush = new drawing.Brush();
  private pen: drawing.Pen = new drawing.Pen();
  private pressed: DrawnRichHit | null = null;
  private statusPen: drawing.Pen = new drawing.Pen();
  private strokeDensity: number = 0;
  private statusWidth: number = 0;
  private selectionRound: boolean = false;

  constructor() {
    super();
    this.brush.setAntiAlias(true); this.pen.setAntiAlias(true); this.statusPen.setAntiAlias(true);
    this.statusPen.setCapStyle(drawing.CapStyle.ROUND_CAP);
  }

  private preparePens(plan: DrawnBubblePlan): void {
    if (this.strokeDensity !== plan.density) {
      this.pen.setStrokeWidth(plan.density); this.strokeDensity = plan.density;
    }
    const width = Math.max(plan.density, plan.statusSize * plan.density / 10);
    if (this.statusWidth !== width) { this.statusPen.setStrokeWidth(width); this.statusWidth = width; }
    this.chromePainter.bind(plan.density);
  }

  bind(plan: DrawnBubblePlan | null, state: string, footerPaintKey: string = ''): DrawnBubbleForeground {
    if (this.plan !== plan || this.sendState !== state || this.footerPaintKey !== footerPaintKey) {
      const traced = drawnStageMetrics.begin(DrawnStage.Foreground);
      try {
        if (plan !== null) { this.preparePens(plan); }
        drawnStageMetrics.invalidated(this.plan !== plan ? DrawnInvalidation.ForegroundPlan
          : this.sendState !== state ? DrawnInvalidation.Status : DrawnInvalidation.Footer);
        this.plan = plan; this.sendState = state; this.footerPaintKey = footerPaintKey; this.pressed = null; this.pressedReaction = null; this.invalidate();
      } finally { drawnStageMetrics.end(traced); }
    } else { drawnStageMetrics.skip(DrawnStage.Foreground); }
    return this;
  }
  press(hit: DrawnRichHit | null): void {
    const clearReaction = hit === null && this.pressedReaction !== null;
    if (clearReaction || hit !== this.pressed) {
      if (clearReaction) { this.pressedReaction = null; }
      this.pressed = hit; drawnStageMetrics.invalidated(DrawnInvalidation.Press); this.invalidate();
    }
  }
  pressReaction(chip: DrawnReactionChip | null): void {
    if (chip !== this.pressedReaction) { this.pressedReaction = chip; drawnStageMetrics.invalidated(DrawnInvalidation.Press); this.invalidate(); }
  }
  drawBehind(context: DrawContext): void {
    const p = this.plan;
    if (p === null) { return; }
    const traced = drawnStageMetrics.begin(DrawnStage.ForegroundPaint);
    try {
      const c = context.canvas, d = p.density;
      if (p.chrome !== null) { this.chromePainter.paint(c, p.chrome, d, p.accent, p.secondary, this.pressedReaction); }
      if (p.header !== null) {
        c.save(); c.translate(p.headerX * d, p.headerY * d);
        p.header.paint(c, this.brush); c.restore();
      }
      if (p.quote !== null && p.quoteBackground !== null) {
        c.save(); c.translate(p.quoteRect.x * d, p.quoteRect.y * d);
        p.quote.paint(c, this.brush, p.quoteBackground, p.quoteStripe, p.quoteClip); c.restore();
      }
      if (p.caption !== null) {
        p.caption.paragraph.paint(c, p.captionX * d, p.captionY * d);
      }
      if (p.footerBackdrop !== null) {
        this.brush.setColor({ alpha: 102, red: 0, green: 0, blue: 0 });
        c.attachBrush(this.brush); c.drawRoundRect(p.footerBackdrop); c.detachBrush();
      }
      if (p.footer !== null) {
        p.footer.paragraph.paint(c, (p.footerX + p.footerTextOffset) * d, p.footerY * d);
        if (p.views) { this.eye(c, p); }
        if (p.outgoing && this.sendState !== '' && this.sendState !== 'none') { this.status(c, p); }
      }
      // Selection is paint-only and O(N); no Circle/Symbol subtree per tile.
      for (const tile of p.tiles) {
        if (!tile.cell.selectionActive) { continue; }
        const x = (tile.x + tile.width - 16) * d, y = (tile.y + 16) * d;
        this.brush.setColor(tile.cell.selected ? p.accent : { alpha: 77, red: 0, green: 0, blue: 0 });
        c.attachBrush(this.brush); c.drawCircle(x, y, 10 * d); c.detachBrush();
        this.pen.setColor({ alpha: 255, red: 255, green: 255, blue: 255 });
        c.attachPen(this.pen); c.drawCircle(x, y, 10 * d);
        if (tile.cell.selected) {
          c.drawLine(x - 5 * d, y, x - d, y + 4 * d);
          c.drawLine(x - d, y + 4 * d, x + 5 * d, y - 4 * d);
        }
        c.detachPen();
      }
      if (this.pressed !== null) {
        const h = this.pressed;
        this.brush.setColor({ alpha: 45, red: 51, green: 144, blue: 236 });
        c.attachBrush(this.brush);
        c.save(); c.translate((p.captionX + h.x) * d, (p.captionY + h.y) * d);
        // A drawRect is supplied by the cached native hit geometry below.
        if (this.pressRect !== null) { c.drawRect(this.pressRect); }
        c.restore(); c.detachBrush();
      }
    } finally { drawnStageMetrics.end(traced); }
  }

  private pressRect: common2D.Rect | null = null;
  setPress(hit: DrawnRichHit | null, density: number): void {
    this.pressRect = hit === null ? null : { left: 0, top: 0,
      right: hit.widthVp * density, bottom: hit.heightVp * density };
    this.press(hit);
  }
  private eye(c: drawing.Canvas, p: DrawnBubblePlan): void {
    const d = p.density, x = (p.footerX + 5) * d, y = (p.footerY + 6) * d;
    this.pen.setColor(p.secondary);
    c.attachPen(this.pen);
    c.drawOval(p.footerEye);
    c.drawCircle(x, y, 1.5 * d); c.detachPen();
  }
  private status(c: drawing.Canvas, p: DrawnBubblePlan): void {
    const d = p.density, size = p.statusSize * d;
    const x = p.statusX * d, y = p.statusY * d;
    // Preserve the existing shared pen's sticky round caps for selection after
    // the first status draw, without changing width between paint operations.
    if (!this.selectionRound) {
      this.pen.setCapStyle(drawing.CapStyle.ROUND_CAP); this.selectionRound = true;
    }
    this.statusPen.setColor(this.sendState === 'failed' ? { alpha: 255, red: 255, green: 0, blue: 0 }
      : (this.sendState === 'read' && !p.onMedia ? p.accent : p.secondary));
    c.attachPen(this.statusPen);
    if (this.sendState === 'sending') {
      c.drawCircle(x + size / 2, y + size / 2, size * .4);
      c.drawLine(x + size / 2, y + size * .24, x + size / 2, y + size / 2);
      c.drawLine(x + size / 2, y + size / 2, x + size * .72, y + size / 2);
    } else if (this.sendState === 'failed') {
      c.drawCircle(x + size / 2, y + size / 2, size * .4);
      c.drawLine(x + size / 2, y + size * .24, x + size / 2, y + size * .52);
      c.drawLine(x + size / 2, y + size * .73, x + size / 2, y + size * .74);
    } else {
      c.drawLine(x + size * .12, y + size * .53, x + size * .4, y + size * .78);
      c.drawLine(x + size * .4, y + size * .78, x + size * .9, y + size * .22);
      if (this.sendState === 'read') {
        c.drawLine(x + size * .52, y + size * .68, x + size * .73, y + size * .78);
        c.drawLine(x + size * .73, y + size * .78, x + size * 1.23, y + size * .22);
      }
    }
    c.detachPen();
  }
}
