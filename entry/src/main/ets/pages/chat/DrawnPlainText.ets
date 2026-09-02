// 自绘纯文本节点（绘制面刀 2 骨架，survey：
// docs/superpowers/specs/2026-09-02-draw-plane-survey.md）。
//
// 定高 Column + DrawModifier：高度/宽度来自 util/paragraphCache 里我们自己
// 的排版结果，ArkUI 布局阶段对这段文本零测量；绘制阶段把缓存的 Paragraph
// 直接 paint 到节点画布上。复用（@Param 换内容）时排版走缓存，命中即零
// 重排。
//
// ⚠️ 尚无调用方（编译期默认不接线）：排版一致性、DrawModifier 在复用节点
// 上的重绘时机、无障碍朗读都要真机 spike 后才放开。只接无实体、无链接的
// 纯文本；paragraph 为 null（排版失败）时渲染空节点，调用方应在上游就回退
// ArkUI Text 路径。
import { DrawContext } from '@kit.ArkUI';
import { PlainParagraph, plainParagraphFor } from '../../util/paragraphCache';

class PlainParagraphModifier extends DrawModifier {
  laid: PlainParagraph | null = null;

  drawFront(context: DrawContext): void {
    const laid = this.laid;
    if (laid !== null && laid.paragraph !== null) {
      laid.paragraph.paint(context.canvas, 0, 0);
    }
  }
}

@ComponentV2
export struct DrawnPlainText {
  @Param content: string = '';
  @Param maxWidthVp: number = 100;
  @Param fontSizeVp: number = 16;
  @Param colorArgb: number = 0xE6000000;
  private modifier: PlainParagraphModifier = new PlainParagraphModifier();

  // 复用路径：@Param 在 aboutToReuse 时已是新值（批 0.5 判读），同步换排版
  // 并催一次重绘即可。非复用路径的内容变化（编辑）走 @Monitor 同款处理。
  private relayout(): PlainParagraph {
    const laid: PlainParagraph = plainParagraphFor(
      this.content, this.maxWidthVp, this.fontSizeVp, this.colorArgb);
    if (this.modifier.laid !== laid) {
      this.modifier.laid = laid;
      this.modifier.invalidate();
    }
    return laid;
  }

  @Monitor('content', 'maxWidthVp', 'fontSizeVp', 'colorArgb')
  onTextChanged(): void {
    this.relayout();
  }

  aboutToReuse(): void {
    this.relayout();
  }

  build() {
    Column()
      .width(this.relayout().widthVp)
      .height(this.relayout().heightVp)
      .drawModifier(this.modifier)
      .accessibilityText(this.content);
  }
}
