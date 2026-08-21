import { common, Want } from '@kit.AbilityKit';
import { promptAction, router } from '@kit.ArkUI';
import {
  KEY_APP_LANGUAGE, KEY_TRANSLATE_CHATS, KEY_TRANSLATE_TARGET, setBoolean, setString
} from '../../store/AppSettings';
import { AppLanguage, LANGUAGE_SYSTEM, appLanguages, applyAppLanguage, labelForTag, requiresRestart, systemMatchedLanguage, LANGUAGE_EPOCH } from '../../util/appLanguage';
import {
  languageDisplayName, resolveTranslateTarget, TRANSLATE_LANG_CODES
} from '../../services/TranslationService';
import { str } from '../../util/strings';
import { COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY } from '../../util/theme';
import { logE } from '../../util/log';
import { HdsSubPage } from '../common/HdsSubPage';

const CARD_BG: ResourceColor = $r('app.color.surface');
const CARD_RADIUS: number = 14;

// 语言. Picking a concrete language takes effect immediately — resources
// reload and every page re-renders. Going back to 跟随系统 does not: the
// platform documents that clearing the app preferred language only applies
// after a restart, so that path offers the restart instead of leaving the user
// staring at an unchanged screen wondering what broke.
@Entry
@Component
struct LanguagePage {
  private hdsScroller: Scroller = new Scroller();
  @StorageProp(LANGUAGE_EPOCH) langEpoch: number = 0;
  @StorageProp('topSafeHeight') topSafe: number = 0;
  @StorageProp('bottomSafeHeight') bottomSafe: number = 0;
  @StorageLink(KEY_APP_LANGUAGE) selected: string = LANGUAGE_SYSTEM;
  // 翻译设置。目标语言 '' = 跟随系统；整聊天翻译是总开关，会话菜单里的
  // 「翻译此聊天」入口只在它打开时出现。
  @StorageLink(KEY_TRANSLATE_TARGET) translateTarget: string = '';
  @StorageLink(KEY_TRANSLATE_CHATS) translateChats: boolean = false;
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
  optionNormalStyle() {
    .backgroundColor(Color.Transparent)
    .opacity(1)
  }

  @Styles
  optionPressedStyle() {
    .backgroundColor($r('app.color.surface_alt'))
    .opacity(0.75)
  }

  @Styles
  actionNormalStyle() {
    .backgroundColor(Color.Transparent)
    .opacity(1)
  }

  @Styles
  actionPressedStyle() {
    .backgroundColor($r('app.color.surface_alt'))
    .opacity(0.75)
  }

  private restartApp(): void {
    try {
      const context = getContext(this) as common.UIAbilityContext;
      const want: Want = {
        bundleName: context.abilityInfo.bundleName,
        abilityName: context.abilityInfo.name
      };
      context.getApplicationContext().restartApp(want);
    } catch (e) {
      // 16000053 (not on top) and 16000064 (too frequent) are both recoverable
      // by the user restarting by hand, so say so rather than failing silently.
      logE(`LanguagePage.restartApp failed: ${e}`);
      promptAction.showToast({ message: str('language_restart_manual'), duration: 3000 });
    }
  }

  private confirmRestart(): void {
    AlertDialog.show({
      title: str('language_restart_title'),
      message: str('language_restart_body'),
      autoCancel: true,
      primaryButton: {
        value: str('language_restart_later'),
        action: (): void => {}
      },
      secondaryButton: {
        value: str('language_restart_now'),
        action: (): void => { this.restartApp(); }
      }
    });
  }

  private choose(tag: string): void {
    if (this.selected === tag) {
      return;
    }
    if (!applyAppLanguage(tag)) {
      promptAction.showToast({ message: str('language_apply_failed'), duration: 2000 });
      return;
    }
    setString(KEY_APP_LANGUAGE, tag);
    if (requiresRestart(tag)) {
      this.confirmRestart();
    }
  }

  // Only the 跟随系统 row gets a subtitle, and only when the system language
  // actually resolves to one of ours: "follow the system" is meaningless to the
  // user unless they can see what it currently means.
  @Builder
  optionRow(opt: AppLanguage, matched: string) {
    Row() {
      Column({ space: 2 }) {
        Text(opt.label).fontSize(16).fontColor(COLOR_TEXT_PRIMARY).width('100%');
        if (opt.tag === LANGUAGE_SYSTEM && matched !== '') {
          Text(str('language_system_hint', labelForTag(matched)))
            .fontSize(13).fontColor(COLOR_TEXT_SECONDARY).width('100%');
        }
      }.layoutWeight(1).alignItems(HorizontalAlign.Start);
      if (this.selected === opt.tag) {
        SymbolGlyph($r('sys.symbol.checkmark')).fontSize(18).fontColor([COLOR_PRIMARY]);
      }
    }
    .width('100%').padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .stateStyles({
      normal: this.optionNormalStyle,
      pressed: this.optionPressedStyle
    })
    .accessibilityText(this.selected === opt.tag
      ? `${opt.label}${str('a11y_selected')}` : opt.label)
    .onClick((): void => { this.choose(opt.tag); });
  }

  // 目标语言选择：首项「跟随系统」（清空设置），其后为固定候选表。
  private pickTranslateTarget(): void {
    const codes: string[] = TRANSLATE_LANG_CODES;
    const names: string[] = [str('language_system')];
    for (const code of codes) {
      names.push(languageDisplayName(code));
    }
    const selectedIdx: number = this.translateTarget === ''
      ? 0 : Math.max(0, codes.indexOf(this.translateTarget) + 1);
    TextPickerDialog.show({
      range: names,
      selected: selectedIdx,
      onAccept: (value: TextPickerResult): void => {
        const idx: number = value.index as number;
        setString(KEY_TRANSLATE_TARGET, idx <= 0 ? '' : codes[idx - 1]);
      }
    });
  }

  private translateTargetLabel(): string {
    if (this.translateTarget === '') {
      return str('language_system_hint', languageDisplayName(resolveTranslateTarget()));
    }
    return languageDisplayName(this.translateTarget);
  }

  @Builder
  translationSection() {
    Text($r('app.string.language_translate_section'))
      .fontSize(13).fontColor(COLOR_TEXT_SECONDARY)
      .width('100%').padding({ left: 16 });
    Column() {
      Row() {
        Text($r('app.string.language_translate_target'))
          .fontSize(16).fontColor(COLOR_TEXT_PRIMARY).layoutWeight(1);
        Text(this.translateTargetLabel())
          .fontSize(15).fontColor(COLOR_TEXT_SECONDARY);
        SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(16)
          .fontColor([COLOR_TEXT_SECONDARY]).margin({ left: 4 });
      }
      .width('100%').padding({ left: 16, right: 12, top: 13, bottom: 13 })
      .stateStyles({
        normal: this.optionNormalStyle,
        pressed: this.optionPressedStyle
      })
      .onClick((): void => { this.pickTranslateTarget(); });
      Divider().color($r('app.color.divider')).strokeWidth(0.7).margin({ left: 16 });
      Row() {
        Column({ space: 2 }) {
          Text($r('app.string.language_translate_chats'))
            .fontSize(16).fontColor(COLOR_TEXT_PRIMARY).width('100%');
          Text($r('app.string.language_translate_chats_hint'))
            .fontSize(13).fontColor(COLOR_TEXT_SECONDARY).width('100%');
        }.layoutWeight(1).alignItems(HorizontalAlign.Start);
        Toggle({ type: ToggleType.Switch, isOn: this.translateChats })
          .selectedColor(COLOR_PRIMARY)
          .onChange((on: boolean): void => { setBoolean(KEY_TRANSLATE_CHATS, on); });
      }
      .width('100%').padding({ left: 16, right: 12, top: 10, bottom: 10 });
    }
    .width('100%').backgroundColor(CARD_BG).borderRadius(CARD_RADIUS)
    .padding({ top: 2, bottom: 2 });
  }

  build() {
    Column() {
      HdsSubPage({ title: $r('app.string.language_title'), scroller: this.hdsScroller, onBack: (): void => { this.leavePage(); } }) {
      Scroll(this.hdsScroller) {
        Column({ space: 14 }) {
          this.translationSection();

          Text($r('app.string.language_app_section'))
            .fontSize(13).fontColor(COLOR_TEXT_SECONDARY)
            .width('100%').padding({ left: 16 });
          Column() {
            ForEach(appLanguages(), (opt: AppLanguage, idx: number) => {
              if (idx > 0) {
                Divider().color($r('app.color.divider')).strokeWidth(0.7).margin({ left: 16 });
              }
              this.optionRow(opt, systemMatchedLanguage());
            }, (opt: AppLanguage) => opt.tag);
          }
          .width('100%').backgroundColor(CARD_BG).borderRadius(CARD_RADIUS)
          .padding({ top: 4, bottom: 4 });

          Text($r('app.string.language_coverage_note'))
            .fontSize(13).fontColor(COLOR_TEXT_SECONDARY)
            .width('100%').padding({ left: 16, right: 16 });
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 8, bottom: this.bottomSafe + 24 });
      }
      .layoutWeight(1).width('100%')
      .align(Alignment.Top)
      .scrollBar(BarState.Off)
      // 不裁剪，内容才能穿到标题栏底下——渐变模糊模糊的正是这部分。
      .clip(false);
    }
    }
    .width('100%').height('100%')
    .backgroundColor($r('app.color.page_bg'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM]);
  }
}
