// Non-interactive hint inside the drop boundary. Uses composer material and
// reduced-animation settings, with no added shadows.
import { COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY } from '../../util/theme';
import { str } from '../../util/strings';
import { NativeGlassHost } from './NativeGlassHost';
import { DropHoverState } from './DropHoverState';
import { chatPlainFill, systemMaterialState } from '../../util/systemMaterialSetting';
import { immersiveMaterialAvailable } from '../../util/overlayMaterial';
import { KEY_POWER_SMOOTH_TRANSITIONS, powerAnimationDuration } from '../../store/AppSettings';

@ComponentV2
export struct DropHoverOverlay {
  @Require @Param state: DropHoverState;
  @Param target: string = '';
  @Param dark: boolean = false;

  // 玻璃画布要的绝对尺寸：先按内容排一次版，量到宽高再回填（与输入栏同一套做法）。
  @Local private cardW: number = 0;
  @Local private cardH: number = 0;

  private glassOn(): boolean {
    return systemMaterialState.chatEnabled && immersiveMaterialAvailable();
  }

  build() {
    if (this.state.visible) {
      // 外层满屏但不是遮罩：只负责把里面那层「框」内缩 12vp，暗色不会溢出到屏幕边缘。
      Stack({ alignContent: Alignment.Center }) {
        Stack({ alignContent: Alignment.Center }) {
          this.dropShade()
          this.hintCard()
        }
        .width('100%')
        .height('100%')
        .padding(12)
      }
      .width('100%')
      .height('100%')
      .hitTestBehavior(HitTestMode.None)
    }
  }

  // 框内：压暗 + 一层很淡的主题色 + 一圈虚线边界，三者都只在框里画。
  @Builder
  dropShade() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .borderRadius(24)
        .backgroundColor(this.dark ? '#6B000000' : '#47000000')
        .opacity(this.state.shown ? 1 : 0)
        .animation({
          duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, this.state.shown ? 280 : 200),
          curve: this.state.shown ? Curve.EaseOut : Curve.EaseIn
        })
      Column()
        .width('100%')
        .height('100%')
        .borderRadius(24)
        .backgroundColor(COLOR_PRIMARY)
        .opacity(this.state.shown ? 0.06 : 0)
        .animation({
          duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, this.state.shown ? 280 : 200),
          curve: this.state.shown ? Curve.EaseOut : Curve.EaseIn
        })
      Column()
        .width('100%')
        .height('100%')
        .borderRadius(24)
        .border({ width: 2, color: COLOR_PRIMARY, style: BorderStyle.Dashed })
        .opacity(this.state.shown ? 1 : 0)
        .animation({
          duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, this.state.shown ? 280 : 200),
          curve: this.state.shown ? Curve.EaseOut : Curve.EaseIn
        })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  hintCard() {
    Stack({ alignContent: Alignment.TopStart }) {
      // 玻璃画布：尺寸等于量出来的卡片尺寸，圆角与卡片一致（26）。
      if (this.glassOn() && this.cardW > 0 && this.cardH > 0) {
        NativeGlassHost({
          surface: 'control', hostWidth: this.cardW, hostHeight: this.cardH, hostRadius: 26, dark: this.dark
        })
      }
      Column() {
        Stack({ alignContent: Alignment.Center }) {
          Circle()
            .width(64)
            .height(64)
            .fill(this.dark ? '#26FFFFFF' : '#14000000')
          SymbolGlyph($r('sys.symbol.paperplane'))
            .fontSize(30)
            .fontColor([COLOR_PRIMARY])
        }
        .width(64)
        .height(64)

        Text(str(this.state.sendMode === null ? 'drop_release_unknown' :
          (this.state.sendMode ? 'drop_release_send' : 'drop_release_draft')))
          .fontSize(20)
          .fontWeight(FontWeight.Medium)
          .fontColor(COLOR_TEXT_PRIMARY)
          .textAlign(TextAlign.Center)
          .margin({ top: 14 })

        if (this.target !== '') {
          Text(str('drop_release_to', this.target))
            .fontSize(14)
            .fontColor(COLOR_TEXT_SECONDARY)
            .textAlign(TextAlign.Center)
            .margin({ top: 6 })
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .padding({ left: 32, right: 32, top: 28, bottom: 26 })
      .width('100%')
      .constraintSize({ maxWidth: 340 })
      // 玻璃还没量到尺寸的那一帧先垫一层近似的玻璃色，避免白字直接压在压暗层上闪一下。
      .backgroundColor(this.glassOn() && this.cardW > 0 && this.cardH > 0
        ? Color.Transparent : chatPlainFill(systemMaterialState.level))
      .borderRadius(26)
      .onAreaChange((_oldArea: Area, newArea: Area): void => {
        const w = Number(newArea.width);
        const h = Number(newArea.height);
        if (w > 0 && Math.abs(w - this.cardW) > 0.5) {
          this.cardW = w;
        }
        if (h > 0 && Math.abs(h - this.cardH) > 0.5) {
          this.cardH = h;
        }
      })
    }
    .width('100%')
    .constraintSize({ maxWidth: 340 })
    // 进场：0.86 → 1、透明 → 实（逐渐放大、从虚到实）；出场反过来（从大到小、从实到虚）。
    .scale({ x: this.state.shown ? 1 : 0.86, y: this.state.shown ? 1 : 0.86 })
    .opacity(this.state.shown ? 1 : 0)
    .animation({
      duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, this.state.shown ? 380 : 240),
      curve: this.state.shown ? Curve.EaseOut : Curve.EaseIn
    })
  }
}
