// One non-observed channel per chat page. Switching slots touches only the old
// and new media listeners, never the page/row inputs or every mounted message.
export interface PlaySlotSnapshot {
  key: string;
  startMs: number;
  revision: number;
  muted: boolean;
}
export const EMPTY_PLAY_SLOT: PlaySlotSnapshot = { key: '', startMs: 0, revision: 0, muted: true };
type SlotListener = (value: PlaySlotSnapshot) => void;

export class PlaySlotChannel {
  private value: PlaySlotSnapshot = EMPTY_PLAY_SLOT;
  private revision: number = 0;
  private listeners: Map<string, Set<SlotListener>> = new Map();

  read(key: string): PlaySlotSnapshot {
    return key !== '' && this.value.key === key ? this.value : EMPTY_PLAY_SLOT;
  }

  publish(key: string, startMs: number, muted: boolean = true): void {
    const position = key === '' ? 0 : Math.max(0, startMs);
    if (this.value.key === key && this.value.startMs === position && this.value.muted === muted) { return; }
    const old = this.value.key;
    const next: PlaySlotSnapshot = { key, startMs: position, revision: ++this.revision, muted };
    this.value = next;
    if (old !== '' && old !== key) { this.notify(old, EMPTY_PLAY_SLOT, next); }
    // A listener can synchronously retire/replace a slot. Never publish an
    // obsolete start after that nested transition.
    if (key !== '' && this.value === next) { this.notify(key, next, next); }
  }

  setMuted(muted: boolean): void { this.publish(this.value.key, this.value.startMs, muted); }

  subscribe(key: string, listener: SlotListener): () => void {
    let bucket = this.listeners.get(key);
    if (bucket === undefined) { bucket = new Set(); this.listeners.set(key, bucket); }
    bucket.add(listener);
    const held = bucket;
    return (): void => {
      held.delete(listener);
      if (held.size === 0 && this.listeners.get(key) === held) { this.listeners.delete(key); }
    };
  }

  private notify(key: string, value: PlaySlotSnapshot, current: PlaySlotSnapshot): void {
    const bucket = this.listeners.get(key);
    if (bucket === undefined) { return; }
    // Snapshot only this key's subscribers; unsubscribe/rebind during delivery
    // cannot loop over newly added listeners or notify a removed receiver.
    const callbacks = Array.from(bucket);
    for (const callback of callbacks) {
      if (this.value !== current) { return; }
      if (bucket.has(callback)) { callback(value); }
    }
  }
}

// The owner stores snapshot in its own @Local. The binding itself is ordinary
// state: parent builders never observe it, and recycle releases its listener.
export class PlaySlotBinding {
  private channel: PlaySlotChannel | undefined = undefined;
  private key: string = '';
  private generation: number = 0;
  private unsubscribe: (() => void) | null = null;
  revision: number = 0;

  bind(channel: PlaySlotChannel | undefined, key: string, changed: SlotListener): void {
    if (channel === undefined) { key = ''; }
    if (this.channel === channel && this.key === key) {
      // Reuse can reset @Local while keeping the binding. Synchronously reseed.
      changed(channel?.read(key) ?? EMPTY_PLAY_SLOT);
      return;
    }
    // Initial attachment must not invalidate visibility callbacks installed
    // by initialRender before aboutToAppear when the empty state is unchanged.
    if (this.channel !== undefined || this.key !== '') { this.clear(); }
    this.channel = channel; this.key = key;
    const generation = this.generation;
    if (channel !== undefined && key !== '') {
      this.unsubscribe = channel.subscribe(key, (value: PlaySlotSnapshot): void => {
        if (generation !== this.generation || this.channel !== channel || this.key !== key) { return; }
        this.revision++; changed(value);
      });
    }
    changed(channel?.read(key) ?? EMPTY_PLAY_SLOT);
  }

  read(channel: PlaySlotChannel | undefined, key: string, local: PlaySlotSnapshot): PlaySlotSnapshot {
    // Input may change before Monitor. Never revive the previous message or
    // accept late player callbacks after A/B/A or off/on slot transitions.
    return this.channel === channel && this.key === key && channel?.read(key) === local ? local : EMPTY_PLAY_SLOT;
  }

  clear(): void {
    this.generation++; this.revision++;
    if (this.unsubscribe !== null) { this.unsubscribe(); this.unsubscribe = null; }
    this.channel = undefined; this.key = '';
  }
}
