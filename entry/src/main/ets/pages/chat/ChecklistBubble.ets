import { MessageEntry } from '../../store/MessageEntry';
import { MessageBubbleActions } from './ReusableMessageBubble';
import { DrawnDocumentWidget } from '../../util/drawnDocumentWidget';
import { DrawnChecklistMessageSource } from './DrawnChecklistMessageSource';
import { DrawnChecklistMessage } from './DrawnChecklistMessage';
import { chatEnv } from '../../util/chatEnvMirror';
import { textMeasureEnvironment } from '../../util/textMeasureCache';

// Compatibility content host when the unified row renderer is disabled. It
// reuses the same prelayout/interaction island inside the existing outer shell.
@ComponentV2
export struct ChecklistBubble {
  @Require @Param msg: MessageEntry;
  @Require @Param actions: MessageBubbleActions;
  @Param chatId: number = 0;
  @Param maxWidth: number = 262;
  @Event onClaim: () => boolean = (): boolean => false;
  private env = chatEnv;
  private source: DrawnChecklistMessageSource = new DrawnChecklistMessageSource();
  @Computed private get widget(): DrawnDocumentWidget | null {
    const document = this.source.prepare(this.getUIContext(), null, this.msg, Math.max(1, this.maxWidth),
      `${this.env.appearanceEpoch}:${this.env.langEpoch}:${textMeasureEnvironment.epoch}`, this.chatId);
    return document?.blocks?.[0]?.widget ?? null;
  }
  build() {
    if (this.widget !== null) {
      DrawnChecklistMessage({ msg: this.msg, actions: this.actions, widget: this.widget,
        chatId: this.chatId, boxWidth: this.widget.width, onClaim: (): boolean => this.onClaim() });
    }
  }
}
