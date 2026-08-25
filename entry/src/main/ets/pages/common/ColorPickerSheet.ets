// 取色器：SV 方块 + 色相条 + hex 输入 + 预设。挂在 bindSheet 里用。
// 方块不用 Canvas——底色是纯色相，上面叠「白→透明」「透明→黑」两层渐变，
// 三层 Column 就是完整的 HSV 平面，色相变了只改底色那一层。
import { hexToHsv, hsvToHex, isValidHex } from '../../util/colorMath';
import { COLOR_PRIMARY, COLOR_SURFACE, COLOR_TEXT_SECONDARY } from '../../util/theme';

// 官方 7 个名字色 + 默认蓝 + 深浅两套气泡/页面底色。
export const PRESET_COLORS: string[] = [
  '#CC5049', '#D67722', '#955CDB', '#40A920', '#309EBA', '#368AD1', '#C7508B',
  '#3390EC', '#17212B', '#2B5278', '#E1FFC7', '#FFFFFF'
];
const SV_HEIGHT: number = 180;
const HUE_HEIGHT: number = 24;
const KNOB: number = 18;
const HUE_STOPS: [ResourceColor, number][] = [
  ['#FF0000', 0], ['#FFFF00', 1 / 6], ['#00FF00', 2 / 6], ['#00FFFF', 3 / 6],
  ['#0000FF', 4 / 6], ['#FF00FF', 5 / 6], ['#FF0000', 1]
];
const FALLBACK_HEX: string = '#3390EC';

@Component
export struct ColorPickerSheet {
  @Prop initialHex: string = FALLBACK_HEX;
  onPick: (hex: string) => void = (): void => {};
  onClose: () => void = (): void => {};
  @State hue: number = 0;
  @State sat: number = 1;
  @State val: number = 1;
  @State hexText: string = '';
  @State hexInvalid: boolean = false;
  @State svW: number = 0;

  aboutToAppear(): void {
    this.setFromHex(isValidHex(this.initialHex) ? this.initialHex : FALLBACK_HEX);
  }

  private setFromHex(hex: string): void {
    const hsv = hexToHsv(hex);
    this.hue = hsv[0];
    this.sat = hsv[1];
    this.val = hsv[2];
    this.hexText = hex.toUpperCase();
    this.hexInvalid = false;
  }

  private current(): string {
    return hsvToHex(this.hue, this.sat, this.val);
  }

  private pureHue(): string {
    return hsvToHex(this.hue, 1, 1);
  }

  private pickSv(x: number, y: number): void {
    if (this.svW <= 0) {
      return;
    }
    this.sat = Math.max(0, Math.min(1, x / this.svW));
    this.val = 1 - Math.max(0, Math.min(1, y / SV_HEIGHT));
    this.hexText = this.current();
    this.hexInvalid = false;
  }

  private pickHue(x: number): void {
    if (this.svW <= 0) {
      return;
    }
    this.hue = Math.max(0, Math.min(359.9, x / this.svW * 360));
    this.hexText = this.current();
    this.hexInvalid = false;
  }

  private onHexInput(v: string): void {
    const t = v.trim();
    this.hexText = t;
    if (isValidHex(t)) {
      this.setFromHex(t);
    } else {
      this.hexInvalid = t !== '';
    }
  }

  build() {
    Column({ space: 14 }) {
      Row({ space: 12 }) {
        Column().width(44).height(44).borderRadius(10).backgroundColor(this.current())
          .border({ width: 1, color: '#22000000' });
        TextInput({ text: this.hexText, placeholder: $r('app.string.color_picker_hex_hint') })
          .layoutWeight(1).height(40).fontSize(15)
          .border({ width: this.hexInvalid ? 1.5 : 0, color: '#E53935' })
          .onChange((v: string): void => this.onHexInput(v));
        Button($r('app.string.color_picker_done')).height(40).backgroundColor(COLOR_PRIMARY)
          .onClick((): void => {
            this.onPick(this.current());
            this.onClose();
          });
      }.width('100%');

      Stack({ alignContent: Alignment.TopStart }) {
        Column().width('100%').height(SV_HEIGHT).backgroundColor(this.pureHue());
        Column().width('100%').height(SV_HEIGHT)
          .linearGradient({ angle: 90, colors: [['#FFFFFFFF', 0], ['#00FFFFFF', 1]] });
        Column().width('100%').height(SV_HEIGHT)
          .linearGradient({ angle: 180, colors: [['#00000000', 0], ['#FF000000', 1]] });
        Column().width(KNOB).height(KNOB).borderRadius(KNOB / 2)
          .border({ width: 2, color: Color.White }).backgroundColor(this.current())
          .shadow({ radius: 3, color: '#55000000' })
          .position({ x: this.sat * this.svW - KNOB / 2, y: (1 - this.val) * SV_HEIGHT - KNOB / 2 });
      }
      .width('100%').height(SV_HEIGHT).borderRadius(10).clip(true)
      .onAreaChange((_o: Area, n: Area): void => {
        this.svW = Number(n.width);
      })
      .onTouch((e: TouchEvent): void => {
        if (e.touches.length > 0) {
          this.pickSv(e.touches[0].x, e.touches[0].y);
        }
      });

      Stack({ alignContent: Alignment.TopStart }) {
        Column().width('100%').height(HUE_HEIGHT).borderRadius(HUE_HEIGHT / 2)
          .linearGradient({ angle: 90, colors: HUE_STOPS });
        Column().width(HUE_HEIGHT + 4).height(HUE_HEIGHT + 4).borderRadius((HUE_HEIGHT + 4) / 2)
          .border({ width: 2, color: Color.White }).backgroundColor(this.pureHue())
          .shadow({ radius: 3, color: '#55000000' })
          .position({ x: this.hue / 360 * this.svW - (HUE_HEIGHT + 4) / 2, y: -2 });
      }
      .width('100%').height(HUE_HEIGHT)
      .onTouch((e: TouchEvent): void => {
        if (e.touches.length > 0) {
          this.pickHue(e.touches[0].x);
        }
      });

      Text($r('app.string.color_picker_presets')).fontSize(12).fontColor(COLOR_TEXT_SECONDARY)
        .width('100%');
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(PRESET_COLORS, (hex: string) => {
          Column().width(32).height(32).borderRadius(16).backgroundColor(hex)
            .border({
              width: this.current() === hex ? 2 : 1,
              color: this.current() === hex ? COLOR_PRIMARY : '#22000000'
            })
            .margin(4)
            .onClick((): void => this.setFromHex(hex));
        }, (hex: string): string => hex);
      }
    }
    .width('100%').padding({ left: 16, right: 16, top: 8, bottom: 24 })
    .backgroundColor(COLOR_SURFACE);
  }
}
