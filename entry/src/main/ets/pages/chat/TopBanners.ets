import { COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_ICON_SECONDARY, COLOR_TEXT_SECONDARY } from '../../util/theme';
import {
  KEY_POWER_PARTICLES, KEY_POWER_SMOOTH_TRANSITIONS, powerAnimationDuration
} from '../../store/AppSettings';
import {
  overlayBackdropBlur, overlayGlassFill, MATERIAL_EPOCH
} from '../../util/overlayMaterial';
import { materialModifier } from '../../util/materialModifier';
import { pinnedActiveSeg, pinnedSegIndices, pinnedShownIndex } from '../../util/pinnedSegments';
import { plural, str } from '../../util/strings';
import {
  CHAT_TOP_BANNER_BOTTOM_GAP, CHAT_TOP_BANNER_DIVIDER_HEIGHT, CHAT_TOP_BANNER_ROW_HEIGHT,
  ChatChromeGeometryInput, chatTopBannerHeight
} from '../../util/ChatChromeGeometry';

// 消息列表上方那张浮卡：置顶消息条 + 直播状态条，两条共用一张卡。
//
// 从 ChatPage 搬出来。它是纯展示——只有两个动作（点置顶条定位、点直播条进入），
// 两者都要碰 store、scroller 和跳转守卫，留在页面里，这里只回调。
//
// 进度格的滑动窗口算术搬去了 util/pinnedSegments，单测钉住了那几个边界。

const LIVE_ACCENT: string = '#FF405C';
const LIVE_ACCENT_PRESSED: string = '#E93652';

@Component
export struct TopBanners {
  // 材质档位（厚度/光感）改变时重绘。overlayMaterial 是 util，订阅不了
  // AppStorage，只能由调用方订阅，同 LANGUAGE_EPOCH 的做法。
  @StorageProp(MATERIAL_EPOCH) private materialEpoch: number = 0;
  // 置顶条
  @Prop pinnedPreview: string;
  @Prop pinnedCount: number;
  @Prop pinnedCycle: number;
  // 'loading' | 'ready' | 'error'
  @Prop pinnedLoadState: string;
  @Prop pinnedJumpBusy: boolean;
  // 直播条
  @Prop liveGroupCallId: number;
  @Prop liveCallIsActive: boolean;
  @Prop liveCallIsRtmp: boolean;
  @Prop liveParticipantCount: number;
  @Prop livePulseExpanded: boolean;
  @Prop liveDialogOpening: boolean;
  @Prop liveNavigationBusy: boolean;
  // 两条都还没定下来时显示的同步态。
  @Prop topCardLoadingVisible: boolean;

  onPinnedTap: () => void = (): void => {};
  onLiveStreamTap: () => void = (): void => {};

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
    return this.pinnedPreview !== '' ||
      (this.liveGroupCallId > 0 && this.liveCallIsActive);
  }

  private liveShowing(): boolean {
    return this.liveGroupCallId > 0 && this.liveCallIsActive;
  }

  private containerHeight(): number {
    const input: ChatChromeGeometryInput = {
      topSafe: 0,
      searchMode: false,
      pinnedVisible: this.pinnedPreview !== '',
      liveVisible: this.liveShowing(),
      loadingVisible: this.topCardLoadingVisible
    };
    // 外层的 bottom:2 margin 由父布局计算，不属于节点自己的 height。
    return chatTopBannerHeight(input) - CHAT_TOP_BANNER_BOTTOM_GAP;
  }

  // 直播条上那句"多少人在线"。a11y 文案要把它拼进整句里，所以用 str/plural
  // 取字符串而不是 $r()——Resource 塞进模板串会变成 "[object Object]"。
  private onlineText(): string {
    return this.liveParticipantCount > 0
      ? plural('cp_n_online', this.liveParticipantCount, this.liveParticipantCount)
      : str('cp_live_in_progress');
  }

  @Builder
  pinnedBanner() {
    Row({ space: 10 }) {
      Column() {
        ForEach(pinnedSegIndices(this.pinnedCount), (i: number) => {
          Column().width(3).layoutWeight(1)
            .backgroundColor(i === pinnedActiveSeg(this.pinnedCycle, this.pinnedCount)
              ? COLOR_PRIMARY : '#303E3E40')
            .borderRadius(1.5).margin({ top: 1, bottom: 1 });
        }, (i: number) => `seg_${i}_${i === pinnedActiveSeg(this.pinnedCycle, this.pinnedCount)}`);
      }.height(34).width(3);
      Column({ space: 2 }) {
        Row({ space: 6 }) {
          Text($r('app.string.cp_pinned_message')).fontSize(12)
            .fontColor(COLOR_PRIMARY).fontWeight(FontWeight.Medium);
          if (this.pinnedCount > 1) {
            Text(`${pinnedShownIndex(this.pinnedCycle, this.pinnedCount) + 1}/${this.pinnedCount}`)
              .fontSize(10)
              .fontColor(COLOR_TEXT_SECONDARY);
          }
          if (this.pinnedLoadState === 'loading') {
            LoadingProgress().width(12).height(12).color(COLOR_PRIMARY);
          }
        }
        Text(this.pinnedPreview).fontSize(13).fontColor(COLOR_TEXT_PRIMARY)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
      }
      .alignItems(HorizontalAlign.Start).layoutWeight(1);
      if (this.pinnedJumpBusy) {
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
    .enabled(!this.pinnedJumpBusy)
    .accessibilityText(str('cp_pinned_a11y', this.pinnedPreview))
    .onClick((): void => { this.onPinnedTap(); });
  }

  // 置顶和直播是同一张卡里的两个独立动作。并存时两者都保留，层级也说得清楚：
  // 置顶内容在前，正在进行的直播在后。
  @Builder
  liveStreamBanner() {
    Row({ space: 10 }) {
      Column()
        .width(3).height(34).backgroundColor(LIVE_ACCENT).borderRadius(1.5)
        .opacity(this.livePulseExpanded ? 1 : 0.62)
        .scale({ x: 1, y: this.livePulseExpanded ? 1 : 0.82 })
        .animation({
          duration: powerAnimationDuration(KEY_POWER_PARTICLES, 720),
          curve: Curve.EaseInOut
        });
      Column({ space: 2 }) {
        Row({ space: 6 }) {
          Text($r('app.string.cp_live_now')).fontSize(12)
            .fontColor(LIVE_ACCENT).fontWeight(FontWeight.Medium);
          if (this.liveCallIsRtmp) {
            Text($r('app.string.cp_one_way')).fontSize(9)
              .fontColor(Color.White).fontWeight(FontWeight.Bold)
              .padding({ left: 5, right: 5, top: 2, bottom: 2 })
              .backgroundColor(LIVE_ACCENT).borderRadius(6);
          }
          Circle({ width: 6, height: 6 }).fill(LIVE_ACCENT)
            .opacity(this.livePulseExpanded ? 1 : 0.45);
        }
        Text(this.onlineText())
          .fontSize(13).fontColor(COLOR_TEXT_PRIMARY)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
      }
      .alignItems(HorizontalAlign.Start).layoutWeight(1);
      Button() {
        Row({ space: 5 }) {
          if (this.liveDialogOpening || this.liveNavigationBusy) {
            LoadingProgress().width(13).height(13).color(Color.White);
          }
          Text(this.liveNavigationBusy ? $r('app.string.cp_entering') : $r('app.string.cp_enter'))
            .fontSize(12)
            .fontColor(Color.White)
            .fontWeight(FontWeight.Medium);
        }
      }
      .height(32).padding({ left: 12, right: 12 })
      .borderRadius(16)
      .stateStyles({ normal: this.liveEntryNormalStyle, pressed: this.liveEntryPressedStyle })
      .enabled(!this.liveDialogOpening && !this.liveNavigationBusy)
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
        if (this.pinnedPreview !== '') {
          this.pinnedBanner();
        }
        if (this.pinnedPreview !== '' && this.liveShowing()) {
          Divider()
            .strokeWidth(0.5)
            .height(CHAT_TOP_BANNER_DIVIDER_HEIGHT)
            .color($r('app.color.divider'))
            .margin({ left: 14, right: 14 });
        }
        if (this.liveShowing()) {
          this.liveStreamBanner();
        }
      } else if (this.topCardLoadingVisible) {
        this.loadingBanner();
      }
    }
    .width('calc(100% - 24vp)')
    .height(this.containerHeight())
    // 置顶消息条和直播状态条共用这一张卡，它浮在消息列表之上、消息从下面
    // 滚过去——和顶栏胶囊、dock 是同一种角色，所以走同一档 'bar' 玻璃。
    // 自绘玻璃的两半要一起上：半透明底 + backdropBlur（不透明底会把模糊盖死）。
    .backgroundColor(overlayGlassFill('bar', $r('app.color.surface')))
    .backdropBlur(overlayBackdropBlur('bar'))
    .borderRadius(14)
    .margin({ left: 12, right: 12, bottom: 2 })
    // 'bar' 档自带阴影关闭，这条浮卡的阴影保持自己的。
    .shadow({ radius: 5, color: '#12000000', offsetX: 0, offsetY: 1 })
    .clip(true)
    .attributeModifier(materialModifier('bar'))
    .transition(TransitionEffect.OPACITY
      .combine(TransitionEffect.translate({ y: -6 }))
      .animation({
        duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 240),
        curve: Curve.EaseOut
      }));
  }
}
