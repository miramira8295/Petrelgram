export interface ComposerInputSwitchHost {
  active: () => boolean;
  contextKey: () => number;
  emojiOpen: () => boolean;
  setEmoji: (open: boolean) => void;
  prepareEditor: () => void;
  focusEditor: () => void;
}

export interface ComposerSwitchClock {
  schedule: (callback: () => void) => number;
  cancel: (id: number) => void;
}

// Focus requests belong to a user action, not to every path that closes a panel.
export class ComposerInputSwitch {
  private host: ComposerInputSwitchHost | null = null;
  private clock: ComposerSwitchClock;
  private generation: number = 0;
  private timer: number = -1;
  private keyboardPending: boolean = false;

  constructor(clock?: ComposerSwitchClock) {
    this.clock = clock ?? {
      schedule: (callback: () => void): number => setTimeout(callback, 0),
      cancel: (id: number): void => { clearTimeout(id); }
    };
  }

  bind(host: ComposerInputSwitchHost): void {
    this.cancel();
    this.host = host;
  }

  toggleEmoji(): void {
    const host = this.host;
    if (host === null || !host.active()) { return; }
    // A second tap during the deferred close reverses the intended transition.
    if (this.keyboardPending || !host.emojiOpen()) {
      this.cancel();
      host.setEmoji(true);
    } else {
      this.showKeyboard();
    }
  }

  showKeyboard(): void {
    const host = this.host;
    if (host === null || !host.active()) { return; }
    this.cancel();
    host.setEmoji(false);
    host.prepareEditor();
    const contextKey = host.contextKey();
    const generation = ++this.generation;
    this.keyboardPending = true;
    this.timer = this.clock.schedule((): void => {
      if (generation !== this.generation) { return; }
      this.timer = -1;
      this.keyboardPending = false;
      if (host === this.host && host.active() && contextKey === host.contextKey() && !host.emojiOpen()) {
        host.focusEditor();
      }
    });
  }

  cancel(): void {
    this.generation++;
    if (this.timer !== -1) { this.clock.cancel(this.timer); }
    this.timer = -1;
    this.keyboardPending = false;
  }

  dispose(): void {
    this.cancel();
    this.host = null;
  }
}
