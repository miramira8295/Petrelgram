// One controller per chat column. Only its matching, fully opaque viewer may
// hide that column; layout and the message nodes remain mounted underneath.
export class ViewerUnderlay {
  private active: boolean = false;
  private mounted: boolean = false;
  private entered: boolean = false;
  private revealing: boolean = false;
  private closing: boolean = false;
  private hidden: boolean = false;
  private session: number = 0;
  private motion: number = 0;
  private changed: (hidden: boolean) => void;

  constructor(changed: (hidden: boolean) => void) { this.changed = changed; }

  setActive(active: boolean): void {
    this.active = active;
    this.publish();
  }

  mount(): number {
    this.session++;
    this.motion = 0;
    this.mounted = true;
    this.entered = false;
    this.revealing = false;
    this.closing = false;
    this.publish();
    return this.session;
  }

  entranceFinished(session: number): void {
    if (!this.owns(session)) { return; }
    this.entered = true;
    this.publish();
  }

  // Restore before the gesture moves/fades the viewer. A later gesture makes
  // an earlier spring-back completion obsolete, even in the same viewer.
  reveal(session: number): number {
    if (!this.owns(session)) { return -1; }
    this.motion++;
    this.revealing = true;
    this.publish();
    return this.motion;
  }

  settled(session: number, motion: number): void {
    if (!this.owns(session) || motion !== this.motion) { return; }
    this.revealing = false;
    this.publish();
  }

  prepareClose(): void {
    this.closing = true;
    this.publish();
  }

  unmount(session: number): void {
    if (!this.owns(session)) { return; }
    this.mounted = false;
    this.publish();
  }

  private owns(session: number): boolean {
    return this.mounted && session === this.session;
  }

  private publish(): void {
    const hidden: boolean = this.active && this.mounted && this.entered && !this.revealing && !this.closing;
    if (hidden === this.hidden) { return; }
    this.hidden = hidden;
    this.changed(hidden);
  }
}
