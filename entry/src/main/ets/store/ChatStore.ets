import { TdClient } from '../tdkit/TdClient';
import { TdObject, TdRequest, TdError } from '../tdkit/TdTypes';
import { UserStore } from './UserStore';
import { ChatEntry, PositionInfo, cloneEntry, computeInitials, compareOrderDesc, isMutedFrom, usesDefaultMuteFrom, chatKindOf } from './ChatEntry';
import { listKeyOf, chatListOf } from './ListKey';
import { formatPreview } from '../util/formatPreview';

const PAGE_LIMIT: number = 30;
const MAIN: string = 'main';
// TDLib update bursts (e.g. read-inbox advancing while the user scrolls a chat)
// arrive many times per frame. Rebuilding and re-sorting every subscribed list
// per update stalls the UI thread, so notifications are coalesced into one
// flush per window.
const NOTIFY_COALESCE_MS: number = 80;
// 分组列表最多连翻多少页。分组通常只有几十个会话，这个上限只是防呆——
// 真被撞上会打日志，不会悄悄截断（见 ensureFullyLoaded）。
const MAX_FULL_LOAD_PAGES: number = 20;

interface Sub {
  listKey: string;
  listener: (chats: ChatEntry[]) => void;
}

export class ChatStore {
  private client: TdClient;
  private users: UserStore;
  private chats: Map<number, ChatEntry> = new Map();
  private positions: Map<string, Map<number, PositionInfo>> = new Map();
  private subs: Sub[] = [];
  private changeListeners: Array<() => void> = [];
  private activeLoads: Map<string, Promise<boolean>> = new Map();
  private initializedLists: Set<string> = new Set();
  private exhaustedLists: Set<string> = new Set();
  private fullyLoadedLists: Set<string> = new Set();
  // 自己的 user id，来自 TDLib 的 updateOption('my_id')。和自己的私聊就是
  // 「我的收藏」，TDLib 不做任何标记，只能靠这个 id 认出来（issue #8）。
  // 0 表示还没收到。
  private selfId: number = 0;
  private groupCallChats: Map<number, number> = new Map();
  private chatSupergroupIds: Map<number, number> = new Map();
  private forumSupergroupIds: Set<number> = new Set();
  private groupCallLoading: Set<number> = new Set();
  private defaultBackgroundLight: TdObject | null = null;
  private defaultBackgroundDark: TdObject | null = null;
  private defaultBackgroundLightKnown: boolean = false;
  private defaultBackgroundDarkKnown: boolean = false;
  private notifyTimer: number = -1;
  private dirtyAllLists: boolean = false;
  private dirtyChatIds: Set<number> = new Set();

  constructor(client: TdClient, users: UserStore) {
    this.client = client;
    this.users = users;
    client.onUpdate('updateOption', (u: TdObject) => this.onOption(u));
    client.onUpdate('updateNewChat', (u: TdObject) => this.onNewChat(u));
    client.onUpdate('updateSupergroup', (u: TdObject) => this.onSupergroup(u));
    client.onUpdate('updateChatPosition', (u: TdObject) => this.onPosition(u));
    client.onUpdate('updateChatLastMessage', (u: TdObject) => this.onLastMessage(u));
    client.onUpdate('updateChatReadInbox', (u: TdObject) => this.onReadInbox(u));
    client.onUpdate('updateChatTitle', (u: TdObject) => this.onTitle(u));
    client.onUpdate('updateChatPhoto', (u: TdObject) => this.onPhoto(u));
    client.onUpdate('updateChatNotificationSettings', (u: TdObject) => this.onNotify(u));
    client.onUpdate('updateChatMessageAutoDeleteTime', (u: TdObject) => this.onAutoDelete(u));
    client.onUpdate('updateChatIsMarkedAsUnread', (u: TdObject) => this.onMarkedUnread(u));
    client.onUpdate('updateChatBackground', (u: TdObject) => this.onBackground(u));
    client.onUpdate('updateChatTheme', (u: TdObject) => this.onTheme(u));
    client.onUpdate('updateDefaultBackground', (u: TdObject) => this.onDefaultBackground(u));
    client.onUpdate('updateChatVideoChat', (u: TdObject) => this.onVideoChat(u));
    client.onUpdate('updateGroupCall', (u: TdObject) => this.onGroupCall(u));
  }

  subscribe(listener: (chats: ChatEntry[]) => void, listKey: string = MAIN): () => void {
    const sub: Sub = { listKey, listener };
    this.subs = [...this.subs, sub];
    listener(this.getChats(listKey));
    return (): void => {
      this.subs = this.subs.filter((s: Sub) => s !== sub);
    };
  }

  // Lightweight invalidation signal for derived UI such as folder unread
  // badges. Unlike subscribe(), this does not rebuild and sort a chat list on
  // every TDLib update.
  subscribeChanges(listener: () => void): () => void {
    this.changeListeners = [...this.changeListeners, listener];
    listener();
    return (): void => {
      this.changeListeners = this.changeListeners.filter((l: () => void) => l !== listener);
    };
  }

  // Every cached chat across all lists (main/archive/folders). Used to request
  // avatars regardless of which list a chat was surfaced through.
  private onSupergroup(update: TdObject): void {
    const supergroup = update['supergroup'] as TdObject | undefined;
    if (supergroup === undefined) {
      return;
    }
    const id: number = (supergroup['id'] as number | undefined) ?? 0;
    if (id <= 0) {
      return;
    }
    if ((supergroup['is_forum'] as boolean | undefined) ?? false) {
      this.forumSupergroupIds.add(id);
    } else {
      this.forumSupergroupIds.delete(id);
    }
  }

  // 话题群（forum supergroup）：打开时应进入话题列表而非普通消息流。
  isForum(chatId: number): boolean {
    const supergroupId = this.chatSupergroupIds.get(chatId);
    return supergroupId !== undefined && this.forumSupergroupIds.has(supergroupId);
  }

  allEntries(): ChatEntry[] {
    return Array.from(this.chats.values());
  }

  getChats(listKey: string = MAIN): ChatEntry[] {
    const bucket = this.positions.get(listKey);
    if (bucket === undefined) {
      return [];
    }
    const list: ChatEntry[] = [];
    bucket.forEach((_pos: PositionInfo, id: number) => {
      const e = this.chats.get(id);
      if (e !== undefined) {
        list.push(e);
      }
    });
    list.sort((a: ChatEntry, b: ChatEntry) => {
      const pa = bucket.get(a.id)!;
      const pb = bucket.get(b.id)!;
      if (pa.isPinned !== pb.isPinned) {
        return pa.isPinned ? -1 : 1;
      }
      return compareOrderDesc(pa.order, pb.order);
    });
    return list;
  }

  // Pinning is per chat list: a chat can be pinned in a folder but not in main.
  isPinned(listKey: string, chatId: number): boolean {
    const pos = this.positions.get(listKey)?.get(chatId);
    return pos !== undefined && pos.isPinned;
  }

  isArchived(chatId: number): boolean {
    return this.positions.get('archive')?.has(chatId) === true;
  }

  isInFolder(folderId: number, chatId: number): boolean {
    return this.positions.get(`folder:${folderId}`)?.has(chatId) === true;
  }

  hasArchive(): boolean {
    const b = this.positions.get('archive');
    return b !== undefined && b.size > 0;
  }

  isListExhausted(listKey: string): boolean {
    return this.exhaustedLists.has(listKey);
  }

  // Count of unmuted chats with unread messages in a list, computed from loaded
  // chats. Used for folder tab badges (TDLib's updateUnreadChatCount is emitted
  // only for the main and archive lists, not for chat folders).
  unreadChatCount(listKey: string): number {
    const bucket = this.positions.get(listKey);
    if (bucket === undefined) {
      return 0;
    }
    let count = 0;
    bucket.forEach((_pos: PositionInfo, id: number) => {
      const e = this.chats.get(id);
      // 只数有未读消息的会话，"手动标记为未读"不计入——与「全部」角标读的
      // unread_unmuted_count 同一个口径（见 UnreadCountStore）。
      if (e !== undefined && e.unreadCount > 0 && !e.isMuted) {
        count += 1;
      }
    });
    return count;
  }

  photoFileIdOf(chatId: number): number {
    const e = this.chats.get(chatId);
    return e !== undefined ? e.photoFileId : 0;
  }

  entryOf(chatId: number): ChatEntry | undefined {
    return this.chats.get(chatId);
  }

  // Remove the badge immediately once the UI has actually shown the newest
  // message. TDLib remains authoritative and will still send
  // updateChatReadInbox; this only bridges its delay (and the local join-service
  // edge case where that update can otherwise stay at unread_count = 1).
  markReadLocally(chatId: number, readThroughId: number): void {
    const entry = this.chats.get(chatId);
    if (entry === undefined || readThroughId <= 0 || entry.lastMessageId <= 0 ||
      readThroughId < entry.lastMessageId ||
      (entry.unreadCount === 0 && !entry.isMarkedUnread)) {
      return;
    }
    const next = cloneEntry(entry);
    next.unreadCount = 0;
    next.isMarkedUnread = false;
    this.chats.set(chatId, next);
    this.notify(chatId);
  }

  defaultBackground(forDarkTheme: boolean): TdObject | null {
    return forDarkTheme ? this.defaultBackgroundDark : this.defaultBackgroundLight;
  }

  defaultBackgroundKnown(forDarkTheme: boolean): boolean {
    return forDarkTheme ? this.defaultBackgroundDarkKnown : this.defaultBackgroundLightKnown;
  }

  load(listKey: string = MAIN): Promise<boolean> {
    if (this.exhaustedLists.has(listKey)) {
      return Promise.resolve(true);
    }
    const active = this.activeLoads.get(listKey);
    if (active !== undefined) {
      return active;
    }
    const req: TdRequest = { '@type': 'loadChats' };
    req['chat_list'] = chatListOf(listKey);
    req['limit'] = PAGE_LIMIT;
    const task = this.client.send(req).then((_result: TdObject): boolean => {
      this.activeLoads.delete(listKey);
      return true;
    }).catch((error: TdError): boolean => {
      this.activeLoads.delete(listKey);
      if (error.code === 404) {
        this.exhaustedLists.add(listKey);
        return true;
      }
      console.error(`ChatStore.load(${listKey}) failed: ${error.message}`);
      return false;
    });
    this.activeLoads.set(listKey, task);
    return task;
  }

  // Request the first page at most once. Parent folder tabs and their child
  // lists can safely call this concurrently without consuming two TDLib pages.
  ensureLoaded(listKey: string = MAIN): Promise<boolean> {
    if (this.initializedLists.has(listKey)) {
      return Promise.resolve(true);
    }
    return this.load(listKey).then((success: boolean): boolean => {
      if (success) {
        this.initializedLists.add(listKey);
      }
      return success;
    });
  }

  async loadMore(listKey: string = MAIN): Promise<boolean> {
    return await this.load(listKey);
  }

  // 把一个列表一次性翻到底。
  //
  // 「所有」那个角标读的是 TDLib 的 updateUnreadChatCount——服务端真值，完整。
  // 分组的角标和分组列表却都只能按**本地已加载的会话**算（TDLib 不为分组下发
  // updateUnreadChatCount，见 unreadChatCount）。而分组此前只预取一页 30 条，
  // 于是两个口径对不上：issue #43 里「所有」显示 5 个群有新消息，某个分组只
  // 显示 3 个，退出重进变 4 个，还有一个哪个分组都找不到——那几个会话就排在
  // 这一页之外，本地根本不知道它们属于这个分组。
  //
  // 分组是定义在客户端已知会话之上的，翻到底是有界的；上限只是防呆。
  async ensureFullyLoaded(listKey: string): Promise<void> {
    if (this.fullyLoadedLists.has(listKey)) {
      return;
    }
    this.fullyLoadedLists.add(listKey);
    for (let page = 0; page < MAX_FULL_LOAD_PAGES; page++) {
      if (this.exhaustedLists.has(listKey)) {
        return;
      }
      const ok: boolean = await this.load(listKey);
      if (!ok) {
        // 网络失败：撤销标记，下次进来还能重试。
        this.fullyLoadedLists.delete(listKey);
        return;
      }
    }
    if (!this.exhaustedLists.has(listKey)) {
      console.warn(`ChatStore.ensureFullyLoaded(${listKey}) stopped at the ` +
        `${MAX_FULL_LOAD_PAGES}-page cap; its badge and list may still be incomplete`);
    }
  }

  // 分组定义变了（成员规则改动、增删分组）：之前"翻到底"的结论作废，
  // 让下一次 ensureFullyLoaded 重新翻。exhaustedLists 也要清——它是粘性的，
  // 不清的话新加入分组的会话永远取不回来。
  invalidateList(listKey: string): void {
    this.fullyLoadedLists.delete(listKey);
    this.exhaustedLists.delete(listKey);
    this.initializedLists.delete(listKey);
  }

  setAvatarPath(chatId: number, path: string): void {
    const e = this.chats.get(chatId);
    if (e === undefined || e.avatarPath === path) {
      return;
    }
    const c = cloneEntry(e);
    c.avatarPath = path;
    this.chats.set(chatId, c);
    this.notify(chatId);
  }

  private setPosition(listKey: string, id: number, order: string, isPinned: boolean): void {
    if (listKey === '') {
      return;
    }
    if (order === '0') {
      const b = this.positions.get(listKey);
      if (b !== undefined) {
        b.delete(id);
      }
      return;
    }
    let bucket = this.positions.get(listKey);
    if (bucket === undefined) {
      bucket = new Map();
      this.positions.set(listKey, bucket);
    }
    bucket.set(id, { order, isPinned });
  }

  private applyPositions(id: number, positions: TdObject[]): void {
    for (const p of positions) {
      const list = p['list'] as TdObject | undefined;
      if (list === undefined) {
        continue;
      }
      const key = listKeyOf(list);
      const order = (p['order'] as string | undefined) ?? '0';
      const isPinned = (p['is_pinned'] as boolean | undefined) ?? false;
      this.setPosition(key, id, order, isPinned);
    }
  }

  private senderName(message: TdObject | undefined): string {
    if (message === undefined) {
      return '';
    }
    const sender = message['sender_id'] as TdObject | undefined;
    if (sender === undefined) {
      return '';
    }
    if (sender['@type'] === 'messageSenderUser') {
      return this.users.displayName(sender['user_id'] as number);
    }
    if (sender['@type'] === 'messageSenderChat') {
      const c = this.chats.get(sender['chat_id'] as number);
      return c !== undefined ? c.title : '';
    }
    return '';
  }

  private smallPhotoId(photo: TdObject | undefined): number {
    if (photo === undefined) {
      return 0;
    }
    const small = photo['small'] as TdObject | undefined;
    if (small === undefined) {
      return 0;
    }
    return (small['id'] as number | undefined) ?? 0;
  }

  private videoChatId(videoChat: TdObject | undefined): number {
    return videoChat !== undefined
      ? ((videoChat['group_call_id'] as number | undefined) ?? 0) : 0;
  }

  private backgroundOf(value: Object | null | undefined): TdObject | null {
    return value !== undefined && value !== null ? value as TdObject : null;
  }

  private rememberGroupCall(chatId: number, previousId: number, groupCallId: number): void {
    if (previousId > 0 && this.groupCallChats.get(previousId) === chatId) {
      this.groupCallChats.delete(previousId);
    }
    if (groupCallId > 0) {
      this.groupCallChats.set(groupCallId, chatId);
      this.requestGroupCall(groupCallId);
    }
  }

  // chat.video_chat only carries the call id. Confirm is_active through
  // getGroupCall so scheduled/ended calls don't receive a LIVE badge.
  private requestGroupCall(groupCallId: number): void {
    if (groupCallId <= 0 || this.groupCallLoading.has(groupCallId)) { return; }
    this.groupCallLoading.add(groupCallId);
    const request: TdRequest = { '@type': 'getGroupCall' };
    request['group_call_id'] = groupCallId;
    this.client.send(request).then((groupCall: TdObject): void => {
      this.groupCallLoading.delete(groupCallId);
      this.applyGroupCall(groupCall);
    }).catch((error: TdError): void => {
      this.groupCallLoading.delete(groupCallId);
      if (error.code !== 404) {
        console.error(`ChatStore.getGroupCall(${groupCallId}) failed: ${error.message}`);
      }
    });
  }

  private applyGroupCall(groupCall: TdObject): void {
    const groupCallId = (groupCall['id'] as number | undefined) ?? 0;
    const chatId = this.groupCallChats.get(groupCallId);
    if (chatId === undefined) { return; }
    const entry = this.chats.get(chatId);
    if (entry === undefined || entry.liveGroupCallId !== groupCallId) { return; }
    const isLive = (groupCall['is_active'] as boolean | undefined) ?? false;
    const isRtmpLive = (groupCall['is_rtmp_stream'] as boolean | undefined) ?? false;
    if (entry.isLive === isLive && entry.isRtmpLive === isRtmpLive) { return; }
    const next = cloneEntry(entry);
    next.isLive = isLive;
    next.isRtmpLive = isRtmpLive;
    this.chats.set(chatId, next);
    this.notify(chatId);
  }

  private onNewChat(update: TdObject): void {
    const chat = update['chat'] as TdObject | undefined;
    if (chat === undefined) {
      return;
    }
    const id = chat['id'] as number;
    // 话题群识别需要 chatId → supergroupId 映射（is_forum 在 supergroup 上）。
    const chatType = chat['type'] as TdObject | undefined;
    if (chatType !== undefined && (chatType['@type'] as string | undefined) === 'chatTypeSupergroup') {
      const supergroupId: number = (chatType['supergroup_id'] as number | undefined) ?? 0;
      if (supergroupId > 0) {
        this.chatSupergroupIds.set(id, supergroupId);
      }
    }
    const previous = this.chats.get(id);
    const previousGroupCallId = previous?.liveGroupCallId ?? 0;
    const title = (chat['title'] as string | undefined) ?? '';
    const lastMsg = chat['last_message'] as TdObject | undefined;
    const groupCallId = this.videoChatId(chat['video_chat'] as TdObject | undefined);
    const photoFileId = this.smallPhotoId(chat['photo'] as TdObject | undefined);
    const samePhoto = previous !== undefined && previous.photoFileId === photoFileId;
    const sameGroupCall = previous !== undefined && previous.liveGroupCallId === groupCallId;
    const entry: ChatEntry = {
      id,
      revision: previous !== undefined ? previous.revision + 1 : 0,
      title,
      isMuted: isMutedFrom(chat['notification_settings'] as TdObject | undefined),
      usesDefaultMute: usesDefaultMuteFrom(chat['notification_settings'] as TdObject | undefined),
      unreadCount: ChatStore.effectiveUnread(
        (chat['unread_count'] as number | undefined) ?? 0,
        (chat['last_read_inbox_message_id'] as number | undefined) ?? 0,
        lastMsg !== undefined ? ((lastMsg['id'] as number | undefined) ?? 0) : 0),
      lastMessageText: formatPreview(lastMsg ?? null),
      lastMessageDate: lastMsg !== undefined ? ((lastMsg['date'] as number | undefined) ?? 0) : 0,
      lastMessageId: lastMsg !== undefined ? ((lastMsg['id'] as number | undefined) ?? 0) : 0,
      lastSenderName: this.senderName(lastMsg),
      photoFileId,
      // getChat/updateNewChat may refresh a chat after its avatar has already
      // completed. Preserve the resolved path when the photo itself is unchanged.
      avatarPath: samePhoto ? previous!.avatarPath : '',
      initials: computeInitials(title),
      autoDeleteTime: (chat['message_auto_delete_time'] as number | undefined) ?? 0,
      kind: chatKindOf(chat['type'] as TdObject | undefined),
      isMarkedUnread: (chat['is_marked_as_unread'] as boolean | undefined) ?? false,
      isSavedMessages: this.selfId !== 0 && id === this.selfId,
      background: this.backgroundOf(chat['background']),
      themeName: (chat['theme_name'] as string | undefined) ?? '',
      liveGroupCallId: groupCallId,
      isLive: sameGroupCall ? previous!.isLive : false,
      isRtmpLive: sameGroupCall ? previous!.isRtmpLive : false
    };
    this.chats.set(id, entry);
    this.rememberGroupCall(id, previousGroupCallId, groupCallId);
    const positions = (chat['positions'] as TdObject[] | undefined) ?? [];
    this.applyPositions(id, positions);
    this.notify();
  }

  // my_id 通常在会话列表出现之前就到了；万一晚到，把已经建好的那条重标一次。
  // 走 cloneEntry 是必要的——它会把 revision 加一，行 key 才会变、列表才会
  // 重画（否则标题仍是自己的昵称）。
  private onOption(update: TdObject): void {
    if (((update['name'] as string | undefined) ?? '') !== 'my_id') {
      return;
    }
    const valueObject = update['value'] as TdObject | undefined;
    const raw = valueObject !== undefined ? valueObject['value'] : undefined;
    // int53 在 JSON 里可能是数字也可能是字符串。
    const id: number = typeof raw === 'number' ? raw as number : Number(`${raw ?? 0}`);
    if (!Number.isFinite(id) || id <= 0 || id === this.selfId) {
      return;
    }
    this.selfId = id;
    const existing = this.chats.get(id);
    if (existing === undefined || existing.isSavedMessages) {
      return;
    }
    const next = cloneEntry(existing);
    next.isSavedMessages = true;
    this.chats.set(id, next);
    this.notify(id);
  }

  private onPosition(update: TdObject): void {
    const id = update['chat_id'] as number;
    const pos = update['position'] as TdObject | undefined;
    if (pos === undefined) {
      return;
    }
    this.applyPositions(id, [pos]);
    this.notify();
  }

  private onLastMessage(update: TdObject): void {
    const id = update['chat_id'] as number;
    const e = this.chats.get(id);
    if (e === undefined) {
      return;
    }
    const lastMsg = update['last_message'] as TdObject | undefined;
    const c = cloneEntry(e);
    c.lastMessageText = formatPreview(lastMsg ?? null);
    c.lastMessageDate = lastMsg !== undefined ? ((lastMsg['date'] as number | undefined) ?? 0) : 0;
    c.lastMessageId = lastMsg !== undefined ? ((lastMsg['id'] as number | undefined) ?? 0) : 0;
    c.lastSenderName = this.senderName(lastMsg);
    this.chats.set(id, c);
    const positions = update['positions'] as TdObject[] | undefined;
    if (positions !== undefined) {
      this.applyPositions(id, positions);
      this.notify();
    } else {
      this.notify(id);
    }
  }

  private onReadInbox(update: TdObject): void {
    const id = update['chat_id'] as number;
    const e = this.chats.get(id);
    if (e === undefined) {
      return;
    }
    const c = cloneEntry(e);
    c.unreadCount = ChatStore.effectiveUnread(
      (update['unread_count'] as number | undefined) ?? 0,
      (update['last_read_inbox_message_id'] as number | undefined) ?? 0,
      e.lastMessageId);
    this.chats.set(id, c);
    this.notify(id);
  }

  private onTitle(update: TdObject): void {
    const id = update['chat_id'] as number;
    const e = this.chats.get(id);
    if (e === undefined) {
      return;
    }
    const title = (update['title'] as string | undefined) ?? '';
    const c = cloneEntry(e);
    c.title = title;
    c.initials = computeInitials(title);
    this.chats.set(id, c);
    this.notify(id);
  }

  private onPhoto(update: TdObject): void {
    const id = update['chat_id'] as number;
    const e = this.chats.get(id);
    if (e === undefined) {
      return;
    }
    const c = cloneEntry(e);
    c.photoFileId = this.smallPhotoId(update['photo'] as TdObject | undefined);
    c.avatarPath = '';
    this.chats.set(id, c);
    this.notify(id);
  }

  private onNotify(update: TdObject): void {
    const id = update['chat_id'] as number;
    const e = this.chats.get(id);
    if (e === undefined) {
      return;
    }
    const c = cloneEntry(e);
    const ns = update['notification_settings'] as TdObject | undefined;
    c.isMuted = isMutedFrom(ns);
    c.usesDefaultMute = usesDefaultMuteFrom(ns);
    this.chats.set(id, c);
    this.notify(id);
  }

  private onMarkedUnread(update: TdObject): void {
    const id = update['chat_id'] as number;
    const e = this.chats.get(id);
    if (e === undefined) {
      return;
    }
    const c = cloneEntry(e);
    c.isMarkedUnread = (update['is_marked_as_unread'] as boolean | undefined) ?? false;
    this.chats.set(id, c);
    this.notify(id);
  }

  private onBackground(update: TdObject): void {
    const id = update['chat_id'] as number;
    const e = this.chats.get(id);
    if (e === undefined) {
      return;
    }
    const background = this.backgroundOf(update['background']);
    if (e.background === background) {
      return;
    }
    const c = cloneEntry(e);
    c.background = background;
    this.chats.set(id, c);
    this.notify(id);
  }

  private onTheme(update: TdObject): void {
    const id = update['chat_id'] as number;
    const e = this.chats.get(id);
    if (e === undefined) {
      return;
    }
    const themeName = (update['theme_name'] as string | undefined) ?? '';
    if (e.themeName === themeName) {
      return;
    }
    const c = cloneEntry(e);
    c.themeName = themeName;
    this.chats.set(id, c);
    this.notify(id);
  }

  private onDefaultBackground(update: TdObject): void {
    const forDarkTheme = (update['for_dark_theme'] as boolean | undefined) ?? false;
    const background = this.backgroundOf(update['background']);
    if (forDarkTheme) {
      this.defaultBackgroundDark = background;
      this.defaultBackgroundDarkKnown = true;
    } else {
      this.defaultBackgroundLight = background;
      this.defaultBackgroundLightKnown = true;
    }
    console.info(
      `[ChatBackground] default dark=${forDarkTheme} background=${background !== null}`
    );
    this.notify();
  }

  private onAutoDelete(update: TdObject): void {
    const id = update['chat_id'] as number;
    const e = this.chats.get(id);
    if (e === undefined) {
      return;
    }
    const c = cloneEntry(e);
    c.autoDeleteTime = (update['message_auto_delete_time'] as number | undefined) ?? 0;
    this.chats.set(id, c);
    this.notify(id);
  }

  private onVideoChat(update: TdObject): void {
    const chatId = (update['chat_id'] as number | undefined) ?? 0;
    const entry = this.chats.get(chatId);
    if (entry === undefined) { return; }
    const groupCallId = this.videoChatId(update['video_chat'] as TdObject | undefined);
    const previousId = entry.liveGroupCallId;
    const next = cloneEntry(entry);
    next.liveGroupCallId = groupCallId;
    // A newly announced id can still be scheduled. Keep the badge hidden
    // until getGroupCall/updateGroupCall confirms is_active.
    next.isLive = false;
    next.isRtmpLive = false;
    this.chats.set(chatId, next);
    this.rememberGroupCall(chatId, previousId, groupCallId);
    this.notify(chatId);
  }

  private onGroupCall(update: TdObject): void {
    const groupCall = update['group_call'] as TdObject | undefined;
    if (groupCall !== undefined) { this.applyGroupCall(groupCall); }
  }

  // Phantom-unread recovery: Telegram can leave unread_count stuck (commonly 1)
  // when the counted message was deleted before this session ever saw it (e.g.
  // a bot removing "user joined" notifications). The state is self-inconsistent
  // — the read watermark already covers the chat's newest message — and
  // viewMessages cannot clear it because nothing viewable is left. Trust what
  // the watermark proves over the raw counter.
  private static effectiveUnread(unread: number, lastReadInboxId: number,
    lastMessageId: number): number {
    const suppressed: boolean = unread > 0 && lastMessageId > 0 && lastReadInboxId >= lastMessageId;
    if (suppressed) {
      // 诊断：反馈过"有些会话不显示未读数"。这里是**唯一**会把非零未读抹成 0
      // 的地方（另外两处是本地摘角标和 TDLib 自己下发），三个数一起打才判断
      // 得出是真幽灵未读还是误伤。只在真抹掉时打。
      console.warn(`effectiveUnread suppressed unread=${unread}` +
        ` lastRead=${lastReadInboxId} lastMsg=${lastMessageId}`);
    }
    return suppressed ? 0 : unread;
  }

  // Mark lists dirty and schedule one coalesced flush. A field-only change
  // passes its chat id so only lists actually containing that chat rebuild;
  // membership/order changes (positions) omit it and dirty every list.
  private notify(chatId?: number): void {
    if (chatId === undefined) {
      this.dirtyAllLists = true;
    } else {
      this.dirtyChatIds.add(chatId);
    }
    if (this.notifyTimer !== -1) {
      return;
    }
    // Trailing throttle, deliberately NOT re-armed by further updates: a
    // continuous update storm still flushes every window instead of starving.
    this.notifyTimer = setTimeout((): void => {
      this.notifyTimer = -1;
      this.flushNotify();
    }, NOTIFY_COALESCE_MS);
  }

  private flushNotify(): void {
    const all = this.dirtyAllLists;
    const dirty = this.dirtyChatIds;
    this.dirtyAllLists = false;
    this.dirtyChatIds = new Set();
    for (const s of this.subs) {
      if (all || this.listContainsAny(s.listKey, dirty)) {
        s.listener(this.getChats(s.listKey));
      }
    }
    for (const listener of this.changeListeners) {
      listener();
    }
  }

  private listContainsAny(listKey: string, ids: Set<number>): boolean {
    const bucket = this.positions.get(listKey);
    if (bucket === undefined) {
      return false;
    }
    for (const id of ids) {
      if (bucket.has(id)) {
        return true;
      }
    }
    return false;
  }
}
