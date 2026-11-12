// O(1) request/cancel and one live closure per attachment, independent of image count.
// The captured generation rejects callbacks from a recycled A -> B -> A owner.
export class DrawnFrameBatch {
  private queued: boolean = false;
  private generation: number = 0;
  request(schedule: (task: () => void) => void, publish: () => void): void {
    if (this.queued) { return; }
    this.queued = true;
    const generation = this.generation;
    schedule((): void => {
      if (generation !== this.generation || !this.queued) { return; }
      this.queued = false;
      publish();
    });
  }
  cancel(): void { this.generation++; this.queued = false; }
}
