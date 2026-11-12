import { senderRoleFor, senderRoleKey, subscribeSenderRole } from './senderRoleChannel';

// The native SenderRoleTag owns its own subscription. This binding is used only
// while the row is a drawn-header candidate, and is detached on recycle or
// when the body needs links, translation or material rendering.
export class DrawnSenderRoleBinding {
  private key: string = '';
  private unsub: (() => void) | null = null;

  attach(chatId: number, senderId: number, changed: (label: string) => void): string {
    const key: string = senderRoleKey(chatId, senderId);
    if (this.key !== key || this.unsub === null) {
      this.detach();
      this.key = key;
      this.unsub = subscribeSenderRole(key, (label: string): void => {
        if (this.key === key) { changed(label); }
      });
    }
    return senderRoleFor(key);
  }

  detach(): void {
    if (this.unsub !== null) { this.unsub(); this.unsub = null; }
    this.key = '';
  }
}
