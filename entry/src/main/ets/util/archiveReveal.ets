// Telegram Android: DialogsActivity + PullForegroundDrawable. Fixed list row,
// 85% snap height, 200ms release gate, 220ms ready hint, .45→.20 drag friction.
// All scroll decisions are O(1); no observed state, timers or allocations here.
export class ArchiveRevealGesture {
  revealed: boolean = false;
  touching: boolean = false;
  settling: boolean = false;
  private startedAt: number = -1;

  begin(): void {
    this.touching = true;
    this.settling = false;
    this.startedAt = -1;
  }

  observe(y: number, height: number, now: number): void {
    const visible = height - y;
    if (visible < 4) {
      this.startedAt = -1;
      this.revealed = false;
    } else if (this.touching && this.startedAt < 0) {
      this.startedAt = now;
    }
  }

  ready(y: number, height: number, now: number): boolean {
    return height > 0 && this.startedAt >= 0 && now - this.startedAt >= 220 &&
      height - y > height * 0.85;
  }

  // Positive scroll delta moves the list up. Only actual finger drag may
  // enter a hidden archive row; fling/scrollbar/retap stop at the first chat.
  filter(delta: number, y: number, height: number, dragging: boolean, available: boolean): number {
    if (this.revealed && available) { return delta; }
    if (delta >= 0) { return delta; }
    if (!available || !dragging || !this.touching) {
      return Math.max(delta, Math.min(0, height - y));
    }
    const beforeRow = Math.min(0, height - y);
    if (delta >= beforeRow) { return delta; }
    const progress = Math.max(0, Math.min(1, 1 - y / height));
    // No extra overscroll above the archive: native spring is reserved for
    // normal scrolling after reveal, not stacked on top of pull friction.
    return Math.max(-Math.max(0, y), beforeRow + (delta - beforeRow) * (0.45 - 0.25 * progress));
  }

  // null means normal list scrolling; number is the normalized snap offset.
  release(y: number, height: number, now: number, available: boolean, cancelled: boolean): number | null {
    this.touching = false;
    if (this.revealed && available) { return null; }
    if (y >= height) { this.startedAt = -1; return null; }
    this.revealed = available && !cancelled && this.startedAt >= 0 &&
      now - this.startedAt >= 200 && height - y >= height * 0.85;
    this.startedAt = -1;
    this.settling = true;
    return this.revealed ? 0 : height;
  }
}

export function archiveLogicalIndex(listIndex: number): number {
  return Math.max(0, listIndex - 1);
}
