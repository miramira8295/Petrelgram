import { TdObject } from '../tdkit/TdTypes';

class DrawnSourcePoolEntry<T> {
  content: string;
  result: T | null;
  cost: number;
  constructor(content: string, result: T, cost: number) {
    this.content = content; this.result = result; this.cost = cost;
  }
}

// Immutable normalized sources only, never Paragraph/PixelMap/UIContext. Entity
// arrays are weak keys: the LRU does not keep message input objects alive.
// Eviction clears the weak-map value's payload too. Cost is a conservative
// string/record budget, not a claim about native or exact JavaScript heap bytes.
export class DrawnSourcePool<T> {
  private inputs: WeakMap<TdObject[], DrawnSourcePoolEntry<T>> = new WeakMap();
  private recent: Map<DrawnSourcePoolEntry<T>, boolean> = new Map();
  private cost: number = 0;

  get(content: string, entities: TdObject[]): T | undefined {
    const entry = this.inputs.get(entities);
    if (entry === undefined || entry.result === null || entry.content !== content) { return undefined; }
    this.recent.delete(entry); this.recent.set(entry, true);
    return entry.result;
  }

  private remove(entry: DrawnSourcePoolEntry<T>): void {
    if (this.recent.delete(entry)) { this.cost -= entry.cost; }
    entry.result = null; entry.content = ''; entry.cost = 0;
  }

  put(content: string, entities: TdObject[], result: T, cost: number): void {
    const old = this.inputs.get(entities);
    if (old !== undefined) { this.remove(old); }
    if (!(cost >= 0) || cost > 262144) { return; }
    const entry = new DrawnSourcePoolEntry<T>(content, result, cost);
    this.inputs.set(entities, entry); this.recent.set(entry, true); this.cost += cost;
    // Each admitted entry is removed at most once: amortized O(1) bookkeeping.
    while (this.recent.size > 64 || this.cost > 262144) {
      this.remove(this.recent.keys().next().value as DrawnSourcePoolEntry<T>);
    }
  }
}
