import { UIContext } from '@kit.ArkUI';
import { image } from '@kit.ImageKit';
import { TdObject } from '../../tdkit/TdTypes';
import { PaidMediaItem, PaidMediaSet } from '../../util/paidMediaModel';
import { documentFileId, documentFilePath } from '../../util/drawnDocumentMedia';
import { documentFileState, watchDocumentFile, requestDocumentFile, DocumentFileState } from '../../util/documentFileChannel';
import { CachedImageSession } from '../../util/CachedImageSession';
import { CachedImageSpec } from '../../util/cachedImageSpec';
import { THUMBNAIL_PRIORITY } from '../../util/downloadPriority';
import { DrawnFrameBatch } from '../../util/drawnFrameBatch';
import { OneShotFrameCallback } from '../../util/oneShotFrameCallback';
import { DrawnPaidMediaImageReceiver } from './DrawnPaidMediaImageReceiver';
import { DrawnPaidMediaGridCell, DrawnPaidMediaGridPlan } from './DrawnPaidMediaGridLayout';

export class DrawnPaidMediaGridSlot {
  readonly receiver: DrawnPaidMediaImageReceiver = new DrawnPaidMediaImageReceiver();
  pixels: image.PixelMap | undefined = undefined;
  path: string = '';
  mini: string = '';
  failed: boolean = false;
  fileId: number = 0;
  private file: TdObject | undefined = undefined;
  private key: string = '';
  private active: boolean = false;
  private generation: number = 0;
  private off: (() => void) | null = null;
  private cell: DrawnPaidMediaGridCell | null = null;
  private changed: () => void;
  private session: CachedImageSession;

  constructor(changed: () => void) {
    this.changed = changed;
    this.session = new CachedImageSession((pixels: image.PixelMap | undefined, _ready: boolean,
      width?: number, height?: number): void => {
      const previous = this.pixels;
      this.pixels = pixels; this.receiver.setPixels(pixels, width, height);
      // Real bitmap replacements invalidate their receiver directly. Only the
      // loading/native-fallback branches require a component attribute update.
      if (this.active && ((previous === undefined) !== (pixels === undefined) ||
        !this.receiver.canDraw(pixels, ImageFit.Cover))) { this.changed(); }
    });
  }
  private spec(): CachedImageSpec {
    return { path: this.path, boxWidth: this.cell?.width ?? 0, boxHeight: this.cell?.height ?? 0,
      fit: ImageFit.Cover, sourceKey: this.key, drawOnCanvas: true };
  }
  bind(ui: UIContext, item: PaidMediaItem, cell: DrawnPaidMediaGridCell, owner: string,
    locked: boolean, density: number): void {
    const file = locked ? undefined : item.media?.thumbnail ?? (item.kind === 'photo' ? item.media?.file : undefined);
    const key = `${owner}:${item.index}:${locked}:${documentFileId(file)}`;
    const changedOwner = this.key !== key, resumed = !this.active;
    if (changedOwner) {
      this.detach(); this.session.dispose(); this.pixels = undefined;
      this.receiver.setPixels(undefined); this.path = ''; this.failed = false; this.key = key;
    }
    this.cell = cell; this.file = file; this.fileId = documentFileId(file);
    const miniChanged = this.mini !== item.mini; this.mini = item.mini;
    this.receiver.bind(ui, cell.width, cell.height, ImageFit.Cover, true, density);
    this.receiver.preparePlay(!locked && item.kind === 'video', cell.width, cell.height, density);
    this.active = true;
    if (file !== undefined) {
      const state = documentFileState(file);
      this.path = documentFilePath(file) || state.path || this.path;
      this.failed = this.path === '' && state.failed;
      if (changedOwner || resumed) {
        const generation = this.generation;
        this.off = watchDocumentFile(file, (next: DocumentFileState): void => {
          if (!this.active || generation !== this.generation) { return; }
          const previousPath = this.path, previousFailed = this.failed;
          if (next.path !== '' || this.path === '') { this.path = next.path; }
          this.failed = this.path === '' && next.failed;
          this.session.update(this.spec());
          if (previousPath !== this.path || previousFailed !== this.failed) { this.changed(); }
        });
        requestDocumentFile(file, THUMBNAIL_PRIORITY);
      }
    }
    if (changedOwner || resumed) { this.session.activate(this.spec()); }
    else { this.session.update(this.spec()); }
    if (changedOwner || resumed || miniChanged) { this.changed(); }
  }
  retry(): void {
    if (!this.active || this.file === undefined) { return; }
    this.failed = false; requestDocumentFile(this.file, THUMBNAIL_PRIORITY, true); this.changed();
  }
  private detach(): void { this.generation++; this.off?.(); this.off = null; }
  recycle(): void {
    this.active = false; this.detach(); this.session.recycle(); this.pixels = undefined; this.receiver.setPixels(undefined);
  }
  dispose(): void { this.recycle(); this.session.dispose(); this.file = undefined; this.cell = null; }
}

// No custom component per image. Each native canvas slot owns its bitmap/file
// subscriptions; pixel/byte updates do not invoke the parent text layout.
export class DrawnPaidMediaGridController {
  readonly slots: DrawnPaidMediaGridSlot[] = [];
  private owner: string = '';
  private set: PaidMediaSet | null = null;
  private plan: DrawnPaidMediaGridPlan | null = null;
  private locked: boolean = true;
  private density: number = 0;
  private active: boolean = false;
  private batching: boolean = false;
  private dirty: boolean = false;
  private ui: UIContext | null = null;
  private frame: DrawnFrameBatch = new DrawnFrameBatch();
  private notify: () => void;
  private publish = (): void => { if (this.active) { this.notify(); } };
  private schedule = (task: () => void): void => { this.ui?.postFrameCallback(new OneShotFrameCallback(task)); };
  constructor(notify: () => void) { this.notify = notify; }
  private changed(): void {
    if (this.batching) { this.dirty = true; }
    else if (this.active) { this.frame.request(this.schedule, this.publish); }
  }
  bind(ui: UIContext, set: PaidMediaSet, plan: DrawnPaidMediaGridPlan, owner: string, locked: boolean, density: number): void {
    if (this.active && this.ui === ui && this.set === set && this.plan === plan && this.owner === owner &&
      this.locked === locked && this.density === density) { return; }
    this.ui = ui; this.active = true; this.batching = true;
    try {
      while (this.slots.length > set.items.length) { this.slots.pop()?.dispose(); }
      while (this.slots.length < set.items.length) { this.slots.push(new DrawnPaidMediaGridSlot((): void => this.changed())); }
      for (const cell of plan.cells) {
        const item = set.items[cell.index];
        if (item !== undefined) { this.slots[cell.index].bind(ui, item, cell, owner, locked, density); }
      }
      this.set = set; this.plan = plan; this.owner = owner; this.locked = locked; this.density = density;
    } finally {
      this.batching = false;
      if (this.dirty) { this.dirty = false; this.frame.cancel(); this.publish(); }
    }
  }
  recycle(): void { this.active = false; this.frame.cancel(); for (const slot of this.slots) { slot.recycle(); } }
  dispose(): void {
    this.active = false; this.frame.cancel();
    for (const slot of this.slots) { slot.dispose(); }
    this.slots.length = 0; this.ui = null; this.set = null; this.plan = null;
  }
}
