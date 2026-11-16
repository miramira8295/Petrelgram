// Only existing RECYCLED hosts, not an offscreen component factory. Bound the
// retained old packet/engine to eight physical rows for <=10s. Active owners
// remove their ticket before reuse. O(1) hold/take/evict, one cleanup timer.
export class DrawnRowRetention {
  private entries: Map<() => void, number> = new Map();
  private timer: number = -1;
  hold(drop: () => void): void {
    if (this.entries.has(drop)) { return; }
    if (this.entries.size >= 8) {
      const first = this.entries.keys().next();
      if (!first.done) { this.entries.delete(first.value); first.value(); }
    }
    this.entries.set(drop, Date.now() + 10000);
    if (this.timer === -1) { this.timer = setTimeout((): void => { this.clear(); }, 10000); }
  }
  take(drop: () => void): void {
    const until = this.entries.get(drop);
    this.entries.delete(drop);
    if (until !== undefined && Date.now() >= until) { drop(); }
    if (this.entries.size === 0 && this.timer !== -1) { clearTimeout(this.timer); this.timer = -1; }
  }
  clear(): void {
    if (this.timer !== -1) { clearTimeout(this.timer); this.timer = -1; }
    const old = this.entries; this.entries = new Map<() => void, number>();
    old.forEach((_until: number, drop: () => void): void => { drop(); });
  }
}
export const drawnRowRetention: DrawnRowRetention = new DrawnRowRetention();
