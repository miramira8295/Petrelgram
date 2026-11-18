import { KEY_POWER_SMOOTH_TRANSITIONS, powerAnimationDuration } from '../../store/AppSettings';

// 输入区最右那颗圆钮：草稿为空时是麦克风，一有字就换成纸飞机。
//
// 外观口径（2026-11-18 用户指定）：**与输入栏左边的回形针附件键一致** —— 自己
// 不画底色，只出图标；玻璃底由外层 ChatComposerInput 的 NativeGlassHost/自绘
// 兜底提供。原来这里是实心主题色圆钮（白图标），和附件键放一起明显不是一套。
//
// 送出去的转场比麦克风多一个 -45° 的回正：纸飞机是"甩出去"的手感，麦克风
// 只是淡入。这处不对称是原样保留的。

const SWAP_MS: number = 200;
const PRESS_MS: number = 120;

@Component
export struct ComposerSendButton {
  // 草稿是不是空的——决定这会儿是麦克风还是纸飞机。
  @Prop hasDraft: boolean;
  // 录音正在启动（申请权限、开采集），此时麦克风转圈且不可点。
  @Prop recordingStarting: boolean;
  // 发送在途，此时纸飞机转圈且不可点。
  @Prop sending: boolean;
  // 麦克风/转圈的图标色，跟附件键同一个色。
  @Prop iconColor: ResourceColor = Color.Transparent;
  // 纸飞机会主动作，用主题色。
  @Prop accentColor: ResourceColor = Color.Transparent;

  onRecord: () => void = (): void => {};
  onSend: () => void = (): void => {};
  // 长按发送键：定时发送 / 静默发送。
  onSendOptions: () => void = (): void => {};

  @Styles
  iconNormalStyle() {
    .backgroundColor(Color.Transparent)
    .opacity(1)
    .scale({ x: 1, y: 1 })
  }

  @Styles
  iconPressedStyle() {
    .backgroundColor(Color.Transparent)
    .opacity(0.72)
    .scale({ x: 0.9, y: 0.9 })
  }

  build() {
    // 图标互换：淡出的那颗缩小消失，进来的那颗放大出现。
    Stack() {
      if (!this.hasDraft) {
        Button() {
          if (this.recordingStarting) {
            LoadingProgress().width(20).height(20).color(this.iconColor);
          } else {
            SymbolGlyph($r('sys.symbol.mic')).fontSize(22).fontColor([this.iconColor]);
          }
        }
        .width(46).height(46).borderRadius(23)
        .backgroundColor(Color.Transparent)
        .stateStyles({ normal: this.iconNormalStyle, pressed: this.iconPressedStyle })
        .animation({
          duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, PRESS_MS),
          curve: Curve.EaseOut
        })
        .enabled(!this.recordingStarting)
        .transition(TransitionEffect.OPACITY
          .combine(TransitionEffect.scale({ x: 0.3, y: 0.3 }))
          .animation({
            duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, SWAP_MS),
            curve: Curve.EaseOut
          }))
        .onClick((): void => { this.onRecord(); });
      } else {
        Button() {
          if (this.sending) {
            LoadingProgress().width(20).height(20).color(this.accentColor);
          } else {
            // 草稿从空变非空时这颗才挂载，isActive=true 让它出现即弹一下，
            // 和外层已有的 opacity+scale 转场叠在一起。
            SymbolGlyph($r('sys.symbol.paperplane')).fontSize(22).fontColor([this.accentColor])
              .symbolEffect(new BounceSymbolEffect(EffectScope.WHOLE, EffectDirection.UP), true);
          }
        }
        .width(46).height(46).borderRadius(23)
        .backgroundColor(Color.Transparent)
        .stateStyles({ normal: this.iconNormalStyle, pressed: this.iconPressedStyle })
        .animation({
          duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, PRESS_MS),
          curve: Curve.EaseOut
        })
        .enabled(!this.sending)
        .transition(TransitionEffect.OPACITY
          .combine(TransitionEffect.scale({ x: 0.3, y: 0.3 }))
          .combine(TransitionEffect.rotate({ angle: -45 }))
          .animation({
            duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, SWAP_MS),
            curve: Curve.EaseOut
          }))
        .onClick((): void => { this.onSend(); })
        .gesture(LongPressGesture().onAction((): void => { this.onSendOptions(); }));
      }
    }.width(46).height(46);
  }
}
