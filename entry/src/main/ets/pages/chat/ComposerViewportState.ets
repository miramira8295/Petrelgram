// Window bounds and keyboard avoidance are different signals. Never learn an
// IME height from a historical maximum of page heights (rotation/split resize).
// Plain per-page state: O(1) updates, no timers or message/layout traversal.
export class ComposerViewportState {
  fullHeight: number = 0;
  resizedHeight: number = 0;
  imeHeight: number = 0;
  private windowWidth: number = 0;
  private windowHeight: number = 0;
  private keyboardHeight: number = 0;
  private closing: boolean = false;
  private imeHeightHeld: boolean = false;

  setWindow(width: number, height: number): boolean {
    if (!Number.isFinite(width) || !Number.isFinite(height) || width <= 0 || height <= 0) { return false; }
    const changed: boolean = this.windowHeight > 0 &&
      (Math.abs(width - this.windowWidth) > 0.5 || Math.abs(height - this.windowHeight) > 0.5);
    if (changed) {
      // Area and native-size callbacks can arrive in either order. Start
      // from the new window bound; the next measured area refines its inset.
      this.fullHeight = height;
      this.resizedHeight = 0;
      this.imeHeight = 0;
      this.imeHeightHeld = false;
      this.keyboardHeight = 0;
      this.closing = false;
    }
    this.windowWidth = width;
    this.windowHeight = height;
    return changed;
  }

  setKeyboard(height: number): void {
    if (!Number.isFinite(height) || height < 0) { return; }
    if (height > 0) {
      if (this.keyboardHeight <= 0) { this.imeHeightHeld = false; }
      this.keyboardHeight = Math.min(height, this.windowHeight || height);
      if (!this.imeHeightHeld) { this.imeHeight = this.keyboardHeight; }
      this.closing = false;
      // Resize may arrive before the keyboard notification, including when
      // the page first appears with the IME already visible.
      if (this.resizedHeight > 0 && this.fullHeight <= this.resizedHeight + 1 &&
        this.windowHeight - this.resizedHeight >= this.keyboardHeight - 1) {
        this.fullHeight = Math.min(this.windowHeight || Number.MAX_VALUE,
          this.resizedHeight + this.keyboardHeight);
      }
    } else {
      this.closing = this.keyboardHeight > 0 && this.resizedHeight < this.fullHeight - 1;
      this.keyboardHeight = 0;
    }
  }

  resize(height: number): void {
    if (!Number.isFinite(height) || height <= 0) { return; }
    this.resizedHeight = height;
    if (this.fullHeight <= 0) {
      this.fullHeight = Math.min(this.windowHeight || Number.MAX_VALUE, height + this.keyboardHeight);
    } else if (height >= this.fullHeight - 1) {
      this.fullHeight = height;
      this.closing = false;
    } else if (this.keyboardHeight <= 0 && !this.closing) {
      // An ordinary window/page shrink is not a keyboard.
      this.fullHeight = height;
    }
  }

  // Freeze the handoff target before stopEditing can emit shrinking IME frames.
  holdImeHeight(): void { this.imeHeightHeld = this.keyboardHeight > 0; }

  overlap(): number {
    if (this.keyboardHeight <= 0 && !this.closing) { return 0; }
    if (this.resizedHeight <= 0) { return this.keyboardHeight; }
    return Math.max(0, this.fullHeight - this.resizedHeight);
  }
}
