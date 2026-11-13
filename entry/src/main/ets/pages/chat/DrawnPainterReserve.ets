import { DrawnBubblePainter, DrawnBubbleAvatar, DrawnBubbleForeground } from './DrawnBubblePainter';

// Only UNBOUND modifiers enter this reserve. Ownership transfers once on pop;
// there is deliberately no release/return API: an attached DrawModifier must
// never migrate between live rows or windows. No messages, pixels or UIContext
// are retained. At most two rows (six modifiers) per process are prepared.
export class DrawnPainterReserve {
  private backgrounds: DrawnBubblePainter[] = [];
  private avatars: DrawnBubbleAvatar[] = [];
  private foregrounds: DrawnBubbleForeground[] = [];
  private prepared: number = 0;
  private hits: number = 0;
  private misses: number = 0;
  private stopped: boolean = false;

  pending(): boolean { return !this.stopped && this.prepared < 6; }

  // A fixed single constructor per idle callback, never a batch/album loop.
  step(): void {
    if (!this.pending()) { return; }
    switch (this.prepared % 3) {
      case 0: this.backgrounds.push(new DrawnBubblePainter()); break;
      case 1: this.avatars.push(new DrawnBubbleAvatar()); break;
      default: this.foregrounds.push(new DrawnBubbleForeground()); break;
    }
    this.prepared++;
  }

  stop(): void { this.stopped = true; }

  // O(1), no observables or per-hit logging. First consumer ends speculation;
  // subsequent rows use ordinary construction when the reserve is exhausted.
  takeBackground(): DrawnBubblePainter {
    this.stop();
    const item = this.backgrounds.pop();
    if (item !== undefined) { this.hits++; return item; }
    this.misses++; return new DrawnBubblePainter();
  }
  takeAvatar(): DrawnBubbleAvatar {
    this.stop();
    const item = this.avatars.pop();
    if (item !== undefined) { this.hits++; return item; }
    this.misses++; return new DrawnBubbleAvatar();
  }
  takeForeground(): DrawnBubbleForeground {
    this.stop();
    const item = this.foregrounds.pop();
    if (item !== undefined) { this.hits++; return item; }
    this.misses++; return new DrawnBubbleForeground();
  }
  summary(): string {
    return `\nhome painters: prepared=${this.prepared}/6 hit=${this.hits} cold=${this.misses}` +
      ` unused=${this.backgrounds.length + this.avatars.length + this.foregrounds.length}`;
  }
}

// Constructing the reserve itself allocates no native drawing resources.
export const drawnPainterReserve: DrawnPainterReserve = new DrawnPainterReserve();
