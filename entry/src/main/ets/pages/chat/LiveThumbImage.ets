import { image } from '@kit.ImageKit';
import { CachedImageSession } from '../../util/CachedImageSession';
import { MINI_PLACEHOLDER_BLUR } from '../../util/miniThumbPlaceholder';
import { scrollPlaceholderState } from '../../util/scrollEffects';
import { CachedImageSpec } from '../../util/cachedImageSpec';
import { subscribeThumbPath, thumbPathFor } from '../../util/mediaThumbChannel';
import { liveThumbPath } from '../../util/liveThumbPath';
import { shouldReattachThumb } from '../../util/liveThumbAttach';
import { warnStaleThumbAttach } from '../../util/thumbAttachGuard';

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
export interface LiveThumbSpec {
  // Chat cells opt in; shared viewer/filmstrip uses keep the default policy.
  syncDisplay?: boolean;
  fileId: number;
  initialPath: string;
  boxWidth: number;
  boxHeight: number;
  radius: number;
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
  @Local private path: string = '';
  @Local private pixelMap: image.PixelMap | undefined = undefined;
  private scrollState = scrollPlaceholderState;
  private imageSession: CachedImageSession = new CachedImageSession(
    (pixels: image.PixelMap | undefined): void => { this.pixelMap = pixels; });
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
      this.imageSession.update(this.imageSpec());
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
      // 可下载文件的实时路径以通道为准，通道尚未就绪时回退到当前 spec 的 initialPath。
      this.attach(this.spec.fileId, this.spec.initialPath);
    }
    // 即使文件未变，尺寸/像素格式等输入变化仍需交给同一个图片会话。
    this.imageSession.update(this.imageSpec());
  }

  aboutToAppear(): void {
    this.attach(this.spec.fileId, this.spec.initialPath);
    this.imageSession.activate(this.imageSpec());
  }

  aboutToRecycle(): void {
    // path 不清（翻页图片乱跳的根修之一）：@Local 由框架在下次复用前重置，
    // aboutToReuse 里同步播种，空窗只剩「通道确实没图」的固有情形。
    this.detach('recycle');
    this.imageSession.recycle();
  }

  aboutToReuse(): void {
    // @Param 已是新值、@Local path 已被框架重置（批 0.5 判读）：同步重挂+
    // 播种。initialPath 也是新行的值，V1「不敢用 initialPath 兜底」的坑不在。
    this.attach(this.spec.fileId, this.spec.initialPath);
    this.imageSession.activate(this.imageSpec());
  }

  // 不退订会让箭头函数一直持有本组件实例，组件无法释放（官方状态管理 FAQ
  // 明确点过这个泄漏）。
  aboutToDisappear(): void {
    this.detach('disappear');
    this.imageSession.dispose();
  }

  // 不变量检查挂在**分支条件**上：build 里不能放语句，而这里同样是拿当前
  // @Param 求值的——不受"参数什么时候落地"影响。返回值就是要画的路径。
  // 顺带读一次 spec.fileId，让这个渲染域把它登记成依赖。见 util/thumbAttachGuard。
  private drawPath(): string {
    warnStaleThumbAttach(this.attachedFileId, this.spec.fileId, this.path, this.detachPhase);
    return this.path;
  }

  private preparedImageSpec: CachedImageSpec | undefined = undefined;
  private preparedImageFileId: number = -1;

  // Read reactive inputs during child construction/update. @Computed would
  // force a reset on every reuse; the existing cache already keeps equal specs
  // stable without that extra dependency rebuild.
  private imageSpec(): CachedImageSpec {
    const spec: LiveThumbSpec = this.spec;
    const previous = this.preparedImageSpec;
    // Compare scalar inputs before allocating the candidate or its source key.
    // Do not short-circuit solely on spec identity: path notifications are
    // independent, and comparing values also handles a changed input in place.
    if (previous !== undefined && this.preparedImageFileId === spec.fileId &&
      previous.path === this.path && previous.boxWidth === spec.boxWidth &&
      previous.boxHeight === spec.boxHeight && previous.radius === spec.radius && previous.fit === spec.fit &&
      previous.syncDisplay === (spec.syncDisplay === true) && previous.opaque === spec.opaque &&
      previous.backdrop === spec.backdrop && previous.backdropImage === spec.mini &&
      previous.deferBackdropOnScroll === (spec.deferMiniOnScroll === true)) {
      return previous;
    }
    const next: CachedImageSpec = {
      path: this.path, boxWidth: spec.boxWidth, boxHeight: spec.boxHeight,
      radius: spec.radius, fit: spec.fit,
      syncDisplay: spec.syncDisplay === true,
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

  private showMiniPlaceholder(): boolean {
    return this.pixelMap === undefined && this.spec.mini !== '' &&
      !(this.spec.deferMiniOnScroll === true && this.scrollState.active);
  }

  // 与 CachedImage 的原生图片属性保持一致。成员零参 Builder 直接读当前输入，
  // 省去每格一层自定义组件及其复用/参数登记，仍保留同步显示与圆角抗锯齿。
  @Builder
  imageContent() {
    Stack() {
      if (this.showMiniPlaceholder()) {
        Image(this.spec.mini)
          .draggable(false)
          .width(this.spec.boxWidth).height(this.spec.boxHeight)
          .borderRadius(this.spec.radius).clip(true)
          .objectFit(this.spec.fit)
          .blur(MINI_PLACEHOLDER_BLUR);
      }
      Image(this.pixelMap)
        .syncLoad(this.spec.syncDisplay === true && this.pixelMap !== undefined)
        .draggable(false)
        .width(this.spec.boxWidth).height(this.spec.boxHeight)
        .backgroundColor(this.spec.backdrop !== '' ? this.spec.backdrop : Color.Transparent)
        .borderRadius(this.spec.radius).clip(true)
        .interpolation(ImageInterpolation.High)
        .objectFit(this.spec.fit);
    }.width(this.spec.boxWidth).height(this.spec.boxHeight);
  }

  build() {
    if (this.drawPath() !== '') {
      this.imageContent();
    } else {
      this.placeholder();
    }
  }
}
