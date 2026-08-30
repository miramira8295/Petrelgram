import { subscribeThumbPath, thumbPathFor } from '../../util/mediaThumbChannel';
import { reuseParam } from '../../util/reuseParams';
import {
  cancelNextFrame, enqueueNextFrame, nextFrameOwnerId
} from '../../util/nextFrameQueue';

// 只在缩略图已经到位（或根本不必等）时渲染内容的小闸门。
//
// 为什么需要它：视频的播放钮原本用 `msg.photoPath !== ''` 判断"缩略图到了
// 没有"，避免和缩略图自己的加载圈叠成两个中心控件。缩略图路径旁路化之后
// （见 mediaThumbChannel），路径不再回写进 MessageEntry、行也不再重建，
// 那个判断就永远是空——播放钮从此不出现。
//
// 和 LiveThumbImage 是同一套办法：自己订阅、自己重建，不惊动整行。区别是
// 它只关心"到了没有"这一个布尔，图由谁画不归它管。
@Component
export struct ThumbReadyGate {
  // 自愈：理由与 LiveThumbImage.onFileIdChanged 同源（复用时  可能晚一帧
  // 落地，只靠下一帧回调会订阅到上一条消息的文件且永不纠正）。
  @Prop @Watch('onFileIdChanged') fileId: number = 0;
  // 调用方已知的路径（历史消息进入时可能本来就带着）。
  @Prop initialPath: string = '';
  // 不必等待：没有缩略图可等（fileId 为 0），或者它已经失败了——这两种
  // 情况下等下去就是永远不显示。
  @Prop ready: boolean = false;
  @BuilderParam content: () => void;
  @State private arrived: boolean = false;
  private unsubThumb: (() => void) | null = null;
  // 回收时挂在哪个文件上。复用时若还是同一个文件，「缩略图到没到」这一位原样留着——理由与
  // LiveThumbImage.recycledFileId 完全相同：@ReusableV2 + reusable:false 下
  // 回收/复用是**普通滑动**的常态，无条件重置 = 每次回收必闪一下。
  // -1 = 没回收过（0 是合法的 fileId，表示「没有文件」）。
  private recycledFileId: number = -1;
  // 见 util/nextFrameQueue：本实例在共享「下一帧」队列里的序号。
  private frameOwnerId: number = nextFrameOwnerId();

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

  private onFileIdChanged(): void {
    cancelNextFrame(this.frameOwnerId);
    this.attach(this.fileId, '');
  }

  aboutToAppear(): void {
    this.attach(this.fileId, this.initialPath);
  }

  aboutToRecycle(): void {
    this.recycledFileId = this.fileId;
    this.detach();
    // 「缩略图到没到」这一位**不在这里重置**，换了文件才重置（见 recycledFileId）。
    // 躺进复用池期间别让上一次复用排的回调再把订阅挂回来——那时已经退订，
    // 没人会再去退它。下一次 aboutToReuse 会重新排队，所以没有丢失。
    cancelNextFrame(this.frameOwnerId);
  }

  aboutToReuse(params: Record<string, Object>): void {
    // reuseParam：params 是 {} 还是 undefined 都安全，取不到就落到下面的
    // setTimeout 兜底（P3 批 2 第 1 项，见 util/reuseParams.ets）。
    const fileId: number | undefined = reuseParam(params, 'fileId') as number | undefined;
    if ((fileId ?? this.fileId) !== this.recycledFileId) {
      this.arrived = false;
    }
    this.recycledFileId = -1;
    const initialPath: string | undefined =
      reuseParam(params, 'initialPath') as string | undefined;
    if (fileId !== undefined) {
      this.attach(fileId, initialPath ?? '');
    }
    // **不 return。** params 那一份只是用来保住这一帧（避免空窗），它是不是和
    // 本组件的 @Prop 同一代，离线证不出来：编译产物里 paramsGenerator_ 只在首建
    // 分支赋值，而 @Prop 的刷新走 updateStateVarsOfChildByElmtId——**两条写入
    // 路径、两个求值时刻**。若 params 是旧一代、而 @Prop 此刻已经是新值，
    // @Watch 就再也不会触发（值没有变化），订阅从此钉死在上一条消息上，而正文
    // 照常更新——那正是用户报的「字是这条的、图是别条的」，且永久，不是闪一下。
    // 所以后面**总是**再按 @Prop 补一次。同 key 短路让重复调用几乎零成本。
    // 合并进共享队列，语义不变（见 util/nextFrameQueue）。
    enqueueNextFrame(this.frameOwnerId,
      (): void => { this.attach(this.fileId, this.initialPath); });
  }

  // 不退订会让箭头函数一直持有本组件实例，组件无法释放。
  aboutToDisappear(): void {
    this.detach();
    // 见 util/nextFrameQueue：撤掉本实例还没跑的那条过期回调。
    cancelNextFrame(this.frameOwnerId);
  }

  build() {
    if (this.ready || this.arrived) {
      this.content();
    }
  }
}
