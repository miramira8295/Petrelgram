import { COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY } from '../../util/theme';
import { KEY_POWER_SMOOTH_TRANSITIONS, powerAnimationDuration } from '../../store/AppSettings';
import { emptyHistoryHint, emptyHistoryIcon, emptyHistoryTitle } from '../../util/emptyHistory';
import { timelineError, timelineLoading } from '../../util/timelineState';
import { str } from '../../util/strings';

// 消息列表的两种"没有内容可看"：中间那张空状态卡（整段历史在同步 / 失败 /
// 确实是空的），和顶上那颗细长的状态胶囊（分页在加载或失败）。
//
// 从 ChatPage 搬出来。两者的判断都在 util（emptyHistory / timelineState，各有
// 单测），这里只负责画，重试回调给页面。

const DANGER: string = '#E64646';

@Component
export struct MessageListStateCard {
  // 'loading' | 'error' | 其余（视作"确实是空的"）
  @Prop loadState: string;
  @Prop loadError: string;
  @Prop threadRootId: number;
  @Prop membershipState: string;
  @Prop isChannel: boolean;
  @Prop isGroup: boolean;
  @Prop screenW: number;

  onRetry: () => void = (): void => {};

  @Styles
  retryNormalStyle() {
    .backgroundColor(COLOR_PRIMARY)
    .opacity(1)
    .scale({ x: 1, y: 1 })
  }

  @Styles
  retryPressedStyle() {
    .backgroundColor('#287BC8')
    .opacity(0.84)
    .scale({ x: 0.92, y: 0.92 })
  }

  @Builder
  badge(fill: ResourceColor) {
    Circle({ width: 56, height: 56 }).fill(fill);
  }

  build() {
    Column({ space: 9 }) {
      if (this.loadState === 'loading') {
        Stack({ alignContent: Alignment.Center }) {
          this.badge($r('app.color.surface_alt'));
          LoadingProgress()
            .width(30).height(30).color(COLOR_PRIMARY);
        }.width(56).height(56);
        Text($r('app.string.cp_syncing_messages'))
          .fontSize(16).fontColor(COLOR_TEXT_PRIMARY).fontWeight(FontWeight.Medium);
        Text($r('app.string.cp_history_soon'))
          .fontSize(13).fontColor(COLOR_TEXT_SECONDARY);
      } else if (this.loadState === 'error') {
        Stack({ alignContent: Alignment.Center }) {
          this.badge('#12E64646');
          SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
            .fontSize(30).fontColor([DANGER]);
        }.width(56).height(56);
        Text($r('app.string.cp_messages_failed'))
          .fontSize(16).fontColor(COLOR_TEXT_PRIMARY).fontWeight(FontWeight.Medium);
        Text(this.loadError !== '' ? this.loadError : $r('app.string.cp_check_network'))
          .fontSize(13).fontColor(COLOR_TEXT_SECONDARY)
          .textAlign(TextAlign.Center).maxLines(2);
        Row({ space: 6 }) {
          SymbolGlyph($r('sys.symbol.arrow_clockwise')).fontSize(14).fontColor([Color.White]);
          Text($r('app.string.settings_retry')).fontSize(13)
            .fontColor(Color.White).fontWeight(FontWeight.Medium);
        }
        .height(34).padding({ left: 14, right: 14 })
        .borderRadius(17)
        .stateStyles({ normal: this.retryNormalStyle, pressed: this.retryPressedStyle })
        .animation({
          duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 120),
          curve: Curve.EaseOut
        })
        .onClick((): void => { this.onRetry(); });
      } else {
        Stack({ alignContent: Alignment.Center }) {
          this.badge($r('app.color.surface_alt'));
          SymbolGlyph($r(emptyHistoryIcon(this.threadRootId, this.membershipState)))
            .fontSize(28).fontColor([COLOR_PRIMARY]);
        }.width(56).height(56);
        Text(emptyHistoryTitle(this.threadRootId, this.membershipState,
          this.isChannel, this.isGroup))
          .fontSize(16).fontColor(COLOR_TEXT_PRIMARY).fontWeight(FontWeight.Medium);
        Text(emptyHistoryHint(this.threadRootId, this.membershipState,
          this.isChannel, this.isGroup))
          .fontSize(13).fontColor(COLOR_TEXT_SECONDARY).textAlign(TextAlign.Center);
      }
    }
    .constraintSize({ minWidth: 210, maxWidth: this.screenW - 48 })
    .padding({ left: 24, right: 24, top: 22, bottom: 22 })
    .backgroundColor($r('app.color.surface'))
    .border({ width: 0.5, color: $r('app.color.divider') })
    .borderRadius(20)
    .shadow({ radius: 8, color: '#18000000', offsetX: 0, offsetY: 3 })
    .alignItems(HorizontalAlign.Center)
    .transition(TransitionEffect.OPACITY
      .combine(TransitionEffect.translate({ y: 8 }))
      .combine(TransitionEffect.scale({ x: 0.97, y: 0.97 }))
      .animation({
        duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 200),
        curve: Curve.EaseOut
      }));
  }
}

@Component
export struct TimelineStatePill {
  // util/timelineState 的档位；调用方保证非空才挂载本组件。
  @Prop mode: string;
  @Prop label: string;
  // 顶上浮着日期条时要往下让一让，否则两者叠在一起。
  @Prop floatDateShown: boolean;

  onRetry: () => void = (): void => {};

  @Styles
  pillNormalStyle() {
    .opacity(1)
    .scale({ x: 1, y: 1 })
  }

  @Styles
  pillPressedStyle() {
    .opacity(0.76)
    .scale({ x: 0.97, y: 0.97 })
  }

  build() {
    Column() {
      Row({ space: 7 }) {
        if (timelineLoading(this.mode)) {
          LoadingProgress().width(15).height(15).color(COLOR_PRIMARY);
        } else {
          SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
            .fontSize(15).fontColor([DANGER]);
        }
        Text(this.label)
          .fontSize(12.5).fontColor(COLOR_TEXT_PRIMARY).fontWeight(FontWeight.Medium);
        if (timelineError(this.mode)) {
          Divider().vertical(true).height(14).color($r('app.color.divider'));
          Text($r('app.string.settings_retry')).fontSize(12.5)
            .fontColor(COLOR_PRIMARY).fontWeight(FontWeight.Medium);
        }
      }
      .height(32)
      .padding({ left: 11, right: 11 })
      .backgroundColor($r('app.color.surface'))
      .border({ width: 0.5, color: $r('app.color.divider') })
      .borderRadius(16)
      .shadow({ radius: 5, color: '#1A000000', offsetX: 0, offsetY: 2 })
      .stateStyles({ normal: this.pillNormalStyle, pressed: this.pillPressedStyle })
      .animation({
        duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 110),
        curve: Curve.EaseOut
      })
      .onClick((): void => { this.onRetry(); })
      .accessibilityText(timelineError(this.mode)
        ? str('cp_timeline_retry_a11y', this.label) : this.label);
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
    .padding({ top: this.floatDateShown ? 42 : 8 })
    .transition(TransitionEffect.OPACITY
      .combine(TransitionEffect.translate({ y: -6 }))
      .animation({
        duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 180),
        curve: Curve.EaseOut
      }));
  }
}
