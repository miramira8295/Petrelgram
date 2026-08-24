import { progressFor, subscribeProgress } from '../../util/mediaProgressChannel';

// 自己订阅、自己更新的下载进度环。
//
// 进度不再进行 key（见 collapseAlbums），所以进度前进时 LazyForEach 不会重建
// 这一行——环必须自己更新自己。与 LiveThumbImage 是同一套办法，也和它成对
// 出现：环活在 LiveThumbImage 的占位里，图一到占位整个消失，环随之卸载。
//
// 视觉与原先 MessageBubble.loadingRing 完全一致：0% 时是不确定态的转圈（此时
// 还没有任何字节到达，画一个 0% 的环等于画一条静止的线），有进度后换成环 +
// 百分比数字。
//
// 进入时先读通道现值而不是干等推送：滚回一段已经在下载中的历史时不会有新的
// 发布，只靠订阅会从 0 开始跳。
@Component
export struct LiveProgressRing {
  @Prop fileId: number = 0;
  @Prop initialPercent: number = 0;
  @Prop ringSize: number = 36;
  @State private percent: number = 0;
  private unsubProgress: (() => void) | null = null;

  private attach(fileId: number, initialPercent: number): void {
    this.detach();
    const known: number = progressFor(fileId);
    this.percent = known > 0 ? known : initialPercent;
    this.unsubProgress = subscribeProgress(fileId, (percent: number): void => {
      this.percent = percent;
    });
  }

  private detach(): void {
    if (this.unsubProgress !== null) {
      this.unsubProgress();
      this.unsubProgress = null;
    }
  }

  aboutToAppear(): void {
    this.attach(this.fileId, this.initialPercent);
  }

  aboutToRecycle(): void {
    this.detach();
    this.percent = 0;
  }

  aboutToReuse(params: Record<string, Object>): void {
    const fileId: number | undefined = params['fileId'] as number | undefined;
    const initialPercent: number | undefined = params['initialPercent'] as number | undefined;
    if (fileId !== undefined) {
      this.attach(fileId, initialPercent ?? 0);
      return;
    }
    setTimeout((): void => { this.attach(this.fileId, this.initialPercent); }, 0);
  }

  // 不退订会让箭头函数一直持有本组件实例，组件无法释放。
  aboutToDisappear(): void {
    this.detach();
  }

  build() {
    Stack() {
      if (this.percent > 0) {
        Progress({ value: this.percent, total: 100, type: ProgressType.Ring })
          .width(this.ringSize).height(this.ringSize).color(Color.White);
        Text(`${this.percent}%`)
          .fontSize(Math.max(9, this.ringSize * 0.24)).fontColor(Color.White);
      } else {
        LoadingProgress()
          .width(this.ringSize * 0.72).height(this.ringSize * 0.72).color(Color.White);
      }
    }
    .padding(6)
    .backgroundColor('#00000066')
    .borderRadius(this.ringSize);
  }
}
