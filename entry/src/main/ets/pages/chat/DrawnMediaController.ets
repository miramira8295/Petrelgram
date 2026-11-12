import { DrawnFrameBatch } from '../../util/drawnFrameBatch';
import { OneShotFrameCallback } from '../../util/oneShotFrameCallback';
import { image } from '@kit.ImageKit';
import { UIContext } from '@kit.ArkUI';
import { CachedImageSession } from '../../util/CachedImageSession';
import { CachedImageSpec } from '../../util/cachedImageSpec';
import { subscribeThumbPath, thumbPathFor } from '../../util/mediaThumbChannel';
import { senderAvatarFor, senderChannelKey, subscribeSenderAvatar } from '../../util/senderAvatarChannel';
import { liveThumbPath } from '../../util/liveThumbPath';
import { miniPlaceholderOf } from '../../util/miniThumbPlaceholder';
import { DrawnImageReceiver } from '../common/DrawnImageReceiver';
import { DrawnBubblePlan, DrawnBubbleTile } from './DrawnBubblePlan';
import { AlbumCellRenderData } from '../../util/albumCellRenderData';
import { AlbumGroup } from '../../util/collapseAlbums';

// No observed fields and no component lifecycle per image. A bitmap-only update
// invalidates its drawing receiver; only placeholder/native-fallback changes
// notify the host. The existing session owns references, cancellation and retry.
export class DrawnImageSlot {
  readonly receiver: DrawnImageReceiver = new DrawnImageReceiver();
  pixels: image.PixelMap | undefined = undefined;
  path: string = '';
  mini: string = '';
  miniShown: boolean = false;
  private fileId: number = -1;
  private initialPath: string = '';
  private unsubscribe: (() => void) | null = null;
  private width: number = 0;
  private height: number = 0;
  private active: boolean = false;
  private generation: number = 0;
  private notify: () => void;
  private session: CachedImageSession;
  private boundCell: AlbumCellRenderData | null = null;
  private boundDensity: number = 0;
  private opaque: boolean = true;

  constructor(notify: () => void) {
    this.notify = notify;
    this.session = new CachedImageSession((pixels: image.PixelMap | undefined, _ready: boolean,
      width?: number, height?: number): void => {
      const previous = this.pixels;
      const wasReady = previous !== undefined;
      const wasNative = !this.receiver.canDraw(this.pixels, ImageFit.Cover);
      this.pixels = pixels;
      this.receiver.setPixels(pixels, width, height);
      if (this.active && (wasReady !== (pixels !== undefined) ||
        wasNative !== !this.receiver.canDraw(pixels, ImageFit.Cover) ||
        (wasNative && previous !== pixels))) { this.notify(); }
    });
  }

  bind(ui: UIContext, tile: DrawnBubbleTile, density: number = ui.vp2px(1)): void {
    const input = tile.cell, previous = this.boundCell;
    if (this.active && previous !== null && this.boundDensity === density && this.opaque === (tile.opaque ?? true) &&
      this.width === tile.width && this.height === tile.height && previous.thumbFileId === input.thumbFileId &&
      previous.thumbPath === input.thumbPath && previous.mini === input.mini &&
      (input.thumbFileId !== 0 || (previous.chatId === input.chatId && previous.messageId === input.messageId))) { return; }
    this.boundCell = input; this.boundDensity = density; this.opaque = tile.opaque ?? true;
    const hadPath = this.path !== '';
    const previousMini = this.mini;
    const cell = tile.cell;
    const same = this.fileId === cell.thumbFileId &&
      (cell.thumbFileId !== 0 || (this.initialPath === cell.thumbPath &&
        previous?.chatId === cell.chatId && previous?.messageId === cell.messageId));
    if (!same) {
      this.detach(); this.path = ''; this.miniShown = false;
      this.fileId = cell.thumbFileId;
      const fileId = this.fileId;
      const generation = this.generation;
      if (fileId > 0) {
        this.unsubscribe = subscribeThumbPath(fileId, (path: string): void => {
          if (!this.active || this.fileId !== fileId || this.generation !== generation) { return; }
          const hadPath = this.path !== '';
          this.path = path;
          this.session.update(this.spec());
          if (hadPath !== (path !== '')) { this.notify(); }
        });
      }
    }
    this.initialPath = cell.thumbPath;
    this.path = same && cell.thumbFileId === 0 && this.path !== '' ? this.path
      : liveThumbPath(cell.thumbFileId, thumbPathFor(cell.thumbFileId), this.path, cell.thumbPath, same);
    const mini = miniPlaceholderOf(cell.mini);
    if (this.mini !== mini) { this.miniShown = false; }
    this.mini = mini;
    this.width = tile.width; this.height = tile.height;
    this.receiver.bind(ui, tile.width, tile.height, ImageFit.Cover, true, density);
    if (!this.active) {
      this.active = true;
      this.session.activate(this.spec());
    } else { this.session.update(this.spec()); }
    if (hadPath !== (this.path !== '') || previousMini !== this.mini) { this.notify(); }
  }

  // Local video poster for messages without a thumbnail file/channel. The
  // caller guards its attachment generation; this only updates the bitmap.
  updateLocalPath(path: string): void {
    if (!this.active || path === '' || this.path === path) { return; }
    const hadPath = this.path !== '';
    this.path = path; this.session.update(this.spec());
    if (!hadPath) { this.notify(); }
  }

  private spec(): CachedImageSpec {
    return { path: this.path, boxWidth: this.width, boxHeight: this.height, opaque: this.opaque,
      radius: 6, fit: ImageFit.Cover, sourceKey: this.fileId > 0 ? `f${this.fileId}` : '',
      drawOnCanvas: true };
  }

  showMini(scrolling: boolean): boolean {
    if (this.path === '' || this.pixels !== undefined || this.mini === '') { return false; }
    if (this.miniShown) { return true; }
    if (scrolling) { return false; }
    this.miniShown = true;
    return true;
  }

  private detach(): void {
    this.generation++;
    if (this.unsubscribe !== null) { this.unsubscribe(); this.unsubscribe = null; }
  }
  recycle(): void { this.active = false; this.detach(); this.fileId = -1; this.session.recycle(); }
  dispose(): void {
    this.recycle(); this.session.dispose(); this.pixels = undefined; this.receiver.setPixels(undefined);
  }
}

export class DrawnMediaController {
  readonly slots: DrawnImageSlot[] = [];
  avatarPixels: image.PixelMap | undefined = undefined;
  readonly avatar: DrawnImageReceiver = new DrawnImageReceiver();
  private avatarSession: CachedImageSession;
  private avatarKey: string = '';
  private avatarPath: string = '';
  private avatarUnsub: (() => void) | null = null;
  private active: boolean = false;
  private notify: () => void;
  private changed: () => void;
  private batching: boolean = false;
  private dirty: boolean = false;
  private frame: DrawnFrameBatch = new DrawnFrameBatch();
  private ui: UIContext | null = null;
  private schedule = (task: () => void): void => { this.ui?.postFrameCallback(new OneShotFrameCallback(task)); };
  private publish = (): void => { if (this.active) { this.notify(); } };
  private avatarGeneration: number = 0;
  private boundTiles: DrawnBubbleTile[] | null = null;
  private boundDensity: number = 0;

  constructor(notify: () => void, changed: () => void) {
    this.notify = notify; this.changed = changed;
    this.avatarSession = new CachedImageSession((pixels: image.PixelMap | undefined, _ready: boolean,
      width?: number, height?: number): void => {
      const previous = this.avatarPixels;
      const wasNative = !this.avatar.canDraw(previous, ImageFit.Cover);
      this.avatarPixels = pixels;
      this.avatar.setPixels(pixels, width, height);
      if (wasNative !== !this.avatar.canDraw(pixels, ImageFit.Cover) ||
        (wasNative && previous !== pixels)) { this.markDirty(); }
      if (this.active) { this.changed(); }
    });
  }

  prepare(ui: UIContext, plan: DrawnBubblePlan, group: AlbumGroup): void {
    this.ui = ui; this.active = true; this.batching = true;
    try {
      if (this.boundTiles !== plan.tiles || this.boundDensity !== plan.density) {
        const count = plan.tiles.length;
        while (this.slots.length > count) { this.slots.pop()?.dispose(); }
        for (let i = 0; i < count; i++) {
          if (i === this.slots.length) {
            this.slots.push(new DrawnImageSlot((): void => { this.markDirty(); }));
          }
          this.slots[i].bind(ui, plan.tiles[i], plan.density);
        }
        this.boundTiles = plan.tiles; this.boundDensity = plan.density;
      }
      const m = group.head;
      const key = plan.avatar.width > 0 ? senderChannelKey(m.senderId, m.senderIsUser) : '';
      if (key !== this.avatarKey || (key !== '' && this.avatarUnsub === null)) {
        this.detachAvatar(); this.avatarKey = key;
        this.avatarPath = key !== '' ? senderAvatarFor(key) || m.senderAvatarPath : '';
        const generation = this.avatarGeneration;
        if (key !== '') {
          this.avatarUnsub = subscribeSenderAvatar(key, (path: string): void => {
            if (!this.active || this.avatarKey !== key || this.avatarGeneration !== generation) { return; }
            this.avatarPath = path; this.changed();
            this.avatarSession.update(this.avatarSpec());
          });
        }
        this.avatarSession.activate(this.avatarSpec());
      } else if (key !== '') {
        const path = senderAvatarFor(key) || m.senderAvatarPath;
        if (this.avatarPath !== path) {
          this.avatarPath = path; this.avatarSession.update(this.avatarSpec());
        }
      }
      this.avatar.bind(ui, 38, 38, ImageFit.Cover, key !== '', plan.density);
    } finally {
      this.batching = false;
      if (this.dirty) { this.dirty = false; this.frame.cancel(); this.publish(); }
    }
  }

  private markDirty(): void {
    if (this.batching) { this.dirty = true; }
    else if (this.active) { this.frame.request(this.schedule, this.publish); }
  }

  get avatarHasPath(): boolean { return this.avatarPath !== ''; }

  private avatarSpec(): CachedImageSpec {
    return { path: this.avatarPath, boxWidth: 38, boxHeight: 38, radius: 19,
      fit: ImageFit.Cover, sourceKey: this.avatarKey, pinBounded: true, drawOnCanvas: true };
  }
  private detachAvatar(): void {
    this.avatarGeneration++;
    if (this.avatarUnsub !== null) { this.avatarUnsub(); this.avatarUnsub = null; }
  }
  recycle(): void {
    this.active = false; this.boundTiles = null; this.frame.cancel(); this.ui = null;
    for (const slot of this.slots) { slot.recycle(); }
    this.detachAvatar(); this.avatarSession.recycle();
  }
  dispose(): void {
    this.recycle();
    for (const slot of this.slots) { slot.dispose(); }
    this.slots.length = 0;
    this.avatarSession.dispose(); this.avatarPixels = undefined; this.avatar.setPixels(undefined);
  }
}
