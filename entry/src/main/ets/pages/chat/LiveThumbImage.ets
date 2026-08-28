import { CachedImage } from '../common/CachedImage';
import { logW } from '../../util/log';
import { subscribeThumbPath, thumbPathFor } from '../../util/mediaThumbChannel';
import { reuseParam } from '../../util/reuseParams';
import {
  cancelNextFrame, enqueueNextFrame, nextFrameOwnerId
} from '../../util/nextFrameQueue';

// 探针：复用回来的那一刻，@Prop fileId 到底是新值还是旧值？
//
// aboutToReuse 里那条 setTimeout(0) 之所以还在，唯一的理由是「官方没有写清
// 状态变量重置与 aboutToReuse 回调的先后」（见 ReusableMessageBubble 里同一段
// 论证）。父级 @ReusableV2 的 aboutToReuse 没有入参，reuseParam 因此恒为
// undefined，于是**每一次复用都走延迟分支**：回收时 path 已经被清空、build 当帧
// 切到 placeholder，恢复却要等下一帧——一进一出保证了一帧空窗。
//
// 想同步恢复就必须先证明「aboutToReuse 里读到的 this.fileId 已经是新值」。
// 这个探针就是那份证据：把回调当时读到的 fileId 和一帧之后读到的比一比。
// 判读（沙箱 petrelgram-log.txt，攒够 300 行才落盘，所以样本上限压得很小）：
//   · 全部 same= 且 sync 数量可观 → this.fileId 在回调里已经是新值，可以删定时器；
//   · 出现 stale= → 回调里读到的是旧值，定时器必须留着。
const REUSE_PROBE_LIMIT: number = 24;
let reuseProbeLogged: number = 0;
let reuseProbeSame: number = 0;
let reuseProbeStale: number = 0;

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
  // @Watch 是这一族组件的**自愈**那一半，缺了它就会「图配错文」（用户报：往上翻
  // 历史加载新数据后，有的行图片是上一条的）。机理：父级是 @ReusableV2，
  // aboutToReuse **没有入参**，只能排一个下一帧回调去读 this.fileId；那时 @Prop
  // 若还没落地，就订阅到了上一条消息的文件，而且**再也不会纠正**——正文走 @Prop
  // 正常更新，图却永远停在旧的。挂上 @Watch 之后，fileId 无论早一帧还是晚一帧
  // 落地，订阅都会按新值自己纠正。LiveSenderAvatar 早就是这么做的，这一族其余
  // 组件当时漏了。
  @Prop @Watch('onFileIdChanged') fileId: number = 0;
  @Prop initialPath: string = '';
  @Prop boxWidth: number = 0;
  @Prop boxHeight: number = 0;
  @Prop radius: number = 0;
  @Prop fit: ImageFit = ImageFit.Cover;
  @BuilderParam placeholder: () => void;
  @State private path: string = '';
  private unsubThumb: (() => void) | null = null;
  // 见 util/nextFrameQueue：本实例在共享「下一帧」队列里的序号。
  private frameOwnerId: number = nextFrameOwnerId();

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

  // 第二个参数传 ''，不传 this.initialPath：@Prop 是逐个落地的，fileId 的回调
  // 触发时 initialPath 可能还是**上一条消息**的路径，拿它兜底等于把旧图画上去。
  // 通道现值 thumbPathFor(fileId) 是按新 fileId 查的，本来就对。
  private onFileIdChanged(): void {
    cancelNextFrame(this.frameOwnerId);
    this.attach(this.fileId, '');
  }

  aboutToAppear(): void {
    this.attach(this.fileId, this.initialPath);
  }

  aboutToRecycle(): void {
    this.detach();
    this.path = '';
    // 躺进复用池期间别让上一次复用排的回调再把订阅挂回来——那时已经退订，
    // 没人会再去退它。下一次 aboutToReuse 会重新排队，所以没有丢失。
    cancelNextFrame(this.frameOwnerId);
  }

  aboutToReuse(params: Record<string, Object>): void {
    // reuseParam：params 是 {} 还是 undefined 都安全，取不到就落到下面的
    // setTimeout 兜底（P3 批 2 第 1 项，见 util/reuseParams.ets）。
    const fileId: number | undefined = reuseParam(params, 'fileId') as number | undefined;
    const initialPath: string | undefined =
      reuseParam(params, 'initialPath') as string | undefined;
    if (fileId !== undefined) {
      this.attach(fileId, initialPath ?? '');
      return;
    }
    const seenAtReuse: number = this.fileId;
    // 合并进共享队列，语义不变（见 util/nextFrameQueue）。探针原样保留。
    enqueueNextFrame(this.frameOwnerId, (): void => {
      const seenNextFrame: number = this.fileId;
      if (seenAtReuse === seenNextFrame) {
        reuseProbeSame++;
      } else {
        reuseProbeStale++;
      }
      if (reuseProbeLogged < REUSE_PROBE_LIMIT) {
        reuseProbeLogged++;
        logW(`[ImgFlick] LiveThumbImage reuse ` +
          `${seenAtReuse === seenNextFrame ? 'same' : 'stale'}=` +
          `${seenAtReuse}->${seenNextFrame} totals same=${reuseProbeSame} ` +
          `stale=${reuseProbeStale}`);
      }
      this.attach(this.fileId, this.initialPath);
    });
  }

  // 不退订会让箭头函数一直持有本组件实例，组件无法释放（官方状态管理 FAQ
  // 明确点过这个泄漏）。
  aboutToDisappear(): void {
    this.detach();
    // 见 util/nextFrameQueue：撤掉本实例还没跑的那条过期回调。
    cancelNextFrame(this.frameOwnerId);
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
