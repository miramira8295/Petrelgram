import { ChatEntry } from './ChatEntry';

// Reverse index of current last-message senders. Changing the last message
// removes the previous dependency; updates visit only affected chat previews.
export class ChatPreviewSenders {
  private byChat: Map<number, string> = new Map<number, string>();
  private dependents: Map<string, Set<number>> = new Map<string, Set<number>>();

  bind(entry: ChatEntry): void {
    const id = entry.lastSenderId ?? 0;
    const key = entry.lastMessageId > 0 && id !== 0 && !entry.isSavedMessages &&
      entry.lastMessageOutgoing !== true ? `${entry.lastSenderIsUser === false ? 'c' : 'u'}:${id}` : '';
    const old = this.byChat.get(entry.id) ?? '';
    if (old === key) { return; }
    if (old !== '') {
      const bucket = this.dependents.get(old);
      bucket?.delete(entry.id);
      if (bucket?.size === 0) { this.dependents.delete(old); }
      this.byChat.delete(entry.id);
    }
    if (key === '') { return; }
    let bucket = this.dependents.get(key);
    if (bucket === undefined) { bucket = new Set<number>(); this.dependents.set(key, bucket); }
    bucket.add(entry.id); this.byChat.set(entry.id, key);
  }

  collect(id: number, isUser: boolean, result: Set<number>): void {
    const bucket = this.dependents.get(`${isUser ? 'u' : 'c'}:${id}`);
    bucket?.forEach((chatId: number): void => { result.add(chatId); });
  }
}
