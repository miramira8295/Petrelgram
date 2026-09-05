import { COLOR_TEXT_PRIMARY } from '../../util/theme';
import { CHAT_HEADER_ACTION_SIZE, CHAT_HEADER_RADIUS } from './ChatHeader';
import { KEY_POWER_SMOOTH_TRANSITIONS, powerAnimationDuration } from '../../store/AppSettings';
import { overlayBackdropBlur, overlayGlassFill } from '../../util/overlayMaterial';
import { materialModifier } from '../../util/materialModifier';
import { str } from '../../util/strings';
import { CHAT_HEADER_BASE_HEIGHT } from '../../util/ChatChromeGeometry';

// 多选态的顶栏：✕ 退出、已选计数、转发 / 复制 / 删除。
//
// 从 ChatPage 搬出来。四个动作全部回调给页面——转发要开选择器、复制要拼文本
// 进剪贴板、删除要弹确认框，都不是这里做得了的。
//
// 圆形胶囊的样子和 ChatHeader 的返回键同款（尺寸/圆角/阴影/玻璃都取自那边
// 导出的常量），删除键只是把图标染成红色，所以没有单独抽第三份。

const DESTRUCTIVE: ResourceColor = '#FF3B30';

// 状态管理 V2（B2 批）。迁的理由不在本层的性能：V1 的 @Component 既不能声明
// @Param、也订阅不了 @ObservedV2 对象的 @Trace，而后续批次要把多选态收进一个
// SelectionSession 控制器、让这个宿主自己在 build() 里直读它——不先换体系就无从
// 谈起。本次迁移本身零行为变更。
@ComponentV2
export struct SelectionHeader {
  // 材质档位（厚度/光感）改变时重绘。overlayMaterial 是 util，订阅不了
  // AppStorage，只能由调用方订阅，同 LANGUAGE_EPOCH 的做法。
  // B2 迁移时更正：V2 没有 @StorageProp / @StorageLink 的等价物，改由 ChatPage
  // 透传（页面自己就持有这个纪元，来自 V1 外壳 ChatPageEntry 的订阅）。
  // 去掉了 private：@Param 要由父组件构造传参。
  @Param materialEpoch: number = 0;
  // @Prop → @Param：V1 的 @Prop 对复杂类型是深拷贝、@Param 是引用传递，这两个
  // 都是 number，两者等价。本组件内部一处也没写过它们，所以不需要 @Once。
  @Param selectedCount: number = 0;
  @Param topSafe: number = 0;

  // @Event 而不是 @Param：调用点传的是内联箭头函数，页面每重建一次都是新闭包，
  // @Param 的 `!==` 恒不相等会让本层白刷一遍。@Event 不具备观测能力，正好复现
  // 迁移前普通字段的行为。空实现默认值保留，让组件能脱离父组件独立预览。
  @Event onExit: () => void = (): void => {};
  @Event onForward: () => void = (): void => {};
  @Event onCopy: () => void = (): void => {};
  @Event onDelete: () => void = (): void => {};

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
    .attributeModifier(materialModifier('bar'))
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
    .height(this.topSafe + CHAT_HEADER_BASE_HEIGHT)
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
