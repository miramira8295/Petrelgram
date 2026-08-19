import { COLOR_TEXT_PRIMARY } from '../../util/theme';
import { CHAT_HEADER_ACTION_SIZE, CHAT_HEADER_RADIUS } from './ChatHeader';
import { KEY_POWER_SMOOTH_TRANSITIONS, powerAnimationDuration } from '../../store/AppSettings';
import {
  overlayBackdropBlur, overlayGlassFill, overlayMaterial
} from '../../util/overlayMaterial';
import { str } from '../../util/strings';

// 多选态的顶栏：✕ 退出、已选计数、转发 / 复制 / 删除。
//
// 从 ChatPage 搬出来。四个动作全部回调给页面——转发要开选择器、复制要拼文本
// 进剪贴板、删除要弹确认框，都不是这里做得了的。
//
// 圆形胶囊的样子和 ChatHeader 的返回键同款（尺寸/圆角/阴影/玻璃都取自那边
// 导出的常量），删除键只是把图标染成红色，所以没有单独抽第三份。

const DESTRUCTIVE: ResourceColor = '#FF3B30';

@Component
export struct SelectionHeader {
  @Prop selectedCount: number;
  @Prop topSafe: number;

  onExit: () => void = (): void => {};
  onForward: () => void = (): void => {};
  onCopy: () => void = (): void => {};
  onDelete: () => void = (): void => {};

  @Styles
  actionNormalStyle() {
    .backgroundColor(overlayGlassFill('bar', $r('app.color.surface')))
    .opacity(1)
    .scale({ x: 1, y: 1 })
  }

  @Styles
  actionPressedStyle() {
    .backgroundColor(overlayGlassFill('bar', $r('app.color.surface_alt')))
    .opacity(0.72)
    .scale({ x: 0.9, y: 0.9 })
  }

  @Builder
  capsule(symbol: string, tint: ResourceColor, onTap: () => void) {
    Row() {
      SymbolGlyph($r(symbol)).fontSize(22).fontColor([tint]);
    }
    .width(CHAT_HEADER_ACTION_SIZE)
    .height(CHAT_HEADER_ACTION_SIZE)
    .borderRadius(CHAT_HEADER_RADIUS)
    .justifyContent(FlexAlign.Center)
    .shadow({ radius: 4, color: '#12000000', offsetX: 0, offsetY: 1 })
    .stateStyles({ normal: this.actionNormalStyle, pressed: this.actionPressedStyle })
    // 顶栏胶囊统一走 'bar' 档材质；低于 API 26 由 backdropBlur + 半透明底自绘。
    .backdropBlur(overlayBackdropBlur('bar'))
    .systemMaterial(overlayMaterial('bar'))
    .animation({
      duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 120),
      curve: Curve.EaseOut
    })
    .onClick((): void => { onTap(); });
  }

  build() {
    Row({ space: 8 }) {
      this.capsule('sys.symbol.xmark', COLOR_TEXT_PRIMARY, (): void => { this.onExit(); });
      Text(str('cp_selected_n', this.selectedCount))
        .fontSize(16).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT_PRIMARY)
        .layoutWeight(1).margin({ left: 6 });
      this.capsule('sys.symbol.arrowshape_turn_up_right', COLOR_TEXT_PRIMARY,
        (): void => { this.onForward(); });
      this.capsule('sys.symbol.plus_square_on_square', COLOR_TEXT_PRIMARY,
        (): void => { this.onCopy(); });
      this.capsule('sys.symbol.trash', DESTRUCTIVE, (): void => { this.onDelete(); });
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: this.topSafe + 8, bottom: 8 })
    .alignItems(VerticalAlign.Center)
    .transition(TransitionEffect.OPACITY
      .combine(TransitionEffect.translate({ y: -5 }))
      .animation({
        duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 180),
        curve: Curve.EaseOut
      }));
  }
}
