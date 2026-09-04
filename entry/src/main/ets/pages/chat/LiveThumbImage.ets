import { CachedImage } from '../common/CachedImage';
import { subscribeThumbPath, thumbPathFor } from '../../util/mediaThumbChannel';
import { liveThumbPath } from '../../util/liveThumbPath';

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

  // 非复用路径的自愈（「图配错文」的历史修法）：fileId 真变化时按新值重挂。
  // 第二个参数传 ''：@Param 逐个落地时 initialPath 可能还是上一条的，拿它
  // 兜底等于把旧图画上去；通道现值本来就按新 fileId 查。
  @Monitor('fileId')
  onFileIdChanged(): void {
    this.attach(this.spec.fileId, '');
  }

  // Same message, same fileId=0, but a local/full-size path was backfilled.
  // No channel event and no fileId @Watch fires in that case, so initialPath
  // must drive the image directly. For non-zero IDs the file-scoped channel is
  // authoritative; ignoring their independently-landed @Prop also avoids
  // pairing a new path with the previous row's fileId during reuse.
  @Monitor('initialPath')
  onInitialPathChanged(): void {
    if (this.spec.fileId === 0) {
      this.attach(0, this.spec.initialPath);
    }
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

  build() {
    if (this.path !== '') {
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
