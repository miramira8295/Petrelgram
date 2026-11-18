import { MessageEntry } from '../../store/MessageEntry';
import { MessageBubbleActions } from './ReusableMessageBubble';
import { DiceBubble } from './DiceBubble';

@ComponentV2
export struct DrawnDiceMessage {
  @Require @Param msg: MessageEntry;
  @Require @Param actions: MessageBubbleActions;
  @Param chatId: number = 0;
  @Param boxWidth: number = 150;
  @Param selectionActive: boolean = false;
  @Event onClaim: () => boolean = (): boolean => false;
  private active: boolean = false;
  aboutToAppear(): void { this.active = true; }
  aboutToReuse(): void { this.active = true; }
  aboutToRecycle(): void { this.active = false; }
  aboutToDisappear(): void { this.active = false; }
  private canInteract(): boolean { return this.active && !this.selectionActive; }
  build() {
    DiceBubble({ emoji: this.msg.diceEmoji, value: this.msg.diceValue,
      hasFinalState: this.msg.diceHasFinalState, successFrame: this.msg.diceSuccessFrame,
      stickerPath: this.msg.stickerPath, layerPaths: this.msg.diceLayerPaths,
      playKey: `${this.chatId}:${this.msg.id}`, compact: true, animationSide: Math.max(1, Math.min(150, this.boxWidth)),
      canInteract: (): boolean => this.canInteract(),
      onBeforeOpen: (): boolean => this.onClaim(),
      onSendSame: (emoji: string): void => { if (this.canInteract()) { this.actions.onSendDice(emoji); } } });
  }
}
