import { common2D } from '@kit.ArkGraphics2D';
import { DrawnReactionChip, DrawnReactionPlan } from './DrawnReactionLayout';

export const REACTION_MOTION_MS: number = 180;

export interface ReactionMotionItem {
  chip: DrawnReactionChip;
  previous: DrawnReactionChip | null;
  progress: number;
  entering: boolean;
  leaving: boolean;
  direction: number;
  countChanged: boolean;
  selectionChanged: boolean;
  x: number;
  y: number;
  scale: number;
  fill: common2D.Color;
  // Scalar/color snapshots only; no paragraph or shape is created by animation.
  fromFill: common2D.Color;
  startedAt: number;
  linearProgress: number;
}

function sameColor(a: common2D.Color, b: common2D.Color): boolean {
  return a.alpha === b.alpha && a.red === b.red && a.green === b.green && a.blue === b.blue;
}
function copyColor(color: common2D.Color): common2D.Color {
  return { alpha: color.alpha, red: color.red, green: color.green, blue: color.blue };
}
function setColor(target: common2D.Color, source: common2D.Color): void {
  target.alpha = source.alpha; target.red = source.red; target.green = source.green; target.blue = source.blue;
}
function interpolateColor(target: common2D.Color, from: common2D.Color, to: common2D.Color, progress: number): void {
  target.alpha = Math.round(from.alpha + (to.alpha - from.alpha) * progress);
  target.red = Math.round(from.red + (to.red - from.red) * progress);
  target.green = Math.round(from.green + (to.green - from.green) * progress);
  target.blue = Math.round(from.blue + (to.blue - from.blue) * progress);
}
function samePresentation(a: DrawnReactionChip, b: DrawnReactionChip): boolean {
  return a.reaction?.count === b.reaction?.count && a.reaction?.isChosen === b.reaction?.isChosen &&
    (a.count === null) === (b.count === null) && a.avatarCount === b.avatarCount && sameColor(a.fill, b.fill);
}
function itemFor(chip: DrawnReactionChip, previous: DrawnReactionChip | null, from: common2D.Color,
  now: number, entering: boolean, leaving: boolean, animated: boolean): ReactionMotionItem {
  const countChanged = previous !== null && chip.reaction?.count !== previous.reaction?.count;
  const selectionChanged = previous !== null && chip.reaction?.isChosen !== previous.reaction?.isChosen;
  return { chip, previous: animated ? previous : null, progress: animated ? 0 : 1,
    entering: animated && entering, leaving: animated && leaving,
    direction: animated && countChanged ? ((chip.reaction?.count ?? 0) > (previous?.reaction?.count ?? 0) ? 1 : -1) : 0,
    countChanged: animated && countChanged, selectionChanged: animated && selectionChanged,
    x: chip.x, y: chip.y, scale: animated && entering ? .75 : 1,
    fill: copyColor(animated ? from : chip.fill), fromFill: copyColor(from),
    startedAt: now, linearProgress: animated ? 0 : 1 };
}

// One immutable plan revision costs O(Rold + Rnew), using key lookup rather
// than scanning old buttons for every new button. Cold/recycled bindings settle
// immediately. Only current live chips and one generation of exits are held.
export class ReactionMotion {
  items: ReactionMotionItem[] = [];
  private byKey: Map<string, ReactionMotionItem> = new Map();
  private plan: DrawnReactionPlan | null = null;
  private owner: string = '';
  private environment: string = '';
  private running: boolean = false;

  bind(plan: DrawnReactionPlan, owner: string, now: number, animate: boolean, environment: string = ''): string {
    const sameOwner = this.plan !== null && this.owner === owner && this.environment === environment;
    if (sameOwner && this.plan === plan) {
      if (!animate && this.running) { this.finish(); }
      return '';
    }
    const allowed = sameOwner && animate && Number.isFinite(now);
    if (this.running) { this.sample(now); }
    const next: ReactionMotionItem[] = [];
    const nextByKey: Map<string, ReactionMotionItem> = new Map();
    let selected = '', running = false;
    for (const chip of plan.chips) {
      const old = sameOwner ? this.byKey.get(chip.key) : undefined;
      let item: ReactionMotionItem;
      if (allowed && old !== undefined && samePresentation(old.chip, chip)) {
        // Resource-only updates or reflow do not restart an existing counter or
        // color transition. Geometry is final immediately, matching avatar islands.
        item = old; item.chip = chip; item.x = chip.x; item.y = chip.y;
      } else {
        const changed = old === undefined || !samePresentation(old.chip, chip);
        const moving = allowed && changed && chip.reaction !== null;
        item = itemFor(chip, old?.chip ?? null, old?.fill ?? chip.fill, now, old === undefined, false, moving);
        if (moving && chip.reaction?.isChosen === true && old?.chip.reaction?.isChosen !== true) { selected = chip.key; }
      }
      running = running || item.progress < 1;
      next.push(item); nextByKey.set(chip.key, item);
    }
    if (allowed) {
      this.byKey.forEach((old: ReactionMotionItem, key: string): void => {
        if (!nextByKey.has(key) && old.chip.reaction !== null) {
          next.push(itemFor(old.chip, null, old.fill, now, false, true, true)); running = true;
        }
      });
    }
    this.items = next; this.byKey = nextByKey; this.plan = plan;
    this.owner = owner; this.environment = environment; this.running = running;
    return selected;
  }

  // O(R) scalar updates while active; O(1) when settled. The array, colors,
  // paragraphs and shapes retain identity throughout all sampled frames.
  sample(now: number): boolean {
    if (!this.running) { return false; }
    if (!Number.isFinite(now)) { this.finish(); return false; }
    let running = false;
    for (const item of this.items) {
      if (item.progress >= 1) { continue; }
      const linear = Math.max(item.linearProgress, Math.max(0, Math.min(1, (now - item.startedAt) / REACTION_MOTION_MS)));
      item.linearProgress = linear;
      const remaining = 1 - linear;
      item.progress = 1 - remaining * remaining * remaining;
      item.scale = item.entering ? .75 + .25 * item.progress : item.leaving ? 1 - item.progress : 1;
      interpolateColor(item.fill, item.fromFill, item.chip.fill, item.progress);
      running = running || linear < 1;
    }
    this.running = running;
    if (!running) { this.finish(); }
    return running;
  }

  finish(): void {
    let write = 0;
    for (const item of this.items) {
      if (item.leaving) { continue; }
      item.previous = null; item.progress = 1; item.linearProgress = 1;
      item.entering = false; item.leaving = false; item.direction = 0;
      item.countChanged = false; item.selectionChanged = false;
      item.x = item.chip.x; item.y = item.chip.y; item.scale = 1;
      setColor(item.fill, item.chip.fill); setColor(item.fromFill, item.chip.fill);
      this.items[write++] = item;
    }
    this.items.length = write; this.running = false;
  }

  clear(): void {
    this.items.length = 0; this.byKey.clear(); this.plan = null;
    this.owner = ''; this.environment = ''; this.running = false;
  }
}
