import { MessageEntry } from '../../store/MessageEntry';
import { MessageBubbleActions } from './ReusableMessageBubble';
import { PaidMediaBubble } from './PaidMediaBubble';
import { progressForOr, subscribeProgress } from '../../util/mediaProgressChannel';
import { DrawnDocumentWidget } from '../../util/drawnDocumentWidget';
import { DrawnPaidMediaLayout, paidMediaLayoutFor } from './DrawnPaidMediaLayout';

@ComponentV2
export struct DrawnPaidMediaMessage {
  @Require @Param msg: MessageEntry;
  @Require @Param actions: MessageBubbleActions;
  @Require @Param widget: DrawnDocumentWidget;
  @Param pending: boolean = false;
  @Param boxWidth: number = 262;
  @Param chatId: number = 0;
  @Local private progress: number = 0;
  private off: (() => void) | null = null;
  private generation: number = 0;
  private active: boolean = false;
  @Event onClaim: () => boolean = (): boolean => false;
  @Computed private get layout(): DrawnPaidMediaLayout | null { return paidMediaLayoutFor(this.widget); }
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
    PaidMediaBubble({ prepared: this.layout, messageId: this.msg.id, locked: this.msg.paidMediaLocked,
      mediaSet: this.msg.paidMediaSet ?? null, ownerKey: `${this.chatId}:${this.msg.rowId}`,
      starCount: this.msg.paidMediaStarCount, mediaCount: this.msg.paidMediaCount,
      mediaKind: this.msg.paidMediaKind, caption: '', photoPath: this.msg.photoPath,
      mediaReady: this.msg.paidMediaSet === undefined ? undefined : (this.msg.paidMediaSet.viewerIndices[0] ?? -1) >= 0,
      completeSet: this.msg.paidMediaSet?.complete ?? false,
      photoFileId: this.msg.photoFileId, photoProgress: this.progress, photoFailed: this.msg.photoFailed,
      pending: this.pending, maxWidth: this.boxWidth, fitAvailableWidth: true,
      onBeforeAction: (): boolean => this.active && this.onClaim(),
      onUnlock: (id: number): void => this.actions.onPaidMediaUnlock(id),
      onOpen: (id: number): void => this.actions.onPaidMediaOpen(id),
      onOpenAt: (id: number, index: number): void => this.actions.onPaidMediaOpen(id, index),
      onRetryPhoto: (id: number): void => this.actions.onSpecialPhotoRetry(id) });
  }
}
