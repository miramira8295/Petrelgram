import { navigateToSetting } from '../../util/settingsNav';
import { COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY } from '../../util/theme';
import { LANGUAGE_EPOCH } from '../../util/appLanguage';
import { str } from '../../util/strings';

// 提示与文件夹栏共用 HDS 标题栏背板，高度由标题栏统一预留。
export const NEW_SESSION_BAR_HEIGHT: number = 64;
@Component
export struct NewSessionBanner {
  @Prop count: number = 0;
  @StorageProp(LANGUAGE_EPOCH) private languageEpoch: number = 0;
  build() {
    if (this.count > 0) {
      Row({ space: 10 }) {
        SymbolGlyph($r('sys.symbol.exclamationmark_circle')).fontSize(24).fontColor([COLOR_PRIMARY]);
        Column({ space: 3 }) {
          Text($r('app.string.session_new_login')).fontSize(14).fontWeight(FontWeight.Medium)
            .fontColor(COLOR_TEXT_PRIMARY);
          Text(this.languageEpoch >= 0 ? str('session_review_count', this.count) : '')
            .fontSize(12).fontColor(COLOR_TEXT_SECONDARY);
        }.layoutWeight(1).alignItems(HorizontalAlign.Start);
        SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(14).fontColor([COLOR_TEXT_SECONDARY]);
      }
      .width('100%').padding({ left: 16, right: 16, top: 12, bottom: 12 })
      .height(NEW_SESSION_BAR_HEIGHT).flexShrink(0)
      .accessibilityGroup(true)
      .onClick((): void => { navigateToSetting('ActiveSessionsPage'); });
    }
  }
}
