import { CachedImage } from '../common/CachedImage';
import { subscribeThumbPath, thumbPathFor } from '../../util/mediaThumbChannel';

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
@Component
export struct LiveThumbImage {
  @Prop fileId: number = 0;
  @Prop initialPath: string = '';
  @Prop boxWidth: number = 0;
  @Prop boxHeight: number = 0;
  @Prop radius: number = 0;
  @Prop fit: ImageFit = ImageFit.Cover;
  @BuilderParam placeholder: () => void;
  @State private path: string = '';
  private unsubThumb: (() => void) | null = null;

  private attach(fileId: number, initialPath: string): void {
    this.detach();
    const known: string = thumbPathFor(fileId);
    this.path = known !== '' ? known : initialPath;
    this.unsubThumb = subscribeThumbPath(fileId, (path: string): void => {
      this.path = path;
    });
  }

  private detach(): void {
    if (this.unsubThumb !== null) {
      this.unsubThumb();
      this.unsubThumb = null;
    }
  }

  aboutToAppear(): void {
    this.attach(this.fileId, this.initialPath);
  }

  aboutToRecycle(): void {
    this.detach();
    this.path = '';
  }

  aboutToReuse(params: Record<string, Object>): void {
    const fileId: number | undefined = params['fileId'] as number | undefined;
    const initialPath: string | undefined = params['initialPath'] as string | undefined;
    if (fileId !== undefined) {
      this.attach(fileId, initialPath ?? '');
      return;
    }
    setTimeout((): void => { this.attach(this.fileId, this.initialPath); }, 0);
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
        boxWidth: this.boxWidth,
        boxHeight: this.boxHeight,
        radius: this.radius,
        fit: this.fit
      });
    } else {
      this.placeholder();
    }
  }
}
