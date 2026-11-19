import { DrawContext, UIContext } from '@kit.ArkUI';
import { common2D, drawing } from '@kit.ArkGraphics2D';
import { GiveawayAudience } from '../../util/giveawayAudience';
import { DrawnTextUnits } from '../../util/drawnTextUnits';
import { DrawnFrameBatch } from '../../util/drawnFrameBatch';
import { OneShotFrameCallback } from '../../util/oneShotFrameCallback';
import { AVATAR_PALETTE, COLOR_PRIMARY } from '../../util/theme';
import { str } from '../../util/strings';
import { DrawnImageReceiver } from '../common/DrawnImageReceiver';
import { DrawnTextLine, DrawnTextLineCache, drawnColor } from './DrawnTextLine';

export class DrawnGiveawayPeerSlot {
  readonly id: number;
  readonly user: boolean;
  readonly key: string;
  readonly receiver: DrawnImageReceiver = new DrawnImageReceiver();
  name: string = '';
  label: DrawnTextLine | null = null;
  initials: DrawnTextLine | null = null;
  x: number = 0;
  y: number = 0;
  width: number = 0;
  height: number = 0;
  background: drawing.RoundRect | null = null;
  colorIndex: number;
  constructor(id: number, user: boolean) {
    this.id = id; this.user = user; this.key = `${user ? 'u' : 'c'}${id}`;
    this.colorIndex = Math.abs(id) % AVATAR_PALETTE.length;
  }
}
interface DrawnGiveawayPeerRow { start: number; end: number; top: number; height: number; width: number; }

// ChatMessageCell/GiveawayMessageCell: prepare text, greedily wrap avatar/name
// chips, then publish height. Only a real name-wrap change updates outer height;
// image pixels and byte progress are paint-only. No measured-height feedback.
@ObservedV2
export class DrawnGiveawayAudienceLayout {
  @Trace height: number = 0;
  readonly width: number;
  readonly density: number;
  readonly slots: DrawnGiveawayPeerSlot[] = [];
  private rows: DrawnGiveawayPeerRow[] = [];
  private ui: UIContext;
  private units: DrawnTextUnits = new DrawnTextUnits();
  private environment: string;
  private labels: Map<string, DrawnTextLine> = new Map();
  private initialsLabels: Map<string, DrawnTextLine> = new Map();
  private nameChanges: Map<number, string> = new Map();
  private namesFrame: DrawnFrameBatch = new DrawnFrameBatch();
  private listeners: Set<() => void> = new Set();
  private pillBrush: drawing.Brush = new drawing.Brush();
  private pressedBrush: drawing.Brush = new drawing.Brush();
  private avatarBrushes: drawing.Brush[] = [];
  private foreground: common2D.Color;
  private white: common2D.Color = { alpha: 255, red: 255, green: 255, blue: 255 };
  private avatarClip: drawing.RoundRect;
  private pressed: number = -1;

  constructor(ui: UIContext, audience: GiveawayAudience, width: number, environment: string) {
    this.ui = ui; this.width = Math.max(1, width); this.environment = environment;
    this.units.prepare(ui, environment); this.density = this.units.density;
    this.foreground = drawnColor(COLOR_PRIMARY);
    this.pillBrush.setAntiAlias(true); this.pillBrush.setColor(drawnColor('#143390EC'));
    this.pressedBrush.setAntiAlias(true); this.pressedBrush.setColor(drawnColor('#303390EC'));
    for (const color of AVATAR_PALETTE) {
      const brush = new drawing.Brush(); brush.setAntiAlias(true); brush.setColor(drawnColor(color)); this.avatarBrushes.push(brush);
    }
    const d = this.density;
    this.avatarClip = new drawing.RoundRect({ left: 0, top: 0, right: 24 * d, bottom: 24 * d }, 12 * d, 12 * d);
    for (const id of audience.chatIds) { this.slots.push(new DrawnGiveawayPeerSlot(id, false)); }
    for (const id of audience.winnerUserIds) { this.slots.push(new DrawnGiveawayPeerSlot(id, true)); }
    for (const slot of this.slots) { this.prepareName(slot, ''); }
    this.repack();
  }
  onPaint(listener: () => void): () => void { this.listeners.add(listener); return (): void => { this.listeners.delete(listener); }; }
  invalidate(): void { this.listeners.forEach((listener: () => void): void => listener()); }
  setPressed(index: number): void { if (this.pressed !== index) { this.pressed = index; this.invalidate(); } }
  queueName(index: number, name: string): void {
    const slot = this.slots[index];
    if (slot === undefined || (this.nameChanges.get(index) ?? slot.name) === name) { return; }
    this.nameChanges.set(index, name);
    this.namesFrame.request((task: () => void): void => this.ui.postFrameCallback(new OneShotFrameCallback(task)), (): void => {
      this.nameChanges.forEach((value: string, at: number): void => { this.prepareName(this.slots[at], value); });
      this.nameChanges.clear(); this.repack(); this.invalidate();
    });
  }
  cancelPending(): void { this.namesFrame.cancel(); this.nameChanges.clear(); this.setPressed(-1); }
  private label(content: string, initials: boolean): DrawnTextLine {
    const cache = initials ? this.initialsLabels : this.labels, hit = cache.get(content);
    if (hit !== undefined) { return hit; }
    const d = this.density;
    const result = new DrawnTextLineCache().prepare(content, initials ? 22 * d : Math.max(1, Math.min(this.width * .8, this.width - 40) * d),
      this.units.fp2px(11.5), initials ? this.white : this.foreground, this.environment, true);
    if (cache.size >= 512) { cache.delete(cache.keys().next().value as string); }
    cache.set(content, result); return result;
  }
  private prepareName(slot: DrawnGiveawayPeerSlot, name: string): void {
    slot.name = name;
    const display = name || str(slot.user ? 'cb_telegram_user' : 'bu_unknown_channel');
    slot.label = this.label(display, false);
    const point = name.codePointAt(0);
    slot.initials = this.label(point === undefined ? '?' : String.fromCodePoint(point).toUpperCase(), true);
  }
  private repack(): void {
    const d = this.density, limit = this.width * .9;
    const rows: DrawnGiveawayPeerRow[] = [];
    let row: DrawnGiveawayPeerRow = { start: 0, end: 0, top: 0, height: 0, width: 0 };
    for (let i = 0; i < this.slots.length; i++) {
      const slot = this.slots[i];
      const width = Math.min(this.width, (slot.label?.widthPx ?? 0) / d + 40);
      const height = Math.max(30, (slot.label?.heightPx ?? 0) / d + 8);
      // Keep channels and winners as separate sections while using the same
      // linear packing algorithm. A long single chip can occupy its own row.
      const section = i > 0 && slot.user !== this.slots[i - 1].user;
      if (i > row.start && (row.width + 6 + width > limit || section)) {
        rows.push(row);
        row = { start: i, end: i, top: row.top + row.height + 6, height: 0, width: 0 };
      }
      slot.x = row.width + (i > row.start ? 6 : 0); slot.y = row.top;
      slot.width = width; slot.height = height;
      row.width = slot.x + width; row.height = Math.max(row.height, height); row.end = i + 1;
    }
    if (row.end > row.start) { rows.push(row); }
    // Each slot is visited once more, not a rows×members cross-product.
    for (const line of rows) {
      const offset = (this.width - line.width) / 2;
      for (let i = line.start; i < line.end; i++) {
        const slot = this.slots[i]; slot.x += offset; slot.y += (line.height - slot.height) / 2;
        slot.background = new drawing.RoundRect({ left: slot.x * d, top: slot.y * d,
          right: (slot.x + slot.width) * d, bottom: (slot.y + slot.height) * d }, 15 * d, 15 * d);
      }
    }
    this.rows = rows;
    const height = rows.length === 0 ? 0 : row.top + row.height;
    if (this.height !== height) { this.height = height; }
  }
  hit(x: number, y: number): number {
    if (!Number.isFinite(x) || !Number.isFinite(y)) { return -1; }
    let lo = 0, hi = this.rows.length - 1;
    while (lo <= hi) {
      const mid = (lo + hi) >>> 1, row = this.rows[mid];
      if (y < row.top) { hi = mid - 1; continue; }
      if (y > row.top + row.height) { lo = mid + 1; continue; }
      let left = row.start, right = row.end - 1;
      while (left <= right) {
        const at = (left + right) >>> 1, slot = this.slots[at];
        if (x < slot.x) { right = at - 1; }
        else if (x > slot.x + slot.width) { left = at + 1; }
        else { return y >= slot.y && y <= slot.y + slot.height ? at : -1; }
      }
      return -1;
    }
    return -1;
  }
  paint(context: DrawContext): void {
    const c = context.canvas, d = this.density;
    for (let i = 0; i < this.slots.length; i++) {
      const slot = this.slots[i];
      if (slot.background !== null) {
        c.attachBrush(i === this.pressed ? this.pressedBrush : this.pillBrush); c.drawRoundRect(slot.background); c.detachBrush();
      }
      const avatarX = (slot.x + 3) * d, avatarY = (slot.y + (slot.height - 24) / 2) * d;
      c.save(); c.translate(avatarX, avatarY); c.clipRoundRect(this.avatarClip);
      c.attachBrush(this.avatarBrushes[slot.colorIndex]); c.drawCircle(12 * d, 12 * d, 12 * d); c.detachBrush();
      slot.initials?.paragraph.paint(c, (24 * d - slot.initials.widthPx) / 2, (24 * d - slot.initials.heightPx) / 2);
      slot.receiver.drawFront(context); c.restore();
      slot.label?.paragraph.paint(c, (slot.x + 32) * d, (slot.y + slot.height / 2) * d - slot.label.heightPx / 2);
    }
  }
}

export class DrawnGiveawayAudiencePainter extends DrawModifier {
  private model: DrawnGiveawayAudienceLayout | null = null;
  bind(model: DrawnGiveawayAudienceLayout): DrawnGiveawayAudiencePainter {
    if (this.model !== model) { this.model = model; this.invalidate(); } return this;
  }
  drawBehind(context: DrawContext): void { this.model?.paint(context); }
}

export class DrawnGiveawayAudienceLayouts {
  private ui: UIContext | null = null;
  private audience: GiveawayAudience | undefined = undefined;
  private width: number = 0;
  private environment: string = '';
  private current: DrawnGiveawayAudienceLayout | null = null;
  prepare(ui: UIContext, audience: GiveawayAudience | undefined, width: number, environment: string): DrawnGiveawayAudienceLayout | null {
    if (this.ui === ui && this.audience === audience && this.width === width && this.environment === environment) { return this.current; }
    this.ui = ui; this.audience = audience; this.width = width; this.environment = environment;
    this.current = audience && audience.chatIds.length + audience.winnerUserIds.length > 0
      ? new DrawnGiveawayAudienceLayout(ui, audience, width, environment) : null;
    return this.current;
  }
}
