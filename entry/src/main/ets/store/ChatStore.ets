import { ChatListSubscription, ChatListPublicationMode } from './ChatListSubscription';
import { OrderSnapshot } from './chatListOrder';
import { ChatMirror } from './chatMirror';
import {
  buildChatEntry, effectiveUnread, messageIdOf, smallPhotoIdOf, videoChatIdOf, backgroundOf,
  compareChatEntries
} from './chatEntryFactory';
import { groupCallGone, groupCallIsLive } from '../util/liveCallState';
import { UnreadBadgeCounts } from '../util/unreadBadgeRule';
import { actionBarCanUnarchiveOf, actionBarKindOf } from '../util/chatActionBar';
import { TdClient, TimerFns } from '../tdkit/TdClient';
import { TdObject, TdRequest, TdError } from '../tdkit/TdTypes';
import { UserStore } from './UserStore';
import {
  ChatEntry, ChatKind, PositionInfo, cloneEntry, computeInitials, compareOrderDesc, effectiveMuted,
  isMutedFrom, usesDefaultMuteFrom, chatKindOf, lastMessageSendStateFrom, refreshOutboxSendState
} from './ChatEntry';
import { SCOPE_MUTE_EPOCH, scopeMutedForKind } from './ScopeMuteStore';
import { listKeyOf, chatListOf } from './ListKey';
import { formatPreview, previewThumbOf } from '../util/formatPreview';
import { str } from '../util/strings';
import { logE, logI, logW } from '../util/log';
import { photoHasAnimation } from '../util/photoAnimation';
import { senderChannelKey } from '../util/senderAvatarChannel';
import { invalidateSenderAnimation } from '../util/senderAnimationChannel';
import {
  TypingAction, TYPING_ACTION_TTL_MS, chatActionLabelOf, headerKindForChatKind, typingActionKind
} from '../util/typingIndicator';

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

interface ListSub {
  listKey: string;
  subscription: ChatListSubscription;
}

interface Sub {
  listKey: string;
  listener: (chats: ChatEntry[]) => void;
}

// 盯**单个会话**的订阅者：只要这个会话变了就通知，不管它在哪个列表里。
interface ChatSub {
  chatId: number;
  listener: () => void;
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
  // 位置索引与排序（第二层第一步：从 store 里剥出来的纯结构，见 chatListOrder）。
  // 第二层 B2 对账计数（worker 影子排序 vs 本地）。只影响日志。
  private orderShadowMatch: number = 0;
  private orderShadowMismatch: number = 0;
  private orderShadowSkew: number = 0;
  private entryShadowMatch: number = 0;
  // B4b-3 的镜像：按"将来要当权威"的规则维护（见 store/chatMirror）。UI 目前
  // 仍以 chats 为准，镜像先跑起来对账，切换时直接换读点。
  private mirror: ChatMirror = new ChatMirror();
  private pinEpochs: Map<string, number> = new Map<string, number>();
  // V2：worker 送来的列表成员与置顶。V1 关闭时，界面读的是这两份而不是 positions。
  private workerLists: Map<string, number[]> = new Map<string, number[]>();
  private workerPinned: Map<string, Set<number>> = new Map<string, Set<number>>();
  private entryShadowMismatch: number = 0;
  private entryShadowSkew: number = 0;
  // 位置最近一次「落地」的时刻。UI 的位置更新会被行级配对事务压后最多 ~320ms，
  // 所以只有当自己安静下来之后，拿 worker 的快照比对才有意义。
  private positionAppliedAt: number = 0;
  private orderShadowPending: Map<string, number[]> = new Map<string, number[]>();
  private orderShadowTimer: number = -1;
  // Position updates are much more frequent than list opens. Keep the sorted
  // identity sequence for every list that has actually been read, then move
  // only the affected chat when TDLib changes its position. getChats() still
  // returns a fresh snapshot, but no longer rebuilds and sorts hundreds of
  // entries for every coalesced notification.
  private orderedChatIds: Map<string, number[]> = new Map();
  private subs: Sub[] = [];
  private listSubs: ListSub[] = [];
  private changeListeners: Array<() => void> = [];
  private avatarListeners: Array<(chatIds: number[]) => void> = [];
  private dirtyAvatarChatIds: Set<number> = new Set();
  private chatSubs: ChatSub[] = [];
  private unreadBadgeListeners: Array<(keys: string[]) => void> = [];
  private dirtyUnreadBadgeKeys: Set<string> = new Set();
  private unreadBadgeCache: Map<string, UnreadBadgeCounts> = new Map();
  private unreadBadgeScopeEpoch: number = -1;
  private activeLoads: Map<string, Promise<boolean>> = new Map();
  private initializedLists: Set<string> = new Set();
  private exhaustedLists: Set<string> = new Set();
  private fullyLoadedLists: Set<string> = new Set();
  // 自己的 user id，来自 TDLib 的 updateOption('my_id')。和自己的私聊就是
  // 「我的收藏」，TDLib 不做任何标记，只能靠这个 id 认出来（issue #8）。
  // 0 表示还没收到。
  private selfId: number = 0;

  // 自己的 user id；0 = 还没收到 my_id。
  selfUserId(): number {
    return this.selfId;
  }
  // chat.photo（chatPhotoInfo）.has_animation。频道/匿名管理员以会话身份发言时，
  // 群聊气泡左侧的头像据此决定要不要取动态头像（issue #140）。不进 ChatEntry：
  // 条目是会话列表行的内容签名，这个标志列表行用不上。
  private animatedPhotoChats: Set<number> = new Set();
  private groupCallChats: Map<number, number> = new Map();
  private chatSupergroupIds: Map<number, number> = new Map();
  private supergroupMemberCounts: Map<number, number> = new Map();
  // 私聊 chatId → 对方 userId。Bot 私聊的话题模式标志在用户上（issue #206）。
  private chatPrivateUserIds: Map<number, number> = new Map();
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
  private chatActions: Map<number, Map<number, TypingAction>> = new Map();
  private chatActionTimers: Map<string, number> = new Map();

  constructor(client: TdClient, users: UserStore, timer?: TimerFns) {
    this.client = client;
    this.users = users;
    this.timer = timer ?? {
      setTimeout: (cb: () => void, ms: number): number => setTimeout(cb, ms),
      clearTimeout: (id: number): void => clearTimeout(id)
    };
    // V2：V1 的实体/位置/角标生产全部不工作，由 worker 投递的镜像与排序快照
    // 驱动。**唯一保留**的是「输入中」这条子系统：它要发送者显示名（UI 侧
    // UserStore）与 TTL 计时器，worker 那边没有用户表；它也不产生会话实体，
    // 只是把文案写进镜像。selfId 同理（my_id 决定 Saved Messages 与"自己"过滤）。
    // 元数据与本地状态这几条**不是会话实体**，worker 那条链不产生它们：
      //   · updateChatAction / updateUser —— 输入中（要 UserStore 里的显示名）
      //   · updateOption —— my_id，决定 Saved Messages 与"自己"过滤
      //   · updateNewChat / updateSupergroup —— 群与频道的能力位、话题群判定
      //     （isForumSupergroup / supergroupIdOf 等，ChatRow 与话题页都要用）
      //   · updateGroupCall —— 直播位（手机上没有别的来源）
    client.onUpdate('updateChatAction', (u: TdObject) => this.onChatAction(u));
    client.onUpdate('updateUser', (u: TdObject) => this.onChatActionUser(u));
    client.onUpdate('updateOption', (u: TdObject) => this.onOption(u));
    client.onUpdate('updateNewChat', (u: TdObject) => this.onNewChat(u));
    client.onUpdate('updateSupergroup', (u: TdObject) => this.onSupergroup(u));
    client.onUpdate('updateGroupCall', (u: TdObject) => this.onGroupCall(u));
    // 默认背景也是元数据：ChatBackgroundStore 靠它决定"没自定义背景时画什么"。
    client.onUpdate('updateDefaultBackground', (u: TdObject) => this.onDefaultBackground(u));

  }

  subscribe(listener: (chats: ChatEntry[]) => void, listKey: string = MAIN): () => void {
    const sub: Sub = { listKey, listener };
    this.subs = [...this.subs, sub];
    listener(this.getChats(listKey));
    return (): void => {
      this.subs = this.subs.filter((s: Sub) => s !== sub);
    };
  }

  // UI lists opt into lazy, visibility-aware publication. Legacy subscribers
  // (chat headers, sharing, services) retain their existing notification timing.
  subscribeList(listener: (chats: ChatEntry[]) => void, listKey: string,
    mode: () => ChatListPublicationMode): ChatListSubscription {
    const subscription = new ChatListSubscription(this.timer, mode,
      (): ChatEntry[] => this.getChats(listKey), listener, (): void => {
        this.listSubs = this.listSubs.filter((sub: ListSub): boolean => sub.subscription !== subscription);
      });
    this.listSubs.push({ listKey, subscription });
    subscription.refresh();
    return subscription;
  }

  hasChats(listKey: string): boolean {
    return this.listIds(listKey).length > 0;
  }

  private invalidateListSubscriptions(chatId: number | undefined, urgent: boolean): void {
    for (const sub of this.listSubs) {
      if (chatId === undefined || this.listIds(sub.listKey).indexOf(chatId) >= 0) {
        sub.subscription.invalidate(urgent);
      }
    }
  }

  // 盯单个会话。会话页用它，而不是 subscribe(listener, 'main')：后者只在会话
  // **位于那个列表里**时才通知（见 flushNotify 的 listContainsAny），归档里的会话、
  // 还没进任何列表的会话，它的更新会话页一条都收不到——陌生人私聊的操作条
  // （updateChatActionBar 在进会话之后才补发）因此永远出不来，标题栏也不刷新。
  subscribeChat(chatId: number, listener: () => void): () => void {
    const sub: ChatSub = { chatId, listener };
    this.chatSubs = [...this.chatSubs, sub];
    listener();
    return (): void => {
      this.chatSubs = this.chatSubs.filter((s: ChatSub) => s !== sub);
    };
  }

  // One initial replay, then only photo changes/path invalidations. This is
  // independent of list membership, so archive/folder-only chats work too.
  subscribeAvatars(listener: (chatIds: number[]) => void): () => void {
    this.avatarListeners = [...this.avatarListeners, listener];
    const ids: number[] = [];
    const source: Iterable<ChatEntry> = this.mirror.values();
    for (const entry of source) {
      if (entry.photoFileId !== 0 && entry.avatarPath === '') { ids.push(entry.id); }
    }
    if (ids.length > 0) { listener(ids); }
    return (): void => {
      this.avatarListeners = this.avatarListeners.filter((value: (chatIds: number[]) => void): boolean =>
        value !== listener);
    };
  }

  // General store invalidations. Badge consumers use subscribeUnreadBadges
  // so content-only updates do not cause unread aggregation.
  subscribeChanges(listener: () => void): () => void {
    this.changeListeners = [...this.changeListeners, listener];
    listener();
    return (): void => {
      this.changeListeners = this.changeListeners.filter((l: () => void) => l !== listener);
    };
  }

  // Replay existing lists once, then coalesce only badge-relevant list keys.
  // Scope-default mute changes are observed separately via SCOPE_MUTE_EPOCH.
  subscribeUnreadBadges(listener: (keys: string[]) => void): () => void {
    this.unreadBadgeListeners = [...this.unreadBadgeListeners, listener];
    listener(Array.from(this.workerLists.keys()));
    return (): void => {
      this.unreadBadgeListeners = this.unreadBadgeListeners.filter(
        (l: (keys: string[]) => void): boolean => l !== listener);
    };
  }

  // 元数据：群/私聊 id 映射（话题群判定要用）。实体的生产在 worker。
  private onNewChat(update: TdObject): void {
    const chat = update['chat'] as TdObject | undefined;
    if (chat === undefined) {
      return;
    }
    const id = chat['id'] as number | undefined;
    if (id === undefined) {
      return;
    }
    const chatType = chat['type'] as TdObject | undefined;
    if (chatType !== undefined && (chatType['@type'] as string | undefined) === 'chatTypeSupergroup') {
      const supergroupId: number = (chatType['supergroup_id'] as number | undefined) ?? 0;
      if (supergroupId > 0) {
        this.chatSupergroupIds.set(id, supergroupId);
      }
    } else if (chatType !== undefined && (chatType['@type'] as string | undefined) === 'chatTypePrivate') {
      const userId: number = (chatType['user_id'] as number | undefined) ?? 0;
      if (userId > 0) {
        this.chatPrivateUserIds.set(id, userId);
      }
    }
  }

  // my_id：Saved Messages 判定与"自己"过滤都要它。
  private onOption(update: TdObject): void {
    if (((update['name'] as string | undefined) ?? '') !== 'my_id') {
      return;
    }
    const valueObject = update['value'] as TdObject | undefined;
    const raw = valueObject !== undefined ? valueObject['value'] : undefined;
    const id: number = typeof raw === 'number' ? raw as number : Number(`${raw ?? 0}`);
    if (!Number.isFinite(id) || id <= 0 || id === this.selfId) {
      return;
    }
    selfIdGuard: {
      break selfIdGuard;
    }
    this.selfId = id;
  }

  private onDefaultBackground(update: TdObject): void {
    const dark: boolean = (update['for_dark_theme'] as boolean | undefined) ?? false;
    const background = update['background'] as TdObject | undefined;
    if (dark) {
      this.defaultBackgroundDark = background !== undefined ? background : null;
      this.defaultBackgroundDarkKnown = true;
    } else {
      this.defaultBackgroundLight = background !== undefined ? background : null;
      this.defaultBackgroundLightKnown = true;
    }
  }

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
    const memberCount: number = (supergroup['member_count'] as number | undefined) ?? 0;
    if (memberCount > 0) {
      this.supergroupMemberCounts.set(id, memberCount);
    }
    if ((supergroup['is_administered_direct_messages_group'] as boolean | undefined) ?? false) {
      this.administeredDirectMessagesSupergroupIds.add(id);
    } else {
      this.administeredDirectMessagesSupergroupIds.delete(id);
    }
  }

  // 是否是论坛超级群（不含开了话题模式的 Bot 私聊）。
  isForumSupergroup(chatId: number): boolean {
    const supergroupId = this.chatSupergroupIds.get(chatId);
    return supergroupId !== undefined && this.forumSupergroupIds.has(supergroupId);
  }

  supergroupIdOf(chatId: number): number {
    return this.chatSupergroupIds.get(chatId) ?? 0;
  }

  supergroupMemberCount(chatId: number): number {
    const supergroupId = this.chatSupergroupIds.get(chatId);
    return supergroupId !== undefined ? (this.supergroupMemberCounts.get(supergroupId) ?? 0) : 0;
  }

  // 按话题组织的会话：论坛超级群，或开了话题模式的 Bot 私聊（issue #206）。
  // 详情页据此挂顶栏话题横条、落到第一个话题。
  isForum(chatId: number): boolean {
    if (this.isForumSupergroup(chatId)) {
      return true;
    }
    const userId = this.chatPrivateUserIds.get(chatId);
    return userId !== undefined && this.users.botHasTopics(userId);
  }

  // 横条上给不给「新建话题」、长按给不给删除。只覆盖 Bot 私聊（allows_users_to_create_topics）；
  // 论坛超级群要按管理员/成员权限算，这一版不做（群里建话题仍走话题列表页）。
  canUserCreateTopics(chatId: number): boolean {
    const userId = this.chatPrivateUserIds.get(chatId);
    return userId !== undefined && this.users.botAllowsUserTopics(userId);
  }

  // Only the administrators' aggregate direct-messages group needs a sender
  // picker. The other party's channel DM is a normal one-to-one chat.
  isAdministeredDirectMessagesGroup(chatId: number): boolean {
    const supergroupId = this.chatSupergroupIds.get(chatId);
    return supergroupId !== undefined &&
      this.administeredDirectMessagesSupergroupIds.has(supergroupId);
  }

  allEntries(): ChatEntry[] {
    return this.mirror.values();
  }

  // 第二层 B2：worker 侧影子排序的对账入口。**只记日志，不改本地顺序。**
  //
  // 一致 → 说明 worker 用同一份更新流排出了同样的序列，切权威的前提成立；
  // 不一致 → 差异行会打出首个分歧下标与两侧长度，先查 worker 漏了哪类更新。


  // V2：worker 的排序快照就是列表成员与置顶的唯一来源。
  applyWorkerOrder(lists: OrderSnapshot[]): void {
    for (const snapshot of lists) {
      this.workerLists.set(snapshot.key, snapshot.ids);
      this.workerPinned.set(snapshot.key, new Set<number>(snapshot.pinned));
    }
    this.notify();
  }

  // 仅供用例：把 worker 的两条投递（列表成员 + 实体）直接灌进来。
  // 生产里只有 worker 会调 applyWorkerOrder / compareWorkerEntries。
  ingestForTest(entries: ChatEntry[], lists: OrderSnapshot[] = []): void {
    for (const list of lists) {
      this.workerLists.set(list.key, list.ids);
      this.workerPinned.set(list.key, new Set<number>(list.pinned));
      this.pinEpochs.set(list.key, this.pinEpoch(list.key) + 1);
    }
    this.compareWorkerEntries(entries);
  }

  private listIds(listKey: string): number[] {
    return this.workerLists.get(listKey) ?? [];
  }


  // 第二层 B4b：worker 侧影子实体的对账入口。**只记日志，不改本地数据。**
  //
  // 一致的字段集合见 compareChatEntries 的注释（revision/头像/发送者名等
  // 本来就各算各的，不参与比较）。
  compareWorkerEntries(entries: ChatEntry[]): void {
    const changed: number[] = this.mirror.apply(entries);
    if (changed.length === 0) {
      return;
    }
    for (const id of changed) {
      const mirrored = this.mirror.get(id);
      // 头像链靠这里：**任何**实体变化都把 id 标脏（含"头像被移除"，photo→0
      // 时要让 FileService 去 detach 并取消重试——V1 的 setChatEntry 就是这个口径）。
      this.dirtyAvatarChatIds.add(id);
      // 只把变了的会话标脏：不在任何列表里的会话不触发列表发布。
      this.notify(id);
    }
  }



  getChats(listKey: string = MAIN): ChatEntry[] {
    const list: ChatEntry[] = [];
    for (const id of this.listIds(listKey)) {
      const entry = this.mirror.get(id);
      if (entry !== undefined) {
        list.push(entry);
      }
    }
    return list;
  }


  // Order-only changes do not invalidate cached pin checks in list row keys.
  pinEpoch(listKey: string): number {
    return this.pinEpochs.get(listKey) ?? 0;
  }


  // Pinning is per chat list: a chat can be pinned in a folder but not in main.
  isPinned(listKey: string, chatId: number): boolean {
    return this.workerPinned.get(listKey)?.has(chatId) === true;
  }


  isArchived(chatId: number): boolean {
    return this.listIds('archive').indexOf(chatId) >= 0;
  }


  isInFolder(folderId: number, chatId: number): boolean {
    return this.listIds(`folder:${folderId}`).indexOf(chatId) >= 0;
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
    this.workerLists.forEach((ids: number[]): void => {
      if (ids.indexOf(chatId) >= 0) { found = true; }
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
    this.workerLists.forEach((ids: number[], key: string): void => {
      if (key !== 'archive' && ids.indexOf(chatId) >= 0) { found = true; }
    });
    return found;
  }


  hasArchive(): boolean {
    return this.listIds('archive').length > 0;
  }


  isListExhausted(listKey: string): boolean {
    return this.exhaustedLists.has(listKey);
  }

  // Count of unmuted chats with unread messages in a list, computed from loaded
  // chats. Used for folder tab badges (TDLib's updateUnreadChatCount is emitted
  // only for the main and archive lists, not for chat folders).
  unreadChatCount(listKey: string): number {
    return this.unreadChatBadge(listKey).unmuted;
  }

  // 角标口径（issue #155）：total = 有未读的会话数（含静音），unmuted = 其中未静音的。
  // 数字用 total，颜色看 unmuted——与 Telegram 同口径；主列表两个数由 TDLib 直接给
  // （UnreadCountStore），文件夹从已加载的会话里数，两边口径必须一致。
  unreadChatBadge(listKey: string): UnreadBadgeCounts {
    const epoch: number = AppStorage.get<number>(SCOPE_MUTE_EPOCH) ?? 0;
    if (epoch !== this.unreadBadgeScopeEpoch) {
      this.unreadBadgeScopeEpoch = epoch;
      this.unreadBadgeCache.clear();
    }
    let counts = this.unreadBadgeCache.get(listKey);
    if (counts === undefined) {
      let total: number = 0;
      let unmuted: number = 0;
      const badgeIds: number[] = this.listIds(listKey);
      for (const id of badgeIds) {
        const e = this.mirror.get(id);
        if (e !== undefined && e.unreadCount > 0) {
          total++;
          if (!effectiveMuted(e, scopeMutedForKind(e.kind))) { unmuted++; }
        }
      }
      counts = { total, unmuted };
      this.unreadBadgeCache.set(listKey, counts);
    }
    // Do not expose the mutable cached result to consumers.
    return { total: counts.total, unmuted: counts.unmuted };
  }


  private invalidateUnreadBadge(listKey: string): void {
    this.unreadBadgeCache.delete(listKey);
    this.dirtyUnreadBadgeKeys.add(listKey);
  }


  hasAnimatedPhoto(chatId: number): boolean {
    return this.animatedPhotoChats.has(chatId);
  }

  // 记动态头像标志；头像换了就作废已取到的动态头像。
  private notePhotoAnimation(chatId: number, photo: TdObject | undefined, photoChanged: boolean): void {
    if (photoHasAnimation(photo)) {
      this.animatedPhotoChats.add(chatId);
    } else {
      this.animatedPhotoChats.delete(chatId);
    }
    if (photoChanged) {
      invalidateSenderAnimation(senderChannelKey(chatId, false));
    }
  }

  photoFileIdOf(chatId: number): number {
    // 走 entryOf：V2 下实体在镜像里，直接查 chats 会永远返回 0——头像下载完成的
    // 回调正是靠它比对"这张图还是不是这个会话的"，返回 0 就等于永不落地。
    const e = this.entryOf(chatId);
    return e !== undefined ? e.photoFileId : 0;
  }

  entryOf(chatId: number): ChatEntry | undefined {
    return this.mirror.get(chatId);
  }


  // Remove the badge immediately once the UI has actually shown the newest
  // message. TDLib remains authoritative and will still send
  // updateChatReadInbox; this only bridges its delay (and the local join-service
  // edge case where that update can otherwise stay at unread_count = 1).
  markReadLocally(chatId: number, readThroughId: number): void {
    const mirrored = this.mirror.get(chatId);
    if (mirrored !== undefined && readThroughId >= mirrored.lastMessageId &&
      (mirrored.unreadCount > 0 || mirrored.isMarkedUnread)) {
      this.mirror.markRead(chatId);
      this.notify();
    }
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
  }

  setAvatarPath(chatId: number, path: string): void {
    const mirrored = this.mirror.get(chatId);
    if (mirrored === undefined || mirrored.avatarPath === path) {
      return;
    }
    this.mirror.setAvatarPath(chatId, path);
    // 路径被清空时 FileService 要重新走一遍（可能从 completedPaths 直接补回）。
    this.dirtyAvatarChatIds.add(chatId);
    this.notify(chatId);
  }





  senderNameOf(message: TdObject | undefined): string {
    return this.senderName(message);
  }

  private senderName(message: TdObject | undefined): string {
    if (message === undefined) {
      return '';
    }
    const sender = message['sender_id'] as TdObject | undefined;
    if (sender === undefined) {
      return (message['is_outgoing'] as boolean | undefined) === true ? str('sm_you') : '';
    }
    if (sender['@type'] === 'messageSenderUser') {
      const userId: number = (sender['user_id'] as number | undefined) ?? 0;
      if ((message['is_outgoing'] as boolean | undefined) === true || (this.selfId > 0 && userId === this.selfId)) {
        return str('sm_you');
      }
      return this.users.displayName(userId);
    }
    if (sender['@type'] === 'messageSenderChat') {
      const c = this.mirror.get(sender['chat_id'] as number);
      return c !== undefined ? c.title : '';
    }
    return '';
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
      if (groupCallGone(error.code)) {
        // 404 是答案不是失败：通话在服务端已经没了 = 直播结束。原来这里静默
        // 吞掉，徽标就永远停在"正在直播"（用户 2026-09-23 实报）。
        this.clearGroupCallLive(groupCallId);
        return;
      }
      logE(`ChatStore.getGroupCall(${groupCallId}) failed: ${error.message}`);
    });
  }

  // 通话已经不存在：把徽标撤掉，但**保留 liveGroupCallId**——那个 id 由
  // chat.video_chat 说了算，等 updateChatVideoChat 来改。这里只回答"在不在播"。
  private clearGroupCallLive(groupCallId: number): void {
    const chatId = this.groupCallChats.get(groupCallId);
    if (chatId === undefined) { return; }
    const entry = this.mirror.get(chatId);
    if (entry === undefined || entry.liveGroupCallId !== groupCallId) { return; }
    if (!entry.isLive && !entry.isRtmpLive) { return; }
    this.mirror.setLiveFlags(chatId, false, false);
    this.notify(chatId);
  }

  private applyGroupCall(groupCall: TdObject): void {
    const groupCallId = (groupCall['id'] as number | undefined) ?? 0;
    const chatId = this.groupCallChats.get(groupCallId);
    if (chatId === undefined) { return; }
    const entry = this.mirror.get(chatId);
    if (entry === undefined || entry.liveGroupCallId !== groupCallId) { return; }
    // is_active 只说明"通话对象还在"，不说明有人在播——判据见 groupCallIsLive。
    const isLive = groupCallIsLive(groupCall);
    const isRtmpLive = (groupCall['is_rtmp_stream'] as boolean | undefined) ?? false;
    if (entry.isLive === isLive && entry.isRtmpLive === isRtmpLive) { return; }
    // 直播位来自通话状态，不在 worker 的数据链上：写进镜像。
    this.mirror.setLiveFlags(chatId, isLive, isRtmpLive);
    this.notify(chatId);
  }


  // my_id 通常在会话列表出现之前就到了；万一晚到，把已经建好的那条重标一次。
  // 走 cloneEntry 是必要的——它会把 revision 加一，行 key 才会变、列表才会
  // 重画（否则标题仍是自己的昵称）。







  // 会话操作条变化（举报/屏蔽/加联系人之后服务端会撤掉它）。






  private actionTimerKey(chatId: number, uid: number): string {
    return `${chatId}:${uid}`;
  }

  private clearActionTimer(chatId: number, uid: number): void {
    const key = this.actionTimerKey(chatId, uid);
    const prev = this.chatActionTimers.get(key);
    if (prev !== undefined) {
      this.timer.clearTimeout(prev);
      this.chatActionTimers.delete(key);
    }
  }

  private computeTypingText(kind: ChatKind, senders: Map<number, TypingAction> | undefined): string {
    if (senders === undefined || senders.size === 0) {
      return '';
    }
    return chatActionLabelOf(
      headerKindForChatKind(kind),
      senders,
      (uid: number): string => this.users.displayName(uid)
    );
  }

  private typingEntryOf(chatId: number): ChatEntry | undefined {
    return this.mirror.get(chatId);
  }

  private publishTypingText(chatId: number): void {
    const e = this.typingEntryOf(chatId);
    if (e === undefined) {
      return;
    }
    const senders = this.chatActions.get(chatId);
    const nextText = this.computeTypingText(e.kind, senders);
    if ((e.typingText ?? '') === nextText) {
      return;
    }
    // 输入中是本地独有字段（worker 不处理 updateChatAction）：写进镜像。
    this.mirror.setTyping(chatId, nextText);
    this.notifySoon(chatId, true);
  }

  private onChatAction(update: TdObject): void {
    const chatId = (update['chat_id'] as number | undefined) ?? 0;
    const e = this.typingEntryOf(chatId);
    if (e === undefined || e.isSavedMessages) {
      return;
    }
    const sender = update['sender_id'] as TdObject | undefined;
    if (sender === undefined || sender['@type'] !== 'messageSenderUser') {
      return;
    }
    const uid = (sender['user_id'] as number | undefined) ?? 0;
    if (uid <= 0 || (this.selfId > 0 && uid === this.selfId)) {
      return;
    }
    const action = update['action'] as TdObject | undefined;
    const type = action !== undefined ? ((action['@type'] as string | undefined) ?? '') : '';
    if (type === 'chatActionCancel') {
      this.clearActionTimer(chatId, uid);
      const senders = this.chatActions.get(chatId);
      if (senders !== undefined && senders.delete(uid)) {
        if (senders.size === 0) {
          this.chatActions.delete(chatId);
        }
        this.publishTypingText(chatId);
      }
      return;
    }
    const kind = typingActionKind(type);
    if (kind === '') {
      return;
    }
    let senders = this.chatActions.get(chatId);
    if (senders === undefined) {
      senders = new Map();
      this.chatActions.set(chatId, senders);
    }
    senders.set(uid, { kind, expiresAt: TYPING_ACTION_TTL_MS });
    this.users.ensure(uid);
    this.clearActionTimer(chatId, uid);
    const key = this.actionTimerKey(chatId, uid);
    const timerId = this.timer.setTimeout((): void => {
      this.chatActionTimers.delete(key);
      const map = this.chatActions.get(chatId);
      if (map !== undefined && map.delete(uid)) {
        if (map.size === 0) {
          this.chatActions.delete(chatId);
        }
        this.publishTypingText(chatId);
      }
    }, TYPING_ACTION_TTL_MS);
    this.chatActionTimers.set(key, timerId);
    this.publishTypingText(chatId);
  }

  private onChatActionUser(update: TdObject): void {
    const user = update['user'] as TdObject | undefined;
    const uid = (user?.['id'] as number | undefined) ?? 0;
    if (uid <= 0) {
      return;
    }
    this.chatActions.forEach((senders: Map<number, TypingAction>, chatId: number): void => {
      if (senders.has(uid)) {
        this.publishTypingText(chatId);
      }
    });
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


  // Only a strictly newer received tail needs an unread counterpart. TDLib's
  // direction flag is required here: an absent flag must not turn an edit or a
  // partially constructed test object into a received message.













  // Mark lists dirty and schedule one coalesced flush. A field-only change
  // passes its chat id so only lists actually containing that chat rebuild;
  // membership/order changes (positions) omit it and dirty every list.
  private notify(chatId?: number, urgentList: boolean = false): void {
    this.invalidateListSubscriptions(chatId, urgentList);
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

  private notifySoon(chatId?: number, urgentList: boolean = false): void {
    this.invalidateListSubscriptions(chatId, urgentList);
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
    const avatarIds = this.dirtyAvatarChatIds;
    this.dirtyAvatarChatIds = new Set();
    const all = this.dirtyAllLists;
    const dirty = this.dirtyChatIds;
    const badgeKeys: string[] = Array.from(this.dirtyUnreadBadgeKeys);
    this.dirtyUnreadBadgeKeys = new Set();
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
    for (const s of this.chatSubs) {
      if (all || dirty.has(s.chatId)) {
        s.listener();
      }
    }
    for (const listener of this.changeListeners) {
      listener();
    }
    if (avatarIds.size > 0 && this.avatarListeners.length > 0) {
      const ids = Array.from(avatarIds);
      for (const listener of this.avatarListeners) { listener(ids); }
    }
    if (badgeKeys.length > 0) {
      for (const listener of this.unreadBadgeListeners) { listener(badgeKeys); }
    }
  }

  private listContainsAny(listKey: string, ids: Set<number>): boolean {
    const members: number[] = this.listIds(listKey);
    for (const id of ids) {
      if (members.indexOf(id) >= 0) { return true; }
    }
    return false;
  }

}
