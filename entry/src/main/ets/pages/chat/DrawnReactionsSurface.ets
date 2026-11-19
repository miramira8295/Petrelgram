import { DrawnReactionPlan, DrawnReactionChip } from './DrawnReactionLayout';
import { DrawnReactionsPainter, ReactionOverlay } from './DrawnReactionsPainter';
import { ReactionAnimationView } from './ReactionAnimationView';
import { chatEnv } from '../../util/chatEnvMirror';
import { textMeasureEnvironment } from '../../util/textMeasureCache';
import { subscribeChatAnimationGate } from '../../util/chatAnimationGate';
import { scrollActiveNow } from '../../util/scrollEffects';
import { logW } from '../../util/log';

@ComponentV2
export struct DrawnReactionsSurface {
  @Param plan: DrawnReactionPlan | null = null;
  @Param ownerKey: string = '';
  @Param density: number = 1;
  @Local private playbackOverlay: ReactionOverlay | null = null;
  private painter: DrawnReactionsPainter = new DrawnReactionsPainter((value: ReactionOverlay | null): void => this.setOverlay(value));
  private attached: boolean = false;
  private visible: boolean = false;
  private gatePaused: boolean = true;
  private offGate: (() => void) | null = null;
  private expiry: number = -1;
  private epoch: number = 0;
  private boundOwner: string = '';
  @Computed private get environment(): string { return `${chatEnv.appearanceEpoch}:${chatEnv.langEpoch}:${textMeasureEnvironment.epoch}`; }
  @Computed private get motionEnabled(): boolean {
    // Read all flags before combining: every switch remains a dependency.
    const chat = chatEnv.chatEffects, message = chatEnv.messageEffects, reaction = chatEnv.reactionEffects;
    const emoji = chatEnv.animatedEmoji, reactions = chatEnv.emojiReactions, power = chatEnv.powerSaving, reduced = chatEnv.reduceAnim, foreground = chatEnv.appIsForeground;
    return chat && message && reaction && emoji && reactions && !power && !reduced && foreground;
  }
  private setOverlay(value: ReactionOverlay | null): void {
    if (this.expiry !== -1) { clearTimeout(this.expiry); this.expiry = -1; }
    if (value === null) { if (this.playbackOverlay !== null) { this.playbackOverlay = null; } return; }
    if (!this.attached || !this.visible || this.gatePaused || !this.motionEnabled || scrollActiveNow()) { return; }
    this.playbackOverlay = value;
    const owner = this.ownerKey, epoch = this.epoch;
    this.expiry = setTimeout((): void => {
      this.expiry = -1;
      if (this.attached && this.ownerKey === owner && this.epoch === epoch && this.playbackOverlay === value) { this.painter.stopOverlay(); }
    }, 3000);
  }
  private syncOwner(): void {
    if (this.boundOwner !== this.ownerKey) { this.epoch++; this.boundOwner = this.ownerKey; }
  }
  private bind(): void {
    this.syncOwner();
    if (!this.attached || this.plan === null) { this.painter.dispose(); return; }
    try {
      this.painter.bind(this.getUIContext(), this.plan, this.ownerKey, this.environment, this.density,
        this.visible, this.motionEnabled && !this.gatePaused && !scrollActiveNow());
    } catch (error) { this.painter.dispose(); logW(`Reaction surface: ${(error as Error).message}`); }
  }
  @Monitor('plan', 'ownerKey', 'density', 'environment', 'motionEnabled') private changed(): void { this.bind(); }
  aboutToAppear(): void {
    this.attached = true;
    if (this.offGate === null) {
      this.offGate = subscribeChatAnimationGate((paused: boolean): void => { this.gatePaused = paused; this.bind(); }, (): boolean => this.visible);
    }
    this.bind();
  }
  aboutToReuse(): void { this.aboutToAppear(); }
  aboutToRecycle(): void {
    this.attached = false; this.visible = false; this.epoch++; this.offGate?.(); this.offGate = null;
    this.painter.dispose(); this.setOverlay(null);
  }
  aboutToDisappear(): void { this.aboutToRecycle(); }
  private visibleCallback(): (visible: boolean) => void {
    // Build may precede appear: both paths establish the same ownership token.
    this.syncOwner();
    const owner = this.ownerKey, epoch = this.epoch;
    return (visible: boolean): void => {
      if (this.ownerKey !== owner || this.epoch !== epoch) { return; }
      this.visible = visible; this.bind();
    };
  }
  private overlayChip(): DrawnReactionChip | undefined { return this.plan?.byKey.get(this.playbackOverlay?.key ?? ''); }
  private started(): () => void {
    const overlay = this.playbackOverlay;
    return (): void => { if (overlay !== null && this.playbackOverlay === overlay) { this.painter.overlayStarted(overlay.key); } };
  }
  private failed(): () => void {
    const overlay = this.playbackOverlay;
    return (): void => { if (this.playbackOverlay === overlay) { this.painter.stopOverlay(); } };
  }
  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.playbackOverlay !== null) {
        ReactionAnimationView({ source: this.playbackOverlay.source, replayToken: this.playbackOverlay.serial, onFailed: this.failed(), onStarted: this.started() })
          .position({ x: (this.overlayChip()?.x ?? 0) + 8,
            y: (this.overlayChip()?.y ?? 0) + ((this.overlayChip()?.height ?? 26) - 20) / 2 });
      }
    }.width(this.plan?.width ?? 0).height(this.plan?.height ?? 0)
    .clip(true).drawModifier(this.painter).hitTestBehavior(HitTestMode.None).accessibilityLevel('no')
    .onVisibleAreaChange([0], this.visibleCallback());
  }
}
