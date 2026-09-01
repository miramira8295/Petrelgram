import { TdClient } from '../tdkit/TdClient';
import { TdError, TdObject, TdRequest } from '../tdkit/TdTypes';
import { compareOrderDesc, computeInitials } from './ChatEntry';
import { formatPreview } from '../util/formatPreview';
import { str } from '../util/strings';
import { logE } from '../util/log';

const TOPIC_PAGE_SIZE: number = 30;
const AVATAR_PRIORITY: number = 16;

export interface DirectMessagesTopicRow {
  id: number;
  revision: number;
  senderType: string; // user | chat
  senderId: number;
  title: string;
  initials: string;
  avatarPath: string;
  avatarFileId: number;
  order: string;
  unreadCount: number;
  isMarkedUnread: boolean;
  lastMessageText: string;
  lastMessageDate: number;
}

type TopicListener = (rows: DirectMessagesTopicRow[], state: string) => void;

function stringInt64(value: Object | undefined): string {
  if (typeof value === 'string') {
    return value;
  }
  if (typeof value === 'number') {
    return `${value}`;
  }
  return '0';
}

function senderKey(senderType: string, senderId: number): string {
  return `${senderType}:${senderId}`;
}

function smallPhotoFile(photo: TdObject | undefined): TdObject | undefined {
  return photo !== undefined ? (photo['small'] as TdObject | undefined) : undefined;
}

function completedFilePath(file: TdObject | undefined): string {
  if (file === undefined) {
    return '';
  }
  const local = file['local'] as TdObject | undefined;
  if (local === undefined ||
    !((local['is_downloading_completed'] as boolean | undefined) ?? false)) {
    return '';
  }
  return (local['path'] as string | undefined) ?? '';
}

function fileId(file: TdObject | undefined): number {
  return file !== undefined ? ((file['id'] as number | undefined) ?? 0) : 0;
}

function cloneRow(row: DirectMessagesTopicRow): DirectMessagesTopicRow {
  return {
    id: row.id,
    revision: row.revision + 1,
    senderType: row.senderType,
    senderId: row.senderId,
    title: row.title,
    initials: row.initials,
    avatarPath: row.avatarPath,
    avatarFileId: row.avatarFileId,
    order: row.order,
    unreadCount: row.unreadCount,
    isMarkedUnread: row.isMarkedUnread,
    lastMessageText: row.lastMessageText,
    lastMessageDate: row.lastMessageDate
  };
}

export class DirectMessagesTopicStore {
  private client: TdClient;
  private chatId: number = 0;
  private rows: Map<number, DirectMessagesTopicRow> = new Map();
  private listeners: TopicListener[] = [];
  private unsubs: Array<() => void> = [];
  private identityRequested: Set<string> = new Set();
  private avatarRequested: Set<number> = new Set();
  private avatarTargets: Map<number, string[]> = new Map();
  private active: boolean = false;
  private loading: boolean = false;
  private allLoaded: boolean = false;
  private state: string = 'loading'; // loading | ready | error

  constructor(client: TdClient) {
    this.client = client;
  }

  subscribe(listener: TopicListener): () => void {
    this.listeners = [...this.listeners, listener];
    listener(this.snapshot(), this.state);
    return (): void => {
      this.listeners = this.listeners.filter((item: TopicListener): boolean => item !== listener);
    };
  }

  open(chatId: number): void {
    if (chatId === 0) {
      this.state = 'error';
      this.notify();
      return;
    }
    if (this.chatId !== chatId) {
      this.reset(chatId);
    }
    if (!this.active) {
      this.active = true;
      this.subscribeUpdates();
    }
    if (this.rows.size === 0) {
      this.loadMore();
    } else {
      this.state = 'ready';
      this.refreshKnownTopics();
      this.notify();
    }
  }

  close(): void {
    this.active = false;
    for (const unsubscribe of this.unsubs) {
      unsubscribe();
    }
    this.unsubs = [];
  }

  loadMore(): void {
    if (!this.active || this.loading || this.allLoaded || this.chatId === 0) {
      return;
    }
    this.loading = true;
    const requestedChatId = this.chatId;
    const request: TdRequest = { '@type': 'loadDirectMessagesChatTopics' };
    request['chat_id'] = this.chatId;
    request['limit'] = TOPIC_PAGE_SIZE;
    this.client.send(request).then((): void => {
      if (requestedChatId !== this.chatId) {
        return;
      }
      this.loading = false;
      if (!this.active) {
        return;
      }
      this.state = 'ready';
      this.notify();
    }).catch((error: TdError): void => {
      if (requestedChatId !== this.chatId) {
        return;
      }
      this.loading = false;
      if (!this.active) {
        return;
      }
      if (error.code === 404) {
        this.allLoaded = true;
        this.state = 'ready';
      } else {
        this.state = this.rows.size > 0 ? 'ready' : 'error';
        logE(`DirectMessagesTopicStore.load failed: ${error.message}`);
      }
      this.notify();
    });
  }

  refreshTopic(topicId: number): void {
    if (!this.active || topicId <= 0 || this.chatId === 0) {
      return;
    }
    const request: TdRequest = { '@type': 'getDirectMessagesChatTopic' };
    request['chat_id'] = this.chatId;
    request['topic_id'] = topicId;
    this.client.send(request).then((topic: TdObject): void => {
      if (this.active) {
        this.applyTopic(topic);
      }
    }).catch((error: TdError): void => {
      if (error.code !== 404) {
        logE(`DirectMessagesTopicStore.refresh(${topicId}) failed: ${error.message}`);
      }
    });
  }

  private reset(chatId: number): void {
    this.close();
    this.chatId = chatId;
    this.rows.clear();
    this.identityRequested.clear();
    this.avatarRequested.clear();
    this.avatarTargets.clear();
    this.loading = false;
    this.allLoaded = false;
    this.state = 'loading';
  }

  private subscribeUpdates(): void {
    this.unsubs.push(this.client.onUpdate('updateDirectMessagesChatTopic',
      (update: TdObject): void => {
        const topic = update['topic'] as TdObject | undefined;
        if (topic !== undefined) {
          this.applyTopic(topic);
        }
      }));
    this.unsubs.push(this.client.onUpdate('updateUser', (update: TdObject): void => {
      const user = update['user'] as TdObject | undefined;
      if (user !== undefined) {
        this.applyUser(user);
      }
    }));
    this.unsubs.push(this.client.onUpdate('updateNewChat', (update: TdObject): void => {
      const chat = update['chat'] as TdObject | undefined;
      if (chat !== undefined) {
        this.applyChat(chat);
      }
    }));
    this.unsubs.push(this.client.onUpdate('updateChatTitle',
      (update: TdObject): void => this.applyChatTitle(update)));
    this.unsubs.push(this.client.onUpdate('updateChatPhoto',
      (update: TdObject): void => this.applyChatPhoto(update)));
    this.unsubs.push(this.client.onUpdate('updateFile', (update: TdObject): void => {
      const file = update['file'] as TdObject | undefined;
      if (file !== undefined) {
        this.applyFile(file);
      }
    }));
  }

  private refreshKnownTopics(): void {
    for (const row of this.rows.values()) {
      this.refreshTopic(row.id);
    }
  }

  private applyTopic(topic: TdObject): void {
    if (((topic['chat_id'] as number | undefined) ?? 0) !== this.chatId) {
      return;
    }
    const id = (topic['id'] as number | undefined) ?? 0;
    if (id <= 0) {
      return;
    }
    const order = stringInt64(topic['order']);
    if (order === '0') {
      if (this.rows.delete(id)) {
        this.notify();
      }
      return;
    }
    const sender = topic['sender_id'] as TdObject | undefined;
    const senderObjectType = (sender?.['@type'] as string | undefined) ?? '';
    const senderType = senderObjectType === 'messageSenderChat' ? 'chat' : 'user';
    const senderId = senderType === 'chat'
      ? ((sender?.['chat_id'] as number | undefined) ?? 0)
      : ((sender?.['user_id'] as number | undefined) ?? 0);
    const previous = this.rows.get(id);
    const lastMessage = topic['last_message'] as TdObject | undefined;
    const fallbackTitle = senderType === 'chat'
      ? str('chat_header_kind_channel') : str('chat_header_kind_user');
    const row: DirectMessagesTopicRow = {
      id: id,
      revision: previous !== undefined ? previous.revision + 1 : 0,
      senderType: senderType,
      senderId: senderId,
      title: previous !== undefined && previous.senderId === senderId
        ? previous.title : fallbackTitle,
      initials: previous !== undefined && previous.senderId === senderId
        ? previous.initials : computeInitials(fallbackTitle),
      avatarPath: previous !== undefined && previous.senderId === senderId
        ? previous.avatarPath : '',
      avatarFileId: previous !== undefined && previous.senderId === senderId
        ? previous.avatarFileId : 0,
      order: order,
      unreadCount: (topic['unread_count'] as number | undefined) ?? 0,
      isMarkedUnread: (topic['is_marked_as_unread'] as boolean | undefined) ?? false,
      lastMessageText: formatPreview(lastMessage ?? null),
      lastMessageDate: lastMessage !== undefined
        ? ((lastMessage['date'] as number | undefined) ?? 0) : 0
    };
    this.rows.set(id, row);
    this.ensureIdentity(senderType, senderId);
    this.state = 'ready';
    this.notify();
  }

  private ensureIdentity(type: string, id: number): void {
    if (id <= 0) {
      return;
    }
    const key = senderKey(type, id);
    if (this.identityRequested.has(key)) {
      return;
    }
    this.identityRequested.add(key);
    const request: TdRequest = { '@type': type === 'chat' ? 'getChat' : 'getUser' };
    request[type === 'chat' ? 'chat_id' : 'user_id'] = id;
    this.client.send(request).then((identity: TdObject): void => {
      if (!this.active) {
        return;
      }
      if (type === 'chat') {
        this.applyChat(identity);
      } else {
        this.applyUser(identity);
      }
    }).catch((error: TdError): void => {
      this.identityRequested.delete(key);
      logE(`DirectMessagesTopicStore.${request['@type']}(${id}) failed: ${error.message}`);
    });
  }

  private applyUser(user: TdObject): void {
    const id = (user['id'] as number | undefined) ?? 0;
    if (id <= 0) {
      return;
    }
    const first = (user['first_name'] as string | undefined) ?? '';
    const last = (user['last_name'] as string | undefined) ?? '';
    const title = `${first} ${last}`.trim();
    const photo = user['profile_photo'] as TdObject | undefined;
    this.applyIdentity('user', id, title, smallPhotoFile(photo));
  }

  private applyChat(chat: TdObject): void {
    const id = (chat['id'] as number | undefined) ?? 0;
    if (id === 0) {
      return;
    }
    this.applyIdentity('chat', id, (chat['title'] as string | undefined) ?? '',
      smallPhotoFile(chat['photo'] as TdObject | undefined));
  }

  private applyChatTitle(update: TdObject): void {
    const id = (update['chat_id'] as number | undefined) ?? 0;
    const title = (update['title'] as string | undefined) ?? '';
    if (id !== 0 && title !== '') {
      this.applyIdentity('chat', id, title, undefined, false);
    }
  }

  private applyChatPhoto(update: TdObject): void {
    const id = (update['chat_id'] as number | undefined) ?? 0;
    if (id !== 0) {
      this.applyIdentity('chat', id, '',
        smallPhotoFile(update['photo'] as TdObject | undefined), true);
    }
  }

  private applyIdentity(type: string, id: number, title: string,
    file: TdObject | undefined, replacePhoto: boolean = true): void {
    const key = senderKey(type, id);
    const resolvedPath = completedFilePath(file);
    const resolvedFileId = fileId(file);
    let changed = false;
    for (const row of this.rows.values()) {
      if (senderKey(row.senderType, row.senderId) !== key) {
        continue;
      }
      const next = cloneRow(row);
      if (title !== '') {
        next.title = title;
        next.initials = computeInitials(title);
      }
      if (replacePhoto) {
        next.avatarFileId = resolvedFileId;
        next.avatarPath = resolvedPath;
      }
      this.rows.set(next.id, next);
      changed = true;
    }
    if (resolvedFileId > 0 && resolvedPath === '') {
      this.requestAvatar(resolvedFileId, key);
    }
    if (changed) {
      this.notify();
    }
  }

  private requestAvatar(id: number, targetKey: string): void {
    const current = this.avatarTargets.get(id) ?? [];
    if (current.indexOf(targetKey) < 0) {
      this.avatarTargets.set(id, [...current, targetKey]);
    }
    if (this.avatarRequested.has(id)) {
      return;
    }
    this.avatarRequested.add(id);
    const request: TdRequest = { '@type': 'downloadFile' };
    request['file_id'] = id;
    request['priority'] = AVATAR_PRIORITY;
    this.client.send(request).then((file: TdObject): void => {
      this.applyFile(file);
    }).catch((error: TdError): void => {
      this.avatarRequested.delete(id);
      logE(`DirectMessagesTopicStore.downloadFile(${id}) failed: ${error.message}`);
    });
  }

  private applyFile(file: TdObject): void {
    const id = fileId(file);
    const path = completedFilePath(file);
    if (id <= 0 || path === '') {
      return;
    }
    const targets = this.avatarTargets.get(id) ?? [];
    if (targets.length === 0) {
      return;
    }
    let changed = false;
    for (const row of this.rows.values()) {
      if (targets.indexOf(senderKey(row.senderType, row.senderId)) < 0 ||
        row.avatarPath === path) {
        continue;
      }
      const next = cloneRow(row);
      next.avatarPath = path;
      next.avatarFileId = id;
      this.rows.set(next.id, next);
      changed = true;
    }
    if (changed) {
      this.notify();
    }
  }

  private snapshot(): DirectMessagesTopicRow[] {
    return Array.from(this.rows.values()).sort(
      (left: DirectMessagesTopicRow, right: DirectMessagesTopicRow): number =>
        compareOrderDesc(left.order, right.order));
  }

  private notify(): void {
    const rows = this.snapshot();
    for (const listener of this.listeners) {
      listener(rows, this.state);
    }
  }
}
