// No timer and no competing long-press recognizer for system-draggable bubbles.
export class MessageDragGesture {
  private started: number = -1;
  private x: number = 0;
  private y: number = 0;
  private moved: boolean = false;
  private earlyMove: boolean = false;
  private claimed: boolean = false;
  private finished: boolean = false;
  private held: boolean = false;

  begin(x: number, y: number, now: number): void {
    this.started = now; this.x = x; this.y = y;
    this.moved = false; this.earlyMove = false; this.claimed = false;
    this.finished = false; this.held = false;
  }
  prefersDrag(now: number): boolean {
    return this.claimed || this.held || (!this.finished && this.started >= 0 &&
      !this.earlyMove && now - this.started >= 500);
  }
  move(x: number, y: number, now: number): void {
    if (this.finished || this.started < 0) { return; }
    if (this.prefersDrag(now)) { this.held = true; }
    if (Math.hypot(x - this.x, y - this.y) > 10) {
      this.moved = true;
      if (!this.held) { this.earlyMove = true; }
    }
  }
  claim(): void { this.claimed = true; }
  end(now: number, canceled: boolean): boolean {
    const held = this.prefersDrag(now);
    const invoke = !this.finished && held && !canceled && !this.claimed && !this.moved;
    this.held = held; this.finished = true;
    return invoke;
  }
}
