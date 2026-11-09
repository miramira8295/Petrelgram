import { TdClient } from '../tdkit/TdClient';
import { TdError, TdObject, TdRequest } from '../tdkit/TdTypes';
import { UserStore } from './UserStore';
import { str } from '../util/strings';
import { logE } from '../util/log';

const MAX_VISIBLE_MESSAGES: number = 100;

export interface GroupCallMessageEntry {
  id: number;
  revision: number;
  senderKey: string;
  senderId: number;
  senderName: string;
  senderInitials: string;
  senderAvatarPath: string;
  colorSeed: number;
  date: number;
  text: string;
  textEntities: TdObject[];
  isFromOwner: boolean;
}

type GroupCallMessageListener = (messages: GroupCallMessageEntry[]) => void;
type GroupCallMessageErrorListener = (message: string) => void;

// Group-call messages deliberately don't use MessageStore: Telegram keeps
// them outside the channel's normal history and delivers them only as live
// overlays while the viewer is joined to the call.
export class GroupCallMessageStore {
  private client: TdClient;
  private users: UserStore;
  private groupCallId: number;
  private messages: GroupCallMessageEntry[] = [];
  private listeners: GroupCallMessageListener[] = [];
  private errorListeners: GroupCallMessageErrorListener[] = [];
  private unsubs: Array<() => void> = [];
  private senderNames: Map<string, string> = new Map();
  private senderAvatars: Map<string, string> = new Map();
  private avatarFileToSender: Map<number, string> = new Map();
  private requestedChats: Set<number> = new Set();

  constructor(client: TdClient, users: UserStore, groupCallId: number) {
    this.client = client;
    this.users = users;
    this.groupCallId = groupCallId;
  }

  open(): void {
    this.unsubs.push(this.client.onUpdate(
      'updateNewGroupCallMessage', (update: TdObject): void => this.onNewMessage(update)
    ));
    this.unsubs.push(this.client.onUpdate(
      'updateGroupCallMessagesDeleted', (update: TdObject): void => this.onDeleted(update)
    ));
    this.unsubs.push(this.client.onUpdate(
      'updateGroupCallMessageSendFailed', (update: TdObject): void => this.onSendFailed(update)
    ));
    this.unsubs.push(this.client.onUpdate(
      'updateUser', (update: TdObject): void => this.onUser(update)
    ));
    this.unsubs.push(this.client.onUpdate(
      'updateFile', (update: TdObject): void => this.onFile(update)
    ));
  }

  close(): void {
    for (const unsubscribe of this.unsubs) { unsubscribe(); }
    this.unsubs = [];
    this.listeners = [];
    this.errorListeners = [];
    this.messages = [];
  }

  subscribe(listener: GroupCallMessageListener): () => void {
    this.listeners = [...this.listeners, listener];
    listener(this.messages);
    return (): void => {
      this.listeners = this.listeners.filter(
        (value: GroupCallMessageListener): boolean => value !== listener
      );
    };
  }

  subscribeError(listener: GroupCallMessageErrorListener): () => void {
    this.errorListeners = [...this.errorListeners, listener];
    return (): void => {
      this.errorListeners = this.errorListeners.filter(
        (value: GroupCallMessageErrorListener): boolean => value !== listener
      );
    };
  }

  async send(text: string): Promise<void> {
    const value = text.trim();
    if (value === '') { return; }
    const formatted: TdObject = { '@type': 'formattedText' };
    formatted['text'] = value;
    formatted['entities'] = [];
    const request: TdRequest = { '@type': 'sendGroupCallMessage' };
    request['group_call_id'] = this.groupCallId;
    request['text'] = formatted;
    request['paid_message_star_count'] = 0;
    await this.client.send(request);
  }

  private onNewMessage(update: TdObject): void {
    if (((update['group_call_id'] as number | undefined) ?? 0) !== this.groupCallId) { return; }
    const message = update['message'] as TdObject | undefined;
    if (message === undefined) { return; }
    const id = (message['message_id'] as number | undefined) ?? 0;
    if (id === 0) { return; }
    const formatted = message['text'] as TdObject | undefined;
    const text = formatted !== undefined ? ((formatted['text'] as string | undefined) ?? '') : '';
    if (text === '') { return; }
    const sender = message['sender_id'] as TdObject | undefined;
    const senderType = sender !== undefined ? ((sender['@type'] as string | undefined) ?? '') : '';
    let senderId = 0;
    if (sender !== undefined && senderType === 'messageSenderUser') {
      senderId = (sender['user_id'] as number | undefined) ?? 0;
    } else if (sender !== undefined && senderType === 'messageSenderChat') {
      senderId = (sender['chat_id'] as number | undefined) ?? 0;
    }
    const senderKey = `${senderType}:${senderId}`;
    const knownName = this.senderNames.get(senderKey) ?? '';
    let senderName = knownName;
    if (senderType === 'messageSenderUser') {
      const userName = this.users.displayName(senderId);
      senderName = userName !== '' ? userName : (knownName !== '' ? knownName : str('gcm_viewer'));
      this.users.ensure(senderId);
    } else if (senderType === 'messageSenderChat') {
      senderName = knownName !== '' ? knownName : str('gn_channel');
      this.resolveChat(senderId, senderKey);
    } else {
      senderName = str('gcm_viewer');
    }
    const next: GroupCallMessageEntry = {
      id,
      revision: 0,
      senderKey,
      senderId,
      senderName,
      senderInitials: this.initials(senderName),
      senderAvatarPath: this.senderAvatars.get(senderKey) ?? '',
      colorSeed: senderId !== 0 ? senderId : id,
      date: (message['date'] as number | undefined) ?? Math.floor(Date.now() / 1000),
      text,
      textEntities: formatted !== undefined
        ? ((formatted['entities'] as TdObject[] | undefined) ?? []) : [],
      isFromOwner: (message['is_from_owner'] as boolean | undefined) ?? false
    };
    const existing = this.messages.findIndex(
      (entry: GroupCallMessageEntry): boolean => entry.id === id
    );
    if (existing >= 0) {
      this.messages[existing] = next;
    } else {
      this.messages = [...this.messages, next];
      this.messages.sort((a: GroupCallMessageEntry, b: GroupCallMessageEntry): number =>
        a.date !== b.date ? a.date - b.date : a.id - b.id);
      if (this.messages.length > MAX_VISIBLE_MESSAGES) {
        this.messages = this.messages.slice(this.messages.length - MAX_VISIBLE_MESSAGES);
      }
    }
    this.notify();
  }

  private onDeleted(update: TdObject): void {
    if (((update['group_call_id'] as number | undefined) ?? 0) !== this.groupCallId) { return; }
    const ids = (update['message_ids'] as number[] | undefined) ?? [];
    if (ids.length === 0) { return; }
    this.messages = this.messages.filter(
      (message: GroupCallMessageEntry): boolean => ids.indexOf(message.id) < 0
    );
    this.notify();
  }

  private onSendFailed(update: TdObject): void {
    if (((update['group_call_id'] as number | undefined) ?? 0) !== this.groupCallId) { return; }
    const error = update['error'] as TdObject | undefined;
    const message = error !== undefined
      ? ((error['message'] as string | undefined) ?? str('gcm_send_failed'))
      : str('gcm_send_failed');
    this.emitError(message);
  }

  private onUser(update: TdObject): void {
    const user = update['user'] as TdObject | undefined;
    if (user === undefined) { return; }
    const id = (user['id'] as number | undefined) ?? 0;
    if (id <= 0) { return; }
    const senderKey = `messageSenderUser:${id}`;
    const first = (user['first_name'] as string | undefined) ?? '';
    const last = (user['last_name'] as string | undefined) ?? '';
    const name = `${first} ${last}`.trim();
    if (name !== '') { this.senderNames.set(senderKey, name); }
    const profilePhoto = user['profile_photo'] as TdObject | undefined;
    const small = profilePhoto !== undefined ? (profilePhoto['small'] as TdObject | undefined) : undefined;
    const fileId = small !== undefined ? ((small['id'] as number | undefined) ?? 0) : 0;
    if (fileId > 0) { this.requestAvatar(fileId, senderKey); }
    this.patchSender(senderKey, name);
  }

  private resolveChat(chatId: number, senderKey: string): void {
    if (chatId === 0 || this.requestedChats.has(chatId)) { return; }
    this.requestedChats.add(chatId);
    const request: TdRequest = { '@type': 'getChat' };
    request['chat_id'] = chatId;
    this.client.send(request).then((chat: TdObject): void => {
      const name = (chat['title'] as string | undefined) ?? str('gn_channel');
      this.senderNames.set(senderKey, name);
      const photo = chat['photo'] as TdObject | undefined;
      const small = photo !== undefined ? (photo['small'] as TdObject | undefined) : undefined;
      const fileId = small !== undefined ? ((small['id'] as number | undefined) ?? 0) : 0;
      if (fileId > 0) { this.requestAvatar(fileId, senderKey); }
      this.patchSender(senderKey, name);
    }).catch((error: TdError): void => {
      logE(`GroupCallMessageStore.getChat(${chatId}) failed: ${error.message}`);
    });
  }

  private requestAvatar(fileId: number, senderKey: string): void {
    this.avatarFileToSender.set(fileId, senderKey);
    const request: TdRequest = { '@type': 'downloadFile' };
    request['file_id'] = fileId;
    request['priority'] = 1;
    request['offset'] = 0;
    request['limit'] = 0;
    request['synchronous'] = false;
    this.client.send(request).then((file: TdObject): void => {
      this.applyAvatarFile(fileId, senderKey, file);
    }).catch((error: TdError): void => {
      logE(`GroupCallMessageStore.downloadFile(${fileId}) failed: ${error.message}`);
    });
  }

  private onFile(update: TdObject): void {
    const file = update['file'] as TdObject | undefined;
    if (file === undefined) { return; }
    const fileId = (file['id'] as number | undefined) ?? 0;
    const senderKey = this.avatarFileToSender.get(fileId);
    if (senderKey !== undefined) { this.applyAvatarFile(fileId, senderKey, file); }
  }

  private applyAvatarFile(fileId: number, senderKey: string, file: TdObject): void {
    const local = file['local'] as TdObject | undefined;
    const completed = local !== undefined
      ? ((local['is_downloading_completed'] as boolean | undefined) ?? false) : false;
    const path = local !== undefined ? ((local['path'] as string | undefined) ?? '') : '';
    if (!completed || path === '') { return; }
    this.avatarFileToSender.delete(fileId);
    this.senderAvatars.set(senderKey, path);
    this.patchSender(senderKey, this.senderNames.get(senderKey) ?? '');
  }

  private patchSender(senderKey: string, resolvedName: string): void {
    let changed = false;
    this.messages = this.messages.map((message: GroupCallMessageEntry): GroupCallMessageEntry => {
      if (message.senderKey !== senderKey) { return message; }
      const name = resolvedName !== '' ? resolvedName : message.senderName;
      const avatar = this.senderAvatars.get(senderKey) ?? message.senderAvatarPath;
      if (name === message.senderName && avatar === message.senderAvatarPath) { return message; }
      changed = true;
      return {
        id: message.id,
        revision: message.revision + 1,
        senderKey: message.senderKey,
        senderId: message.senderId,
        senderName: name,
        senderInitials: this.initials(name),
        senderAvatarPath: avatar,
        colorSeed: message.colorSeed,
        date: message.date,
        text: message.text,
        textEntities: message.textEntities,
        isFromOwner: message.isFromOwner
      };
    });
    if (changed) { this.notify(); }
  }

  private initials(name: string): string {
    const trimmed = name.trim();
    return trimmed !== '' ? trimmed.substring(0, 1).toUpperCase() : '?';
  }

  private notify(): void {
    for (const listener of this.listeners) { listener(this.messages); }
  }

  private emitError(message: string): void {
    for (const listener of this.errorListeners) { listener(message); }
  }
}
