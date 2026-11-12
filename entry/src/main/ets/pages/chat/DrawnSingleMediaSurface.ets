import { MessageEntry } from '../../store/MessageEntry';
import { MessageBubbleActions, MessageBubbleRenderData } from './ReusableMessageBubble';
import { MessageBubbleContext } from './MessageBubbleShell';
import { DrawnImageSlot } from './DrawnMediaController';
import { DrawnSingleMediaGeometry } from './DrawnSingleMediaGeometry';
import { DrawnBubbleTile } from './DrawnBubblePlan';
import { DrawnSingleMediaVideo } from './DrawnSingleMediaVideo';
import { LiveProgressRing } from './LiveProgressRing';
import { BUBBLE_AVATAR_GUTTER_VP } from '../../util/mediaBox';
import { drawnAnimationPlaying } from '../../util/drawnAnimationPolicy';
import { thumbBackdropColor } from '../../util/thumbBackdrop';
import { MINI_PLACEHOLDER_BLUR } from '../../util/miniThumbPlaceholder';
import { scrollPlaceholderState } from '../../util/scrollEffects';
import { chatEnv } from '../../util/chatEnvMirror';
import { str } from '../../util/strings';

// Intrinsic-content fallback shares the same image session and video island as
// the whole-row renderer. Complex text/material/accessibility do not restore
// the old LiveThumbImage -> CachedImage/ThumbReadyGate component chain.
@ComponentV2
export struct DrawnSingleMediaSurface {
  @Require @Param msg: MessageEntry;
  @Require @Param data: MessageBubbleRenderData;
  @Require @Param actions: MessageBubbleActions;
  @Require @Param context: MessageBubbleContext;
  @Param corners: BorderRadiuses = {};
  @Local private imageEpoch: number = 0;
  @Local private videoLabel: string = '';
  private env = chatEnv;
  private scroll = scrollPlaceholderState;
  private geometry: DrawnSingleMediaGeometry = new DrawnSingleMediaGeometry();
  private slot: DrawnImageSlot = new DrawnImageSlot((): void => { this.imageEpoch++; });
  private active: boolean = false;
  private identity: string = '';
  private generation: number = 0;
  private touchedGeneration: number = -1;

  @Computed
  private get tile(): DrawnBubbleTile {
    const epoch = this.env.appearanceEpoch;
    return this.geometry.prepare(this.msg, this.data.chatId, this.data.contentWidth,
      this.data.isGroup && !this.msg.isOutgoing ? BUBBLE_AVATAR_GUTTER_VP : 0,
      epoch < 0 ? 1 : this.getUIContext().vp2px(1)).tiles[0];
  }
  private bindIdentity(): number {
    const key = `${this.data.chatId}:${this.msg.rowId}:${this.msg.id}`;
    if (key !== this.identity) {
      this.identity = key; this.generation++; this.touchedGeneration = -1; this.videoLabel = '';
    }
    return this.generation;
  }
  private sync(): void {
    this.bindIdentity();
    if (this.active) { this.slot.bind(this.getUIContext(), this.tile); }
  }
  @Monitor('tile', 'msg', 'data')
  private changed(): void { this.sync(); }
  aboutToAppear(): void { this.active = true; this.sync(); }
  aboutToReuse(): void { this.active = true; this.sync(); }
  aboutToRecycle(): void {
    this.active = false; this.generation++; this.identity = ''; this.touchedGeneration = -1; this.slot.recycle();
  }
  aboutToDisappear(): void { this.aboutToRecycle(); this.slot.dispose(); }
  private missing(): boolean { return this.imageEpoch >= 0 && this.slot.path === ''; }
  private labelCallback(): (label: string) => void {
    const generation = this.bindIdentity(), id = this.msg.id, chatId = this.data.chatId;
    return (label: string): void => {
      if (this.active && generation === this.generation && id === this.msg.id && chatId === this.data.chatId) { this.videoLabel = label; }
    };
  }
  private label(): string {
    const epoch = this.env.langEpoch;
    if (epoch < 0) { return ''; }
    if (this.msg.contentType === 'video') { return this.videoLabel || str('mb_tap_play_video'); }
    return str(this.msg.photoFailed ? 'mb_photo_failed' : 'mb_open_photo');
  }
  private clickCallback(): (event: ClickEvent) => void {
    const generation = this.bindIdentity(), id = this.msg.id, chatId = this.data.chatId;
    return (event: ClickEvent): void => {
      if (!this.active || generation !== this.generation || this.msg.id !== id || this.data.chatId !== chatId ||
        this.context.gestureClaimed || (event.source === SourceType.TouchScreen && this.touchedGeneration !== generation)) { return; }
      if (this.data.selectionActive) { this.actions.onToggleSelectedMessage(id); }
      else if (this.msg.photoPath === '' && this.msg.photoFailed && this.msg.photoFileId !== 0) {
        this.actions.onSpecialPhotoRetry(id);
      } else if (this.msg.isAnimation) {
        if (drawnAnimationPlaying(this.msg, this.data, this.env, true)) {
          this.context.recordMenuOffset(event.x, Number(event.target.area.width)); this.context.msgContextMenuShown = true;
        } else { this.actions.onAnimationTap(id, false); }
      } else { this.actions.onMediaTap(id, event.windowX, event.windowY); }
    };
  }
  build() {
    Stack() {
      if (this.imageEpoch >= 0 && this.slot.pixels !== undefined && !this.slot.receiver.canDraw(this.slot.pixels, ImageFit.Cover)) {
        Image(this.slot.pixels).width(this.tile.width).height(this.tile.height).draggable(false).objectFit(ImageFit.Cover).syncLoad(true);
      }
      if (this.imageEpoch >= 0 && this.slot.showMini(this.scroll.active)) {
        Image(this.slot.mini).width(this.tile.width).height(this.tile.height).draggable(false).objectFit(ImageFit.Cover).blur(MINI_PLACEHOLDER_BLUR);
      }
      if (this.missing()) {
        if (this.msg.contentType === 'photo' && (this.msg.photoFailed || this.msg.photoFileId === 0)) {
          Column({ space: 3 }) {
            SymbolGlyph($r('sys.symbol.arrow_clockwise')).fontSize(18).fontColor([Color.White]);
            Text($r('app.string.settings_retry')).fontSize(11).fontColor(Color.White).fontWeight(FontWeight.Medium);
          }.padding({ left: 10, right: 10, top: 7, bottom: 7 }).backgroundColor('#80000000').borderRadius(18);
        } else if (this.msg.photoFileId !== 0 && !this.msg.photoFailed) {
          LiveProgressRing({ fileId: this.msg.photoFileId, initialPercent: this.msg.photoProgress, ringSize: 36 });
        }
      }
      if (this.msg.contentType === 'video') {
        DrawnSingleMediaVideo({ msg: this.msg, data: this.data, actions: this.actions, slot: this.slot,
          mediaWidth: this.tile.width, mediaHeight: this.tile.height, sendState: this.context.liveSendState,
          thumbReady: !this.missing() || this.msg.photoFileId === 0 || this.msg.photoFailed,
          reportAccessibility: true, onLabelChanged: this.labelCallback() });
      }
      if (this.context.liveSendState === 'sending') {
        LiveProgressRing({ fileId: this.msg.contentType === 'video' ? this.msg.videoFileId : this.msg.photoFileId,
          initialPercent: 0, ringSize: Math.min(44, Math.min(this.tile.width, this.tile.height) * .3) });
      }
    }.width(this.tile.width).height(this.tile.height).borderRadius(this.corners).clip(true)
    .backgroundColor(thumbBackdropColor(this.msg.contentType === 'video')).drawModifier(this.slot.receiver)
    .geometryTransition(`media_${this.data.chatId}_${this.msg.id}`).accessibilityText(this.label())
    .onClick(this.clickCallback())
    .onTouch((event: TouchEvent): void => {
      if (event.type === TouchType.Down) { this.touchedGeneration = this.bindIdentity(); }
      else if (event.type === TouchType.Cancel || event.touches.length > 1) { this.touchedGeneration = -1; }
    });
  }
}
