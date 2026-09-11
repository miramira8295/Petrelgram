// One channel per ChatPage. Only the target row receives focus updates; a
// timeline-wide observable would wake every mounted message on each pulse.
export class BubbleFocusChannel {
  private rowId: number = 0;
  private strength: number = 0;
  private listeners: Map<number, Set<(strength: number) => void>> = new Map();

  value(rowId: number): number {
    return rowId === this.rowId ? this.strength : 0;
  }

  set(rowId: number, strength: number): void {
    if (this.rowId !== rowId) {
      const previous: number = this.rowId;
      this.rowId = rowId;
      this.strength = 0;
      this.emit(previous, 0);
    }
    this.strength = strength;
    this.emit(rowId, strength);
  }

  clear(): void {
    this.set(0, 0);
  }

  subscribe(rowId: number, callback: (strength: number) => void): () => void {
    let callbacks: Set<(strength: number) => void> | undefined = this.listeners.get(rowId);
    if (callbacks === undefined) {
      callbacks = new Set();
      this.listeners.set(rowId, callbacks);
    }
    callbacks.add(callback);
    callback(this.value(rowId));
    return (): void => {
      const current: Set<(strength: number) => void> | undefined = this.listeners.get(rowId);
      if (current !== undefined) {
        current.delete(callback);
        if (current.size === 0) {
          this.listeners.delete(rowId);
        }
      }
    };
  }

  private emit(rowId: number, strength: number): void {
    this.listeners.get(rowId)?.forEach((callback: (strength: number) => void): void => {
      callback(strength);
    });
  }
}
