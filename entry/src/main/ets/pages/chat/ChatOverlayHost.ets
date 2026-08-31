import { MessageEntry } from '../../store/MessageEntry';
import { ReactionSheet } from './ReactionSheet';
import { ForwardSheet } from './ForwardSheet';
import { ScheduledSheet } from './ScheduledSheet';
import { PollComposeSheet } from './PollComposeSheet';
import { ContactPickerSheet, PickedContact } from './ContactPickerSheet';
import { VideoNoteRecorderView } from './VideoNoteRecorderView';

// Presentation host for the transient chat overlays. ChatPage retains the
// state and business actions; this component only wires values and events into
// the existing sheets.
@ComponentV2
export struct ChatOverlayHost {
  @Param showReactionSheet: boolean = false;
  @Param showForwardSheet: boolean = false;
  @Param showScheduledSheet: boolean = false;
  @Param showPollSheet: boolean = false;
  @Param showContactSheet: boolean = false;
  @Param showVideoNoteRecorder: boolean = false;

  @Param messages: MessageEntry[] = [];
  @Param reactionTargetId: number = 0;
  @Param reactionPendingKey: string = '';
  @Param chatId: number = 0;
  @Param threadRootId: number = 0;
  @Param forwardMessageIds: number[] = [];
  @Param bottomSafe: number = 0;
  @Param keyboardH: number = 0;

  @Event onReactionShowChange: (show: boolean) => void = (): void => {};
  @Event onReactionPick: (reactionKey: string, chosen: boolean) => void =
    (): void => {};
  @Event onForwardShowChange: (show: boolean) => void = (): void => {};
  @Event onForwardSent: () => void = (): void => {};
  @Event onScheduledShowChange: (show: boolean) => void = (): void => {};
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
      if (this.showReactionSheet) {
        ReactionSheet({
          show: this.showReactionSheet,
          onShowChange: (show: boolean): void => { this.onReactionShowChange(show); },
          messages: this.messages,
          targetId: this.reactionTargetId,
          chatId: this.chatId,
          pendingKey: this.reactionPendingKey,
          // ReactionSheet no longer reads V1 storage props for these values.
          bottomSafe: this.bottomSafe,
          keyboardH: this.keyboardH,
          effectDuration: (key: string, ms: number): number => this.effectDuration(key, ms),
          onPick: (reactionKey: string, chosen: boolean): void => {
            this.onReactionPick(reactionKey, chosen);
          }
        });
      }
      if (this.showForwardSheet) {
        ForwardSheet({
          show: this.showForwardSheet,
          onShowChange: (show: boolean): void => { this.onForwardShowChange(show); },
          messageIds: this.forwardMessageIds,
          sourceChatId: this.chatId,
          threadRootId: this.threadRootId,
          effectDuration: (key: string, ms: number): number => this.effectDuration(key, ms),
          onSent: (): void => { this.onForwardSent(); }
        });
      }
      if (this.showScheduledSheet) {
        ScheduledSheet({
          show: this.showScheduledSheet,
          onShowChange: (show: boolean): void => { this.onScheduledShowChange(show); },
          chatId: this.chatId
        });
      }
      if (this.showPollSheet) {
        PollComposeSheet({
          onSubmit: (question: string, options: string[], isAnonymous: boolean,
            isQuiz: boolean, correctOptionId: number): void => {
            this.onPollSubmit(question, options, isAnonymous, isQuiz, correctOptionId);
          },
          onClose: (): void => { this.onPollClose(); }
        });
      }
      if (this.showContactSheet) {
        ContactPickerSheet({
          onPick: (contact: PickedContact): void => { this.onContactPick(contact); },
          onClose: (): void => { this.onContactClose(); }
        });
      }
      if (this.showVideoNoteRecorder) {
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
