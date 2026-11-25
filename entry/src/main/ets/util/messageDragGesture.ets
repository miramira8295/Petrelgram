// Stationary hold opens the context menu immediately while the finger is down;
// touch dragging only takes over after a deliberate large travel (>= 42vp).
export const MESSAGE_HOLD_MENU_MS: number = 420;
export const MESSAGE_DRAG_HOLD_MS: number = 320;
export const MESSAGE_HOLD_SLOP_VP: number = 10;
export const MESSAGE_TOUCH_DRAG_DISTANCE_VP: number = 42;

export class MessageDragGesture {
  private started: number = -1;
  private x: number = 0;
  private y: number = 0;
  private maxDistance: number = 0;
  private touch: boolean = false;
  private moved: boolean = false;
  private earlyMove: boolean = false;
  private claimed: boolean = false;
  private finished: boolean = false;
  private held: boolean = false;
  private menuOpened: boolean = false;

  reset(): void {
    this.started = -1; this.x = 0; this.y = 0; this.maxDistance = 0;
    this.touch = false; this.moved = false; this.earlyMove = false;
    this.claimed = false; this.finished = false; this.held = false;
    this.menuOpened = false;
  }

  begin(x: number, y: number, now: number, touch: boolean = false): void {
    this.started = now; this.x = x; this.y = y; this.maxDistance = 0;
    this.touch = touch; this.moved = false; this.earlyMove = false;
    this.claimed = false; this.finished = false; this.held = false;
    this.menuOpened = false;
  }

  prefersDrag(now: number): boolean {
    return this.claimed || this.held || this.menuOpened || (!this.finished && this.started >= 0 &&
      !this.earlyMove && now - this.started >= MESSAGE_DRAG_HOLD_MS);
  }

  move(x: number, y: number, now: number): void {
    if (this.finished || this.started < 0) { return; }
    if (this.prefersDrag(now)) { this.held = true; }
    const dist: number = Math.hypot(x - this.x, y - this.y);
    if (dist > this.maxDistance) { this.maxDistance = dist; }
    if (dist > MESSAGE_HOLD_SLOP_VP) {
      this.moved = true;
      if (!this.held && !this.menuOpened) { this.earlyMove = true; }
    }
  }

  markMenuOpened(): void {
    if (this.started >= 0 && !this.finished && !this.claimed) {
      this.held = true;
      this.menuOpened = true;
    }
  }

  hasOpenedMenu(): boolean {
    return this.menuOpened && !this.claimed && !this.finished;
  }

  claim(): void {
    this.claimed = true;
    this.menuOpened = false;
  }

  // Mouse drags start at the native threshold; touch drags require a stationary
  // hold plus deliberate large travel (>= 42vp) so small finger movement while
  // holding or lifting never tears down an already-opened context menu.
  canStartDrag(): boolean {
    if (this.started < 0 || this.finished || this.claimed) { return false; }
    if (!this.touch) { return true; }
    return (this.held || this.menuOpened) && !this.earlyMove &&
      this.maxDistance >= MESSAGE_TOUCH_DRAG_DISTANCE_VP;
  }

  // Proactive touch drag handoff once travel crosses the large drag threshold,
  // even if the native ~10vp drag callback already canceled earlier in the hold.
  shouldStartTouchDrag(x: number, y: number, now: number): boolean {
    this.move(x, y, now);
    return this.touch && this.canStartDrag();
  }

  end(now: number, canceled: boolean): boolean {
    const held: boolean = this.claimed || this.held || this.menuOpened || (!this.finished &&
      this.started >= 0 && !this.earlyMove && now - this.started >= MESSAGE_HOLD_MENU_MS);
    const invoke: boolean = !this.finished && !this.menuOpened && held &&
      !canceled && !this.claimed && !this.moved;
    this.held = held; this.finished = true; this.menuOpened = false;
    return invoke;
  }
}
