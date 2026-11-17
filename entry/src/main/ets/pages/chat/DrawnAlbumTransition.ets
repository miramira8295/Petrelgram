import { logW } from '../../util/log';
import { withAlbumCanvasAnchor, withAlbumCanvasTransition } from '../../util/albumCanvasTransition';

// At most one temporary source node per clicked row; nothing is allocated for
// untouched albums. No image ownership/decoding, global registry or list scan.
export class DrawnAlbumTransition {
  private generation: number = 0;
  private pending: boolean = false;
  private scheduled: boolean = false;
  private timeout: number = -1;
  private valid: () => boolean = (): boolean => false;
  private open: () => void = (): void => {};
  private messageId: number = 0;
  private publish: (index: number) => void;
  private schedule: (task: () => void) => void;

  constructor(publish: (index: number) => void, schedule: (task: () => void) => void) {
    this.publish = publish; this.schedule = schedule;
  }

  begin(index: number, messageId: number, valid: () => boolean, open: () => void): void {
    this.cancel();
    const generation = this.generation;
    this.messageId = messageId; this.valid = valid; this.open = open;
    this.pending = true;
    this.publish(index);
    // A layout callback is not guaranteed on a disappearing/hidden node. Never
    // leave a valid tap stuck; fall back to the existing fade after a bound.
    this.timeout = setTimeout((): void => this.finish(generation, false), 320);
  }

  ready(): void {
    if (!this.pending || this.scheduled) { return; }
    this.scheduled = true;
    const generation = this.generation;
    this.schedule((): void => this.finish(generation, true));
  }

  private finish(generation: number, anchored: boolean): void {
    if (generation !== this.generation || !this.pending) { return; }
    this.pending = false;
    if (this.timeout !== -1) { clearTimeout(this.timeout); this.timeout = -1; }
    if (!this.valid()) { this.cancel(); return; }
    const open = this.open, messageId = this.messageId;
    // Do not retain row input/event closures for the viewer lifetime.
    this.valid = (): boolean => false; this.open = (): void => {};
    const release = (): void => { if (generation === this.generation) { this.cancel(); } };
    try {
      if (anchored) {
        if (!withAlbumCanvasAnchor(messageId, release, open)) { release(); }
      } else {
        release(); withAlbumCanvasTransition(messageId, open);
      }
    } catch (error) { release(); logW(`Album viewer open failed: ${(error as Error).message}`); }
  }

  cancel(): void {
    this.generation++; this.pending = false; this.scheduled = false;
    if (this.timeout !== -1) { clearTimeout(this.timeout); this.timeout = -1; }
    this.valid = (): boolean => false; this.open = (): void => {};
    this.publish(-1);
  }
}
