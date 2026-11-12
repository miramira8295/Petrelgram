import { image } from '@kit.ImageKit';
import { DrawnImageReceiver } from '../common/DrawnImageReceiver';
import { CachedImageSession } from '../../util/CachedImageSession';
import { MINI_PLACEHOLDER_BLUR } from '../../util/miniThumbPlaceholder';
import { scrollPlaceholderState } from '../../util/scrollEffects';
import { CachedImageSpec } from '../../util/cachedImageSpec';
import { subscribeThumbPath, thumbPathFor } from '../../util/mediaThumbChannel';
import { liveThumbPath } from '../../util/liveThumbPath';
import { shouldReattachThumb } from '../../util/liveThumbAttach';
import { warnStaleThumbAttach } from '../../util/thumbAttachGuard';
import { EMPTY_LIVE_THUMB_DISPLAY, LiveThumbDisplayState, liveThumbDisplayState } from '../../util/liveThumbDisplayState';

// 自己订阅、自己换图的缩略图。
//
// 路径不再进 key（见 collapseAlbums），所以缩略图落地时 LazyForEach 不会
// 重建这一行——图必须自己更新自己。与 MessageBubble 里的 LiveSenderAvatar
// 是同一套办法。
//
// 无图/有图两态都在组件内部处理：没有路径时渲染调用方通过 placeholder 传入
// 的占位内容（灰底、进度环、失败重试等，那些细节和调用方状态强耦合，留在
// 调用方而不搬进来），拿到路径后在本组件内直接绘图，路径与位图生命周期在同一个边界内完成。
//
// 进入时先读通道现值而不是干等推送：滚回已经下好的那一段历史时不会有新的
// 发布，只靠订阅会一直是空白。
// P4 批 4：迁 @ComponentV2（配方同批 1/2/3b/3c，判读依据 survey 批 0.5 节）。
// aboutToReuse 时 @Param 已是新值 → 同步重挂+播种，V1 的延帧兜底/换文件才
// 清图（#137 判据）整套退役；@Monitor 只兜非复用路径的自愈（「图配错文」
// 的历史修复语义原样保留在 onFileIdChanged 的注释里）。
// 一格缩略图要的全部参数，**打成一个对象下发**。
//
// 原来是 6 个独立 @Param。09-03 的相册真机对照里
// `updateStateVars@LiveThumbImage` 是新包里 fireChange 的**头名**（126.3ms）——
// 每个 @Param 赋值走一次 `updateParam → fireChange`，而每次 fireChange 都会
// 同步排干一遍 ObserveV2 的 idle 队列。一格 6 次、一行 6–9 格。
//
// **这和 LightweightPlainTextBubble 那边刻意不合并不矛盾**，判据是同一条：
// 合并省的是"逐个登记 + 每次排队列"，赔的是"整棵子树粗粒度失效"。本组件的
// 子树只有一组图片节点或一段占位——赔得起；纯文本气泡的子树是整条消息，
// 赔不起。
// 一格缩略图的入参记忆化。父组件每次重渲染都会现造 spec 对象，V2 的 @Param
// 按 `===` 比较 → 必然"变化"一次，@Monitor('spec') 重跑、整格重渲染。
// 2026-11-09 的 Insight 采集里 `LiveThumbImage.spec` 198 次写有 183 次内容
// 完全相同（92%）；相册一行 6–9 格，这笔是按格乘的。
export class LiveThumbSpecCache {
  private previous: LiveThumbSpec | undefined = undefined;

  prepare(next: LiveThumbSpec): LiveThumbSpec {
    const p = this.previous;
    if (p !== undefined && p.fileId === next.fileId && p.initialPath === next.initialPath &&
      p.boxWidth === next.boxWidth && p.boxHeight === next.boxHeight &&
      p.radius === next.radius && p.fit === next.fit && p.opaque === next.opaque &&
      p.backdrop === next.backdrop && p.mini === next.mini &&
      p.syncDisplay === next.syncDisplay && p.drawOnCanvas === next.drawOnCanvas &&
      p.deferMiniOnScroll === next.deferMiniOnScroll && p.readyWithoutPath === next.readyWithoutPath && sameRadii(p.radii, next.radii)) {
      return p;
    }
    this.previous = next;
    return next;
  }
}

function sameRadii(a: BorderRadiuses | undefined, b: BorderRadiuses | undefined): boolean {
  if (a === undefined || b === undefined) {
    return a === b;
  }
  return a.topLeft === b.topLeft && a.topRight === b.topRight &&
    a.bottomLeft === b.bottomLeft && a.bottomRight === b.bottomRight;
}

export interface LiveThumbSpec {
  // Album video badge may be shown without a path on missing/failed thumbnails.
  readyWithoutPath?: boolean;
  // Chat cells opt in; shared viewer/filmstrip uses keep the default policy.
  syncDisplay?: boolean;
  drawOnCanvas?: boolean;
  fileId: number;
  initialPath: string;
  boxWidth: number;
  boxHeight: number;
  radius: number;
  // 四角可分别设置时优先用它；调用方需要和外层气泡四角同心时传这个。
  // 缺省保持单值 radius 的旧行为。
  radii?: BorderRadiuses;
  fit: ImageFit;
  // 不透明源，允许 RGB_565 解码（见 pixelCache.PixelRequest.opaque）。
  // 相册格 true，单张大图与查看器缩略图条 false。
  opaque: boolean;
  // 解码完成前垫的底色（见 util/thumbBackdrop）。必须和调用方 placeholder 的
  // 底色一致，否则撤占位那一帧会看到跳色。空串 = 不垫。
  backdrop: string;
  // 解码完成前画的内联小图（data URL，见 util/miniThumbPlaceholder）。
  // 空串 = 只有底色。
  mini: string;
  // Album-only placeholder policy; decoded images remain visible while scrolling.
  deferMiniOnScroll?: boolean;
}


@ComponentV2
export struct LiveThumbImage {
  @Require @Param spec: LiveThumbSpec;
  @BuilderParam placeholder: () => void;
  @BuilderParam readyContent: () => void = this.emptyReadyContent;

  @Builder
  emptyReadyContent() {}
  // Prepare source/decoder state without publishing a transient empty image.
  // One UI snapshot is reset/reseeded by V2 instead of two independent locals.
  private path: string = '';
  @Local private displayState: LiveThumbDisplayState = EMPTY_LIVE_THUMB_DISPLAY;
  private get pixelMap(): image.PixelMap | undefined { return this.displayState.pixels; }
  private scrollState = scrollPlaceholderState;
  private imageReceiver: DrawnImageReceiver = new DrawnImageReceiver();
  private imageActive: boolean = false;
  private imageSession: CachedImageSession = new CachedImageSession(
    (pixels: image.PixelMap | undefined, _ready: boolean, width?: number, height?: number): void => {
      this.imageReceiver.setPixels(this.spec.drawOnCanvas === true ? pixels : undefined, width, height);
      this.publishDisplay(pixels);
    });

  private publishDisplay(pixels: image.PixelMap | undefined): void {
    if (!this.imageActive) { return; }
    const previous = this.displayState;
    const next = liveThumbDisplayState(previous, this.path !== '', pixels);
    if (previous !== next) { this.displayState = next; }
  }

  private updateImageSession(): void {
    this.imageSession.update(this.imageSpec());
    // Same-source pending upgrades can intentionally keep the held bitmap and
    // skip the session callback. Publish visibility only if it actually changed.
    this.publishDisplay(this.pixelMap);
  }
  private unsubThumb: (() => void) | null = null;
  // 订阅此刻挂在哪个文件上。两个用途：① 同 key 短路，让 attach 幂等；
  // ② 让「订阅挂在哪」成为可判定的事实，而不是靠推断 params 到没到。
  // -1 = 没挂；0 表示只有 initialPath、没有可订阅的缩略图文件。
  private attachedFileId: number = -1;
  // 最后一次 detach 的由头，只给 [ThumbGuard] 判读用（见 util/thumbAttachGuard）。
  private detachPhase: string = 'init';
  private attach(fileId: number, initialPath: string): void {
    // fileId=0 cannot publish through mediaThumbChannel. In this path-only
    // mode initialPath is the source identity, so changing it must replace an
    // old row's image instead of preserving the old non-empty path.
    if (fileId === 0) {
      if (this.attachedFileId !== 0) {
        this.detach();
      }
      this.attachedFileId = 0;
      this.path = liveThumbPath(fileId, '', this.path, initialPath,
        this.attachedFileId === fileId);
      return;
    }
    if (this.unsubThumb !== null && this.attachedFileId === fileId) {
      // 已经挂在同一个文件上：订阅原样留着（一整轮退订+重订阅是滚动时的每行常数
      // 开销），只重新播种一次现值——回收期间 path 可能被清过。
      // 与 LiveSenderAvatar.attachAvatarChannel 的同 key 短路是同一套做法。
      const seeded: string = thumbPathFor(fileId);
      this.path = liveThumbPath(fileId, seeded, this.path, initialPath, true);
      return;
    }
    this.detach();
    this.attachedFileId = fileId;
    const known: string = thumbPathFor(fileId);
    this.path = liveThumbPath(fileId, known, this.path, initialPath, false);
    this.unsubThumb = subscribeThumbPath(fileId, (path: string): void => {
      if (this.attachedFileId !== fileId) { return; }
      this.path = path;
      this.updateImageSession();
    });
  }

  private detach(phase: string = 'swap'): void {
    this.detachPhase = phase;
    if (this.unsubThumb !== null) {
      this.unsubThumb();
      this.unsubThumb = null;
    }
    this.attachedFileId = -1;
  }

  // 自愈：spec 换了之后按新值重挂。**唯一**能兜住"复用时 @Param 比
  // aboutToReuse 晚落地"的地方。
  //
  // ⚠️ 监听的是 spec 整体，不是 'fileId' / 'initialPath'。那两个名字是 6 个
  // @Param 合并成 spec 之前的写法，合并时被落下了；组件里没有这两个成员，
  // ArkUI 既不报编译错也不打告警，于是自愈静默失效——2026-09-10 真机实测
  // 50 次 attach 里这两个回调触发 0 次，同一次滑动抓到 7 次挂错行。
  // 判据见 util/liveThumbAttach（纯函数，有回归测试）。
  @Monitor('spec')
  onSpecChanged(): void {
    if (shouldReattachThumb(this.spec.fileId, this.spec.initialPath,
      this.attachedFileId, this.path)) {
      // 可下载文件的实时路径以通道为准；纯路径模式由 initialPath 定义身份。
      this.attach(this.spec.fileId, this.spec.fileId === 0 ? this.spec.initialPath : '');
    }
    // 即使文件未变，尺寸/像素格式等输入变化仍需交给同一个图片会话。
    this.updateImageSession();
    this.syncImageReceiver();
  }

  aboutToAppear(): void {
    this.imageActive = true;
    this.attach(this.spec.fileId, this.spec.initialPath);
    this.imageSession.activate(this.imageSpec());
  }

  aboutToRecycle(): void {
    // Keep the held pixels/display while pooled. V2 resets the single snapshot
    // immediately before reuse; activation synchronously publishes its final state.
    this.imageActive = false;
    this.detach('recycle');
    this.imageSession.recycle();
  }

  aboutToReuse(): void {
    this.imageActive = true;
    // Match the former @Local path reset, without a separate reactive write.
    // Do not carry a previous file's private path into a new attachment.
    this.path = '';
    this.attach(this.spec.fileId, this.spec.initialPath);
    this.imageSession.activate(this.imageSpec());
  }

  // 不退订会让箭头函数一直持有本组件实例，组件无法释放（官方状态管理 FAQ
  // 明确点过这个泄漏）。
  aboutToDisappear(): void {
    this.imageActive = false;
    this.imageReceiver.setPixels(undefined);
    this.detach('disappear');
    this.imageSession.dispose();
  }

  // Both visibility and pixels come from the final published snapshot. The
  // non-observed working path is used only for source preparation/diagnostics.
  private hasImagePath(): boolean {
    warnStaleThumbAttach(this.attachedFileId, this.spec.fileId, this.path, this.detachPhase);
    return this.displayState.hasPath;
  }

  private preparedImageSpec: CachedImageSpec | undefined = undefined;
  private preparedImageFileId: number = -1;

  // Read reactive inputs during child construction/update. @Computed would
  // force a reset on every reuse; the existing cache already keeps equal specs
  // stable without that extra dependency rebuild.
  private imageSpec(): CachedImageSpec {
    const spec: LiveThumbSpec = this.spec;
    const path: string = this.path;
    const previous = this.preparedImageSpec;
    // Compare scalar inputs before allocating the candidate or its source key.
    // Do not short-circuit solely on spec identity: path notifications are
    // independent, and comparing values also handles a changed input in place.
    if (previous !== undefined && this.preparedImageFileId === spec.fileId &&
      previous.path === path && previous.boxWidth === spec.boxWidth &&
      previous.boxHeight === spec.boxHeight && previous.radius === spec.radius && previous.fit === spec.fit &&
      previous.syncDisplay === (spec.syncDisplay === true) && previous.drawOnCanvas === spec.drawOnCanvas &&
      previous.opaque === spec.opaque &&
      previous.backdrop === spec.backdrop && previous.backdropImage === spec.mini &&
      previous.deferBackdropOnScroll === (spec.deferMiniOnScroll === true)) {
      return previous;
    }
    const next: CachedImageSpec = {
      path, boxWidth: spec.boxWidth, boxHeight: spec.boxHeight,
      radius: spec.radius, fit: spec.fit,
      syncDisplay: spec.syncDisplay === true, drawOnCanvas: spec.drawOnCanvas,
      // A path upgrade for the same file keeps the held image until it is ready.
      sourceKey: spec.fileId > 0 ? `f${spec.fileId}` : '',
      opaque: spec.opaque, backdrop: spec.backdrop,
      backdropImage: spec.mini,
      deferBackdropOnScroll: spec.deferMiniOnScroll === true
    };
    this.preparedImageFileId = spec.fileId;
    this.preparedImageSpec = next;
    return next;
  }

  private useDrawnImage(): boolean {
    const spec: LiveThumbSpec = this.spec;
    return spec.drawOnCanvas === true && this.imageReceiver.canDraw(this.pixelMap, spec.fit);
  }

  private bindImageReceiver(): DrawnImageReceiver | undefined {
    const spec: LiveThumbSpec = this.spec;
    return spec.drawOnCanvas === true ? this.imageReceiver.bind(this.getUIContext(),
      spec.boxWidth, spec.boxHeight, spec.fit, this.useDrawnImage()) : undefined;
  }

  private syncImageReceiver(): void {
    if (this.imageActive) {
      this.imageReceiver.setPixels(this.spec.drawOnCanvas === true ? this.pixelMap : undefined);
    }
  }

  private shownMiniFileId: number = -1;
  private shownMiniPath: string = '';
  private shownMiniData: string = '';

  private showMiniPlaceholder(): boolean {
    if (this.pixelMap !== undefined) { return false; }
    const spec: LiveThumbSpec = this.spec;
    if (spec.mini === '') { return false; }
    const alreadyShown: boolean = this.shownMiniFileId === spec.fileId &&
      this.shownMiniData === spec.mini && (spec.fileId !== 0 || this.shownMiniPath === spec.initialPath);
    if (alreadyShown) { return true; }
    // Still defer the first miniature creation during a fling. Once visible,
    // retain it until decoded pixels arrive, instead of flashing the backdrop
    // at every scroll start. Identity checks prevent carrying it to a new row.
    if (spec.deferMiniOnScroll === true && this.scrollState.active) { return false; }
    this.shownMiniFileId = spec.fileId;
    this.shownMiniPath = spec.initialPath;
    this.shownMiniData = spec.mini;
    return true;
  }

  // 与 CachedImage 共用绘制接管；聊天格直接画在 Stack，查看器保留原生 Image。
  // 成员零参 Builder 读取当前输入，圆角裁剪由原有容器承接。
  // 圆角取值：给了四角就按四角画，否则沿用单值。
  private effectiveRadii(): Length | BorderRadiuses {
    const radii: BorderRadiuses | undefined = this.spec.radii;
    return radii !== undefined ? radii : this.spec.radius;
  }

  @Builder
  imageContent() {
    Stack() {
      if (this.showMiniPlaceholder()) {
        Image(this.spec.mini)
          .draggable(false)
          .width(this.spec.boxWidth).height(this.spec.boxHeight)
          .borderRadius(this.effectiveRadii()).clip(true)
          .objectFit(this.spec.fit)
          .blur(MINI_PLACEHOLDER_BLUR);
      }
      if (!this.useDrawnImage()) {
        Image(this.pixelMap)
          .syncLoad(this.spec.syncDisplay === true && this.pixelMap !== undefined)
          .draggable(false)
          .width(this.spec.boxWidth).height(this.spec.boxHeight)
          .backgroundColor(this.spec.backdrop !== '' ? this.spec.backdrop : Color.Transparent)
          .borderRadius(this.effectiveRadii()).clip(true)
          .interpolation(ImageInterpolation.High)
          .objectFit(this.spec.fit);
      }
      this.readyContent();
    }.width(this.spec.boxWidth).height(this.spec.boxHeight)
    .backgroundColor(this.useDrawnImage() && this.spec.backdrop !== '' ? this.spec.backdrop : Color.Transparent)
    .borderRadius(this.effectiveRadii()).clip(this.useDrawnImage())
    .drawModifier(this.bindImageReceiver());
  }

  build() {
    if (this.hasImagePath()) {
      this.imageContent();
    } else if (this.spec.readyWithoutPath === true) {
      Stack() {
        this.placeholder();
        this.readyContent();
      }.width(this.spec.boxWidth).height(this.spec.boxHeight);
    } else {
      this.placeholder();
    }
  }
}
