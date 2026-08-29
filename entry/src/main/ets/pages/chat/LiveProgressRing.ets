import { progressFor, subscribeProgress } from '../../util/mediaProgressChannel';
import { reuseParam } from '../../util/reuseParams';
import {
  cancelNextFrame, enqueueNextFrame, nextFrameOwnerId
} from '../../util/nextFrameQueue';

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
  // 自愈：理由与 LiveThumbImage.onFileIdChanged 同源。进度环挂错文件时，
  // 显示的是另一条消息的下载进度。
  @Prop @Watch('onFileIdChanged') fileId: number = 0;
  @Prop initialPercent: number = 0;
  @Prop ringSize: number = 36;
  @State private percent: number = 0;
  private unsubProgress: (() => void) | null = null;
  // 回收时挂在哪个文件上。复用时若还是同一个文件，进度原样留着——理由与
  // LiveThumbImage.recycledFileId 完全相同：@ReusableV2 + reusable:false 下
  // 回收/复用是**普通滑动**的常态，无条件重置 = 每次回收必闪一下。
  // -1 = 没回收过（0 是合法的 fileId，表示「没有文件」）。
  private recycledFileId: number = -1;
  // 见 util/nextFrameQueue：本实例在共享「下一帧」队列里的序号。
  private frameOwnerId: number = nextFrameOwnerId();

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

  // 第二个参数传 0 而不是 this.initialPercent：后者可能还是上一条的进度。
  // 通道现值 progressFor(fileId) 按新 fileId 查，是对的。
  private onFileIdChanged(): void {
    cancelNextFrame(this.frameOwnerId);
    this.attach(this.fileId, 0);
  }

  aboutToAppear(): void {
    this.attach(this.fileId, this.initialPercent);
  }

  aboutToRecycle(): void {
    this.recycledFileId = this.fileId;
    this.detach();
    // 进度**不在这里重置**，换了文件才重置（见 recycledFileId）。
    // 躺进复用池期间别让上一次复用排的回调再把订阅挂回来——那时已经退订，
    // 没人会再去退它。下一次 aboutToReuse 会重新排队，所以没有丢失。
    cancelNextFrame(this.frameOwnerId);
  }

  aboutToReuse(params: Record<string, Object>): void {
    // reuseParam：params 是 {} 还是 undefined 都安全，取不到就落到下面的
    // setTimeout 兜底（P3 批 2 第 1 项，见 util/reuseParams.ets）。
    const fileId: number | undefined = reuseParam(params, 'fileId') as number | undefined;
    if ((fileId ?? this.fileId) !== this.recycledFileId) {
      this.percent = 0;
    }
    this.recycledFileId = -1;
    const initialPercent: number | undefined =
      reuseParam(params, 'initialPercent') as number | undefined;
    if (fileId !== undefined) {
      this.attach(fileId, initialPercent ?? 0);
      return;
    }
    // 合并进共享队列，语义不变（见 util/nextFrameQueue）。
    enqueueNextFrame(this.frameOwnerId,
      (): void => { this.attach(this.fileId, this.initialPercent); });
  }

  // 不退订会让箭头函数一直持有本组件实例，组件无法释放。
  aboutToDisappear(): void {
    this.detach();
    // 见 util/nextFrameQueue：撤掉本实例还没跑的那条过期回调。
    cancelNextFrame(this.frameOwnerId);
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
