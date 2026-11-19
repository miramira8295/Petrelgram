import { DrawContext, UIContext } from '@kit.ArkUI';
import { common2D, drawing } from '@kit.ArkGraphics2D';
import { DrawnReactionPlan, DrawnReactionChip } from './DrawnReactionLayout';
import { ReactionMotion, ReactionMotionItem } from './ReactionMotion';
import { ReactionImage, ReactionAnimationSource } from './ReactionImage';
import { DrawnReactionAvatarsPainter } from './DrawnReactionAvatarsPainter';
import { DrawnFrameBatch } from '../../util/drawnFrameBatch';
import { OneShotFrameCallback } from '../../util/oneShotFrameCallback';

export interface ReactionOverlay { key: string; source: ReactionAnimationSource; serial: number; }
// All ordinary chip pixels live on one bounded canvas. Frames, bitmap delivery
// and press feedback never invalidate the text/footer/media foreground modifier.
export class DrawnReactionsPainter extends DrawModifier {
  private motion: ReactionMotion = new ReactionMotion();
  private images: Map<string, ReactionImage> = new Map();
  private avatars: Map<string, DrawnReactionAvatarsPainter> = new Map();
  private ui: UIContext | null = null;
  private plan: DrawnReactionPlan | null = null;
  private owner: string = '';
  private environment: string = '';
  private density: number = 0;
  private active: boolean = false;
  private animate: boolean = false;
  private offPress: (() => void) | null = null;
  private brush: drawing.Brush = new drawing.Brush();
  private pen: drawing.Pen = new drawing.Pen();
  private counterClip: common2D.Rect = { left: 0, top: 0, right: 0, bottom: 0 };
  private pressedFill: common2D.Color = { alpha: 28, red: 0, green: 0, blue: 0 };
  private frames: DrawnFrameBatch = new DrawnFrameBatch();
  private hiddenIconKey: string = '';
  private overlayKey: string = '';
  private serial: number = 0;
  private onOverlay: (value: ReactionOverlay | null) => void;
  constructor(onOverlay: (value: ReactionOverlay | null) => void) {
    super(); this.onOverlay = onOverlay; this.brush.setAntiAlias(true); this.pen.setAntiAlias(true);
  }
  bind(ui: UIContext, plan: DrawnReactionPlan, owner: string, environment: string,
    density: number, active: boolean, animate: boolean): void {
    const reset = this.owner !== owner || this.environment !== environment || this.density !== density || this.ui !== ui;
    if (reset) { this.dispose(); this.ui = ui; this.owner = owner; this.environment = environment; this.density = density; this.pen.setStrokeWidth(density); }
    const changed = this.plan !== plan;
    if (!changed && this.active === active && this.animate === animate && !reset) { return; }
    if (changed) {
      this.offPress?.(); this.offPress = plan.onPress((): void => this.invalidate());
    }
    this.active = active; this.animate = animate; this.plan = plan;
    const selected = this.motion.bind(plan, owner, Date.now(), active && animate, environment);
    if (!active) { this.releaseImages(); this.stopOverlay(); this.motion.finish(); this.frames.cancel(); this.invalidate(); return; }
    if (!animate) { this.stopOverlay(); this.motion.finish(); }
    this.prepareImages();
    if (this.overlayKey !== '' && plan.byKey.get(this.overlayKey)?.reaction?.isChosen !== true) { this.stopOverlay(); }
    if (selected !== '') { this.play(selected); }
    this.requestFrame();
  }
  private prepareImages(): void {
    const ui = this.ui;
    if (ui === null) { return; }
    const alive: Set<string> = new Set();
    for (const item of this.motion.items) {
      const chip = item.chip, reaction = chip.reaction;
      if (reaction === null) { continue; }
      alive.add(chip.key);
      let icon = this.images.get(chip.key);
      if (icon === undefined) {
        icon = new ReactionImage(ui, chip.key, reaction.emoji, this.density, this.environment,
          chip.foreground, (): void => this.requestFrame(), chip.emoji ?? undefined);
        this.images.set(chip.key, icon); icon.start(reaction.customEmojiPath);
      } else { icon.update(chip.foreground, reaction.customEmojiPath); }
      let avatar = this.avatars.get(chip.key);
      if (chip.avatarCount > 0) {
        if (avatar === undefined) {
          avatar = new DrawnReactionAvatarsPainter((): void => this.invalidate()); this.avatars.set(chip.key, avatar);
        }
        avatar.bind(ui, reaction.recentSenders ?? [], `${this.owner}:${chip.key}`, this.environment);
      } else if (avatar !== undefined) { avatar.dispose(); this.avatars.delete(chip.key); }
    }
    this.images.forEach((icon: ReactionImage, key: string): void => { if (!alive.has(key)) { icon.dispose(); this.images.delete(key); } });
    this.avatars.forEach((avatar: DrawnReactionAvatarsPainter, key: string): void => { if (!alive.has(key)) { avatar.dispose(); this.avatars.delete(key); } });
  }
  private requestFrame(): void {
    const ui = this.ui;
    if (ui === null || !this.active) { return; }
    this.frames.request((task: () => void): void => ui.postFrameCallback(new OneShotFrameCallback(task)), (): void => {
      const running = this.motion.sample(Date.now()); this.invalidate();
      if (running && this.animate) { this.requestFrame(); }
      else { this.pruneExits(); }
    });
  }
  private pruneExits(): void {
    const plan = this.plan;
    this.images.forEach((icon: ReactionImage, key: string): void => { if (!plan?.byKey.has(key)) { icon.dispose(); this.images.delete(key); } });
    this.avatars.forEach((avatar: DrawnReactionAvatarsPainter, key: string): void => { if (!plan?.byKey.has(key)) { avatar.dispose(); this.avatars.delete(key); } });
  }
  private play(key: string): void {
    this.stopOverlay(); this.overlayKey = key;
    const serial = this.serial, icon = this.images.get(key);
    icon?.play((source: ReactionAnimationSource): void => {
      if (serial !== this.serial || !this.active || !this.animate || this.plan?.byKey.get(key)?.reaction?.isChosen !== true) { return; }
      this.onOverlay({ key, source, serial });
    });
  }
  overlayStarted(key: string): void {
    if (this.active && this.overlayKey === key && this.hiddenIconKey !== key) { this.hiddenIconKey = key; this.invalidate(); }
  }
  stopOverlay(): void {
    if (this.hiddenIconKey !== '') { this.hiddenIconKey = ''; this.invalidate(); }
    this.serial++; this.images.get(this.overlayKey)?.cancelAnimation(); this.overlayKey = ''; this.onOverlay(null);
  }
  private releaseImages(): void {
    this.images.forEach((icon: ReactionImage): void => icon.dispose()); this.images.clear();
    this.avatars.forEach((avatar: DrawnReactionAvatarsPainter): void => avatar.dispose()); this.avatars.clear();
  }
  dispose(): void {
    this.active = false; this.frames.cancel(); this.stopOverlay(); this.offPress?.(); this.offPress = null;
    this.releaseImages(); this.motion.clear(); this.plan = null; this.ui = null; this.owner = ''; this.environment = ''; this.invalidate();
  }
  drawBehind(context: DrawContext): void {
    const c = context.canvas, d = this.density;
    for (const item of this.motion.items) {
      if (item.scale <= 0) { continue; }
      const chip = item.chip;
      c.save(); c.translate(item.x * d, item.y * d);
      if (item.scale !== 1) { c.translate(chip.width * d / 2, chip.height * d / 2); c.scale(item.scale, item.scale); c.translate(-chip.width * d / 2, -chip.height * d / 2); }
      if (chip.reaction === null) {
        this.pen.setColor(chip.foreground); c.attachPen(this.pen);
        c.drawLine(9 * d, (chip.height / 2 - 4) * d, 13 * d, chip.height * d / 2);
        c.drawLine(13 * d, chip.height * d / 2, 9 * d, (chip.height / 2 + 4) * d); c.detachPen();
      } else {
        this.brush.setColor(item.fill); c.attachBrush(this.brush); c.drawRoundRect(chip.background); c.detachBrush();
        c.save(); c.translate(8 * d, (chip.height - 20) * d / 2);
        if (item.selectionChanged && chip.reaction.isChosen && item.progress < 1) {
          const pulse = 1 + .12 * Math.sin(Math.PI * item.progress);
          c.translate(10 * d, 10 * d); c.scale(pulse, pulse); c.translate(-10 * d, -10 * d);
        }
        const icon = this.images.get(chip.key);
        if (this.hiddenIconKey !== chip.key) {
          if (icon !== undefined) { icon.draw(context); }
          else { chip.emoji?.paragraph.paint(c, 0, (20 * d - chip.emoji.heightPx) / 2); }
        }
        c.restore();
        this.paintCounter(context, item);
        const avatar = this.avatars.get(chip.key);
        if (avatar !== undefined) { c.save(); c.translate(chip.countX * d, (chip.height - 20) * d / 2); avatar.drawBehind(context); c.restore(); }
        if (this.plan?.pressedKey === chip.key) {
          this.brush.setColor(this.pressedFill); c.attachBrush(this.brush); c.drawRoundRect(chip.background); c.detachBrush();
        }
      }
      c.restore();
    }
  }
  private paintCounter(context: DrawContext, item: ReactionMotionItem): void {
    const chip = item.chip, count = chip.count, c = context.canvas, d = this.density;
    if (count === null) { return; }
    const x = chip.countX * d, y = (chip.height * d - count.heightPx) / 2;
    const old = item.previous?.count;
    if (!item.countChanged || old === null || old === undefined || item.progress >= 1) { count.paragraph.paint(c, x, y); return; }
    this.counterClip.left = x; this.counterClip.top = 0; this.counterClip.right = chip.width * d; this.counterClip.bottom = chip.height * d;
    c.save(); c.clipRect(this.counterClip);
    const travel = chip.height * d * item.direction;
    old.paragraph.paint(c, x, (chip.height * d - old.heightPx) / 2 - travel * item.progress);
    count.paragraph.paint(c, x, y + travel * (1 - item.progress)); c.restore();
  }
}
