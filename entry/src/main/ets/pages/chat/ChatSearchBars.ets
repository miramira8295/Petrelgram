import { COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_ICON_SECONDARY, COLOR_TEXT_SECONDARY } from '../../util/theme';
import { KEY_POWER_SMOOTH_TRANSITIONS, powerAnimationDuration } from '../../store/AppSettings';
import {
  SEARCH_LABEL_COUNTER, SEARCH_LABEL_NONE,
  canStepNewer, canStepOlder, searchCounterText, searchLabelKind
} from '../../util/searchPaging';
import { CHAT_SEARCH_HEADER_BASE_HEIGHT } from '../../util/ChatChromeGeometry';

// 会话内搜索的两条：顶上的输入框、底下的计数与上下翻。
//
// 从 ChatPage 搬出来。搜索态下这两条**同时**替换掉常规顶栏和输入区，是同一个
// 特性的两半，所以放一个文件里。
//
// 全部动作回调给页面：翻页要碰 TDLib 分页、跳转要碰 scroller 和高亮。
// 翻页决策与两个箭头的亮灭在 util/searchPaging（有单测）。

@Component
export struct SearchHeader {
  @Prop query: string;
  @Prop topSafe: number;

  onExit: () => void = (): void => {};
  onQueryChange: (value: string) => void = (): void => {};
  onSubmit: () => void = (): void => {};

  @Styles
  rowNormalStyle() {
    .backgroundColor(Color.Transparent)
    .opacity(1)
  }

  @Styles
  rowPressedStyle() {
    .backgroundColor($r('app.color.surface_alt'))
    .opacity(0.68)
  }

  build() {
    Row({ space: 4 }) {
      Row() {
        SymbolGlyph($r('sys.symbol.chevron_left'))
          .fontSize(22).fontColor([COLOR_TEXT_PRIMARY]);
      }
      .width(40).height(40)
      .borderRadius(20)
      .justifyContent(FlexAlign.Center)
      .stateStyles({ normal: this.rowNormalStyle, pressed: this.rowPressedStyle })
      .animation({
        duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 110),
        curve: Curve.EaseOut
      })
      .onClick((): void => { this.onExit(); })
      .accessibilityText($r('app.string.cp_back_to_chat'));
      TextInput({ text: this.query, placeholder: $r('app.string.cp_search_messages') })
        .layoutWeight(1).height(40).fontSize(16)
        .backgroundColor(Color.Transparent).padding(0).borderRadius(0)
        .placeholderColor(COLOR_TEXT_SECONDARY)
        .caretColor(COLOR_PRIMARY)
        .enterKeyType(EnterKeyType.Search)
        .defaultFocus(true)
        .onChange((v: string): void => { this.onQueryChange(v); })
        .onSubmit((): void => { this.onSubmit(); });
      if (this.query !== '') {
        Row() {
          SymbolGlyph($r('sys.symbol.xmark_circle'))
            .fontSize(19).fontColor([COLOR_ICON_SECONDARY]);
        }
        .width(34).height(34)
        .borderRadius(17)
        .justifyContent(FlexAlign.Center)
        .stateStyles({ normal: this.rowNormalStyle, pressed: this.rowPressedStyle })
        .animation({
          duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 110),
          curve: Curve.EaseOut
        })
        .onClick((): void => { this.onQueryChange(''); })
        .accessibilityText($r('app.string.clear_search'));
      }
    }
    .width('calc(100% - 24vp)').height(CHAT_SEARCH_HEADER_BASE_HEIGHT - 16)
    .padding({ left: 3, right: 6 })
    .margin({ left: 12, right: 12, top: this.topSafe + 8, bottom: 8 })
    .backgroundColor($r('app.color.surface'))
    .border({ width: 0.5, color: $r('app.color.divider') })
    .borderRadius(23)
    .shadow({ radius: 5, color: '#16000000', offsetX: 0, offsetY: 1 })
    .alignItems(VerticalAlign.Center)
    .transition(TransitionEffect.OPACITY
      .combine(TransitionEffect.translate({ y: -5 }))
      .animation({
        duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 180),
        curve: Curve.EaseOut
      }));
  }
}

@Component
export struct SearchBottomBar {
  @Prop query: string;
  @Prop loadedCount: number;
  @Prop total: number;
  @Prop currentIndex: number;
  // 输入区底部让出的高度，由页面按键盘/抽屉状态算好传进来。
  @Prop bottomGap: number;

  onOlder: () => void = (): void => {};
  onNewer: () => void = (): void => {};

  @Builder
  label() {
    // 三种情形分开：有结果显示计数；查过了没结果显示空白（提示语再挂着会像
    // 没反应过）；还没查才显示提示语。
    if (searchLabelKind(this.loadedCount, this.total, this.query) === SEARCH_LABEL_COUNTER) {
      Text(searchCounterText(this.currentIndex, this.total))
        .fontSize(15).fontColor(COLOR_TEXT_PRIMARY);
    } else if (searchLabelKind(this.loadedCount, this.total, this.query) === SEARCH_LABEL_NONE) {
      Text('').fontSize(15).fontColor(COLOR_TEXT_PRIMARY);
    } else {
      Text($r('app.string.cp_search_placeholder'))
        .fontSize(15).fontColor(COLOR_TEXT_PRIMARY);
    }
  }

  build() {
    Row() {
      this.label();
      Blank().layoutWeight(1);
      if (this.loadedCount > 0) {
        Row() {
          SymbolGlyph($r('sys.symbol.chevron_up')).fontSize(22).fontColor([COLOR_TEXT_PRIMARY]);
        }
        .width(42).height(42).justifyContent(FlexAlign.Center)
        .opacity(canStepOlder(this.loadedCount, this.currentIndex, this.total) ? 1 : 0.4)
        .onClick((): void => { this.onOlder(); });
        Row() {
          SymbolGlyph($r('sys.symbol.chevron_down')).fontSize(22).fontColor([COLOR_TEXT_PRIMARY])
            .symbolEffect(new BounceSymbolEffect(EffectScope.WHOLE, EffectDirection.DOWN), true);
        }
        .width(42).height(42).justifyContent(FlexAlign.Center)
        .opacity(canStepNewer(this.currentIndex) ? 1 : 0.4)
        .onClick((): void => { this.onNewer(); });
      }
    }
    .width('100%').height(52 + this.bottomGap)
    .padding({ left: 20, right: 10, bottom: this.bottomGap })
    .alignItems(VerticalAlign.Center)
    .backgroundColor($r('app.color.surface'))
    .border({ width: { top: 0.7 }, color: $r('app.color.divider') });
  }
}
