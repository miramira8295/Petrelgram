import { actionBarButtons, ActionBarButton } from '../../util/chatActionBar';
import { COLOR_ICON_SECONDARY, COLOR_PRIMARY } from '../../util/theme';
import { str } from '../../util/strings';
import { CHAT_TOP_BANNER_ROW_HEIGHT } from '../../util/ChatChromeGeometry';

// 会话操作条（issue #201 第 8 条）：一行文字按钮 + 右侧 ✕。住在 TopBanners 里、
// 置顶横幅之上（Telegram 也在那）。只发回调，动作由 ChatActionBarActions 做。
@ComponentV2
export struct ChatActionBarView {
  @Param kind: string = '';
  @Param canUnarchive: boolean = false;
  @Event onAction: (id: string) => void = (_id: string): void => {};
  @Event onDismiss: () => void = (): void => {};

  private buttons(): ActionBarButton[] {
    return actionBarButtons(this.kind, this.canUnarchive);
  }

  build() {
    Row() {
      Row() {
        ForEach(this.buttons(), (b: ActionBarButton) => {
          Text(str(b.labelKey))
            .fontSize(14).fontWeight(FontWeight.Medium)
            .fontColor(b.destructive ? '#E5484D' : COLOR_PRIMARY)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            .textAlign(TextAlign.Center)
            .layoutWeight(1).height('100%')
            .onClick((): void => { this.onAction(b.id); });
        }, (b: ActionBarButton): string => b.id);
      }
      .layoutWeight(1).height('100%');
      SymbolGlyph($r('sys.symbol.xmark'))
        .fontSize(16).fontColor([COLOR_ICON_SECONDARY])
        .width(36).height('100%')
        .onClick((): void => { this.onDismiss(); });
    }
    .width('100%').height(CHAT_TOP_BANNER_ROW_HEIGHT)
    .padding({ left: 8 })
    .accessibilityText(str('ab_block'))
    .accessibilityGroup(false);
  }
}
