import { MessageEntry } from '../../store/MessageEntry';
import { MessageBubbleActions } from './ReusableMessageBubble';
import { GiveawayBubble } from './GiveawayBubble';
import { DrawnDocumentWidget } from '../../util/drawnDocumentWidget';
import { DrawnGiveawayLayout, giveawayLayoutFor } from './DrawnGiveawayLayout';

@ComponentV2
export struct DrawnGiveawayMessage {
  @Require @Param msg: MessageEntry;
  @Require @Param actions: MessageBubbleActions;
  @Require @Param widget: DrawnDocumentWidget;
  @Param boxWidth: number = 262;
  private active: boolean = false;
  aboutToAppear(): void { this.active = true; }
  aboutToReuse(): void { this.active = true; }
  aboutToRecycle(): void { this.active = false; }
  aboutToDisappear(): void { this.active = false; }
  @Event onClaim: () => boolean = (): boolean => false;
  @Computed private get layout(): DrawnGiveawayLayout | null { return giveawayLayoutFor(this.widget); }
  build() {
    GiveawayBubble({ prepared: this.layout, messageId: this.msg.id, state: this.msg.giveawayState,
      winnerCount: this.msg.giveawayWinnerCount, prize: this.msg.giveawayPrize,
      description: this.msg.giveawayDescription, selectionDate: this.msg.giveawaySelectionDate,
      unclaimedCount: this.msg.giveawayUnclaimedCount, originalMessageId: this.msg.giveawayMessageId,
      boostedChatId: this.msg.giveawayBoostedChatId, refunded: this.msg.giveawayRefunded,
      onlyNewMembers: this.msg.giveawayOnlyNewMembers, photoPath: this.msg.photoPath,
      maxWidth: this.boxWidth, fitAvailableWidth: true, fullDescription: true,
      onBeforeAction: (): boolean => this.active && this.onClaim(),
      onOpenOriginal: (chatId: number, messageId: number): void => this.actions.onGiveawayOpen(chatId, messageId) });
  }
}
