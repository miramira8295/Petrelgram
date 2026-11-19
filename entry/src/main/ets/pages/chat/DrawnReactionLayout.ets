import { reactionAvatarCount, reactionAvatarWidth, reactionTotal } from '../../util/reactionSenders';
import { DrawnTextUnits } from '../../util/drawnTextUnits';
import { UIContext } from '@kit.ArkUI';
import { common2D, drawing } from '@kit.ArkGraphics2D';
import { ReactionInfo } from '../../store/MessageEntry';
import { DrawnAlbumRect } from '../../util/drawnAlbumPolicy';
import { reactionKeyFrom } from '../../util/reactions';
import { REACTION_ICON_VP, REACTION_HEIGHT_VP, REACTION_PADDING_VP, reactionCountGap, reactionFill, reactionForeground } from '../../util/reactionPresentation';
import { DrawnTextLine, DrawnTextLineCache, drawnColor } from './DrawnTextLine';

export interface DrawnReactionChip extends DrawnAlbumRect {
  key: string;
  reaction: ReactionInfo | null;
  emoji: DrawnTextLine | null;
  count: DrawnTextLine | null;
  iconWidth: number;
  countX: number;
  avatarCount: number;
  background: drawing.RoundRect;
  fill: common2D.Color;
  foreground: common2D.Color;
}
// ForEach captures its chip value: geometry must participate in the island
// key, otherwise wrapping retains the previous position. Selection does not.
export function reactionAvatarIslandKey(chip: DrawnReactionChip): string {
  return `${chip.key}:${chip.reaction?.recentSenderKey ?? ''}:${chip.x}:${chip.y}:${chip.countX}:${chip.height}`;
}

interface DrawnReactionBand { y: number; height: number; start: number; end: number; }

export class DrawnReactionPlan {
  external: boolean = false;
  readonly byKey: Map<string, DrawnReactionChip> = new Map();
  pressedKey: string = '';
  private pressListeners: Set<() => void> = new Set();
  onPress(listener: () => void): () => void {
    this.pressListeners.add(listener); return (): void => { this.pressListeners.delete(listener); };
  }
  setPressed(key: string): void {
    if (this.pressedKey === key) { return; }
    this.pressedKey = key; this.pressListeners.forEach((listener: () => void): void => listener());
  }
  chips: DrawnReactionChip[] = [];
  images: DrawnReactionChip[] = [];
  avatars: DrawnReactionChip[] = [];
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
  private metricDensity: number = 0;

  measure(ui: UIContext, reactions: ReactionInfo[], maxWidth: number, arrow: boolean,
    environment: string, outgoing: boolean = false, privateChat: boolean = false): number {
    this.units.prepare(ui, environment);
    const d = this.units.density, key = `${d}:${this.units.fp2px(13)}:${maxWidth}:${arrow}:${environment}:${outgoing}:${privateChat}`;
    if (this.source === reactions && this.metricKey === key) { return this.natural; }
    this.emojis.length = Math.min(this.emojis.length, reactions.length);
    this.counts.length = Math.min(this.counts.length, reactions.length);
    const metrics: DrawnReactionChip[] = [];
    // Resolve the four theme colors once per update, not once per chip.
    const normalFill = drawnColor(reactionFill(outgoing, false));
    const selectedFill = drawnColor(reactionFill(outgoing, true));
    const normalText = drawnColor(reactionForeground(outgoing, false));
    const selectedText = drawnColor(reactionForeground(outgoing, true));
    const total = reactionTotal(reactions);
    let width = 0;
    for (let i = 0; i < reactions.length; i++) {
      const r = reactions[i];
      if (i === this.emojis.length) { this.emojis.push(new DrawnTextLineCache()); this.counts.push(new DrawnTextLineCache()); }
      let avatarCount = reactionAvatarCount(r, total, !arrow, privateChat);
      if (REACTION_PADDING_VP + REACTION_ICON_VP + reactionCountGap(r.customEmojiId !== '') + reactionAvatarWidth(avatarCount) > maxWidth) {
        avatarCount = 0; // Narrow panels retain a readable count instead of clipped people.
      }
      const count = avatarCount > 0 ? null : this.counts[i].prepare(`${r.count}`, Math.max(1, (maxWidth - 2 * REACTION_PADDING_VP - REACTION_ICON_VP - reactionCountGap(r.customEmojiId !== '')) * d), this.units.fp2px(12),
        (r.isChosen ? selectedText : normalText), environment, true);
      const emoji = r.customEmojiId === '' ? this.emojis[i].prepare(r.emoji,
        REACTION_ICON_VP * d, REACTION_ICON_VP * d,
        (r.isChosen ? selectedText : normalText), environment, false, REACTION_ICON_VP * d) : null;
      const iconWidth = REACTION_ICON_VP;
      const countX = REACTION_PADDING_VP + iconWidth + reactionCountGap(r.customEmojiId !== '');
      const chipWidth = Math.min(maxWidth, countX + (avatarCount > 0 ? reactionAvatarWidth(avatarCount) : (count?.widthPx ?? 0) / d + REACTION_PADDING_VP));
      // Large accessibility fonts may grow the chip; normal-size chips stay 26vp.
      const height = Math.max(REACTION_HEIGHT_VP, (count?.heightPx ?? 0) / d + 8);
      const old = this.metrics[i];
      const background = old !== undefined && this.metricDensity === d && old.width === chipWidth && old.height === height ? old.background :
        new drawing.RoundRect({ left: 0, top: 0, right: chipWidth * d, bottom: height * d }, height * d / 2, height * d / 2);
      metrics.push({ x: 0, y: 0, width: chipWidth, height, key: reactionKeyFrom(r.emoji, r.customEmojiId, r.isPaid === true),
        reaction: r, emoji, count, iconWidth, countX, avatarCount, background,
        foreground: r.isChosen ? selectedText : normalText, fill: r.isChosen ? selectedFill : normalFill });
      width += chipWidth + 4;
    }
    if (arrow && reactions.length > 0) {
      metrics.push({ x: 0, y: 0, width: 24, height: REACTION_HEIGHT_VP, key: 'reactors', reaction: null, emoji: null,
        count: null, iconWidth: 0, countX: 0, avatarCount: 0, background: new drawing.RoundRect({ left: 0, top: 0, right: 0, bottom: 0 }, 0, 0),
        foreground: normalText, fill: drawnColor(Color.Transparent) });
      width += 28;
    }
    this.source = reactions; this.metricKey = key; this.metricDensity = d; this.metrics = metrics;
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
        reaction: m.reaction, emoji: m.emoji, count: m.count, iconWidth: m.iconWidth, countX: m.countX, avatarCount: m.avatarCount,
        background: m.background, fill: m.fill, foreground: m.foreground };
      p.chips.push(c); p.byKey.set(c.key, c);
      if (c.reaction === null) { p.arrow = c; }
      else if (c.reaction.customEmojiId !== '') { p.images.push(c); }
      if (c.avatarCount > 0) { p.avatars.push(c); }
      x += m.width + 4; height = Math.max(height, m.height); p.width = Math.max(p.width, x - 4);
    }
    if (p.chips.length > 0) { p.bands.push({ y, height, start, end: p.chips.length }); }
    p.height = y + height; p.lastRight = Math.max(0, x - 4); p.lastHeight = height;
    this.flowWidth = width; this.previous = p; return p;
  }
}
