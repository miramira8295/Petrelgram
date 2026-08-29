import { KB_TEXT, KeyboardBtn } from '../../store/ReplyKeyboard';
import { COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_ICON_SECONDARY, COLOR_TEXT_SECONDARY, botButtonBg } from '../../util/theme';
import { KEY_POWER_SMOOTH_TRANSITIONS, powerAnimationDuration } from '../../store/AppSettings';

// 机器人自定义键盘：消息随附的一排排按钮。
//
// 从 ChatPage 搬出来。一次只允许一个按钮在途——sendingKey 非空时整块禁用，
// 正在发的那一颗显示转圈。键是"行号_列号_文案"，因为同一块键盘里文案可以重复。
//
// 点击后要发消息、要碰 store，所以只回调不执行。

@Component
export struct ReplyKeyboardPanel {
  @Prop rows: KeyboardBtn[][];
  // 正在发送的那颗按钮的键；空串表示空闲。
  @Prop sendingKey: string;
  // 机器人要求收缩键盘高度。
  @Prop resize: boolean;
  // 底部让出的高度，由页面按键盘/抽屉状态算好传进来。
  @Prop bottomGap: number;
  // 入场动画时长，由页面按省电分组算好传进来。
  @Prop enterDuration: number;

  onTap: (btn: KeyboardBtn, key: string) => void = (): void => {};

  @Styles
  buttonNormalStyle() {
    .opacity(1)
    .scale({ x: 1, y: 1 })
  }

  @Styles
  buttonPressedStyle() {
    .opacity(0.72)
    .scale({ x: 0.96, y: 0.9 })
  }

  build() {
    Scroll() {
      Column({ space: 6 }) {
        ForEach(this.rows, (row: KeyboardBtn[], rowIdx: number) => {
          Row({ space: 6 }) {
            ForEach(row, (btn: KeyboardBtn, btnIdx: number) => {
              Row({ space: 6 }) {
                if (this.sendingKey === `${rowIdx}_${btnIdx}_${btn.text}`) {
                  LoadingProgress()
                    .width(16).height(16)
                    .color(btn.style !== '' ? Color.White : COLOR_PRIMARY);
                }
                Text(btn.text)
                  .fontSize(14)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(btn.style !== '' ? Color.White : COLOR_TEXT_PRIMARY)
                  .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
                  .textAlign(TextAlign.Center);
                // 非纯文本按钮（要位置、要联系人、要开网页…）带一个提示角标：
                // 点下去会有额外后果，先给个信号。
                if (btn.type !== '' && btn.type !== KB_TEXT) {
                  SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
                    .fontSize(12)
                    .fontColor([btn.style !== '' ? Color.White : COLOR_ICON_SECONDARY]);
                }
              }
              .layoutWeight(1)
              .constraintSize({ minHeight: 42 })
              .padding({ left: 8, right: 8, top: 7, bottom: 7 })
              .backgroundColor(botButtonBg(btn.style, $r('app.color.surface')))
              .borderRadius(10)
              .justifyContent(FlexAlign.Center)
              .stateStyles({ normal: this.buttonNormalStyle, pressed: this.buttonPressedStyle })
              .animation({
                duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 110),
                curve: Curve.EaseOut
              })
              // 有一颗在途时整块禁用：这些按钮多半是"确认/取消"这类，
              // 连点两下的后果不是重复发送那么简单。
              .enabled(this.sendingKey === '')
              .onClick((): void => {
                this.onTap(btn, `${rowIdx}_${btnIdx}_${btn.text}`);
              });
            }, (btn: KeyboardBtn, btnIdx: number) => `kb_${rowIdx}_${btnIdx}_${btn.text}`);
          }.width('100%');
        }, (_row: KeyboardBtn[], rowIdx: number) => `kbrow_${rowIdx}`);
      }
      .width('100%');
    }
    .width('calc(100% - 16vp)')
    .constraintSize({ maxHeight: this.resize ? 210 : 280 })
    .scrollBar(BarState.Auto)
    .padding(8)
    .margin({ left: 8, right: 8, bottom: this.bottomGap })
    .backgroundColor($r('app.color.surface_alt'))
    .borderRadius(16)
    .shadow({ radius: 6, color: '#16000000', offsetX: 0, offsetY: 2 })
    .transition(TransitionEffect.OPACITY
      .combine(TransitionEffect.translate({ y: 10 }))
      .animation({ duration: this.enterDuration, curve: Curve.EaseOut }));
  }
}
