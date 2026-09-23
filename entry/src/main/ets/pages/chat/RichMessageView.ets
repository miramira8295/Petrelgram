import { TdObject } from '../../tdkit/TdTypes';
import {
  RB_DIVIDER, RB_HEADING, RB_LIST_ITEM, RB_PRE, RB_QUOTE, RB_TABLE,
  RichBlock, RichCell, RichSpan, parseRichMessage
} from '../../util/richBlocks';
import {
  MathImage, ensureMathImage, mathForegroundColor, mathImageFor, mathKeyOf
} from '../../util/mathImageCache';
import { copyPlainText } from '../../util/clipboard';
import { str } from '../../util/strings';
import { tableColumnWidths, tableContentWidth } from '../../util/tableLayout';
import { setTableScrollTouch } from '../../util/tableTouchChannel';
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
// 表格用的字号和格内左右内边距。内边距要和 util/tableLayout 的
// TABLE_CELL_PAD_VP（左右合计）对得上，否则算出来的列宽装不下文字。
// 公式按 3 倍字号排版、按 1/3 显示：直接按字号排在高分屏上会糊。
const MATH_SUPERSAMPLE: number = 3;
const CELL_SIZE: number = 14;
const CELL_PAD: number = 10;
// 表格线。**不用 app.color.divider**：那是给列表分割线调的，压在气泡底色上
// 几乎看不见（用户实报「边框不清晰」）。这里用带透明度的中性灰，深浅两种
// 气泡底上都读得出来，又不至于喧宾夺主。
const TABLE_BORDER: string = '#8C6E7887';
// 表头底色：比斑马纹重一档，让第一行一眼能认出来。
const TABLE_HEADER_BG: string = '#22808A96';

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

  // 公式排好之后要重绘，而位图存在模块级缓存里、组件订阅不了它。
  // 每排好一条就 +1，build 里读它一次就建立了依赖。
  @Local private mathEpoch: number = 0;

  // 超采样倍率：按 3 倍字号排版、按 1/3 显示，否则高分屏上公式发糊。
  private mathImageOf(expr: string, size: number): MathImage | undefined {
    const rendered: number = size * MATH_SUPERSAMPLE;
    const color: number = mathForegroundColor();
    const key: string = mathKeyOf(expr.trim(), rendered, color);
    const hit: MathImage | undefined = mathImageFor(key);
    if (hit !== undefined) {
      return hit;
    }
    // 读一下纪元，让这个节点订阅"又排好了一条"。
    if (this.mathEpoch >= 0) {
      ensureMathImage(expr, rendered, color, (): void => { this.mathEpoch++; });
    }
    return undefined;
  }

  // 一段行内文字。样式逐 span 生效，带 url 的染成主色并可点。
  @Builder
  spanText(spans: RichSpan[], size: number, weight: FontWeight, color: ResourceColor) {
    Text() {
      ForEach(spans, (s: RichSpan) => {
        // 公式排好了就贴图（ImageSpan 能嵌在 Text 里，行内公式要的正是这个）；
        // 还没排好、或者公式本身有语法错，退回等宽显示 LaTeX 原文——比空着强。
        if (s.math && this.mathImageOf(s.text, size) !== undefined) {
          ImageSpan(this.mathImageOf(s.text, size)!.pixel)
            .width(this.mathImageOf(s.text, size)!.width / MATH_SUPERSAMPLE)
            .height(this.mathImageOf(s.text, size)!.height / MATH_SUPERSAMPLE)
            .verticalAlign(ImageSpanAlignment.CENTER)
            .objectFit(ImageFit.Contain);
        } else {
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
        }
      }, (s: RichSpan, i: number) => `sp_${i}_${s.text.length}_${s.url}_${s.math ? 1 : 0}`);
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

  // 一次 build 内的列宽缓存。blocks() 每次 build 都重新解析、产出新的块对象，
  // 所以**按对象身份**缓存正好：同一帧里每个格子都拿到同一份，跨帧自然失效。
  // 不缓存的话 4x3 的表要把列宽算 13 遍（每格一遍 + 判要不要可滚一遍）。
  private widthsFor: RichBlock | null = null;
  private widthsCache: number[] = [];

  // 表格每列多宽。判据是纯函数（util/tableLayout），这里只把每格的**纯文本**
  // 摊出来喂给它。
  private tableWidths(b: RichBlock): number[] {
    if (this.widthsFor === b) {
      return this.widthsCache;
    }
    const text: string[][] = b.rows.map((row: RichCell[]): string[] =>
      row.map((c: RichCell): string => c.spans.map((s: RichSpan): string => s.text).join('')));
    this.widthsCache = tableColumnWidths(text, CELL_SIZE);
    this.widthsFor = b;
    return this.widthsCache;
  }

  // 表格够宽才让它可滚；不超宽却挂着横向 Scroll，会白白和整行的左滑回复抢手势。
  private tableScrollable(b: RichBlock): boolean {
    return tableContentWidth(this.tableWidths(b)) > this.maxWidth;
  }

  // 表头一档、斑马纹一档、其余透明。表头不参与隔行计数。
  private rowBackground(b: RichBlock, ri: number): ResourceColor {
    if (ri === 0 && b.rows.length > 0 && b.rows[0].some((c: RichCell): boolean => c.header)) {
      return TABLE_HEADER_BG;
    }
    return b.striped && ri > 0 && ri % 2 === 0
      ? $r('app.color.surface_alt') : Color.Transparent;
  }

  private cellTextAlign(align: string): TextAlign {
    if (align === 'center') {
      return TextAlign.Center;
    }
    return align === 'right' ? TextAlign.End : TextAlign.Start;
  }

  // 一格。**外面必须包一层能被拉伸的容器**：竖分隔线画在这一层上，而 Text 的
  // 高度只等于它自己的文字高度——同一行里别的格子更高时，画在 Text 上的竖线
  // 就只有那么一小段，看着就是「表格线没接上」（用户 2026-09-22 实报）。
  // 行改用 Flex + ItemAlign.Stretch 之后，这一层会被撑到整行高，线才连得上。
  @Builder
  tableCell(cell: RichCell, width: number, bordered: boolean, lastCol: boolean) {
    Column() {
    Text() {
      ForEach(cell.spans, (s: RichSpan) => {
        Span(s.text)
          .fontSize(s.code ? CELL_SIZE - 1 : CELL_SIZE)
          .fontWeight(cell.header || s.bold ? FontWeight.Bold : FontWeight.Normal)
          .fontStyle(s.italic ? FontStyle.Italic : FontStyle.Normal)
          .fontColor(s.url !== '' ? COLOR_PRIMARY : COLOR_BUBBLE_TEXT)
          .decoration({
            type: s.strike ? TextDecorationType.LineThrough
              : (s.underline || s.url !== '' ? TextDecorationType.Underline
                : TextDecorationType.None)
          })
          .fontFamily(s.code ? 'monospace' : undefined);
      }, (s: RichSpan, i: number) => `tc_${i}_${s.text.length}_${s.url}`);
    }
    .width('100%')
    .textAlign(this.cellTextAlign(cell.align))
    .lineHeight(CELL_SIZE * LINE_RATIO);
    }
    .width(width)
    // flexShrink 在 Flex 容器里默认是 1——不钉成 0，表格一超宽每列就被压扁，
    // 「超宽横滑」当场失效。
    .flexShrink(0)
    .alignItems(HorizontalAlign.Start)
    .justifyContent(FlexAlign.Start)
    .padding({ left: CELL_PAD, right: CELL_PAD, top: 6, bottom: 6 })
    // 竖分隔线画在每格右侧，最后一列不画（外框由整表那一层负责）。
    .border(bordered && !lastCol
      ? { width: { right: 1 }, color: TABLE_BORDER }
      : { width: 0 });
  }

  // 表格。**气泡宽度优先**：表格从不把气泡撑宽，内容超了在气泡里横滑。
  //
  // 只有**真的超宽**时才让它可滚——不超宽却挂着一个横向 Scroll，会和气泡
  // 整行那个 parallelGesture 的横向 PanGesture（左滑回复 / 右滑多选）抢手势，
  // 白白把回复手势在表格这块废掉。
  @Builder
  tableView(b: RichBlock) {
    Column({ space: 4 }) {
      Scroll() {
        Column() {
          ForEach(b.rows, (row: RichCell[], ri: number) => {
            // Row 没有「拉伸」这档对齐（VerticalAlign 只有 Top/Center/Bottom），
            // 所以用 Flex + ItemAlign.Stretch：每格被撑到整行高，竖线才连得上。
            // Flex 比 Row 多一趟布局，但表格少见、格子也少，代价可以忽略。
            Flex({ direction: FlexDirection.Row, alignItems: ItemAlign.Stretch }) {
              ForEach(row, (cell: RichCell, ci: number) => {
                this.tableCell(cell, this.tableWidths(b)[ci] ?? 0,
                  b.bordered, ci === row.length - 1);
              }, (cell: RichCell, ci: number) => `td_${ri}_${ci}`);
            }
            // 每行都铺满内容总宽：行宽不一致时底部那条横线长短不一，也接不上。
            .width(tableContentWidth(this.tableWidths(b)))
            // 斑马纹跳过表头那一行，从第一条数据开始隔行。
            .backgroundColor(this.rowBackground(b, ri))
            .border(b.bordered && ri !== b.rows.length - 1
              ? { width: { bottom: 1 }, color: TABLE_BORDER }
              : { width: 0 });
          }, (row: RichCell[], ri: number) => `tr_${ri}_${row.length}`);
        }
        .alignItems(HorizontalAlign.Start);
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .align(Alignment.TopStart)
      .enableScrollInteraction(this.tableScrollable(b))
      .constraintSize({ maxWidth: this.maxWidth })
      // 外框比格线重一档：气泡底色本身就浅，0.5px 的 divider 压上去几乎看不见
      // （用户 2026-09-22：「表格边框不清晰」）。
      .border({ width: 1, color: TABLE_BORDER, radius: 8 })
      .clip(true)
      // 手指压在能横滑的表格上时，让整行的左滑回复/右滑多选让路。
      // 那条是 parallelGesture，只能靠这个旁路标记，见 util/tableTouchChannel。
      .onTouch((event: TouchEvent): void => {
        if (!this.tableScrollable(b)) {
          return;
        }
        if (event.type === TouchType.Down) {
          setTableScrollTouch(true);
        } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
          setTableScrollTouch(false);
        }
      });
      if (b.spans.length > 0) {
        this.spanText(b.spans, CELL_SIZE - 1, FontWeight.Normal, COLOR_TEXT_SECONDARY);
      }
    }
    .alignItems(HorizontalAlign.Start)
    .constraintSize({ maxWidth: this.maxWidth });
  }

  // 代码块表头。语言由源提供（pageBlockPreformatted.language），常常是空串。
  // 「code」是技术标签不是正文，不进资源表。
  private codeHeader(b: RichBlock): string {
    const lang: string = b.language.trim();
    return lang === '' ? 'code' : `code: ${lang}`;
  }

  // 代码块的原文。拼的是 span 的 text 而不是渲染结果：要拿走的是代码本身，
  // 不带任何格式标记。
  private copyCode(b: RichBlock): void {
    copyPlainText(b.spans.map((s: RichSpan): string => s.text).join(''),
      $r('app.string.copied'));
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
      // 代码块：一行表头（语言 + 复制）压在代码上方。
      //
      // 【为什么整块钉死宽度，而不是只给 constraintSize】表头要"语言靠左、复制
      // 靠右"，靠的是 layoutWeight —— 它要求父容器有**确定的宽度**。只给
      // constraintSize 时容器按内容撑，表头里的 width('100%') 解不出来，复制
      // 按钮被压成 0 宽、整个看不见（2026-09-23 第一版就是这么丢的）。
      // 代码块本来也该占满气泡宽度。
      Column({ space: 4 }) {
        Row() {
          Text(this.codeHeader(b))
            .fontSize(BODY_SIZE - 3).fontColor(COLOR_TEXT_SECONDARY)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1);
          // 复制的是**这一段代码**；气泡长按菜单里那个"复制"复制的是整条消息，
          // 两者不是一回事。
          Row() {
            SymbolGlyph($r('sys.symbol.square_on_square_fill'))
              .fontSize(15).fontColor([COLOR_TEXT_SECONDARY]);
          }
          .width(28).height(28).borderRadius(14)
          .justifyContent(FlexAlign.Center)
          .accessibilityText(str('copy'))
          .onClick((): void => { this.copyCode(b); });
        }
        .width('100%')
        .alignItems(VerticalAlign.Center);
        this.spanText(b.spans, BODY_SIZE - 1, FontWeight.Normal, COLOR_BUBBLE_TEXT);
      }
      .alignItems(HorizontalAlign.Start)
      .width(this.maxWidth)
      .padding({ left: 8, right: 4, top: 4, bottom: 8 })
      .borderRadius(8)
      // 整段代码块和行内代码同一套底色：叠加层，不是不透明底。
      .backgroundColor($r('app.color.code_surface'));
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
    } else if (b.kind === RB_TABLE) {
      this.tableView(b);
    } else if (b.kind === RB_LIST_ITEM) {
      Row({ space: 6 }) {
        // 任务列表：源里 pageBlockListItem 自带 has_checkbox / is_checked，
        // 画成勾选框而不是圆点（不去解析 `- [x]` 那种文本前缀）。
        if (b.hasCheckbox) {
          SymbolGlyph($r(b.checked
            ? 'sys.symbol.checkmark_square_fill' : 'sys.symbol.square'))
            .fontSize(BODY_SIZE + 2)
            .fontColor([b.checked ? COLOR_PRIMARY : COLOR_TEXT_SECONDARY]);
        } else {
          Text(b.marker)
            .fontSize(BODY_SIZE).lineHeight(BODY_SIZE * LINE_RATIO)
            .fontColor(COLOR_TEXT_SECONDARY);
        }
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
