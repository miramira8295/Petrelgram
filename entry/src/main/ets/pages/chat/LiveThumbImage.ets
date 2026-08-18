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
  fileId: number = 0;
  initialPath: string = '';
  boxWidth: number = 0;
  boxHeight: number = 0;
  radius: number = 0;
  fit: ImageFit = ImageFit.Cover;
  @BuilderParam placeholder: () => void;
  @State private path: string = '';
  private unsubThumb: (() => void) | null = null;

  aboutToAppear(): void {
    const known: string = thumbPathFor(this.fileId);
    this.path = known !== '' ? known : this.initialPath;
    this.unsubThumb = subscribeThumbPath(this.fileId, (path: string): void => {
      this.path = path;
    });
  }

  // 不退订会让箭头函数一直持有本组件实例，组件无法释放（官方状态管理 FAQ
  // 明确点过这个泄漏）。
  aboutToDisappear(): void {
    if (this.unsubThumb !== null) {
      this.unsubThumb();
      this.unsubThumb = null;
    }
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
