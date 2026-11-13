import { DrawnTextUnits } from '../../util/drawnTextUnits';
import { UIContext } from '@kit.ArkUI';
import { common2D, drawing } from '@kit.ArkGraphics2D';
import { ReactionInfo } from '../../store/MessageEntry';
import { DrawnAlbumRect } from '../../util/drawnAlbumPolicy';
import { reactionKeyFrom } from '../../util/reactions';
import { COLOR_PRIMARY, COLOR_TEXT_SECONDARY } from '../../util/theme';
import { DrawnTextLine, DrawnTextLineCache, drawnColor } from './DrawnTextLine';

export interface DrawnReactionChip extends DrawnAlbumRect {
  key: string;
  reaction: ReactionInfo | null;
  emoji: DrawnTextLine | null;
  count: DrawnTextLine | null;
  iconWidth: number;
  background: drawing.RoundRect;
  fill: common2D.Color;
}
interface DrawnReactionBand { y: number; height: number; start: number; end: number; }

export class DrawnReactionPlan {
  chips: DrawnReactionChip[] = [];
  images: DrawnReactionChip[] = [];
  bands: DrawnReactionBand[] = [];
  arrow: DrawnReactionChip | null = null;
  width: number = 0;
  height: number = 0;
  lastRight: number = 0;
  lastHeight: number = 0;

  // Sorted non-overlapping rows/cells: O(log R), including a long wrapped list.
  hit(x: number, y: number): DrawnReactionChip | null {
    let lo = 0, hi = this.bands.length;
    while (lo < hi) {
      const mid = (lo + hi) >>> 1, row = this.bands[mid];
      if (y < row.y) { hi = mid; }
      else if (y >= row.y + row.height) { lo = mid + 1; }
      else {
        lo = row.start; hi = row.end;
        while (lo < hi) {
          const i = (lo + hi) >>> 1, chip = this.chips[i];
          if (x < chip.x) { hi = i; }
          else if (x >= chip.x + chip.width) { lo = i + 1; }
          else { return y < chip.y + chip.height ? chip : null; }
        }
        return null;
      }
    }
    return null;
  }
}

// Bounded slots, not a history-wide Map. Measurement and wrapping are separate:
// a footer/width change can reflow chips without shaping each label again.
export class DrawnReactionLayouts {
  private units: DrawnTextUnits = new DrawnTextUnits();
  private emojis: DrawnTextLineCache[] = [];
  private counts: DrawnTextLineCache[] = [];
  private source: ReactionInfo[] | null = null;
  private metrics: DrawnReactionChip[] = [];
  private metricKey: string = '';
  private natural: number = 0;
  private previous: DrawnReactionPlan | null = null;
  private flowWidth: number = 0;

  measure(ui: UIContext, reactions: ReactionInfo[], maxWidth: number, arrow: boolean,
    environment: string): number {
    this.units.prepare(ui, environment);
    const d = this.units.density, key = `${d}:${this.units.fp2px(13)}:${maxWidth}:${arrow}:${environment}`;
    if (this.source === reactions && this.metricKey === key) { return this.natural; }
    this.emojis.length = Math.min(this.emojis.length, reactions.length);
    this.counts.length = Math.min(this.counts.length, reactions.length);
    const metrics: DrawnReactionChip[] = [];
    let width = 0;
    for (let i = 0; i < reactions.length; i++) {
      const r = reactions[i];
      if (i === this.emojis.length) { this.emojis.push(new DrawnTextLineCache()); this.counts.push(new DrawnTextLineCache()); }
      const count = this.counts[i].prepare(`${r.count}`, Math.max(1, (maxWidth - 37) * d), this.units.fp2px(12),
        drawnColor(r.isChosen ? Color.White : COLOR_TEXT_SECONDARY), environment);
      const emoji = r.customEmojiId === '' ? this.emojis[i].prepare(r.emoji,
        Math.max(1, (maxWidth - 22) * d - count.widthPx), this.units.fp2px(13),
        drawnColor(r.isChosen ? Color.White : COLOR_TEXT_SECONDARY), environment) : null;
      const iconWidth = emoji !== null ? emoji.widthPx / d : 15;
      const chipWidth = Math.min(maxWidth, 22 + iconWidth + count.widthPx / d);
      const height = Math.max(15, emoji !== null ? emoji.heightPx / d : 15, count.heightPx / d) + 8;
      metrics.push({ x: 0, y: 0, width: chipWidth, height, key: reactionKeyFrom(r.emoji, r.customEmojiId),
        reaction: r, emoji, count, iconWidth, background: new drawing.RoundRect({ left: 0, top: 0,
          right: chipWidth * d, bottom: height * d }, height * d / 2, height * d / 2),
        fill: drawnColor(r.isChosen ? COLOR_PRIMARY : $r('app.color.reaction_chip')) });
      width += chipWidth + 4;
    }
    if (arrow && reactions.length > 0) {
      metrics.push({ x: 0, y: 0, width: 24, height: 23, key: 'reactors', reaction: null, emoji: null,
        count: null, iconWidth: 0, background: new drawing.RoundRect({ left: 0, top: 0, right: 0, bottom: 0 }, 0, 0),
        fill: drawnColor(Color.Transparent) });
      width += 28;
    }
    this.source = reactions; this.metricKey = key; this.metrics = metrics;
    this.natural = Math.max(0, width - 4); this.previous = null;
    return this.natural;
  }

  flow(width: number): DrawnReactionPlan {
    if (this.previous !== null && this.flowWidth === width) { return this.previous; }
    const p = new DrawnReactionPlan();
    let x = 0, y = 0, height = 0, start = 0;
    for (const m of this.metrics) {
      if (x > 0 && x + m.width > width) {
        p.bands.push({ y, height, start, end: p.chips.length });
        y += height + 4; x = 0; height = 0; start = p.chips.length;
      }
      const c: DrawnReactionChip = { x, y, width: m.width, height: m.height, key: m.key,
        reaction: m.reaction, emoji: m.emoji, count: m.count, iconWidth: m.iconWidth,
        background: m.background, fill: m.fill };
      p.chips.push(c);
      if (c.reaction === null) { p.arrow = c; }
      else if (c.reaction.customEmojiId !== '') { p.images.push(c); }
      x += m.width + 4; height = Math.max(height, m.height); p.width = Math.max(p.width, x - 4);
    }
    if (p.chips.length > 0) { p.bands.push({ y, height, start, end: p.chips.length }); }
    p.height = y + height; p.lastRight = Math.max(0, x - 4); p.lastHeight = height;
    this.flowWidth = width; this.previous = p; return p;
  }
}
