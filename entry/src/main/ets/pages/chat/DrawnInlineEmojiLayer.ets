import { MessageEntry } from '../../store/MessageEntry';
import { DrawnRichTextLayout } from './DrawnRichTextLayout';
import { DrawnInlineEmojiPainter } from './DrawnInlineEmojiPainter';

// One drawing node for all inline custom emoji. Bitmap completion invalidates
// only this modifier; it never changes @Local state or rebuilds the message row.
@ComponentV2
export struct DrawnInlineEmojiLayer {
  @Param plan: DrawnRichTextLayout | null = null;
  @Require @Param msg: MessageEntry;
  private painter: DrawnInlineEmojiPainter = new DrawnInlineEmojiPainter();
  private attached: boolean = false;

  aboutToAppear(): void { this.attached = true; this.sync(); }
  aboutToDisappear(): void { this.attached = false; this.painter.dispose(); }

  @Monitor('plan', 'msg')
  sync(): void {
    if (this.attached) {
      this.painter.bind(this.getUIContext(), this.plan, this.msg.inlineCustomEmojiIds,
        this.msg.inlineCustomEmojiPaths, this.msg.inlineCustomEmojiRepaint);
    }
  }

  build() {
    Row().width(this.plan?.widthVp ?? 0).height(this.plan?.heightVp ?? 0)
      .drawModifier(this.painter).hitTestBehavior(HitTestMode.None).accessibilityLevel('no');
  }
}
