import { COLOR_PRIMARY, COLOR_ICON_SECONDARY, COLOR_TEXT_SECONDARY } from '../../util/theme';
import { KEY_POWER_SMOOTH_TRANSITIONS, powerAnimationDuration } from '../../store/AppSettings';
import { str } from '../../util/strings';

// 输入框上方那一条：正在编辑某条，或正在回复某条。两者共用同一个位置，
// 不可能同时出现（util/composerMode 的状态机保证，有单测）。
//
// 从 ChatPage 搬出来。它们贴在输入卡的内部，自己不画背景/边框/分隔线，
// 整个输入区因此读起来是一块连续的面。
//
// 注意两条并不对称，这是原样保留的既有行为，不是这次改出来的：
//   - 编辑条固定高 44，回复条用上下 padding 撑；
//   - 回复条的 ✕ 有按压反馈和入场动画，编辑条的没有；
//   - 回复条的文字区可点（跳到被引用的消息），编辑条的不可点。
// 想统一的话是另一件事，得先想清楚点编辑条应该跳到哪里。

@Component
export struct EditStrip {
  // 'caption' 时标题是"编辑说明"，否则是"编辑消息"。
  @Prop editingKind: string;
  @Prop preview: string;

  onCancel: () => void = (): void => {};

  build() {
    Row({ space: 10 }) {
      Row().width(3).height(34).borderRadius(2).backgroundColor(COLOR_PRIMARY);
      Column({ space: 1 }) {
        Text(this.editingKind === 'caption'
          ? $r('app.string.mb_edit_caption') : $r('app.string.cp_edit_message'))
          .fontSize(13).fontColor(COLOR_PRIMARY).fontWeight(FontWeight.Medium);
        Text(this.preview).fontSize(13).fontColor(COLOR_TEXT_SECONDARY)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
      }
      .alignItems(HorizontalAlign.Start).layoutWeight(1);
      Row() {
        SymbolGlyph($r('sys.symbol.xmark')).fontSize(16).fontColor([COLOR_ICON_SECONDARY]);
      }
      .width(32).height(32).borderRadius(16)
      .justifyContent(FlexAlign.Center)
      .onClick((): void => { this.onCancel(); });
    }
    .width('100%').height(44).padding({ left: 12, right: 8 });
  }
}

@Component
export struct ReplyStrip {
  @Prop name: string;
  @Prop snippet: string;
  // 入场动画时长由页面按省电分组算好传进来（chatEffectDuration）。
  @Prop enterDuration: number;

  onTapQuote: () => void = (): void => {};
  onCancel: () => void = (): void => {};

  @Styles
  closeNormalStyle() {
    .backgroundColor(Color.Transparent)
    .opacity(1)
    .scale({ x: 1, y: 1 })
  }

  @Styles
  closePressedStyle() {
    .backgroundColor($r('app.color.surface_alt'))
    .opacity(0.76)
    .scale({ x: 0.985, y: 0.96 })
  }

  build() {
    Row({ space: 10 }) {
      Row().width(3).height(34).borderRadius(2).backgroundColor(COLOR_PRIMARY);
      Column({ space: 1 }) {
        Text(`${str('mb_reply')} ${this.name}`)
          .fontSize(13).fontColor(COLOR_PRIMARY).fontWeight(FontWeight.Medium)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
        Text(this.snippet).fontSize(13).fontColor(COLOR_TEXT_SECONDARY)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
      }
      .alignItems(HorizontalAlign.Start).layoutWeight(1)
      .onClick((): void => { this.onTapQuote(); });
      Row() {
        SymbolGlyph($r('sys.symbol.xmark')).fontSize(16).fontColor([COLOR_ICON_SECONDARY]);
      }
      .width(32).height(32).borderRadius(16)
      .justifyContent(FlexAlign.Center)
      .stateStyles({ normal: this.closeNormalStyle, pressed: this.closePressedStyle })
      .animation({
        duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 110),
        curve: Curve.EaseOut
      })
      .onClick((): void => { this.onCancel(); });
    }
    .width('100%').padding({ left: 16, right: 16, top: 7, bottom: 7 })
    .alignItems(VerticalAlign.Center)
    .transition(
      TransitionEffect.translate({ y: 12 })
        .combine(TransitionEffect.OPACITY)
        .animation({ duration: this.enterDuration, curve: Curve.EaseOut })
    );
  }
}
