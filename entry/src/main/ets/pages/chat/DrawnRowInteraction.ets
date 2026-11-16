// One owner per physical row. Keep UI dependencies field-specific, without
// asking V2 to reset these fields again on every recursive component reuse.
// This object is never shared between rows or retained in a process cache.
@ObservedV2
export class DrawnRowInteraction {
  @Trace avatarRevision: number = 0;
  @Trace menuShown: boolean = false;
  @Trace swipeX: number = 0;
  @Trace capturedDeleteKey: string = '';
  @Trace allowBodyDrag: boolean = true;

  reset(): void {
    if (this.menuShown) { this.menuShown = false; }
    if (this.swipeX !== 0) { this.swipeX = 0; }
    if (this.capturedDeleteKey !== '') { this.capturedDeleteKey = ''; }
    if (!this.allowBodyDrag) { this.allowBodyDrag = true; }
    // Revision belongs to this physical image receiver. It need not return to
    // zero: a new image state increments it and updates only its native branch.
  }
}
