import { common } from '@kit.AbilityKit';
import { overlayBackdropBlur, overlayGlassFill } from '../../util/overlayMaterial';
import { materialModifier } from '../../util/materialModifier';
import {
  hopDirection, hopProgress, nextMediaGroupIndex
} from '../../util/viewerGroupHop';
import { MessageEntry } from '../../store/MessageEntry';
import { MessageStore } from '../../store/MessageStore';
import { AlbumGroup } from '../../util/collapseAlbums';
import { formatTime } from '../../util/formatTime';
import { StreamingVideoPlayer } from './StreamingVideoPlayer';
import { isLivePhotoVideo } from '../../util/livePhoto';
import { extractFirstFrame, saveMovingPhoto } from '../../util/livePhotoSave';
import { fileIo as fs } from '@kit.CoreFileKit';
import { promptAction } from '@kit.ArkUI';
import { logE } from '../../util/log';
import { setMediaViewerOrientation } from './LiveViewerUi';
import { thumbPathFor } from '../../util/mediaThumbChannel';
import {
  KEY_CURRENT_NETWORK_TYPE, KEY_POWER_EFFECT_BLUR, KEY_POWER_SMOOTH_TRANSITIONS, powerAnimationDuration
} from '../../store/AppSettings';
import { str } from '../../util/strings';
import { MediaContext, shouldPrefetchNeighbour } from '../../store/MediaPolicy';

// 控制层的底色。材质接管时它会被 overlayGlassFill 清成透明（不透明底色会盖在
// 材质层之上，官方常见问题写死），只有低于 API 26 时才真正画出来——那时
// overlayMaterial 里持有的 viewer 回退色和这个是同一个值，观感不变。
const VIEWER_CHROME_BG: string = '#6e3e3e40';
// 顶部通栏里那一行（状态栏之下）的高度。加上 topSafe 才是整条栏的高度，
// 而底下那两个提示胶囊挂在 topSafe + 76 上——56 给它们留出了余量。
const CHROME_BAR_ROW_H: number = 56;
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
// 状态管理 V2（P3 批 2 第 2 项）。迁移的理由是还债，不是顺手统一：V1 的 @Prop
// 对复杂类型是**深拷贝**，而且是单向**同步** —— 父组件里的源每换一次新数组就
// 重拷一次。查看器开着的时候，页面的 messages 每跳一次下载进度就换一个新数组，
// 几百个 MessageEntry 会整体深拷一遍（下面 messages 那条注释里预告的就是这件
// 事）。V2 的 @Param 是引用传递，这笔债到此还清。
@ComponentV2
export struct MediaViewerOverlay {
  // V2 没有 @StorageProp 的等价物，三个全局键（语言纪元 / 材质纪元 / 顶部安全区）
  // 改由页面透传——页面自己就持有它们。
  @Param langEpoch: number = 0;
  // 单向入 + 回调出，而不是 @Link：@Link 只能被 V1 状态变量初始化，页面已经是
  // 状态管理 V2，接不上。翻页/关闭时先改本地副本，再把新值交给页面，页面回灌
  // 同一个值，语义与双向同步等价。
  //
  // @Param @Once（不是裸 @Param）：@Param 只读，而这三个变量组件内部要改。官方
  // 《组件内状态变量迁移》@Prop -> @Param 第三条：「如果子组件需要修改传入的
  // 参数，使用 @Once 允许子组件在本地修改该变量」。代价是「后续无父组件到子
  // 组件的同步能力」，这里付得起：页面侧对这三个变量的写入只发生在**打开**
  // （onMediaTap，本组件尚未构造）和**关闭**（closeViewer，本组件正被 if 摘掉）
  // 两处，查看器开着的整段时间里页面一次都不往下推新值。
  @Param @Once viewerMsgId: number = 0;
  @Event onViewerMsgIdChange: (msgId: number) => void = (): void => {};
  @Param @Once chromeVisible: boolean = true;
  @Event onChromeVisibleChange: (visible: boolean) => void = (): void => {};
  // 材质档位是设置里的用户偏好，而 overlayMaterial 那几个是普通函数、订阅不了
  // AppStorage。跟着这个纪元走，用户改了厚度/光感这一层才会重绘（和别处一样）。
  // 去掉了 private：@Param 要由父组件构造传参。
  @Param materialEpoch: number = 0;
  // @Param（不是普通字段）：普通字段会冻结在构造时的值，历史加载进来之后查看器
  // 就翻不动相册了。@Param 走引用，不再有 @Prop 的整表深拷贝。
  @Param messages: MessageEntry[] = [];
  @Param groups: AlbumGroup[] = [];
  // 越界方向上已加载的消息里没有下一组媒体时调用（dir 同 hopDirection 的约定，
  // -1 = 要更旧的历史）。groups 是从**已加载的聊天窗口**折叠出来的，窗口边缘
  // 不等于会话边缘——不补历史的话，切几组就"到头"，其实服务器上还有。
  @Event onNeedHistory: (dir: number) => void = (): void => {};

  @Param topSafe: number = 0;

  // Window coordinates (vp) of the tap that opened the viewer — anchor for the
  // expand-from-tap open / shrink-back-to-tap close transition. The transition
  // lives on this component's own root Stack rather than on the component
  // instance in the page: `.transition()` is documented for containers and
  // their inserted/removed children, not for custom-component instances. The
  // page's `if` removing this component still triggers it, because removal
  // recursively fires the transitions of everything being removed.
  @Param tapX: number = 0;
  @Param tapY: number = 0;

  // Set once at construction by the page (index of the tapped album member).
  // @Param 而不是无装饰器成员：V2 里无装饰器成员是纯本地常量，父组件初始化它
  // 是编译错误 10905324（P3 批 1 实测）。下面几个同理。
  @Param initIdx: number = 0;
  // Bubble→viewer handoff: the play position the page had recorded for the
  // tapped message (see ChatPage.bubblePositionMs), read once here just like
  // initIdx. Only applies to that one message — a different album member
  // reached by swiping starts at 0, since it never had a bubble play slot in
  // this session.
  @Param initStartPositionMs: number = 0;
  @Param store: MessageStore | null = null;
  @Param chatTitle: string = '';
  @Param nowSec: number = 0;

  // 全部函数型入参一律 @Event，包括这两个「查询型」的。理由是观测能力：调用点
  // 传的是**内联箭头函数**，页面每重建一次都是一个新闭包，若用 @Param，那个
  // `!==` 恒不相等，本层就会跟着页面的每一次重建白刷一遍。@Event 不具备观测
  // 能力，正好复现迁移前「普通字段只在构造时赋值一次」的行为。官方《@Event》：
  // 「@Event 装饰的回调方法中参数以及返回值由开发者决定」——带返回值是允许的。
  @Event effectDuration: (key: string, ms: number) => number =
    (_key: string, ms: number): number => ms;
  @Event isVideoEntry: (entry: MessageEntry) => boolean = (): boolean => false;
  @Event onRequestClose: () => void = (): void => {};
  @Event onSaveMedia: () => void = (): void => {};
  // 保存到文件（首次授权 Download，之后保存到 Download/Petrelgram）——issue #97/#65。
  @Event onSaveMediaToFiles: () => void = (): void => {};
  // Viewer→bubble handoff (the other direction): the page samples this on
  // every tick and writes it back to bubblePositionMs when the viewer closes.
  // 350ms-ish cadence from StreamingVideoPlayer, same "plain field, no @State"
  // reasoning as the bubble side.
  @Event onPositionChanged: (positionMs: number) => void = (_positionMs: number): void => {};
  // Captured once in aboutToAppear: which message initStartPositionMs belongs
  // to, since viewerMsgId itself moves as the user swipes.
  private initialViewerMsgId: number = 0;

  @Local pageIdx: number = 0;
  // 横屏状态页面也要看得见：它的 onBackPress 得先认出"现在是横屏"、先退横屏
  // 而不是关查看器。同样走 @Prop + 回调而不是 @Link。
  @Param @Once videoLandscape: boolean = false;
  @Event onVideoLandscapeChange: (landscape: boolean) => void = (): void => {};
  // Zoom is viewer-owned. Keeping it out of the message row prevents the
  // gesture from mutating a recycled Image node in the chat list.
  //
  // Model (per the official picture-preview best practice): the Image scales
  // around its own center and pans via translate, so screen = offset + scale
  // * content-point (measured from the image center). Pinch anchoring and
  // boundary clamping are both computed against that model.
  @Local photoScale: number = VIEWER_MIN_SCALE;
  @Local photoOffsetX: number = 0;
  @Local photoOffsetY: number = 0;

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
  // 下滑关闭：整层（图片 + 控制层）跟着手指往下走的位移。松手时要么越过阈值
  // 关闭，要么弹回 0。
  @Local private dismissY: number = 0;
  // 越界切组：方向（+1 下一组 / -1 上一组 / 0 无）、拉拽进度 0..1、目标组下标。
  // 松手时按 hopProgress 是否到 1 决定切还是弹回。
  @Local private hopDir: number = 0;
  @Local private hopProgress: number = 0;
  private hopTargetIdx: number = -1;
  // 缩略图条自己的滚动控制器。切组之后内容会整体换掉（siblingIds 从
  // viewerMsgId 推出来），但横向偏移不会自动回位——往前切落在新组的最后一张
  // 时，那张会停在屏幕右边看不见的地方。
  private filmScroller: Scroller = new Scroller();
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
    this.onVideoLandscapeChange(landscape);
    this.chromeVisible = true;
    this.onChromeVisibleChange(true);
    setMediaViewerOrientation(getContext(this) as common.UIAbilityContext, landscape);
  }

  private toggleChrome(): void {
    const next: boolean = !this.chromeVisible;
    this.chromeVisible = next;
    this.onChromeVisibleChange(next);
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

  // 1x 下拖：整层跟着手指走。只跟随向下，往上拖不动——向上没有"退出"的语义，
  // 让它跟手只会让用户以为还有别的东西可以拉出来。
  private onDismissUpdate(event: GestureEvent): void {
    this.dismissY = Math.max(0, event.offsetY);
  }

  // 松手：越过阈值就关，否则弹回。阈值取视口高度的 1/5，比写死一个 vp 数更
  // 跨设备一致——pad 上 120vp 只是轻轻一划，手机上却已经是小半屏。
  private onDismissEnd(): void {
    const threshold: number = Math.max(80, this.areaH / 5);
    if (this.dismissY >= threshold) {
      this.onRequestClose();
      return;
    }
    animateTo({
      duration: this.effectDuration(KEY_POWER_EFFECT_BLUR, 220), curve: Curve.Friction
    }, () => { this.dismissY = 0; });
  }

  // 下滑过程中背景由黑渐透，露出底下的聊天页——"整层往下走然后退出"这件事
  // 靠这个才读得出来，否则只是一张图在黑幕里滑动。
  private dismissProgress(): number {
    const span: number = Math.max(1, this.areaH / 3);
    return Math.min(1, this.dismissY / span);
  }

  private onPanEnd(): void {
    if (!this.zoomed()) {
      this.onDismissEnd();
      return;
    }
    if (Math.abs(this.edgeOverscroll) < 60) {
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
      this.onDismissUpdate(event);
      return;
    }
    const desiredX: number = this.panStartOffsetX + event.offsetX;
    this.photoOffsetX = desiredX;
    this.photoOffsetY = this.panStartOffsetY + event.offsetY;
    this.clampOffset();
    // clamp 吃掉的水平位移就是"已经贴边还在继续拖"的量。
    this.edgeOverscroll = desiredX - this.photoOffsetX;
  }

  // 单击一律切换控制层的显隐，**不再关闭查看器**。
  //
  // 原来 1x 的图片上单击是关闭（照官方端的行为）。改掉是因为那让"看清这张图"
  // 和"退出"抢同一个手势：想把顶栏和缩略图条收起来只看图，唯一的办法反而是
  // 退出去。现在收起控制层交给单击，退出交给下滑（onDismissUpdate），两个
  // 意图各有各的手势。
  //
  // 视频本来就是切换，不受影响。
  private onPhotoTap(): void {
    if (Date.now() < this.ignoreTapUntilMs) {
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

  // 这一行是不是媒体行。用户拉的是"下一组媒体"，中间隔着几十条文字消息不该
  // 让这个动作失效，所以要能跳过非媒体行。
  private groupIsMedia(index: number): boolean {
    const g = this.groups[index];
    return g !== undefined &&
      (g.head.contentType === 'photo' || this.isVideoEntry(g.head));
  }

  private currentGroupIndex(): number {
    return this.groups.findIndex(
      (g: AlbumGroup): boolean => g.memberIds.indexOf(this.viewerMsgId) >= 0);
  }

  // Swiper 拖动中：判断有没有越界，以及拉了多少。
  private onSwiperGesture(offset: number): void {
    const ids: number[] = this.siblingIds();
    const dir: number = hopDirection(this.pageIdx, ids.length, offset);
    if (dir === 0) {
      this.clearHop();
      return;
    }
    if (dir !== this.hopDir) {
      // 换了方向：重新找目标组。找不到就当没越界——没有下一组时不该弹气泡。
      const from: number = this.currentGroupIndex();
      const target: number = from < 0 ? -1 : nextMediaGroupIndex(
        this.groups.length, from, dir,
        (i: number): boolean => this.groupIsMedia(i));
      if (target < 0) {
        // 已加载的消息里没有这一方向的下一组。多半是历史窗口没拉到那儿，先把
        // 那个方向的历史翻一页；消息一到 groups 会自己更新，用户再拉一次就能
        // 切过去。这一次先当没越界处理。
        this.onNeedHistory(dir);
        this.clearHop();
        return;
      }
      this.hopTargetIdx = target;
      this.hopDir = dir;
    }
    // 阈值随视口宽度走：pad 上 80vp 只是轻轻一带，手机上已经是小半屏。
    this.hopProgress = hopProgress(offset, Math.max(80, this.areaW / 4));
  }

  private clearHop(): void {
    if (this.hopDir === 0 && this.hopProgress === 0) {
      return;
    }
    this.hopDir = 0;
    this.hopProgress = 0;
    this.hopTargetIdx = -1;
  }

  // 松手：拉够了就切组，没拉够就把气泡收回去、什么都不做。
  private settleHop(): void {
    const dir: number = this.hopDir;
    const target: number = this.hopTargetIdx;
    if (dir === 0 || target < 0 || this.hopProgress < 1) {
      animateTo({
        duration: this.effectDuration(KEY_POWER_EFFECT_BLUR, 180), curve: Curve.Friction
      }, () => { this.clearHop(); });
      return;
    }
    this.clearHop();
    const g = this.groups[target];
    if (g === undefined || g.memberIds.length === 0) {
      return;
    }
    // 往后切落在新组的第一张，往前切落在最后一张——都是"接着刚才的方向继续
    // 看下去"的那一张，而不是让用户从组的另一头重新开始。
    const landing: number = dir > 0 ? g.memberIds[0] : g.memberIds[g.memberIds.length - 1];
    this.resetPhotoZoom(false);
    this.dismissY = 0;
    // 与 onPageChange 同一个理由：换了消息就把胶囊打回「未播放」。这条是**越界
    // 切组**那条换页路，不经过 onPageChange，漏掉它就会在跨组时残留暂停图标。
    // 旧播放器卸载兜不住——livePlaying 住在本组件上，而新播放器在预热模式下
    // 从头到尾不会报一次 true。
    this.livePlaying = false;
    this.viewerMsgId = landing;
    this.onViewerMsgIdChange(landing);
    this.pageIdx = dir > 0 ? 0 : g.memberIds.length - 1;
    this.prefetchNeighbours(this.pageIdx);
    // 缩略图条的内容随 viewerMsgId 自动换掉，但滚动偏移不会——手动带回去。
    // 放在下一帧：这一帧新的那批缩略图还没挂上，量不出位置。
    const landingIdx: number = this.pageIdx;
    setTimeout((): void => { this.scrollFilmstripTo(landingIdx); }, 0);
  }

  // 气泡里那张缩略图。目标组的封面：往后切给第一张，往前切给最后一张，
  // 和真正会落到的那一张保持一致。
  private hopThumbPath(): string {
    const g = this.groups[this.hopTargetIdx];
    if (g === undefined || g.photoPaths.length === 0) {
      return '';
    }
    const p: string = this.hopDir > 0
      ? g.photoPaths[0] : g.photoPaths[g.photoPaths.length - 1];
    return p !== '' && p.startsWith('/') ? `file://${p}` : p;
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

  // 查看器里那张"预览图"（大图没解码出来之前顶上的缩略图，以及底部胶片条）。
  //
  // **先问旁路通道，再看行对象**（用户报：图片组放大之后预览图不展示）。
  // AlbumGroup.photoPaths 是**刻意不进行 key** 的（见 collapseAlbums：缩略图路径
  // 走 mediaThumbChannel 直达气泡，进 key 会让每张图落地都拖着整行重建）。代价是
  // reuseUnchangedRows 在 key 没变时**把旧行对象还回来**，于是缩略图落地之后
  // photoPaths 永远停在 ''——AlbumGroupDataSource.test 里那条
  // `prefetch_source_must_be_fed_the_fresh_rows_not_the_merged_ones` 钉的就是它。
  // 气泡不受影响（LiveThumbImage 自己订阅通道），**只有查看器**这一处直接读行对象，
  // 所以只有它拿到空路径：大图照常出来（photoSrcFor 读的是新鲜的 entry），
  // 预览图却是空的。这与 453c00f 修掉的 photoFailed 是同一类问题的另一处。
  //
  // 修法不是把 photoPaths 塞回 key 或 sameRenderSnapshot——那正是重建风暴的来源。
  // 通道按 fileId 索引、永远是最新的，而 photoFileIds **在** key 里（所以是新鲜的）。
  private siblingPath(id: number): string {
    const g = this.group();
    if (g !== null) {
      const idx = g.memberIds.indexOf(id);
      if (idx >= 0 && idx < g.photoPaths.length) {
        const fileId: number = idx < g.photoFileIds.length ? g.photoFileIds[idx] : 0;
        const live: string = fileId !== 0 ? thumbPathFor(fileId) : '';
        if (live !== '') {
          return live;
        }
        if (g.photoPaths[idx] !== '') {
          return g.photoPaths[idx];
        }
        // 行对象和通道都没有：往下走 entry 那一支（this.messages 是每次发布都换
        // 的新鲜列表，不受 reuseUnchangedRows 影响）。
      }
    }
    const idx2 = this.messages.findIndex((m: MessageEntry) => m.id === id);
    if (idx2 < 0) {
      return '';
    }
    const entry: MessageEntry = this.messages[idx2];
    const live: string = entry.photoFileId !== 0 ? thumbPathFor(entry.photoFileId) : '';
    return live !== '' ? live : entry.photoPath;
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
    this.dismissY = 0;
    this.resetPhotoZoom(false);
    // 翻页要显式把胶囊打回「未播放」。**改成不自动播之后这一句才成为必需**：
    // 原来它是靠「新播放器 onPrepared 报一次 true」被隐式拉回的，现在那一下没有
    // 了（@Watch 不在初始赋值时触发，新播放器的 isPlaying 初值 false 不产生变化
    // 事件）。漏掉的话，从一张播过的实况翻到下一张，胶囊会残留暂停图标而画面
    // 其实是静止的。
    this.livePlaying = false;
    this.pageIdx = index;
    this.viewerMsgId = id;
    this.onViewerMsgIdChange(id);
    if (this.store !== null && !this.siblingIsVideo(id)) {
      this.store.requestFullPhoto(id);
    }
    this.prefetchNeighbours(index);
    // 组内翻页也把缩略图条带过去：不然翻到第七张时高亮的那一格还在条外面。
    this.scrollFilmstripTo(index);
  }

  private isVideo(): boolean {
    const e = this.entry();
    return e !== null && this.isVideoEntry(e);
  }

  private videoLocalPath(): string {
    const e = this.entry();
    return e !== null ? e.videoPath : '';
  }

  // ── 实况照片（util/livePhoto）───────────────────────────────────────────
  // PG 发出去的实况在协议上就是一段普通有声视频，只有文件名带标记。这里认出来
  // 之后按 iOS 的样子渲染：**进来停在静态首帧**，左下角一枚「实况」胶囊，点一下
  // 才开始播；标准控制栏关掉，给胶囊让位。
  //
  // 「停在首帧」不是靠不起播实现的——那样屏幕上只有 TDLib 那张低清缩略图。
  // 播放器侧走的是「静音预热到真首帧再暂停」，见 StreamingVideoPlayer 的
  // primingFirstFrame。这里要做的只有三件：liveMode 传下去、胶囊初值改成
  // 「未播放」、以及翻页时把它显式重置。
  //
  // 别的客户端发的视频一概不走这条路——判定要文件名标记 + 时长 ≤10s 同时成立。
  @Local private liveToggleSeq: number = 0;
  // 胶囊图标跟随播放器的真实状态，由 onPlayStateChanged 回报。初值 false：
  // 进来停在静态首帧，图标是播放三角。
  //
  // **只改这个初值没有用**——播放器一 start 就会经 onPlayStateChanged 把它翻回
  // 来，必须和 StreamingVideoPlayer 侧的 liveMode 分支配套。
  @Local private livePlaying: boolean = false;

  private isLiveEntry(id: number): boolean {
    const idx: number = this.messages.findIndex((m: MessageEntry) => m.id === id);
    if (idx < 0) {
      return false;
    }
    const e: MessageEntry = this.messages[idx];
    return this.isVideoEntry(e) && isLivePhotoVideo(e.videoFileName, e.videoDuration);
  }

  private isLiveNow(): boolean {
    return this.isLiveEntry(this.viewerMsgId);
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
    .backgroundColor(overlayGlassFill('viewer', VIEWER_CHROME_BG)).borderRadius(16)
    .backdropBlur(overlayBackdropBlur('viewer'))
    .attributeModifier(materialModifier('viewer'))
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
    .backgroundColor(overlayGlassFill('viewer', VIEWER_CHROME_BG)).borderRadius(16)
    .backdropBlur(overlayBackdropBlur('viewer'))
    .attributeModifier(materialModifier('viewer'))
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
  // 左下角的「实况」胶囊。标准元素：同心圆图标（sys.symbol.livephoto，暂停时
  // 用 livephoto_slash 的斜杠版）+ 文案，点一下切换播放/暂停，播完点它重播。
  //
  // 位置选在标准控制栏原本占的那条带子上（底部 40vp 左右）：实况把控制栏关掉了，
  // 那块地方空着，而缩略图带在更上面的 110vp，两者不会打架。
  // 把这条实况存回图库，变回一张**真的**动态照片而不是一段视频。
  //
  // 必须挂在 SaveButton 的 onClick 里：创建动态照片资产只有 createAssetRequest
  // 那一条路，而它要么申请常驻的媒体写权限、要么由用户点一次安全控件临时授权。
  // 本应用一贯避开常驻权限，所以用后者——理由与推导见 util/livePhotoSave。
  private async saveLiveToGallery(): Promise<void> {
    const video: string = this.videoLocalPath();
    if (video === '') {
      // 还没下完就没有本地文件可存。
      promptAction.showToast({ message: str('media_save_failed'), duration: 1800 });
      return;
    }
    const ctx = getContext(this) as common.UIAbilityContext;
    const still: string = `${ctx.filesDir}/live_save_${Date.now()}.jpg`;
    try {
      // 静图那一半从视频里抽首帧，而不是拿 TDLib 的缩略图——缩略图只有几百像素
      // 宽，而这张就是用户之后在图库里看到的照片。
      const ok: boolean = await extractFirstFrame(
        video, still, this.videoWidth(), this.videoHeight());
      if (!ok) {
        promptAction.showToast({ message: str('media_save_failed'), duration: 1800 });
        return;
      }
      await saveMovingPhoto(ctx, still, video, `live_${Date.now()}`);
      promptAction.showToast({ message: str('media_saved_gallery'), duration: 2000 });
    } catch (error) {
      logE(`MediaViewer.saveLiveToGallery failed: ${error}`);
      promptAction.showToast({ message: str('media_save_failed'), duration: 1800 });
    } finally {
      // 抽出来的首帧只是中转，落库之后就没用了。删不掉不该打断流程。
      try {
        fs.unlinkSync(still);
      } catch (error) {
        logE(`MediaViewer.saveLiveToGallery cleanup failed: ${error}`);
      }
    }
  }

  // 「存为实况」。放在右下角，和左下角那枚实况胶囊分居两侧，互不遮挡。
  @Builder
  liveSaveButton() {
    Column() {
      SaveButton({
        icon: SaveIconStyle.FULL_FILLED,
        text: SaveDescription.SAVE_IMAGE,
        buttonType: ButtonType.Capsule
      })
        .onClick((event: ClickEvent, result: SaveButtonOnClickResult): void => {
          if (result !== SaveButtonOnClickResult.SUCCESS) {
            return;
          }
          this.saveLiveToGallery();
        });
    }
    .width('100%').height('100%')
    .justifyContent(FlexAlign.End)
    .alignItems(HorizontalAlign.End)
    .padding({ right: 16, bottom: 40 })
    .hitTestBehavior(HitTestMode.Transparent);
  }

  @Builder
  liveCapsule() {
    Column() {
      Row({ space: 5 }) {
        // 三个时刻都是播放键：刚打开（停在静态首帧）、用户按停、播完
        // （onCompletion 会把 isPlaying 置 false）——一眼就知道点它能看动的那份；
        // 播放中则是标准的同心圆实况标，点它暂停。
        SymbolGlyph($r(this.livePlaying ? 'sys.symbol.livephoto' : 'sys.symbol.play_fill'))
          .fontSize(17).fontColor([Color.White]);
        Text($r('app.string.cp_live_photo'))
          .fontSize(13).fontColor(Color.White).fontWeight(FontWeight.Medium);
      }
      .height(30)
      .padding({ left: 10, right: 12 })
      .backgroundColor('#66000000')
      .borderRadius(15)
      .onClick((): void => { this.liveToggleSeq++; });
    }
    .width('100%').height('100%')
    .justifyContent(FlexAlign.End)
    .alignItems(HorizontalAlign.Start)
    .padding({ left: 16, bottom: 44 })
    .hitTestBehavior(HitTestMode.Transparent);
  }

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
                // 实况走自己的胶囊，标准控制栏（进度条/倍速）让位。
                showControls: this.chromeVisible && !this.isLiveEntry(id),
                liveMode: this.isLiveEntry(id),
                liveToggleSeq: this.liveToggleSeq,
                onPlayStateChanged: (playing: boolean): void => { this.livePlaying = playing; },
                landscape: this.videoLandscape,
                // 全屏就该有声音，不受气泡自动播放静音开关影响。
                muted: false,
                // 实况恒从 0 起。续播位是给普通视频的——从一条播到一半的实况
                // 气泡点进来，停在中途那一帧当「静态照片」是不对的。
                startPositionMs: (id === this.initialViewerMsgId && !this.isLiveEntry(id))
                  ? this.initStartPositionMs : 0,
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
            // 每一页永久绑自己的 id，**绝不在活节点上改 id**。
            //
            // 原来是「只有当前页绑真 id，其余绑 media_idle_<id>」，翻页时同一个
            // 活节点的 id 会来回改。日志证实这一侧的取值全程正确（当前页总是
            // 真 id，关闭时也对得上），可退出动画的落点仍然错——说明框架的配对
            // 登记不跟着活节点的 id 走，退场时按最初登记的那一页去找落点，
            // 于是翻过页就落在第一张的位置上。不翻页正好没暴露。
            //
            // 静态之后每个 id 恰好一对节点：相册里的那一格 + 查看器里的那一页，
            // 正是 geometryTransition 要求的形状，动画仍由节点的出现/消失驱动。
            .geometryTransition(`media_${id}`)
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
            // 并行组的后果：一次双击也会把单击触发两次。单击现在是切换控制层
            // 的显隐，切两次等于没切，落回原样——所以双击放大在 1x 上现在是
            // 真的可用了。（以前 1x 的单击是关闭查看器，第一下就把整层关掉，
            // 双击根本没有机会成立，进放大只能靠双指捏合。）
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
                // 放大态：全方向、阈值小，单指拖动平移图片。
                // 1x：**只认竖直**，横向原样留给 Swiper 翻页——这比原来单靠
                // 一个大阈值（50）挡住横向更可靠，那样横向拖过 50vp 仍会把
                // Swiper 的手势抢走。竖直方向拖的是"下滑关闭"，阈值取 20 让
                // 它跟手，又不至于被列表式的轻微竖向抖动误触发。
                PanGesture({
                  fingers: 1,
                  distance: this.zoomed() ? 3 : 20,
                  direction: this.zoomed() ? PanDirection.All : PanDirection.Vertical
                })
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
    // 拖动中上报当前位移。停在头/尾还继续往外拖时，这个值会越过 0 继续走，
    // 那段就是"越界量"——切组的气泡跟着它长。
    .onGestureSwipe((_index: number, extra: SwiperAnimationEvent) => {
      this.onSwiperGesture(extra.currentOffset);
    })
    // 松手的判定放在 onTouch 而不是 onAnimationStart：后者在"拖了但不足以翻页"
    // 时不一定触发，而这恰恰是气泡最需要收回去的那种情形。
    .onTouch((e: TouchEvent) => {
      if (e.type === TouchType.Up || e.type === TouchType.Cancel) {
        this.settleHop();
      }
    })
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
      .backgroundColor(overlayGlassFill('viewer', VIEWER_CHROME_BG)).borderRadius(16)
    .backdropBlur(overlayBackdropBlur('viewer'))
    .attributeModifier(materialModifier('viewer'))
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
      .backgroundColor(overlayGlassFill('viewer', VIEWER_CHROME_BG)).borderRadius(16)
    .backdropBlur(overlayBackdropBlur('viewer'))
    .attributeModifier(materialModifier('viewer'))
      .position({ x: 14, y: this.topSafe + 76 })
      .onClick((): void => { this.retryPhoto(); });
    }
  }

  // Thumbnail strip for the current message's album (photo/video list) —
  // tap a thumbnail to switch the viewer to that item.
  // 把第 index 张缩略图滚到可视范围中间。
  // 52 的缩略图 + 6 的间距 = 每格 58；左边还有 12 的内边距。
  private scrollFilmstripTo(index: number): void {
    if (index < 0) {
      return;
    }
    const target: number = Math.max(0, 12 + index * 58 + 26 - this.areaW / 2);
    try {
      this.filmScroller.scrollTo({ xOffset: target, yOffset: 0, animation: true });
    } catch (e) {
      // 条还没挂上（切组的同一帧）时会抛，下一次 onPageChange 会再来一次。
    }
  }

  @Builder
  viewerFilmstrip() {
    Scroll(this.filmScroller) {
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
    // 顶部通栏。**一整条，不是三块浮在照片上的玻璃胶囊。**
    //
    // 原来是「✕ 圆片 + 标题胶囊 + ⋮ 圆片」三块各自带玻璃背板，状态栏那一条
    // 则什么都没有——照片直接透到系统时钟和图标底下。而本应用的前景色规则是
    // 「玻璃上的前景跟主题走」（见下面图标的颜色），状态栏没有玻璃可跟，浅色
    // 主题下就是黑字压在任意一张照片上，深浅全看运气（issue #122）。
    //
    // 通栏一铺，状态栏就有了和标题同一块背板：**全局那套跟随主题的状态栏内容
    // 色于是自动变成对的**，一行 setWindowSystemBarProperties 都不用调，也不
    // 用去猜照片亮度。三块胶囊的背板随之失去意义，按钮只留热区和按压态。
    Column() {
      // 状态栏占位。玻璃铺到这里，系统时钟和图标就压在它上面。
      Row().width('100%').height(this.topSafe).hitTestBehavior(HitTestMode.None);
      Row({ space: 6 }) {
        Stack() {
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
          Text(this.infoTitle()).fontSize(15).fontColor(Color.White)
            .fontWeight(FontWeight.Medium)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
          if (this.infoSubtitle() !== '') {
            Text(this.infoSubtitle()).fontSize(11).fontColor('#D9FFFFFF')
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
          }
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1);
        // No download indicator up here: the seek bar's lighter track shows
        // the downloaded span, and a stalled player draws a centered ring.
        // "⋮" menu — 保存到相册 etc.
        Stack() {
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
        } as MenuElement, {
          value: $r('app.string.ms_save_to_files'),
          action: (): void => { this.onSaveMediaToFiles(); }
        } as MenuElement]);
      }
      .width('100%').height(CHROME_BAR_ROW_H)
      .padding({ left: 6, right: 6 })
      .alignItems(VerticalAlign.Center);
    }
    .width('100%')
    .position({ x: 0, y: 0 })
    // 玻璃与材质挂在通栏本身上，三块胶囊的背板因此全部撤掉。
    .backgroundColor(overlayGlassFill('viewer', VIEWER_CHROME_BG))
    .backdropBlur(overlayBackdropBlur('viewer'))
    .attributeModifier(materialModifier('viewer'))
    .transition(TransitionEffect.OPACITY
      .combine(TransitionEffect.translate({ y: -8 }))
      .animation({
        duration: this.effectDuration(KEY_POWER_EFFECT_BLUR, 180),
        curve: Curve.EaseOut
      }));
  }

  // 越界切组的气泡。跟着手指长，拉满时换成"松手即可查看"。
  //
  // 贴在越界的那一侧：往下一组是从右边出来，往上一组从左边——方向和手指
  // 拖出去的方向一致，才读得出"那边还有东西"。
  @Builder
  hopBubble() {
    Row({ space: 8 }) {
      // 前景一律白：这一面的底是固定的深色半透明，不参与沉浸材质，也就不跟
      // 主题走（见 util/overlayMaterial 的 usesImmersiveMaterial）。
      if (this.hopDir < 0) {
        SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(15).fontColor([Color.White]);
      }
      if (this.hopThumbPath() !== '') {
        Image(this.hopThumbPath()).draggable(false)
          .width(34).height(34).borderRadius(6).objectFit(ImageFit.Cover);
      }
      Text(this.hopProgress >= 1
        ? $r('app.string.mv_hop_release')
        : (this.hopDir > 0 ? $r('app.string.mv_hop_next') : $r('app.string.mv_hop_prev')))
        .fontSize(12).fontColor(Color.White)
        .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
        .constraintSize({ maxWidth: 132 });
      if (this.hopDir > 0) {
        SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(15).fontColor([Color.White]);
      }
    }
    .padding({ left: 10, right: 10, top: 8, bottom: 8 })
    .backgroundColor(overlayGlassFill('viewer', VIEWER_CHROME_BG))
    .backdropBlur(overlayBackdropBlur('viewer'))
    .attributeModifier(materialModifier('viewer'))
    .borderRadius(18)
    .alignItems(VerticalAlign.Center)
    // 跟手：越拉越显、越拉越实。拉满前是"还差一点"的观感，拉满才定下来。
    .opacity(0.35 + 0.65 * this.hopProgress)
    .scale({ x: 0.88 + 0.12 * this.hopProgress, y: 0.88 + 0.12 * this.hopProgress })
    .hitTestBehavior(HitTestMode.None);
  }

  build() {
    Stack() {
      this.viewerContent();
      if (this.hopDir !== 0) {
        Row() {
          this.hopBubble();
        }
        .width('100%').height('100%')
        .padding({ left: 16, right: 16 })
        .justifyContent(this.hopDir > 0 ? FlexAlign.End : FlexAlign.Start)
        .alignItems(VerticalAlign.Center)
        .hitTestBehavior(HitTestMode.None);
      }
      if (this.chromeVisible) {
        this.chromeLayer();
      }
      if (this.chromeVisible && this.isLiveNow()) {
        this.liveCapsule();
        this.liveSaveButton();
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
    .width('100%').height('100%')
    // 整层（图片 + 控制层）一起跟着手指往下走，退出的是"这一整块沉浸"，
    // 不是单独一张图。
    .translate({ y: this.dismissY })
    .backgroundColor(this.dismissY > 0 ? `#${
      Math.round((1 - this.dismissProgress()) * 255).toString(16).padStart(2, '0')
    }000000` : Color.Black)
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
