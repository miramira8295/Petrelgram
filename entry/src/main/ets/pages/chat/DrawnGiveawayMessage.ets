import { MessageEntry } from '../../store/MessageEntry';
import { MessageBubbleActions } from './ReusableMessageBubble';
import { GiveawayBubble } from './GiveawayBubble';
import { DrawnDocumentWidget } from '../../util/drawnDocumentWidget';
import { DrawnGiveawayLayout, giveawayLayoutFor } from './DrawnGiveawayLayout';

@ComponentV2
export struct DrawnGiveawayMessage {
  @Param chatId: number = 0;
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
    GiveawayBubble({ audience: this.msg.giveawayAudience, ownerKey: `${this.chatId}:${this.msg.rowId}`,
      onPeer: (id: number, user: boolean): void => {
        if (user) { this.actions.onContactOpen(id, '', ''); } else { this.actions.onGiveawayChannelOpen(id); }
      }, chatId: this.chatId, prepared: this.layout, messageId: this.msg.id, state: this.msg.giveawayState,
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
