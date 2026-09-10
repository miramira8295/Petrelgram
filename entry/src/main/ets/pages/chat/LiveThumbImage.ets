import { CachedImage } from '../common/CachedImage';
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
// 调用方而不搬进来），拿到路径后原地换成 CachedImage。
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
// 子树只有一个 CachedImage 或一段占位——赔得起；纯文本气泡的子树是整条消息，
// 赔不起。
export interface LiveThumbSpec {
  fileId: number;
  initialPath: string;
  boxWidth: number;
  boxHeight: number;
  radius: number;
  fit: ImageFit;
}

@ComponentV2
export struct LiveThumbImage {
  @Require @Param spec: LiveThumbSpec;
  @BuilderParam placeholder: () => void;
  @Local private path: string = '';
  private unsubThumb: (() => void) | null = null;
  // 订阅此刻挂在哪个文件上。两个用途：① 同 key 短路，让 attach 幂等；
  // ② 让「订阅挂在哪」成为可判定的事实，而不是靠推断 params 到没到。
  // -1 = 没挂；0 表示只有 initialPath、没有可订阅的缩略图文件。
  private attachedFileId: number = -1;
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
      this.path = path;
    });
  }

  private detach(): void {
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
    if (!shouldReattachThumb(this.spec.fileId, this.spec.initialPath,
      this.attachedFileId, this.path)) {
      return;
    }
    // fileId ≠ 0 时第二个参数传 ''：@Param 逐个落地时 initialPath 可能还是
    // 上一条的，拿它兜底等于把旧图画上去；通道现值本来就按新 fileId 查。
    this.attach(this.spec.fileId,
      this.spec.fileId === 0 ? this.spec.initialPath : '');
  }

  aboutToAppear(): void {
    this.attach(this.spec.fileId, this.spec.initialPath);
  }

  aboutToRecycle(): void {
    // path 不清（翻页图片乱跳的根修之一）：@Local 由框架在下次复用前重置，
    // aboutToReuse 里同步播种，空窗只剩「通道确实没图」的固有情形。
    this.detach();
  }

  aboutToReuse(): void {
    // @Param 已是新值、@Local path 已被框架重置（批 0.5 判读）：同步重挂+
    // 播种。initialPath 也是新行的值，V1「不敢用 initialPath 兜底」的坑不在。
    this.attach(this.spec.fileId, this.spec.initialPath);
  }

  // 不退订会让箭头函数一直持有本组件实例，组件无法释放（官方状态管理 FAQ
  // 明确点过这个泄漏）。
  aboutToDisappear(): void {
    this.detach();
  }

  // 不变量检查挂在**分支条件**上：build 里不能放语句，而这里同样是拿当前
  // @Param 求值的——不受"参数什么时候落地"影响。返回值就是要画的路径。
  // 顺带读一次 spec.fileId，让这个渲染域把它登记成依赖。见 util/thumbAttachGuard。
  private drawPath(): string {
    warnStaleThumbAttach(this.attachedFileId, this.spec.fileId, this.path);
    return this.path;
  }

  build() {
    if (this.drawPath() !== '') {
      CachedImage({
        path: this.path,
        boxWidth: this.spec.boxWidth,
        boxHeight: this.spec.boxHeight,
        radius: this.spec.radius,
        fit: this.spec.fit
      });
    } else {
      this.placeholder();
    }
  }
}
