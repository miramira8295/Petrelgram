import { router, promptAction } from '@kit.ArkUI';
import { TdError, TdObject } from '../../tdkit/TdTypes';
import {
  RULE_CONTACTS, RULE_EVERYBODY, RULE_NOBODY,
  PrivacyValue, getPrivacy, setPrivacy
} from '../../store/PrivacyApi';
import {
  COLOR_PAGE_BG, COLOR_PRIMARY, COLOR_SURFACE,
  COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY
} from '../../util/theme';
import { str } from '../../util/strings';
import { logE } from '../../util/log';
import { readableContentWidth } from '../../util/contentWidth';

const CARD_RADIUS: number = 16;

export interface PrivacyRuleParams {
  setting: string;
  title: string;
  hint: string;
  allowNobody: boolean;
}

export interface PrivacyExceptionsParams {
  setting: string;
  title: string;
}

interface RuleOption {
  label: string;
  value: string;
}

const ALL_OPTIONS: RuleOption[] = [
  { label: str('privacy_everybody'), value: RULE_EVERYBODY },
  { label: str('privacy_contacts'), value: RULE_CONTACTS },
  { label: str('privacy_nobody'), value: RULE_NOBODY }
];

@Entry
@Component
struct PrivacyRulePage {
  @StorageProp('topSafeHeight') topSafe: number = 0;
  @StorageProp('bottomSafeHeight') bottomSafe: number = 0;
  // 窗口宽（不是屏幕宽），限宽用。平板上把一列拉满 2880px 眼睛要横扫一行。
  @StorageProp('screenWidthVp') screenW: number = 360;
  @State setting: string = '';
  @State title: string = '';
  @State hint: string = '';
  @State allowNobody: boolean = true;
  @State base: string = '';
  @State allowExceptions: number = 0;
  @State restrictExceptions: number = 0;
  @State loadState: string = 'loading';
  @State saving: boolean = false;
  @State pressedKey: string = '';
  private preserved: TdObject[] = [];
  private active: boolean = false;
  private sequence: number = 0;

  @Styles
  optionNormalStyle() {
    .backgroundColor(Color.Transparent).opacity(1).scale({ x: 1, y: 1 })
  }

  @Styles
  optionPressedStyle() {
    .backgroundColor($r('app.color.surface_alt')).opacity(0.82).scale({ x: 0.992, y: 0.97 })
  }

  aboutToAppear(): void {
    this.active = true;
    const params = router.getParams() as PrivacyRuleParams | undefined;
    if (params === undefined || params.setting === undefined || params.setting === '') {
      router.back();
      return;
    }
    this.setting = params.setting;
    this.title = params.title;
    this.hint = params.hint;
    this.allowNobody = params.allowNobody !== false;
    this.load();
  }

  aboutToDisappear(): void {
    this.active = false;
    this.sequence++;
    this.saving = false;
  }

  private load(): void {
    const sequence = ++this.sequence;
    this.loadState = 'loading';
    getPrivacy(this.setting).then((value: PrivacyValue): void => {
      if (!this.active || sequence !== this.sequence) { return; }
      this.base = value.base;
      this.allowExceptions = value.allowExceptions;
      this.restrictExceptions = value.restrictExceptions;
      this.preserved = value.extra;
      this.loadState = 'ready';
    }).catch((error: TdError): void => {
      if (!this.active || sequence !== this.sequence) { return; }
      logE(`PrivacyRulePage.load failed: ${error.message}`);
      this.loadState = 'error';
    });
  }

  private options(): RuleOption[] {
    return this.allowNobody ? ALL_OPTIONS : ALL_OPTIONS.slice(0, 2);
  }

  private pick(value: string): void {
    if (this.loadState !== 'ready' || this.saving || value === this.base) { return; }
    if (!this.allowNobody && value === RULE_NOBODY) { return; }
    const previous = this.base;
    this.base = value;
    this.saving = true;
    setPrivacy(this.setting, value, this.preserved).then((): void => {
      if (!this.active) { return; }
      this.saving = false;
    }).catch((error: TdError): void => {
      logE(`PrivacyRulePage.setPrivacy failed: ${error.message}`);
      if (!this.active) { return; }
      this.base = previous;
      this.saving = false;
      promptAction.showToast({ message: $r('app.string.privacy_save_failed'), duration: 1800 });
    });
  }

  private openExceptions(): void {
    if (this.loadState !== 'ready' || this.saving) { return; }
    const params: PrivacyExceptionsParams = { setting: this.setting, title: this.title };
    router.pushUrl({ url: 'pages/main/PrivacyExceptionsPage', params }).catch((): void => {
      promptAction.showToast({ message: $r('app.string.privacy_exceptions_open_failed'), duration: 1600 });
    });
  }

  @Builder
  header() {
    Row({ space: 8 }) {
      Button() {
        SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(24).fontColor([COLOR_TEXT_PRIMARY]);
      }
      .width(40).height(40).borderRadius(20).backgroundColor(Color.Transparent)
      .onClick((): void => { router.back(); });
      Text(this.title).fontSize(22).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT_PRIMARY)
        .layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
      if (this.saving) { LoadingProgress().width(21).height(21).color(COLOR_PRIMARY); }
    }
    .width('100%').height(52).padding({ left: 8, right: 16 }).alignItems(VerticalAlign.Center);
  }

  @Builder
  divider() {
    Divider().color($r('app.color.divider')).strokeWidth(0.7).margin({ left: 16 });
  }

  @Builder
  loadError() {
    Column({ space: 12 }) {
      SymbolGlyph($r('sys.symbol.exclamationmark_circle')).fontSize(46).fontColor([COLOR_TEXT_SECONDARY]);
      Text($r('app.string.privacy_rule_unreadable')).fontSize(17).fontWeight(FontWeight.Medium).fontColor(COLOR_TEXT_PRIMARY);
      Text($r('app.string.privacy_rule_no_overwrite')).fontSize(13).fontColor(COLOR_TEXT_SECONDARY);
      Button($r('app.string.settings_reload')).height(42).borderRadius(21).fontColor(Color.White).backgroundColor(COLOR_PRIMARY)
        .onClick((): void => { this.load(); });
    }
    .layoutWeight(1).width('100%').justifyContent(FlexAlign.Center);
  }

  build() {
    Column() {
      this.header();
      if (this.loadState === 'loading') {
        Column({ space: 10 }) {
          LoadingProgress().width(34).height(34).color(COLOR_PRIMARY);
          Text($r('app.string.privacy_rule_loading')).fontSize(13).fontColor(COLOR_TEXT_SECONDARY);
        }.layoutWeight(1).width('100%').justifyContent(FlexAlign.Center);
      } else if (this.loadState === 'error') {
        this.loadError();
      } else {
        Scroll() {
          // 两层 Column 是故意的：外层铺满、负责居中，内层才是被限宽的内容。
          // 限宽如果加在 Scroll 上，滚动条和边缘回弹会跟着一起缩进来，侧边留白
          // 区域还会拖不动页面；做在里面则留白仍在 Scroll 的命中区，能拖。
          Column() {
            Column({ space: 12 }) {
              Column() {
                Text($r('app.string.privacy_who_can')).fontSize(14).fontWeight(FontWeight.Medium).fontColor(COLOR_PRIMARY)
                  .width('100%').padding({ left: 16, top: 13, bottom: 5 });
                ForEach(this.options(), (option: RuleOption, index: number) => {
                  if (index > 0) { this.divider(); }
                  Row({ space: 10 }) {
                    Text(option.label).fontSize(16).fontColor(COLOR_TEXT_PRIMARY).layoutWeight(1);
                    if (this.base === option.value) {
                      SymbolGlyph($r('sys.symbol.checkmark')).fontSize(19).fontColor([COLOR_PRIMARY]);
                    }
                  }
                  .width('100%').constraintSize({ minHeight: 50 }).padding({ left: 16, right: 16 })
                  .borderRadius(12).stateStyles({ normal: this.optionNormalStyle, pressed: this.optionPressedStyle })
                  .opacity(this.saving ? 0.72 : 1)
                  .onClick((): void => { this.pick(option.value); });
                }, (option: RuleOption): string => `${option.value}_${this.base}`);
              }
              .width('100%').backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS).padding({ bottom: 5 });

              Text(this.hint).fontSize(12).fontColor(COLOR_TEXT_SECONDARY).lineHeight(18)
                .width('100%').padding({ left: 16, right: 16 });

              Column() {
                Text($r('app.string.privacy_exceptions')).fontSize(14).fontWeight(FontWeight.Medium).fontColor(COLOR_PRIMARY)
                  .width('100%').padding({ left: 16, top: 13, bottom: 5 });
                Row({ space: 9 }) {
                  Column({ space: 2 }) {
                    Text($r('app.string.privacy_always_allow')).fontSize(16).fontColor(COLOR_TEXT_PRIMARY);
                    Text($r('app.string.privacy_always_allow_sub')).fontSize(12).fontColor(COLOR_TEXT_SECONDARY);
                  }.layoutWeight(1).alignItems(HorizontalAlign.Start);
                  Text(`${this.allowExceptions}`).fontSize(14).fontColor(COLOR_TEXT_SECONDARY);
                  SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(16).fontColor([COLOR_TEXT_SECONDARY]);
                }
                .width('100%').constraintSize({ minHeight: 60 }).padding({ left: 16, right: 14 })
                .onClick((): void => { this.openExceptions(); });
                this.divider();
                Row({ space: 9 }) {
                  Column({ space: 2 }) {
                    Text($r('app.string.privacy_never_allow')).fontSize(16).fontColor(COLOR_TEXT_PRIMARY);
                    Text($r('app.string.privacy_never_allow_sub')).fontSize(12).fontColor(COLOR_TEXT_SECONDARY);
                  }.layoutWeight(1).alignItems(HorizontalAlign.Start);
                  Text(`${this.restrictExceptions}`).fontSize(14).fontColor(COLOR_TEXT_SECONDARY);
                  SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(16).fontColor([COLOR_TEXT_SECONDARY]);
                }
                .width('100%').constraintSize({ minHeight: 60 }).padding({ left: 16, right: 14 })
                .onClick((): void => { this.openExceptions(); });
              }
              .width('100%').backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS).padding({ bottom: 5 });

              Text($r('app.string.privacy_exceptions_note'))
                .fontSize(12).fontColor(COLOR_TEXT_SECONDARY).lineHeight(18)
                .width('100%').padding({ left: 16, right: 16 });
            }
            .width('100%')
            .constraintSize({ maxWidth: readableContentWidth(this.screenW) })
            .padding({ left: 12, right: 12, top: 6, bottom: this.bottomSafe + 24 });
          }
          .width('100%')
          // Column 默认左对齐：限了宽不居中就是把内容全堆在屏幕左边，比不限还难看。
          .alignItems(HorizontalAlign.Center);
        }
        .layoutWeight(1).width('100%').align(Alignment.Top).scrollBar(BarState.Off);
      }
    }
    .width('100%').height('100%').backgroundColor(COLOR_PAGE_BG)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .padding({ top: this.topSafe });
  }
}
