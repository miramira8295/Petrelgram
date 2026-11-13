import { UIContext } from '@kit.ArkUI';
import { DrawnFrameWork } from '../../util/drawnFrameQueue';
import { drawnMediaActivation, enqueueDrawnMedia } from '../../util/drawnMediaActivation';

// One coalesced job per physical tile. No message history or observed queue.
// Geometry and cache-hit pixels are already installed before request().
export class DrawnSlotActivation {
  ready: boolean = true;
  staged: boolean = false;
  // Once this physical slot can host native children, keep the branch alive
  // across message reuse. Only source-bound decode work is cancelled/requeued.
  // Resetting readiness on every bind destroys otherwise reusable video islands.
  private prepared: boolean = false;
  private active: boolean = false;
  private visible: boolean = false;
  private paused: boolean = false;
  private ui: UIContext | null = null;
  private work: DrawnFrameWork | null = null;
  private decode: (() => void) | null = null;
  private content: (() => void) | null = null;
  private publish: () => void;
  constructor(publish: () => void) { this.publish = publish; }

  bind(ui: UIContext, staged: boolean, reset: boolean): void {
    if (reset || staged !== this.staged) {
      this.cancel();
      if (!staged) { this.prepared = true; }
      this.ready = this.prepared; this.paused = false; this.visible = false;
    }
    this.ui = ui; this.staged = staged; this.active = true;
  }
  scheduleDecode(start: () => void): () => void {
    if (!this.staged) { start(); return (): void => {}; }
    this.decode = start; this.request();
    return (): void => {
      if (this.decode !== start) { return; }
      this.decode = null;
      if (this.ready && this.content === null) { this.cancelWork(); }
    };
  }
  // Data publication shares the same global budget as cold decode starts.
  // Replacing a pending snapshot never adds another queue node for this slot.
  scheduleContent(publish: (() => void) | null): void {
    this.content = publish;
    if (publish !== null) { this.request(); }
    else if (this.ready && this.decode === null) { this.cancelWork(); }
  }
  finishCached(): void {
    if (!this.active || this.decode !== null || this.content !== null) { return; }
    this.cancelWork(); this.prepared = true; this.ready = true;
  }
  request(): void {
    if (!this.active || this.paused || this.ui === null || this.work !== null ||
      (this.ready && this.decode === null && this.content === null)) { return; }
    this.work = enqueueDrawnMedia(this.ui, (): void => { this.work = null; this.finish(); }, this.visible);
    // Bounded overflow must not strand a thumbnail/progress indicator forever.
    // This is an observable exceptional synchronous fallback, not silent loss.
    if (this.work === null) { this.finish(); }
  }
  private finish(): void {
    if (!this.active) { return; }
    const changed = !this.ready, decode = this.decode, content = this.content;
    this.prepared = true; this.ready = true; this.decode = null; this.content = null;
    try { content?.(); decode?.(); } finally { if (changed) { this.publish(); } }
  }
  setVisible(visible: boolean): void {
    this.visible = visible; this.paused = !visible;
    if (!visible) { this.cancelWork(); }
    else if (this.work !== null) { drawnMediaActivation.priority(this.work, true); }
    else { this.request(); }
  }
  private cancelWork(): void {
    if (this.work !== null) { drawnMediaActivation.cancel(this.work); this.work = null; }
  }
  cancel(): void {
    this.cancelWork(); this.active = false; this.ui = null; this.decode = null; this.content = null;
  }
}
