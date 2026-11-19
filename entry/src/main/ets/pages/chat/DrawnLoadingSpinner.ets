import { OneShotFrameCallback } from '../../util/oneShotFrameCallback';
import { chatEnv } from '../../util/chatEnvMirror';
import { textMeasureEnvironment } from '../../util/textMeasureCache';
import { DrawnProgressRing } from './DrawnProgressRing';

// One painted arc + native rotation animation. No timer/frame loop in ArkTS;
// visibility and reduced motion stop the animation, not its loading semantics.
@ComponentV2
export struct DrawnLoadingSpinner {
  @Param ringSize: number = 20;
  @Param ringColor: ResourceColor = '#FFFFFF';
  @Param percent: number = -1;
  @Param showPercent: boolean = false;
  @Param activityScale: number = 1;
  @Param ringStroke: number = 1.8;
  @Local private angle: number = 0;
  private painter: DrawnProgressRing = new DrawnProgressRing();
  private env = chatEnv;
  private visible: boolean = false;
  private running: boolean = false;
  private queued: boolean = false;
  private generation: number = 0;
  @Computed private get environment(): string {
    return `${this.env.appearanceEpoch}:${this.env.langEpoch}:${textMeasureEnvironment.epoch}`;
  }
  @Computed private get animationAllowed(): boolean { return this.percent < 0 && !this.env.reduceAnim && !this.env.powerSaving; }
  @Monitor('animationAllowed') private animationChanged(): void { this.syncAnimation(); }
  private syncAnimation(): void {
    if (!this.visible || !this.animationAllowed) { this.stop(); return; }
    if (this.running || this.queued) { return; }
    this.queued = true;
    const token = ++this.generation;
    this.getUIContext().postFrameCallback(new OneShotFrameCallback((): void => {
      if (token !== this.generation || !this.visible || !this.animationAllowed) { return; }
      this.queued = false; this.running = true;
      this.getUIContext().animateTo({ duration: 900, curve: Curve.Linear, iterations: -1 }, (): void => { this.angle = 360; });
    }));
  }
  private stop(): void {
    if (!this.running && !this.queued && this.angle === 0) { return; }
    this.generation++; this.queued = false; this.running = false;
    // A normal property update cancels its former explicit animation. Avoid
    // opening animation contexts from component destruction/recycle callbacks.
    this.angle = 0;
  }
  aboutToRecycle(): void { this.visible = false; this.stop(); }
  aboutToDisappear(): void { this.aboutToRecycle(); }
  build() {
    Row().width(this.ringSize).height(this.ringSize)
      .drawModifier(this.painter.bind(this.getUIContext(), this.environment, this.ringSize, this.ringColor, Math.max(0, this.percent), this.showPercent && this.percent >= 0, this.percent < 0, this.ringStroke))
      .rotate({ angle: this.angle })
      .scale({ x: this.percent < 0 ? this.activityScale : 1, y: this.percent < 0 ? this.activityScale : 1 })
      .accessibilityLevel('no').hitTestBehavior(HitTestMode.None)
      .onAppear((): void => { this.visible = true; this.syncAnimation(); })
      .onVisibleAreaChange([0], (visible: boolean): void => { this.visible = visible; this.syncAnimation(); });
  }
}
