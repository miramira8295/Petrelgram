// 【自绘玻璃，不走组件级系统材质】系统已经把**组件级**的 systemMaterial 收回，
// 只有 HDS 导航级的栏（HdsNavigation 的 titleBar、HdsTabs 的 barFloatingStyle）
// 还拿得到。继续用 overlayGlassFill + overlayBackdropBlur 的面会两头落空——
// 前者按"底下还有材质在画"返回 25% 的淡色，后者按"把观感让给材质"返回 0 半径，
// 结果既没有材质也没有自己的玻璃，就是一块平板（用户 2026-09-07：
// 「会话详情底下的几个控制条实现样式和输入框不太一样」）。
// 输入框（ChatComposerInput）早已迁到 plainGlassFill + plainBackdropBlur +
// hdsVisualEffect 这一套，这里跟上，三者的档位保持各自原有的 surface 不变。
import { COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_ICON_SECONDARY, COLOR_TEXT_SECONDARY } from '../../util/theme';
import {
  KEY_POWER_PARTICLES, KEY_POWER_SMOOTH_TRANSITIONS, powerAnimationDuration
} from '../../store/AppSettings';
import { plainBackdropBlur, plainGlassFill } from '../../util/overlayMaterial';
import { hdsVisualEffect } from '../../util/hdsPointLight';
import { pinnedActiveSeg, pinnedSegIndices, pinnedShownIndex } from '../../util/pinnedSegments';
import { plural, str } from '../../util/strings';
import {
  CHAT_TOP_BANNER_BOTTOM_GAP, CHAT_TOP_BANNER_DIVIDER_HEIGHT, CHAT_TOP_BANNER_ROW_HEIGHT,
  ChatChromeGeometryInput, chatTopBannerHeight
} from '../../util/ChatChromeGeometry';
import { LiveTopCardController } from './LiveTopCardController';

// 消息列表上方那张浮卡：置顶消息条 + 直播状态条，两条共用一张卡。
//
// 从 ChatPage 搬出来。它是纯展示——只有两个动作（点置顶条定位、点直播条进入）。
// B5 更正：这两个动作原来那句"留在页面里"已经不准了——它们连同整簇状态机搬进了
// LiveTopCardController；页面只留下它们碰的那部分共享真源（scroller、
// pendingJumpId）。本层的角色一个字没变：只发回调，@Event → ChatPage →
// topCard.onPinnedTap() / topCard.onLiveStreamTap()。
//
// 进度格的滑动窗口算术搬去了 util/pinnedSegments，单测钉住了那几个边界。

const LIVE_ACCENT: string = '#FF405C';
const LIVE_ACCENT_PRESSED: string = '#E93652';

// 状态管理 V2（B2 批）。这一步本身不求性能收益，它是后续批次的前置：V1 的
// @Component 既不能声明 @Param、也订阅不了 @ObservedV2 类上的 @Trace，而
// 「宿主接控制器实例、在自己的 build() 里直读 @Trace」是唯一能真正缩小 ChatPage
// 重渲染半径的做法。配方照 25d3797（MediaViewerOverlay / ReactionSheet 那次）。
//
// 本层的入参全是 string/number/boolean，@Prop（复杂类型深拷贝 + 单向同步）换成
// @Param（引用 + 单向同步）在这里是等价变换，零行为变更。
// build() 里没有任何自定义子组件（全是内置组件），不触及「V2 普通组件挂 V1
// @Reusable 子组件会静默不建节点」那个坑。
//
// B5 更正：上面那句"入参全是 string/number/boolean"说的是 B2 当时的形状。B5 之后
// 那 13 个标量入参已被一个 LiveTopCardController 引用整体取代，只剩 materialEpoch
// 还是标量；@Param 收控制器引用这件事本身仍是"引用 + 单向同步"，与 B2 结论一致。
@ComponentV2
export struct TopBanners {
  // 材质档位（厚度/光感）改变时重绘。overlayMaterial 是 util，订阅不了
  // AppStorage，只能由调用方订阅，同 LANGUAGE_EPOCH 的做法。
  // B2 迁移更正：V2 没有 @StorageProp/@StorageLink 的等价物，材质纪元改由
  // ChatPage 透传（页面自己就持有这个键）；同时去掉 private——@Param 要能被父
  // 组件构造传参。纪元变化的路径从「宿主自订阅」变成「ChatPageChrome → ChatPage
  // → 宿主」，多两次 === 比较，无行为差。
  @Param materialEpoch: number = 0;
  // 这张卡的全部显示态，一个 @ObservedV2 控制器（B5 批）。置顶条读它的 pinned*
  // 五个 @Trace、直播条读 live* 七个，另加一个 topCardLoadingVisible——字段名与取值
  // 和搬之前的 13 个标量 @Param 一一对应，只是住的地方从 ChatPage 的 @Local 换成了
  // 控制器上的 @Trace。原来挂在这两个字段上的注释一并留下：pinnedLoadState 的取值
  // 是 'loading' | 'ready' | 'error'；topCardLoadingVisible 是"两条都还没定下来时
  // 显示的同步态"。
  //
  // 【为什么值得换】改前这 13 个值住在页面里：任何一个变化都要先重跑 ChatPage 的
  // chatTitleBarBottom 闭包，再逐个做 13 次 @Param 比较，最后才轮到本组件。最密的
  // 那一个是 livePulseExpanded——直播条只要亮着就每 780ms 翻一次，一次呼吸动画的
  // 代价是整页一轮依赖重算。改后本组件直接持有控制器引用、在自己的 build() 里读
  // @Trace：翻转只刷新读到它的那几个节点（竖条的 opacity/scale + 那颗圆点），
  // ChatPage 一个字都不读，13 次比较也一起消失。
  // 只把字段搬进控制器、读点还留在页面的话，收益就只有行数——本层直读才是 B5 真正
  // 缩小重渲染半径的地方。
  //
  // 【纪律】只能在 build()、本组件的 @Builder、以及被它们**同步调用**的私有方法里
  // 读 this.topCard.xxx。@Trace 的订阅是在节点 build 的那一刻按"这次读过谁"记下来
  // 的：一旦在 build 之外（生命周期回调、事件回调、字段初始化器）把值抄进局部变量
  // 或普通字段，依赖就不会建立，值变了这里不刷新。下面的 hasContent / liveShowing /
  // containerHeight / onlineText 都只从 build/@Builder 同步调用，读发生在 build 期
  // 间，依赖照常收集。
  //
  // 不带默认值：@Require 已经保证调用点必须传（同 FloatingDateOverlay 的
  // `@Require @Param state: FloatingDateState`）。引用由 ChatPage 的字段初始化器
  // new 出来、全生命周期不变，所以 @Param 那层的 `!==` 永不成立，本组件不会因为
  // 父组件重建而整体重刷。
  @Require @Param topCard: LiveTopCardController;

  // 两个回调一律 @Event：调用点传的是内联箭头函数，页面每重建一次都是新闭包，
  // 用 @Param 的话那个 `!==` 恒不相等会让本层跟着页面白刷；@Event 不具备观测
  // 能力，正好复现迁移前普通字段的行为。空实现默认值保留（仓库惯例：组件要能
  // 脱离父组件独立预览）。
  @Event onPinnedTap: () => void = (): void => {};
  @Event onLiveStreamTap: () => void = (): void => {};

  @Styles
  rowNormalStyle() {
    .backgroundColor(Color.Transparent)
    .opacity(1)
    .scale({ x: 1, y: 1 })
  }

  @Styles
  rowPressedStyle() {
    .backgroundColor($r('app.color.surface_alt'))
    .opacity(0.82)
    .scale({ x: 0.992, y: 0.97 })
  }

  @Styles
  liveEntryNormalStyle() {
    .backgroundColor(LIVE_ACCENT)
    .opacity(1)
    .scale({ x: 1, y: 1 })
  }

  @Styles
  liveEntryPressedStyle() {
    .backgroundColor(LIVE_ACCENT_PRESSED)
    .opacity(0.82)
    .scale({ x: 0.94, y: 0.94 })
  }

  private hasContent(): boolean {
    return this.topCard.pinnedPreview !== '' ||
      (this.topCard.liveGroupCallId > 0 && this.topCard.liveCallIsActive);
  }

  private liveShowing(): boolean {
    return this.topCard.liveGroupCallId > 0 && this.topCard.liveCallIsActive;
  }

  private containerHeight(): number {
    const input: ChatChromeGeometryInput = {
      topSafe: 0,
      searchMode: false,
      pinnedVisible: this.topCard.pinnedPreview !== '',
      liveVisible: this.liveShowing(),
      loadingVisible: this.topCard.topCardLoadingVisible
    };
    // 外层的 bottom:2 margin 由父布局计算，不属于节点自己的 height。
    return chatTopBannerHeight(input) - CHAT_TOP_BANNER_BOTTOM_GAP;
  }

  // 直播条上那句"多少人在线"。a11y 文案要把它拼进整句里，所以用 str/plural
  // 取字符串而不是 $r()——Resource 塞进模板串会变成 "[object Object]"。
  private onlineText(): string {
    return this.topCard.liveParticipantCount > 0
      ? plural('cp_n_online', this.topCard.liveParticipantCount, this.topCard.liveParticipantCount)
      : str('cp_live_in_progress');
  }

  @Builder
  pinnedBanner() {
    Row({ space: 10 }) {
      Column() {
        ForEach(pinnedSegIndices(this.topCard.pinnedCount), (i: number) => {
          Column().width(3).layoutWeight(1)
            .backgroundColor(i === pinnedActiveSeg(this.topCard.pinnedCycle, this.topCard.pinnedCount)
              ? COLOR_PRIMARY : '#303E3E40')
            .borderRadius(1.5).margin({ top: 1, bottom: 1 });
        }, (i: number) => `seg_${i}_${i === pinnedActiveSeg(this.topCard.pinnedCycle, this.topCard.pinnedCount)}`);
      }.height(34).width(3);
      Column({ space: 2 }) {
        Row({ space: 6 }) {
          Text($r('app.string.cp_pinned_message')).fontSize(12)
            .fontColor(COLOR_PRIMARY).fontWeight(FontWeight.Medium);
          if (this.topCard.pinnedCount > 1) {
            Text(`${pinnedShownIndex(this.topCard.pinnedCycle, this.topCard.pinnedCount) + 1}/${this.topCard.pinnedCount}`)
              .fontSize(10)
              .fontColor(COLOR_TEXT_SECONDARY);
          }
          if (this.topCard.pinnedLoadState === 'loading') {
            LoadingProgress().width(12).height(12).color(COLOR_PRIMARY);
          }
        }
        Text(this.topCard.pinnedPreview).fontSize(13).fontColor(COLOR_TEXT_PRIMARY)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
      }
      .alignItems(HorizontalAlign.Start).layoutWeight(1);
      if (this.topCard.pinnedJumpBusy) {
        LoadingProgress().width(18).height(18).color(COLOR_PRIMARY);
      } else {
        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(15)
          .fontColor([COLOR_ICON_SECONDARY]);
      }
    }
    .width('100%')
    .height(CHAT_TOP_BANNER_ROW_HEIGHT)
    .padding({ left: 14, right: 14, top: 8, bottom: 8 })
    .alignItems(VerticalAlign.Center)
    .stateStyles({ normal: this.rowNormalStyle, pressed: this.rowPressedStyle })
    .animation({
      duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 130),
      curve: Curve.EaseOut
    })
    .enabled(!this.topCard.pinnedJumpBusy)
    .accessibilityText(str('cp_pinned_a11y', this.topCard.pinnedPreview))
    .onClick((): void => { this.onPinnedTap(); });
  }

  // 置顶和直播是同一张卡里的两个独立动作。并存时两者都保留，层级也说得清楚：
  // 置顶内容在前，正在进行的直播在后。
  @Builder
  liveStreamBanner() {
    Row({ space: 10 }) {
      Column()
        .width(3).height(34).backgroundColor(LIVE_ACCENT).borderRadius(1.5)
        .opacity(this.topCard.livePulseExpanded ? 1 : 0.62)
        .scale({ x: 1, y: this.topCard.livePulseExpanded ? 1 : 0.82 })
        .animation({
          duration: powerAnimationDuration(KEY_POWER_PARTICLES, 720),
          curve: Curve.EaseInOut
        });
      Column({ space: 2 }) {
        Row({ space: 6 }) {
          Text($r('app.string.cp_live_now')).fontSize(12)
            .fontColor(LIVE_ACCENT).fontWeight(FontWeight.Medium);
          if (this.topCard.liveCallIsRtmp) {
            Text($r('app.string.cp_one_way')).fontSize(9)
              .fontColor(Color.White).fontWeight(FontWeight.Bold)
              .padding({ left: 5, right: 5, top: 2, bottom: 2 })
              .backgroundColor(LIVE_ACCENT).borderRadius(6);
          }
          Circle({ width: 6, height: 6 }).fill(LIVE_ACCENT)
            .opacity(this.topCard.livePulseExpanded ? 1 : 0.45);
        }
        Text(this.onlineText())
          .fontSize(13).fontColor(COLOR_TEXT_PRIMARY)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
      }
      .alignItems(HorizontalAlign.Start).layoutWeight(1);
      Button() {
        Row({ space: 5 }) {
          if (this.topCard.liveDialogOpening || this.topCard.liveNavigationBusy) {
            LoadingProgress().width(13).height(13).color(Color.White);
          }
          Text(this.topCard.liveNavigationBusy ? $r('app.string.cp_entering') : $r('app.string.cp_enter'))
            .fontSize(12)
            .fontColor(Color.White)
            .fontWeight(FontWeight.Medium);
        }
      }
      .height(32).padding({ left: 12, right: 12 })
      .borderRadius(16)
      .stateStyles({ normal: this.liveEntryNormalStyle, pressed: this.liveEntryPressedStyle })
      .enabled(!this.topCard.liveDialogOpening && !this.topCard.liveNavigationBusy)
      .onClick((): void => { this.onLiveStreamTap(); });
    }
    .width('100%')
    .height(CHAT_TOP_BANNER_ROW_HEIGHT)
    .padding({ left: 14, right: 12, top: 8, bottom: 8 })
    .alignItems(VerticalAlign.Center)
    .stateStyles({ normal: this.rowNormalStyle, pressed: this.rowPressedStyle })
    .animation({
      duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 130),
      curve: Curve.EaseOut
    })
    .accessibilityText(str('cp_live_a11y', this.onlineText()))
    .onClick((): void => { this.onLiveStreamTap(); });
  }

  @Builder
  loadingBanner() {
    Row({ space: 12 }) {
      LoadingProgress().width(22).height(22).color(COLOR_PRIMARY);
      Column({ space: 2 }) {
        Text($r('app.string.cp_syncing_chat'))
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(COLOR_TEXT_PRIMARY);
        Text($r('app.string.cp_checking_pinned_live'))
          .fontSize(12)
          .fontColor(COLOR_TEXT_SECONDARY);
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1);
    }
    .width('100%')
    .height(CHAT_TOP_BANNER_ROW_HEIGHT)
    .padding({ left: 14, right: 14, top: 8, bottom: 8 })
    .alignItems(VerticalAlign.Center)
    .accessibilityText($r('app.string.cp_syncing_pinned_live'));
  }

  build() {
    Column() {
      if (this.hasContent()) {
        if (this.topCard.pinnedPreview !== '') {
          this.pinnedBanner();
        }
        if (this.topCard.pinnedPreview !== '' && this.liveShowing()) {
          Divider()
            .strokeWidth(0.5)
            .height(CHAT_TOP_BANNER_DIVIDER_HEIGHT)
            .color($r('app.color.divider'))
            .margin({ left: 14, right: 14 });
        }
        if (this.liveShowing()) {
          this.liveStreamBanner();
        }
      } else if (this.topCard.topCardLoadingVisible) {
        this.loadingBanner();
      }
    }
    .width('calc(100% - 24vp)')
    .height(this.containerHeight())
    // 置顶消息条和直播状态条共用这一张卡，它浮在消息列表之上、消息从下面
    // 滚过去——和顶栏胶囊、dock 是同一种角色，所以走同一档 'bar' 玻璃。
    // 自绘玻璃的两半要一起上：半透明底 + backdropBlur（不透明底会把模糊盖死）。
    .backgroundColor(plainGlassFill($r('app.color.surface')))
    .backdropBlur(plainBackdropBlur('bar'))
    .borderRadius(14)
    .margin({ left: 12, right: 12, bottom: 2 })
    // 'bar' 档自带阴影关闭，这条浮卡的阴影保持自己的。
    .shadow({ radius: 5, color: '#12000000', offsetX: 0, offsetY: 1 })
    .clip(true)
    .visualEffect(hdsVisualEffect('bar'))
    .transition(TransitionEffect.OPACITY
      .combine(TransitionEffect.translate({ y: -6 }))
      .animation({
        duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 240),
        curve: Curve.EaseOut
      }));
  }
}
