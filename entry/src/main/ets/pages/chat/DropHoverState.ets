import { KEY_POWER_SMOOTH_TRANSITIONS, powerAnimationDuration } from '../../store/AppSettings';

// Constant-size state: at most one enter and one exit timer, no per-frame work.
@ObservedV2
export class DropHoverState {
  @Trace visible: boolean = false;
  @Trace shown: boolean = false;
  @Trace sendMode: boolean | null = null;
  private generation: number = 0;
  private showTimer: number = -1;
  private hideTimer: number = -1;

  setVisible(on: boolean): void {
    if (powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 1) === 0) {
      this.dispose();
      this.visible = on; this.shown = on;
      return;
    }
    if (on) {
      if (this.hideTimer !== -1) { clearTimeout(this.hideTimer); this.hideTimer = -1; }
      if (this.visible && (this.shown || this.showTimer !== -1)) { return; }
      const generation = ++this.generation;
      this.visible = true;
      this.showTimer = setTimeout((): void => {
        if (generation !== this.generation) { return; }
        this.showTimer = -1; this.shown = true;
      }, 16);
    } else {
      if (this.showTimer !== -1) { clearTimeout(this.showTimer); this.showTimer = -1; }
      if (!this.visible) { return; }
      this.shown = false;
      if (this.hideTimer !== -1) { return; }
      const generation = ++this.generation;
      this.hideTimer = setTimeout((): void => {
        if (generation !== this.generation) { return; }
        this.hideTimer = -1; this.visible = false;
      }, 260);
    }
  }

  dispose(): void {
    this.generation++;
    if (this.showTimer !== -1) { clearTimeout(this.showTimer); this.showTimer = -1; }
    if (this.hideTimer !== -1) { clearTimeout(this.hideTimer); this.hideTimer = -1; }
    this.visible = false; this.shown = false;
  }
}
