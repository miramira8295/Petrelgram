import { router } from '@kit.ArkUI';
import { KEY_MSG_GESTURE, setString } from '../../store/AppSettings';
import { GESTURE_CLASSIC, GESTURE_TAP_FIRST } from '../../util/messageGestures';
import { COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY } from '../../util/theme';
import { str } from '../../util/strings';
import { LANGUAGE_EPOCH } from '../../util/appLanguage';

const CARD_BG: ResourceColor = $r('app.color.surface');
const CARD_RADIUS: number = 14;

interface GestureOption {
  value: string;
  label: ResourceStr;
  detail: ResourceStr;
}

// 顺序固定：老交互在上，因为它是默认值，也是绝大多数人现在正在用的那个。
const GESTURE_OPTIONS: GestureOption[] = [
  {
    value: GESTURE_CLASSIC,
    label: $r('app.string.ix_classic'),
    detail: $r('app.string.ix_classic_sub')
  },
  {
    value: GESTURE_TAP_FIRST,
    label: $r('app.string.ix_tap_first'),
    detail: $r('app.string.ix_tap_first_sub')
  }
];

// 交互设置。目前只有聊天详情一组——这个页面存在的意义是"手势的分工可以换"，
// 以后别的页面有同类可换项时往这里加分组，而不是散到各自的设置页里。
@Entry
@Component
struct InteractionSettingsPage {
  @StorageProp(LANGUAGE_EPOCH) langEpoch: number = 0;
  @StorageProp('topSafeHeight') topSafe: number = 0;
  @StorageProp('bottomSafeHeight') bottomSafe: number = 0;
  @StorageLink(KEY_MSG_GESTURE) gestureScheme: string = GESTURE_CLASSIC;
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
      Text($r('app.string.settings_interaction')).fontSize(22).fontWeight(FontWeight.Bold)
        .fontColor(COLOR_TEXT_PRIMARY).layoutWeight(1);
    }
    .width('100%').height(56).padding({ left: 8, right: 16 })
    .alignItems(VerticalAlign.Center);
  }

  @Builder
  cardTitle(text: ResourceStr) {
    Text(text).fontSize(15).fontWeight(FontWeight.Medium).fontColor(COLOR_PRIMARY)
      .width('100%').padding({ left: 16, right: 16, top: 12, bottom: 4 });
  }

  @Builder
  chatCard() {
    Column() {
      this.cardTitle($r('app.string.ix_chat_group'));
      ForEach(GESTURE_OPTIONS, (opt: GestureOption, idx: number) => {
        if (idx > 0) {
          Divider().color($r('app.color.divider')).strokeWidth(0.7).margin({ left: 16 });
        }
        Row() {
          Column({ space: 3 }) {
            Text(opt.label).fontSize(16).fontColor(COLOR_TEXT_PRIMARY).width('100%');
            // 说明写全：这两套的差别不是一个词能讲清的，尤其"图片链接按钮
            // 的点击不受影响"这句，不写的话没人敢开。
            Text(opt.detail).fontSize(13).fontColor(COLOR_TEXT_SECONDARY).width('100%');
          }.layoutWeight(1);
          if (this.gestureScheme === opt.value) {
            SymbolGlyph($r('sys.symbol.checkmark')).fontSize(18).fontColor([COLOR_PRIMARY])
              .margin({ left: 12 });
          }
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 12, bottom: 12 })
        .alignItems(VerticalAlign.Center)
        .stateStyles({
          normal: this.optionNormalStyle,
          pressed: this.optionPressedStyle
        })
        .accessibilityText(str('a11y_option_state', `${opt.label}`,
          this.gestureScheme === opt.value ? str('a11y_selected') : ''))
        .onClick((): void => {
          if (this.gestureScheme !== opt.value) {
            // @StorageLink 立即翻，界面上的对勾马上动；setString 负责落盘。
            // 聊天页的气泡用 @StorageProp 读同一个键，退回去就已经是新手势了。
            this.gestureScheme = opt.value;
            setString(KEY_MSG_GESTURE, opt.value);
          }
        });
      }, (opt: GestureOption) => opt.value);
    }
    .width('100%')
    .backgroundColor(CARD_BG)
    .borderRadius(CARD_RADIUS)
    .padding({ bottom: 4 });
  }

  build() {
    Column() {
      this.header();
      Scroll() {
        Column({ space: 14 }) {
          this.chatCard();
        }
        .width('100%')
        .padding({ left: 14, right: 14, bottom: this.bottomSafe + 20 });
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .align(Alignment.Top);
    }
    .width('100%').height('100%')
    // 没有这一行时页面的布局区停在安全区边界，状态栏那一条不归页面画，
    // 露出的是窗口底色。padding 只负责把内容让开，铺满是另一回事。
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .padding({ top: this.topSafe })
    .backgroundColor($r('app.color.page_bg'));
  }
}
