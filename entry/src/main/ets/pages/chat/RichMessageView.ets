import { TdObject } from '../../tdkit/TdTypes';
import {
  RB_DIVIDER, RB_HEADING, RB_LIST_ITEM, RB_PRE, RB_QUOTE,
  RichBlock, RichSpan, parseRichMessage
} from '../../util/richBlocks';
import { COLOR_BUBBLE_TEXT, COLOR_PRIMARY, COLOR_TEXT_SECONDARY } from '../../util/theme';

// 富文本长帖（messageRichMessage）的渲染。
//
// 单独成文件，MessageBubble 只 import 一个组件——那个文件已经很大，这类
// 自成一体的内容不该再往里塞。
//
// 和"摊平成一条文本消息"的区别：那条路只有加粗能表达层级，标题、引用、列表
// 全都退化成同一种样子。这里按块渲染，标题用字号分档、引用画竖条、列表画
// 项目符号，观感才和其它客户端对得上。

const HEADING_SIZE: number[] = [0, 19, 17, 15];   // level 1..3
const BODY_SIZE: number = 15;
const LINE_RATIO: number = 1.36;
const BLOCK_GAP: number = 8;

// P4 批 6a：迁 @ComponentV2（纯展示组件，@Prop/回调 → @Param 引用语义）。
@ComponentV2
export struct RichMessageView {
  // 原始 blocks（TdObject），在这里解析一次。放原始数据而不是解析结果，是为了
  // 让 MessageEntry 只多带一个字段，不必为块模型再引一套类型。
  @Param rawBlocks: TdObject[] = [];
  @Param maxWidth: number = 260;
  @Param onOpenUrl: (url: string) => void = (): void => {};

  private blocks(): RichBlock[] {
    const wrapper: TdObject = { '@type': 'messageRichMessage' };
    const inner: TdObject = { '@type': 'richMessage' };
    inner['blocks'] = this.rawBlocks;
    wrapper['message'] = inner;
    return parseRichMessage(wrapper);
  }

  // 一段行内文字。样式逐 span 生效，带 url 的染成主色并可点。
  @Builder
  spanText(spans: RichSpan[], size: number, weight: FontWeight, color: ResourceColor) {
    Text() {
      ForEach(spans, (s: RichSpan) => {
        Span(s.text)
          .fontSize(s.code ? size - 1 : size)
          .fontWeight(s.bold ? FontWeight.Bold : weight)
          .fontStyle(s.italic ? FontStyle.Italic : FontStyle.Normal)
          .fontColor(s.url !== '' ? COLOR_PRIMARY : color)
          .decoration({
            type: s.strike ? TextDecorationType.LineThrough
              : (s.underline || s.url !== '' ? TextDecorationType.Underline
                : TextDecorationType.None)
          })
          .fontFamily(s.code ? 'monospace' : undefined);
      }, (s: RichSpan, i: number) => `sp_${i}_${s.text.length}_${s.url}`);
    }
    .lineHeight(size * LINE_RATIO)
    .constraintSize({ maxWidth: this.maxWidth })
    .onClick((): void => {
      // 整段里只要有链接就打开第一个。逐 Span 的点击 ArkUI 不给，做不到
      // "点哪个词开哪个链接"——退而求其次好过完全不能点。
      for (const s of spans) {
        if (s.url !== '') {
          this.onOpenUrl(s.url);
          return;
        }
      }
    });
  }

  @Builder
  blockView(b: RichBlock, depth: number) {
    if (b.kind === RB_HEADING) {
      this.spanText(b.spans, HEADING_SIZE[Math.min(3, Math.max(1, b.level))],
        FontWeight.Bold, COLOR_BUBBLE_TEXT);
    } else if (b.kind === RB_DIVIDER) {
      Divider().color(COLOR_TEXT_SECONDARY).opacity(0.3).strokeWidth(0.6)
        .margin({ top: 2, bottom: 2 });
    } else if (b.kind === RB_PRE) {
      Column() {
        this.spanText(b.spans, BODY_SIZE - 1, FontWeight.Normal, COLOR_BUBBLE_TEXT);
      }
      .padding(8)
      .borderRadius(8)
      .backgroundColor($r('app.color.surface_alt'))
      .constraintSize({ maxWidth: this.maxWidth });
    } else if (b.kind === RB_QUOTE) {
      Column({ space: 4 }) {
        ForEach(b.children, (c: RichBlock, i: number) => {
          this.blockView(c, depth + 1);
        }, (c: RichBlock, i: number) => `q_${depth}_${i}_${c.kind}`);
      }
      .alignItems(HorizontalAlign.Start)
      .padding({ left: 8, top: 2, bottom: 2 })
      .border({ width: { left: 2 }, color: COLOR_PRIMARY })
      .constraintSize({ maxWidth: this.maxWidth });
    } else if (b.kind === RB_LIST_ITEM) {
      Row({ space: 6 }) {
        Text(b.marker)
          .fontSize(BODY_SIZE).lineHeight(BODY_SIZE * LINE_RATIO)
          .fontColor(COLOR_TEXT_SECONDARY);
        Column({ space: 2 }) {
          ForEach(b.children, (c: RichBlock, i: number) => {
            this.blockView(c, depth + 1);
          }, (c: RichBlock, i: number) => `li_${depth}_${i}_${c.kind}`);
        }.alignItems(HorizontalAlign.Start).layoutWeight(1);
      }
      .alignItems(VerticalAlign.Top)
      .constraintSize({ maxWidth: this.maxWidth });
    } else {
      this.spanText(b.spans, BODY_SIZE, FontWeight.Normal, COLOR_BUBBLE_TEXT);
    }
  }

  build() {
    Column({ space: BLOCK_GAP }) {
      ForEach(this.blocks(), (b: RichBlock, i: number) => {
        this.blockView(b, 0);
      }, (b: RichBlock, i: number) => `rb_${i}_${b.kind}_${b.level}`);
    }
    .alignItems(HorizontalAlign.Start)
    .constraintSize({ maxWidth: this.maxWidth });
  }
}
