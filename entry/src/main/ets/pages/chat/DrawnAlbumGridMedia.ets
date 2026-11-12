import { DrawnFrameBatch } from '../../util/drawnFrameBatch';
import { OneShotFrameCallback } from '../../util/oneShotFrameCallback';
import { UIContext } from '@kit.ArkUI';
import { DrawnImageSlot } from './DrawnMediaController';
import { DrawnAlbumGridPlan } from './DrawnAlbumGridLayout';

// A grid owns N lightweight image sessions, no avatar session and no component
// per photo. Pixel updates go straight to the receiver; only placeholder or
// native fallback transitions publish a UI epoch. Batch initial seeding once.
export class DrawnAlbumGridMedia {
  readonly slots: DrawnImageSlot[] = [];
  private previous: DrawnAlbumGridPlan | null = null;
  private active: boolean = false;
  private batching: boolean = false;
  private dirty: boolean = false;
  private notify: () => void;
  private frame: DrawnFrameBatch = new DrawnFrameBatch();
  private ui: UIContext | null = null;
  private schedule = (task: () => void): void => { this.ui?.postFrameCallback(new OneShotFrameCallback(task)); };
  private publish = (): void => { if (this.active) { this.notify(); } };

  constructor(notify: () => void) { this.notify = notify; }

  prepare(ui: UIContext, plan: DrawnAlbumGridPlan): void {
    if (this.active && this.previous === plan) { return; }
    this.ui = ui; this.active = true; this.batching = true;
    try {
      while (this.slots.length > plan.tiles.length) { this.slots.pop()?.dispose(); }
      for (let i = 0; i < plan.tiles.length; i++) {
        if (i === this.slots.length) { this.slots.push(new DrawnImageSlot((): void => { this.changed(); })); }
        this.slots[i].bind(ui, plan.tiles[i], plan.density);
      }
      this.previous = plan;
    } finally {
      this.batching = false;
      if (this.dirty) { this.dirty = false; this.frame.cancel(); this.publish(); }
    }
  }

  private changed(): void {
    if (this.batching) { this.dirty = true; }
    else if (this.active) { this.frame.request(this.schedule, this.publish); }
  }
  recycle(): void {
    this.active = false; this.previous = null; this.frame.cancel(); this.ui = null;
    for (const slot of this.slots) { slot.recycle(); }
  }
  dispose(): void {
    this.active = false; this.previous = null; this.frame.cancel(); this.ui = null;
    for (const slot of this.slots) { slot.dispose(); }
    this.slots.length = 0;
  }
}
