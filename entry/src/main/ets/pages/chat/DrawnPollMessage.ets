import { MessageEntry } from '../../store/MessageEntry';
import { MessageBubbleActions } from './ReusableMessageBubble';
import { MessageBubbleContext } from './MessageBubbleShell';
import { PollBubble } from './PollBubble';
import { DrawnDocumentWidget } from '../../util/drawnDocumentWidget';
import { DrawnPollLayout, pollLayoutFor } from './DrawnPollLayout';

@ComponentV2
export struct DrawnPollMessage {
  @Require @Param msg: MessageEntry;
  @Require @Param actions: MessageBubbleActions;
  @Require @Param widget: DrawnDocumentWidget;
  @Param boxWidth: number = 262;
  @Param nowSec: number = 0;
  @Event onClaim: () => boolean = (): boolean => false;
  private context: MessageBubbleContext = new MessageBubbleContext();
  @Computed private get layout(): DrawnPollLayout | null { return pollLayoutFor(this.widget); }
  build() {
    PollBubble({ msg: this.msg, actions: this.actions, context: this.context, prepared: this.layout,
      nowSec: this.nowSec, maxWidth: this.boxWidth, fitAvailableWidth: true,
      onBeforeAction: (): boolean => this.onClaim() });
  }
}
