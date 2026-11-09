import { COLOR_PRIMARY } from '../../util/theme';
import { KEY_POWER_SMOOTH_TRANSITIONS, powerAnimationDuration } from '../../store/AppSettings';

// 输入区最右那颗圆钮：草稿为空时是麦克风，一有字就换成纸飞机。
//
// 从 ChatPage 搬出来。两颗按钮除了图标、禁用条件和入场转场之外完全一样，
// 原来是两段几乎逐行重复的代码；这里合成一个 shell，差异用参数表达。
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

  onRecord: () => void = (): void => {};
  onSend: () => void = (): void => {};
  // 长按发送键：定时发送 / 静默发送。
  onSendOptions: () => void = (): void => {};

  @Styles
  primaryNormalStyle() {
    .backgroundColor(COLOR_PRIMARY)
    .opacity(1)
    .scale({ x: 1, y: 1 })
  }

  @Styles
  primaryPressedStyle() {
    .backgroundColor('#287BC8')
    .opacity(0.84)
    .scale({ x: 0.92, y: 0.92 })
  }

  build() {
    // 图标互换：淡出的那颗缩小消失，进来的那颗放大出现。
    Stack() {
      if (!this.hasDraft) {
        Button() {
          if (this.recordingStarting) {
            LoadingProgress().width(18).height(18).color(Color.White);
          } else {
            SymbolGlyph($r('sys.symbol.mic')).fontSize(20).fontColor([Color.White]);
          }
        }
        .width(40).height(40).borderRadius(20)
        .stateStyles({ normal: this.primaryNormalStyle, pressed: this.primaryPressedStyle })
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
            LoadingProgress().width(18).height(18).color(Color.White);
          } else {
            // 草稿从空变非空时这颗才挂载，isActive=true 让它出现即弹一下，
            // 和外层已有的 opacity+scale 转场叠在一起。
            SymbolGlyph($r('sys.symbol.paperplane')).fontSize(20).fontColor([Color.White])
              .symbolEffect(new BounceSymbolEffect(EffectScope.WHOLE, EffectDirection.UP), true);
          }
        }
        .width(40).height(40).borderRadius(20)
        .stateStyles({ normal: this.primaryNormalStyle, pressed: this.primaryPressedStyle })
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
    }.width(40).height(40);
  }
}
