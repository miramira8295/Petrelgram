import { TdClient } from '../tdkit/TdClient';
import { TdObject } from '../tdkit/TdTypes';
import { listKeyOf } from './ListKey';

export class UnreadCountStore {
  private counts: Map<string, number> = new Map();
  private listeners: Array<() => void> = [];

  constructor(client: TdClient) {
    client.onUpdate('updateUnreadChatCount', (u: TdObject) => this.onCount(u));
  }

  getUnread(listKey: string): number {
    return this.counts.get(listKey) ?? 0;
  }

  subscribe(listener: () => void): () => void {
    this.listeners = [...this.listeners, listener];
    listener();
    return (): void => {
      this.listeners = this.listeners.filter((l: () => void) => l !== listener);
    };
  }

  private onCount(update: TdObject): void {
    const chatList = update['chat_list'] as TdObject | undefined;
    if (chatList === undefined) {
      return;
    }
    const key = listKeyOf(chatList);
    if (key === '') {
      return;
    }
    // 两个字段都要。TDLib 把"手动标记为未读"单独放在
    // marked_as_unread_unmuted_count 里，**不含**在 unread_unmuted_count 中；
    // 而文件夹角标那边数的是 `未读 > 0 或被标记为未读`（ChatStore.unreadChatCount）。
    // 只读前一个，就会出现"把会话标记成未读，文件夹的数字 +1、全部的数字不动"。
    const unread: number = (update['unread_unmuted_count'] as number | undefined) ?? 0;
    const marked: number = (update['marked_as_unread_unmuted_count'] as number | undefined) ?? 0;
    this.counts.set(key, unread + marked);
    for (const l of this.listeners) {
      l();
    }
  }
}
