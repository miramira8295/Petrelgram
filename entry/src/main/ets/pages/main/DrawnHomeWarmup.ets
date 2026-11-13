import { FrameCallback, UIContext, uiObserver } from '@kit.ArkUI';
import { drawnPainterReserve } from '../chat/DrawnPainterReserve';
import { DrawnHomeMessages, drawnHomeMessageSummary } from './DrawnHomeMessages';
import { logI, logW } from '../../util/log';

class DrawnHomeIdleFrame extends FrameCallback {
  private task: ((budget: number) => void) | undefined;
  constructor(task: (budget: number) => void) { super(); this.task = task; }
  cancel(): void { this.task = undefined; }
  onIdle(budget: number): void {
    const task = this.task; this.task = undefined;
    if (task !== undefined) { task(budget); }
  }
}

// Home-only cold-start preparation. onIdle runs on the UI thread AFTER render;
// it is not a worker and its budget is not a preemption guarantee. Bound both
// attempts and resources; first input/scroll/navigation/consumer cancels it.
export class DrawnHomeWarmup {
  private started: boolean = false;
  private ui: UIContext | undefined;
  private gate: (() => boolean) | undefined;
  private frame: DrawnHomeIdleFrame | undefined;
  private expiry: number = -1;
  private attempts: number = 0;
  private observing: boolean = false;
  private messages: DrawnHomeMessages | undefined;
  private messagesStarted: boolean = false;
  private onScroll: (event: uiObserver.ScrollEventInfo) => void = (_event: uiObserver.ScrollEventInfo): void => {
    this.cancel();
  };

  update(ui: UIContext, gate: () => boolean): void {
    if (gate()) { this.start(ui, gate); }
    else if (this.ui !== undefined) { this.cancel(); }
  }

  start(ui: UIContext, gate: () => boolean): void {
    if (this.started || !gate()) { return; }
    this.started = true; this.ui = ui; this.gate = gate;
    try {
      ui.getUIObserver().on('scrollEvent', this.onScroll); this.observing = true;
      // Do not retain a dead page if ArkUI never finds an idle frame.
      this.expiry = setTimeout((): void => { this.cancel(); }, 8000);
      this.schedule(1000);
    } catch (error) { this.fail(error as Error); }
  }

  private schedule(delay: number): void {
    const ui = this.ui;
    if (ui === undefined) { return; }
    this.frame = new DrawnHomeIdleFrame((budget: number): void => { this.run(budget); });
    ui.postDelayedFrameCallback(this.frame, delay);
  }

  private run(budget: number): void {
    this.frame = undefined;
    try {
      if (this.gate === undefined || !this.gate()) { this.cancel(); return; }
      this.attempts++;
      if (budget >= 3000000) {
        if (!this.messagesStarted) {
          this.messagesStarted = true;
          this.messages = new DrawnHomeMessages(this.gate);
          // begin handles rejection; it only reads bounded local metadata.
          this.messages.begin();
        } else if (drawnPainterReserve.pending()) { drawnPainterReserve.step(); }
        else { this.messages?.step(this.ui!); }
      }
      if (this.attempts >= 40 || (this.messagesStarted && !drawnPainterReserve.pending() && !this.messages?.pending())) {
        this.cancel(); return;
      }
      this.schedule(120);
    } catch (error) { this.fail(error as Error); }
  }

  private fail(error: Error): void {
    logW(`DrawnHomeWarmup: ${error.message}`); this.cancel();
  }

  cancel(): void {
    // Input can arrive before the home nav bar becomes visible. In that case
    // suppress the later start too; never start speculative work after a drag.
    this.started = true;
    this.messages?.cancel(); this.messages = undefined;
    drawnPainterReserve.stop();
    this.frame?.cancel(); this.frame = undefined;
    if (this.expiry !== -1) { clearTimeout(this.expiry); this.expiry = -1; }
    const ui = this.ui;
    this.ui = undefined; this.gate = undefined;
    if (ui !== undefined && this.observing) {
      this.observing = false;
      try { ui.getUIObserver().off('scrollEvent', this.onScroll); }
      catch (error) { logW(`DrawnHomeWarmup: observer cleanup: ${(error as Error).message}`); }
    }
    if (ui !== undefined) { logI(`DrawnHomeWarmup:${drawnPainterReserve.summary()}${drawnHomeMessageSummary()}`); }
  }
}
