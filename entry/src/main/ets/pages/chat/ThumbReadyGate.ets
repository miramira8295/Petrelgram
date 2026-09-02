import { subscribeThumbPath, thumbPathFor } from '../../util/mediaThumbChannel';

// 只在缩略图已经到位（或根本不必等）时渲染内容的小闸门。
//
// 为什么需要它：视频的播放钮原本用 `msg.photoPath !== ''` 判断"缩略图到了
// 没有"，避免和缩略图自己的加载圈叠成两个中心控件。缩略图路径旁路化之后
// （见 mediaThumbChannel），路径不再回写进 MessageEntry、行也不再重建，
// 那个判断就永远是空——播放钮从此不出现。
//
// 和 LiveThumbImage 是同一套办法：自己订阅、自己重建，不惊动整行。区别是
// 它只关心"到了没有"这一个布尔，图由谁画不归它管。
// P4 批 5：迁 @ComponentV2（配方同批 1~4）。复用在 aboutToReuse 同步重挂+
// 从通道现值播种；@Monitor 兜非复用路径。
@ComponentV2
export struct ThumbReadyGate {
  @Param fileId: number = 0;
  // 调用方已知的路径（历史消息进入时可能本来就带着）。
  @Param initialPath: string = '';
  // 不必等待：没有缩略图可等（fileId 为 0），或者它已经失败了——这两种
  // 情况下等下去就是永远不显示。
  @Param ready: boolean = false;
  @BuilderParam content: () => void;
  @Local private arrived: boolean = false;
  private unsubThumb: (() => void) | null = null;

  private attach(fileId: number, initialPath: string): void {
    this.detach();
    // 先读通道现值：滚回已经下好的那段历史时不会有新的发布，只靠订阅会一直
    // 是空。
    this.arrived = thumbPathFor(fileId) !== '' || initialPath !== '';
    if (this.arrived) {
      return;
    }
    this.unsubThumb = subscribeThumbPath(fileId, (path: string): void => {
      if (path !== '') {
        this.arrived = true;
      }
    });
  }

  private detach(): void {
    if (this.unsubThumb !== null) {
      this.unsubThumb();
      this.unsubThumb = null;
    }
  }

  @Monitor('fileId')
  onFileIdChanged(): void {
    this.attach(this.fileId, '');
  }

  aboutToAppear(): void {
    this.attach(this.fileId, this.initialPath);
  }

  aboutToRecycle(): void {
    this.detach();
  }

  aboutToReuse(): void {
    // @Param 已是新值、@Local arrived 已重置：同步重挂+播种。
    this.attach(this.fileId, this.initialPath);
  }

  // 不退订会让箭头函数一直持有本组件实例，组件无法释放。
  aboutToDisappear(): void {
    this.detach();
  }

  build() {
    if (this.ready || this.arrived) {
      this.content();
    }
  }
}
