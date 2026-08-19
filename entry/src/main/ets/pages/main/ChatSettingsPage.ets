import { router } from '@kit.ArkUI';
import {
  KEY_TEXT_SIZE, KEY_BUBBLE_RADIUS, KEY_THREE_LINES, KEY_NIGHT_MODE, KEY_REDUCE_ANIM, KEY_SEND_BY_ENTER,
  KEY_POWER_SMOOTH_TRANSITIONS, KEY_IN_APP_BROWSER,
  TEXT_SIZE_MIN, TEXT_SIZE_MAX, RADIUS_MIN, RADIUS_MAX,
  NIGHT_SYSTEM, NIGHT_DARK, NIGHT_LIGHT,
  powerAnimationDuration, setNumber, setBoolean, setNightMode
} from '../../store/AppSettings';
import {
  COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY, COLOR_BUBBLE_IN, COLOR_BUBBLE_OUT
} from '../../util/theme';
import { str } from '../../util/strings';
import { LANGUAGE_EPOCH } from '../../util/appLanguage';

const CARD_BG: ResourceColor = $r('app.color.surface');
const CARD_RADIUS: number = 14;

interface NightOption {
  label: string;
  value: string;
}

const NIGHT_OPTIONS: NightOption[] = [
  { label: str('night_system'), value: NIGHT_SYSTEM },
  { label: str('night_always_on'), value: NIGHT_DARK },
  { label: str('night_always_off'), value: NIGHT_LIGHT }
];

// 聊天设置. Deliberately limited to settings the app actually honours — the
// official page also offers wallpapers, colour themes and app icons, which need
// capabilities we don't have yet, and a switch that changes nothing is worse
// than no switch at all.
@Entry
@Component
struct ChatSettingsPage {
  @StorageProp(LANGUAGE_EPOCH) langEpoch: number = 0;
  @StorageProp('topSafeHeight') topSafe: number = 0;
  @StorageProp('bottomSafeHeight') bottomSafe: number = 0;
  @StorageLink(KEY_TEXT_SIZE) textSize: number = 16;
  @StorageLink(KEY_BUBBLE_RADIUS) bubbleRadius: number = 17;
  @StorageLink(KEY_THREE_LINES) threeLines: boolean = false;
  @StorageLink(KEY_NIGHT_MODE) nightMode: string = NIGHT_SYSTEM;
  @StorageLink(KEY_REDUCE_ANIM) reduceAnim: boolean = false;
  @StorageLink(KEY_SEND_BY_ENTER) sendByEnter: boolean = false;
  @State leavingPage: boolean = false;
  private leaveTimer: number = -1;

  aboutToDisappear(): void {
    if (this.leaveTimer !== -1) {
      clearTimeout(this.leaveTimer);
      this.leaveTimer = -1;
    }
    this.leavingPage = false;
  }

  private leavePage(): void {
    if (this.leavingPage) {
      return;
    }
    this.leavingPage = true;
    this.leaveTimer = setTimeout((): void => {
      this.leaveTimer = -1;
      this.leavingPage = false;
    }, 500);
    router.back();
  }

  private numberValue(key: string): number {
    return key === KEY_TEXT_SIZE ? this.textSize : this.bubbleRadius;
  }

  private booleanValue(key: string): boolean {
    if (key === KEY_REDUCE_ANIM) { return this.reduceAnim; }
    return this.sendByEnter;
  }

  @Styles
  actionNormalStyle() {
    .backgroundColor(Color.Transparent)
    .opacity(1)
    .scale({ x: 1, y: 1 })
  }

  @Styles
  actionPressedStyle() {
    .backgroundColor($r('app.color.surface_alt'))
    .opacity(0.72)
    .scale({ x: 0.92, y: 0.92 })
  }

  @Styles
  optionNormalStyle() {
    .backgroundColor(Color.Transparent)
    .opacity(1)
    .scale({ x: 1, y: 1 })
  }

  @Styles
  optionPressedStyle() {
    .backgroundColor($r('app.color.surface_alt'))
    .opacity(0.75)
    .scale({ x: 0.98, y: 0.98 })
  }

  @Builder
  header() {
    Row({ space: 8 }) {
      Row() {
        SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(25).fontColor([COLOR_TEXT_PRIMARY]);
      }
      .width(44).height(44).borderRadius(22)
      .justifyContent(FlexAlign.Center)
      .stateStyles({
        normal: this.actionNormalStyle,
        pressed: this.actionPressedStyle
      })
      .enabled(!this.leavingPage)
      .accessibilityText($r('app.string.back_to_settings'))
      .onClick((): void => { this.leavePage(); });
      Text($r('app.string.settings_chat')).fontSize(22).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT_PRIMARY)
        .layoutWeight(1);
    }
    .width('100%').height(56).padding({ left: 8, right: 16 })
    .alignItems(VerticalAlign.Center);
  }

  @Builder
  cardTitle(text: ResourceStr) {
    Text(text).fontSize(15).fontWeight(FontWeight.Medium).fontColor(COLOR_PRIMARY)
      .width('100%').padding({ left: 16, right: 16, top: 12, bottom: 4 });
  }

  // Live sample of what the sliders above do — same colours, size and radius as
  // a real bubble.
  @Builder
  preview() {
    Column({ space: 8 }) {
      Row() {
        Text($r('app.string.chat_settings_preview_in'))
          .fontSize(this.textSize).fontColor(COLOR_TEXT_PRIMARY)
          .padding({ left: 12, right: 12, top: 8, bottom: 8 })
          .backgroundColor(COLOR_BUBBLE_IN)
          .borderRadius(this.bubbleRadius);
      }.width('100%').justifyContent(FlexAlign.Start);
      Row() {
        Text($r('app.string.chat_settings_preview_out'))
          .fontSize(this.textSize).fontColor(COLOR_TEXT_PRIMARY)
          .padding({ left: 12, right: 12, top: 8, bottom: 8 })
          .backgroundColor(COLOR_BUBBLE_OUT)
          .borderRadius(this.bubbleRadius);
      }.width('100%').justifyContent(FlexAlign.End);
    }
    .width('100%').padding(14);
  }

  @Builder
  sliderRow(title: string, key: string, min: number, max: number) {
    Column() {
      this.cardTitle(title);
      Row({ space: 12 }) {
        Slider({ value: this.numberValue(key), min: min, max: max, step: 1 })
          .layoutWeight(1)
          .trackColor($r('app.color.divider')).selectedColor(COLOR_PRIMARY).blockColor(COLOR_PRIMARY)
          .onChange((value: number): void => { setNumber(key, Math.round(value)); });
        Text(`${this.numberValue(key)}`)
          .fontSize(15).fontColor(COLOR_PRIMARY).width(28).textAlign(TextAlign.End);
      }.width('100%').padding({ left: 16, right: 16, bottom: 6 });
    }.width('100%');
  }

  @Builder
  toggleRow(title: string, subtitle: string, key: string) {
    Row({ space: 12 }) {
      Column({ space: 2 }) {
        Text(title).fontSize(16).fontColor(COLOR_TEXT_PRIMARY);
        if (subtitle !== '') {
          Text(subtitle).fontSize(12).fontColor(COLOR_TEXT_SECONDARY);
        }
      }
      .height(52)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .borderRadius(10)
      .stateStyles({
        normal: this.optionNormalStyle,
        pressed: this.optionPressedStyle
      })
      .accessibilityText(str('a11y_toggle_state', title, this.booleanValue(key) ? str('state_on') : str('state_off')))
      .onClick((): void => { setBoolean(key, !this.booleanValue(key)); });
      Toggle({ type: ToggleType.Switch, isOn: this.booleanValue(key) })
        .selectedColor(COLOR_PRIMARY)
        .onChange((value: boolean): void => { setBoolean(key, value); });
    }
    .width('100%').height(64).padding({ left: 16, right: 13 })
    .alignItems(VerticalAlign.Center);
  }

  // Chat-list row density: two lines (name + preview) or three (adds a second
  // preview line).
  @Builder
  chatListView() {
    Column() {
      this.cardTitle($r('app.string.chat_settings_list_view'));
      Row({ space: 12 }) {
        this.densityOption(str('chat_settings_two_lines'), false);
        this.densityOption(str('chat_settings_three_lines'), true);
      }.width('100%').padding({ left: 16, right: 16, top: 4, bottom: 12 });
    }.width('100%');
  }

  @Builder
  densityOption(label: string, isThree: boolean) {
    Column({ space: 8 }) {
      Column({ space: 5 }) {
        Row({ space: 8 }) {
          Circle({ width: 22, height: 22 }).fill($r('app.color.divider'));
          Column({ space: 3 }) {
            Row().width('70%').height(4).borderRadius(2).backgroundColor($r('app.color.divider'));
            Row().width('90%').height(4).borderRadius(2).backgroundColor($r('app.color.divider'));
            if (isThree) {
              Row().width('80%').height(4).borderRadius(2).backgroundColor($r('app.color.divider'));
            }
          }.alignItems(HorizontalAlign.Start).layoutWeight(1);
        }.width('100%').alignItems(VerticalAlign.Center);
      }
      .width('100%').padding(10)
      .borderRadius(10)
      .border({ width: this.threeLines === isThree ? 2 : 1,
        color: this.threeLines === isThree ? COLOR_PRIMARY : $r('app.color.divider') })
      .backgroundColor(this.threeLines === isThree ? $r('app.color.surface_alt') : Color.Transparent)
      .animation({
        duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 160),
        curve: Curve.EaseOut
      });
      Text(label).fontSize(13)
        .fontColor(this.threeLines === isThree ? COLOR_PRIMARY : COLOR_TEXT_SECONDARY);
    }
    .layoutWeight(1)
    .borderRadius(12)
    .stateStyles({
      normal: this.optionNormalStyle,
      pressed: this.optionPressedStyle
    })
    .accessibilityText(str('a11y_chat_list_view', label, this.threeLines === isThree ? str('a11y_selected') : ''))
    .onClick((): void => {
      if (this.threeLines !== isThree) {
        setBoolean(KEY_THREE_LINES, isThree);
      }
    });
  }

  @Builder
  nightModeCard() {
    Column() {
      this.cardTitle($r('app.string.chat_settings_night_mode'));
      ForEach(NIGHT_OPTIONS, (opt: NightOption, idx: number) => {
        if (idx > 0) {
          Divider().color($r('app.color.divider')).strokeWidth(0.7).margin({ left: 16 });
        }
        Row() {
          Text(opt.label).fontSize(16).fontColor(COLOR_TEXT_PRIMARY).layoutWeight(1);
          if (this.nightMode === opt.value) {
            SymbolGlyph($r('sys.symbol.checkmark')).fontSize(18).fontColor([COLOR_PRIMARY]);
          }
        }
        .width('100%').height(48).padding({ left: 16, right: 16 })
        .stateStyles({
          normal: this.optionNormalStyle,
          pressed: this.optionPressedStyle
        })
        .accessibilityText(str('a11y_option_state', opt.label, this.nightMode === opt.value ? str('a11y_selected') : ''))
        .onClick((): void => {
          if (this.nightMode !== opt.value) {
            setNightMode(opt.value);
          }
        });
      }, (opt: NightOption) => opt.value);
    }.width('100%');
  }

  build() {
    Column() {
      this.header();
      Scroll() {
        Column({ space: 14 }) {
          // 字号 + 圆角, with the preview they drive.
          Column() {
            this.sliderRow(str('chat_settings_text_size'), KEY_TEXT_SIZE, TEXT_SIZE_MIN, TEXT_SIZE_MAX);
            this.preview();
            Divider().color($r('app.color.divider')).strokeWidth(0.7).margin({ left: 16, right: 16 });
            this.sliderRow(str('chat_settings_corner'), KEY_BUBBLE_RADIUS, RADIUS_MIN, RADIUS_MAX);
          }
          .width('100%').backgroundColor(CARD_BG).borderRadius(CARD_RADIUS);

          Row({ space: 12 }) {
            SymbolGlyph($r('sys.symbol.picture')).fontSize(20).fontColor([COLOR_PRIMARY]);
            Text($r('app.string.chat_settings_background')).fontSize(16).fontColor(COLOR_TEXT_PRIMARY).layoutWeight(1);
            SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(16)
              .fontColor([COLOR_TEXT_SECONDARY]);
          }
          .width('100%').height(52).padding({ left: 16, right: 12 })
          .backgroundColor(CARD_BG).borderRadius(CARD_RADIUS)
          .onClick((): void => {
            router.pushUrl({ url: 'pages/main/ChatBackgroundPage' })
              .catch((error: Error): void => {
                console.error(`ChatSettings open background failed: ${error.message}`);
              });
          });

          Column() {
            this.chatListView();
          }.width('100%').backgroundColor(CARD_BG).borderRadius(CARD_RADIUS);

          Column() {
            this.nightModeCard();
          }.width('100%').backgroundColor(CARD_BG).borderRadius(CARD_RADIUS).padding({ bottom: 4 });

          Column() {
            this.toggleRow(str('chat_settings_reduce_anim'), str('chat_settings_reduce_anim_sub'), KEY_REDUCE_ANIM);
            Divider().color($r('app.color.divider')).strokeWidth(0.7).margin({ left: 16 });
            this.toggleRow(str('chat_settings_send_by_enter'), str('chat_settings_send_by_enter_sub'), KEY_SEND_BY_ENTER);
            Divider().color($r('app.color.divider')).strokeWidth(0.7).margin({ left: 16 });
            this.toggleRow(str('chat_settings_in_app_browser'),
              str('chat_settings_in_app_browser_sub'), KEY_IN_APP_BROWSER);
          }
          .width('100%').backgroundColor(CARD_BG).borderRadius(CARD_RADIUS)
          .padding({ top: 4, bottom: 4 });

        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 8, bottom: this.bottomSafe + 24 });
      }
      .layoutWeight(1).width('100%')
      .align(Alignment.Top)
      .scrollBar(BarState.Off);
    }
    .width('100%').height('100%')
    .backgroundColor($r('app.color.page_bg'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .padding({ top: this.topSafe });
  }
}
