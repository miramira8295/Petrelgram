import { COLOR_BUBBLE_TEXT } from '../../util/theme';
import { KEY_POWER_SMOOTH_TRANSITIONS, powerAnimationDuration } from '../../store/AppSettings';

// Shared row used by both the long-press message context menu
// (MessageBubble.msgContextMenu) and the chat header ⋮ dropdown
// (ChatPage.headerMenu) so the two menus render identically. Spec pinned to
// the bubble menu's original numbers: space 14 / icon 19 / text 16 /
// padding 16,11 / row radius 10 / danger color #FF3B30.
// Global @Styles: same visual as the bubble menu's original pressed feedback
// (opacity + slight non-uniform scale, no background tint).
@Styles
function actionMenuRowNormalStyle() {
  .opacity(1)
  .scale({ x: 1, y: 1 })
}

@Styles
function actionMenuRowPressedStyle() {
  .opacity(0.72)
  .scale({ x: 0.97, y: 0.94 })
}

@Builder
export function actionMenuRow(icon: string, label: string, danger: boolean, onTap: () => void) {
  Row({ space: 14 }) {
    SymbolGlyph($r(icon)).fontSize(19).fontColor([danger ? '#FF3B30' : COLOR_BUBBLE_TEXT]);
    Text(label).fontSize(16).fontColor(danger ? '#FF3B30' : COLOR_BUBBLE_TEXT).layoutWeight(1);
  }
  .width('100%').padding({ left: 16, right: 16, top: 11, bottom: 11 })
  .alignItems(VerticalAlign.Center)
  .borderRadius(10)
  .stateStyles({
    normal: actionMenuRowNormalStyle,
    pressed: actionMenuRowPressedStyle
  })
  .animation({ duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 110), curve: Curve.EaseOut })
  .onClick(onTap);
}
