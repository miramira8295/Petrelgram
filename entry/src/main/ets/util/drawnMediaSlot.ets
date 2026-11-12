// Identity belongs to a physical drawing slot, not to the message displayed in
// it. Immutable slot IDs may be captured by ForEach; mutable media/geometry must
// always be read from the current plan. These are NOT List/Repeat message keys.
export interface DrawnMediaSlot {
  readonly index: number;
  readonly key: string;
}
export class DrawnMediaSlots {
  private slots: DrawnMediaSlot[] = [];
  prepare(count: number): DrawnMediaSlot[] {
    if (this.slots.length === count) { return this.slots; }
    const next: DrawnMediaSlot[] = this.slots.slice(0, count);
    for (let index: number = next.length; index < count; index++) {
      next.push({ index, key: `drawn-media-slot-${index}` });
    }
    this.slots = next;
    return next;
  }
}
