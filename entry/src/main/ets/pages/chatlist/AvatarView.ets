import { image } from '@kit.ImageKit';
import { AVATAR_PALETTE, AVATAR_SIZE, COLOR_PRIMARY } from '../../util/theme';
import { formatTTL } from '../../util/formatTTL';
import { LANGUAGE_EPOCH } from '../../util/appLanguage';
import { AvLoopVideo } from '../common/AvLoopVideo';
import { CachedImageSession } from '../../util/CachedImageSession';
import { CachedImageSpec } from '../../util/cachedImageSpec';
import { KEY_POWER_ACTIVE, KEY_POWER_ANIMATED_AVATAR } from '../../store/AppSettings';

@Component
export struct AvatarView {
  @Prop @Watch('onAvatarInputChanged') avatarPath: string;
  @Prop initials: string;
  @Prop @Watch('onAvatarInputChanged') colorSeed: number;
  @Prop autoDeleteTime: number = 0;
  @StorageProp(LANGUAGE_EPOCH) private languageEpoch: number = 0;
  @Prop isLive: boolean = false;
  @Prop livePulseExpanded: boolean = false;
  @Prop isOnline: boolean = false;
  @Prop onlineColor: ResourceColor = COLOR_PRIMARY;
  // Animated profile photo (MPEG4 loop). Only profile pages pass this —
  // list rows stay static (one looping player per row would be too heavy).
  @Prop @Watch('onAvatarInputChanged') animPath: string = '';
  @Prop animationPaused: boolean = false;
  // 「我的收藏」：和自己的私聊。画书签而不是自己的头像——用户在列表里要一眼
  // 认出它，Telegram 各端都是这么处理的（issue #8）。
  @Prop @Watch('onAvatarInputChanged') savedMessages: boolean = false;
  // 预载/隐藏页签先画首字母占位，真正成为当前页后再启动图片或视频解码。
  @Prop @Watch('onAvatarInputChanged') loadImage: boolean = true;
  @StorageProp(KEY_POWER_ACTIVE) @Watch('onAvatarInputChanged') powerSaving: boolean = false;
  @StorageProp(KEY_POWER_ANIMATED_AVATAR) @Watch('onAvatarInputChanged') animatedAvatar: boolean = true;
  // **必须是 @Prop，不能是普通成员**：会话行的头像在手机/平板分栏之间是两个尺寸
  // （见 util/chatRowMetrics），而没有装饰器的成员只在构造时取一次值、之后再不同步
  // ——转屏或进出分栏时已经存在的那些行会停在旧尺寸上（HdsSubDestination 的 menuItems
  // 栽过同一个坑）。数字过 @Prop 的深拷贝没有任何代价。
  @Prop @Watch('onAvatarInputChanged') avatarSize: number = AVATAR_SIZE;
  // 个人资料页「下拉放大头像」用：把「画多大」和「解码多大」拆开传。默认值让
  // 其余 30 多处调用点**零变化**。
  //   boxWidth/boxHeight  实际绘制尺寸，下拉过程中逐帧变——所以故意**不带**
  //                       @Watch：它只影响布局，不该每次触发一遍解码规格重算。
  //   boxRadius           实际圆角；-1 表示沿用圆形（min(w,h)/2）。
  //   decodeWidth/Height  解码分辨率，只在收起/展开两个稳定态之间切换一次。
  @Prop boxWidth: number = 0;
  @Prop boxHeight: number = 0;
  @Prop boxRadius: number = -1;
  @Prop @Watch('onAvatarInputChanged') decodeWidth: number = 0;
  @Prop @Watch('onAvatarInputChanged') decodeHeight: number = 0;
  // 直接在 V1 @Component 内持有 CachedImageSession 与 @State pixelMap，不再嵌套 V2
  // @ComponentV2 的 CachedImage：ChatRow / ContactRowView / MemberRow 等外层都是
  // V1 @Reusable，复用 V2 子组件会导致 ArkUI AceStateMgmt 报
  // `CachedImage activeCount_ error:2` 并冻住旧频道的头像位图。
  @State private pixelMap: image.PixelMap | undefined = undefined;
  private imageActive: boolean = false;
  private imageSession: CachedImageSession = new CachedImageSession(
    (pixels: image.PixelMap | undefined, _ready: boolean): void => {
      if (this.pixelMap !== pixels) {
        this.pixelMap = pixels;
      }
    }
  );

  aboutToAppear(): void {
    this.imageActive = true;
    this.imageSession.activate(this.currentImageSpec());
  }

  aboutToRecycle(): void {
    this.imageActive = false;
    if (this.pixelMap !== undefined) {
      this.pixelMap = undefined;
    }
    this.imageSession.recycle();
  }

  aboutToReuse(_params: Record<string, Object>): void {
    this.imageActive = true;
    this.imageSession.activate(this.currentImageSpec());
  }

  aboutToDisappear(): void {
    this.imageActive = false;
    this.imageSession.dispose();
  }

  private onAvatarInputChanged(): void {
    const spec: CachedImageSpec = this.currentImageSpec();
    if (!this.imageActive) {
      this.imageActive = true;
      this.imageSession.activate(spec);
      return;
    }
    this.imageSession.update(spec);
  }

  private shouldLoadStaticImage(): boolean {
    return !this.savedMessages && !this.shouldAnimate() && this.loadImage && this.avatarPath !== '';
  }

  // 绘制盒尺寸：没传 boxWidth/boxHeight 时就是原来的方/圆 avatarSize。
  private boxW(): number {
    return this.boxWidth > 0 ? this.boxWidth : this.avatarSize;
  }

  private boxH(): number {
    return this.boxHeight > 0 ? this.boxHeight : this.avatarSize;
  }

  // -1 = 圆形（与历史行为逐像素相同）；>=0 用调用方给的值。
  private boxR(): number {
    if (this.boxRadius >= 0) {
      return this.boxRadius;
    }
    return Math.min(this.boxW(), this.boxH()) / 2;
  }

  private currentImageSpec(): CachedImageSpec {
    // 解码尺寸与绘制尺寸分开：资料页展开后是 360×390 的大图，但解码只需要按
    // 那张稳定态要一次；下拉途中的 100→380 由绘制拉伸，不去重解码。
    const dw: number = this.decodeWidth > 0 ? this.decodeWidth : this.boxW();
    const dh: number = this.decodeHeight > 0 ? this.decodeHeight : this.boxH();
    return {
      path: this.shouldLoadStaticImage() ? this.avatarPath : '',
      sourceKey: `${this.colorSeed}:${this.avatarPath}`,
      boxWidth: dw,
      boxHeight: dh,
      radius: Math.min(dw, dh) / 2,
      fit: ImageFit.Cover,
      pinBounded: true,
    };
  }

  // 动态头像播不播。
  //
  // 原来挂在"自动播放视频"（KEY_POWER_AUTOPLAY_VIDEO）上，那是把实现细节
  // 漏到了用户语义上——恰好都用播放器解码，就被绑到了同一个开关。可这两件
  // 事的用户预期完全不同：「自动播放视频」是"聊天里的视频别自动播"，动机是
  // 省流量；而动态头像是几十 KB 的循环片段、**而且早就下载完了**，不播它一
  // 点流量都省不了，只是让界面变呆。用户在设置里看到那一行，也不会想到它管
  // 的是头像。
  //
  // 改成省电设置里自己的一档「播放动图头像」。省电模式仍然是总闸。
  //
  // 别处的边界本来就是对的（MessageStore 里 isAnimation ? GIF : VIDEO），
  // 只有头像这一处错了。
  private shouldAnimate(): boolean {
    return this.loadImage && this.animPath !== '' && this.animatedAvatar && !this.powerSaving;
  }

  @Builder
  base() {
    if (this.savedMessages) {
      Row() {
        SymbolGlyph($r('sys.symbol.bookmark_fill'))
          .fontSize(Math.min(this.boxW(), this.boxH()) * 0.5)
          .fontColor([Color.White]);
      }
      .width(this.boxW()).height(this.boxH())
      .borderRadius(this.boxR())
      .backgroundColor(COLOR_PRIMARY)
      .justifyContent(FlexAlign.Center);
    } else if (this.shouldAnimate()) {
      // Animated avatars are H.264 MP4 — the system AVPlayer loops them with
      // hardware decode (far lighter than ijkplayer's software path).
      Column() {
        AvLoopVideo({
          videoPath: this.animPath,
          paused: this.animationPaused,
          boxWidth: this.boxW(),
          boxHeight: this.boxH()
        });
      }
      .width(this.boxW()).height(this.boxH())
      .borderRadius(this.boxR())
      .clip(true);
    } else if (this.avatarPath !== '') {
      // Through the PixelMap cache, like chat photos. Avatars are small but
      // there are a lot of them and they repeat: the same file is decoded for
      // every row showing that chat and again after every recycle. Straight
      // Image(file://…) redid all of that, which is why chat-list rows WITH an
      // avatar stuttered more than rows falling back to initials.
      Stack() {
        // The initials sit underneath so a pending decode shows the coloured
        // circle rather than a hole.
        this.initialsCircle();
        if (this.loadImage) {
          Image(this.pixelMap)
            .draggable(false)
            .width(this.boxW()).height(this.boxH())
            .borderRadius(this.boxR())
            .clip(true)
            .interpolation(ImageInterpolation.High)
            .objectFit(ImageFit.Cover);
        }
      }
      .width(this.boxW()).height(this.boxH());
    } else {
      this.initialsCircle();
    }
  }

  // 单 Text 画整颗字母头像：圆是 backgroundColor + borderRadius，居中靠
  // align/textAlign。原来是 Stack{Circle,Text} 三个节点——这颗头像每行一个、
  // 全 APP 30 处调用，精简节点数从这种无属性容器下手（docs/chatlist-perf-todo
  // 第 2 条，rs_node 实测 142 节点/行）。
  @Builder
  initialsCircle() {
    Text(this.initials)
      .fontColor(Color.White).fontSize(Math.min(this.boxW(), this.boxH()) * 0.4).fontWeight(FontWeight.Medium)
      .width(this.boxW()).height(this.boxH())
      .align(Alignment.Center).textAlign(TextAlign.Center)
      .backgroundColor(AVATAR_PALETTE[Math.abs(this.colorSeed) % AVATAR_PALETTE.length])
      .borderRadius(this.boxR());
  }

  private ttlBadgeSize(): number {
    return this.avatarSize < 42 ? 18 : 22;
  }

  private ttlRingSize(): number {
    return this.avatarSize < 42 ? 15 : 18.5;
  }

  private ttlFontSize(): number {
    return this.avatarSize < 42 ? 6.5 : 7.5;
  }

  build() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      this.base();
      if (this.isOnline && !this.isLive && this.autoDeleteTime <= 0 && !this.savedMessages) {
        Row()
          .width(this.avatarSize < 42 ? 12 : 14)
          .height(this.avatarSize < 42 ? 12 : 14)
          .backgroundColor(this.onlineColor)
          .border({ width: 2, color: $r('app.color.surface') })
          .borderRadius(this.avatarSize < 42 ? 6 : 7)
          .translate({ x: 1, y: 1 });
      }
      if (this.autoDeleteTime > 0 && !this.isLive) {
        Stack({ alignContent: Alignment.Center }) {
          Image($r('app.media.ic_auto_delete_ring'))
            .width(this.ttlRingSize())
            .height(this.ttlRingSize())
            .draggable(false);
          Text(this.languageEpoch >= 0 ? formatTTL(this.autoDeleteTime) : '')
            .fontSize(this.ttlFontSize())
            .fontColor(Color.White)
            .fontWeight(FontWeight.Bold)
            .textAlign(TextAlign.Center)
            .maxLines(1);
        }
        .width(this.ttlBadgeSize())
        .height(this.ttlBadgeSize())
        .backgroundColor(COLOR_PRIMARY)
        .borderRadius(this.ttlBadgeSize() / 2)
        .border({ width: 1.5, color: $r('app.color.surface') })
        .translate({ x: 1, y: 1 });
      }
      if (this.isLive) {
        Stack({ alignContent: Alignment.Center }) {
          Circle({ width: 22, height: 22 })
            .fill('#442AABEE')
            .opacity(this.livePulseExpanded ? 0.18 : 0.52)
            .scale({
              x: this.livePulseExpanded ? 1.12 : 0.92,
              y: this.livePulseExpanded ? 1.12 : 0.92
            });
          Circle({ width: 18, height: 18 })
            .fill('#F8FCFF')
            .border({ width: 0.8, color: '#382A88C9' })
            .scale({
              x: this.livePulseExpanded ? 1.03 : 0.98,
              y: this.livePulseExpanded ? 1.03 : 0.98
            });
          Row({ space: 1.5 }) {
            Circle({ width: 2.5, height: 2.5 }).fill('#249FE8');
            Rect({ width: 2.5, height: 8, radius: 1.25 }).fill('#249FE8');
            Rect({ width: 2.5, height: 8, radius: 1.25 }).fill('#249FE8');
            Circle({ width: 2.5, height: 2.5 }).fill('#249FE8');
          }.alignItems(VerticalAlign.Center);
        }
        .width(22).height(22)
        .translate({ x: 1, y: 1 });
      }
    }
    .width(this.boxW()).height(this.boxH());
  }
}
