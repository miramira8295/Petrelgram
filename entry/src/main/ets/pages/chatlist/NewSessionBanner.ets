import { getSessionSecurityStore } from '../../tdkit/Globals';
import { navigateToSetting } from '../../util/settingsNav';
import { COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY } from '../../util/theme';
import { LANGUAGE_EPOCH } from '../../util/appLanguage';
import { str } from '../../util/strings';

// 隔离罕见的安全状态刷新，不让整张会话列表依赖待确认设备计数。
@Component
export struct NewSessionBanner {
  @State private count: number = 0;
  @StorageProp(LANGUAGE_EPOCH) private languageEpoch: number = 0;
  private off: (() => void) | null = null;

  aboutToAppear(): void {
    this.off = getSessionSecurityStore().subscribe((count: number): void => { this.count = count; });
  }
  aboutToDisappear(): void { this.off?.(); this.off = null; }

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
      .backgroundColor($r('app.color.surface')).flexShrink(0)
      .accessibilityGroup(true)
      .onClick((): void => { navigateToSetting('ActiveSessionsPage'); });
    }
  }
}
