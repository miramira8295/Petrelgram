import { ChatEntry } from '../../store/ChatEntry';

export interface ChatListRowSnapshot {
  chat: ChatEntry;
  contentKey: string;
}

// Owned by one published list, never by ChatStore. Replace the first-level
// snapshot property so V1 ObjectLink observes even pin-only changes. Mutating
// nested ChatEntry fields would not notify ObjectLink and would break freezing.
@Observed
export class ChatListRowState {
  readonly id: number;
  snapshot: ChatListRowSnapshot;

  constructor(chat: ChatEntry, contentKey: string) {
    this.id = chat.id;
    this.snapshot = { chat, contentKey };
  }

  update(chat: ChatEntry, contentKey: string): void {
    if (chat.id !== this.id) { throw new Error('ChatListRowState identity changed'); }
    if (contentKey === this.snapshot.contentKey) { return; }
    this.snapshot = { chat, contentKey };
  }
}
