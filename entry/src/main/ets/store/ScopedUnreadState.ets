import { TdObject, TdRequest } from '../tdkit/TdTypes';
import { messageOutsideTopicScope } from '../util/messageTopicScope';

export interface ScopedUnreadHost {
  send: (request: TdRequest) => Promise<TdObject>;
  onUpdate: (type: string, listener: (update: TdObject) => void) => (() => void);
}

// Badge-only channel. One in-flight query and one coalescing timer per scope;
// no history scans, album expansion or message-list publication.
export class ScopedUnreadState {
  private count: number = 0;
  private confirmedRead: number = 0;
  private lastMessageId: number = 0;
  private revision: number = 0;
  private running: boolean = false;
  private closed: boolean = false;
  private opened: boolean = false;
  private timer: number = -1;
  private listeners: Set<(count: number) => void> = new Set();
  private unsubs: (() => void)[] = [];

  private host: ScopedUnreadHost;
  private chatId: number;
  private threadId: number;
  private forumId: number;
  private directId: number;
  constructor(host: ScopedUnreadHost, chatId: number,
    threadId: number, forumId: number, directId: number) {
    this.host = host; this.chatId = chatId;
    this.threadId = threadId; this.forumId = forumId; this.directId = directId;
  }

  subscribe(listener: (count: number) => void): () => void {
    this.listeners.add(listener);
    listener(this.count);
    return (): void => { this.listeners.delete(listener); };
  }

  open(): void {
    if (this.opened || this.closed) { return; }
    this.opened = true;
    for (const type of ['updateMessageInteractionInfo', 'updateForumTopic',
      'updateDirectMessagesChatTopic', 'updateNewMessage', 'updateDeleteMessages']) {
      this.unsubs.push(this.host.onUpdate(type, (update: TdObject): void => {
        if (this.affectsScope(type, update)) { this.refresh(); }
      }));
    }
    this.query();
  }

  private affectsScope(type: string, update: TdObject): boolean {
    if (type === 'updateNewMessage') {
      const m = update['message'] as TdObject | undefined;
      return m !== undefined && m['chat_id'] === this.chatId &&
        !messageOutsideTopicScope(m, this.threadId, this.forumId, this.directId);
    }
    if (type === 'updateDirectMessagesChatTopic') {
      const t = update['topic'] as TdObject | undefined;
      return this.directId > 0 && t !== undefined && t['chat_id'] === this.chatId && t['id'] === this.directId;
    }
    if (update['chat_id'] !== this.chatId) { return false; }
    if (type === 'updateForumTopic') { return this.forumId > 0 && update['forum_topic_id'] === this.forumId; }
    if (type === 'updateMessageInteractionInfo') {
      return this.threadId > 0 && update['message_id'] === this.threadId;
    }
    return type === 'updateDeleteMessages';
  }

  readConfirmed(messageId: number): void {
    if (this.closed) { return; }
    this.confirmedRead = Math.max(this.confirmedRead, messageId);
    if (this.lastMessageId > 0 && this.confirmedRead >= this.lastMessageId) { this.publish(0); }
    this.refresh();
  }

  private refresh(): void {
    if (this.closed) { return; }
    this.revision++;
    this.schedule();
  }

  private schedule(): void {
    if (this.closed || this.running || this.timer !== -1) { return; }
    this.timer = setTimeout((): void => { this.timer = -1; this.query(); }, 200);
  }

  private query(): void {
    if (this.closed || this.running) { return; }
    const request: TdRequest = { '@type': 'getMessageThread' };
    request['chat_id'] = this.chatId;
    if (this.directId > 0) {
      request['@type'] = 'getDirectMessagesChatTopic'; request['topic_id'] = this.directId;
    } else if (this.forumId > 0) {
      request['@type'] = 'getForumTopic'; request['forum_topic_id'] = this.forumId;
    } else { request['message_id'] = this.threadId; }
    const revision: number = this.revision;
    this.running = true;
    this.host.send(request).then((result: TdObject): void => {
      if (!this.closed && revision === this.revision) { this.apply(result); }
    }).catch((): void => {
      // Retain the last scoped value on failure. Never substitute the group's
      // unread total or spin on network errors; the next read/update retries.
    }).finally((): void => {
      this.running = false;
      if (!this.closed && revision !== this.revision) { this.schedule(); }
    });
  }

  private apply(result: TdObject): void {
    let count: number;
    let last: number;
    if (this.directId > 0) {
      if (result['chat_id'] !== this.chatId || result['id'] !== this.directId) { return; }
      const message = result['last_message'] as TdObject | undefined;
      last = (message?.['id'] as number | undefined) ?? 0;
      count = (result['unread_count'] as number | undefined) ?? 0;
    } else if (this.forumId > 0) {
      const info = result['info'] as TdObject | undefined;
      if (info?.['chat_id'] !== this.chatId || info?.['forum_topic_id'] !== this.forumId) { return; }
      const message = result['last_message'] as TdObject | undefined;
      last = (message?.['id'] as number | undefined) ?? 0;
      count = (result['unread_count'] as number | undefined) ?? 0;
    } else {
      if (result['chat_id'] !== this.chatId || result['message_thread_id'] !== this.threadId) { return; }
      const replies = result['reply_info'] as TdObject | undefined;
      last = (replies?.['last_message_id'] as number | undefined) ?? 0;
      count = (result['unread_message_count'] as number | undefined) ?? 0;
    }
    this.lastMessageId = last;
    this.publish(last > 0 && this.confirmedRead >= last ? 0 : Math.max(0, count));
  }

  private publish(count: number): void {
    if (count === this.count) { return; }
    this.count = count;
    for (const listener of this.listeners) { listener(count); }
  }

  close(): void {
    this.closed = true;
    if (this.timer !== -1) { clearTimeout(this.timer); this.timer = -1; }
    for (const off of this.unsubs) { off(); }
    this.unsubs = [];
    this.listeners.clear();
  }
}
