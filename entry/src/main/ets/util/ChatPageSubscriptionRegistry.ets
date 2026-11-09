export type SubscriptionDisposer = () => void;

// Keeps subscription replacement and teardown consistent. A key can only have
// one live disposer, so reused destinations cannot orphan an older listener.
export class ChatPageSubscriptionRegistry {
  private entries: Map<string, SubscriptionDisposer> =
    new Map<string, SubscriptionDisposer>();

  set(key: string, disposer: SubscriptionDisposer): void {
    this.clear(key);
    this.entries.set(key, disposer);
  }

  clear(key: string): void {
    const disposer: SubscriptionDisposer | undefined = this.entries.get(key);
    if (disposer !== undefined) {
      disposer();
      this.entries.delete(key);
    }
  }

  clearInOrder(keys: string[]): void {
    for (const key of keys) {
      this.clear(key);
    }
  }
}
