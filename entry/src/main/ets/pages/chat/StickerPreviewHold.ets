// Shared by the original touch target and the non-modal preview. Coordinates are window vp.
export class StickerPreviewHold {
  private active: boolean = false;
  private moved: boolean = false;
  private selected: boolean = false;
  private left: number = 0;
  private top: number = 0;
  private width: number = 0;
  private height: number = 0;
  onSelection: (selected: boolean) => void = (): void => {};
  onFinish: (send: boolean, x: number, y: number) => void = (): void => {};
  begin(): void { this.active = true; this.moved = false; this.selected = false; }
  bounds(x: number, y: number, width: number, height: number): void {
    this.left = x; this.top = y; this.width = width; this.height = height;
  }
  move(x: number, y: number): void {
    if (!this.active) { return; }
    this.moved = true;
    this.select(x, y);
  }
  private select(x: number, y: number): void {
    const next = this.moved && this.width > 0 && this.height > 0 &&
      x >= this.left && x <= this.left + this.width && y >= this.top && y <= this.top + this.height;
    if (next !== this.selected) { this.selected = next; this.onSelection(next); }
  }
  finish(x: number, y: number, cancelled: boolean): void {
    if (!this.active) { return; }
    this.select(x, y);
    this.active = false;
    this.onFinish(!cancelled && this.selected, x, y);
  }
  cancel(): void { this.active = false; this.onSelection = (): void => {}; this.onFinish = (): void => {}; }
  touch(event: TouchEvent): void {
    const point = event.changedTouches[0] ?? event.touches[0];
    if (event.type === TouchType.Cancel) { this.finish(0, 0, true); }
    else if (point !== undefined && event.type === TouchType.Move) { this.move(point.windowX, point.windowY); }
    else if (event.type === TouchType.Up) { this.finish(point?.windowX ?? 0, point?.windowY ?? 0, point === undefined); }
  }
}
