import { str } from '../../util/strings';
import { DrawnLoadingSpinner } from './DrawnLoadingSpinner';
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
// P4 批 5：迁 @ComponentV2（配方同批 1~4）。复用在 aboutToReuse 同步重挂+
// 从通道现值播种（@Param 已是新值、@Local 已重置——批 0.5 判读），换文件才
// 保留进度的判据随之退役；@Monitor 兜非复用路径（挂错文件 = 显示别条消息
// 的下载进度）。
@ComponentV2
export struct LiveProgressRing {
  @Param fileId: number = 0;
  @Param initialPercent: number = 0;
  @Param ringSize: number = 36;
  @Local private percent: number = 0;
  private active: boolean = false;
  private generation: number = 0;
  private unsubProgress: (() => void) | null = null;

  private attach(fileId: number, initialPercent: number): void {
    this.detach();
    const known: number = progressFor(fileId);
    this.percent = known > 0 ? known : initialPercent;
    if (!this.active) { return; }
    const generation = this.generation;
    this.unsubProgress = subscribeProgress(fileId, (percent: number): void => {
      if (generation === this.generation && this.percent !== percent) { this.percent = percent; }
    });
  }

  private detach(): void {
    this.generation++;
    if (this.unsubProgress !== null) {
      this.unsubProgress();
      this.unsubProgress = null;
    }
  }

  // 第二个参数传 0 而不是 this.initialPercent：非复用路径上后者可能还是
  // 上一条的进度。通道现值 progressFor(fileId) 按新 fileId 查，是对的。
  @Monitor('fileId')
  onFileIdChanged(): void {
    this.attach(this.fileId, 0);
  }

  aboutToAppear(): void {
    this.active = true;
    this.attach(this.fileId, this.initialPercent);
  }

  aboutToRecycle(): void {
    this.active = false;
    this.detach();
  }

  aboutToReuse(): void {
    this.active = true;
    // @Param 已是新值：同步重挂，进度从通道现值/新行 initialPercent 播种。
    this.attach(this.fileId, this.initialPercent);
  }

  // 不退订会让箭头函数一直持有本组件实例，组件无法释放。
  aboutToDisappear(): void { this.aboutToRecycle(); }

  build() {
    Stack() {
      DrawnLoadingSpinner({ ringSize: this.ringSize, ringColor: '#FFFFFF', ringStroke: 2.5,
        percent: this.percent > 0 ? this.percent : -1, showPercent: this.percent > 0, activityScale: .72 });
    }
    .width(this.ringSize + 12).height(this.ringSize + 12)
    .padding(6)
    .backgroundColor('#73000000')
    .border({ width: 0.5, color: '#24FFFFFF' })
    .borderRadius(this.ringSize)
    .accessibilityText(this.percent > 0 ? `${this.percent}%` : str('downloading'));
  }
}
