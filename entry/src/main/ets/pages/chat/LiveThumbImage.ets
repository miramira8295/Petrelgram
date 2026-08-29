import { CachedImage } from '../common/CachedImage';
import { logW } from '../../util/log';
import { subscribeThumbPath, thumbPathFor } from '../../util/mediaThumbChannel';
import { reuseParam } from '../../util/reuseParams';
import {
  cancelNextFrame, enqueueNextFrame, nextFrameOwnerId
} from '../../util/nextFrameQueue';

// 探针：一次滑动里有多少媒体行被回收又复用，以及有没有因为换了文件而清图。
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
  // 回收时挂在哪个文件上。复用时若还是同一个文件，位图原样留着（issue #137 在
  // 头像上的做法，这里是它漏掉的另一半）。-1 = 没有回收过；0 是合法值（无图）。
  private recycledFileId: number = -1;
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
    // 记下回收时挂在哪个文件上，复用时据此判断要不要清图。
    this.recycledFileId = this.fileId;
    this.detach();
    // **path 不在这里清**（用户报：翻页时图片乱跳/闪）。
    //
    // 官方《@ReusableV2》：Repeat 的 virtualScroll 配了 `reusable: false`
    // （ChatPage.ets:9570）之后，「滑动场景、更新场景**均会**触发 @ReusableV2 的
    // 回收与复用」，且「回收阶段会**递归**调用所有子组件的 aboutToRecycle（即使
    // 子组件未被标记可复用）」。也就是说这个回调在普通滑动里就会不停地跑。
    //
    // 而本组件的 build() 是 if/else 互斥：path 一空就整个换成占位图。原来在这里
    // 无条件清空，等于**每一次回收都必然空一帧**——哪怕复用回来还是同一条消息、
    // 同一个文件。恢复要等 aboutToReuse 排的下一帧回调（@Prop 没变时 @Watch 不
    // 触发，那条回调是唯一的路），一进一出就是肉眼可见的闪。
    //
    // LiveSenderAvatar 为同一件事修过（MessageBubble.ets 的 recycledAvatarKey，
    // issue #137「翻消息时头像一闪一闪」），缩略图当时没跟上。
    //
    // 注意形状：回收这一刻**拿不到**「下一个 fileId」，所以只能记下当前的、到
    // aboutToReuse 再比，不能写成「下一个相同就不清」。
    this.detach();
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
    // 换了文件才清图（issue #137 的同一套判据）。params 拿不到时用此刻的 @Prop
    // 比：若 @Prop 还没落地，比出来是「同一个文件」、位图先留着——真换了文件，
    // @Prop 落地时 onFileIdChanged 会按新 fileId 重挂并改写 path，赶在那一帧
    // 之前；没换则什么都不用动，那正是要保住的一帧。
    const nextFileId: number = fileId ?? this.fileId;
    const kept: boolean = nextFileId === this.recycledFileId;
    if (!kept) {
      this.path = '';
    }
    const hadRecycled: number = this.recycledFileId;
    this.recycledFileId = -1;
    // 复用规模探针（替掉原来那条 [ImgFlick]）。原探针量的是「回调里读到的
    // fileId 是不是新值」，但它排在 enqueueNextFrame 里，而 onFileIdChanged 第
    // 一句就是 cancelNextFrame —— @Prop 一落地就把它取消了，`stale=` 那一支
    // **在当前代码里根本打不出来**，探针只能证明自己没被取消。
    //
    // 换成在这里打：kept=false 的条数 = 真正因为换文件而清图的次数，
    // kept=true 的条数 = 被这次修复救下来的空帧数，params 则回答「下一帧兜底
    // 是不是唯一路径」（按官方文档 @ReusableV2 的 aboutToReuse 没有入参，
    // 预期 100% 是 false）。
    if (reuseProbeLogged < REUSE_PROBE_LIMIT) {
      reuseProbeLogged++;
      if (kept) {
        reuseProbeSame++;
      } else {
        reuseProbeStale++;
      }
      logW(`[ThumbBlank] reuse file=${hadRecycled}->${nextFileId} kept=${kept}` +
        ` params=${fileId !== undefined} totals kept=${reuseProbeSame} cleared=${reuseProbeStale}`);
    }
    if (fileId !== undefined) {
      this.attach(fileId, initialPath ?? '');
      return;
    }
    // 合并进共享队列，语义不变（见 util/nextFrameQueue）。
    enqueueNextFrame(this.frameOwnerId, (): void => {
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
