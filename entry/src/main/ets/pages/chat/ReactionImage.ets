import { DrawContext, UIContext } from '@kit.ArkUI';
import { common2D, drawing } from '@kit.ArkGraphics2D';
import { image } from '@kit.ImageKit';
import { ReactionArtwork, watchReactionArtwork } from '../../services/ReactionArtwork';
import { DrawnImageReceiver } from '../common/DrawnImageReceiver';
import { CachedImageSession } from '../../util/CachedImageSession';
import { CachedImageSpec } from '../../util/cachedImageSpec';
import { documentFilePath, documentFileId } from '../../util/drawnDocumentMedia';
import { documentFileState, watchDocumentFile, requestDocumentFile, DocumentFileState } from '../../util/documentFileChannel';
import { THUMBNAIL_PRIORITY } from '../../util/downloadPriority';
import { DrawnTextLine, DrawnTextLineCache } from './DrawnTextLine';
import { TdObject } from '../../tdkit/TdTypes';

export interface ReactionAnimationSource { path: string; poster: string; format: string; }
// One mounted reaction owns subscriptions and decoder references; global caches
// own immutable metadata/pixels. Async completions never write a message/plan.
export class ReactionImage {
  readonly key: string;
  private receiver: DrawnImageReceiver = new DrawnImageReceiver();
  private session: CachedImageSession;
  private offMetadata: (() => void) | null = null;
  private offFile: (() => void) | null = null;
  private offAnimation: (() => void) | null = null;
  private artwork: ReactionArtwork | null = null;
  private fileId: number = 0;
  private path: string = '';
  private fallbackPath: string = '';
  private generation: number = 0;
  private animationGeneration: number = 0;
  private active: boolean = true;
  private ready: boolean = false;
  private environment: string = '';
  private density: number;
  private tint: drawing.Brush = new drawing.Brush();
  private tintColor: common2D.Color;
  private fallback: DrawnTextLine | null = null;
  private labels: DrawnTextLineCache = new DrawnTextLineCache();
  private fallbackEmoji: string;
  private fallbackContent: string = '';
  private changed: () => void;
  private pendingAnimation: ((source: ReactionAnimationSource) => void) | null = null;
  private animationUntil: number = 0;
  private animationTimer: number = -1;
  private started: boolean = false;
  constructor(ui: UIContext, key: string, emoji: string, density: number, environment: string,
    color: common2D.Color, changed: () => void, fallback?: DrawnTextLine) {
    this.key = key; this.fallbackEmoji = emoji; this.density = density; this.changed = changed;
    this.environment = environment; this.tintColor = { alpha: color.alpha, red: color.red, green: color.green, blue: color.blue }; this.tint.setAntiAlias(true);
    // The row already shaped this 20vp symbol. Share that label until TDLib
    // supplies a genuinely different fallback; color updates do not reshape.
    if (fallback !== undefined) { this.fallback = fallback; this.fallbackContent = emoji || '◌'; }
    this.receiver.bind(ui, 20, 20, ImageFit.Contain, true, density);
    this.session = new CachedImageSession((pixels: image.PixelMap | undefined, _ready: boolean, width?: number, height?: number): void => {
      if (!this.active) { return; }
      this.receiver.setPixels(pixels, width, height); this.ready = pixels !== undefined && this.receiver.canDraw(pixels, ImageFit.Contain); this.changed();
    });
    this.prepareLabel();
  }
  start(path: string): void {
    if (!this.active) { return; }
    if (this.started) { this.update(this.tintColor, path); return; }
    this.started = true; this.fallbackPath = path; this.updatePath(path); this.session.activate(this.spec());
    this.offMetadata = watchReactionArtwork(this.key, (art: ReactionArtwork | null): void => {
      if (!this.active || art === null) { return; }
      if (documentFileId(this.artwork?.animation) !== documentFileId(art.animation)) {
        this.animationGeneration++; this.offAnimation?.(); this.offAnimation = null;
      }
      this.artwork = art; this.prepareTint(); this.prepareLabel(); this.bindFile(art.poster); this.tryAnimation(); this.changed();
    });
  }
  update(color: common2D.Color, fallbackPath: string): void {
    if (!this.active) { return; }
    if (color.alpha !== this.tintColor.alpha || color.red !== this.tintColor.red || color.green !== this.tintColor.green || color.blue !== this.tintColor.blue) {
      this.tintColor = { alpha: color.alpha, red: color.red, green: color.green, blue: color.blue }; this.prepareTint(); this.prepareLabel(); this.changed();
    }
    if (fallbackPath !== '' && fallbackPath !== this.fallbackPath) {
      const previous = this.fallbackPath; this.fallbackPath = fallbackPath;
      if (this.path === '' || this.path === previous) { this.updatePath(fallbackPath); }
    }
  }
  private prepareTint(): void {
    if (this.artwork?.repaint) {
      this.tint.setColorFilter(drawing.ColorFilter.createBlendModeColorFilter(this.tintColor, drawing.BlendMode.SRC_IN));
    }
  }
  private prepareLabel(): void {
    const emoji = this.artwork?.emoji || this.fallbackEmoji || '◌';
    if (this.fallback !== null && this.fallbackContent === emoji) {
      this.fallback.recolor(this.tintColor); return;
    }
    this.fallback = this.labels.prepare(emoji, 20 * this.density, 20 * this.density,
      this.tintColor, this.environment, false, 20 * this.density);
    this.fallbackContent = emoji;
  }
  private spec(): CachedImageSpec {
    return { path: this.path, boxWidth: 20, boxHeight: 20, fit: ImageFit.Contain, drawOnCanvas: true,
      sourceKey: `reaction:${this.key}:${this.fileId}` };
  }
  private updatePath(path: string): void {
    if (this.path === path && this.path !== '') { return; }
    this.path = path; this.session.update(this.spec());
  }
  private bindFile(file: TdObject | undefined): void {
    const id = documentFileId(file);
    if (id <= 0 || file === undefined || this.fileId === id) { return; }
    this.generation++; this.offFile?.(); this.fileId = id;
    const token = this.generation;
    this.offFile = watchDocumentFile(file, (state: DocumentFileState): void => {
      if (this.active && token === this.generation && state.path !== '') { this.updatePath(state.path); }
    });
    this.updatePath(documentFilePath(file) || documentFileState(file).path || this.fallbackPath);
    this.session.activate(this.spec()); requestDocumentFile(file, THUMBNAIL_PRIORITY, documentFileState(file).failed);
  }
  play(callback: (source: ReactionAnimationSource) => void): void {
    this.cancelAnimation();
    if (!this.active) { return; }
    this.pendingAnimation = callback; this.animationUntil = Date.now() + 1500;
    this.animationTimer = setTimeout((): void => { this.cancelAnimation(); }, 1500);
    this.tryAnimation();
  }
  private tryAnimation(): void {
    const art = this.artwork, file = art?.animation;
    if (!this.active || this.pendingAnimation === null || Date.now() > this.animationUntil || file === undefined || this.offAnimation !== null) { return; }
    // Repaint-only emoji retain the correctly tinted static symbol and pulse;
    // untinted native movie frames must never cover it with the wrong color.
    if (art?.repaint || (art?.format !== 'stickerFormatTgs' && art?.format !== 'stickerFormatWebm')) { this.cancelAnimation(); return; }
    const token = this.animationGeneration;
    const deliver = (path: string): void => {
      if (!this.active || token !== this.animationGeneration || Date.now() > this.animationUntil || path === '') { return; }
      const callback = this.pendingAnimation; this.cancelAnimation();
      callback?.({ path, poster: this.path, format: art.format });
    };
    const path = documentFilePath(file) || documentFileState(file).path;
    if (path !== '') { deliver(path); return; }
    this.offAnimation = watchDocumentFile(file, (state: DocumentFileState): void => deliver(state.path));
    requestDocumentFile(file, THUMBNAIL_PRIORITY, documentFileState(file).failed);
  }
  cancelAnimation(): void {
    this.animationGeneration++; this.pendingAnimation = null; this.animationUntil = 0;
    if (this.animationTimer !== -1) { clearTimeout(this.animationTimer); this.animationTimer = -1; }
    this.offAnimation?.(); this.offAnimation = null;
  }
  draw(context: DrawContext): void {
    if (!this.active) { return; }
    if (this.ready) {
      if (this.artwork?.repaint) { context.canvas.attachBrush(this.tint); }
      this.receiver.drawFront(context);
      if (this.artwork?.repaint) { context.canvas.detachBrush(); }
    } else if (this.fallback !== null) {
      this.fallback.paragraph.paint(context.canvas, 0, (20 * this.density - this.fallback.heightPx) / 2);
    }
  }
  dispose(): void {
    this.active = false; this.generation++; this.cancelAnimation(); this.offMetadata?.(); this.offMetadata = null;
    this.offFile?.(); this.offFile = null; this.receiver.setPixels(undefined); this.session.dispose(); this.ready = false;
  }
}
