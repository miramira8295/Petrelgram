import { COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY } from '../../util/theme';
import { languageDisplayName } from '../../services/TranslationService';
import { TRANSLATE_DONE, TRANSLATE_EMPTY, TRANSLATE_FAILED } from '../../util/translationMode';
import { str } from '../../util/strings';

// 长按消息「翻译」弹出的那张单条译文卡：原文 / 译文 / 目标语言胶囊 / 复制。
//
// 从 ChatPage 搬出来。纯展示——三个动作（换语言、重试、复制）全都要碰
// TranslationService 和剪贴板，留在页面里，这里只回调。
//
// 显示态由 util/translationMode 的 sheetStateOf 定，有单测：null 是失败，
// 空串和"原样返回原文"都算没东西可看。

const LANG_PILL_BG: string = '#143390EC';

@Component
export struct TranslateSheet {
  @Prop original: string;
  @Prop translated: string;
  // TRANSLATE_LOADING | TRANSLATE_DONE | TRANSLATE_FAILED | TRANSLATE_EMPTY
  @Prop state: string;
  @Prop lang: string;
  @Prop bottomSafe: number;

  onPickLang: () => void = (): void => {};
  onRetry: () => void = (): void => {};
  onCopy: () => void = (): void => {};

  @Builder
  header() {
    Row() {
      Text($r('app.string.mb_translate'))
        .fontSize(17).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT_PRIMARY)
        .layoutWeight(1);
      // 目标语言胶囊：点它换语言并重译。
      Row({ space: 4 }) {
        Text(languageDisplayName(this.lang))
          .fontSize(13).fontColor(COLOR_PRIMARY).fontWeight(FontWeight.Medium);
        SymbolGlyph($r('sys.symbol.chevron_down')).fontSize(12).fontColor([COLOR_PRIMARY]);
      }
      .padding({ left: 10, right: 10, top: 5, bottom: 5 })
      .borderRadius(14)
      .backgroundColor(LANG_PILL_BG)
      .onClick((): void => { this.onPickLang(); });
    }
    .width('100%')
    .padding({ left: 18, right: 18, top: 6, bottom: 10 });
  }

  @Builder
  result() {
    if (this.state === TRANSLATE_FAILED) {
      Text($r('app.string.cp_translate_failed'))
        .fontSize(14).fontColor(COLOR_TEXT_SECONDARY).alignSelf(ItemAlign.Start);
      Button($r('app.string.cp_translate_retry'))
        .fontSize(14).height(34)
        .backgroundColor(LANG_PILL_BG).fontColor(COLOR_PRIMARY)
        .alignSelf(ItemAlign.Start)
        .onClick((): void => { this.onRetry(); });
    } else if (this.state === TRANSLATE_EMPTY) {
      Text($r('app.string.cp_nothing_to_translate'))
        .fontSize(14).fontColor(COLOR_TEXT_SECONDARY).alignSelf(ItemAlign.Start);
    } else if (this.state === TRANSLATE_DONE) {
      Text(this.translated)
        .fontSize(16).lineHeight(22).fontColor(COLOR_TEXT_PRIMARY)
        .copyOption(CopyOptions.LocalDevice)
        .alignSelf(ItemAlign.Start);
    } else {
      // loading，以及任何没见过的态——转圈比空白诚实。
      LoadingProgress().width(26).height(26).color(COLOR_PRIMARY)
        .alignSelf(ItemAlign.Center).margin({ top: 12 });
    }
  }

  build() {
    Column() {
      this.header();
      Scroll() {
        Column({ space: 6 }) {
          Text($r('app.string.cp_translate_original'))
            .fontSize(12).fontColor(COLOR_TEXT_SECONDARY)
            .alignSelf(ItemAlign.Start);
          Text(this.original)
            .fontSize(16).lineHeight(22).fontColor(COLOR_TEXT_PRIMARY)
            .copyOption(CopyOptions.LocalDevice)
            .alignSelf(ItemAlign.Start);
          Divider().color($r('app.color.divider')).strokeWidth(0.7)
            .margin({ top: 8, bottom: 8 });
          Text(str('mb_translated_into', languageDisplayName(this.lang)))
            .fontSize(12).fontColor(COLOR_TEXT_SECONDARY)
            .alignSelf(ItemAlign.Start);
          this.result();
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding({ left: 18, right: 18, bottom: 16 });
      }
      .layoutWeight(1)
      .align(Alignment.TopStart)
      .scrollBar(BarState.Off);
      if (this.state === TRANSLATE_DONE) {
        // width('100%') 不能和横向 margin 同时用：百分比宽先按父宽定值，margin 再叠在
        // 外部，总宽 = 父宽 + left + right，右端会被裁掉。宽度改用 calc 扣掉左右 margin。
        Button($r('app.string.copy'))
          .width('calc(100% - 36vp)').height(44).fontSize(16)
          .backgroundColor(COLOR_PRIMARY).fontColor(Color.White)
          .margin({ left: 18, right: 18, bottom: this.bottomSafe + 10 })
          .onClick((): void => { this.onCopy(); });
      }
    }
    .width('100%').height('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ top: 8 });
  }
}
