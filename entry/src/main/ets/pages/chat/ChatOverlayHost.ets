import { MessageEntry } from '../../store/MessageEntry';
import { ChatOverlayState } from './ChatOverlayState';
import { ReactionSheet } from './ReactionSheet';
import { ForwardSheet } from './ForwardSheet';
import { ScheduledSheet } from './ScheduledSheet';
import { PollComposeSheet } from './PollComposeSheet';
import { ContactPickerSheet, PickedContact } from './ContactPickerSheet';
import { VideoNoteRecorderView } from './VideoNoteRecorderView';

// Presentation host for the transient chat overlays. ChatPage retains the
// state and business actions; this component only wires values and events into
// the existing sheets.
//
// 【B11】showReactionSheet/showForwardSheet/showScheduledSheet/showPollSheet/
// showContactSheet/showVideoNoteRecorder/reactionTargetId/reactionPendingKey/
// forwardMessageIds 这 9 个标量 @Param 收口成一个 @Require @Param
// overlayState: ChatOverlayState——组件内所有读点相应改成 this.overlayState.xxx。
// messages/chatId/threadRootId/bottomSafe/keyboardH 不属于 overlay 簇（页面
// 持有的会话级/视口状态），原样保留标量 @Param。
@ComponentV2
export struct ChatOverlayHost {
  @Require @Param overlayState: ChatOverlayState;

  @Param messages: MessageEntry[] = [];
  @Param chatId: number = 0;
  @Param threadRootId: number = 0;
  @Param bottomSafe: number = 0;
  @Param keyboardH: number = 0;

  // onReactionShowChange/onForwardShowChange/onScheduledShowChange 三个
  // @Event 在 B11 之前把 show 值再转发回页面去写 this.showXxx；现在这三个
  // sheet 的 show/onShowChange 直接落在 this.overlayState.setSheet(kind, show)
  // 上（见下方 build() 里三处 onShowChange），组件自己就能收窄这段重渲染依
  // 赖，不再需要绕页面一趟——因此这三个 @Event 字段本身被收掉，不是漏写。
  @Event onReactionPick: (reactionKey: string, chosen: boolean) => void =
    (): void => {};
  @Event onForwardSent: () => void = (): void => {};
  @Event onPollSubmit: (question: string, options: string[], isAnonymous: boolean,
    isQuiz: boolean, correctOptionId: number) => void = (): void => {};
  @Event onPollClose: () => void = (): void => {};
  @Event onContactPick: (contact: PickedContact) => void = (): void => {};
  @Event onContactClose: () => void = (): void => {};
  @Event onVideoCaptured: (path: string, durationSec: number, length: number) => void =
    (): void => {};
  @Event onVideoClose: () => void = (): void => {};
  @Event effectDuration: (key: string, ms: number) => number =
    (_key: string, ms: number): number => ms;

  build() {
    Stack() {
      if (this.overlayState.showReactionSheet) {
        ReactionSheet({
          show: this.overlayState.showReactionSheet,
          onShowChange: (show: boolean): void => { this.overlayState.setSheet('reaction', show); },
          messages: this.messages,
          targetId: this.overlayState.reactionTargetId,
          chatId: this.chatId,
          pendingKey: this.overlayState.reactionPendingKey,
          // ReactionSheet no longer reads V1 storage props for these values.
          bottomSafe: this.bottomSafe,
          keyboardH: this.keyboardH,
          effectDuration: (key: string, ms: number): number => this.effectDuration(key, ms),
          onPick: (reactionKey: string, chosen: boolean): void => {
            this.onReactionPick(reactionKey, chosen);
          }
        });
      }
      if (this.overlayState.showForwardSheet) {
        ForwardSheet({
          show: this.overlayState.showForwardSheet,
          onShowChange: (show: boolean): void => { this.overlayState.setSheet('forward', show); },
          messageIds: this.overlayState.forwardMessageIds,
          sourceChatId: this.chatId,
          threadRootId: this.threadRootId,
          effectDuration: (key: string, ms: number): number => this.effectDuration(key, ms),
          onSent: (): void => { this.onForwardSent(); }
        });
      }
      if (this.overlayState.showScheduledSheet) {
        ScheduledSheet({
          show: this.overlayState.showScheduledSheet,
          onShowChange: (show: boolean): void => { this.overlayState.setSheet('scheduled', show); },
          chatId: this.chatId
        });
      }
      if (this.overlayState.showPollSheet) {
        PollComposeSheet({
          onSubmit: (question: string, options: string[], isAnonymous: boolean,
            isQuiz: boolean, correctOptionId: number): void => {
            this.onPollSubmit(question, options, isAnonymous, isQuiz, correctOptionId);
          },
          onClose: (): void => { this.onPollClose(); }
        });
      }
      if (this.overlayState.showContactSheet) {
        ContactPickerSheet({
          onPick: (contact: PickedContact): void => { this.onContactPick(contact); },
          onClose: (): void => { this.onContactClose(); }
        });
      }
      if (this.overlayState.showVideoNoteRecorder) {
        VideoNoteRecorderView({
          onCaptured: (path: string, durationSec: number, length: number): void => {
            this.onVideoCaptured(path, durationSec, length);
          },
          onClose: (): void => { this.onVideoClose(); }
        });
      }
    }
    .width('100%').height('100%');
  }
}
