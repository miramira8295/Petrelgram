import { MessageEntry } from '../../store/MessageEntry';
import { MessageBubbleActions } from './ReusableMessageBubble';
import { GameBubble } from './GameBubble';
import { progressForOr, subscribeProgress } from '../../util/mediaProgressChannel';
import { DrawnDocumentWidget } from '../../util/drawnDocumentWidget';
import { DrawnGameLayout, gameLayoutFor } from './DrawnGameLayout';

@ComponentV2
export struct DrawnGameMessage {
  @Param chatId: number = 0;
  @Require @Param msg: MessageEntry;
  @Require @Param actions: MessageBubbleActions;
  @Require @Param widget: DrawnDocumentWidget;
  @Param boxWidth: number = 262;
  @Local private progress: number = 0;
  private off: (() => void) | null = null;
  private generation: number = 0;
  private active: boolean = false;
  @Event onClaim: () => boolean = (): boolean => false;
  @Computed private get layout(): DrawnGameLayout | null { return gameLayoutFor(this.widget); }
  @Computed private get sourceIdentity(): string { return `${this.msg.rowId}:${this.msg.photoFileId}`; }
  private detach(): void { this.generation++; this.off?.(); this.off = null; }
  private bind(): void {
    this.detach();
    this.progress = progressForOr(this.msg.photoFileId, this.msg.photoProgress);
    if (!this.active) { return; }
    const owner = this.generation;
    this.off = subscribeProgress(this.msg.photoFileId, (progress: number): void => {
      if (owner === this.generation && this.progress !== progress) { this.progress = progress; }
    });
  }
  @Monitor('sourceIdentity') private sourceChanged(): void { this.bind(); }
  aboutToAppear(): void { this.active = true; this.bind(); }
  aboutToReuse(): void { this.active = true; this.bind(); }
  aboutToRecycle(): void { this.active = false; this.detach(); }
  aboutToDisappear(): void { this.aboutToRecycle(); }

  build() {
    GameBubble({ chatId: this.chatId, richMessage: this.msg, prepared: this.layout,
      messageId: this.msg.id, title: this.msg.gameTitle, shortName: this.msg.gameShortName,
      description: this.msg.gameDescription, gameText: this.msg.gameText, photoPath: this.msg.photoPath,
      photoFileId: this.msg.photoFileId, photoProgress: this.progress, photoFailed: this.msg.photoFailed,
      maxWidth: this.boxWidth, fitAvailableWidth: true,
      onBeforeAction: (): boolean => this.active && this.onClaim(),
      onLink: (url: string, hidesUrl: boolean): void => this.actions.onLinkTap(url, hidesUrl),
      onOpen: (id: number): void => this.actions.onGameOpen(id),
      onRetryPhoto: (id: number): void => this.actions.onGamePhotoRetry(id) });
  }
}
