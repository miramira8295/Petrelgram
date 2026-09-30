import { actionBarButtons, ActionBarButton } from '../../util/chatActionBar';
import { COLOR_ICON_SECONDARY, COLOR_PRIMARY, accentSoft } from '../../util/theme';
import { str } from '../../util/strings';
import { CHAT_TOP_BANNER_ROW_HEIGHT } from '../../util/ChatChromeGeometry';
import { KEY_POWER_SMOOTH_TRANSITIONS, powerAnimationDuration } from '../../store/AppSettings';

// 按钮胶囊的高度。整行 CHAT_TOP_BANNER_ROW_HEIGHT（54），上下各留一点空。
const PILL_HEIGHT: number = 36;
const DESTRUCTIVE_TEXT: string = '#E5484D';

// 与 actionMenuRow / 菜单行同一套按压反馈。
@Styles
function pillNormalStyle() {
  .opacity(1)
  .scale({ x: 1, y: 1 })
}

@Styles
function pillPressedStyle() {
  .opacity(0.72)
  .scale({ x: 0.96, y: 0.94 })
}

// 会话操作条（issue #201 第 8 条）：一行按钮 + 右侧 ✕。住在 TopBanners 里、
// 置顶横幅之上（Telegram 也在那）。只发回调，动作由 ChatActionBarActions 做。
//
// 每个按钮是一颗浅底胶囊、带按压反馈。第一版只有彩色文字，没有底、按下去也没
// 反应，整条读起来像一行说明（用户：「一点都没有按钮的感觉」）。
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
    Row({ space: 8 }) {
      ForEach(this.buttons(), (b: ActionBarButton) => {
        Text(str(b.labelKey))
          .fontSize(14).fontWeight(FontWeight.Medium)
          .fontColor(b.destructive ? DESTRUCTIVE_TEXT : COLOR_PRIMARY)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          .textAlign(TextAlign.Center)
          .layoutWeight(1).height(PILL_HEIGHT)
          .padding({ left: 8, right: 8 })
          .borderRadius(PILL_HEIGHT / 2)
          .backgroundColor(b.destructive ? $r('app.color.dc_err_soft') : accentSoft())
          .stateStyles({ normal: pillNormalStyle, pressed: pillPressedStyle })
          .animation({ duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 110), curve: Curve.EaseOut })
          .onClick((): void => { this.onAction(b.id); });
      }, (b: ActionBarButton): string => b.id);
      Stack() {
        SymbolGlyph($r('sys.symbol.xmark'))
          .fontSize(14).fontColor([COLOR_ICON_SECONDARY]);
      }
      .width(PILL_HEIGHT).height(PILL_HEIGHT)
      .borderRadius(PILL_HEIGHT / 2)
      .backgroundColor($r('app.color.reaction_chip'))
      .stateStyles({ normal: pillNormalStyle, pressed: pillPressedStyle })
      .animation({ duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 110), curve: Curve.EaseOut })
      .onClick((): void => { this.onDismiss(); });
    }
    .width('100%').height(CHAT_TOP_BANNER_ROW_HEIGHT)
    .padding({ left: 10, right: 10 })
    .alignItems(VerticalAlign.Center)
    .accessibilityText(str('ab_block'))
    .accessibilityGroup(false);
  }
}
