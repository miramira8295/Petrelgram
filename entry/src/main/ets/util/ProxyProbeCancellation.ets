// An automatic failover owns its temporary probe routes, not the saved proxy
// configuration or another caller's latency test.
export class ProxyProbeCancellation {
  cancelled: boolean = false;
  private listeners: Set<() => void> = new Set();

  subscribe(listener: () => void): () => void {
    if (this.cancelled) { listener(); return (): void => {}; }
    this.listeners.add(listener);
    return (): void => { this.listeners.delete(listener); };
  }

  cancel(): void {
    if (this.cancelled) { return; }
    this.cancelled = true;
    const listeners = Array.from(this.listeners);
    this.listeners.clear();
    for (const listener of listeners) {
      try { listener(); } catch (_error) { /* Cancel every sibling even if one cleanup fails. */ }
    }
  }

  assertActive(): void {
    if (this.cancelled) { throw new Error('proxy probe cancelled'); }
  }

  run<T>(operation: () => Promise<T>): Promise<T> {
    return new Promise<T>((resolve, reject): void => {
      const unsubscribe = this.subscribe((): void => reject(new Error('proxy probe cancelled')));
      Promise.resolve().then((): Promise<T> => {
        this.assertActive();
        return operation();
      }).then(resolve, reject).finally(unsubscribe);
    });
  }
}
