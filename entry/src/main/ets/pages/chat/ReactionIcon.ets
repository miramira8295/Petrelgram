import { DrawContext } from '@kit.ArkUI';
import { ReactionInfo } from '../../store/MessageEntry';
import { reactionKeyFrom } from '../../util/reactions';
import { reactionForeground } from '../../util/reactionPresentation';
import { chatEnv } from '../../util/chatEnvMirror';
import { textMeasureEnvironment } from '../../util/textMeasureCache';
import { subscribeChatAnimationGate } from '../../util/chatAnimationGate';
import { scrollActiveNow } from '../../util/scrollEffects';
import { DrawnFrameBatch } from '../../util/drawnFrameBatch';
import { OneShotFrameCallback } from '../../util/oneShotFrameCallback';
import { drawnColor } from './DrawnTextLine';
import { ReactionImage, ReactionAnimationSource } from './ReactionImage';
import { ReactionAnimationView } from './ReactionAnimationView';
import { logW } from '../../util/log';

class ReactionIconPainter extends DrawModifier {
  private image: ReactionImage | null = null;
  private density: number = 1;
  private hidden: boolean = false;
  private pulseStarted: number = -1;
  private scale: number = 1;
  bind(image: ReactionImage | null, density: number = 1): void {
    this.density = density;
    if (this.image !== image) { this.image = image; this.invalidate(); }
  }
  startPulse(): void { this.pulseStarted = Date.now(); this.scale = 1; }
  advancePulse(): boolean {
    if (this.pulseStarted < 0) { return false; }
    const progress = Math.max(0, Math.min(1, (Date.now() - this.pulseStarted) / 180));
    this.scale = 1 + .12 * Math.sin(Math.PI * progress);
    if (progress >= 1) { this.pulseStarted = -1; this.scale = 1; }
    return this.pulseStarted >= 0;
  }
  showMovie(): void {
    this.hidden = true; this.pulseStarted = -1; this.scale = 1; this.invalidate();
  }
  reset(): void {
    const changed = this.hidden || this.scale !== 1;
    this.hidden = false; this.pulseStarted = -1; this.scale = 1;
    if (changed) { this.invalidate(); }
  }
  drawBehind(context: DrawContext): void {
    if (this.hidden || this.image === null) { return; }
    if (this.scale === 1) { this.image.draw(context); return; }
    const canvas = context.canvas, center = 10 * this.density;
    canvas.save(); canvas.translate(center, center); canvas.scale(this.scale, this.scale);
    canvas.translate(-center, -center); this.image.draw(context); canvas.restore();
  }
}

// Pixel arrivals and playback touch this 20vp leaf only. A reaction-count or
// selected-state update retains the same metadata/file/decoder subscription.
@ComponentV2
export struct ReactionIcon {
  @Require @Param reaction: ReactionInfo;
  @Param outgoing: boolean = false;
  @Param ownerKey: string = '';
  @Local private playbackSource: ReactionAnimationSource | null = null;
  @Local private replay: number = 0;
  private painter: ReactionIconPainter = new ReactionIconPainter();
  private image: ReactionImage | null = null;
  private frame: DrawnFrameBatch = new DrawnFrameBatch();
  private attached: boolean = false;
  private visible: boolean = false;
  private suspended: boolean = true;
  private offGate: (() => void) | null = null;
  private identity: string = '';
  private imageEnvironment: string = '';
  private chosen: boolean = false;
  private generation: number = 0;
  private animationGeneration: number = 0;
  private stopTimer: number = -1;

  @Computed private get environment(): string {
    return `${chatEnv.appearanceEpoch}:${chatEnv.langEpoch}:${textMeasureEnvironment.epoch}`;
  }
  @Computed private get effectPolicy(): number {
    return (chatEnv.chatEffects ? 1 : 0) + (chatEnv.messageEffects ? 2 : 0) +
      (chatEnv.reactionEffects ? 4 : 0) + (chatEnv.animatedEmoji ? 8 : 0) +
      (chatEnv.emojiReactions ? 16 : 0) + (chatEnv.powerSaving ? 32 : 0) +
      (chatEnv.reduceAnim ? 64 : 0) + (chatEnv.appIsForeground ? 128 : 0);
  }
  private mayAnimate(): boolean {
    return this.attached && this.visible && !this.suspended && !scrollActiveNow() && this.effectPolicy === 159;
  }
  private stopAnimation(): void {
    this.animationGeneration++; this.image?.cancelAnimation(); this.painter.reset();
    if (this.stopTimer !== -1) { clearTimeout(this.stopTimer); this.stopTimer = -1; }
    if (this.playbackSource !== null) { this.playbackSource = null; }
  }
  private releaseImage(): void {
    this.stopAnimation(); this.generation++; this.frame.cancel();
    this.painter.bind(null); this.image?.dispose(); this.image = null;
  }
  private bind(allowPlay: boolean): void {
    const key = reactionKeyFrom(this.reaction.emoji, this.reaction.customEmojiId, this.reaction.isPaid === true);
    const identity = `${this.ownerKey}:${key}`;
    const sameOwner = this.identity === identity;
    const newlyChosen = sameOwner && !this.chosen && this.reaction.isChosen;
    const sameEnvironment = this.imageEnvironment === this.environment;
    this.identity = identity; this.chosen = this.reaction.isChosen;
    if (!sameOwner || !sameEnvironment) { this.releaseImage(); this.imageEnvironment = this.environment; }
    if (!this.attached || !this.visible) { return; }
    try {
      const color = drawnColor(reactionForeground(this.outgoing, this.reaction.isChosen));
      if (this.image === null) {
        const ui = this.getUIContext(), token = this.generation, density = ui.vp2px(1);
        this.image = new ReactionImage(ui, key, this.reaction.emoji, density, this.environment, color, (): void => {
          if (!this.attached || !this.visible || token !== this.generation) { return; }
          this.requestPaint();
        });
        this.painter.bind(this.image, density); this.image.start(this.reaction.customEmojiPath);
      } else { this.image.update(color, this.reaction.customEmojiPath); }
      if (!this.reaction.isChosen) { this.stopAnimation(); }
      if (allowPlay && newlyChosen && sameEnvironment && this.mayAnimate()) { this.play(); }
    } catch (error) { this.releaseImage(); logW(`Reaction icon: ${(error as Error).message}`); }
  }
  // Pixels and the finite 180ms pulse share one O(1) frame queue. Only this
  // painter is invalidated; no state write, shape allocation or chip measurement.
  private requestPaint(): void {
    const ui = this.getUIContext();
    this.frame.request((task: () => void): void => ui.postFrameCallback(new OneShotFrameCallback(task)), (): void => {
      if (!this.attached || !this.visible) { return; }
      if (!this.mayAnimate()) { this.painter.reset(); }
      const active = this.painter.advancePulse();
      this.painter.invalidate();
      if (active) { this.requestPaint(); }
    });
  }
  private overlayCallback(started: boolean): () => void {
    const source = this.playbackSource, replay = this.replay;
    const token = this.animationGeneration, identity = this.identity;
    return (): void => {
      if (source === null || source !== this.playbackSource || replay !== this.replay ||
        token !== this.animationGeneration || identity !== this.identity || !this.mayAnimate()) { return; }
      if (started) { this.painter.showMovie(); } else { this.stopAnimation(); }
    };
  }
  private play(): void {
    this.stopAnimation(); this.painter.startPulse(); this.requestPaint();
    const token = this.animationGeneration, identity = this.identity;
    this.image?.play((source: ReactionAnimationSource): void => {
      if (token !== this.animationGeneration || identity !== this.identity || !this.chosen || !this.mayAnimate()) { return; }
      this.playbackSource = source; this.replay++;
      this.stopTimer = setTimeout((): void => {
        if (token === this.animationGeneration) { this.stopAnimation(); }
      }, 3000);
    });
  }
  @Monitor('reaction', 'outgoing', 'ownerKey', 'environment') private sourceChanged(): void { this.bind(true); }
  @Monitor('effectPolicy') private policyChanged(): void { if (!this.mayAnimate()) { this.stopAnimation(); } }
  private appear(): void {
    this.attached = true;
    if (this.offGate === null) {
      this.offGate = subscribeChatAnimationGate((suspended: boolean): void => {
        this.suspended = suspended; if (suspended) { this.stopAnimation(); }
      }, (): boolean => this.visible);
    }
    this.bind(false);
  }
  aboutToAppear(): void { this.appear(); }
  aboutToReuse(): void { this.appear(); }
  aboutToRecycle(): void {
    this.attached = false; this.visible = false; this.releaseImage(); this.identity = ''; this.chosen = false;
    this.offGate?.(); this.offGate = null;
  }
  aboutToDisappear(): void { this.aboutToRecycle(); }
  private visibilityChanged(visible: boolean): void {
    if (this.visible === visible) { return; }
    this.visible = visible;
    if (visible) { this.bind(false); } else { this.releaseImage(); }
  }
  build() {
    Stack() {
      Row().width(20).height(20).drawModifier(this.painter);
      if (this.playbackSource !== null) {
        ReactionAnimationView({ source: this.playbackSource, replayToken: this.replay,
          onStarted: this.overlayCallback(true), onFailed: this.overlayCallback(false) });
      }
    }.width(20).height(20).hitTestBehavior(HitTestMode.None).accessibilityLevel('no')
      .onVisibleAreaChange([0], (visible: boolean): void => this.visibilityChanged(visible));
  }
}
