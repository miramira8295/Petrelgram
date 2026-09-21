import { COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_ON_PRIMARY
} from '../../util/theme';
import { KEY_POWER_SMOOTH_TRANSITIONS, powerAnimationDuration } from '../../store/AppSettings';
import {
  plainBackdropBlur, plainGlassFill, MATERIAL_EPOCH
} from '../../util/overlayMaterial';
import { hdsVisualEffect } from '../../util/hdsPointLight';
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
  // 箭头的颜色由页面按**壁纸**算好传进来（chatChrome）：这颗浮在壁纸上，
  // 跟深浅色模式取色会在"浅色模式 + 黑壁纸"下变成黑箭头压黑底。
  @Prop iconColor: ResourceColor;

  onTap: () => void = (): void => {};

  // 【底色不在这里，在属性链上】（2026-09-21）
  //
  // 原来 normal 档里写着 `.backgroundColor(plainGlassFill($r('app.color.surface')))`。
  // 搬到属性链是为了和全仓库另外十几个自绘玻璃面（输入栏、顶栏、搜索栏、话题条、
  // 底部抽屉、会员条）写法一致——它们都是在 build() 里直接链式调。
  //
  // ⚠️ **但这不是「实心白」的原因**。我一度据此推断"@Styles 求值太早、拿到了
  // materialOff=true 时的实色"，真机探针把它推翻了：
  //   [Glass] materialOff=false available=true blur(card)=16 blur(control)=16
  // 底色一直拿的是 dock_glass 半透明。真凶是下面 visualEffect 那一档的
  // pressShadow，见那里的说明。这一段留着是因为写法本身更好，不是因为它治了什么。
  @Styles
  fabNormalStyle() {
    .opacity(1)
    .scale({ x: 1, y: 1 })
  }

  // 按压不再换底色：换了就等于在 stateStyles 里又写一次 backgroundColor，
  // 与属性链上那条打架（后写的赢），正是上面要避开的那件事。形变 + 透明度
  // 已经够，材质可用时它那套按压形变还会再叠上来。
  @Styles
  fabPressedStyle() {
    .opacity(0.84)
    .scale({ x: 0.92, y: 0.92 })
  }

  build() {
    Stack() {
      Button({ type: ButtonType.Circle }) {
        if (this.busy) {
          LoadingProgress().width(20).height(20).color(COLOR_PRIMARY);
        } else {
          // 只在离开底部时挂载，出现即弹一下提示"这里可以回去"。
          SymbolGlyph($r('sys.symbol.chevron_down')).fontSize(22).fontColor([this.iconColor])
            .symbolEffect(new BounceSymbolEffect(EffectScope.WHOLE, EffectDirection.DOWN), true);
        }
      }
      .width(46).height(46)
      .borderRadius(23)
      // 和输入栏那条逐属性一致：plainGlassFill + plainBackdropBlur + hdsVisualEffect。
      // **必须写在属性链上**，不能挪回 stateStyles（理由见上面那段）。
      .backgroundColor(plainGlassFill($r('app.color.surface')))
      .stateStyles({ normal: this.fabNormalStyle, pressed: this.fabPressedStyle })
      .animation({
        duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 130),
        curve: Curve.EaseOut
      })
      // 玻璃自绘，和输入栏里那颗同样 46×46 的圆控件逐属性一致（见
      // ChatComposerInput 的附件键）：组件级 systemMaterial 已被系统收回，
      // overlayGlassFill('card') 在材质"可用"的设备上返回**透明**、把观感全交给
      // materialModifier，而那一层在这颗圆上什么都不画——结果就是一个只剩描边的
      // 空心圈，浮在自绘玻璃的输入栏上面格格不入（用户 2026-09-18 截图）。
      // 描边也一并去掉：输入栏那颗控件没有，而 divider 压在深色照片上就是一道白圈。
      .backdropBlur(plainBackdropBlur('control'))
      // 【这里必须是 'card'，不能是 'control'】（2026-09-21 真机验证，用户截图
      // 「底栏磨砂半透明，圆圈实心白」）
      //
      // 两档的**唯一**差别是 pressShadow(BLEND_GRADIENT)——usesInteraction 只对
      // control / navigationMenu 为真。而那层按压阴影画在这颗 46 的小圆上就是
      // 一块不透明的白，把自绘玻璃整个盖住。
      //
      // 【怎么定的】真机探针一行读数就把另外两条嫌疑排掉了：
      //   [Glass] materialOff=false available=true blur(card)=16 blur(control)=16
      // 底色拿到的是 dock_glass（#8CFFFFFF 半透明）不是实心白，两档模糊也一样。
      // 换成 'card' 之后用户确认「变了，已经正常了」。
      //
      // 代价：没有材质那套按压阴影了。按压反馈由下面 stateStyles 的形变 +
      // 透明度承担——也正因为 'card' 不叠材质形变，这两者不会打架。
      //
      // ⚠️ 输入栏左边那颗回形针（ChatComposerInput 的附件键）仍然是 'control'，
      // 同样的白。要不要一起改由用户定，别顺手动。
      .visualEffect(hdsVisualEffect('card'))
      // 阴影保留：那颗附件键坐在已经是玻璃的输入栏里，这颗是浮在照片上的，
      // 没有一点投影在浅色图上会糊掉。
      .shadow({ radius: 7, color: '#26000000', offsetX: 0, offsetY: 2 })
      .enabled(!this.busy)
      .accessibilityText(this.busy
        ? $r('app.string.cp_returning_latest') : $r('app.string.cp_return_latest'))
      .onClick((): void => { this.onTap(); })
      .position({ x: 6, y: 10 });
      if (this.unreadCount > 0) {
        Row() {
          Text(unreadBadgeText(this.unreadCount))
            .fontSize(12).fontColor(COLOR_ON_PRIMARY).fontWeight(FontWeight.Medium)
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
