import { COLOR_PRIMARY, COLOR_TEXT_PRIMARY } from '../../util/theme';
import { KEY_POWER_SMOOTH_TRANSITIONS, powerAnimationDuration } from '../../store/AppSettings';
import {
  overlayBackdropBlur, overlayGlassFill, overlayMaterial, MATERIAL_EPOCH
} from '../../util/overlayMaterial';
import {
  BADGE_HEIGHT, unreadBadgeOffsetX, unreadBadgeText, unreadBadgeWidth
} from '../../util/unreadBadge';
import { plural } from '../../util/strings';

// 右下角的「↓」：回到最新，或者退回引用链上的上一站。
//
// 从 ChatPage 搬出来。它只显示，不判断——"该不该出现"和"点了去哪儿"都由
// util/readingReturn 的三级返回决定，页面算好后一个回调传进来。
//
// 角标的宽度与落点在 util/unreadBadge（有单测）：两者必须一起变，否则数字
// 一多角标就往右溢出。

@Component
export struct ScrollFab {
  // 材质档位（厚度/光感）改变时重绘。overlayMaterial 是 util，订阅不了
  // AppStorage，只能由调用方订阅，同 LANGUAGE_EPOCH 的做法。
  @StorageProp(MATERIAL_EPOCH) private materialEpoch: number = 0;
  // 未读数，0 表示不挂角标。
  @Prop unreadCount: number;
  // 正在滚回底部：转圈并禁用，避免连点排队。
  @Prop busy: boolean;

  onTap: () => void = (): void => {};

  @Styles
  fabNormalStyle() {
    .backgroundColor(overlayGlassFill('card', $r('app.color.surface')))
    .opacity(1)
    .scale({ x: 1, y: 1 })
  }

  @Styles
  fabPressedStyle() {
    .backgroundColor($r('app.color.press_overlay'))
    .opacity(0.84)
    .scale({ x: 0.92, y: 0.92 })
  }

  build() {
    Stack() {
      Button() {
        if (this.busy) {
          LoadingProgress().width(20).height(20).color(COLOR_PRIMARY);
        } else {
          // 只在离开底部时挂载，出现即弹一下提示"这里可以回去"。
          SymbolGlyph($r('sys.symbol.chevron_down')).fontSize(22).fontColor([COLOR_TEXT_PRIMARY])
            .symbolEffect(new BounceSymbolEffect(EffectScope.WHOLE, EffectDirection.DOWN), true);
        }
      }
      .width(46).height(46).borderRadius(23)
      .stateStyles({ normal: this.fabNormalStyle, pressed: this.fabPressedStyle })
      .animation({
        duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 130),
        curve: Curve.EaseOut
      })
      .backdropBlur(overlayBackdropBlur('card'))
      .border({ width: 0.7, color: $r('app.color.divider') })
      .systemMaterial(overlayMaterial('card'))
      .shadow({ radius: 7, color: '#26000000', offsetX: 0, offsetY: 2 })
      .enabled(!this.busy)
      .accessibilityText(this.busy
        ? $r('app.string.cp_returning_latest') : $r('app.string.cp_return_latest'))
      .onClick((): void => { this.onTap(); })
      .position({ x: 6, y: 10 });
      if (this.unreadCount > 0) {
        Row() {
          Text(unreadBadgeText(this.unreadCount))
            .fontSize(12).fontColor(Color.White).fontWeight(FontWeight.Medium)
            .maxLines(1).textAlign(TextAlign.Center);
        }
        .width(unreadBadgeWidth(this.unreadCount)).height(BADGE_HEIGHT)
        .justifyContent(FlexAlign.Center).alignItems(VerticalAlign.Center)
        .backgroundColor(COLOR_PRIMARY).borderRadius(11)
        .border({ width: 1.5, color: $r('app.color.surface') })
        .shadow({ radius: 3, color: '#24000000', offsetX: 0, offsetY: 1 })
        .position({ x: unreadBadgeOffsetX(this.unreadCount), y: 0 })
        .animation({
          duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 140),
          curve: Curve.EaseOut
        })
        .transition(TransitionEffect.OPACITY
          .combine(TransitionEffect.scale({ x: 0.72, y: 0.72 }))
          .animation({
            duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 160),
            curve: Curve.EaseOut
          }))
        .enabled(!this.busy)
        .onClick((): void => { this.onTap(); })
        .accessibilityText(plural('cp_unread_a11y', this.unreadCount, this.unreadCount));
      }
    }
    .width(52).height(56)
    .transition(TransitionEffect.OPACITY
      .combine(TransitionEffect.scale({ x: 0.72, y: 0.72 }))
      .combine(TransitionEffect.translate({ y: 10 }))
      .animation({
        duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 220),
        curve: Curve.EaseOut
      }));
  }
}
