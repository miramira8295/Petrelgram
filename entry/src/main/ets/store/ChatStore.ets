import { TdClient, TimerFns } from '../tdkit/TdClient';
import { TdObject, TdRequest, TdError } from '../tdkit/TdTypes';
import { UserStore } from './UserStore';
import { ChatEntry, PositionInfo, cloneEntry, computeInitials, compareOrderDesc, effectiveMuted, isMutedFrom, usesDefaultMuteFrom, chatKindOf } from './ChatEntry';
import { scopeMutedForKind } from './ScopeMuteStore';
import { listKeyOf, chatListOf } from './ListKey';
import { formatPreview } from '../util/formatPreview';
import { logE, logI, logW } from '../util/log';

const PAGE_LIMIT: number = 30;
const MAIN: string = 'main';
// TDLib update bursts (e.g. read-inbox advancing while the user scrolls a chat)
// arrive many times per frame. Rebuilding and re-sorting every subscribed list
// per update stalls the UI thread, so notifications are coalesced into one
// flush per window.
const NOTIFY_COALESCE_MS: number = 80;
// A received message changes the row through two independent TDLib updates.
// TDLib can deliberately hold updateChatReadInbox for about 100ms, so stage a
// lone half per chat and publish it only after the counterpart or this bound.
const ROW_SYNC_WAIT_MS: number = 160;
// Let back-to-back TDLib updates from a multi-message burst settle before the
// staged row is committed. The hard wait above still caps the total latency.
const ROW_SYNC_SETTLE_MS: number = 16;
// A counterpart arriving just after the hard bound belongs to the row we just
// released, not to a new pair. Keep that association briefly, then expire it.
const ROW_SYNC_LATE_MATCH_MS: number = 320;
// 分组列表最多连翻多少页。分组通常只有几十个会话，这个上限只是防呆——
// 真被撞上会打日志，不会悄悄截断（见 ensureFullyLoaded）。
const MAX_FULL_LOAD_PAGES: number = 20;

interface Sub {
  listKey: string;
  listener: (chats: ChatEntry[]) => void;
}

type RowSyncHalf = 'lastMessage' | 'unread';

interface PendingRowSync {
  hasLastMessage: boolean;
  lastMessage: TdObject | null;
  positionUpdates: TdObject[];
  affectsPositions: boolean;
  hasUnread: boolean;
  baseRawUnreadCount: number;
  rawUnreadCount: number;
  lastReadInboxId: number;
  clearMarkedUnread: boolean;
  sawIncomingLast: boolean;
  latestIncomingLastId: number;
  incomingTailCount: number;
  unreadCreditCount: number;
  unreadAdvanceCount: number;
  timeoutTimer: number;
  settleTimer: number;
}

interface LateRowSync {
  half: RowSyncHalf;
  units: number;
  lastMessageId: number;
  expiryTimer: number;
}

export class ChatStore {
  private client: TdClient;
  private users: UserStore;
  private chats: Map<number, ChatEntry> = new Map();
  private positions: Map<string, Map<number, PositionInfo>> = new Map();
  // Position updates are much more frequent than list opens. Keep the sorted
  // identity sequence for every list that has actually been read, then move
  // only the affected chat when TDLib changes its position. getChats() still
  // returns a fresh snapshot, but no longer rebuilds and sorts hundreds of
  // entries for every coalesced notification.
  private orderedChatIds: Map<string, number[]> = new Map();
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
  private administeredDirectMessagesSupergroupIds: Set<number> = new Set();
  private groupCallLoading: Set<number> = new Set();
  private defaultBackgroundLight: TdObject | null = null;
  private defaultBackgroundDark: TdObject | null = null;
  private defaultBackgroundLightKnown: boolean = false;
  private defaultBackgroundDarkKnown: boolean = false;
  private timer: TimerFns;
  private notifyTimer: number = -1;
  private pendingRowSync: Map<number, PendingRowSync> = new Map();
  private lateRowSync: Map<number, LateRowSync> = new Map();
  private dirtyAllLists: boolean = false;
  private dirtyChatIds: Set<number> = new Set();

  constructor(client: TdClient, users: UserStore, timer?: TimerFns) {
    this.client = client;
    this.users = users;
    this.timer = timer ?? {
      setTimeout: (cb: () => void, ms: number): number => setTimeout(cb, ms),
      clearTimeout: (id: number): void => clearTimeout(id)
    };
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
    if ((supergroup['is_administered_direct_messages_group'] as boolean | undefined) ?? false) {
      this.administeredDirectMessagesSupergroupIds.add(id);
    } else {
      this.administeredDirectMessagesSupergroupIds.delete(id);
    }
  }

  // 话题群（forum supergroup）：打开时应进入话题列表而非普通消息流。
  isForum(chatId: number): boolean {
    const supergroupId = this.chatSupergroupIds.get(chatId);
    return supergroupId !== undefined && this.forumSupergroupIds.has(supergroupId);
  }

  // Only the administrators' aggregate direct-messages group needs a sender
  // picker. The other party's channel DM is a normal one-to-one chat.
  isAdministeredDirectMessagesGroup(chatId: number): boolean {
    const supergroupId = this.chatSupergroupIds.get(chatId);
    return supergroupId !== undefined &&
      this.administeredDirectMessagesSupergroupIds.has(supergroupId);
  }

  allEntries(): ChatEntry[] {
    return Array.from(this.chats.values());
  }

  getChats(listKey: string = MAIN): ChatEntry[] {
    const bucket = this.positions.get(listKey);
    if (bucket === undefined) {
      return [];
    }
    let ordered = this.orderedChatIds.get(listKey);
    if (ordered === undefined) {
      ordered = [];
      bucket.forEach((_pos: PositionInfo, id: number): void => {
        if (this.chats.has(id)) {
          ordered!.push(id);
        }
      });
      ordered.sort((a: number, b: number): number => this.compareChatPosition(listKey, a, b));
      this.orderedChatIds.set(listKey, ordered);
    }
    const list: ChatEntry[] = [];
    for (const id of ordered) {
      const entry = this.chats.get(id);
      if (entry !== undefined) {
        list.push(entry);
      }
    }
    return list;
  }

  private compareChatPosition(listKey: string, a: number, b: number): number {
    const bucket = this.positions.get(listKey);
    const pa = bucket?.get(a);
    const pb = bucket?.get(b);
    if (pa === undefined) { return pb === undefined ? 0 : 1; }
    if (pb === undefined) { return -1; }
    if (pa.isPinned !== pb.isPinned) {
      return pa.isPinned ? -1 : 1;
    }
    return compareOrderDesc(pa.order, pb.order);
  }

  private removeOrderedChat(listKey: string, id: number): void {
    const ordered = this.orderedChatIds.get(listKey);
    if (ordered === undefined) {
      return;
    }
    const index = ordered.indexOf(id);
    if (index >= 0) {
      ordered.splice(index, 1);
    }
  }

  private insertOrderedChat(listKey: string, id: number): void {
    const ordered = this.orderedChatIds.get(listKey);
    if (ordered === undefined || !this.chats.has(id)) {
      return;
    }
    // Remove first so repeated/unchanged position pushes cannot duplicate an
    // identity in the cache. Then binary-search the new order.
    const previous = ordered.indexOf(id);
    if (previous >= 0) {
      ordered.splice(previous, 1);
    }
    let lo = 0;
    let hi = ordered.length;
    while (lo < hi) {
      const mid = (lo + hi) >> 1;
      if (this.compareChatPosition(listKey, id, ordered[mid]) < 0) {
        hi = mid;
      } else {
        lo = mid + 1;
      }
    }
    ordered.splice(lo, 0, id);
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

  // 这个会话在不在**任何一个**会话列表里（主列表 / 归档 / 任意文件夹）。
  //
  // 【它等价于"在不在我的会话列表中"】TDLib 只给**属于某个列表**的会话下发
  // position。路过点进去看了一眼、没有加入的公开群，chat 对象拿得到（所以
  // entryOf 有值），但它一个 position 都没有。
  //
  // 通知那边靠它挡掉"没加入的群还一直推消息"（用户 2026-09-09 实测）。
  // **会话不认识时不要用它下结论**：那时我们只是还没收到 chat 对象，
  // 按"不在列表里"处理会把真正该响的通知也吞掉。
  inAnyChatList(chatId: number): boolean {
    let found: boolean = false;
    this.positions.forEach((bucket: Map<number, PositionInfo>): void => {
      if (!found && bucket.has(chatId)) {
        found = true;
      }
    });
    return found;
  }

  // 至少出现在一个**非归档**列表里（主列表或任意文件夹）。
  //
  // 「分享到…」的候选集判据（用户定的规则）：在任何文件夹里的都该搜得到，
  // 只躺在归档里、不属于任何文件夹的不该出现。文件夹可以收录归档会话，所以
  // 不能写成 `!isArchived()`——那会把"归档 + 在文件夹里"的一起否掉。
  inNonArchiveList(chatId: number): boolean {
    let found: boolean = false;
    this.positions.forEach((bucket: Map<number, PositionInfo>, listKey: string): void => {
      if (!found && listKey !== 'archive' && bucket.has(chatId)) {
        found = true;
      }
    });
    return found;
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
      // 静音判定要过分类默认：整类静音的会话在这里也不该计入"未静音未读"
      // （issue #110 的同一根因）。
      if (e !== undefined && e.unreadCount > 0 &&
        !effectiveMuted(e, scopeMutedForKind(e.kind))) {
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
    const pending = this.pendingRowSync.get(chatId);
    const newestKnownId: number = pending !== undefined && pending.latestIncomingLastId > 0
      ? pending.latestIncomingLastId : (entry?.lastMessageId ?? 0);
    if (entry !== undefined && pending !== undefined && pending.sawIncomingLast &&
      readThroughId > 0 &&
      newestKnownId > 0 && readThroughId >= newestKnownId) {
      // The chat page has already displayed the staged tail. Fold that local
      // read into the same transaction instead of exposing either half first.
      pending.hasUnread = true;
      pending.rawUnreadCount = 0;
      pending.lastReadInboxId = Math.max(pending.lastReadInboxId, readThroughId);
      pending.clearMarkedUnread = true;
      this.scheduleRowSyncSettle(chatId, pending);
      return;
    }
    if (pending !== undefined) {
      // A pending unread-first update already proves that the committed badge
      // is stale. Likewise, an older visible id must not clear a staged tail.
      return;
    }
    if (entry === undefined || readThroughId <= 0 || entry.lastMessageId <= 0 ||
      readThroughId < entry.lastMessageId ||
      (entry.unreadCount === 0 && !entry.isMarkedUnread)) {
      return;
    }
    const next = cloneEntry(entry);
    next.unreadCount = 0;
    next.isMarkedUnread = false;
    this.chats.set(chatId, next);
    this.clearLateRowSync(chatId);
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
      logE(`ChatStore.load(${listKey}) failed: ${error.message}`);
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
      logW(`ChatStore.ensureFullyLoaded(${listKey}) stopped at the ` +
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
    this.orderedChatIds.delete(listKey);
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
      this.removeOrderedChat(listKey, id);
      return;
    }
    let bucket = this.positions.get(listKey);
    if (bucket === undefined) {
      bucket = new Map();
      this.positions.set(listKey, bucket);
    }
    bucket.set(id, { order, isPinned });
    this.insertOrderedChat(listKey, id);
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
        logE(`ChatStore.getGroupCall(${groupCallId}) failed: ${error.message}`);
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
    // A full chat is authoritative for both halves. Do not let an older staged
    // incremental update overwrite it when its timeout fires.
    this.discardPendingRowSync(id);
    this.clearLateRowSync(id);
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
    const rawLastMessage = chat['last_message'];
    const lastMsg: TdObject | null = rawLastMessage !== undefined && rawLastMessage !== null
      ? rawLastMessage as TdObject : null;
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
        this.messageIdOf(lastMsg)),
      rawUnreadCount: (chat['unread_count'] as number | undefined) ?? 0,
      lastReadInboxId: (chat['last_read_inbox_message_id'] as number | undefined) ?? 0,
      lastMessageText: formatPreview(lastMsg),
      lastMessageDate: lastMsg !== null ? ((lastMsg['date'] as number | undefined) ?? 0) : 0,
      lastMessageId: this.messageIdOf(lastMsg),
      lastSenderName: this.senderName(lastMsg ?? undefined),
      photoFileId,
      // getChat/updateNewChat may refresh a chat after its avatar has already
      // completed. Preserve the resolved path when the photo itself is unchanged.
      avatarPath: samePhoto ? previous!.avatarPath : '',
      initials: computeInitials(title),
      autoDeleteTime: (chat['message_auto_delete_time'] as number | undefined) ?? 0,
      kind: chatKindOf(chat['type'] as TdObject | undefined),
      isMarkedUnread: (chat['is_marked_as_unread'] as boolean | undefined) ?? false,
      // deleteChatHistory 的两个前置能力位。TDLib 没有针对它们的增量 update
      // （updateChat* 里没有对应的类），只随完整 chat 对象到达，所以这里是
      // 唯一的写入点；缺省取 false —— 宁可少给一个入口，也不要给一个必然
      // 报 "Can't delete history of X only for self" 的入口。
      canDeleteOnlyForSelf: (chat['can_be_deleted_only_for_self'] as boolean | undefined) ?? false,
      canDeleteForAllUsers: (chat['can_be_deleted_for_all_users'] as boolean | undefined) ?? false,
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
    // Saved Messages can contain forwarded messages reported as incoming but
    // never gains an unread counterpart. Release such a staged tail now that
    // the self-chat identity is known.
    this.commitPendingRowSync(id);
    this.clearLateRowSync(id);
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
    const pending = this.pendingRowSync.get(id);
    if (pending !== undefined) {
      pending.positionUpdates.push(pos);
      pending.affectsPositions = true;
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
    const rawLastMessage = update['last_message'];
    const lastMsg: TdObject | null = rawLastMessage !== undefined && rawLastMessage !== null
      ? rawLastMessage as TdObject : null;
    const positions = update['positions'] as TdObject[] | undefined;
    let pending = this.pendingRowSync.get(id);
    const baselineLastId: number = pending !== undefined && pending.latestIncomingLastId > 0
      ? pending.latestIncomingLastId : e.lastMessageId;
    const freshIncoming: boolean = this.isFreshIncomingTail(e, baselineLastId, lastMsg);
    const nextLastMessageId: number = this.messageIdOf(lastMsg);

    if (pending === undefined && freshIncoming) {
      if (e.lastReadInboxId >= nextLastMessageId) {
        // The read half was committed before this tail became known (for
        // example while the chat is open). The watermark proves the pair is
        // already complete, so no fallback timer is needed.
        this.clearLateRowSync(id);
        this.applyLastMessage(id, e, lastMsg, positions, true);
        return;
      }
      const late = this.lateRowSync.get(id);
      pending = late !== undefined
        ? this.takeLateRowSync(id, e)
        : this.createPendingRowSync(id, e.rawUnreadCount, e.lastReadInboxId);
    }

    if (pending !== undefined) {
      const updatesStagedIncoming: boolean = pending.sawIncomingLast &&
        nextLastMessageId > 0 && nextLastMessageId === pending.latestIncomingLastId;
      this.stagePendingLastMessage(pending, lastMsg, positions);
      if (freshIncoming) {
        pending.sawIncomingLast = true;
        pending.latestIncomingLastId = nextLastMessageId;
        pending.incomingTailCount += 1;
      } else if (!updatesStagedIncoming) {
        // An outgoing tail, deletion or backtrack supersedes the staged
        // preview. Publish it now. Preserve only a real outstanding side: an
        // edit of the committed row can still be followed by the unread-first
        // tail, while a staged incoming can still receive its delayed count.
        const sameCommittedIdentity: boolean = nextLastMessageId === e.lastMessageId;
        this.commitPendingRowSync(id,
          pending.sawIncomingLast || sameCommittedIdentity);
        return;
      }
      this.scheduleRowSyncSettle(id, pending);
      return;
    }

    const late = this.lateRowSync.get(id);
    if (late !== undefined && nextLastMessageId !== e.lastMessageId) {
      // A different authoritative tail supersedes an unmatched unread-first
      // generation. It must not credit some future incoming message.
      this.clearLateRowSync(id);
    }
    this.applyLastMessage(id, e, lastMsg, positions, false);
  }

  private onReadInbox(update: TdObject): void {
    const id = update['chat_id'] as number;
    const e = this.chats.get(id);
    if (e === undefined) {
      return;
    }
    const nextRawUnread: number = (update['unread_count'] as number | undefined) ?? 0;
    const nextLastReadInboxId: number =
      (update['last_read_inbox_message_id'] as number | undefined) ?? 0;
    const unreadAdvanced: boolean = nextRawUnread > e.rawUnreadCount ||
      (nextLastReadInboxId > e.lastReadInboxId && nextLastReadInboxId > e.lastMessageId);
    let pending = this.pendingRowSync.get(id);
    if (pending === undefined) {
      const late = this.lateRowSync.get(id);
      if (late !== undefined) {
        const matchesLateLast: boolean = late.half === 'lastMessage' &&
          (nextRawUnread > e.rawUnreadCount ||
            (late.lastMessageId > 0 && nextLastReadInboxId >= late.lastMessageId));
        if (matchesLateLast || (late.half === 'unread' && unreadAdvanced)) {
          pending = this.takeLateRowSync(id, e);
        } else {
          // A duplicate or an ordinary read must not consume an unmatched
          // generation. Keep the marker for its actual counterpart.
          if (nextRawUnread !== e.rawUnreadCount ||
            nextLastReadInboxId !== e.lastReadInboxId) {
            this.applyReadInbox(id, e, nextRawUnread, nextLastReadInboxId, false);
          }
          return;
        }
      } else if (unreadAdvanced) {
        pending = this.createPendingRowSync(id, e.rawUnreadCount, e.lastReadInboxId);
      } else {
        this.applyReadInbox(id, e, nextRawUnread, nextLastReadInboxId, false);
        return;
      }
    }

    const rawAdvance: number = Math.max(0,
      nextRawUnread - pending.baseRawUnreadCount);
    const previousReadInboxId: number = pending.lastReadInboxId;
    const coversStagedTail: boolean = pending.latestIncomingLastId > 0 &&
      nextLastReadInboxId >= pending.latestIncomingLastId;
    const watermarkAddsUnit: boolean = rawAdvance === 0 &&
      nextLastReadInboxId > previousReadInboxId &&
      nextLastReadInboxId > e.lastMessageId;
    const contributesToPair: boolean = rawAdvance > 0 || coversStagedTail || watermarkAddsUnit;
    if (contributesToPair || pending.hasUnread) {
      pending.hasUnread = true;
      pending.rawUnreadCount = nextRawUnread;
      pending.lastReadInboxId = nextLastReadInboxId;
      pending.unreadAdvanceCount = Math.max(pending.unreadAdvanceCount, rawAdvance);
      if (watermarkAddsUnit) {
        pending.unreadAdvanceCount += 1;
      }
      this.scheduleRowSyncSettle(id, pending);
      return;
    }

    // This update only changes the already committed side. Apply it through
    // the normal 80ms window and rebase the still-pending generation.
    if (nextRawUnread !== e.rawUnreadCount || nextLastReadInboxId !== e.lastReadInboxId) {
      this.applyReadInbox(id, e, nextRawUnread, nextLastReadInboxId, false);
    }
    pending.baseRawUnreadCount = nextRawUnread;
    pending.rawUnreadCount = nextRawUnread;
    pending.lastReadInboxId = nextLastReadInboxId;
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
    logI(
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
      logW(`effectiveUnread suppressed unread=${unread}` +
        ` lastRead=${lastReadInboxId} lastMsg=${lastMessageId}`);
    }
    return suppressed ? 0 : unread;
  }

  private messageIdOf(message: TdObject | null): number {
    return message !== null ? ((message['id'] as number | undefined) ?? 0) : 0;
  }

  // Only a strictly newer received tail needs an unread counterpart. TDLib's
  // direction flag is required here: an absent flag must not turn an edit or a
  // partially constructed test object into a received message.
  private isFreshIncomingTail(entry: ChatEntry, baselineLastId: number,
    lastMessage: TdObject | null): boolean {
    if (lastMessage === null || entry.isSavedMessages ||
      (lastMessage['is_outgoing'] as boolean | undefined) !== false) {
      return false;
    }
    const sendingState = lastMessage['sending_state'];
    const schedulingState = lastMessage['scheduling_state'];
    if ((sendingState !== undefined && sendingState !== null) ||
      (schedulingState !== undefined && schedulingState !== null)) {
      return false;
    }
    const nextLastMessageId = this.messageIdOf(lastMessage);
    return Number.isSafeInteger(nextLastMessageId) && nextLastMessageId > 0 &&
      nextLastMessageId > baselineLastId;
  }

  private createPendingRowSync(chatId: number, baseRawUnreadCount: number,
    baseLastReadInboxId: number): PendingRowSync {
    const pending: PendingRowSync = {
      hasLastMessage: false,
      lastMessage: null,
      positionUpdates: [],
      affectsPositions: false,
      hasUnread: false,
      baseRawUnreadCount,
      rawUnreadCount: baseRawUnreadCount,
      lastReadInboxId: baseLastReadInboxId,
      clearMarkedUnread: false,
      sawIncomingLast: false,
      latestIncomingLastId: 0,
      incomingTailCount: 0,
      unreadCreditCount: 0,
      unreadAdvanceCount: 0,
      timeoutTimer: -1,
      settleTimer: -1
    };
    this.pendingRowSync.set(chatId, pending);
    pending.timeoutTimer = this.timer.setTimeout((): void => {
      if (this.pendingRowSync.get(chatId) !== pending) {
        return;
      }
      this.commitPendingRowSync(chatId, true);
    }, ROW_SYNC_WAIT_MS);
    return pending;
  }

  private takeLateRowSync(chatId: number, entry: ChatEntry): PendingRowSync {
    const late = this.lateRowSync.get(chatId);
    this.clearLateRowSync(chatId);
    const pending = this.createPendingRowSync(
      chatId, entry.rawUnreadCount, entry.lastReadInboxId);
    if (late === undefined) {
      return pending;
    }
    if (late.half === 'lastMessage') {
      pending.sawIncomingLast = true;
      pending.latestIncomingLastId = late.lastMessageId;
      pending.incomingTailCount = late.units;
    } else {
      // This unread state is already canonical; only its unmatched pairing
      // credit needs to cross into the next bounded generation.
      pending.unreadCreditCount = late.units;
    }
    return pending;
  }

  private stagePendingLastMessage(pending: PendingRowSync,
    lastMessage: TdObject | null, positions: TdObject[] | undefined): void {
    pending.hasLastMessage = true;
    pending.lastMessage = lastMessage;
    if (positions === undefined) {
      return;
    }
    for (const position of positions) {
      pending.positionUpdates.push(position);
    }
    pending.affectsPositions = true;
  }

  private scheduleRowSyncSettle(chatId: number, pending: PendingRowSync): void {
    const unreadUnits: number = pending.unreadCreditCount + pending.unreadAdvanceCount;
    const watermarkCoversTail: boolean = pending.hasUnread &&
      pending.latestIncomingLastId > 0 &&
      pending.lastReadInboxId >= pending.latestIncomingLastId;
    const ready: boolean = pending.sawIncomingLast &&
      (watermarkCoversTail ||
        (unreadUnits > 0 && unreadUnits === pending.incomingTailCount));
    if (!ready) {
      if (pending.settleTimer !== -1) {
        this.timer.clearTimeout(pending.settleTimer);
        pending.settleTimer = -1;
      }
      return;
    }
    if (pending.settleTimer !== -1) {
      return;
    }
    pending.settleTimer = this.timer.setTimeout((): void => {
      if (this.pendingRowSync.get(chatId) === pending) {
        this.commitPendingRowSync(chatId);
      }
    }, ROW_SYNC_SETTLE_MS);
  }

  private discardPendingRowSync(chatId: number): void {
    const pending = this.pendingRowSync.get(chatId);
    if (pending === undefined) {
      return;
    }
    this.pendingRowSync.delete(chatId);
    this.timer.clearTimeout(pending.timeoutTimer);
    if (pending.settleTimer !== -1) {
      this.timer.clearTimeout(pending.settleTimer);
    }
  }

  private commitPendingRowSync(chatId: number,
    rememberOutstanding: boolean = false): void {
    const pending = this.pendingRowSync.get(chatId);
    if (pending === undefined) {
      return;
    }
    let lateHalf: RowSyncHalf | undefined = undefined;
    let lateUnits: number = 0;
    const unreadUnits: number = pending.unreadCreditCount + pending.unreadAdvanceCount;
    const watermarkCoversTail: boolean = pending.hasUnread &&
      pending.latestIncomingLastId > 0 &&
      pending.lastReadInboxId >= pending.latestIncomingLastId;
    if (rememberOutstanding && !watermarkCoversTail) {
      if (pending.incomingTailCount > unreadUnits) {
        lateHalf = 'lastMessage';
        lateUnits = pending.incomingTailCount - unreadUnits;
      } else if (unreadUnits > pending.incomingTailCount) {
        lateHalf = 'unread';
        lateUnits = unreadUnits - pending.incomingTailCount;
      }
    }
    this.discardPendingRowSync(chatId);
    const entry = this.chats.get(chatId);
    if (entry === undefined) {
      return;
    }
    const next = cloneEntry(entry);
    if (pending.hasLastMessage) {
      next.lastMessageText = formatPreview(pending.lastMessage);
      next.lastMessageDate = pending.lastMessage !== null
        ? ((pending.lastMessage['date'] as number | undefined) ?? 0) : 0;
      next.lastMessageId = this.messageIdOf(pending.lastMessage);
      next.lastSenderName = this.senderName(pending.lastMessage ?? undefined);
    }
    if (pending.hasUnread) {
      next.rawUnreadCount = pending.rawUnreadCount;
      next.lastReadInboxId = pending.lastReadInboxId;
    }
    if (pending.clearMarkedUnread) {
      next.isMarkedUnread = false;
    }
    // Recompute only after both staged fields are present. This also preserves
    // the existing phantom-unread recovery when the read half arrived first.
    next.unreadCount = ChatStore.effectiveUnread(
      next.rawUnreadCount, next.lastReadInboxId, next.lastMessageId);
    this.chats.set(chatId, next);
    if (pending.affectsPositions) {
      this.applyPositions(chatId, pending.positionUpdates);
    }
    if (lateHalf !== undefined && lateUnits > 0) {
      this.rememberLateRowSync(
        chatId, lateHalf, lateUnits, pending.latestIncomingLastId);
    }
    this.notifySoon(pending.affectsPositions ? undefined : chatId);
  }

  private rememberLateRowSync(chatId: number, half: RowSyncHalf,
    units: number, lastMessageId: number): void {
    this.clearLateRowSync(chatId);
    const late: LateRowSync = { half, units, lastMessageId, expiryTimer: -1 };
    this.lateRowSync.set(chatId, late);
    late.expiryTimer = this.timer.setTimeout((): void => {
      if (this.lateRowSync.get(chatId) === late) {
        this.lateRowSync.delete(chatId);
      }
    }, ROW_SYNC_LATE_MATCH_MS);
  }

  private clearLateRowSync(chatId: number): void {
    const late = this.lateRowSync.get(chatId);
    if (late === undefined) {
      return;
    }
    this.lateRowSync.delete(chatId);
    this.timer.clearTimeout(late.expiryTimer);
  }

  private applyLastMessage(chatId: number, entry: ChatEntry,
    lastMessage: TdObject | null, positions: TdObject[] | undefined,
    immediately: boolean): void {
    const next = cloneEntry(entry);
    next.lastMessageText = formatPreview(lastMessage);
    next.lastMessageDate = lastMessage !== null
      ? ((lastMessage['date'] as number | undefined) ?? 0) : 0;
    next.lastMessageId = this.messageIdOf(lastMessage);
    next.lastSenderName = this.senderName(lastMessage ?? undefined);
    next.unreadCount = ChatStore.effectiveUnread(
      next.rawUnreadCount, next.lastReadInboxId, next.lastMessageId);
    this.chats.set(chatId, next);
    if (positions !== undefined) {
      this.applyPositions(chatId, positions);
    }
    const dirtyChatId: number | undefined = positions !== undefined ? undefined : chatId;
    if (immediately) {
      this.notifySoon(dirtyChatId);
    } else {
      this.notify(dirtyChatId);
    }
  }

  private applyReadInbox(chatId: number, entry: ChatEntry, rawUnreadCount: number,
    lastReadInboxId: number, immediately: boolean): void {
    const next = cloneEntry(entry);
    next.rawUnreadCount = rawUnreadCount;
    next.lastReadInboxId = lastReadInboxId;
    next.unreadCount = ChatStore.effectiveUnread(
      next.rawUnreadCount, next.lastReadInboxId, next.lastMessageId);
    this.chats.set(chatId, next);
    if (immediately) {
      this.notifySoon(chatId);
    } else {
      this.notify(chatId);
    }
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
    this.scheduleNotify(NOTIFY_COALESCE_MS);
  }

  private notifySoon(chatId?: number): void {
    if (chatId === undefined) {
      this.dirtyAllLists = true;
    } else {
      this.dirtyChatIds.add(chatId);
    }
    if (this.notifyTimer !== -1) {
      this.timer.clearTimeout(this.notifyTimer);
      this.notifyTimer = -1;
    }
    this.scheduleNotify(0);
  }

  private scheduleNotify(delayMs: number): void {
    this.notifyTimer = this.timer.setTimeout((): void => {
      this.notifyTimer = -1;
      this.onNotifyTimer();
    }, delayMs);
  }

  private onNotifyTimer(): void {
    this.flushNotify();
  }

  private flushNotify(): void {
    const all = this.dirtyAllLists;
    const dirty = this.dirtyChatIds;
    this.dirtyAllLists = false;
    this.dirtyChatIds = new Set();
    // Multiple views can subscribe to the same folder (for example while a
    // cached tab is transitioning). Materialize that list once and fan out the
    // same immutable-by-convention snapshot instead of mapping it repeatedly.
    const snapshots: Map<string, ChatEntry[]> = new Map();
    for (const s of this.subs) {
      if (all || this.listContainsAny(s.listKey, dirty)) {
        let snapshot = snapshots.get(s.listKey);
        if (snapshot === undefined) {
          snapshot = this.getChats(s.listKey);
          snapshots.set(s.listKey, snapshot);
        }
        s.listener(snapshot);
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
