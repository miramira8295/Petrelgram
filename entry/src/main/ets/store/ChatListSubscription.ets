import { ChatEntry } from './ChatEntry';
import { TimerFns } from '../tdkit/TdClient';

export enum ChatListPublicationMode {
  Paused,
  Batched,
  Immediate
}

const LIST_PUBLICATION_MS: number = 250;

// A dirty bit, not a buffered snapshot: hidden lists do no materialization.
// The view still owns the final menu/touch/transition publication gate.
export class ChatListSubscription {
  private dirty: boolean = true;
  private closed: boolean = false;
  private timerId: number = -1;
  private timer: TimerFns;
  private mode: () => ChatListPublicationMode;
  private read: () => ChatEntry[];
  private listener: (chats: ChatEntry[]) => void;
  private detach: () => void;

  constructor(timer: TimerFns, mode: () => ChatListPublicationMode,
    read: () => ChatEntry[], listener: (chats: ChatEntry[]) => void, detach: () => void) {
    this.timer = timer;
    this.mode = mode;
    this.read = read;
    this.listener = listener;
    this.detach = detach;
  }

  invalidate(urgent: boolean = false): void {
    if (this.closed) { return; }
    this.dirty = true;
    const mode = this.mode();
    if (mode === ChatListPublicationMode.Paused) {
      this.cancelTimer();
      return;
    }
    if (urgent || mode === ChatListPublicationMode.Immediate) {
      this.cancelTimer();
      this.schedule(0);
    } else if (this.timerId === -1) {
      // Do not rearm on each update: continuous traffic must not starve UI.
      this.schedule(LIST_PUBLICATION_MS);
    }
  }

  // Gate changes cancel old deadlines. On resume, publish only the latest
  // dirty state once; initial subscriptions also replay synchronously here.
  refresh(force: boolean = false): void {
    if (force) { this.dirty = true; }
    this.cancelTimer();
    if (this.closed || !this.dirty || this.mode() === ChatListPublicationMode.Paused) { return; }
    this.dirty = false;
    this.listener(this.read());
  }

  close(): void {
    if (this.closed) { return; }
    this.closed = true;
    this.cancelTimer();
    this.detach();
  }

  private schedule(delay: number): void {
    this.timerId = this.timer.setTimeout((): void => {
      this.timerId = -1;
      this.refresh();
    }, delay);
  }

  private cancelTimer(): void {
    if (this.timerId !== -1) {
      this.timer.clearTimeout(this.timerId);
      this.timerId = -1;
    }
  }
}
