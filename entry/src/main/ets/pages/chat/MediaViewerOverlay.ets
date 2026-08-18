import { common } from '@kit.AbilityKit';
import { MessageEntry } from '../../store/MessageEntry';
import { MessageStore } from '../../store/MessageStore';
import { AlbumGroup } from '../../util/collapseAlbums';
import { formatTime } from '../../util/formatTime';
import { StreamingVideoPlayer } from './StreamingVideoPlayer';
import { setMediaViewerOrientation } from './LiveViewerUi';
import {
  KEY_CURRENT_NETWORK_TYPE, KEY_POWER_EFFECT_BLUR, KEY_POWER_SMOOTH_TRANSITIONS, powerAnimationDuration
} from '../../store/AppSettings';
import { str } from '../../util/strings';
import { LANGUAGE_EPOCH } from '../../util/appLanguage';
import { MediaContext, shouldPrefetchNeighbour } from '../../store/MediaPolicy';

const VIEWER_CHROME_BG: string = '#6e3e3e40';
const VIEWER_MIN_SCALE: number = 1;
const VIEWER_MAX_SCALE: number = 4;
const VIEWER_DOUBLE_TAP_SCALE: number = 2.5;

interface ViewerFit {
  w: number;
  h: number;
}

// Fullscreen photo/video viewer, extracted from ChatPage.
//
// Ownership split with the page: the page owns *which* message is open
// (viewerMsgId) and the open/close animation, because the hero transition is
// anchored to the tapped thumbnail's position in the chat list. Everything that
// only matters while the viewer is up — zoom/pan, paging, landscape, the chrome
// layer — lives here. The component is created and destroyed by the page's
// `if (viewerMsgId !== 0)` branch, so this state resets per open for free and
// no explicit teardown is needed.
@Component
export struct MediaViewerOverlay {
  @StorageProp(LANGUAGE_EPOCH) langEpoch: number = 0;
  // Two-way with the page: tapping close clears the id from in here.
  @Link viewerMsgId: number;
  @Link chromeVisible: boolean;
  // @Link (not @Prop) for both arrays: @Prop deep-copies its source, which for
  // the whole loaded message list would run on every download-progress tick.
  @Link messages: MessageEntry[];
  @Link groups: AlbumGroup[];

  @StorageProp('topSafeHeight') topSafe: number = 0;

  // Window coordinates (vp) of the tap that opened the viewer — anchor for the
  // expand-from-tap open / shrink-back-to-tap close transition. The transition
  // lives on this component's own root Stack rather than on the component
  // instance in the page: `.transition()` is documented for containers and
  // their inserted/removed children, not for custom-component instances. The
  // page's `if` removing this component still triggers it, because removal
  // recursively fires the transitions of everything being removed.
  @Prop tapX: number = 0;
  @Prop tapY: number = 0;

  // Set once at construction by the page (index of the tapped album member).
  initIdx: number = 0;
  // Bubble→viewer handoff: the play position the page had recorded for the
  // tapped message (see ChatPage.bubblePositionMs), read once here just like
  // initIdx. Only applies to that one message — a different album member
  // reached by swiping starts at 0, since it never had a bubble play slot in
  // this session.
  initStartPositionMs: number = 0;
  store: MessageStore | null = null;
  chatTitle: string = '';
  @Prop nowSec: number = 0;

  effectDuration: (key: string, ms: number) => number =
    (_key: string, ms: number): number => ms;
  isVideoEntry: (entry: MessageEntry) => boolean = (): boolean => false;
  onRequestClose: () => void = (): void => {};
  onSaveMedia: () => void = (): void => {};
  // Viewer→bubble handoff (the other direction): the page samples this on
  // every tick and writes it back to bubblePositionMs when the viewer closes.
  // 350ms-ish cadence from StreamingVideoPlayer, same "plain field, no @State"
  // reasoning as the bubble side.
  onPositionChanged: (positionMs: number) => void = (_positionMs: number): void => {};
  // Captured once in aboutToAppear: which message initStartPositionMs belongs
  // to, since viewerMsgId itself moves as the user swipes.
  private initialViewerMsgId: number = 0;

  @State pageIdx: number = 0;
  // Landscape stays two-way with the page: its onBackPress must be able to see
  // "we're in landscape" and exit that first instead of closing the viewer.
  @Link videoLandscape: boolean;
  // Zoom is viewer-owned. Keeping it out of the message row prevents the
  // gesture from mutating a recycled Image node in the chat list.
  //
  // Model (per the official picture-preview best practice): the Image scales
  // around its own center and pans via translate, so screen = offset + scale
  // * content-point (measured from the image center). Pinch anchoring and
  // boundary clamping are both computed against that model.
  @State photoScale: number = VIEWER_MIN_SCALE;
  @State photoOffsetX: number = 0;
  @State photoOffsetY: number = 0;

  private pinchStartScale: number = VIEWER_MIN_SCALE;
  private pinchStartOffsetX: number = 0;
  private pinchStartOffsetY: number = 0;
  // Pinch anchor relative to the viewer center (vp) — the content point that
  // was under the fingers at pinch start stays under them while zooming.
  private pinchAnchorX: number = 0;
  private pinchAnchorY: number = 0;
  private panStartOffsetX: number = 0;
  private panStartOffsetY: number = 0;
  private areaW: number = 0;
  private areaH: number = 0;
  private ignoreTapUntilMs: number = 0;
  // 放大态下拖到左右边界后继续拖动的累计量。达到阈值即翻页，
  // 让"滑到边上还能翻下一张"在放大时也成立（此时 Swiper 收不到手势）。
  private edgeOverscroll: number = 0;
  private swiperCtrl: SwiperController = new SwiperController();

  aboutToAppear(): void {
    this.pageIdx = this.initIdx;
    this.initialViewerMsgId = this.viewerMsgId;
    this.prefetchNeighbours(this.pageIdx);
  }

  // Leaving the viewer in landscape would strand the chat page sideways.
  aboutToDisappear(): void {
    if (this.videoLandscape) {
      setMediaViewerOrientation(getContext(this) as common.UIAbilityContext, false);
    }
  }

  private networkMetered(): boolean {
    const type: string = AppStorage.get<string>(KEY_CURRENT_NETWORK_TYPE) ?? 'other';
    return type === 'mobile' || type === 'roaming';
  }

  // Prefetches the left/right neighbours' full-resolution photos so paging
  // to them lands already-sharp. Gated by the shared media policy: off on
  // metered networks. Videos/GIFs are never prefetched — requestFullPhoto
  // only ever fetches photoFullFileId, so this filter just avoids wasted
  // lookups for entries that can't have one.
  private prefetchNeighbours(index: number): void {
    if (this.store === null) {
      return;
    }
    const ctx: MediaContext = {
      inWindow: true,
      isPlaySlot: false,
      viewerOpen: true,
      autoplayEnabled: true,
      powerSaving: false,
      networkMetered: this.networkMetered(),
      // shouldPrefetchNeighbour 不看这个字段，查看器语境下填 false 即可。
      reduceAnimations: false
    };
    if (!shouldPrefetchNeighbour(ctx)) {
      return;
    }
    const ids: number[] = this.siblingIds();
    const neighbourIndexes: number[] = [index - 1, index + 1];
    for (const i of neighbourIndexes) {
      if (i < 0 || i >= ids.length) {
        continue;
      }
      const id: number = ids[i];
      if (this.siblingIsVideo(id)) {
        continue;
      }
      this.store.requestFullPhoto(id, false, false);
    }
  }

  @Styles
  chromeNormalStyle() {
    .backgroundColor(Color.Transparent)
    .opacity(1)
    .scale({ x: 1, y: 1 })
  }

  @Styles
  chromePressedStyle() {
    .backgroundColor($r('app.color.surface_alt'))
    .opacity(0.76)
    .scale({ x: 0.985, y: 0.96 })
  }

  private setVideoLandscape(landscape: boolean): void {
    if (landscape && !this.isVideo()) {
      return;
    }
    if (this.videoLandscape === landscape) {
      return;
    }
    this.videoLandscape = landscape;
    this.chromeVisible = true;
    setMediaViewerOrientation(getContext(this) as common.UIAbilityContext, landscape);
  }

  private toggleChrome(): void {
    this.chromeVisible = !this.chromeVisible;
  }

  private zoomed(): boolean {
    return this.photoScale > VIEWER_MIN_SCALE + 0.01;
  }

  // Contain-fitted display size of the current photo at 1x, in vp. Falls back
  // to the viewport itself when the photo's pixel size is unknown.
  private fittedSize(): ViewerFit {
    const w = this.areaW;
    const h = this.areaH;
    const e = this.entry();
    const pw = e !== null ? e.photoWidth : 0;
    const ph = e !== null ? e.photoHeight : 0;
    if (w <= 0 || h <= 0 || pw <= 0 || ph <= 0) {
      return { w: w, h: h };
    }
    const fit = Math.min(w / pw, h / ph);
    return { w: pw * fit, h: ph * fit };
  }

  // Boundary restriction (per the official best practice): an axis whose
  // scaled size still fits the viewport stays centered; otherwise the photo
  // edge stops at the viewport edge — no black gaps, never dragged off-screen.
  private clampOffset(): void {
    const s = this.photoScale;
    const fitted = this.fittedSize();
    const maxX = Math.max(0, (fitted.w * s - this.areaW) / 2);
    const maxY = Math.max(0, (fitted.h * s - this.areaH) / 2);
    this.photoOffsetX = Math.min(maxX, Math.max(-maxX, this.photoOffsetX));
    this.photoOffsetY = Math.min(maxY, Math.max(-maxY, this.photoOffsetY));
  }

  private resetPhotoZoom(animated: boolean): void {
    this.pinchStartScale = VIEWER_MIN_SCALE;
    if (animated) {
      animateTo({
        duration: this.effectDuration(KEY_POWER_EFFECT_BLUR, 180), curve: Curve.EaseOut
      }, () => {
        this.photoScale = VIEWER_MIN_SCALE;
        this.photoOffsetX = 0;
        this.photoOffsetY = 0;
      });
    } else {
      this.photoScale = VIEWER_MIN_SCALE;
      this.photoOffsetX = 0;
      this.photoOffsetY = 0;
    }
  }

  private onPinchStart(event: GestureEvent): void {
    this.pinchStartScale = this.photoScale;
    this.pinchStartOffsetX = this.photoOffsetX;
    this.pinchStartOffsetY = this.photoOffsetY;
    this.pinchAnchorX = event.pinchCenterX - this.areaW / 2;
    this.pinchAnchorY = event.pinchCenterY - this.areaH / 2;
    this.ignoreTapUntilMs = Number.MAX_VALUE;
  }

  // Keep the content point that was under the initial pinch center glued to
  // the CURRENT pinch center: zooming follows the fingers and moving both
  // fingers together doubles as a two-finger pan.
  private onPinchUpdate(event: GestureEvent): void {
    const s0 = this.pinchStartScale;
    const next = Math.max(VIEWER_MIN_SCALE, Math.min(VIEWER_MAX_SCALE, s0 * event.scale));
    const ratio = next / s0;
    const px = event.pinchCenterX - this.areaW / 2;
    const py = event.pinchCenterY - this.areaH / 2;
    this.photoScale = next;
    this.photoOffsetX = px - (this.pinchAnchorX - this.pinchStartOffsetX) * ratio;
    this.photoOffsetY = py - (this.pinchAnchorY - this.pinchStartOffsetY) * ratio;
    this.clampOffset();
  }

  private onPinchEnd(): void {
    this.ignoreTapUntilMs = Date.now() + 200;
    if (!this.zoomed()) {
      this.resetPhotoZoom(false);
    } else {
      this.pinchStartScale = this.photoScale;
    }
  }

  private onPanStart(): void {
    this.panStartOffsetX = this.photoOffsetX;
    this.panStartOffsetY = this.photoOffsetY;
    this.edgeOverscroll = 0;
  }

  private onPanEnd(): void {
    if (!this.zoomed() || Math.abs(this.edgeOverscroll) < 60) {
      this.edgeOverscroll = 0;
      return;
    }
    const forward: boolean = this.edgeOverscroll < 0; // 向左拖 = 看下一张
    this.edgeOverscroll = 0;
    // 翻页前回到 1x，否则新图会沿用上一张的缩放与偏移。
    this.resetPhotoZoom(false);
    if (forward) {
      this.swiperCtrl.showNext();
    } else {
      this.swiperCtrl.showPrevious();
    }
  }

  // One-finger drag pans the zoomed photo; clamping keeps it on-screen. At
  // the fitted 1x size this is a no-op and the Swiper keeps paging instead.
  private onPanUpdate(event: GestureEvent): void {
    if (!this.zoomed()) {
      return;
    }
    const desiredX: number = this.panStartOffsetX + event.offsetX;
    this.photoOffsetX = desiredX;
    this.photoOffsetY = this.panStartOffsetY + event.offsetY;
    this.clampOffset();
    // clamp 吃掉的水平位移就是"已经贴边还在继续拖"的量。
    this.edgeOverscroll = desiredX - this.photoOffsetX;
  }

  // A single tap on a photo at 1x closes the viewer, the way the official
  // client behaves — at that zoom level there is nothing to inspect, so a tap
  // means "done". Once zoomed the tap goes back to toggling chrome, because
  // closing out of a zoomed photo would lose the user's position.
  //
  // Video keeps the toggle at every level: a tap there is how you reach the
  // controls.
  //
  // Closing goes through onRequestClose, the same path as the top-left button,
  // so the shrink-back-to-thumbnail transition is unchanged.
  private onPhotoTap(): void {
    if (Date.now() < this.ignoreTapUntilMs) {
      return;
    }
    if (!this.isVideo() && !this.zoomed()) {
      this.onRequestClose();
      return;
    }
    this.toggleChrome();
  }

  // Double tap zooms around the actual touch point instead of the center of the
  // screen. A second double tap is a quick way back to the fitted 1x image.
  private onPhotoDoubleTap(event: GestureEvent): void {
    if (this.zoomed()) {
      this.resetPhotoZoom(true);
      return;
    }
    let px = 0;
    let py = 0;
    if (event.fingerList.length > 0) {
      px = event.fingerList[0].localX - this.areaW / 2;
      py = event.fingerList[0].localY - this.areaH / 2;
    }
    this.pinchStartScale = VIEWER_DOUBLE_TAP_SCALE;
    animateTo({
      duration: this.effectDuration(KEY_POWER_EFFECT_BLUR, 200), curve: Curve.EaseOut
    }, () => {
      this.photoScale = VIEWER_DOUBLE_TAP_SCALE;
      this.photoOffsetX = px * (1 - VIEWER_DOUBLE_TAP_SCALE);
      this.photoOffsetY = py * (1 - VIEWER_DOUBLE_TAP_SCALE);
      this.clampOffset();
    });
  }

  private entryById(id: number): MessageEntry | null {
    const idx = this.messages.findIndex((m: MessageEntry) => m.id === id);
    return idx >= 0 ? this.messages[idx] : null;
  }

  private entry(): MessageEntry | null {
    return this.entryById(this.viewerMsgId);
  }

  private infoTitle(): string {
    const e: MessageEntry | null = this.entry();
    if (e === null) {
      return this.chatTitle;
    }
    if (this.isVideoEntry(e) && e.videoFileName !== '') {
      return e.videoFileName;
    }
    return e.senderName !== '' ? e.senderName : this.chatTitle;
  }

  private infoSubtitle(): string {
    const e: MessageEntry | null = this.entry();
    if (e === null) {
      return '';
    }
    const ids: number[] = this.siblingIds();
    const index: number = ids.indexOf(this.viewerMsgId);
    const position: string = ids.length > 1 && index >= 0 ? `${index + 1} / ${ids.length} · ` : '';
    return `${position}${formatTime(e.date, this.nowSec)}`;
  }

  // The album (media group) containing the viewer's current message, if any.
  private group(): AlbumGroup | null {
    for (const g of this.groups) {
      if (g.memberIds.indexOf(this.viewerMsgId) >= 0) {
        return g;
      }
    }
    return null;
  }

  // Sibling message ids for swipe/filmstrip navigation — just the current
  // message when it isn't part of a multi-item album.
  private siblingIds(): number[] {
    const g = this.group();
    if (g !== null && g.memberIds.length > 1) {
      return g.memberIds;
    }
    return this.viewerMsgId !== 0 ? [this.viewerMsgId] : [];
  }

  private siblingPath(id: number): string {
    const g = this.group();
    if (g !== null) {
      const idx = g.memberIds.indexOf(id);
      if (idx >= 0 && idx < g.photoPaths.length) {
        return g.photoPaths[idx];
      }
    }
    const idx2 = this.messages.findIndex((m: MessageEntry) => m.id === id);
    return idx2 >= 0 ? this.messages[idx2].photoPath : '';
  }

  private siblingIsVideo(id: number): boolean {
    const idx = this.messages.findIndex((m: MessageEntry) => m.id === id);
    return idx >= 0 && this.isVideoEntry(this.messages[idx]);
  }

  // Best available image for a viewer page: full-res once downloaded, else thumbnail.
  private photoSrcFor(id: number): string {
    const e = this.entryById(id);
    if (e === null) {
      return '';
    }
    const p = e.photoFullPath !== '' ? e.photoFullPath : e.photoPath;
    return p.startsWith('/') ? `file://${p}` : p;
  }

  // Programmatic paging: the Swiper animates the transition; onChange keeps
  // viewerMsgId in sync.
  private switchViewer(delta: number): void {
    if (delta > 0) {
      this.swiperCtrl.showNext();
    } else {
      this.swiperCtrl.showPrevious();
    }
  }

  // Filmstrip tap: page the Swiper to the tapped album member.
  private jumpToSibling(id: number): void {
    const i = this.siblingIds().indexOf(id);
    if (i >= 0) {
      this.swiperCtrl.changeIndex(i, true);
    }
  }

  private onPageChange(index: number): void {
    const ids = this.siblingIds();
    if (index < 0 || index >= ids.length) {
      return;
    }
    const id = ids[index];
    if (id === this.viewerMsgId) {
      this.pageIdx = index;
      return;
    }
    if (this.videoLandscape) {
      this.setVideoLandscape(false);
    }
    this.resetPhotoZoom(false);
    this.pageIdx = index;
    this.viewerMsgId = id;
    if (this.store !== null && !this.siblingIsVideo(id)) {
      this.store.requestFullPhoto(id);
    }
    this.prefetchNeighbours(index);
  }

  private isVideo(): boolean {
    const e = this.entry();
    return e !== null && this.isVideoEntry(e);
  }

  private videoLocalPath(): string {
    const e = this.entry();
    return e !== null ? e.videoPath : '';
  }

  private videoFileId(): number {
    const e = this.entry();
    return e !== null ? e.videoFileId : 0;
  }

  private videoFileSize(): number {
    const e = this.entry();
    return e !== null ? e.videoFileSize : 0;
  }

  private videoMimeType(): string {
    const e = this.entry();
    return e !== null ? e.videoMimeType : '';
  }

  private videoWidth(): number {
    const e = this.entry();
    return e !== null ? e.photoWidth : 0;
  }

  private videoHeight(): number {
    const e = this.entry();
    return e !== null ? e.photoHeight : 0;
  }

  private photoSrc(): string {
    return this.photoSrcFor(this.viewerMsgId);
  }

  private photoUpgrading(): boolean {
    const e = this.entry();
    return e !== null && e.photoFullPath === '' && e.photoFullFileId !== 0 &&
      !e.photoFullFailed;
  }

  private photoProgress(): number {
    const e = this.entry();
    if (e === null) {
      return 0;
    }
    return e.photoFullProgress > 0 ? e.photoFullProgress : e.photoProgress;
  }

  private photoFailed(): boolean {
    const e: MessageEntry | null = this.entry();
    if (e === null) {
      // 条目还没解析出来 ≠ 加载失败。打开的第一帧查看器可能还查不到这条
      // 消息，之前赋值是同步的、这一帧挤不出来；改用 animateTo 挂载做一镜
      // 到底之后，它就露出来了——表现为放大瞬间闪一下"图片加载失败"。
      //
      // 未知一律按加载中处理：条目通常一两帧内就位；真的消息没了，ChatPage
      // 会直接关掉查看器（见它对 viewerMsgId 的守卫），轮不到这里报错。
      return false;
    }
    if (e.photoFullFailed) {
      return true;
    }
    return e.photoPath === '' && e.photoFullPath === '' &&
      e.photoFileId === 0 && e.photoFullFileId === 0;
  }

  private retryPhoto(): void {
    if (this.store === null || this.viewerMsgId === 0) {
      return;
    }
    this.store.retryPhoto(this.viewerMsgId);
  }

  @Builder
  photoLoadingState() {
    Column({ space: 10 }) {
      if (this.photoProgress() > 0) {
        Stack() {
          Progress({ value: this.photoProgress(), total: 100, type: ProgressType.Ring })
            .width(44).height(44).color(Color.White);
          Text(`${this.photoProgress()}%`).fontSize(10).fontColor(Color.White);
        }
      } else {
        LoadingProgress().width(38).height(38).color(Color.White);
      }
      Text($r('app.string.mv_loading')).fontSize(13).fontColor('#D9FFFFFF');
    }
    .padding({ left: 18, right: 18, top: 16, bottom: 16 })
    .backgroundColor(VIEWER_CHROME_BG).borderRadius(16)
    .transition(TransitionEffect.OPACITY
      .combine(TransitionEffect.scale({ x: 0.92, y: 0.92 }))
      .animation({ duration: this.effectDuration(KEY_POWER_EFFECT_BLUR, 180), curve: Curve.EaseOut }));
  }

  @Builder
  photoErrorState() {
    Column({ space: 10 }) {
      SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
        .fontSize(30).fontColor([Color.White]);
      Text($r('app.string.mv_load_failed')).fontSize(14).fontColor(Color.White).fontWeight(FontWeight.Medium);
      Text($r('app.string.tap_to_retry')).fontSize(12).fontColor('#D9FFFFFF');
    }
    .padding({ left: 22, right: 22, top: 16, bottom: 16 })
    .backgroundColor(VIEWER_CHROME_BG).borderRadius(16)
    .stateStyles({
      normal: this.chromeNormalStyle,
      pressed: this.chromePressedStyle
    })
    .animation({ duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 120), curve: Curve.EaseOut })
    .onClick((): void => { this.retryPhoto(); });
  }

  // Fullscreen viewer content: a Swiper over the album's members, so pages
  // follow the finger and slide continuously to the neighbor. Only the CURRENT
  // page mounts a video player; inactive video pages show their thumbnail.
  @Builder
  viewerContent() {
    Swiper(this.swiperCtrl) {
      ForEach(this.siblingIds(), (id: number) => {
        Stack() {
          if (this.siblingIsVideo(id)) {
            if (id === this.viewerMsgId && this.videoFileId() !== 0) {
              StreamingVideoPlayer({
                fileId: this.videoFileId(),
                fileSize: this.videoFileSize(),
                mimeType: this.videoMimeType(),
                videoWidth: this.videoWidth(),
                videoHeight: this.videoHeight(),
                localPath: this.videoLocalPath(),
                posterPath: this.siblingPath(id),
                showControls: this.chromeVisible,
                landscape: this.videoLandscape,
                // 全屏就该有声音，不受气泡自动播放静音开关影响。
                muted: false,
                startPositionMs: id === this.initialViewerMsgId ? this.initStartPositionMs : 0,
                onPositionChanged: (positionMs: number): void => { this.onPositionChanged(positionMs); },
                onBackgroundTap: () => { this.toggleChrome(); },
                onSwipeNext: () => { this.switchViewer(1); },
                onSwipePrev: () => { this.switchViewer(-1); },
                onOrientationChange: (landscape: boolean) => {
                  this.setVideoLandscape(landscape);
                }
              });
            } else {
              if (this.siblingPath(id) !== '') {
                Image(this.siblingPath(id).startsWith('/')
                  ? `file://${this.siblingPath(id)}` : this.siblingPath(id)).draggable(false)
                  .objectFit(ImageFit.Contain).width('100%').height('100%');
              }
              Stack() {
                Circle({ width: 56, height: 56 }).fill('#00000066');
                Text('▶').fontSize(24).fontColor(Color.White);
              }.width(56).height(56);
            }
          } else {
            // Gestures live on this UNSCALED wrapper, not on the Image: a
            // scaled component reports gesture coordinates/offsets in its own
            // scaled space, which made panning lag the finger by the zoom
            // factor. The Image only carries the scale/translate transform.
            Stack() {
              if (this.photoSrcFor(id) !== '') {
                Image(this.photoSrcFor(id)).draggable(false)
                  .objectFit(ImageFit.Contain).width('100%').height('100%')
                  .scale({
                    x: id === this.viewerMsgId ? this.photoScale : VIEWER_MIN_SCALE,
                    y: id === this.viewerMsgId ? this.photoScale : VIEWER_MIN_SCALE
                  })
                  .translate({
                    x: id === this.viewerMsgId ? this.photoOffsetX : 0,
                    y: id === this.viewerMsgId ? this.photoOffsetY : 0
                  });
              }
            }
            .width('100%').height('100%')
            // 一镜到底的落点：与气泡里同一条消息的媒体框绑同一个 id，系统负责
            // 把宽高和位置从缩略图过渡到全屏。
            //
            // 只有当前页绑真实 id——同一时刻一个 id 只能有一对节点，左右邻页
            // 若也绑上，系统就不知道该跟谁配对了。内层 Image 身上挂着捏合缩放
            // 与拖动的 scale/translate，所以绑在外层这个不带变换的 Stack 上，
            // 两套变换才不会打架（官方要求绑定节点的宽高动画不能有跳变）。
            .geometryTransition(id === this.viewerMsgId
              ? `media_${id}` : `media_idle_${id}`)
            // Parallel, not Exclusive. Exclusive has to hold the single tap
            // back until the double-tap window expires, and since a single tap
            // at 1x now closes the viewer, that wait showed up as a stall
            // before the shrink animation started. In parallel the single tap
            // fires on release.
            //
            // The gesture tree stays static on purpose: choosing the recogniser
            // from this.zoomed() looked tidier but left the tap bound to
            // nothing at all, because the binding is not re-evaluated when the
            // condition changes.
            //
            // Consequences, both acceptable. At 1x the first tap closes, so
            // double-tap-to-zoom-in never gets a chance — pinch is the way in.
            // While zoomed, a double tap also fires the single tap twice, which
            // toggles chrome twice and lands back where it started.
            .gesture(
              GestureGroup(GestureMode.Parallel,
                TapGesture({ count: 2, fingers: 1 })
                  .onAction((event: GestureEvent) => { this.onPhotoDoubleTap(event); }),
                TapGesture({ count: 1, fingers: 1 })
                  .onAction(() => { this.onPhotoTap(); })
              )
            )
            .priorityGesture(
              GestureGroup(GestureMode.Parallel,
                PinchGesture({ fingers: 2 })
                  .onActionStart((event: GestureEvent) => { this.onPinchStart(event); })
                  .onActionUpdate((event: GestureEvent) => { this.onPinchUpdate(event); })
                  .onActionEnd(() => { this.onPinchEnd(); })
                  .onActionCancel(() => { this.onPinchEnd(); }),
                // Dynamic distance resolves the Swiper conflict (official
                // best practice): a large threshold at 1x lets the Swiper's
                // own pan win and page the album; a small one while zoomed
                // keeps single-finger panning responsive.
                PanGesture({ fingers: 1, distance: this.zoomed() ? 3 : 50 })
                  .onActionStart(() => { this.onPanStart(); })
                  .onActionUpdate((event: GestureEvent) => { this.onPanUpdate(event); })
                  .onActionEnd(() => { this.onPanEnd(); })
              )
            );
          }
        }.width('100%').height('100%');
      }, (id: number) => `vm_${id}`);
    }
    .indicator(false)
    .loop(false)
    .index(this.pageIdx)
    // While enlarged, one-finger movement must not page the album out from
    // under the zoomed photo. Resetting to 1x re-enables normal paging.
    .disableSwipe(this.zoomed() || this.videoLandscape)
    .onChange((i: number) => { this.onPageChange(i); })
    .onAreaChange((_old: Area, area: Area) => {
      this.areaW = Number(area.width);
      this.areaH = Number(area.height);
    })
    .width('100%').height('100%');
    if (!this.isVideo() && this.photoSrc() === '') {
      Column() {
        if (this.photoFailed()) {
          this.photoErrorState();
        } else {
          this.photoLoadingState();
        }
      }
      .width('100%').height('100%')
      .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
      .hitTestBehavior(HitTestMode.Transparent);
    } else if (!this.isVideo() && this.photoUpgrading() && this.chromeVisible) {
      Row({ space: 7 }) {
        LoadingProgress().width(15).height(15).color(Color.White);
        Text(this.photoProgress() > 0
          ? str('mv_loading_full_pct', this.photoProgress()) : $r('app.string.mv_loading_full'))
          .fontSize(12).fontColor(Color.White);
      }
      .padding({ left: 11, right: 11, top: 7, bottom: 7 })
      .backgroundColor(VIEWER_CHROME_BG).borderRadius(16)
      .position({ x: 14, y: this.topSafe + 76 })
      .hitTestBehavior(HitTestMode.None)
      .transition(TransitionEffect.OPACITY
        .combine(TransitionEffect.translate({ y: -5 }))
        .animation({ duration: this.effectDuration(KEY_POWER_EFFECT_BLUR, 160), curve: Curve.EaseOut }));
    } else if (!this.isVideo() && this.photoFailed() && this.chromeVisible) {
      Row({ space: 6 }) {
        SymbolGlyph($r('sys.symbol.arrow_clockwise')).fontSize(14).fontColor([Color.White]);
        Text($r('app.string.mv_full_failed')).fontSize(12).fontColor(Color.White);
      }
      .padding({ left: 11, right: 11, top: 7, bottom: 7 })
      .backgroundColor(VIEWER_CHROME_BG).borderRadius(16)
      .position({ x: 14, y: this.topSafe + 76 })
      .onClick((): void => { this.retryPhoto(); });
    }
  }

  // Thumbnail strip for the current message's album (photo/video list) —
  // tap a thumbnail to switch the viewer to that item.
  @Builder
  viewerFilmstrip() {
    Scroll() {
      Row({ space: 6 }) {
        ForEach(this.siblingIds(), (id: number) => {
          Stack() {
            if (this.siblingPath(id) !== '') {
              Image(this.siblingPath(id).startsWith('/') ? `file://${this.siblingPath(id)}` : this.siblingPath(id)).draggable(false)
                .width(52).height(52).borderRadius(6).objectFit(ImageFit.Cover);
            } else {
              Column().width(52).height(52).borderRadius(6).backgroundColor('#333333');
            }
            if (this.siblingIsVideo(id)) {
              Text('▶').fontSize(14).fontColor(Color.White);
            }
          }
          .width(52).height(52)
          .border({ width: id === this.viewerMsgId ? 2 : 0, color: Color.White })
          .borderRadius(6)
          .opacity(id === this.viewerMsgId ? 1 : 0.68)
          .scale({ x: id === this.viewerMsgId ? 1 : 0.92, y: id === this.viewerMsgId ? 1 : 0.92 })
          .animation({
            duration: this.effectDuration(KEY_POWER_EFFECT_BLUR, 160),
            curve: Curve.EaseOut
          })
          .onClick(() => { this.jumpToSibling(id); });
        }, (id: number) => `film_${id}`);
      }.padding({ left: 12, right: 12 });
    }.scrollable(ScrollDirection.Horizontal).width('100%');
  }

  @Builder
  chromeLayer() {
    // Content-height wrapper pinned to the top — a full-screen wrapper here
    // (default hit-test mode) would block ALL touches on the player below it.
    Row() {
      Row({ space: 10 }) {
        Stack() {
          Circle({ width: 36, height: 36 }).fill('#12000000');
          SymbolGlyph($r('sys.symbol.xmark')).fontSize(18).fontColor([Color.White]);
        }
        .width(40).height(40).borderRadius(20)
        .stateStyles({
          normal: this.chromeNormalStyle,
          pressed: this.chromePressedStyle
        })
        .animation({
          duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 120),
          curve: Curve.EaseOut
        })
        .onClick(() => { this.onRequestClose(); });
        Column({ space: 1 }) {
          Text(this.infoTitle()).fontSize(13).fontColor(Color.White).fontWeight(FontWeight.Medium)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            .constraintSize({ maxWidth: 220 });
          if (this.infoSubtitle() !== '') {
            Text(this.infoSubtitle()).fontSize(11).fontColor('#BFFFFFFF')
              .maxLines(1);
          }
        }
        .alignItems(HorizontalAlign.Start).flexShrink(1);
      }
      .padding({ left: 12, right: 14, top: 10, bottom: 10 })
      .backgroundColor(VIEWER_CHROME_BG)
      .borderRadius(18)
      .alignItems(VerticalAlign.Center)
      .flexShrink(1);
      Blank().layoutWeight(1).hitTestBehavior(HitTestMode.None);
      // No download indicator up here: the seek bar's lighter track shows
      // the downloaded span, and a stalled player draws a centered ring.
      // "⋮" menu — 保存到相册 etc.
      Stack() {
        Circle({ width: 36, height: 36 }).fill(VIEWER_CHROME_BG);
        SymbolGlyph($r('sys.symbol.more')).fontSize(18).fontColor([Color.White]);
      }
      .width(40).height(40).borderRadius(20)
      .stateStyles({
        normal: this.chromeNormalStyle,
        pressed: this.chromePressedStyle
      })
      .animation({
        duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 120),
        curve: Curve.EaseOut
      })
      .bindMenu([{
        value: $r('app.string.ms_save_to_gallery'),
        action: (): void => { this.onSaveMedia(); }
      } as MenuElement]);
    }
    .width('100%')
    .position({ x: 0, y: 0 })
    .padding({ left: 12, right: 12, top: this.topSafe + 12 })
    .transition(TransitionEffect.OPACITY
      .combine(TransitionEffect.translate({ y: -8 }))
      .animation({
        duration: this.effectDuration(KEY_POWER_EFFECT_BLUR, 180),
        curve: Curve.EaseOut
      }));
  }

  build() {
    Stack() {
      this.viewerContent();
      if (this.chromeVisible) {
        this.chromeLayer();
      }
      if (this.chromeVisible && this.siblingIds().length > 1) {
        Column() {
          this.viewerFilmstrip();
        }
        .width('100%').height('100%')
        .justifyContent(FlexAlign.End)
        .padding({ bottom: this.isVideo() ? 110 : 30 })
        .hitTestBehavior(HitTestMode.Transparent)
        .transition(TransitionEffect.OPACITY
          .combine(TransitionEffect.translate({ y: 10 }))
          .animation({
            duration: this.effectDuration(KEY_POWER_EFFECT_BLUR, 180),
            curve: Curve.EaseOut
          }));
      }
    }
    .width('100%').height('100%').backgroundColor(Color.Black)
    // The fullscreen surface owns its transition. The chat thumbnail stays
    // mounted and decoded underneath, so closing can never leave that cell
    // as a grey/background placeholder or an empty Image node.
    // 只留不透明度：几何过渡已经交给 geometryTransition（气泡 ↔ 全屏图），
    // 这里再叠一套"从点击点缩放"就是两套几何动画抢同一个节点。tapX/tapY
    // 仍然保留着，回退到这套转场时不用重新接线。
    .transition(
      TransitionEffect.OPACITY
        .animation({ duration: this.effectDuration(KEY_POWER_EFFECT_BLUR, 300), curve: Curve.Friction })
    );
  }
}
