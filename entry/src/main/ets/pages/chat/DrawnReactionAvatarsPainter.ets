import { DrawContext, UIContext } from '@kit.ArkUI';
import { drawing } from '@kit.ArkGraphics2D';
import { image } from '@kit.ImageKit';
import { ReactionSender } from '../../util/reactionSenders';
import { watchGiveawayPeer as watchPeer, GiveawayPeerInfo } from '../../services/GiveawayPeerCache';
import { TdObject } from '../../tdkit/TdTypes';
import { CachedImageSession } from '../../util/CachedImageSession';
import { CachedImageSpec } from '../../util/cachedImageSpec';
import { documentFileId, documentFilePath } from '../../util/drawnDocumentMedia';
import { documentFileState, watchDocumentFile, requestDocumentFile, DocumentFileState } from '../../util/documentFileChannel';
import { THUMBNAIL_PRIORITY } from '../../util/downloadPriority';
import { DrawnImageReceiver } from '../common/DrawnImageReceiver';
import { DrawnTextLine, DrawnTextLineCache, drawnColor } from './DrawnTextLine';
import { DrawnFrameBatch } from '../../util/drawnFrameBatch';
import { OneShotFrameCallback } from '../../util/oneShotFrameCallback';
import { AVATAR_PALETTE } from '../../util/theme';

// Shares the existing account-scoped peer cache (4 concurrent, 512 recent),
// file channel and bitmap pool. No message mutation or per-avatar UI nodes.
class ReactionAvatarSlot {
  readonly receiver: DrawnImageReceiver = new DrawnImageReceiver();
  readonly brush: drawing.Brush = new drawing.Brush();
  private session: CachedImageSession;
  private offPeer: (() => void) | null = null;
  private offFile: (() => void) | null = null;
  private active: boolean = true;
  private generation: number = 0;
  private fileId: number = 0;
  private path: string = '';
  private name: string = '';
  private text: DrawnTextLineCache = new DrawnTextLineCache();
  initials: DrawnTextLine | null = null;
  private ui: UIContext;
  readonly sender: ReactionSender;
  private owner: string;
  private density: number;
  private environment: string;
  private changed: () => void;
  constructor(ui: UIContext, sender: ReactionSender, owner: string,
    density: number, environment: string, changed: () => void) {
    this.ui = ui; this.sender = sender; this.owner = owner;
    this.density = density; this.environment = environment; this.changed = changed;
    this.brush.setAntiAlias(true); this.brush.setColor(drawnColor(AVATAR_PALETTE[Math.abs(sender.id) % AVATAR_PALETTE.length]));
    this.receiver.bind(ui, 20, 20, ImageFit.Cover, true, density);
    this.session = new CachedImageSession((pixels: image.PixelMap | undefined, _ready: boolean, width?: number, height?: number): void => {
      if (!this.active) { return; }
      this.receiver.setPixels(pixels, width, height); this.changed();
    });
    this.prepareName('?');
  }
  start(): void {
    this.offPeer = watchPeer(this.sender.id, this.sender.user, (info: GiveawayPeerInfo | null): void => {
      if (!this.active || info === null) { return; }
      this.prepareName(info.name); this.photo(info.photo);
    });
  }
  private prepareName(name: string): void {
    if (this.name === name && this.initials !== null) { return; }
    this.name = name;
    const point = name.codePointAt(0), initial = point === undefined ? '?' : String.fromCodePoint(point).toUpperCase();
    this.initials = this.text.prepare(initial, 18 * this.density, this.ui.fp2px(8), drawnColor(Color.White), this.environment, true);
    this.changed();
  }
  private spec(): CachedImageSpec {
    return { path: this.path, boxWidth: 20, boxHeight: 20, fit: ImageFit.Cover, drawOnCanvas: true,
      sourceKey: `${this.owner}:${this.sender.key}:${this.fileId}` };
  }
  private photo(file: TdObject | undefined): void {
    const id = documentFileId(file), changed = id !== this.fileId;
    if (changed || file === undefined) {
      this.generation++; this.offFile?.(); this.offFile = null;
      this.receiver.setPixels(undefined); this.session.dispose(); this.path = ''; this.fileId = id; this.changed();
    }
    if (file === undefined || id <= 0) { return; }
    this.path = documentFilePath(file) || documentFileState(file).path || this.path;
    if (changed) {
      const token = this.generation;
      this.offFile = watchDocumentFile(file, (next: DocumentFileState): void => {
        if (!this.active || token !== this.generation) { return; }
        if (next.path !== '' || this.path === '') { this.path = next.path; }
        this.session.update(this.spec());
      });
      this.session.activate(this.spec()); requestDocumentFile(file, THUMBNAIL_PRIORITY);
    } else { this.session.update(this.spec()); }
  }
  dispose(): void {
    this.active = false; this.generation++; this.offPeer?.(); this.offPeer = null; this.offFile?.(); this.offFile = null;
    this.receiver.setPixels(undefined); this.session.dispose();
  }
}

export class DrawnReactionAvatarsPainter extends DrawModifier {
  private slots: ReactionAvatarSlot[] = [];
  private key: string = '';
  private ui: UIContext | null = null;
  private density: number = 0;
  private clip: drawing.RoundRect | null = null;
  private frame: DrawnFrameBatch = new DrawnFrameBatch();
  private onPaint: (() => void) | null;
  constructor(onPaint?: () => void) {
    super(); this.onPaint = onPaint ?? null;
  }
  bind(ui: UIContext, senders: ReactionSender[], owner: string, environment: string): void {
    // At most three keys; selection/count repaint does not restart subscriptions.
    const key = `${owner}:${environment}:${senders.slice(0, 3).map((sender: ReactionSender): string => sender.key).join(',')}`;
    if (this.key === key && this.ui === ui) { return; }
    this.dispose(); this.key = key; this.ui = ui; this.density = ui.vp2px(1);
    const d = this.density;
    this.clip = new drawing.RoundRect({ left: 0, top: 0, right: 20 * d, bottom: 20 * d }, 10 * d, 10 * d);
    try {
      for (let i = 0; i < Math.min(3, senders.length); i++) {
        const slot = new ReactionAvatarSlot(ui, senders[i], owner, d, environment, (): void => this.repaint());
        this.slots.push(slot); slot.start();
      }
    } catch (error) { this.dispose(); throw error as Error; }
    this.repaint();
  }
  private repaint(): void {
    const ui = this.ui;
    if (ui === null) { return; }
    this.frame.request((task: () => void): void => ui.postFrameCallback(new OneShotFrameCallback(task)), (): void => {
      this.invalidate(); this.onPaint?.();
    });
  }
  dispose(): void {
    const hadContent = this.clip !== null || this.slots.length > 0;
    for (const slot of this.slots) { slot.dispose(); }
    this.slots.length = 0; this.key = ''; this.ui = null; this.clip = null; this.frame.cancel(); this.invalidate();
    // A parent canvas may draw synchronously from this callback. Never expose
    // cleared receivers with stale slots/geometry, or publish a canceled frame.
    if (hadContent) { this.onPaint?.(); }
  }
  drawBehind(context: DrawContext): void {
    if (this.clip === null) { return; }
    const c = context.canvas, d = this.density;
    // Android avatar size20, stride16. Leftmost avatar is in front. Fixed <=3.
    for (let i = this.slots.length - 1; i >= 0; i--) {
      const slot = this.slots[i];
      c.save(); c.translate((2 + i * 16) * d, 0); c.clipRoundRect(this.clip);
      c.attachBrush(slot.brush); c.drawCircle(10 * d, 10 * d, 10 * d); c.detachBrush();
      const initials = slot.initials;
      if (initials !== null) { initials.paragraph.paint(c, (20 * d - initials.widthPx) / 2, (20 * d - initials.heightPx) / 2); }
      slot.receiver.drawFront(context); c.restore();
    }
  }
}
