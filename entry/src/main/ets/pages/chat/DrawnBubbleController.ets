import { MessageEntry } from '../../store/MessageEntry';
import { sendStateFor, subscribeSendState } from '../../util/sendStateChannel';
import { TranslationStatus, subscribeTranslationStatus, translationStatusFor } from '../../util/translationChannel';
import { subscribeViewCount, viewCountLabelFor } from '../../util/viewCountChannel';
import { DrawnSenderRoleBinding } from '../../util/drawnSenderRoleBinding';

export interface DrawnBubbleEvents {
  send: (state: string) => void;
  views: (label: string) => void;
  translation: (status: TranslationStatus | null) => void;
  role: (label: string) => void;
}

// Channels belong to the row, not its paint passes. O(1) identity checks keep
// media/selection updates from tearing down unrelated message subscriptions.
export class DrawnBubbleController {
  private key: string = '';
  private generation: number = 0;
  private unsubs: (() => void)[] = [];
  private role: DrawnSenderRoleBinding = new DrawnSenderRoleBinding();
  private events: DrawnBubbleEvents;
  constructor(events: DrawnBubbleEvents) { this.events = events; }

  attach(chatId: number, msg: MessageEntry, showName: boolean): void {
    const key = `${chatId}:${msg.rowId}:${msg.id}:${msg.senderId}:${showName}`;
    if (this.key !== key) {
      this.detach(); this.key = key;
      const generation = this.generation;
      this.unsubs.push(subscribeSendState(msg.rowId, (value: string): void => {
        if (this.key === key && this.generation === generation) { this.events.send(value); }
      }));
      this.unsubs.push(subscribeViewCount(chatId, msg.id, (value: string): void => {
        if (this.key === key && this.generation === generation) { this.events.views(value); }
      }));
      this.unsubs.push(subscribeTranslationStatus(msg.id, (value: TranslationStatus | null): void => {
        if (this.key === key && this.generation === generation) { this.events.translation(value); }
      }));
    }
    this.events.send(sendStateFor(msg.rowId) || msg.sendState);
    this.events.views(viewCountLabelFor(chatId, msg.id));
    this.events.translation(translationStatusFor(msg.id));
    const generation = this.generation;
    if (showName && msg.senderTag === '') {
      this.events.role(this.role.attach(chatId, msg.senderId, (value: string): void => {
        if (this.key === key && this.generation === generation) { this.events.role(value); }
      }));
    } else { this.role.detach(); this.events.role(msg.senderTag); }
  }

  detach(): void {
    this.key = ''; this.generation++;
    for (const unsubscribe of this.unsubs) { unsubscribe(); }
    this.unsubs.length = 0; this.role.detach();
  }
}
