import { TdObject, TdRequest } from '../../tdkit/TdTypes';
import { applyMessageTopicScope, messageOutsideTopicScope } from '../../util/messageTopicScope';

export interface UnreadMentionScope {
  chatId: number;
  threadRootId: number;
  forumTopicId: number;
  directMessagesTopicId: number;
}

export interface UnreadMentionPort {
  send: (request: TdRequest) => Promise<TdObject>;
  subscribeCount: (listener: (count: number) => void) => () => void;
  onUpdate: (type: string, listener: (update: TdObject) => void) => () => void;
  active: () => boolean;
  jump: (messageId: number) => void;
  failed: () => void;
}

// One instance per conversation. Counting/searching never marks anything read;
// only MessageStore's actual visible-message reporting consumes mentions.
@ObservedV2
export class UnreadMentionSession {
  @Trace count: number = 0;
  @Trace busy: boolean = false;
  private scope: UnreadMentionScope = { chatId: 0, threadRootId: 0, forumTopicId: 0, directMessagesTopicId: 0 };
  private port: UnreadMentionPort | null = null;
  private unsubs: (() => void)[] = [];
  private generation: number = 0;
  private countSequence: number = 0;
  private chatCount: number = -1;
  private cursor: number = 0;

  open(scope: UnreadMentionScope, port: UnreadMentionPort): void {
    this.dispose();
    this.scope = scope;
    this.port = port;
    this.unsubs.push(port.subscribeCount((count: number): void => {
      if (count === this.chatCount) { return; }
      this.chatCount = count;
      if (!this.scoped()) { this.count = count; }
      else { this.refreshScopedCount(); }
    }));
    this.unsubs.push(port.onUpdate('updateMessageMentionRead', (update: TdObject): void => {
      if (update['chat_id'] === this.scope.chatId && this.scoped()) { this.refreshScopedCount(); }
    }));
    this.unsubs.push(port.onUpdate('updateForumTopic', (update: TdObject): void => {
      if (this.scope.forumTopicId > 0 && update['chat_id'] === this.scope.chatId &&
        update['forum_topic_id'] === this.scope.forumTopicId) {
        ++this.countSequence;
        this.count = Math.max(0, (update['unread_mention_count'] as number | undefined) ?? 0);
      }
    }));
  }

  private scoped(): boolean {
    return this.scope.threadRootId > 0 || this.scope.forumTopicId > 0 || this.scope.directMessagesTopicId > 0;
  }

  private request(fromId: number, limit: number): TdRequest {
    const request: TdRequest = { '@type': 'searchChatMessages' };
    request['chat_id'] = this.scope.chatId;
    request['query'] = '';
    request['from_message_id'] = fromId;
    request['offset'] = 0;
    request['limit'] = limit;
    request['filter'] = { '@type': 'searchMessagesFilterUnreadMention' } as TdObject;
    applyMessageTopicScope(request, this.scope.threadRootId, this.scope.forumTopicId, this.scope.directMessagesTopicId);
    return request;
  }

  private ids(result: TdObject): number[] {
    const messages = (result['messages'] as TdObject[] | undefined) ?? [];
    return messages.filter((message: TdObject): boolean => message['chat_id'] === this.scope.chatId &&
      !messageOutsideTopicScope(message, this.scope.threadRootId, this.scope.forumTopicId,
        this.scope.directMessagesTopicId))
      .map((message: TdObject): number => (message['id'] as number | undefined) ?? 0)
      .filter((id: number): boolean => id > 0).sort((a: number, b: number): number => b - a);
  }

  private refreshScopedCount(): void {
    const port = this.port;
    if (port === null) { return; }
    const generation = this.generation;
    const sequence = ++this.countSequence;
    port.send(this.request(0, 1)).then((result: TdObject): void => {
      if (generation !== this.generation || sequence !== this.countSequence) { return; }
      this.count = Math.max(this.ids(result).length, (result['total_count'] as number | undefined) ?? 0);
    }).catch((): void => {}); // Retain the last known count on network failure.
  }

  async next(): Promise<void> {
    const port = this.port;
    if (port === null || this.busy || this.count <= 0 || !port.active()) { return; }
    const generation = this.generation;
    this.busy = true;
    try {
      const result = await port.send(this.request(this.cursor, 2));
      if (generation !== this.generation || this.count <= 0 || !port.active()) { return; }
      let ids = this.ids(result).filter((id: number): boolean => this.cursor === 0 || id < this.cursor);
      // Search is newest → oldest; after the last unread mention, wrap so a
      // newly arrived mention (or a still-unplayed voice mention) stays reachable.
      if (ids.length === 0 && this.cursor !== 0) {
        const newest = await port.send(this.request(0, 2));
        if (generation !== this.generation || this.count <= 0 || !port.active()) { return; }
        ids = this.ids(newest);
      }
      if (ids.length === 0) { port.failed(); return; }
      this.cursor = ids[0];
      port.jump(this.cursor);
    } catch (_) {
      if (generation === this.generation && port.active()) { port.failed(); }
    } finally {
      if (generation === this.generation) { this.busy = false; }
    }
  }

  dispose(): void {
    ++this.generation;
    ++this.countSequence;
    for (const unsub of this.unsubs) { unsub(); }
    this.unsubs = [];
    this.port = null;
    this.chatCount = -1;
    this.cursor = 0;
    this.count = 0;
    this.busy = false;
  }
}
