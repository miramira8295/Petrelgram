import { TdClient } from '../tdkit/TdClient';
import { TdObject, TdRequest, TdError } from '../tdkit/TdTypes';
import { UserStore } from './UserStore';
import { MessageEntry, cloneMessage, buildMessageEntry, commentInfoFromInteraction, CommentInfo, reactionsFromInteraction, ReactionInfo, parseInlineKeyboard, refreshSystemUserLabel } from './MessageEntry';
import { ReplyKeyboard, parseReplyKeyboard } from './ReplyKeyboard';
import { publishSenderAvatar, senderChannelKey } from '../util/senderAvatarChannel';
import { publishThumbPath } from '../util/mediaThumbChannel';
import { formatUserStatus } from '../util/formatUserStatus';
import { formatPreview } from '../util/formatPreview';
import { formatMemberCount } from '../util/formatMemberCount';
import {
  KEY_POWER_ACTIVE, KEY_POWER_AUTOPLAY_GIF, KEY_POWER_AUTOPLAY_VIDEO, powerFeatureEnabled,
  reduceAnimations
} from './AppSettings';
import { decideMedia, subjectOfEntry, MediaContext, MediaIntent } from './MediaPolicy';
import { PollOptionInfo } from '../util/formatMsgContent';
import { reactionTypeOf } from '../util/reactions';
import { str } from '../util/strings';
import { publishProgress } from '../util/mediaProgressChannel';
import { publishSendState } from '../util/sendStateChannel';

const PAGE: number = 30;
// 首屏填充最多续追几次。三次足以把 14 + 2 + 30 这种序列填过一页，又不至于在
// 填不满的会话里一直问下去。
const INITIAL_FILL_TRIES: number = 3;
// TDLib 的消息 id 每条递增 2^20。
const ID_STEP: number = 1048576;
// 向上分页时，新页最旧一条和窗口最新一条之间隔多少条才算"接不上"。
// 被删过的消息会留下永久空档，所以小差值属正常；43 那种才是本地库缺了一段。
const NEWER_GAP_TOLERANCE: number = 5;
// 接不上时从同一个锚点重问几次。TDLib 会在后台向服务端补，重问通常能拿到
// 连续的那一段；用完还接不上就照旧合并，宁可有洞也别把消息卡住不显示。
const NEWER_GAP_RETRIES: number = 2;
// Visible bubble/header thumbnails should outrank silent video prefetch. The
// bubble still requests the compact inline size; this only changes scheduling,
// not image quality or transferred bytes.
const THUMBNAIL_PRIORITY: number = 16;
const MEDIA_PREFETCH_PRIORITY: number = 8;
const MEDIA_USER_PRIORITY: number = 24;
const REPLY_KB_PROBE_PAGE: number = 100;
const REPLY_KB_PROBE_LIMIT: number = 500;
// Re-request a still-missing thumbnail at most this often (stalled downloads
// whose bounded retries were exhausted by a transient network failure).
const THUMB_REKICK_MS: number = 8000;
// 向上翻页拿到空页时的重试次数。3 次之后仍然一条更旧的都没有，才认为到顶。
const OLDER_EMPTY_RETRIES: number = 3;
// 缩略图同时在途上限。放开时几十个请求互相抢带宽，首屏那几张反而最晚到；
// 4 条既能压满一般家宽，又给整段媒体和消息同步留出余量。
const THUMB_MAX_ACTIVE: number = 4;

// 被回复消息的预览快照（发送者 + 摘要）。
interface RepliedPreview {
  senderName: string;
  text: string;
}
// 一帧的量级：下载进度的发布合并到这个窗口里，见 notifySoon()。
const NOTIFY_COALESCE_MS: number = 16;
// 初始历史发布后的安置期。首页刚建好的这段时间里，头像回填、回复引用、缩略
// 图会各到一批——16ms 的窗口把它们放成两三波，每波都是近乎整页的 CHANGE 重建
// （实测每波 27-30 行、各吃一个掉帧）。安置期内的发布整体压到窗口末尾一次
// 放行，期满恢复 16ms，日常更新照旧灵敏。见 notifySoon()。
const INITIAL_SETTLE_WINDOW_MS: number = 400;
// 首屏历史页的条数。30 条一帧建完是实测的首帧掉帧来源；12 条先铺满屏幕，
// 剩余由短页补链/滚动分页在后续帧补齐。
const INITIAL_FIRST_PAGE: number = 12;

function pollVoteErrorText(raw: string): string {
  const normalized = raw.trim().toUpperCase();
  if (normalized.indexOf('POLL_MEMBER_RESTRICTED') >= 0) {
    return str('ms_poll_subscribers_only');
  }
  if (normalized.indexOf('POLL_COUNTRY_RESTRICTED') >= 0) {
    return str('ms_poll_region_only');
  }
  if (normalized.indexOf('REVOTE_NOT_ALLOWED') >= 0) {
    return str('ms_poll_no_change');
  }
  if (normalized.indexOf('MESSAGE_POLL_CLOSED') >= 0 ||
    normalized.indexOf('POLL_CLOSED') >= 0) {
    return str('ms_poll_closed');
  }
  if (normalized.indexOf('OPTION_INVALID') >= 0 ||
    normalized.indexOf('POLL_OPTION_INVALID') >= 0) {
    return str('ms_poll_option_stale');
  }
  return raw.trim() !== '' ? str('ms_vote_failed_msg', raw.trim()) : str('ms_vote_failed');
}

type MsgListener = (msgs: MessageEntry[]) => void;
type SubtitleListener = (s: string) => void;
type ReplyKeyboardListener = (kb: ReplyKeyboard | null) => void;

interface KeyboardMarkupHit {
  messageId: number;
  keyboard: ReplyKeyboard | null;
}

export interface MediaSendItem {
  path: string;
  isVideo: boolean;
}

export class MessageStore {
  private client: TdClient;
  private users: UserStore;
  private chatId: number;
  private messages: MessageEntry[] = [];
  private oldestId: number = 0;
  private subtitle: string = '';
  private pinnedPreview: string = '';
  private pinnedIds: number[] = [];
  private pinnedPreviews: string[] = [];
  private pinnedLoadState: string = 'loading';
  private coalesceTimer: number = -1;
  private pinnedResolveSeq: number = 0;
  private msgSubs: MsgListener[] = [];
  private subSubs: SubtitleListener[] = [];
  private pinnedSubs: SubtitleListener[] = [];
  private unsubs: Array<() => void> = [];
  private fileToMsg: Map<number, number> = new Map();
  private linkFileToMsg: Map<number, number> = new Map();
  private linkThumbAttempts: Map<number, number> = new Map();
  private linkThumbLastKick: Map<number, number> = new Map();
  private fullPhotoFileToMsg: Map<number, number> = new Map();
  private videoFileToMsg: Map<number, number> = new Map();
  private voiceListenPending: Set<number> = new Set();
  private stickerFileToMsg: Map<number, number> = new Map();
  // fileId -> 上次发出 downloadFile 的时间。见 requestStickerSource 里的说明：
  // 没有它时，一次静默卡死的下载会把贴纸永久钉在 0%。
  private stickerLastKick: Map<number, number> = new Map();
  // Live incoming media is the only automatic-download/autosave candidate.
  // Initial history never starts a burst of full-resolution downloads.
  // Consumed by ChatPage's autosave-to-gallery flow (consumeLiveIncomingMediaIds).
  private liveIncomingMediaIds: number[] = [];
  private inlineCustomEmojiFileToId: Map<number, string> = new Map();
  private inlineCustomEmojiPathById: Map<string, string> = new Map();
  // Telegram reuses the same thumbnail/source file ids whenever the same
  // sticker is sent again. Keep completed paths independently from a message
  // id so a newly-created outgoing bubble can render immediately.
  private completedFilePaths: Map<number, string> = new Map();
  private thumbLastKick: Map<number, number> = new Map();
  private peerUserId: number = 0;
  private peerUserStatus: TdObject | undefined = undefined;
  private statusRefreshTimer: number = -1;
  private groupId: number = 0;
  private lastReadInboxId: number = 0;
  private lastReadOutboxId: number = 0;
  private unreadCount: number = 0;
  private viewedUpTo: number = 0;
  private chatResolved: boolean = false;
  private historyPending: boolean = false;
  private historyPendingKind: string = 'history';
  private isGroupFlag: boolean = false;
  private repliedFetched: number[] = [];
  // Reply previews already fetched, kept so a window replacement can restore
  // them without a second request (repliedFetched would refuse one anyway).
  private repliedPreview: Map<number, RepliedPreview> = new Map();
  private isChannel: boolean = false;
  private chatPhotoFileId: number = 0;
  private chatPhotoPath: string = '';
  private headerAvatarSubs: SubtitleListener[] = [];
  private chatTitle: string = '';
  private headerTitleSubs: SubtitleListener[] = [];
  private senderAvatarPaths: Map<string, string> = new Map();
  private senderRequested: Set<string> = new Set();
  private avatarFileToSender: Map<number, string> = new Map();
  private forwardTitleCache: Map<number, string> = new Map();
  private forwardTitleRequested: Set<number> = new Set();
  private thumbAttempts: Map<number, number> = new Map();
  private replierAvatarPaths: Map<number, string> = new Map();
  private replierAvatarRequested: Set<number> = new Set();
  private avatarFileToReplier: Map<number, number> = new Map();
  private contactAvatarPaths: Map<number, string> = new Map();
  private contactAvatarRequested: Set<number> = new Set();
  private avatarFileToContact: Map<number, number> = new Map();
  private requestedAroundMessageId: number = 0;
  private initialLoadStarted: boolean = false;
  private initialHistoryState: string = 'loading'; // loading | ready | error
  private initialHistoryError: string = '';
  private olderPending: boolean = false;
  private newerPending: boolean = false;
  // chat.last_message captured at open. TDLib can hang a LOCAL service message
  // (e.g. "您已加入此群组") off chat.last_message that getChatHistory never
  // returns — it is also the chat's one unread message, so a timeline built
  // purely from history can never view it and the unread badge sticks at 1.
  // Grafted into the timeline once the loaded window reaches the live tail.
  private pendingLastMessage: TdObject | null = null;
  // A newly joined chat can expose its sole unread join notice only through
  // chat.last_message. Because it is guaranteed to be the initial unread
  // target, acknowledge it once the first real timeline snapshot is ready.
  private initialJoinServiceReadId: number = 0;
  private initialJoinServiceReadPending: boolean = false;
  private manualUnreadClearSent: boolean = false;
  private latestPending: boolean = false;
  private hasMoreOlder: boolean = true;
  private hasMoreNewer: boolean = false;
  // Pagination errors never replace an already-readable timeline. The page
  // renders them as compact edge pills with an explicit retry action.
  private olderLoadState: string = 'idle'; // idle | loading | error | end
  private newerLoadState: string = 'idle'; // idle | loading | error | end
  // Exposed only while listeners are being notified. The page uses this to
  // distinguish a real-time arrival from a newer-history page whose maximum
  // id also increases, but must not animate or auto-follow like a new message.
  private currentNotifyKind: string = 'update';
  private memberCount: number = 0;
  private onlineCount: number = 0;
  // Bot custom reply keyboard. Chat-level: replyMarkupMessageId names the
  // message carrying the active markup (0 = none, per chat.reply_markup_message_id).
  private replyMarkupMessageId: number = 0;
  private replyKeyboard: ReplyKeyboard | null = null;
  private replyKbSubs: ReplyKeyboardListener[] = [];
  // Fallback for when TDLib reports chat.reply_markup_message_id as 0 even though
  // a keyboard is live (seen in supergroups, and after a one_time keyboard is
  // used — other clients keep showing it). Tracks the NEWEST loaded message
  // carrying a keyboard-affecting markup, and the keyboard it implies
  // (null when that newest markup is replyMarkupRemoveKeyboard).
  private kbMarkupMsgId: number = 0;
  private kbFromHistory: ReplyKeyboard | null = null;
  private kbHistoryProbeSeq: number = 0;
  private kbHistoryProbeRunning: boolean = false;
  private chatOpened: boolean = false;

  // >0: this store is scoped to one message thread (channel-post comments) —
  // history comes from getMessageThreadHistory and sends target the thread.
  private threadRootId: number = 0;
  private historyPageSize: number = PAGE;

  constructor(client: TdClient, users: UserStore, chatId: number,
    threadRootId: number = 0, historyPageSize: number = PAGE, forumTopicId: number = 0) {
    this.client = client;
    this.users = users;
    this.chatId = chatId;
    this.threadRootId = threadRootId;
    this.forumTopicId = forumTopicId;
    this.historyPageSize = Math.max(1, Math.min(100, historyPageSize));
  }

  // 论坛话题（forum_topic_id，独立于评论线程的 message_thread_id）。
  // 历史走 getForumTopicHistory，发送带 topic_id: messageTopicForum。
  private forumTopicId: number = 0;

  private topicIdObject(): TdObject {
    const topic: TdObject = { '@type': 'messageTopicForum' };
    topic['forum_topic_id'] = this.forumTopicId;
    return topic;
  }

  // 发送/输入指示类请求的作用域。本 td 版本这些请求已无 message_thread_id
  // 参数，评论线程同样要走 topic_id（messageTopicThread）。
  private applyTopicScope(req: TdRequest): void {
    if (this.forumTopicId > 0) {
      req['topic_id'] = this.topicIdObject();
    } else if (this.threadRootId > 0) {
      const topic: TdObject = { '@type': 'messageTopicThread' };
      topic['message_thread_id'] = this.threadRootId;
      req['topic_id'] = topic;
    }
  }

  // 实时更新过滤：不属于当前话题/线程窗口的消息不进入本窗口。
  private outsideTopicScope(m: TdObject): boolean {
    if (this.forumTopicId > 0) {
      const topic = m['topic_id'] as TdObject | undefined;
      const topicId: number = topic !== undefined
        ? ((topic['forum_topic_id'] as number | undefined) ?? 0) : 0;
      return topicId !== this.forumTopicId;
    }
    if (this.threadRootId > 0) {
      return (m['message_thread_id'] as number | undefined) !== this.threadRootId;
    }
    return false;
  }

  // getChatHistory, or getMessageThreadHistory when scoped to a comment thread
  // (same paging contract: from_message_id + offset + limit).
  private historyRequest(fromId: number, offset: number): TdRequest {
    if (this.forumTopicId > 0) {
      const topicReq: TdRequest = { '@type': 'getForumTopicHistory' };
      topicReq['chat_id'] = this.chatId;
      topicReq['forum_topic_id'] = this.forumTopicId;
      topicReq['from_message_id'] = fromId;
      topicReq['offset'] = offset;
      topicReq['limit'] = this.historyPageSize;
      return topicReq;
    }
    const req: TdRequest = { '@type': this.threadRootId > 0 ? 'getMessageThreadHistory' : 'getChatHistory' };
    req['chat_id'] = this.chatId;
    req['from_message_id'] = fromId;
    req['offset'] = offset;
    req['limit'] = this.historyPageSize;
    if (this.threadRootId > 0) {
      req['message_id'] = this.threadRootId;
    } else {
      req['only_local'] = false;
    }
    return req;
  }

  // 应用切后台：TDLib 对"打开中"的会话不生成通知（认为用户正在看）。
  // 暂时 closeChat，回前台再 openChat，否则停留在会话页时永远收不到通知。
  suspendOpenChat(): void {
    if (!this.chatOpened) {
      return;
    }
    this.sendSimple('closeChat');
    this.chatOpened = false;
    this.chatSuspended = true;
  }

  resumeOpenChat(): void {
    if (!this.chatSuspended || this.chatOpened) {
      return;
    }
    this.chatSuspended = false;
    this.sendSimple('openChat');
    this.chatOpened = true;
    this.readAllBadges();
    // The suspended stretch is a blind spot: the OS freezes the process, the
    // connection drops, and messages delivered meanwhile are synced by TDLib
    // without ever passing through updateNewMessage. The window then holds
    // [old tail] + [messages arriving after resume] with the in-between pages
    // simply absent — rendered as a seamless jump (10:46 followed by 10:57).
    // Refetch the newest page; onHistory's continuity check decides whether it
    // merges into the window or replaces it.
    console.info(`[StoreDiag] resume rows=${this.messages.length}` +
      ` oldest=${this.oldestId} state=${this.initialHistoryState}` +
      ` hasMoreNewer=${this.hasMoreNewer} olderPending=${this.olderPending}`);
    if (this.initialHistoryState === 'ready' && !this.hasMoreNewer) {
      this.loadHistory(0);
    }
  }

  // 首屏填充还能再追几次。
  //
  // TDLib 只给本地库里已有的，不够时返回更少并在后台向服务端补，契约是
  // 「再问一次」——**一次往往不够**：实测首屏 around 回 14 条、补链只补到 2 条。
  // 所以按短页继续追，直到窗口够一页、或者对方回 0（真到顶了），或者用完次数。
  //
  // 上限存在的意义是防死循环：某些会话（被限流、纯服务消息）可能每次都回少量
  // 却永远填不满，没有上限就会一直问下去。
  private initialFillTries: number = 0;
  // 向上分页遇到"接不上"时还能重问几次。
  private newerGapRetries: number = NEWER_GAP_RETRIES;

  private chatSuspended: boolean = false;

  open(aroundMessageId?: number, passive: boolean = false): void {
    // Embedded consumers such as the livestream interaction panel need chat
    // history and updates without changing TDLib's open-chat lifecycle for the
    // full ChatPage underneath them.
    if (!passive) {
      this.sendSimple('openChat');
      this.chatOpened = true;
      // Opening the chat clears its @-mention and reaction badges, as in the
      // official clients.
      this.readAllBadges();
    }
    this.unsubs.push(this.client.onUpdate('updateNewMessage', (u: TdObject) => this.onNewMessage(u)));
    this.unsubs.push(this.client.onUpdate('updateMessageSendSucceeded', (u: TdObject) => this.onSendSucceeded(u)));
    this.unsubs.push(this.client.onUpdate('updateMessageSendFailed', (u: TdObject) => this.onSendFailed(u)));
    this.unsubs.push(this.client.onUpdate('updateMessageContent', (u: TdObject) => this.onContent(u)));
    this.unsubs.push(this.client.onUpdate('updatePoll', (u: TdObject) => this.onPoll(u)));
    this.unsubs.push(this.client.onUpdate('updateDeleteMessages', (u: TdObject) => this.onDelete(u)));
    this.unsubs.push(this.client.onUpdate('updateChatReadOutbox', (u: TdObject) => this.onReadOutbox(u)));
    this.unsubs.push(this.client.onUpdate('updateFile', (u: TdObject) => this.onFile(u)));
    this.unsubs.push(this.client.onUpdate('updateUserStatus', (u: TdObject) => this.onUserStatus(u)));
    this.unsubs.push(this.client.onUpdate('updateBasicGroup', (u: TdObject) => this.onGroup(u)));
    this.unsubs.push(this.client.onUpdate('updateSupergroup', (u: TdObject) => this.onGroup(u)));
    this.unsubs.push(this.client.onUpdate('updateUser', () => {
      this.resolveSenderAvatars();
      this.resolveSystemUserLabels();
      this.resolveCommentAvatars();
      this.resolveContactAvatars();
    }));
    this.unsubs.push(this.client.onUpdate('updateMessageInteractionInfo', (u: TdObject) => this.onInteractionInfo(u)));
    this.unsubs.push(this.client.onUpdate('updateChatOnlineMemberCount', (u: TdObject) => this.onOnlineCount(u)));
    // A message got (un)pinned while the chat is open — re-resolve the pinned
    // list so the banner reflects the new pin without re-entering the chat.
    this.unsubs.push(this.client.onUpdate('updateMessageIsPinned', (u: TdObject) => {
      if ((u['chat_id'] as number | undefined) === this.chatId) {
        this.onPinnedUpdate(u);
      }
    }));
    this.unsubs.push(this.client.onUpdate('updateMessageEdited', (u: TdObject) => this.onEdited(u)));
    // Bot showed/removed its custom reply keyboard.
    this.unsubs.push(this.client.onUpdate('updateChatReplyMarkup', (u: TdObject) => this.onChatReplyMarkup(u)));
    this.requestedAroundMessageId = aroundMessageId !== undefined ? aroundMessageId : 0;
    this.resolveChat();
    this.resolvePinned();
    if (this.threadRootId > 0) {
      this.fetchThreadRoot();
    }
  }

  // Comment thread: the root (the channel post as forwarded into the discussion
  // group) heads the view — thread history alone may not include it.
  private fetchThreadRoot(): void {
    const req: TdRequest = { '@type': 'getMessage' };
    req['chat_id'] = this.chatId;
    req['message_id'] = this.threadRootId;
    this.client.send(req).then((m: TdObject) => {
      this.upsert(buildMessageEntry(m, this.users));
      this.requestPhotos();
      this.resolveSenderAvatars();
      this.notifySoon();
    }).catch((e: TdError) => {
      console.error(`MessageStore.fetchThreadRoot failed: ${e.message}`);
    });
  }

  close(): void {
    if (this.coalesceTimer !== -1) {
      clearTimeout(this.coalesceTimer);
      this.coalesceTimer = -1;
    }
    this.pinnedResolveSeq++;
    this.kbHistoryProbeSeq++;
    this.kbHistoryProbeRunning = false;
    if (this.chatOpened) {
      this.sendSimple('closeChat');
      this.chatOpened = false;
    }
    for (const un of this.unsubs) {
      un();
    }
    this.unsubs = [];
    if (this.statusRefreshTimer !== -1) {
      clearInterval(this.statusRefreshTimer);
      this.statusRefreshTimer = -1;
    }
  }

  getMessages(): MessageEntry[] {
    return this.messages;
  }

  consumeLiveIncomingMediaIds(): number[] {
    const ids = this.liveIncomingMediaIds.slice();
    this.liveIncomingMediaIds = [];
    return ids;
  }

  getSubtitle(): string {
    return this.subtitle;
  }

  // Chat unread count snapshot captured at open time (for the scroll-to-bottom badge).
  getUnreadCount(): number {
    return this.unreadCount;
  }

  // True for basic groups / supergroups / channels — drives per-message avatars + sender names.
  getIsGroup(): boolean {
    return this.isGroupFlag;
  }

  // True only for broadcast channels — reply_info.reply_count is a generic
  // Peer user id for private chats (0 for groups/channels) — used to open the
  // user profile page from the chat header.
  getPeerUserId(): number {
    return this.peerUserId;
  }

  // "times replied" counter shared with ordinary in-chat reply threads, so the
  // "N Comments" chip must only render for real channel posts.
  getIsChannel(): boolean {
    return this.isChannel;
  }

  // Id of the first unread message captured at open time (0 = none / all read).
  // Used by the page to position the initial scroll at the unread boundary.
  getFirstUnreadId(): number {
    if (this.unreadCount <= 0 || this.lastReadInboxId <= 0) {
      return 0;
    }
    for (const m of this.messages) {
      if (m.id > this.lastReadInboxId) {
        return m.id;
      }
    }
    return 0;
  }

  getReplyKeyboard(): ReplyKeyboard | null {
    return this.replyKeyboard;
  }

  subscribeReplyKeyboard(l: ReplyKeyboardListener): () => void {
    this.replyKbSubs = [...this.replyKbSubs, l];
    l(this.replyKeyboard);
    return (): void => { this.replyKbSubs = this.replyKbSubs.filter((x: ReplyKeyboardListener) => x !== l); };
  }

  private setReplyKeyboard(kb: ReplyKeyboard | null): void {
    this.replyKeyboard = kb;
    for (const l of this.replyKbSubs) {
      l(kb);
    }
  }

  // Resolve replyMarkupMessageId into an actual keyboard. The message is usually
  // already in the loaded window; otherwise fetch it (the markup often comes from
  // a message far above the current view, so we can't rely on history alone).
  private resolveReplyKeyboard(): void {
    const id = this.replyMarkupMessageId;
    if (id === 0) {
      // TDLib reports 0 here even when a keyboard is live (supergroups; a
      // one_time keyboard that's already been used) while other clients keep
      // showing it — so trust the newest keyboard markup seen in history.
      this.setReplyKeyboard(this.kbFromHistory);
      return;
    }
    const req: TdRequest = { '@type': 'getMessage' };
    req['chat_id'] = this.chatId;
    req['message_id'] = id;
    this.client.send(req).then((m: TdObject) => {
      if (this.replyMarkupMessageId !== id) {
        return; // superseded while in flight
      }
      this.setReplyKeyboard(parseReplyKeyboard(m));
    }).catch((e: TdError) => {
      console.error(`MessageStore.resolveReplyKeyboard(${id}) failed: ${e.message}`);
      this.setReplyKeyboard(this.kbFromHistory);
      this.startKeyboardHistoryProbe();
    });
  }

  private onChatReplyMarkup(u: TdObject): void {
    if ((u['chat_id'] as number | undefined) !== this.chatId) {
      return;
    }
    this.replyMarkupMessageId = (u['reply_markup_message_id'] as number | undefined) ?? 0;
    this.resolveReplyKeyboard();
    if (this.replyMarkupMessageId === 0) {
      // Restart from the live tail: this update can mean a removal, but some
      // supergroups also publish 0 while a persistent keyboard remains active.
      this.startKeyboardHistoryProbe(true);
    }
  }

  private newestKeyboardMarkup(arr: TdObject[]): KeyboardMarkupHit | null {
    let hit: KeyboardMarkupHit | null = null;
    for (const m of arr) {
      const mk = m['reply_markup'] as TdObject | undefined;
      if (mk === undefined) {
        continue;
      }
      const t = (mk['@type'] as string | undefined) ?? '';
      if (t !== 'replyMarkupShowKeyboard' && t !== 'replyMarkupRemoveKeyboard') {
        continue;
      }
      const id = (m['id'] as number | undefined) ?? 0;
      if (id <= 0 || (hit !== null && id <= hit.messageId)) {
        continue;
      }
      hit = {
        messageId: id,
        keyboard: t === 'replyMarkupShowKeyboard' ? parseReplyKeyboard(m) : null
      };
    }
    return hit;
  }

  private applyKeyboardMarkupHit(hit: KeyboardMarkupHit): void {
    if (hit.messageId < this.kbMarkupMsgId) {
      return;
    }
    this.kbMarkupMsgId = hit.messageId;
    this.kbFromHistory = hit.keyboard;
    if (this.replyMarkupMessageId === 0 ||
      this.replyMarkupMessageId === hit.messageId) {
      this.setReplyKeyboard(hit.keyboard);
    }
  }

  // Track a real-time message that shows or removes a reply keyboard.
  // (replyMarkupInlineKeyboard is NOT one of these — those buttons live in the
  // bubble and are rendered separately.)
  private scanKeyboardMarkup(arr: TdObject[]): void {
    const hit: KeyboardMarkupHit | null = this.newestKeyboardMarkup(arr);
    if (hit === null) {
      return;
    }
    this.kbHistoryProbeSeq++;
    this.kbHistoryProbeRunning = false;
    this.applyKeyboardMarkupHit(hit);
  }

  // In busy groups the active keyboard message can be far above the currently
  // rendered 30-message window, and TDLib can publish reply_markup_message_id
  // as 0. Probe from the LIVE tail independently of the user's history anchor;
  // the first show/remove marker encountered is the authoritative newest one.
  private startKeyboardHistoryProbe(force: boolean = false): void {
    if (this.kbHistoryProbeRunning && !force) {
      return;
    }
    const seq: number = ++this.kbHistoryProbeSeq;
    this.kbHistoryProbeRunning = true;
    this.probeKeyboardHistoryPage(seq, 0, 0);
  }

  private finishKeyboardHistoryProbe(seq: number): void {
    if (seq === this.kbHistoryProbeSeq) {
      this.kbHistoryProbeRunning = false;
    }
  }

  private probeKeyboardHistoryPage(seq: number, fromMessageId: number,
    scanned: number): void {
    if (seq !== this.kbHistoryProbeSeq) {
      return;
    }
    const req: TdRequest = { '@type': 'getChatHistory' };
    req['chat_id'] = this.chatId;
    req['from_message_id'] = fromMessageId;
    req['offset'] = 0;
    req['limit'] = REPLY_KB_PROBE_PAGE;
    req['only_local'] = false;
    this.client.send(req).then((res: TdObject): void => {
      if (seq !== this.kbHistoryProbeSeq) {
        return;
      }
      const arr: TdObject[] = (res['messages'] as TdObject[] | undefined) ?? [];
      const hit: KeyboardMarkupHit | null = this.newestKeyboardMarkup(arr);
      if (hit !== null) {
        this.applyKeyboardMarkupHit(hit);
        this.finishKeyboardHistoryProbe(seq);
        return;
      }
      const nextScanned: number = scanned + arr.length;
      if (arr.length === 0 || nextScanned >= REPLY_KB_PROBE_LIMIT) {
        this.finishKeyboardHistoryProbe(seq);
        return;
      }
      let oldestId: number = 0;
      for (const m of arr) {
        const id: number = (m['id'] as number | undefined) ?? 0;
        if (id > 0 && (oldestId === 0 || id < oldestId)) {
          oldestId = id;
        }
      }
      if (oldestId === 0 || oldestId === fromMessageId) {
        this.finishKeyboardHistoryProbe(seq);
        return;
      }
      this.probeKeyboardHistoryPage(seq, oldestId, nextScanned);
    }).catch((e: TdError): void => {
      this.finishKeyboardHistoryProbe(seq);
      if (e.code !== 404) {
        console.error(`MessageStore keyboard history probe failed: ${e.message}`);
      }
    });
  }

  private ensureKeyboardHistoryProbe(): void {
    if (this.isGroupFlag && this.replyMarkupMessageId === 0 &&
      this.kbMarkupMsgId === 0) {
      this.startKeyboardHistoryProbe();
    }
  }

  subscribe(l: MsgListener): () => void {
    this.msgSubs = [...this.msgSubs, l];
    l(this.messages);
    return (): void => { this.msgSubs = this.msgSubs.filter((x: MsgListener) => x !== l); };
  }

  subscribeSubtitle(l: SubtitleListener): () => void {
    this.subSubs = [...this.subSubs, l];
    l(this.subtitle);
    return (): void => { this.subSubs = this.subSubs.filter((x: SubtitleListener) => x !== l); };
  }

  subscribePinned(l: SubtitleListener): () => void {
    this.pinnedSubs = [...this.pinnedSubs, l];
    l(this.pinnedPreview);
    return (): void => { this.pinnedSubs = this.pinnedSubs.filter((x: SubtitleListener) => x !== l); };
  }

  getPinnedLoadState(): string {
    return this.pinnedLoadState;
  }

  refreshPinned(): void {
    this.resolvePinned();
  }

  // Header avatar path, resolved from the chat photo. Authoritative for the chat
  // page header (works even for channels/chats not present in the loaded lists).
  subscribeHeaderAvatar(l: SubtitleListener): () => void {
    this.headerAvatarSubs = [...this.headerAvatarSubs, l];
    l(this.chatPhotoPath);
    return (): void => { this.headerAvatarSubs = this.headerAvatarSubs.filter((x: SubtitleListener) => x !== l); };
  }

  // Chat title resolved from getChat — a fallback header title/initials for chats
  // opened by t.me link that aren't in ChatStore's cache yet.
  subscribeHeaderTitle(l: SubtitleListener): () => void {
    this.headerTitleSubs = [...this.headerTitleSubs, l];
    l(this.chatTitle);
    return (): void => { this.headerTitleSubs = this.headerTitleSubs.filter((x: SubtitleListener) => x !== l); };
  }

  private notifyHeaderTitle(): void {
    for (const l of this.headerTitleSubs) {
      l(this.chatTitle);
    }
  }

  private notifyHeaderAvatar(): void {
    for (const l of this.headerAvatarSubs) {
      l(this.chatPhotoPath);
    }
  }

  // Load the previous (older) page. Guarded so scroll-driven prefetch can call
  // this repeatedly without stacking duplicate in-flight requests.
  private loadOlderRefusalSeen: Set<string> = new Set<string>();
  // 向上翻页遇到"这一页没有更旧的"时，还允许再问几次。见 loadOlder 里的说明：
  // TDLib 返回空不等于没有历史，它的契约是"再问一次"。
  private olderEmptyRetries: number = OLDER_EMPTY_RETRIES;

  loadOlder(): boolean {
    if (this.olderPending || this.olderLoadState === 'error' ||
      !this.hasMoreOlder || this.oldestId === 0) {
      // 诊断：反馈过"有会话进去只有一页、往上翻不动"，且不必现。这里是历史
      // 分页唯一的拒绝点，四个条件各指一处原因。
      //
      // 每个会话只打一行：正常翻到顶也会走这里，逐次打会把环形缓冲刷爆，
      // 等偶发现象时反而把证据挤掉。
      // 每种**理由**各打一次，而不是整个会话只打一次：先因为"请求在途"被拒
      // （正常），之后因为 hasMore=false 被拒（异常）就再也看不见了——那正是
      // 要查的那种。
      const reason: string = `${this.olderPending}/${this.olderLoadState}/${this.hasMoreOlder}`;
      if (!this.loadOlderRefusalSeen.has(reason)) {
        this.loadOlderRefusalSeen.add(reason);
        console.warn(`loadOlder refused pending=${this.olderPending}` +
          ` state=${this.olderLoadState} hasMore=${this.hasMoreOlder}` +
          ` oldest=${this.oldestId} rows=${this.messages.length}`);
      }
      return false;
    }
    const anchorId = this.oldestId;
    this.olderPending = true;
    this.olderLoadState = 'loading';
    this.notify('paginationState');
    const req = this.historyRequest(anchorId, 0);
    this.client.send(req).then((res: TdObject) => {
      this.olderPending = false;
      const arr = (res['messages'] as TdObject[] | undefined) ?? [];
      let hasOlderEntry = false;
      for (const message of arr) {
        const id = (message['id'] as number | undefined) ?? 0;
        if (id > 0 && id < anchorId) {
          hasOlderEntry = true;
          break;
        }
      }
      if (!hasOlderEntry) {
        // 空页**不等于**到顶。getChatHistory 只给本地缓存里有的，明明还有历史
        // 也可能返回空或只返回锚点自己——它的契约是"再问一次"（同一个文件里
        // latest 那条路的注释早就写明了这一点，这里却更严：一次没拿到更旧的
        // 就把 hasMoreOlder 永久置 false，之后 loadOlder 在入口直接拒绝，那个
        // 会话就永远停在那点内容上，用户看到的是"999+ 却滑不动"）。
        //
        // 而且这个坑会自锁：向上预取是滚动驱动的，内容不够一屏就滚不动，
        // 滚不动就没人再来敲门。所以这里不能等下一次滚动，得自己立刻再问。
        if (this.olderEmptyRetries > 0) {
          this.olderEmptyRetries--;
          this.olderLoadState = 'idle';
          console.warn(`[StoreDiag] older empty, retrying left=${this.olderEmptyRetries}` +
            ` anchor=${anchorId} rows=${this.messages.length}`);
          this.onHistory(res, 'older');
          this.loadOlder();
          return;
        }
        this.hasMoreOlder = false;
        this.olderLoadState = 'end';
      } else {
        this.olderEmptyRetries = OLDER_EMPTY_RETRIES;
        this.olderLoadState = 'idle';
      }
      this.onHistory(res, 'older');
    }).catch((e: TdError) => {
      this.olderPending = false;
      if ((e as TdError).code === 404) {
        this.hasMoreOlder = false;
        this.olderLoadState = 'end';
      } else {
        this.olderLoadState = 'error';
        console.error(`MessageStore.loadOlder failed: ${e.message}`);
      }
      this.notify('paginationState');
    });
    return true;
  }

  // True while unloaded newer pages exist below the loaded window (i.e. we
  // jumped into the middle of history and haven't reached the live tail).
  getHasMoreNewer(): boolean {
    return this.hasMoreNewer;
  }

  getHasMoreOlder(): boolean {
    return this.hasMoreOlder;
  }

  getOlderLoadState(): string {
    return this.olderLoadState;
  }

  getNewerLoadState(): string {
    return this.newerLoadState;
  }

  getCurrentNotifyKind(): string {
    return this.currentNotifyKind;
  }

  getInitialHistoryState(): string {
    return this.initialHistoryState;
  }

  getInitialHistoryError(): string {
    return this.initialHistoryError;
  }

  retryInitialHistory(): void {
    if (this.initialHistoryState !== 'error') {
      return;
    }
    this.initialHistoryState = 'loading';
    this.initialHistoryError = '';
    this.notify('initialState');
    this.requestInitialPage();
  }

  retryOlder(): void {
    if (this.olderLoadState !== 'error') {
      return;
    }
    this.olderLoadState = 'idle';
    this.loadOlder();
  }

  retryNewer(): void {
    if (this.newerLoadState !== 'error') {
      return;
    }
    this.newerLoadState = 'idle';
    this.loadNewer();
  }

  // Jump straight to the newest messages: drop the loaded window and reload
  // latest page. The replacement is atomic: keep the current window visible
  // until the request succeeds, so a network failure never leaves a blank list.
  // Used by the scroll-to-bottom button when thousands of unloaded messages
  // separate the user from the tail.
  jumpToLatest(onComplete?: (success: boolean) => void): void {
    if (this.latestPending) {
      if (onComplete !== undefined) {
        onComplete(false);
      }
      return;
    }
    this.latestPending = true;
    const req = this.historyRequest(0, 0);
    this.client.send(req).then((res: TdObject): void => {
      this.latestPending = false;
      this.hasMoreNewer = false;
      this.hasMoreOlder = true;
      this.newerPending = false;
      this.olderPending = false;
      this.olderEmptyRetries = OLDER_EMPTY_RETRIES;
      this.newerLoadState = 'end';
      this.olderLoadState = 'idle';
      this.messages = [];
      this.oldestId = 0;
      this.onHistory(res, 'latest');
      if (onComplete !== undefined) {
        onComplete(true);
      }
    }).catch((e: TdError): void => {
      this.latestPending = false;
      if ((e as TdError).code !== 404) {
        console.error(`MessageStore.jumpToLatest failed: ${e.message}`);
      }
      if (onComplete !== undefined) {
        onComplete(false);
      }
    });
  }

  // Anchor of the one allowed cache-warm retry — see the comment in loadNewer.
  // Reset implicitly: a successful page moves newestId, and the next stall (if
  // any) is a different anchor.
  private newerRetryAnchor: number = 0;

  // Load the next (newer) page — only meaningful after a loadAround jump into
  // the middle of history left unloaded messages below the window.
  loadNewer(): boolean {
    if (this.newerPending || this.newerLoadState === 'error' ||
      !this.hasMoreNewer || this.messages.length === 0) {
      return false;
    }
    const newestId = this.messages[this.messages.length - 1].id;
    this.newerPending = true;
    this.newerLoadState = 'loading';
    this.notify('paginationState');
    const req = this.historyRequest(newestId, -(this.historyPageSize - 1));
    this.client.send(req).then((res: TdObject) => {
      this.newerPending = false;
      const arr = (res['messages'] as TdObject[] | undefined) ?? [];
      let maxId = 0;
      for (const m of arr) {
        const id = (m['id'] as number | undefined) ?? 0;
        if (id > maxId) {
          maxId = id;
        }
      }
      // 连续性检查。loadNewer 从窗口最新一条往上取，如果本地库里紧邻的那段
      // 是空的，TDLib 会返回**更上面**的一段——和窗口接不上。无条件合并就会
      // 在中间留下一个洞，而且再也不会自己合上（后续加载都发生在更新的那端）。
      // 实测抓到过 43 条的洞卡在第 223 行、窗口涨到 630 行它还在。
      //
      // latest 那边早有同样的检查，newer 一直漏着。
      let pageOldest: number = 0;
      for (const m of arr) {
        const id = (m['id'] as number | undefined) ?? 0;
        if (id > 0 && (pageOldest === 0 || id < pageOldest)) {
          pageOldest = id;
        }
      }
      const skipped: number = pageOldest > newestId
        ? Math.round((pageOldest - newestId) / ID_STEP) : 0;
      if (skipped > NEWER_GAP_TOLERANCE && this.newerGapRetries > 0) {
        // 页首就和窗口接不上：整页都不要，从同一个锚点重问，等 TDLib 把中间
        // 那段取回来。
        this.newerGapRetries--;
        this.newerLoadState = 'idle';
        console.warn(`[StoreDiag] newer discontinuous skipped=${skipped}` +
          ` newestId=${newestId} pageOldest=${pageOldest}` +
          ` retriesLeft=${this.newerGapRetries}`);
        this.loadNewer();
        return;
      }
      if (skipped > NEWER_GAP_TOLERANCE) {
        console.warn(`[StoreDiag] newer discontinuous skipped=${skipped} merged anyway`);
      }
      this.newerGapRetries = NEWER_GAP_RETRIES;
      // 页首连得上还不够：这一页**内部**也可能是断的。本地库里若只剩"紧挨着
      // 窗口的几条"和"最新那一条"，TDLib 会把两截一起给回来，中间几万条缺着。
      // 实测抓到过 99689 条的缺口就是这么进来的——页首连续，检查放行，洞跟着
      // 整页一起进了窗口，而且再也不会自己合上。
      //
      // 所以只收与窗口连续的那一段，断点之后的整段丢掉：那部分等用户真翻到
      // 那里再取，宁可少收也不能留洞。
      // 只看**严格更新**的那些。页里往往还带着窗口已有的几条，它们与锚点的
      // 步长是 0，会被当成"连续前缀"留下来——留下来又都是重复的，窗口一行
      // 不涨、锚点一步不进，于是同一个锚点问同一个问题，永远原地打转。
      // 实测就是这样卡死的：一页 30 条留 2 条，rows 恒定 14，新消息还被
      // 实时到达守卫一并挡掉，表现为"999+ 却滑不动、也不更新"。
      const sorted: TdObject[] = arr.slice()
        .filter((m: TdObject): boolean => (((m['id'] as number | undefined) ?? 0) > newestId))
        .sort((a: TdObject, b: TdObject): number =>
          (((a['id'] as number | undefined) ?? 0) - ((b['id'] as number | undefined) ?? 0)));
      const contiguous: TdObject[] = [];
      let prevId: number = newestId;
      let dropped: number = 0;
      for (const m of sorted) {
        const id = (m['id'] as number | undefined) ?? 0;
        const step: number = prevId > 0 ? Math.round((id - prevId) / ID_STEP) : 1;
        if (dropped === 0 && step <= NEWER_GAP_TOLERANCE) {
          contiguous.push(m);
          prevId = id;
        } else {
          dropped++;
        }
      }
      // 一条都接不上：这一页里更新的消息全在缺口之后。再问同一个锚点只会拿到
      // 同一页，所以不能再丢——整页收下，让窗口带着这个洞往前走。
      //
      // 留洞确实是这套过滤当初要避免的，但"洞"和"整个会话冻住"不是一个量级：
      // 洞还能往下翻、新消息照常进来，冻住则什么都做不了。宁可留洞。
      if (contiguous.length === 0 && sorted.length > 0) {
        console.warn(`[StoreDiag] newer page all behind a gap: taking ${sorted.length}` +
          ` as-is to avoid stalling (newest=${newestId})`);
        const whole: TdObject = { '@type': 'messages' };
        whole['messages'] = sorted;
        this.onHistory(whole, 'newer');
        this.notify('paginationState');
        return;
      }
      if (dropped > 0) {
        console.warn(`[StoreDiag] newer page had inner gap: kept=${contiguous.length}` +
          ` dropped=${dropped} lastKept=${prevId}`);
        // 丢掉了后半段，说明更新的消息还在，别把分页关掉。
        this.hasMoreNewer = true;
        this.newerLoadState = 'idle';
        const trimmed: TdObject = { '@type': 'messages' };
        trimmed['messages'] = contiguous;
        this.onHistory(trimmed, 'newer');
        this.notify('paginationState');
        return;
      }
      if (maxId <= newestId) {
        // TDLib's classic negative-offset trap: the FIRST getChatHistory with
        // offset < 0 is often served from the local cache only and returns
        // nothing newer even though newer messages exist server-side. Treating
        // that as "reached the live tail" froze newer-paging permanently —
        // the "unread messages don't fully load" report. The first call warms
        // TDLib's cache, so ask ONCE more from the same anchor; only a second
        // empty answer means the tail is real.
        if (this.newerRetryAnchor !== newestId) {
          this.newerRetryAnchor = newestId;
          this.newerLoadState = 'idle';
          this.onHistory(res, 'newer');
          this.loadNewer();
          return;
        }
        this.hasMoreNewer = false;
        this.newerLoadState = 'end';
      } else {
        this.newerLoadState = 'idle';
      }
      this.onHistory(res, 'newer');
    }).catch((e: TdError) => {
      this.newerPending = false;
      if ((e as TdError).code === 404) {
        this.hasMoreNewer = false;
        this.newerLoadState = 'end';
      } else {
        this.newerLoadState = 'error';
        console.error(`MessageStore.loadNewer failed: ${e.message}`);
      }
      this.notify('paginationState');
    });
    return true;
  }

  send(text: string, replyToId: number = 0): void {
    this.sendAsync(text, replyToId).catch((e: TdError) => {
      console.error(`MessageStore.send failed: ${e.message}`);
    });
  }

  // entities 目前只用于按 user_id 提及没有用户名的成员（见 mentionEntities）。
  // 其余实体仍由服务器扫文本自行识别，这里不接管。
  sendAsync(text: string, replyToId: number = 0, entities: TdObject[] = []): Promise<void> {
    const ft: TdObject = { '@type': 'formattedText' };
    ft['text'] = text;
    if (entities.length > 0) {
      ft['entities'] = entities;
    }
    const content: TdObject = { '@type': 'inputMessageText' };
    content['text'] = ft;
    const req: TdRequest = { '@type': 'sendMessage' };
    req['chat_id'] = this.chatId;
    if (replyToId !== 0) {
      const rt: TdObject = { '@type': 'inputMessageReplyToMessage' };
      rt['message_id'] = replyToId;
      req['reply_to'] = rt;
    }
    req['input_message_content'] = content;
    this.applyTopicScope(req);
    // 诊断：sendMessage 的往返耗时。用户报"发消息慢"（issue #47），但慢在
    // 哪一段没量过——TDLib 本地接收下这个请求本该是毫秒级的，真慢的话说明
    // 应答排在主线程上别的活后面（所有 TDLib 应答都经 threadsafe function
    // 投递到 UI 线程，updateFile 的洪流也在同一条队里）。先把数拿到。
    const sentAt: number = Date.now();
    return this.client.send(req).then((m: TdObject): void => {
      const roundTripMs: number = Date.now() - sentAt;
      if (roundTripMs > 300) {
        console.warn(`[SendDiag] sendMessage roundTrip=${roundTripMs}ms rows=${this.messages.length}`);
      } else {
        console.info(`[SendDiag] sendMessage roundTrip=${roundTripMs}ms rows=${this.messages.length}`);
      }
      this.upsert(buildMessageEntry(m, this.users));
      this.resolveReplies();
      this.notifySoon();
    });
  }

  // Replace a text message's content in place. TDLib returns the edited
  // message; upsert applies it (updateMessageContent also mirrors the change
  // on other devices).
  editTextAsync(messageId: number, text: string): Promise<void> {
    const ft: TdObject = { '@type': 'formattedText' };
    ft['text'] = text;
    const content: TdObject = { '@type': 'inputMessageText' };
    content['text'] = ft;
    const req: TdRequest = { '@type': 'editMessageText' };
    req['chat_id'] = this.chatId;
    req['message_id'] = messageId;
    req['input_message_content'] = content;
    return this.client.send(req).then((m: TdObject): void => {
      this.upsert(buildMessageEntry(m, this.users));
      this.resolveReplies();
      this.notifySoon();
    });
  }

  private lastTypingAtMs: number = 0;

  // "typing…" indicator for the peer. Throttled: Telegram clients resend the
  // action at most every few seconds while input continues.
  notifyTyping(): void {
    const now = Date.now();
    if (now - this.lastTypingAtMs < 4000) { return; }
    this.lastTypingAtMs = now;
    const req: TdRequest = { '@type': 'sendChatAction' };
    req['chat_id'] = this.chatId;
    this.applyTopicScope(req);
    req['action'] = { '@type': 'chatActionTyping' } as TdObject;
    this.client.send(req).catch((): void => {});
  }

  // Persist (or clear, when text is empty) the chat draft so it syncs to the
  // account's other devices. TDLib clears the draft itself on send.
  saveDraft(text: string, replyToId: number): void {
    const req: TdRequest = { '@type': 'setChatDraftMessage' };
    req['chat_id'] = this.chatId;
    this.applyTopicScope(req);
    if (text.trim() !== '') {
      const ft: TdObject = { '@type': 'formattedText' };
      ft['text'] = text;
      const content: TdObject = { '@type': 'inputMessageText' };
      content['text'] = ft;
      const draft: TdObject = { '@type': 'draftMessage' };
      draft['input_message_text'] = content;
      if (replyToId !== 0) {
        const rt: TdObject = { '@type': 'inputMessageReplyToMessage' };
        rt['message_id'] = replyToId;
        draft['reply_to'] = rt;
      }
      req['draft_message'] = draft;
    }
    this.client.send(req).catch((e: TdError): void => {
      console.error(`MessageStore.saveDraft failed: ${e.message}`);
    });
  }

  // Send a text message at a future time (scheduling_state), or silently.
  sendScheduledAsync(
    text: string, replyToId: number, sendDate: number, silent: boolean
  ): Promise<void> {
    const ft: TdObject = { '@type': 'formattedText' };
    ft['text'] = text;
    const content: TdObject = { '@type': 'inputMessageText' };
    content['text'] = ft;
    const options: TdObject = { '@type': 'messageSendOptions' };
    options['disable_notification'] = silent;
    if (sendDate > 0) {
      const schedule: TdObject = { '@type': 'messageSchedulingStateSendAtDate' };
      schedule['send_date'] = sendDate;
      options['scheduling_state'] = schedule;
    }
    const req: TdRequest = { '@type': 'sendMessage' };
    req['chat_id'] = this.chatId;
    if (replyToId !== 0) {
      const rt: TdObject = { '@type': 'inputMessageReplyToMessage' };
      rt['message_id'] = replyToId;
      req['reply_to'] = rt;
    }
    req['input_message_content'] = content;
    req['options'] = options;
    this.applyTopicScope(req);
    return this.client.send(req).then((m: TdObject): void => {
      // Scheduled messages live in a separate list; only immediate silent
      // sends belong in the visible history.
      if (sendDate <= 0) {
        this.upsert(buildMessageEntry(m, this.users));
        this.notifySoon();
      }
    });
  }

  stopPollAsync(messageId: number): Promise<void> {
    const req: TdRequest = { '@type': 'stopPoll' };
    req['chat_id'] = this.chatId;
    req['message_id'] = messageId;
    return this.client.send(req).then((): void => {});
  }

  // Public-poll voters for one option, resolved to display names.
  pollVotersAsync(messageId: number, optionId: number): Promise<TdObject> {
    const req: TdRequest = { '@type': 'getPollVoters' };
    req['chat_id'] = this.chatId;
    req['message_id'] = messageId;
    req['option_id'] = optionId;
    req['offset'] = 0;
    req['limit'] = 50;
    return this.client.send(req, 12000);
  }

  setAutoDeleteAsync(seconds: number): Promise<void> {
    const req: TdRequest = { '@type': 'setChatMessageAutoDeleteTime' };
    req['chat_id'] = this.chatId;
    req['message_auto_delete_time'] = seconds;
    return this.client.send(req).then((): void => {});
  }

  // Clear the @-mention and reaction badges for this chat.
  readAllBadges(): void {
    const mentions: TdRequest = { '@type': 'readAllChatMentions' };
    mentions['chat_id'] = this.chatId;
    this.client.send(mentions).catch((): void => {});
    const reactions: TdRequest = { '@type': 'readAllChatReactions' };
    reactions['chat_id'] = this.chatId;
    this.client.send(reactions).catch((): void => {});
  }

  // Pin / unpin one message. The pinned banner refreshes through the store's
  // existing pinned-message tracking (service message + pinned list updates).
  pinAsync(messageId: number): Promise<void> {
    const req: TdRequest = { '@type': 'pinChatMessage' };
    req['chat_id'] = this.chatId;
    req['message_id'] = messageId;
    req['disable_notification'] = false;
    req['only_for_self'] = false;
    return this.client.send(req).then((): void => { this.refreshPinned(); });
  }

  unpinAsync(messageId: number): Promise<void> {
    const req: TdRequest = { '@type': 'unpinChatMessage' };
    req['chat_id'] = this.chatId;
    req['message_id'] = messageId;
    return this.client.send(req).then((): void => { this.refreshPinned(); });
  }

  // 新版 td_api：inputMessageXxx 的媒体字段是包装对象（inputPhoto/inputVideo/
  // inputAudio/inputDocument/...），内部才是 InputFile。旧的裸 InputFile 会被
  // 解析成 null，td 报 "InputFile is not specified"。
  private static wrapInputFile(wrapperType: string, fileField: string,
    inputFile: TdObject): TdObject {
    const wrapper: TdObject = { '@type': wrapperType };
    wrapper[fileField] = inputFile;
    return wrapper;
  }

  private static localFile(path: string): TdObject {
    const inputFile: TdObject = { '@type': 'inputFileLocal' };
    inputFile['path'] = path;
    return inputFile;
  }

  // Swap the media of an already-sent photo/video message (keeps the caption).
  editMediaAsync(messageId: number, path: string, isVideo: boolean, caption: string): Promise<void> {
    const inputFile: TdObject = MessageStore.localFile(path);
    const content: TdObject = {
      '@type': isVideo ? 'inputMessageVideo' : 'inputMessagePhoto'
    };
    content[isVideo ? 'video' : 'photo'] = MessageStore.wrapInputFile(
      isVideo ? 'inputVideo' : 'inputPhoto', isVideo ? 'video' : 'photo', inputFile);
    if (caption !== '') {
      const ft: TdObject = { '@type': 'formattedText' };
      ft['text'] = caption;
      content['caption'] = ft;
    }
    const req: TdRequest = { '@type': 'editMessageMedia' };
    req['chat_id'] = this.chatId;
    req['message_id'] = messageId;
    req['input_message_content'] = content;
    return this.client.send(req, 30000).then((m: TdObject): void => {
      this.upsert(buildMessageEntry(m, this.users));
      this.notifySoon();
    });
  }

  // Reschedule a pending scheduled message.
  editScheduleAsync(messageId: number, sendDate: number): Promise<void> {
    const state: TdObject = { '@type': 'messageSchedulingStateSendAtDate' };
    state['send_date'] = sendDate;
    const req: TdRequest = { '@type': 'editMessageSchedulingState' };
    req['chat_id'] = this.chatId;
    req['message_id'] = messageId;
    req['scheduling_state'] = state;
    return this.client.send(req, 15000).then((): void => {});
  }

  // Replace a media message's caption (photo/video/file/audio/voice).
  editCaptionAsync(messageId: number, caption: string): Promise<void> {
    const ft: TdObject = { '@type': 'formattedText' };
    ft['text'] = caption;
    const req: TdRequest = { '@type': 'editMessageCaption' };
    req['chat_id'] = this.chatId;
    req['message_id'] = messageId;
    req['caption'] = ft;
    return this.client.send(req).then((m: TdObject): void => {
      this.upsert(buildMessageEntry(m, this.users));
      this.resolveReplies();
      this.notifySoon();
    });
  }

  // Toggle a reaction on a message. `reactionKey` 既可以是标准 emoji，也可以是
  // 'ce:<custom_emoji_id>' 形式的自定义 emoji（见 util/reactions.ets）。TDLib
  // 会通过 updateMessageInteractionInfo 推回新的计数，onInteraction() 已处理。
  setReaction(messageId: number, reactionKey: string, isChosen: boolean): Promise<void> {
    const rt: TdObject = reactionTypeOf(reactionKey);
    if (isChosen) {
      const req: TdRequest = { '@type': 'removeMessageReaction' };
      req['chat_id'] = this.chatId;
      req['message_id'] = messageId;
      req['reaction_type'] = rt;
      return this.client.send(req).then((): void => {}).catch((e: TdError): Promise<void> => {
        console.error(`MessageStore.removeMessageReaction failed: ${e.message}`);
        return Promise.reject(e);
      });
    }
    const req: TdRequest = { '@type': 'addMessageReaction' };
    req['chat_id'] = this.chatId;
    req['message_id'] = messageId;
    req['reaction_type'] = rt;
    req['is_big'] = false;
    req['update_recent_reactions'] = true;
    return this.client.send(req).then((): void => {}).catch((e: TdError): Promise<void> => {
      console.error(`MessageStore.addMessageReaction failed: ${e.message}`);
      return Promise.reject(e);
    });
  }

  // Resolve a public/private t.me link for a message (used by 拷贝消息链接).
  messageLink(messageId: number, cb: (url: string) => void): void {
    const req: TdRequest = { '@type': 'getMessageLink' };
    req['chat_id'] = this.chatId;
    req['message_id'] = messageId;
    this.client.send(req).then((res: TdObject) => {
      cb((res['link'] as string | undefined) ?? '');
    }).catch((e: TdError) => {
      console.error(`MessageStore.getMessageLink failed: ${e.message}`);
      cb('');
    });
  }

  // Send a document from a local (sandbox) path. TDLib uploads it and the
  // pending message arrives via the normal update flow.
  sendDocument(path: string, caption: string): void {
    const content: TdObject = { '@type': 'inputMessageDocument' };
    content['document'] = MessageStore.wrapInputFile(
      'inputDocument', 'document', MessageStore.localFile(path));
    if (caption !== '') {
      const ft: TdObject = { '@type': 'formattedText' };
      ft['text'] = caption;
      content['caption'] = ft;
    }
    const req: TdRequest = { '@type': 'sendMessage' };
    req['chat_id'] = this.chatId;
    req['input_message_content'] = content;
    this.applyTopicScope(req);
    this.client.send(req).then((m: TdObject) => {
      this.upsert(buildMessageEntry(m, this.users));
      // Media returned by sendMessage still needs the same local-file
      // resolution as history/new-message entries. Omitting this left a newly
      // sent sticker on its loading ring until the chat was reopened.
      this.requestPhotos();
      this.notifySoon();
    }).catch((e: TdError) => {
      console.error(`MessageStore.sendDocument failed: ${e.message}`);
    });
  }

  // Shared sendMessage plumbing for media content types.
  private sendContent(content: TdObject, tag: string, replyToId: number = 0): Promise<number> {
    const req: TdRequest = { '@type': 'sendMessage' };
    req['chat_id'] = this.chatId;
    req['input_message_content'] = content;
    if (replyToId > 0) {
      const replyTo: TdObject = { '@type': 'inputMessageReplyToMessage' };
      replyTo['message_id'] = replyToId;
      req['reply_to'] = replyTo;
    }
    this.applyTopicScope(req);
    return this.client.send(req).then((m: TdObject): number => {
      this.upsert(buildMessageEntry(m, this.users));
      this.requestPhotos();
      this.notifySoon();
      return (m['id'] as number | undefined) ?? 0;
    }).catch((e: TdError): number => {
      console.error(`MessageStore.${tag} failed: ${e.message}`);
      return 0;
    });
  }

  // 投票：options 为选项文本；isQuiz 时 correctOptionId 指向正确选项下标。
  // TDLib 1.8.15+ 的 question/options 是 formattedText（纯字符串会被拒）。
  sendPoll(question: string, options: string[], isAnonymous: boolean,
    isQuiz: boolean, correctOptionId: number): void {
    const toFormatted = (text: string): TdObject => {
      const ft: TdObject = { '@type': 'formattedText' };
      ft['text'] = text;
      return ft;
    };
    const content: TdObject = { '@type': 'inputMessagePoll' };
    content['question'] = toFormatted(question);
    content['options'] = options.map((option: string): TdObject => toFormatted(option));
    content['is_anonymous'] = isAnonymous;
    if (isQuiz) {
      const quizType: TdObject = { '@type': 'pollTypeQuiz' };
      quizType['correct_option_id'] = correctOptionId;
      content['type'] = quizType;
    } else {
      content['type'] = { '@type': 'pollTypeRegular' } as TdObject;
    }
    this.sendContent(content, 'sendPoll');
  }

  sendLocation(latitude: number, longitude: number): void {
    const location: TdObject = { '@type': 'location' };
    location['latitude'] = latitude;
    location['longitude'] = longitude;
    const content: TdObject = { '@type': 'inputMessageLocation' };
    content['location'] = location;
    this.sendContent(content, 'sendLocation');
  }

  // 实时位置：live_period 秒内可持续更新。TDLib 用 0x7FFFFFFF 表示"永久"，
  // 但那个值一般只在特定场景才被接受，这里只给有限时长。
  //
  // 必须用 inputMessageLiveLocation —— 捆绑的 libtdjson.so 把实时位置拆成了
  // 独立的类（strings 里 inputMessageLocation / inputMessageLiveLocation 并存）。
  // 挂在 inputMessageLocation 上的 live_period 会被 JSON 解析静默丢弃，发出去
  // 的是一条静态位置，事后怎么 edit 都不会动。
  sendLiveLocation(latitude: number, longitude: number, livePeriodSec: number): Promise<number> {
    const location: TdObject = { '@type': 'location' };
    location['latitude'] = latitude;
    location['longitude'] = longitude;
    // location 字段的类型是 liveLocation（一个包装层），不是裸 location：
    // live_period/heading/proximity_alert_radius 都挂在包装层上。塞裸 location
    // 会因为 @type 对不上被判为空 —— "Live location must be non-empty"。
    const live: TdObject = { '@type': 'liveLocation' };
    live['location'] = location;
    live['live_period'] = livePeriodSec;
    live['heading'] = 0;
    live['proximity_alert_radius'] = 0;
    const content: TdObject = { '@type': 'inputMessageLiveLocation' };
    content['location'] = live;
    return this.sendContent(content, 'sendLiveLocation');
  }

  // 更新一条已发出的实时位置。location 传 null 即停止共享（schema 里
  // "pass null to stop sharing the live location"）。
  updateLiveLocation(messageId: number, latitude: number, longitude: number,
    livePeriodSec: number): Promise<void> {
    const location: TdObject = { '@type': 'location' };
    location['latitude'] = latitude;
    location['longitude'] = longitude;
    const live: TdObject = { '@type': 'liveLocation' };
    live['location'] = location;
    live['live_period'] = livePeriodSec;
    live['heading'] = 0;
    live['proximity_alert_radius'] = 0;
    return this.editLiveLocation(messageId, live);
  }

  // 不带 location（即 null）就是停止共享。
  stopLiveLocation(messageId: number): Promise<void> {
    return this.editLiveLocation(messageId, null);
  }

  // location 是 liveLocation 包装层，不是裸 location —— 详见 LiveLocationService。
  private editLiveLocation(messageId: number, live: TdObject | null): Promise<void> {
    const req: TdRequest = { '@type': 'editMessageLiveLocation' };
    req['chat_id'] = this.chatId;
    req['message_id'] = messageId;
    if (live !== null) {
      req['location'] = live;
    }
    return this.client.send(req, 15000).then((): void => {});
  }

  sendContact(phoneNumber: string, firstName: string, lastName: string, userId: number): void {
    const contact: TdObject = { '@type': 'contact' };
    contact['phone_number'] = phoneNumber;
    contact['first_name'] = firstName;
    contact['last_name'] = lastName;
    contact['user_id'] = userId;
    const content: TdObject = { '@type': 'inputMessageContact' };
    content['contact'] = contact;
    this.sendContent(content, 'sendContact');
  }

  sendAudio(path: string, caption: string): void {
    const content: TdObject = { '@type': 'inputMessageAudio' };
    content['audio'] = MessageStore.wrapInputFile(
      'inputAudio', 'audio', MessageStore.localFile(path));
    if (caption !== '') {
      const ft: TdObject = { '@type': 'formattedText' };
      ft['text'] = caption;
      content['caption'] = ft;
    }
    this.sendContent(content, 'sendAudio');
  }

  sendDice(emoji: string): void {
    const content: TdObject = { '@type': 'inputMessageDice' };
    content['emoji'] = emoji;
    content['clear_draft'] = false;
    this.sendContent(content, 'sendDice');
  }

  sendPhoto(path: string, caption: string, replyToId: number = 0): void {
    const content: TdObject = { '@type': 'inputMessagePhoto' };
    content['photo'] = MessageStore.wrapInputFile(
      'inputPhoto', 'photo', MessageStore.localFile(path));
    if (caption !== '') {
      const ft: TdObject = { '@type': 'formattedText' };
      ft['text'] = caption;
      content['caption'] = ft;
    }
    this.sendContent(content, 'sendPhoto', replyToId);
  }

  sendVideo(path: string, caption: string, replyToId: number = 0): void {
    const content: TdObject = { '@type': 'inputMessageVideo' };
    content['video'] = MessageStore.wrapInputFile(
      'inputVideo', 'video', MessageStore.localFile(path));
    if (caption !== '') {
      const ft: TdObject = { '@type': 'formattedText' };
      ft['text'] = caption;
      content['caption'] = ft;
    }
    this.sendContent(content, 'sendVideo', replyToId);
  }

  private mediaInputContent(item: MediaSendItem, caption: string): TdObject {
    const inputFile: TdObject = MessageStore.localFile(item.path);
    const content: TdObject = {
      '@type': item.isVideo ? 'inputMessageVideo' : 'inputMessagePhoto'
    };
    content[item.isVideo ? 'video' : 'photo'] = MessageStore.wrapInputFile(
      item.isVideo ? 'inputVideo' : 'inputPhoto', item.isVideo ? 'video' : 'photo', inputFile);
    if (caption !== '') {
      const ft: TdObject = { '@type': 'formattedText' };
      ft['text'] = caption;
      content['caption'] = ft;
    }
    return content;
  }

  private rememberLocalMedia(entry: MessageEntry, item: MediaSendItem): MessageEntry {
    const hydrated = cloneMessage(entry);
    if (item.isVideo) {
      hydrated.videoPath = item.path;
      hydrated.videoProgress = 100;
      hydrated.videoFailed = false;
      hydrated.mediaDownloadActive = false;
      if (hydrated.videoFileId > 0) {
        this.completedFilePaths.set(hydrated.videoFileId, item.path);
        publishThumbPath(hydrated.videoFileId, item.path);
      }
    } else {
      hydrated.photoPath = item.path;
      hydrated.photoProgress = 100;
      hydrated.photoFailed = false;
      hydrated.photoFullPath = item.path;
      if (hydrated.photoFileId > 0) {
        this.completedFilePaths.set(hydrated.photoFileId, item.path);
        publishThumbPath(hydrated.photoFileId, item.path);
      }
      if (hydrated.photoFullFileId > 0) {
        this.completedFilePaths.set(hydrated.photoFullFileId, item.path);
        publishThumbPath(hydrated.photoFullFileId, item.path);
      }
    }
    return hydrated;
  }

  // The picker may return up to nine mixed photos/videos. Two or more items
  // must use sendMessageAlbum; sending them one-by-one loses media_album_id and
  // the receiver can never render a real Telegram album.
  sendMedia(items: MediaSendItem[], caption: string, replyToId: number = 0): Promise<void> {
    if (items.length === 0) {
      return Promise.resolve();
    }
    const contents: TdObject[] = [];
    for (let i = 0; i < items.length; i++) {
      contents.push(this.mediaInputContent(items[i], i === 0 ? caption : ''));
    }
    const req: TdRequest = {
      '@type': items.length > 1 ? 'sendMessageAlbum' : 'sendMessage'
    };
    req['chat_id'] = this.chatId;
    if (items.length > 1) {
      req['input_message_contents'] = contents;
    } else {
      req['input_message_content'] = contents[0];
    }
    if (replyToId > 0) {
      const replyTo: TdObject = { '@type': 'inputMessageReplyToMessage' };
      replyTo['message_id'] = replyToId;
      req['reply_to'] = replyTo;
    }
    this.applyTopicScope(req);
    return this.client.send(req).then((result: TdObject): void => {
      const sent: TdObject[] = items.length > 1
        ? ((result['messages'] as TdObject[] | undefined) ?? [])
        : [result];
      for (let i = 0; i < sent.length; i++) {
        const source = items[Math.min(i, items.length - 1)];
        const entry = this.rememberLocalMedia(buildMessageEntry(sent[i], this.users), source);
        this.upsert(entry);
      }
      this.resolveReplies();
      this.requestPhotos();
      this.notifySoon();
    }).catch((e: TdError): Promise<void> => {
      console.error(`MessageStore.sendMedia failed: ${e.message}`);
      return Promise.reject(e);
    });
  }

  // Send a sticker the user picked from an installed set (already on Telegram
  // servers — reference it by TDLib file id).
  // 注意：捆绑的 td 快照是"半新" schema —— photo/video/audio/document 用
  // 包装对象，但 sticker/animation/voiceNote 仍是旧的裸 InputFile
  // （真机验证：inputSticker 包装报 Unknown class）。升级 tdlib 时重查。
  sendSticker(fileId: number, width: number, height: number): void {
    const inputFile: TdObject = { '@type': 'inputFileId' };
    inputFile['id'] = fileId;
    const content: TdObject = { '@type': 'inputMessageSticker' };
    content['sticker'] = inputFile;
    content['width'] = width;
    content['height'] = height;
    this.sendContent(content, 'sendSticker');
  }

  // Send a saved GIF (server-side file, referenced by id).
  sendAnimation(fileId: number, width: number, height: number, durationSec: number): void {
    const inputFile: TdObject = { '@type': 'inputFileId' };
    inputFile['id'] = fileId;
    const content: TdObject = { '@type': 'inputMessageAnimation' };
    content['animation'] = inputFile;
    content['width'] = width;
    content['height'] = height;
    content['duration'] = durationSec;
    this.sendContent(content, 'sendAnimation');
  }

  sendVoiceNote(path: string, durationSec: number): void {
    const content: TdObject = { '@type': 'inputMessageVoiceNote' };
    content['voice_note'] = MessageStore.localFile(path);
    content['duration'] = durationSec;
    this.sendContent(content, 'sendVoiceNote');
  }

  // 圆形视频消息。length 是正方形边长（圆形视频宽高相等）。
  // video_note 是裸 InputFile，和 voiceNote/sticker/animation 一族一致 —— 捆绑的
  // libtdjson.so 里根本没有 inputVideoNote 这个类（`strings libtdjson.so` 只有
  // inputMessageVideoNote），包装对象会被判为未知类型而整条消息发不出去。
  // 对应地 duration/length 直接挂在 inputMessageVideoNote 外层。
  sendVideoNote(path: string, durationSec: number, length: number): void {
    const content: TdObject = { '@type': 'inputMessageVideoNote' };
    content['video_note'] = MessageStore.localFile(path);
    content['duration'] = durationSec;
    content['length'] = length;
    this.sendContent(content, 'sendVideoNote');
  }

  // 语音/圆形视频转文字。调用只返回 Ok，识别结果异步经 updateMessageContent
  // 回流（speech_recognition_result），所以这里只负责发起并把本地状态置为
  // pending，让气泡立刻有反馈。
  //
  // 这是 Premium 功能：非会员账号服务端会直接拒绝，错误原样抛给调用方去提示。
  recognizeSpeech(messageId: number): Promise<void> {
    const idx = this.indexOf(messageId);
    if (idx < 0) {
      return Promise.reject(new Error(str('ms_message_missing')));
    }
    this.patch(messageId, (c: MessageEntry): void => {
      c.speechState = 'pending';
      c.speechText = '';
    });
    const req: TdRequest = { '@type': 'recognizeSpeech' };
    req['chat_id'] = this.chatId;
    req['message_id'] = messageId;
    return this.client.send(req, 30000).then((): void => {}).catch((e: TdError): void => {
      // 失败要把 pending 撤回，否则气泡会永远转圈。
      this.patch(messageId, (c: MessageEntry): void => {
        c.speechState = '';
        c.speechText = '';
      });
      throw e as Error;
    });
  }

  private sendSimple(type: string): void {
    const req: TdRequest = { '@type': type };
    req['chat_id'] = this.chatId;
    this.client.send(req).catch((e: TdError) => {
      console.error(`MessageStore.${type} failed: ${e.message}`);
    });
  }

  private loadHistory(fromId: number): void {
    const req = this.historyRequest(fromId, 0);
    // 首屏页刻意取小。实测把通知风暴整个压掉后首帧依然掉帧——瓶颈是一帧里
    // 构建 30 个 MessageBubble 本身。12 条铺满一屏出头；'latest' 的短页补链
    // （见 onHistory）随即用增量前插把整页补齐，mvcp 保锚点，肉眼无感。
    if (fromId === 0 && this.initialHistoryState === 'loading') {
      req['limit'] = Math.min(INITIAL_FIRST_PAGE, this.historyPageSize);
    }
    this.client.send(req).then((res: TdObject) => this.onHistory(res, fromId === 0 ? 'latest' : 'history'))
      .catch((e: TdError) => {
      const code = (e as TdError).code;
      if (code !== 404) {
        console.error(`MessageStore.getChatHistory failed: ${e.message}`);
      }
      if (this.initialHistoryState === 'loading') {
        // A 404 is TDLib's valid "this chat has no messages" result.
        this.initialHistoryState = code === 404 ? 'ready' : 'error';
        this.initialHistoryError = code === 404 ? '' : this.historyErrorHint(e);
        if (code === 404) {
          this.hasMoreOlder = false;
          this.olderLoadState = 'end';
        }
        this.notify('initialState');
      }
    });
  }

  private onHistory(res: TdObject, kind: string = 'history'): void {
    const arr = (res['messages'] as TdObject[] | undefined) ?? [];
    if (this.initialHistoryState !== 'ready' && (kind === 'latest' || kind === 'around')) {
      // 首页即将发布：接下来的解析回填进入宽合并窗（见 notifySoon）。
      this.initialSettleStart = Date.now();
    }
    this.initialHistoryState = 'ready';
    this.initialHistoryError = '';
    if (kind === 'latest') {
      // TDLib may legally return FEWER messages than requested — for a chat
      // visited the first time, commonly just one (its newest message) — even
      // though more history exists. Only an empty result proves the chat has
      // no messages; a short non-empty page keeps older-paging enabled and is
      // backfilled immediately below.
      this.hasMoreOlder = arr.length > 0;
      this.olderLoadState = this.hasMoreOlder ? 'idle' : 'end';
      this.hasMoreNewer = false;
      this.newerLoadState = 'end';
    }
    // Keyboard fallback is probed from the live tail separately. Scanning an
    // arbitrary around/older page here can resurrect a stale keyboard that a
    // newer remove marker already superseded.
    this.ensureKeyboardHistoryProbe();
    const entries: MessageEntry[] = arr.map((m: TdObject): MessageEntry => buildMessageEntry(m, this.users));
    console.info(`[StoreDiag] onHistory kind=${kind} got=${arr.length}` +
      ` rowsBefore=${this.messages.length} oldest=${this.oldestId}`);
    this.logWindowGap(kind);
    // Continuity check for the newest page. If it does not overlap the loaded
    // window — its oldest id is newer than everything we hold — then the pages
    // between were never fetched (they were delivered while the process was
    // suspended). Merging would render the two runs seamlessly glued with the
    // middle silently missing, so replace the window instead; older paging
    // refills downward from the new tail. Skipped when the window's newest id
    // is a pending outgoing message (huge local id): replacement would drop an
    // unsent message, and that corner merges as before.
    if (kind === 'latest' && entries.length > 0 && this.messages.length > 0) {
      let pageOldest: number = entries[0].id;
      for (const e of entries) {
        if (e.id < pageOldest) {
          pageOldest = e.id;
        }
      }
      const windowNewest: number = this.messages[this.messages.length - 1].id;
      let pageNewest: number = entries[0].id;
      for (const e of entries) {
        if (e.id > pageNewest) {
          pageNewest = e.id;
        }
      }
      const replaced: boolean = pageOldest > windowNewest;
      // 诊断：恢复后窗口出现空洞。要判的是这一页到底装了什么——是不是真的
      // 最新页、和窗口有没有重叠、替换与否。
      console.info(`[StoreDiag] latest page=${entries.length}` +
        ` [${pageOldest}..${pageNewest}] windowNewest=${windowNewest}` +
        ` windowLen=${this.messages.length} replaced=${replaced}`);
      if (replaced) {
        this.messages = [];
        this.hasMoreOlder = true;
        this.olderLoadState = 'idle';
      }
    }
    this.upsertBatch(entries);
    if (this.messages.length > 0) {
      this.oldestId = this.messages[0].id;
    }
    // First-visit backfill: chain one older-page request when the initial
    // response came back short, so the page fills in right after the first
    // (possibly single-message) snapshot renders.
    if (kind === 'latest' && arr.length > 0 && arr.length < this.historyPageSize) {
      this.initialFillTries = INITIAL_FILL_TRIES;
      this.loadOlder();
    } else if (kind === 'older' && this.initialFillTries > 0) {
      // 首屏填充的续追：还短就再问一次。回 0 说明真到顶，够一页说明填满了，
      // 两种情况都收手。
      this.initialFillTries--;
      const stillShort: boolean = this.messages.length < this.historyPageSize;
      if (arr.length > 0 && stillShort && this.initialFillTries > 0) {
        this.loadOlder();
      } else {
        this.initialFillTries = 0;
      }
    }
    this.injectLastMessageAtTail();
    this.resolveReplies();
    this.resolveForwardTitles();
    this.requestPhotos();
    this.resolveSenderAvatars();
    this.resolveCommentAvatars();
    // NOTE: do NOT mark messages read here. Read state is a high-water mark in
    // TDLib, so viewing the newest loaded message would mark ALL older ones read.
    // Read-marking is driven by the actually-visible range (see markViewed).
    // Hold the very first render until getChat supplies the unread anchor, so the
    // page can position at the first unread message without a race. Later loads
    // (loadOlder) notify normally.
    if (this.chatResolved) {
      this.notify(kind);
    } else {
      this.historyPending = true;
      this.historyPendingKind = kind;
    }
    this.acknowledgeInitialJoinService();
  }

  // --- whole-chat translation ------------------------------------------------
  //
  // TranslationService owns the cache and the request queue; these methods own
  // the write path into the entries, because only the store can raise the
  // CHANGE notifications the list renders from. translatedText feeds the row's
  // content signature (mutableSig), so a translation landing rebuilds exactly
  // that row.

  applyTranslation(messageId: number, lang: string, text: string): void {
    this.patch(messageId, (c: MessageEntry): void => {
      c.translatedText = text;
      c.translatedLang = lang;
    });
  }

  setTranslationHidden(messageId: number, hidden: boolean): void {
    this.patch(messageId, (c: MessageEntry): void => {
      c.translationHidden = hidden;
    });
  }

  // Turning whole-chat translation off strips the rendered translations in one
  // pass; the service keeps its cache, so turning it back on is instant.
  clearTranslations(): void {
    let changed = false;
    const next = this.messages.map((m: MessageEntry): MessageEntry => {
      if (m.translatedText === '' && !m.translationHidden) {
        return m;
      }
      const c = cloneMessage(m);
      c.translatedText = '';
      c.translatedLang = '';
      c.translationHidden = false;
      changed = true;
      return c;
    });
    if (changed) {
      this.messages = next;
      this.notifySoon();
    }
  }

  // Message ids in the given display range worth translating: visible text,
  // no translation for the current target yet. The caller feeds these to
  // TranslationService.
  translationCandidates(fromId: number, toId: number, lang: string): MessageEntry[] {
    const out: MessageEntry[] = [];
    for (const m of this.messages) {
      if (m.id < fromId || m.id > toId) {
        continue;
      }
      if (m.text === '' || m.contentType === 'system' || m.contentType === 'hidden') {
        continue;
      }
      if (m.translatedText !== '' && m.translatedLang === lang) {
        continue;
      }
      out.push(m);
    }
    return out;
  }

  // Graft chat.last_message into the timeline when history alone didn't reach
  // it (local service messages never come back from getChatHistory). Gated on
  // the loaded window being at the live tail so a jump into old history can't
  // create a gap between the window and an injected far-future tail message.
  private injectLastMessageAtTail(): void {
    const m = this.pendingLastMessage;
    if (m === null || this.hasMoreNewer) {
      return;
    }
    this.pendingLastMessage = null;
    const id = (m['id'] as number | undefined) ?? 0;
    const newestId = this.messages.length > 0 ? this.messages[this.messages.length - 1].id : 0;
    if (id <= 0 || id <= newestId) {
      return; // already part of the loaded window
    }
    // 诊断：这里是唯一会把一条"远期"消息硬接在窗口尾巴上的地方，观测到的
    // 空洞形状（一段连续的旧消息 + 孤零零一条最新的）正好是它的产物。
    // id 与 newestId 的差值就是被跳过的消息条数（TDLib 的 id 每条加 2^20）。
    const skipped: number = Math.round((id - newestId) / 1048576);
    if (skipped > 1) {
      console.warn(`[StoreDiag] inject tail id=${id} newestId=${newestId}` +
        ` skipped=${skipped} windowLen=${this.messages.length}`);
    }
    this.upsert(buildMessageEntry(m, this.users));
  }

  // `messageChatJoinByLink` / the equivalent member-add notice can be LOCAL:
  // getChat exposes it as last_message, while getChatHistory omits it forever.
  // For the narrowly safe case of exactly one unread service notice at the
  // live tail, insert it immediately instead of waiting for newer pagination
  // to prove a tail that history can never contain.
  private injectSoleUnreadJoinService(lastMessage: TdObject | undefined): void {
    if (this.threadRootId > 0 || this.requestedAroundMessageId > 0 ||
      this.unreadCount !== 1 || lastMessage === undefined) {
      return;
    }
    const entry = buildMessageEntry(lastMessage, this.users);
    if (entry.id <= 0 || entry.contentType !== 'system' ||
      (entry.systemType !== 'messageChatJoinByLink' &&
       entry.systemType !== 'messageChatJoinByRequest' &&
       entry.systemType !== 'messageChatAddMembers')) {
      return;
    }
    this.upsert(entry);
    this.pendingLastMessage = null;
    this.initialJoinServiceReadId = entry.id;
  }

  private acknowledgeInitialJoinService(): void {
    const messageId = this.initialJoinServiceReadId;
    if (messageId <= 0 || this.initialHistoryState !== 'ready' ||
      this.initialJoinServiceReadPending) {
      return;
    }
    this.initialJoinServiceReadPending = true;
    const req: TdRequest = { '@type': 'viewMessages' };
    req['chat_id'] = this.chatId;
    req['message_ids'] = [messageId];
    req['force_read'] = true;
    this.client.send(req).then((): void => {
      this.initialJoinServiceReadPending = false;
      this.initialJoinServiceReadId = 0;
      this.viewedUpTo = Math.max(this.viewedUpTo, messageId);
      this.unreadCount = 0;
      this.clearManualUnreadFlag();
    }).catch((error: TdError): void => {
      this.initialJoinServiceReadPending = false;
      console.error(`MessageStore.viewInitialJoinService failed: ${error.message}`);
    });
  }

  private clearManualUnreadFlag(): void {
    if (this.manualUnreadClearSent) {
      return;
    }
    this.manualUnreadClearSent = true;
    const req: TdRequest = { '@type': 'toggleChatIsMarkedAsUnread' };
    req['chat_id'] = this.chatId;
    req['is_marked_as_unread'] = false;
    this.client.send(req).catch((error: TdError): void => {
      this.manualUnreadClearSent = false;
      console.error(`MessageStore.clearMarkedUnread failed: ${error.message}`);
    });
  }

  private flushInitial(): void {
    this.chatResolved = true;
    if (this.historyPending) {
      this.historyPending = false;
      this.notify(this.historyPendingKind);
      this.historyPendingKind = 'history';
    }
  }

  private onNewMessage(u: TdObject): void {
    const m = u['message'] as TdObject | undefined;
    if (m === undefined || (m['chat_id'] as number | undefined) !== this.chatId) {
      return;
    }
    // Thread mode: only messages of this thread belong in the view.
    if (this.outsideTopicScope(m)) {
      return;
    }
    // A bot that shows/removes its keyboard does it via a message's markup.
    this.scanKeyboardMarkup([m]);
    const entry: MessageEntry = buildMessageEntry(m, this.users);
    // 窗口停在旧历史里时，实时到达的消息不能直接贴到尾部。
    //
    // 它和窗口最后一条之间可能隔着上万条没加载的历史，贴上去就是一个永久的
    // 洞——后续加载都发生在更新的那一端，中间那段再也没人去取。实测：停在
    // 未读锚点几分钟，频道来了 5 条，窗口里就出现 13009 条的缺口。
    //
    // 不收也不会丢：用户往下翻时由分页把它连同中间那段一起取回来。
    // injectLastMessageAtTail 早就有同样的门槛（见那边的注释），这里一直漏着。
    //
    // 自己发出去的消息例外——那是用户刚做的动作，必须立刻可见。
    if (this.hasMoreNewer && !entry.isOutgoing) {
      console.info(`[StoreDiag] live arrival skipped id=${entry.id}` +
        ` windowNewest=${this.messages.length > 0 ? this.messages[this.messages.length - 1].id : 0}`);
      return;
    }
    this.upsert(entry);
    // 实时到达（不是翻历史翻出来的）。整段媒体的可见窗口对这些消息放行：
    // 它们一次就一条，用户多半正看着尾部，等滚动事件才下会明显发愣。
    this.liveArrivals.add(entry.id);
    if (!entry.isOutgoing && (entry.contentType === 'photo' || entry.contentType === 'video' ||
      entry.contentType === 'audio' || entry.contentType === 'file')) {
      if (this.liveIncomingMediaIds.indexOf(entry.id) < 0) {
        this.liveIncomingMediaIds.push(entry.id);
      }
    }
    this.resolveReplies();
    this.resolveForwardTitles();
    this.requestPhotos();
    this.resolveSenderAvatars();
    this.resolveCommentAvatars();
    // New incoming messages are marked read only when they become visible
    // (driven by markViewed from the page), not on arrival.
    this.notifySoon();
  }

  private onSendSucceeded(u: TdObject): void {
    const oldId = u['old_message_id'] as number | undefined;
    const m = u['message'] as TdObject | undefined;
    if (oldId === undefined || m === undefined ||
      (m['chat_id'] as number | undefined) !== this.chatId) {
      return;
    }
    if (this.outsideTopicScope(m)) {
      return;
    }
    // 行身份必须跨过这次替换：临时 id 那条的 rowId 传给真实 id 那条，
    // 列表才不会把它当成新行销毁重建（发完消息"闪一下"的来源）。
    const previous = this.messages.find((e: MessageEntry): boolean => e.id === oldId);
    const carriedRowId: number = previous !== undefined ? previous.rowId : 0;
    this.messages = this.messages.filter((e: MessageEntry) => e.id !== oldId);
    const arrived = buildMessageEntry(m, this.users);
    if (carriedRowId !== 0) {
      arrived.rowId = carriedRowId;
    }
    publishSendState(arrived.rowId, arrived.sendState);
    this.upsert(arrived);
    this.resolveReplies();
    this.requestPhotos();
    this.notifySoon();
  }

  private onSendFailed(u: TdObject): void {
    const m = u['message'] as TdObject | undefined;
    if (m === undefined || (m['chat_id'] as number | undefined) !== this.chatId) {
      return;
    }
    if (this.outsideTopicScope(m)) {
      return;
    }
    const id = m['id'] as number;
    this.patch(id, (c: MessageEntry) => { c.sendState = 'failed'; });
  }

  private onContent(u: TdObject): void {
    if ((u['chat_id'] as number | undefined) !== this.chatId) {
      return;
    }
    const id = u['message_id'] as number | undefined;
    if (id === undefined) {
      return;
    }
    const idx = this.indexOf(id);
    if (idx < 0) {
      return;
    }
    // rebuild content by wrapping the new content into a message-like object
    const fake: TdObject = { '@type': 'message' };
    fake['content'] = u['new_content'];
    const rebuilt = buildMessageEntry(fake, this.users);
    this.patch(id, (c: MessageEntry) => {
      const sameVideoFile: boolean = c.videoFileId !== 0 && c.videoFileId === rebuilt.videoFileId;
      const samePhotoFile: boolean = c.photoFileId !== 0 && c.photoFileId === rebuilt.photoFileId;
      const sameStickerFile: boolean = c.stickerFileId !== 0 &&
        c.stickerFileId === rebuilt.stickerFileId;
      const sameLinkPhotoFile: boolean = c.linkPhotoFileId !== 0 &&
        c.linkPhotoFileId === rebuilt.linkPhotoFileId;
      const sameContactUser: boolean = c.contactUserId !== 0 &&
        c.contactUserId === rebuilt.contactUserId;
      const previousContactAvatarPath: string = c.contactAvatarPath;
      const previousPhotoPath: string = c.photoPath;
      const previousPhotoProgress: number = c.photoProgress;
      const previousPhotoFailed: boolean = c.photoFailed;
      const previousVideoPath: string = c.videoPath;
      const previousVideoProgress: number = c.videoProgress;
      const previousVideoFailed: boolean = c.videoFailed;
      const previousDownloadActive: boolean = c.mediaDownloadActive;
      const previousLinkPhotoPath: string = c.linkPhotoPath;
      const previousLinkPhotoProgress: number = c.linkPhotoProgress;
      const previousLinkPhotoFailed: boolean = c.linkPhotoFailed;
      const previousLinkPhotoActive: boolean = c.linkPhotoDownloadActive;
      c.contentType = rebuilt.contentType;
      c.text = rebuilt.text;
      c.textEntities = rebuilt.textEntities;
      c.inlineCustomEmojiIds = rebuilt.inlineCustomEmojiIds;
      c.inlineCustomEmojiPaths = rebuilt.inlineCustomEmojiPaths;
      c.photoFileId = rebuilt.photoFileId;
      c.photoWidth = rebuilt.photoWidth;
      c.photoHeight = rebuilt.photoHeight;
      c.placeholderLabel = rebuilt.placeholderLabel;
      c.photoPath = samePhotoFile ? previousPhotoPath : rebuilt.photoPath;
      c.photoProgress = samePhotoFile ? previousPhotoProgress : rebuilt.photoProgress;
      c.photoFailed = samePhotoFile ? previousPhotoFailed : rebuilt.photoFailed;
      c.linkSiteName = rebuilt.linkSiteName;
      c.linkTitle = rebuilt.linkTitle;
      c.linkDescription = rebuilt.linkDescription;
      c.linkDescriptionEntities = rebuilt.linkDescriptionEntities;
      c.linkPhotoFileId = rebuilt.linkPhotoFileId;
      c.linkPhotoPath = sameLinkPhotoFile ? previousLinkPhotoPath : rebuilt.linkPhotoPath;
      c.linkPhotoWidth = rebuilt.linkPhotoWidth;
      c.linkPhotoHeight = rebuilt.linkPhotoHeight;
      c.linkPhotoProgress = sameLinkPhotoFile ? previousLinkPhotoProgress : rebuilt.linkPhotoProgress;
      c.linkPhotoFailed = sameLinkPhotoFile ? previousLinkPhotoFailed : rebuilt.linkPhotoFailed;
      c.linkPhotoDownloadActive = sameLinkPhotoFile
        ? previousLinkPhotoActive : rebuilt.linkPhotoDownloadActive;
      c.linkPreviewType = rebuilt.linkPreviewType;
      c.linkUrl = rebuilt.linkUrl;
      c.photoFullFileId = rebuilt.photoFullFileId;
      c.photoFullPath = '';
      c.photoFullProgress = 0;
      c.photoFullFailed = false;
      c.videoFileId = rebuilt.videoFileId;
      c.videoFileSize = rebuilt.videoFileSize;
      c.videoMimeType = rebuilt.videoMimeType;
      c.videoFileName = rebuilt.videoFileName;
      c.videoDuration = rebuilt.videoDuration;
      c.isAnimation = rebuilt.isAnimation;
      // Listening to a voice note arrives as updateMessageContent. Preserve
      // the already-downloaded file when only is_listened/waveform changed;
      // otherwise the bubble jumps back to "loading" while audio is playing.
      c.videoPath = sameVideoFile ? previousVideoPath : rebuilt.videoPath;
      c.videoProgress = sameVideoFile ? previousVideoProgress : rebuilt.videoProgress;
      c.videoFailed = sameVideoFile ? previousVideoFailed : false;
      c.mediaDownloadActive = sameVideoFile
        ? previousDownloadActive : rebuilt.mediaDownloadActive;
      c.voiceWaveform = rebuilt.voiceWaveform;
      c.voiceListened = rebuilt.voiceListened;
      // 语音识别结果就是通过 updateMessageContent 回流的，必须跟着更新。
      c.speechState = rebuilt.speechState;
      c.speechText = rebuilt.speechText;
      c.audioTitle = rebuilt.audioTitle;
      c.audioPerformer = rebuilt.audioPerformer;
      c.stickerFileId = rebuilt.stickerFileId;
      c.stickerFormat = rebuilt.stickerFormat;
      c.isEmojiSticker = rebuilt.isEmojiSticker;
      c.stickerPath = sameStickerFile ? c.stickerPath : rebuilt.stickerPath;
      c.stickerProgress = sameStickerFile ? c.stickerProgress : rebuilt.stickerProgress;
      c.stickerFailed = sameStickerFile ? c.stickerFailed : rebuilt.stickerFailed;
      c.stickerDownloadActive = sameStickerFile
        ? c.stickerDownloadActive : rebuilt.stickerDownloadActive;
      c.customEmojiId = rebuilt.customEmojiId;
      c.contactPhone = rebuilt.contactPhone;
      c.contactFirstName = rebuilt.contactFirstName;
      c.contactLastName = rebuilt.contactLastName;
      c.contactVcard = rebuilt.contactVcard;
      c.contactUserId = rebuilt.contactUserId;
      c.contactAvatarPath = sameContactUser ? previousContactAvatarPath : rebuilt.contactAvatarPath;
      c.locationLatitude = rebuilt.locationLatitude;
      c.locationLongitude = rebuilt.locationLongitude;
      c.locationAccuracy = rebuilt.locationAccuracy;
      c.locationValid = rebuilt.locationValid;
      c.locationLivePeriod = rebuilt.locationLivePeriod;
      c.locationExpiresIn = rebuilt.locationExpiresIn;
      c.locationHeading = rebuilt.locationHeading;
      c.locationProximityRadius = rebuilt.locationProximityRadius;
      c.venueTitle = rebuilt.venueTitle;
      c.venueAddress = rebuilt.venueAddress;
      c.venueProvider = rebuilt.venueProvider;
      c.venueId = rebuilt.venueId;
      c.venueType = rebuilt.venueType;
      c.pollId = rebuilt.pollId;
      c.pollQuestion = rebuilt.pollQuestion;
      c.pollOptions = rebuilt.pollOptions;
      c.pollTotalVoterCount = rebuilt.pollTotalVoterCount;
      c.pollIsAnonymous = rebuilt.pollIsAnonymous;
      c.pollIsQuiz = rebuilt.pollIsQuiz;
      c.pollAllowMultiple = rebuilt.pollAllowMultiple;
      c.pollCorrectOptionId = rebuilt.pollCorrectOptionId;
      c.pollExplanation = rebuilt.pollExplanation;
      c.pollOpenPeriod = rebuilt.pollOpenPeriod;
      c.pollCloseDate = rebuilt.pollCloseDate;
      c.pollIsClosed = rebuilt.pollIsClosed;
      c.pollVotePending = rebuilt.pollOptions.some(
        (option: PollOptionInfo): boolean => option.isBeingChosen
      );
      c.pollVoteError = '';
      c.diceEmoji = rebuilt.diceEmoji;
      c.diceValue = rebuilt.diceValue;
      c.diceSuccessFrame = rebuilt.diceSuccessFrame;
      c.diceHasFinalState = rebuilt.diceHasFinalState;
      c.gameId = rebuilt.gameId;
      c.gameShortName = rebuilt.gameShortName;
      c.gameTitle = rebuilt.gameTitle;
      c.gameDescription = rebuilt.gameDescription;
      c.gameText = rebuilt.gameText;
      c.paidMediaLocked = rebuilt.paidMediaLocked;
      c.paidMediaStarCount = rebuilt.paidMediaStarCount;
      c.paidMediaCount = rebuilt.paidMediaCount;
      c.paidMediaKind = rebuilt.paidMediaKind;
      c.giftKind = rebuilt.giftKind;
      c.giftTitle = rebuilt.giftTitle;
      c.giftValue = rebuilt.giftValue;
      c.giftStatus = rebuilt.giftStatus;
      c.giftCode = rebuilt.giftCode;
      c.giftRefunded = rebuilt.giftRefunded;
      c.giveawayState = rebuilt.giveawayState;
      c.giveawayWinnerCount = rebuilt.giveawayWinnerCount;
      c.giveawayPrize = rebuilt.giveawayPrize;
      c.giveawayDescription = rebuilt.giveawayDescription;
      c.giveawaySelectionDate = rebuilt.giveawaySelectionDate;
      c.giveawayUnclaimedCount = rebuilt.giveawayUnclaimedCount;
      c.giveawayMessageId = rebuilt.giveawayMessageId;
      c.giveawayBoostedChatId = rebuilt.giveawayBoostedChatId;
      c.giveawayRefunded = rebuilt.giveawayRefunded;
      c.giveawayOnlyNewMembers = rebuilt.giveawayOnlyNewMembers;
    });
    this.requestPhotos();
    if (this.pinnedIds.includes(id)) {
      this.resolvePinned();
    }
  }

  // Poll result changes are delivered globally by poll id rather than by
  // chat/message id. Patch every loaded bubble carrying that poll and clear
  // any optimistic "submitting" state once the authoritative result arrives.
  private onPoll(u: TdObject): void {
    const poll = u['poll'] as TdObject | undefined;
    if (poll === undefined) {
      return;
    }
    const pollId = `${poll['id'] ?? ''}`;
    if (pollId === '') {
      return;
    }
    const content: TdObject = { '@type': 'messagePoll' };
    content['poll'] = poll;
    const fake: TdObject = { '@type': 'message' };
    fake['content'] = content;
    const rebuilt = buildMessageEntry(fake, this.users);
    let changed = false;
    this.messages = this.messages.map((message: MessageEntry): MessageEntry => {
      if (message.contentType !== 'poll' || message.pollId !== pollId) {
        return message;
      }
      changed = true;
      const next = cloneMessage(message);
      next.pollQuestion = rebuilt.pollQuestion;
      next.pollOptions = rebuilt.pollOptions;
      next.pollTotalVoterCount = rebuilt.pollTotalVoterCount;
      next.pollIsAnonymous = rebuilt.pollIsAnonymous;
      next.pollIsQuiz = rebuilt.pollIsQuiz;
      next.pollAllowMultiple = rebuilt.pollAllowMultiple;
      next.pollCorrectOptionId = rebuilt.pollCorrectOptionId;
      next.pollExplanation = rebuilt.pollExplanation;
      next.pollOpenPeriod = rebuilt.pollOpenPeriod;
      next.pollCloseDate = rebuilt.pollCloseDate;
      next.pollIsClosed = rebuilt.pollIsClosed;
      next.pollVotePending = rebuilt.pollOptions.some(
        (option: PollOptionInfo): boolean => option.isBeingChosen
      );
      next.pollVoteError = '';
      return next;
    });
    if (changed) {
      this.notifySoon();
    }
  }

  // 诊断：窗口里有没有"洞"。TDLib 的消息 id 每条递增 2^20，所以相邻两行的
  // 差值除以 2^20 就是它们之间隔了几条。正常相邻是 1；被删过的地方会留下永久
  // 空档，所以小差值不算异常，只报最大的那个。
  //
  // 用来区分两种现象：窗口真的缺了一大段（差值几十），还是分页方向的问题
  // （窗口连续、只是没往某个方向取）。
  private logWindowGap(tag: string): void {
    if (this.messages.length < 2) {
      return;
    }
    let worst: number = 0;
    let atIdx: number = -1;
    for (let i = 1; i < this.messages.length; i++) {
      const step: number = Math.round(
        (this.messages[i].id - this.messages[i - 1].id) / 1048576);
      if (step > worst) {
        worst = step;
        atIdx = i;
      }
    }
    if (worst > 3) {
      console.warn(`[StoreDiag] gap after=${tag} biggest=${worst} atIdx=${atIdx}` +
        ` rows=${this.messages.length}` +
        ` around=${this.messages[atIdx - 1].id}..${this.messages[atIdx].id}`);
    }
  }

  private onDelete(u: TdObject): void {
    if ((u['chat_id'] as number | undefined) !== this.chatId) {
      return;
    }
    // from_cache 不是删除，是 TDLib 把消息挪出了本地缓存——服务端还在，之后
    // 还能取回。当成真删除会把窗口挖空：应用在后台被冻结一段时间后，TDLib
    // 回收缓存并补发一批这样的通知，实测一次就把 31 条窗口打到只剩 1 条，
    // 随后的补链再从别的锚点往下取，中间那段就永久缺失了——现象是消息错乱、
    // 时间线出现跳跃（10:39 后面直接接 10:54）。
    //
    // is_permanent 为真时即便带着 from_cache 也是真删除，照常移除。
    // 同样的判断 CallsStore.onMessagesDeleted 早就有了，这里一直漏着。
    const permanent = (u['is_permanent'] as boolean | undefined) ?? false;
    const fromCache = (u['from_cache'] as boolean | undefined) ?? false;
    const incoming = (u['message_ids'] as number[] | undefined) ?? [];
    if (fromCache && !permanent) {
      // 诊断：确认"窗口被挖空"确实来自这一路。查完连同下面那条一起删。
      let hit: number = 0;
      for (const e of this.messages) {
        if (incoming.indexOf(e.id) >= 0) {
          hit++;
        }
      }
      console.warn(`[StoreDiag] delete from_cache ids=${incoming.length}` +
        ` inWindow=${hit} rows=${this.messages.length} ignored`);
      return;
    }
    const removeIds = incoming;
    if (removeIds.length > 0) {
      console.info(`[StoreDiag] delete real ids=${removeIds.length}` +
        ` permanent=${permanent} fromCache=${fromCache} rows=${this.messages.length}`);
    }
    const set = new Set<number>(removeIds);
    this.messages = this.messages.filter((e: MessageEntry) => !set.has(e.id));
    this.notifySoon();
    if (this.pinnedIds.some((id: number): boolean => set.has(id))) {
      this.removePinnedIds(set);
      this.resolvePinned();
    }
  }

  // updateMessageEdited carries both the edit timestamp and the fresh inline
  // keyboard. Keep both in the render model so text edits and bot keyboard
  // changes invalidate the same bubble row.
  private onEdited(u: TdObject): void {
    if ((u['chat_id'] as number | undefined) !== this.chatId) {
      return;
    }
    const id = u['message_id'] as number | undefined;
    if (id === undefined) {
      return;
    }
    const buttons = parseInlineKeyboard(u['reply_markup'] as TdObject | undefined);
    const editDate = (u['edit_date'] as number | undefined) ?? 0;
    this.patch(id, (c: MessageEntry) => {
      c.inlineButtons = buttons;
      c.editDate = editDate;
    });
  }

  private onInteractionInfo(u: TdObject): void {
    if ((u['chat_id'] as number | undefined) !== this.chatId) {
      return;
    }
    const id = u['message_id'] as number | undefined;
    if (id === undefined) {
      return;
    }
    const ii = u['interaction_info'] as TdObject | undefined;
    const cmt: CommentInfo = commentInfoFromInteraction(ii);
    const rx: ReactionInfo[] = reactionsFromInteraction(ii);
    this.patch(id, (c: MessageEntry) => {
      c.commentCount = cmt.count;
      c.commentReplierIds = cmt.replierIds;
      c.commentReplierAvatarPaths = [];
      c.reactions = rx;
    });
    // 反应是随更新推过来的，可能首次出现自定义 emoji：立刻解析位图，
    // 否则要等下一次 requestPhotos 才会补齐。
    if (rx.some((r: ReactionInfo): boolean => r.customEmojiId !== '')) {
      this.resolveCustomEmojis();
    }
    this.resolveCommentAvatars();
  }

  private onReadOutbox(u: TdObject): void {
    if ((u['chat_id'] as number | undefined) !== this.chatId) {
      return;
    }
    this.lastReadOutboxId = (u['last_read_outbox_message_id'] as number | undefined) ?? 0;
    this.notifySoon(); // notify() applies the read marking centrally
  }

  // Outgoing messages at or below the outbox-read boundary become 'read'.
  // Applied on every notify so history pages (already read long ago) get
  // marked too, not only live updateChatReadOutbox events.
  private applyReadOutbox(): void {
    if (this.lastReadOutboxId <= 0) {
      return;
    }
    let changed = false;
    const mapped = this.messages.map((e: MessageEntry) => {
      if (e.isOutgoing && e.sendState === 'sent' && e.id <= this.lastReadOutboxId) {
        const c = cloneMessage(e);
        c.sendState = 'read';
        publishSendState(c.rowId, c.sendState);
        changed = true;
        return c;
      }
      return e;
    });
    if (changed) {
      this.messages = mapped;
    }
  }

  // --- photos ---
  private setThumbnailFailed(fileId: number, failed: boolean): void {
    let changed = false;
    this.messages = this.messages.map((m: MessageEntry): MessageEntry => {
      if (m.photoFileId !== fileId || m.photoFailed === failed || m.photoPath !== '') {
        return m;
      }
      const c = cloneMessage(m);
      c.photoFailed = failed;
      if (failed) {
        c.photoProgress = 0;
      }
      changed = true;
      return c;
    });
    if (changed) {
      this.notifySoon();
    }
  }

  // 缩略图下载闸。requestPhotos() 会对整页每张图各发一次 downloadFile，
  // 图多的频道一进去就是几十个并发请求 —— 它们互相抢带宽，谁都不先完成，
  // 首屏那几张反而最晚出来，同时挤占 TDLib 的网络线程让列表发卡。
  // 这里排队：同时最多 THUMB_MAX_ACTIVE 个在途，其余按入队顺序等待。
  private thumbActive: number = 0;
  private thumbQueue: number[] = [];
  private thumbQueued: Set<number> = new Set();

  // Download an inline thumbnail with up to 2 automatic retries (backoff),
  // so a transient failure doesn't leave the bubble stuck at 0% forever.
  private downloadThumb(fileId: number): void {
    if (this.thumbQueued.has(fileId)) {
      return; // 已在队列或在途
    }
    this.thumbQueued.add(fileId);
    this.thumbQueue.push(fileId);
    this.pumpThumbs();
  }

  private pumpThumbs(): void {
    while (this.thumbActive < THUMB_MAX_ACTIVE && this.thumbQueue.length > 0) {
      const fileId = this.thumbQueue.shift() as number;
      this.thumbActive++;
      this.startThumbDownload(fileId);
    }
  }

  // 队列是先进先出，但滑动之后排在前面的都是已经划走的旧图。把当前可见
  // 范围内的排到队头 —— 否则用户盯着的位置要等前面几十张下完才轮到。
  private prioritiseVisibleThumbs(): void {
    if (this.thumbQueue.length < 2) {
      return;
    }
    const visible: number[] = [];
    const rest: number[] = [];
    for (const fileId of this.thumbQueue) {
      const messageId = this.fileToMsg.get(fileId) ?? 0;
      if (messageId !== 0 && this.inMediaWindow(messageId)) {
        visible.push(fileId);
      } else {
        rest.push(fileId);
      }
    }
    this.thumbQueue = visible.concat(rest);
  }

  private startThumbDownload(fileId: number): void {
    this.setThumbnailFailed(fileId, false);
    const attempt = (this.thumbAttempts.get(fileId) ?? 0) + 1;
    this.thumbAttempts.set(fileId, attempt);
    const req: TdRequest = { '@type': 'downloadFile' };
    req['file_id'] = fileId;
    req['priority'] = THUMBNAIL_PRIORITY;
    const settle = (): void => {
      this.thumbActive--;
      this.thumbQueued.delete(fileId);
      this.pumpThumbs();
    };
    this.client.send(req).then((f: TdObject) => {
      this.applyFile(f);
      settle();
    }).catch((err: TdError) => {
      console.error(`MessageStore photo ${fileId} (attempt ${attempt}): ${err.message}`);
      settle();
      if (attempt <= 2) {
        setTimeout(() => this.downloadThumb(fileId), 1000 * attempt);
      } else {
        this.setThumbnailFailed(fileId, true);
      }
    });
  }

  private patchLinkPreviewEntries(fileId: number, fn: (entry: MessageEntry) => void): void {
    let changed: boolean = false;
    this.messages = this.messages.map((message: MessageEntry): MessageEntry => {
      if (message.linkPhotoFileId !== fileId) {
        return message;
      }
      const next: MessageEntry = cloneMessage(message);
      fn(next);
      changed = true;
      return next;
    });
    if (changed) {
      this.notifySoon();
    }
  }

  private downloadLinkPreviewPhoto(fileId: number): void {
    this.patchLinkPreviewEntries(fileId, (entry: MessageEntry): void => {
      entry.linkPhotoFailed = false;
      entry.linkPhotoDownloadActive = true;
    });
    const attempt: number = (this.linkThumbAttempts.get(fileId) ?? 0) + 1;
    this.linkThumbAttempts.set(fileId, attempt);
    const req: TdRequest = { '@type': 'downloadFile' };
    req['file_id'] = fileId;
    req['priority'] = THUMBNAIL_PRIORITY;
    this.client.send(req).then((file: TdObject): void => {
      this.applyFile(file);
    }).catch((error: TdError): void => {
      console.error(`MessageStore link photo ${fileId} (attempt ${attempt}): ${error.message}`);
      if (attempt <= 2) {
        setTimeout((): void => { this.downloadLinkPreviewPhoto(fileId); }, 1000 * attempt);
      } else {
        this.linkFileToMsg.delete(fileId);
        this.patchLinkPreviewEntries(fileId, (entry: MessageEntry): void => {
          entry.linkPhotoProgress = 0;
          entry.linkPhotoFailed = true;
          entry.linkPhotoDownloadActive = false;
        });
      }
    });
  }

  retryLinkPreviewPhoto(messageId: number): void {
    const index: number = this.indexOf(messageId);
    if (index < 0) {
      return;
    }
    const entry: MessageEntry = this.messages[index];
    if (entry.linkPhotoFileId === 0 || entry.linkPhotoPath !== '') {
      return;
    }
    this.linkFileToMsg.delete(entry.linkPhotoFileId);
    this.linkThumbAttempts.delete(entry.linkPhotoFileId);
    this.linkThumbLastKick.delete(entry.linkPhotoFileId);
    this.linkFileToMsg.set(entry.linkPhotoFileId, messageId);
    this.downloadLinkPreviewPhoto(entry.linkPhotoFileId);
  }

  // Resolve every custom-emoji id once. A message made of one custom emoji
  // morphs into the existing animated sticker pipeline; custom emoji embedded
  // in mixed text use a static WEBP/thumbnail through ArkUI ImageSpan.
  private customEmojiRequested: Set<string> = new Set();
  private customEmojiFailed: Set<string> = new Set();

  private resolveCustomEmojis(): void {
    this.hydrateCustomEmojiPaths();
    for (const e of this.messages) {
      if (e.contentType === 'customEmoji' && e.customEmojiId !== '') {
        this.resolveCustomEmojiId(e.customEmojiId, e.id);
      }
      for (const id of e.inlineCustomEmojiIds) {
        this.resolveCustomEmojiId(id, e.id);
      }
      // 自定义 emoji 反应复用同一条解析/下载管线：拿到的静态位图正好是
      // 反应 chip 需要的尺寸，无需第二套缓存。
      for (const r of e.reactions) {
        if (r.customEmojiId !== '') {
          this.resolveCustomEmojiId(r.customEmojiId, e.id);
        }
      }
    }
  }

  // 已下载的位图路径同时回填到「文本内联自定义 emoji」和「自定义 emoji 反应」，
  // 一次遍历一次 notify，避免两条路径各自刷新列表。
  private hydrateCustomEmojiPaths(): void {
    let changed = false;
    this.messages = this.messages.map((m: MessageEntry): MessageEntry => {
      const inlinePaths: string[] | null = this.updatedInlineCustomEmojiPaths(m);
      const reactions: ReactionInfo[] | null = this.updatedReactionCustomEmojiPaths(m);
      if (inlinePaths === null && reactions === null) {
        return m;
      }
      const c = cloneMessage(m);
      if (inlinePaths !== null) {
        c.inlineCustomEmojiPaths = inlinePaths;
      }
      if (reactions !== null) {
        c.reactions = reactions;
      }
      changed = true;
      return c;
    });
    if (changed) {
      this.notifySoon();
    }
  }

  // 返回 null 表示无变化（调用方据此跳过克隆）。
  private updatedInlineCustomEmojiPaths(m: MessageEntry): string[] | null {
    if (m.inlineCustomEmojiIds.length === 0) {
      return null;
    }
    const paths: string[] = [];
    let differs = m.inlineCustomEmojiPaths.length !== m.inlineCustomEmojiIds.length;
    for (let i = 0; i < m.inlineCustomEmojiIds.length; i++) {
      const path = this.inlineCustomEmojiPathById.get(m.inlineCustomEmojiIds[i]) ?? '';
      paths.push(path);
      if (!differs && path !== m.inlineCustomEmojiPaths[i]) {
        differs = true;
      }
    }
    return differs ? paths : null;
  }

  private updatedReactionCustomEmojiPaths(m: MessageEntry): ReactionInfo[] | null {
    let differs = false;
    const next: ReactionInfo[] = m.reactions.map((r: ReactionInfo): ReactionInfo => {
      if (r.customEmojiId === '') {
        return r;
      }
      const path = this.inlineCustomEmojiPathById.get(r.customEmojiId) ?? '';
      if (path === r.customEmojiPath) {
        return r;
      }
      differs = true;
      return {
        emoji: r.emoji, count: r.count, isChosen: r.isChosen,
        customEmojiId: r.customEmojiId, customEmojiPath: path
      };
    });
    return differs ? next : null;
  }

  private applyInlineCustomEmojiPath(customEmojiId: string, path: string): void {
    if (customEmojiId === '' || path === '' ||
      this.inlineCustomEmojiPathById.get(customEmojiId) === path) {
      return;
    }
    this.inlineCustomEmojiPathById.set(customEmojiId, path);
    this.hydrateCustomEmojiPaths();
  }

  private markCustomEmojiResolveFailed(ceId: string): void {
    this.customEmojiRequested.delete(ceId);
    this.customEmojiFailed.add(ceId);
    let changed = false;
    this.messages = this.messages.map((m: MessageEntry): MessageEntry => {
      if (m.contentType !== 'customEmoji' || m.customEmojiId !== ceId || m.photoFailed) {
        return m;
      }
      const c = cloneMessage(m);
      c.photoFailed = true;
      changed = true;
      return c;
    });
    if (changed) {
      this.notifySoon();
    }
  }

  private completedPathOf(file: TdObject | undefined): string {
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

  private resolveCustomEmojiId(ceId: string, messageId: number, forceRetry: boolean = false): void {
    if (ceId === '' || this.customEmojiRequested.has(ceId) ||
      (!forceRetry && this.customEmojiFailed.has(ceId))) {
      return;
    }
    if (forceRetry) {
      this.customEmojiFailed.delete(ceId);
    }
    this.customEmojiRequested.add(ceId);
    console.info(`MessageStore: resolving custom emoji ${ceId} for msg ${messageId}`);
    const req: TdRequest = { '@type': 'getCustomEmojiStickers' };
    req['custom_emoji_ids'] = [ceId];
    this.client.send(req).then((res: TdObject) => {
      const stickers = (res['stickers'] as TdObject[] | undefined) ?? [];
      if (stickers.length === 0) {
        this.markCustomEmojiResolveFailed(ceId);
        return; // Unicode alternative remains visible with a retry affordance.
      }
      const st = stickers[0];
      const fmt = st['format'] as TdObject | undefined;
      const fmtName = fmt !== undefined ? ((fmt['@type'] as string | undefined) ?? '') : '';
      const format = fmtName === 'stickerFormatWebp' ? 'webp'
        : (fmtName === 'stickerFormatTgs' ? 'tgs'
          : (fmtName === 'stickerFormatWebm' ? 'webm' : ''));
      const file = st['sticker'] as TdObject | undefined;
      const srcId = file !== undefined ? ((file['id'] as number | undefined) ?? 0) : 0;
      const thumb = st['thumbnail'] as TdObject | undefined;
      const thumbFile = thumb !== undefined ? (thumb['file'] as TdObject | undefined) : undefined;
      const thumbId = thumbFile !== undefined ? ((thumbFile['id'] as number | undefined) ?? 0) : 0;
      if (format === '' || (srcId === 0 && thumbId === 0)) {
        this.markCustomEmojiResolveFailed(ceId);
        return;
      }
      const sourceLocalPath = this.completedPathOf(file);
      const thumbLocalPath = this.completedPathOf(thumbFile);
      if (sourceLocalPath !== '' && srcId !== 0) {
        this.completedFilePaths.set(srcId, sourceLocalPath);
        publishThumbPath(srcId, sourceLocalPath);
      }
      if (thumbLocalPath !== '' && thumbId !== 0) {
        this.completedFilePaths.set(thumbId, thumbLocalPath);
        publishThumbPath(thumbId, thumbLocalPath);
      }

      // Mixed text needs a raster source. Animated TGS/WEBM uses its thumbnail;
      // static WEBP can be inserted directly when no separate thumbnail exists.
      const inlineFileId = thumbId !== 0 ? thumbId : (format === 'webp' ? srcId : 0);
      if (inlineFileId !== 0) {
        this.inlineCustomEmojiFileToId.set(inlineFileId, ceId);
        const cachedPath = this.completedFilePaths.get(inlineFileId) ?? '';
        if (cachedPath !== '') {
          this.applyInlineCustomEmojiPath(ceId, cachedPath);
        } else {
          const download: TdRequest = { '@type': 'downloadFile' };
          download['file_id'] = inlineFileId;
          download['priority'] = THUMBNAIL_PRIORITY;
          this.client.send(download).then((f: TdObject) => this.applyFile(f)).catch((err: TdError) => {
            console.error(`MessageStore inline custom emoji ${inlineFileId}: ${err.message}`);
          });
        }
      }

      let changed = false;
      this.messages = this.messages.map((m: MessageEntry): MessageEntry => {
        if (m.contentType !== 'customEmoji' || m.customEmojiId !== ceId) {
          return m;
        }
        changed = true;
        const c = cloneMessage(m);
        c.contentType = 'sticker';
        c.stickerFormat = format;
        c.isEmojiSticker = true;
        c.photoWidth = 100;
        c.photoHeight = 100;
        c.photoFailed = false;
        c.stickerFailed = false;
        if (format === 'webp') {
          c.photoFileId = srcId;
          c.photoPath = sourceLocalPath !== '' ? sourceLocalPath
            : (this.completedFilePaths.get(srcId) ?? '');
          c.photoProgress = c.photoPath !== '' ? 100 : 0;
          c.stickerFileId = 0;
          c.stickerPath = '';
          c.stickerProgress = 0;
          c.stickerDownloadActive = false;
        } else {
          c.photoFileId = thumbId;
          c.photoPath = thumbLocalPath !== '' ? thumbLocalPath
            : (this.completedFilePaths.get(thumbId) ?? '');
          c.photoProgress = c.photoPath !== '' ? 100 : 0;
          c.stickerFileId = srcId;
          c.stickerPath = sourceLocalPath !== '' ? sourceLocalPath
            : (this.completedFilePaths.get(srcId) ?? '');
          c.stickerProgress = c.stickerPath !== '' ? 100 : 0;
          c.stickerDownloadActive = c.stickerPath === '' && srcId !== 0;
        }
        return c;
      });
      this.customEmojiFailed.delete(ceId);
      if (changed) {
        this.requestPhotos(); // kick thumbnail + animated source downloads
        this.notifySoon();
      }
    }).catch((err: TdError) => {
      console.error(`MessageStore.getCustomEmojiStickers(${ceId}) failed: ${err.message}`);
      this.markCustomEmojiResolveFailed(ceId);
    });
  }

  // Send one custom emoji as its own message (formattedText + custom-emoji
  // entity — the receiver renders the animated emoji).
  sendCustomEmoji(emoji: string, customEmojiId: string): void {
    const ent: TdObject = { '@type': 'textEntity' };
    ent['offset'] = 0;
    ent['length'] = emoji.length; // UTF-16 units — matches TDLib's convention
    const entType: TdObject = { '@type': 'textEntityTypeCustomEmoji' };
    entType['custom_emoji_id'] = customEmojiId;
    ent['type'] = entType;
    const ft: TdObject = { '@type': 'formattedText' };
    ft['text'] = emoji;
    ft['entities'] = [ent];
    const content: TdObject = { '@type': 'inputMessageText' };
    content['text'] = ft;
    this.sendContent(content, 'sendCustomEmoji');
  }

  // 媒体自动下载的可见窗口，由 ChatPage 的 onScrollIndex 推进（消息 id 区间）。
  // 0/0 表示"还没有视口信息"，此时只允许缩略图，不碰整段媒体 —— 进频道那一
  // 刻整页 30 条的动图/语音一起抢带宽，就是列表卡死的原因。
  private mediaWindowFrom: number = 0;
  private mediaWindowTo: number = 0;
  // 聊天开着时实时到达的消息 id。见 onNewMessage。
  private liveArrivals: Set<number> = new Set();
  // 用户显式点过下载的文件：不受可见窗口约束，滑走也继续。
  // 豁免可见窗口自动取消的文件。会被 releaseVideoPlayback 摘掉 —— 只加不删
  // 的话，点开看过一次的视频就永远取消不掉了。
  private userRequestedFiles: Set<number> = new Set();
  // 已进 TDLib 下载管理器（addFileToDownloads）的文件。用户明确要留下来的，
  // 本地不去取消它们。
  private managedFiles: Set<number> = new Set();

  private mediaContextFor(entry: MessageEntry): MediaContext {
    return {
      inWindow: this.inMediaWindow(entry.id),
      isPlaySlot: false, // 播放位竞选属二期，一期没有任何条目是播放位
      // decideMedia 不再按 viewerOpen 产出 'full'（见 MediaPolicy 注释），
      // 全屏查看器是否打开对这里的决策没有影响，固定填 false。
      viewerOpen: false,
      autoplayEnabled: powerFeatureEnabled(
        entry.isAnimation ? KEY_POWER_AUTOPLAY_GIF : KEY_POWER_AUTOPLAY_VIDEO),
      powerSaving: AppStorage.get<boolean>(KEY_POWER_ACTIVE) ?? false,
      networkMetered: false,
      reduceAnimations: reduceAnimations()
    };
  }

  setMediaWindow(fromId: number, toId: number): void {
    if (this.mediaWindowFrom === fromId && this.mediaWindowTo === toId) {
      return;
    }
    this.mediaWindowFrom = fromId;
    this.mediaWindowTo = toId;
    this.cancelMediaOutsideWindow();
    this.prioritiseVisibleThumbs();
    this.requestPhotos();
  }

  private inMediaWindow(id: number): boolean {
    // 实时到达的消息一律放行 —— 判据是"怎么来的"，不是"在不在视口"：
    // 翻历史整页涌入才需要窗口约束，新来的一条不该等滚动事件。
    if (this.liveArrivals.has(id)) {
      return true;
    }
    if (this.mediaWindowFrom === 0 && this.mediaWindowTo === 0) {
      return false; // 视口未知且非实时到达：不预取整段媒体
    }
    return id >= this.mediaWindowFrom && id <= this.mediaWindowTo;
  }

  // 划走即停。TDLib 的 downloadFile 是有状态的后台任务，不主动取消就会把
  // 整个可见区之外的视频也拉完 —— 用户看到的"下载不会停"。
  private cancelMediaOutsideWindow(): void {
    const stale: number[] = [];
    this.videoFileToMsg.forEach((messageId: number, fileId: number): void => {
      if (!this.inMediaWindow(messageId)) {
        stale.push(fileId);
      }
    });
    for (const fileId of stale) {
      const messageId = this.videoFileToMsg.get(fileId) ?? 0;
      const idx = this.indexOf(messageId);
      // 已下完的不动；用户手动点过的也不动。
      if (idx >= 0 && this.messages[idx].videoPath !== '') {
        continue;
      }
      if (this.userRequestedFiles.has(fileId) || this.liveArrivals.has(messageId)) {
        continue;
      }
      this.videoFileToMsg.delete(fileId);
      const req: TdRequest = { '@type': 'cancelDownloadFile' };
      req['file_id'] = fileId;
      req['only_if_pending'] = false;
      this.client.send(req).catch((): void => { /* 取消失败无副作用 */ });
      this.patchVideoEntries(fileId, (c: MessageEntry): void => {
        c.mediaDownloadActive = false;
        c.videoProgress = 0;
      });
    }
  }

  private requestPhotos(): void {
    this.resolveCustomEmojis();
    this.resolveContactAvatars();
    for (const e of this.messages) {
      if ((e.contentType === 'photo' || e.contentType === 'video' ||
        e.contentType === 'videoNote' ||
        e.contentType === 'sticker' || e.contentType === 'audio' ||
        e.contentType === 'game' || e.contentType === 'paidMedia' ||
        e.contentType === 'gift' || e.contentType === 'giveaway')
        && e.photoFileId !== 0 && e.photoPath === '') {
        if (!this.fileToMsg.has(e.photoFileId)) {
          this.fileToMsg.set(e.photoFileId, e.id);
          this.downloadThumb(e.photoFileId);
        } else {
          // Already requested but still no local file: a download that burned
          // its retries (transient network failure at load time) would sit at
          // 0% forever — re-kick it, rate-limited. downloadFile is idempotent.
          const now = Date.now();
          const lastKick = this.thumbLastKick.get(e.photoFileId) ?? 0;
          if (now - lastKick > THUMB_REKICK_MS) {
            this.thumbLastKick.set(e.photoFileId, now);
            this.downloadThumb(e.photoFileId);
          }
        }
      }
      // 整段媒体（语音 / videoNote / GIF / 显式整文件下载）统一交给
      // MediaPolicy 决策：缩略图已在上文入队（含去重与限速重试），高清图
      // 不再由这里消费——它会对窗口内每一张有 photoFullFileId 的照片都发起
      // 原图下载，查看器打开时只该给当前这一张升级，其余是浪费带宽（见
      // MediaPolicy.decideMedia 的注释）。全屏查看器自己对当前图与左右
      // 邻图调 requestFullPhoto 驱动高清下载。stream 留给二期的播放位
      // 控制器，一期不会产出。
      const intents: MediaIntent[] = decideMedia(subjectOfEntry(e), this.mediaContextFor(e));
      for (const intent of intents) {
        if (intent === 'explicit') {
          this.requestVideoDownload(e.id); // deduped via videoFileToMsg
        }
      }
      // Animated (TGS) sticker source file — small (<64KB), download eagerly so
      // the Lottie animation starts as soon as the message is visible.
      // 骰子（messageDice）的结果动画走同一管线。
      if ((e.contentType === 'sticker' || e.contentType === 'dice') &&
        e.stickerFileId !== 0 && e.stickerPath === '') {
        this.requestStickerSource(e.id);
      }
      // 🎰 老虎机 5 层 TGS：逐层下载，完成经 applyFile 回填 diceLayerPaths。
      if (e.contentType === 'dice' && e.diceLayerFileIds.length > 0) {
        for (let layerIndex = 0; layerIndex < e.diceLayerFileIds.length; layerIndex++) {
          const layerFileId: number = e.diceLayerFileIds[layerIndex];
          if (layerFileId === 0 || e.diceLayerPaths[layerIndex] !== '' ||
            this.diceLayerRequested.has(layerFileId)) {
            continue;
          }
          const cachedLayerPath: string = this.completedFilePaths.get(layerFileId) ?? '';
          if (cachedLayerPath !== '') {
            this.applyDiceLayerPath(layerFileId, cachedLayerPath);
            continue;
          }
          this.diceLayerRequested.add(layerFileId);
          const layerReq: TdRequest = { '@type': 'downloadFile' };
          layerReq['file_id'] = layerFileId;
          layerReq['priority'] = THUMBNAIL_PRIORITY;
          this.client.send(layerReq).then((f: TdObject) => this.applyFile(f))
            .catch((err: TdError): void => {
              this.diceLayerRequested.delete(layerFileId);
              console.error(`MessageStore dice layer ${layerFileId}: ${err.message}`);
            });
        }
      }
      if (e.linkPhotoFileId !== 0 && e.linkPhotoPath === '') {
        if (!this.linkFileToMsg.has(e.linkPhotoFileId)) {
          this.linkFileToMsg.set(e.linkPhotoFileId, e.id);
          this.linkThumbLastKick.set(e.linkPhotoFileId, Date.now());
          this.downloadLinkPreviewPhoto(e.linkPhotoFileId);
        } else if (!e.linkPhotoDownloadActive && !e.linkPhotoFailed) {
          const now: number = Date.now();
          const lastKick: number = this.linkThumbLastKick.get(e.linkPhotoFileId) ?? 0;
          if (now - lastKick > THUMB_REKICK_MS) {
            this.linkThumbLastKick.set(e.linkPhotoFileId, now);
            this.downloadLinkPreviewPhoto(e.linkPhotoFileId);
          }
        }
      }
    }
  }

  // On-demand full-resolution photo download (triggered by opening the fullscreen
  // viewer). The inline bubble only ever downloads photoFileId (a small size).
  requestFullPhoto(messageId: number, forceRetry: boolean = false,
    userInitiated: boolean = true): void {
    const idx = this.indexOf(messageId);
    if (idx < 0) {
      return;
    }
    const e = this.messages[idx];
    if (e.photoFullFileId === 0 || e.photoFullPath !== '') {
      return;
    }
    if (forceRetry) {
      this.fullPhotoFileToMsg.delete(e.photoFullFileId);
    } else if (this.fullPhotoFileToMsg.has(e.photoFullFileId)) {
      return;
    }
    this.patch(messageId, (c: MessageEntry): void => {
      c.photoFullFailed = false;
      c.photoFullProgress = 0;
    });
    this.fullPhotoFileToMsg.set(e.photoFullFileId, messageId);
    const req: TdRequest = { '@type': 'downloadFile' };
    req['file_id'] = e.photoFullFileId;
    req['priority'] = userInitiated ? MEDIA_USER_PRIORITY : MEDIA_PREFETCH_PRIORITY;
    this.client.send(req).then((f: TdObject) => this.applyFile(f)).catch((err: TdError) => {
      this.fullPhotoFileToMsg.delete(e.photoFullFileId);
      this.patch(messageId, (c: MessageEntry): void => {
        c.photoFullFailed = true;
        c.photoFullProgress = 0;
      });
      console.error(`MessageStore full photo ${e.photoFullFileId}: ${err.message}`);
    });
  }

  retryPhoto(messageId: number): void {
    const idx = this.indexOf(messageId);
    if (idx < 0) {
      return;
    }
    const e: MessageEntry = this.messages[idx];
    if (e.photoPath === '' && e.photoFileId !== 0) {
      this.fileToMsg.delete(e.photoFileId);
      this.thumbLastKick.delete(e.photoFileId);
      this.thumbAttempts.delete(e.photoFileId);
      this.patch(messageId, (c: MessageEntry): void => {
        c.photoFailed = false;
        c.photoProgress = 0;
      });
      this.fileToMsg.set(e.photoFileId, messageId);
      this.downloadThumb(e.photoFileId);
    }
    if (e.photoFullPath === '' && e.photoFullFileId !== 0) {
      this.requestFullPhoto(messageId, true);
    }
  }

  private patchStickerEntries(fileId: number, fn: (c: MessageEntry) => void): void {
    let changed = false;
    this.messages = this.messages.map((m: MessageEntry): MessageEntry => {
      if (m.stickerFileId !== fileId) {
        return m;
      }
      const c = cloneMessage(m);
      fn(c);
      changed = true;
      return c;
    });
    if (changed) {
      this.notifySoon();
    }
  }

  private requestStickerSource(messageId: number, forceRetry: boolean = false): void {
    const idx = this.indexOf(messageId);
    if (idx < 0) {
      return;
    }
    const entry = this.messages[idx];
    const fileId = entry.stickerFileId;
    if (fileId === 0 || entry.stickerPath !== '') {
      return;
    }
    const cachedPath = this.completedFilePaths.get(fileId) ?? '';
    if (cachedPath !== '') {
      this.patchStickerEntries(fileId, (c: MessageEntry): void => {
        c.stickerPath = cachedPath;
        c.stickerProgress = 100;
        c.stickerFailed = false;
        c.stickerDownloadActive = false;
      });
      return;
    }
    if (forceRetry) {
      this.stickerFileToMsg.delete(fileId);
      this.stickerLastKick.delete(fileId);
    } else if (entry.stickerFailed) {
      // 明确失败过的要用户主动点重试，不自动重发。
      return;
    } else if (this.stickerFileToMsg.has(fileId)) {
      // 已经请求过、本地文件却仍然没有。下载可能把重试次数烧光了（加载时的
      // 瞬时网络故障）——它既不完成也不报错，于是 stickerFileToMsg 里这一条
      // 永远清不掉，贴纸卡在 0%。用户看到的就是"贴纸加载不出来，退出会话
      // 再进去就好"：退出销毁了 store，连带清掉了这张表（issue #68）。
      //
      // 缩略图那条路一直有这个限速重发（requestPhotos 里的 thumbLastKick），
      // 贴纸这条漏了。同一档 8s，downloadFile 幂等，重发没有副作用。
      const now: number = Date.now();
      if (now - (this.stickerLastKick.get(fileId) ?? 0) <= THUMB_REKICK_MS) {
        return;
      }
    }
    this.stickerLastKick.set(fileId, Date.now());
    this.stickerFileToMsg.set(fileId, messageId);
    this.patchStickerEntries(fileId, (c: MessageEntry): void => {
      c.stickerFailed = false;
      c.stickerDownloadActive = true;
      if (forceRetry) {
        c.stickerProgress = 0;
      }
    });
    const req: TdRequest = { '@type': 'downloadFile' };
    req['file_id'] = fileId;
    req['priority'] = THUMBNAIL_PRIORITY;
    this.client.send(req).then((f: TdObject) => this.applyFile(f)).catch((err: TdError) => {
      this.stickerFileToMsg.delete(fileId);
      this.stickerLastKick.delete(fileId);
      this.patchStickerEntries(fileId, (c: MessageEntry): void => {
        c.stickerFailed = true;
        c.stickerProgress = 0;
        c.stickerDownloadActive = false;
      });
      console.error(`MessageStore sticker ${fileId}: ${err.message}`);
    });
  }

  retrySticker(messageId: number): void {
    const idx = this.indexOf(messageId);
    if (idx < 0) {
      return;
    }
    const entry = this.messages[idx];
    if (entry.contentType === 'customEmoji' && entry.customEmojiId !== '') {
      this.patch(messageId, (c: MessageEntry): void => {
        c.photoFailed = false;
        c.photoProgress = 0;
      });
      this.resolveCustomEmojiId(entry.customEmojiId, messageId, true);
      return;
    }
    if (entry.contentType !== 'sticker') {
      return;
    }
    if (entry.photoPath === '' && entry.photoFileId !== 0) {
      this.retryPhoto(messageId);
    }
    if (entry.stickerPath === '' && entry.stickerFileId !== 0) {
      this.requestStickerSource(messageId, true);
    }
  }

  // Full video/file download used by inline autoplay and explicit save/open.
  // Fullscreen playback can stream independently, while this path provides a
  // stable local file and progress state for the bubble/download manager.
  // register=true (user-initiated file/video downloads) goes through TDLib's
  // download manager (addFileToDownloads) so the search page's 下载 tab can
  // list it with live progress; auto-downloads (voice prefetch) stay silent.
  requestVideoDownload(messageId: number, register: boolean = false, forceRetry: boolean = false): void {
    this.startVideoDownload(messageId, register, register, forceRetry);
  }

  // 为"现在看"而下载。豁免可见窗口的自动取消（用户正盯着它），但**不**进
  // TDLib 的下载管理器：addFileToDownloads 是持久注册，按设计跨页面、跨应用
  // 重启继续跑，进去了就只能靠 removeFileFromDownloads 摘出来。用它来支撑
  // 播放，等于用户关掉播放器回到列表后视频还在偷偷下 —— 正是实测到的现象。
  requestVideoForPlayback(messageId: number, forceRetry: boolean = false): void {
    this.startVideoDownload(messageId, false, true, forceRetry);
  }

  // 播放结束（关播放器 / 划走）：解除豁免，没下完的就地取消。
  // 已经下完的不动（本地文件留着有用），进过下载管理器的也不动 —— 那是用户
  // 明确要留的东西，不该被"看完了"顺手取消掉。
  releaseVideoPlayback(messageId: number): void {
    const idx = this.indexOf(messageId);
    if (idx < 0) {
      return;
    }
    const e = this.messages[idx];
    const fileId = e.videoFileId;
    if (fileId === 0 || !this.userRequestedFiles.has(fileId)) {
      return;
    }
    this.userRequestedFiles.delete(fileId);
    if (e.videoPath !== '' || this.managedFiles.has(fileId)) {
      return;
    }
    this.videoFileToMsg.delete(fileId);
    const req: TdRequest = { '@type': 'cancelDownloadFile' };
    req['file_id'] = fileId;
    req['only_if_pending'] = false;
    this.client.send(req).catch((): void => { /* 取消失败无副作用 */ });
    this.patchVideoEntries(fileId, (c: MessageEntry): void => {
      c.mediaDownloadActive = false;
      c.videoProgress = 0;
    });
  }

  // manage：进 TDLib 的下载管理器（用户要"留下"这个文件）。
  // exempt：豁免可见窗口的自动取消（用户此刻正在用这个文件）。
  // 两者过去被同一个 register 布尔绑在一起，于是"点开看一眼"也拿到了永久的
  // 下载注册 + 永久的取消豁免。
  private startVideoDownload(
    messageId: number, manage: boolean, exempt: boolean, forceRetry: boolean
  ): void {
    const idx = this.indexOf(messageId);
    if (idx < 0) {
      return;
    }
    const e = this.messages[idx];
    const cachedPath = e.videoFileId !== 0 ? (this.completedFilePaths.get(e.videoFileId) ?? '') : '';
    if (e.videoPath === '' && cachedPath !== '') {
      this.patchVideoEntries(e.videoFileId, (c: MessageEntry): void => {
        c.videoPath = cachedPath;
        c.videoProgress = 100;
        c.videoFailed = false;
        c.mediaDownloadActive = false;
      });
      return;
    }
    if (forceRetry && e.videoFileId !== 0) {
      this.videoFileToMsg.delete(e.videoFileId);
    }
    if (e.videoFileId === 0 || e.videoPath !== '') {
      return;
    }
    // 已经在下了（自动预取，或另一处先触发了）。意图仍然要记下来：不记的话
    // 关播放器时 releaseVideoPlayback 找不到该取消谁，视频就一直下下去。
    // manage 是例外 —— 光记标记不等于真进了下载管理器，得把请求发出去。
    if (this.videoFileToMsg.has(e.videoFileId) && !manage) {
      if (exempt) {
        this.userRequestedFiles.add(e.videoFileId);
      }
      return;
    }
    this.videoFileToMsg.set(e.videoFileId, messageId);
    if (exempt) {
      this.userRequestedFiles.add(e.videoFileId);
    }
    if (manage) {
      this.managedFiles.add(e.videoFileId);
    }
    this.patchVideoEntries(e.videoFileId, (c: MessageEntry): void => {
      c.videoFailed = false;
      c.mediaDownloadActive = true;
      if (forceRetry) {
        c.videoProgress = 0;
      }
    });
    const req: TdRequest = { '@type': manage ? 'addFileToDownloads' : 'downloadFile' };
    req['file_id'] = e.videoFileId;
    req['priority'] = manage ? MEDIA_USER_PRIORITY : MEDIA_PREFETCH_PRIORITY;
    if (manage) {
      req['chat_id'] = this.chatId;
      req['message_id'] = messageId;
    }
    this.client.send(req).then((f: TdObject) => this.applyFile(f)).catch((err: TdError) => {
      this.videoFileToMsg.delete(e.videoFileId);
      this.patchVideoEntries(e.videoFileId, (c: MessageEntry): void => {
        c.videoFailed = true;
        c.videoProgress = 0;
        c.mediaDownloadActive = false;
      });
      console.error(`MessageStore video ${e.videoFileId}: ${err.message}`);
    });
  }

  private diceLayerRequested: Set<number> = new Set();

  // 🎰 某一层动画文件就绪：回填所有引用它的骰子消息的对应层路径。
  private applyDiceLayerPath(fileId: number, path: string): void {
    let changed = false;
    const next = this.messages.map((e: MessageEntry): MessageEntry => {
      const layerIndex: number = e.diceLayerFileIds.indexOf(fileId);
      if (e.contentType !== 'dice' || layerIndex < 0 ||
        e.diceLayerPaths[layerIndex] === path) {
        return e;
      }
      const c = cloneMessage(e);
      c.diceLayerPaths[layerIndex] = path;
      changed = true;
      return c;
    });
    if (changed) {
      this.messages = next;
      this.notifySoon();
    }
  }

  private onFile(u: TdObject): void {
    const f = u['file'] as TdObject | undefined;
    if (f !== undefined) {
      this.applyFile(f);
    }
  }

  private downloadPercent(file: TdObject, local: TdObject): number {
    const size = ((file['size'] as number | undefined) ?? 0) || ((file['expected_size'] as number | undefined) ?? 0);
    const downloaded = (local['downloaded_size'] as number | undefined) ?? 0;
    return size > 0 ? Math.min(100, Math.floor((downloaded / size) * 100)) : 0;
  }

  // 诊断：applyFile 是 updateFile 的落点，而每个活跃下载的每次进度变化都会
  // 来一条。它内部有四次全量 messages.some() 扫描外加一次 patch（又一遍
  // map + 克隆），窗口几百行时单条就不便宜。每秒汇总一次调用数和累计耗时，
  // 用来判断 sendMessage 的应答是不是排在这堆活后面。
  private fileDiagWindowStart: number = 0;
  private fileDiagCalls: number = 0;
  private fileDiagMs: number = 0;

  private applyFile(file: TdObject): void {
    const enteredAt: number = Date.now();
    if (this.fileDiagWindowStart === 0) {
      this.fileDiagWindowStart = enteredAt;
    } else if (enteredAt - this.fileDiagWindowStart >= 1000) {
      console.info(`[SendDiag] applyFile calls=${this.fileDiagCalls}` +
        ` totalMs=${this.fileDiagMs} rows=${this.messages.length}`);
      this.fileDiagWindowStart = enteredAt;
      this.fileDiagCalls = 0;
      this.fileDiagMs = 0;
    }
    this.fileDiagCalls++;
    this.applyFileInner(file);
    this.fileDiagMs += Date.now() - enteredAt;
  }

  private applyFileInner(file: TdObject): void {
    const id = file['id'] as number | undefined;
    if (id === undefined) {
      return;
    }
    const local = file['local'] as TdObject | undefined;
    if (local === undefined) {
      return;
    }
    const done = (local['is_downloading_completed'] as boolean | undefined) ?? false;
    const path = (local['path'] as string | undefined) ?? '';
    if (done && path !== '') {
      this.completedFilePaths.set(id, path);
      publishThumbPath(id, path);
      this.applyDiceLayerPath(id, path);
      const customEmojiId = this.inlineCustomEmojiFileToId.get(id);
      if (customEmojiId !== undefined) {
        this.applyInlineCustomEmojiPath(customEmojiId, path);
      }
      const contactUserId = this.avatarFileToContact.get(id);
      if (contactUserId !== undefined) {
        this.contactAvatarPaths.set(contactUserId, path);
        this.applyContactAvatarPath(contactUserId, path);
      }
    }

    // A sticker source id can belong to many messages. Keep source progress,
    // completion and paused state in sync for every matching bubble.
    if (this.messages.some((m: MessageEntry): boolean => m.stickerFileId === id)) {
      const percent = done && path !== '' ? 100 : this.downloadPercent(file, local);
      const active = !done &&
        ((local['is_downloading_active'] as boolean | undefined) ?? false);
      this.patchStickerEntries(id, (c: MessageEntry): void => {
        if (done && path !== '') {
          c.stickerPath = path;
          c.stickerFailed = false;
        }
        c.stickerProgress = percent;
        c.stickerDownloadActive = active;
      });
      if (done && path !== '') {
        this.stickerFileToMsg.delete(id);
        this.stickerLastKick.delete(id);
      }
      return;
    }

    // A Telegram preview thumbnail can be reused by several messages. Patch
    // every matching card rather than the first message that requested it.
    if (this.messages.some((m: MessageEntry): boolean => m.linkPhotoFileId === id)) {
      const percent: number = done && path !== '' ? 100 : this.downloadPercent(file, local);
      const active: boolean = !done &&
        ((local['is_downloading_active'] as boolean | undefined) ?? false);
      this.patchLinkPreviewEntries(id, (entry: MessageEntry): void => {
        if (done && path !== '') {
          entry.linkPhotoPath = path;
          entry.linkPhotoFailed = false;
        }
        entry.linkPhotoProgress = percent;
        entry.linkPhotoDownloadActive = active;
      });
      if (done && path !== '') {
        this.linkFileToMsg.delete(id);
        this.linkThumbAttempts.delete(id);
        this.linkThumbLastKick.delete(id);
      }
    }

    // Full-resolution photo / full video: progress while downloading, path on completion.
    const fullMsgId = this.fullPhotoFileToMsg.get(id);
    if (fullMsgId !== undefined) {
      const percent = this.downloadPercent(file, local);
      this.patch(fullMsgId, (c: MessageEntry) => {
        if (done && path !== '') {
          c.photoFullPath = path;
          c.photoFullFailed = false;
          // Backfill: if the inline thumbnail download failed/stalled, the
          // full-resolution image serves as the bubble thumbnail too.
          if (c.photoPath === '') {
            c.photoPath = path;
          }
        }
        c.photoFullProgress = percent;
      });
      return;
    }
    const videoTracked = this.videoFileToMsg.has(id);
    const hasVideoEntry = this.messages.some((m: MessageEntry): boolean => m.videoFileId === id);
    if (videoTracked || (done && path !== '' && hasVideoEntry)) {
      const percent = done && path !== '' ? 100 : this.downloadPercent(file, local);
      this.patchVideoEntries(id, (c: MessageEntry): void => {
        if (done && path !== '') {
          c.videoPath = path;
          c.videoFailed = false;
          c.mediaDownloadActive = false;
        } else {
          c.mediaDownloadActive = true;
        }
        c.videoProgress = percent;
      });
      if (done && path !== '') {
        this.videoFileToMsg.delete(id);
      }
      return;
    }
    // Inline thumbnail: progress while downloading, path on completion (drives
    // the in-bubble loading ring).
    if (this.messages.some((m: MessageEntry): boolean => m.photoFileId === id)) {
      const percent = this.downloadPercent(file, local);
      this.messages = this.messages.map((m: MessageEntry): MessageEntry => {
        if (m.photoFileId !== id) {
          return m;
        }
        const c = cloneMessage(m);
        if (done && path !== '') {
          c.photoPath = path;
          c.photoFailed = false;
        }
        c.photoProgress = percent;
        return c;
      });
      // 进度同时走旁路通道：它已经不在行 key 里了（见 collapseAlbums），
      // 等待中的进度环靠 LiveProgressRing 自订阅刷新。
      publishProgress(id, percent);
      if (done && path !== '') {
        this.thumbAttempts.delete(id);
        this.thumbLastKick.delete(id);
      }
      // The hottest path of all during a fling: every row entering the viewport
      // downloads its thumbnail. Coalesced, see notifySoon().
      this.notifySoon();
      return;
    }

    if (!done || path === '') {
      return;
    }
    // The chat photo drives the header avatar (may also be a message sender's avatar
    // when the channel posts as itself — fall through so both get updated).
    if (id === this.chatPhotoFileId && this.chatPhotoPath !== path) {
      this.chatPhotoPath = path;
      this.notifyHeaderAvatar();
    }
    const senderKey = this.avatarFileToSender.get(id);
    if (senderKey !== undefined) {
      this.senderAvatarPaths.set(senderKey, path);
      this.applySenderPath(senderKey, path);
      return;
    }
    const replierUid = this.avatarFileToReplier.get(id);
    if (replierUid !== undefined) {
      this.replierAvatarPaths.set(replierUid, path);
      this.applyReplierAvatar(replierUid, path);
      return;
    }
  }

  // Download the chat photo for the header avatar (independent of the chat lists,
  // so channels opened from a folder still get their header avatar).
  private downloadChatPhoto(): void {
    if (this.chatPhotoFileId <= 0) {
      return;
    }
    const req: TdRequest = { '@type': 'downloadFile' };
    req['file_id'] = this.chatPhotoFileId;
    req['priority'] = THUMBNAIL_PRIORITY;
    this.client.send(req).then((f: TdObject) => this.applyFile(f)).catch((err: TdError) => {
      console.error(`MessageStore chatPhoto ${this.chatPhotoFileId}: ${err.message}`);
    });
  }

  // --- sender avatars (group/channel per-message avatars) ---
  private senderKey(senderId: number, isUser: boolean): string {
    return `${isUser ? 'u' : 'c'}${senderId}`;
  }

  // Messages sent AS a chat (posting-as-channel / anonymous admins) carry a
  // messageSenderChat — their display name/avatar come from getChat, not the
  // user store (senderName() leaves them empty).
  private chatSenderNames: Map<number, string> = new Map();
  private chatSenderRequested: Set<number> = new Set();

  private resolveChatSenders(): void {
    for (const e of this.messages) {
      if (e.senderIsUser || e.senderId === 0 || e.senderId === this.chatId) {
        continue;
      }
      const cached = this.chatSenderNames.get(e.senderId);
      if (cached !== undefined && cached !== '') {
        this.applyChatSenderName(e.senderId, cached);
        continue;
      }
      if (this.chatSenderRequested.has(e.senderId)) {
        continue;
      }
      this.chatSenderRequested.add(e.senderId);
      const senderId = e.senderId;
      const req: TdRequest = { '@type': 'getChat' };
      req['chat_id'] = senderId;
      this.client.send(req).then((chat: TdObject) => {
        const title = (chat['title'] as string | undefined) ?? '';
        if (title !== '') {
          this.chatSenderNames.set(senderId, title);
          this.applyChatSenderName(senderId, title);
        }
        const photo = chat['photo'] as TdObject | undefined;
        const small = photo !== undefined ? (photo['small'] as TdObject | undefined) : undefined;
        const fileId = small !== undefined ? ((small['id'] as number | undefined) ?? 0) : 0;
        const key = this.senderKey(senderId, false);
        if (fileId > 0 && !this.senderRequested.has(key)) {
          this.senderRequested.add(key);
          this.avatarFileToSender.set(fileId, key);
          const dl: TdRequest = { '@type': 'downloadFile' };
          dl['file_id'] = fileId;
          dl['priority'] = THUMBNAIL_PRIORITY;
          this.client.send(dl).then((f: TdObject) => this.applyFile(f)).catch((err: TdError) => {
            console.error(`MessageStore chat-sender avatar ${fileId}: ${err.message}`);
          });
        }
      }).catch((err: TdError) => {
        console.error(`MessageStore.resolveChatSenders getChat(${senderId}) failed: ${err.message}`);
      });
    }
  }

  private applyChatSenderName(senderId: number, name: string): void {
    let changed = false;
    const next = this.messages.map((e: MessageEntry) => {
      if (!e.senderIsUser && e.senderId === senderId && e.senderName !== name) {
        changed = true;
        const c = cloneMessage(e);
        c.senderName = name;
        return c;
      }
      return e;
    });
    if (changed) {
      this.messages = next;
      this.notifySoon();
    }
  }

  private resolveSenderAvatars(): void {
    this.resolveChatSenders();
    const seen = new Set<string>();
    for (const e of this.messages) {
      if (e.isOutgoing || e.senderId === 0) {
        continue;
      }
      const key = this.senderKey(e.senderId, e.senderIsUser);
      if (seen.has(key)) {
        continue;
      }
      seen.add(key);
      const known = this.senderAvatarPaths.get(key);
      if (known !== undefined && known !== '') {
        this.applySenderPath(key, known);
        continue;
      }
      if (this.senderRequested.has(key)) {
        continue;
      }
      let fileId = 0;
      if (e.senderIsUser) {
        // Users TDLib was never pushed (a chat opened from global search) have
        // no photo id and no updateUser is coming unless we ask.
        this.users.ensure(e.senderId);
        this.backfillSenderName(e.senderId);
        fileId = this.users.photoFileId(e.senderId);
      } else if (e.senderId === this.chatId) {
        fileId = this.chatPhotoFileId;
      }
      if (fileId <= 0) {
        continue; // not known yet — retried on updateUser / getChat
      }
      this.senderRequested.add(key);
      this.avatarFileToSender.set(fileId, key);
      const req: TdRequest = { '@type': 'downloadFile' };
      req['file_id'] = fileId;
      req['priority'] = THUMBNAIL_PRIORITY;
      this.client.send(req).then((f: TdObject) => this.applyFile(f)).catch((err: TdError) => {
        console.error(`MessageStore avatar ${fileId}: ${err.message}`);
      });
    }
  }

  // Message entries snapshot the sender's name AND initials when built. For a
  // user the cache didn't know yet both were empty, and many senders in a chat
  // we aren't a member of never get a profile photo at all (privacy) — their
  // initials ARE the avatar, so both fields must be backfilled once the user
  // arrives (the LazyForEach key includes senderName, so the row re-renders).
  private backfillSenderName(userId: number): void {
    const name = this.users.displayName(userId);
    if (name === '') {
      return;
    }
    const initials = name.substring(0, 1).toUpperCase();
    // Single-pass bulk update with ONE notify. A per-message patch()+notify()
    // loop here made every subscriber rebuild the whole timeline once per
    // message right after an older page landed — the load-more jank.
    let changed = false;
    const next = this.messages.map((e: MessageEntry): MessageEntry => {
      if (!e.senderIsUser || e.senderId !== userId || e.senderName === name) {
        return e;
      }
      const c = cloneMessage(e);
      c.senderName = name;
      c.senderInitials = initials;
      changed = true;
      return c;
    });
    if (changed) {
      this.messages = next;
      this.notifySoon();
    }
  }

  private resolveSystemUserLabels(): void {
    let changed = false;
    const next = this.messages.map((entry: MessageEntry): MessageEntry => {
      const refreshed = refreshSystemUserLabel(entry, this.users);
      if (refreshed !== entry) {
        changed = true;
      }
      return refreshed;
    });
    if (changed) {
      this.messages = next;
      this.notifySoon();
    }
  }

  // Through the side channel, NOT by patching entries. Writing the path into
  // every entry changed every row's content key the moment a group's avatars
  // resolved — a full-page rebuild (`change × 31`) and a dropped frame ~0.7s
  // after every first entry. The bubbles' avatar views subscribe to the
  // channel and swap the image in place instead.
  private applySenderPath(key: string, path: string): void {
    publishSenderAvatar(key, path);
  }

  // --- shared-contact avatars ---
  private resolveContactAvatars(): void {
    for (const e of this.messages) {
      const userId = e.contactUserId;
      if (e.contentType !== 'contact' || userId <= 0) {
        continue;
      }
      const known = this.contactAvatarPaths.get(userId);
      if (known !== undefined && known !== '') {
        this.applyContactAvatarPath(userId, known);
        continue;
      }
      this.users.ensure(userId);
      const fileId = this.users.photoFileId(userId);
      if (fileId <= 0 || this.contactAvatarRequested.has(userId)) {
        continue;
      }
      const cachedPath = this.completedFilePaths.get(fileId) ?? '';
      if (cachedPath !== '') {
        this.contactAvatarPaths.set(userId, cachedPath);
        this.applyContactAvatarPath(userId, cachedPath);
        continue;
      }
      this.contactAvatarRequested.add(userId);
      this.avatarFileToContact.set(fileId, userId);
      const req: TdRequest = { '@type': 'downloadFile' };
      req['file_id'] = fileId;
      req['priority'] = THUMBNAIL_PRIORITY;
      this.client.send(req).then((f: TdObject) => this.applyFile(f)).catch((err: TdError) => {
        this.contactAvatarRequested.delete(userId);
        this.avatarFileToContact.delete(fileId);
        console.error(`MessageStore contact avatar ${fileId}: ${err.message}`);
      });
    }
  }

  private applyContactAvatarPath(userId: number, path: string): void {
    let changed = false;
    this.messages = this.messages.map((e: MessageEntry): MessageEntry => {
      if (e.contentType !== 'contact' || e.contactUserId !== userId ||
        e.contactAvatarPath === path) {
        return e;
      }
      const c = cloneMessage(e);
      c.contactAvatarPath = path;
      changed = true;
      return c;
    });
    if (changed) {
      this.notifySoon();
    }
  }

  // --- comment-row avatars (recent commenters shown on a channel post) ---
  private resolveCommentAvatars(): void {
    for (const e of this.messages) {
      for (const uid of e.commentReplierIds) {
        const known = this.replierAvatarPaths.get(uid);
        if (known !== undefined && known !== '') {
          this.applyReplierAvatar(uid, known);
          continue;
        }
        if (this.replierAvatarRequested.has(uid)) {
          continue;
        }
        const fileId = this.users.photoFileId(uid);
        if (fileId <= 0) {
          continue; // not known yet — retried on updateUser
        }
        this.replierAvatarRequested.add(uid);
        this.avatarFileToReplier.set(fileId, uid);
        const req: TdRequest = { '@type': 'downloadFile' };
        req['file_id'] = fileId;
        req['priority'] = THUMBNAIL_PRIORITY;
        this.client.send(req).then((f: TdObject) => this.applyFile(f)).catch((err: TdError) => {
          console.error(`MessageStore replier avatar ${fileId}: ${err.message}`);
        });
      }
    }
  }

  private applyReplierAvatar(userId: number, path: string): void {
    // 先发通道。评论者头像原来只写进 MessageEntry，而这个字段**不在行 key 里**
    // （key 精简后只留真正决定行内容的字段），LazyForEach 不会重建这一行，
    // 头像就永远到不了界面——用户看到的三个「?」正是这个。
    // 下面仍然写回 entry：新进场的行拿它当初值，省一次闪烁。
    publishSenderAvatar(senderChannelKey(userId, true), path);
    let changed = false;
    const next = this.messages.map((e: MessageEntry) => {
      const idx = e.commentReplierIds.indexOf(userId);
      if (idx < 0 || e.commentReplierAvatarPaths[idx] === path) {
        return e;
      }
      changed = true;
      const c = cloneMessage(e);
      const arr = c.commentReplierAvatarPaths.slice();
      while (arr.length <= idx) {
        arr.push('');
      }
      arr[idx] = path;
      c.commentReplierAvatarPaths = arr;
      return c;
    });
    if (changed) {
      this.messages = next;
      this.notifySoon();
    }
  }

  // --- subtitle ---
  // Newest pinned message → one-line preview shown in the banner under the header.
  private resolvePinned(): void {
    const seq: number = ++this.pinnedResolveSeq;
    if (this.threadRootId > 0) {
      this.pinnedIds = [];
      this.pinnedPreviews = [];
      this.pinnedLoadState = 'ready';
      this.setPinned('');
      return; // comment thread view — the discussion group's pins don't apply
    }
    this.pinnedLoadState = 'loading';
    this.notifyPinned();
    const filter: TdObject = { '@type': 'searchMessagesFilterPinned' };
    const req: TdRequest = { '@type': 'searchChatMessages' };
    // 话题模式：只取本话题内的置顶（全群作用域会把其它话题的置顶带进来，
    // 点击后在本话题历史中找不到目标）。
    if (this.forumTopicId > 0) {
      req['topic_id'] = this.topicIdObject();
    }
    req['chat_id'] = this.chatId;
    req['query'] = '';
    req['from_message_id'] = 0;
    req['offset'] = 0;
    req['limit'] = 100;
    req['filter'] = filter;
    this.client.send(req).then((res: TdObject) => {
      if (seq !== this.pinnedResolveSeq) {
        return;
      }
      const arr = (res['messages'] as TdObject[] | undefined) ?? [];
      const ids: number[] = [];
      const previews: string[] = [];
      for (const m of arr) {
        const id = m['id'] as number | undefined;
        if (id !== undefined) {
          ids.push(id);
          previews.push(formatPreview(m));
        }
      }
      this.pinnedIds = ids; // newest → oldest, as returned
      this.pinnedPreviews = previews;
      this.pinnedLoadState = 'ready';
      this.setPinned(previews.length > 0 ? previews[0] : '');
    }).catch((e: TdError) => {
      if (seq !== this.pinnedResolveSeq) {
        return;
      }
      // TDLib uses 404 for "there is no pinned message" in some chat types.
      // That is a valid empty result, not a request failure: clear any stale
      // preview and let ChatPage omit the optional top card entirely.
      if (e.code === 404) {
        this.pinnedIds = [];
        this.pinnedPreviews = [];
        this.pinnedLoadState = 'ready';
        this.setPinned('');
        return;
      }
      this.pinnedLoadState = 'error';
      this.notifyPinned();
      console.error(`MessageStore.resolvePinned failed: ${e.message}`);
    });
  }

  private onPinnedUpdate(u: TdObject): void {
    const messageId = (u['message_id'] as number | undefined) ?? 0;
    const isPinned = (u['is_pinned'] as boolean | undefined) ?? false;
    if (!isPinned && messageId > 0) {
      this.removePinnedIds(new Set<number>([messageId]));
    }
    this.resolvePinned();
  }

  private removePinnedIds(removeIds: Set<number>): void {
    if (!this.pinnedIds.some((id: number): boolean => removeIds.has(id))) {
      return;
    }
    const ids: number[] = [];
    const previews: string[] = [];
    for (let i = 0; i < this.pinnedIds.length; i++) {
      if (!removeIds.has(this.pinnedIds[i])) {
        ids.push(this.pinnedIds[i]);
        previews.push(i < this.pinnedPreviews.length ? this.pinnedPreviews[i] : '');
      }
    }
    this.pinnedIds = ids;
    this.pinnedPreviews = previews;
    this.setPinned(previews.length > 0 ? previews[0] : '');
  }

  // Pinned message ids, newest → oldest (for the banner tap-cycle).
  getPinnedIds(): number[] {
    return this.pinnedIds;
  }

  // Pinned message previews, aligned with getPinnedIds().
  getPinnedPreviews(): string[] {
    return this.pinnedPreviews;
  }

  // Load a page centered on a message (for jumping to a pinned/quoted message
  // that isn't in the currently loaded window). Notifies when it arrives.
  loadAround(messageId: number, onComplete?: (found: boolean) => void): void {
    // Jumping into the middle of history: newer messages beyond this window
    // may exist — enable downward prefetch to discover/load them.
    const hadMoreNewer: boolean = this.hasMoreNewer;
    this.hasMoreNewer = true;
    this.newerLoadState = 'idle';
    // 首屏（未读锚点定位）同样取小窗：见 loadHistory 里的注释。之后的滚动
    // 分页（loadOlder/loadNewer）把两侧补齐。会话中途的跳转维持整页。
    const initial: boolean = this.initialHistoryState === 'loading';
    const req = this.historyRequest(messageId, initial ? -7 : -15);
    req['limit'] = initial ? 14 : 30;
    const wanted: number = initial ? 14 : 30;
    this.client.send(req).then((res: TdObject): void => {
      const got: number = ((res['messages'] as TdObject[] | undefined) ?? []).length;
      this.onHistory(res, 'around');
      // 短页补链：和 loadHistory('latest') 那边同样的处理，之前只有 latest 有。
      //
      // TDLib 只给本地库里已有的，不够时返回更少并在后台向服务端补，契约是
      // 「再问一次」，短页**不代表**到头了。首屏取小窗是为了首帧流畅（见上），
      // 但未读锚点打开的会话如果只回来十来条，用户看到的就是一屏就没了、还得
      // 自己往上滚才长出来——999+ 未读的群实测就是这样。
      //
      // 只在首屏补：会话中途的跳转本来就是整页，且用户已有明确的目标位置。
      if (initial && got > 0 && got < wanted) {
        this.initialFillTries = INITIAL_FILL_TRIES;
        this.loadOlder();
      }
      if (onComplete !== undefined) {
        onComplete(this.indexOf(messageId) >= 0);
      }
    }).catch((e: TdError) => {
      this.hasMoreNewer = hadMoreNewer;
      console.error(`MessageStore.loadAround failed: ${e.message}`);
      if (this.initialHistoryState === 'loading') {
        if ((e as TdError).code === 404) {
          // A stale unread/search anchor should not turn a healthy chat into
          // an empty/error page. Fall back to its live tail.
          this.loadHistory(0);
        } else {
          this.initialHistoryState = 'error';
          this.initialHistoryError = this.historyErrorHint(e);
          this.notify('initialState');
        }
      }
      if (onComplete !== undefined) {
        onComplete(false);
      }
    });
  }

  private setPinned(s: string): void {
    this.pinnedPreview = s;
    this.notifyPinned();
  }

  private historyErrorHint(error: TdError): string {
    if (error.code === -1 || error.message.toLowerCase().indexOf('timeout') >= 0) {
      return str('ms_timeout');
    }
    if (error.code === 401) {
      return str('ms_session_expired');
    }
    return str('ms_sync_failed');
  }

  private notifyPinned(): void {
    for (const l of this.pinnedSubs) {
      l(this.pinnedPreview);
    }
  }

  private resolveChat(): void {
    const req: TdRequest = { '@type': 'getChat' };
    req['chat_id'] = this.chatId;
    this.client.send(req).then((chat: TdObject) => this.onChat(chat)).catch((e: TdError) => {
      console.error(`MessageStore.getChat failed: ${e.message}`);
      this.startInitialLoad();
      this.flushInitial();
    });
  }

  private onChat(chat: TdObject): void {
    // Thread views exclude it: chat.last_message need not belong to the thread.
    if (this.threadRootId === 0) {
      this.pendingLastMessage = (chat['last_message'] as TdObject | undefined) ?? null;
    }
    // Capture the unread boundary BEFORE loading history / marking read, so the
    // page can position at the first unread message even after we mark it read.
    this.lastReadInboxId = (chat['last_read_inbox_message_id'] as number | undefined) ?? 0;
    this.lastReadOutboxId = (chat['last_read_outbox_message_id'] as number | undefined) ?? 0;
    this.unreadCount = (chat['unread_count'] as number | undefined) ?? 0;
    // Phantom-unread recovery (see ChatStore.effectiveUnread): a stuck counter
    // whose watermark already covers the newest message must not anchor the
    // page at a "first unread" that does not exist.
    const lastMsg = chat['last_message'] as TdObject | undefined;
    const lastMsgId = lastMsg !== undefined ? ((lastMsg['id'] as number | undefined) ?? 0) : 0;
    if (this.unreadCount > 0 && lastMsgId > 0 && this.lastReadInboxId >= lastMsgId) {
      this.unreadCount = 0;
    }
    this.injectSoleUnreadJoinService(lastMsg);
    const photo = chat['photo'] as TdObject | undefined;
    const small = photo !== undefined ? (photo['small'] as TdObject | undefined) : undefined;
    this.chatPhotoFileId = small !== undefined ? ((small['id'] as number | undefined) ?? 0) : 0;
    this.downloadChatPhoto();
    this.chatTitle = (chat['title'] as string | undefined) ?? '';
    this.notifyHeaderTitle();
    // Active bot reply keyboard for this chat (0 = none). updateChatReplyMarkup
    // keeps it current from here on.
    this.replyMarkupMessageId = (chat['reply_markup_message_id'] as number | undefined) ?? 0;
    this.resolveReplyKeyboard();
    const type = chat['type'] as TdObject | undefined;
    if (type !== undefined) {
      const t = type['@type'] as string | undefined;
      if (t === 'chatTypePrivate') {
        this.peerUserId = (type['user_id'] as number | undefined) ?? 0;
        this.fetchUserStatus();
      } else if (t === 'chatTypeBasicGroup') {
        this.groupId = (type['basic_group_id'] as number | undefined) ?? 0;
        this.isGroupFlag = true;
        this.resolveBasicGroup(this.groupId);
      } else if (t === 'chatTypeSupergroup') {
        this.groupId = (type['supergroup_id'] as number | undefined) ?? 0;
        this.isGroupFlag = true;
        this.resolveSupergroup(this.groupId);
      }
    }
    this.resolveSenderAvatars();
    this.startInitialLoad();
    this.flushInitial();
  }

  private startInitialLoad(): void {
    if (this.initialLoadStarted) {
      return;
    }
    this.initialLoadStarted = true;
    this.requestInitialPage();
  }

  private requestInitialPage(): void {
    if (this.requestedAroundMessageId > 0) {
      this.loadAround(this.requestedAroundMessageId);
      return;
    }
    // getFirstUnreadId() only scans the loaded window, so with a large unread
    // count the newest-30 page (loadHistory(0)) never actually contains the
    // true first-unread message — it silently returns the oldest of that page
    // instead, landing (and read-marking) far past the real boundary. Center
    // on lastReadInboxId to guarantee the boundary is in the loaded window —
    // but ONLY when there's actually something unread: last_read_inbox_message_id
    // only tracks incoming messages, so a fully-read chat whose newest messages
    // are outgoing (sent by us) can have it sitting well behind the true tail —
    // loadAround there would miss the real end of the chat. Fully-read chats
    // always just load the newest page instead.
    if (this.unreadCount > 0 && this.lastReadInboxId > 0) {
      this.loadAround(this.lastReadInboxId);
      return;
    }
    this.loadHistory(0);
  }

  private fetchUserStatus(): void {
    if (this.peerUserId === 0) {
      return;
    }
    const req: TdRequest = { '@type': 'getUser' };
    req['user_id'] = this.peerUserId;
    this.client.send(req).then((user: TdObject) => {
      this.applyPeerUserStatus(user['status'] as TdObject | undefined);
    }).catch((e: TdError) => {
      console.error(`MessageStore.getUser failed: ${e.message}`);
    });
  }

  private onUserStatus(u: TdObject): void {
    if ((u['user_id'] as number | undefined) !== this.peerUserId || this.peerUserId === 0) {
      return;
    }
    this.applyPeerUserStatus(u['status'] as TdObject | undefined);
  }

  private applyPeerUserStatus(status: TdObject | undefined): void {
    this.peerUserStatus = status;
    this.setSubtitle(formatUserStatus(status, Math.floor(Date.now() / 1000)));
    const type = status !== undefined ? ((status['@type'] as string | undefined) ?? '') : '';
    if (type !== 'userStatusOffline') {
      if (this.statusRefreshTimer !== -1) {
        clearInterval(this.statusRefreshTimer);
        this.statusRefreshTimer = -1;
      }
      return;
    }
    if (this.statusRefreshTimer !== -1) {
      return;
    }
    this.statusRefreshTimer = setInterval((): void => {
      const next = formatUserStatus(this.peerUserStatus, Math.floor(Date.now() / 1000));
      if (next !== this.subtitle) {
        this.setSubtitle(next);
      }
    }, 30 * 1000);
  }

  private onGroup(u: TdObject): void {
    const g = (u['basic_group'] as TdObject | undefined) ?? (u['supergroup'] as TdObject | undefined);
    if (g === undefined) {
      return;
    }
    if ((g['id'] as number | undefined) !== this.groupId || this.groupId === 0) {
      return;
    }
    const isCh = (g['is_channel'] as boolean | undefined);
    if (isCh !== undefined) {
      this.isChannel = isCh;
    }
    const count = (g['member_count'] as number | undefined) ?? 0;
    if (count > 0) {
      this.setMemberSubtitle(count);
    }
  }

  // Subscriber/member count subtitle, K-abbreviated like Telegram
  // ("33.1K 位订阅者" / "128 位成员, 12 人在线").
  private setMemberSubtitle(count: number): void {
    this.memberCount = count;
    this.composeMemberSubtitle();
  }

  private composeMemberSubtitle(): void {
    if (this.memberCount <= 0) {
      return;
    }
    let s = str('subtitle_member_count', formatMemberCount(this.memberCount), this.isChannel ? str('subscribers_word') : str('members_word'));
    // Channels don't surface member presence — online counts are a group thing.
    if (!this.isChannel && this.onlineCount > 0) {
      s += str('subtitle_online_suffix', this.onlineCount);
    }
    this.setSubtitle(s);
  }

  private onOnlineCount(u: TdObject): void {
    if ((u['chat_id'] as number | undefined) !== this.chatId) {
      return;
    }
    this.onlineCount = (u['online_member_count'] as number | undefined) ?? 0;
    this.composeMemberSubtitle();
  }

  // Supergroup/channel: the pushed supergroup object often carries member_count 0,
  // so fetch the authoritative count from getSupergroupFullInfo (and is_channel
  // from getSupergroup) rather than waiting for an updateSupergroup that may not come.
  private resolveSupergroup(id: number): void {
    if (id === 0) {
      return;
    }
    const sg: TdRequest = { '@type': 'getSupergroup' };
    sg['supergroup_id'] = id;
    this.client.send(sg).then((s: TdObject) => {
      this.isChannel = (s['is_channel'] as boolean | undefined) ?? this.isChannel;
      const c = (s['member_count'] as number | undefined) ?? 0;
      if (c > 0) {
        this.setMemberSubtitle(c);
      }
    }).catch((e: TdError) => {
      console.error(`MessageStore.getSupergroup failed: ${e.message}`);
    });
    const full: TdRequest = { '@type': 'getSupergroupFullInfo' };
    full['supergroup_id'] = id;
    this.client.send(full).then((f: TdObject) => {
      const c = (f['member_count'] as number | undefined) ?? 0;
      if (c > 0) {
        this.setMemberSubtitle(c);
      }
    }).catch((e: TdError) => {
      console.error(`MessageStore.getSupergroupFullInfo failed: ${e.message}`);
    });
  }

  private resolveBasicGroup(id: number): void {
    if (id === 0) {
      return;
    }
    this.isChannel = false;
    const req: TdRequest = { '@type': 'getBasicGroup' };
    req['basic_group_id'] = id;
    this.client.send(req).then((bg: TdObject) => {
      const c = (bg['member_count'] as number | undefined) ?? 0;
      if (c > 0) {
        this.setMemberSubtitle(c);
      }
    }).catch((e: TdError) => {
      console.error(`MessageStore.getBasicGroup failed: ${e.message}`);
    });
  }

  private setSubtitle(s: string): void {
    this.subtitle = s;
    for (const l of this.subSubs) {
      l(this.subtitle);
    }
  }

  // --- read marking (driven by the visible range) ---
  // Mark messages read up to maxVisibleId. Because TDLib read state is a
  // high-water mark, we only ever send the highest id the user has actually
  // seen — so entering a chat without scrolling leaves the rest unread.
  markViewed(maxVisibleId: number): void {
    if (maxVisibleId <= this.viewedUpTo) {
      return;
    }
    this.viewedUpTo = maxVisibleId;
    this.clearManualUnreadFlag();
    const req: TdRequest = { '@type': 'viewMessages' };
    req['chat_id'] = this.chatId;
    req['message_ids'] = [maxVisibleId];
    req['force_read'] = true;
    this.client.send(req).catch((e: TdError) => {
      console.error(`MessageStore.viewMessages failed: ${e.message}`);
    });
  }

  // Submit or change a poll answer. The request is guarded per message so a
  // double tap can't race two different selections. TDLib's updatePoll is the
  // authoritative result; the small optimistic patch only bridges request →
  // update latency and is rolled back to the prior options on failure.
  votePoll(messageId: number, optionIds: number[],
    onFinished: (ok: boolean, error: string) => void): void {
    const idx = this.indexOf(messageId);
    if (idx < 0) {
      onFinished(false, str('ms_poll_message_gone'));
      return;
    }
    const entry = this.messages[idx];
    const expired = entry.pollCloseDate > 0 &&
      Math.floor(Date.now() / 1000) >= entry.pollCloseDate;
    if (entry.contentType !== 'poll' || entry.pollQuestion.trim() === '' ||
      entry.pollOptions.length < 2) {
      onFinished(false, str('poll_unavailable'));
      return;
    }
    if (entry.pollVotePending) {
      return;
    }
    if (entry.pollIsClosed || expired) {
      onFinished(false, str('ms_poll_closed'));
      return;
    }
    if (entry.pollIsQuiz &&
      entry.pollOptions.some((option): boolean => option.isChosen)) {
      onFinished(false, str('ms_quiz_once'));
      return;
    }
    const unique: number[] = [];
    for (const optionId of optionIds) {
      if (optionId >= 0 && optionId < entry.pollOptions.length &&
        unique.indexOf(optionId) < 0) {
        unique.push(optionId);
      }
    }
    if (!entry.pollAllowMultiple && unique.length > 1) {
      onFinished(false, str('ms_single_choice'));
      return;
    }
    const previousOptions: PollOptionInfo[] =
      entry.pollOptions.map((option: PollOptionInfo): PollOptionInfo => ({
      text: option.text,
      voterCount: option.voterCount,
      votePercentage: option.votePercentage,
      isChosen: option.isChosen,
      isBeingChosen: option.isBeingChosen
    }));
    this.patch(messageId, (message: MessageEntry): void => {
      message.pollVotePending = true;
      message.pollVoteError = '';
      message.pollOptions = message.pollOptions.map((
        option: PollOptionInfo,
        optionId: number
      ): PollOptionInfo => ({
        text: option.text,
        voterCount: option.voterCount,
        votePercentage: option.votePercentage,
        isChosen: option.isChosen,
        isBeingChosen: unique.indexOf(optionId) >= 0
      }));
    });
    const req: TdRequest = { '@type': 'setPollAnswer' };
    req['chat_id'] = this.chatId;
    req['message_id'] = messageId;
    req['option_ids'] = unique;
    this.client.send(req).then((): void => {
      this.patch(messageId, (message: MessageEntry): void => {
        message.pollVotePending = false;
        message.pollVoteError = '';
        message.pollOptions = message.pollOptions.map((
          option: PollOptionInfo,
          optionId: number
        ): PollOptionInfo => ({
          text: option.text,
          voterCount: option.voterCount,
          votePercentage: option.votePercentage,
          isChosen: unique.indexOf(optionId) >= 0,
          isBeingChosen: false
        }));
      });
      onFinished(true, '');
    }).catch((error: TdError): void => {
      const message = pollVoteErrorText(error.message);
      this.patch(messageId, (current: MessageEntry): void => {
        current.pollVotePending = false;
        current.pollVoteError = message;
        current.pollOptions = previousOptions;
        if (message === str('ms_poll_closed')) { current.pollIsClosed = true; }
      });
      onFinished(false, message);
      console.error(`MessageStore.setPollAnswer failed: ${error.message}`);
    });
  }

  // Voice notes have a separate listened bit from the chat's ordinary read
  // high-water mark. Open the content only after playback has actually begun,
  // then optimistically remove the unread dot while TDLib propagates the
  // refreshed message content.
  markVoiceListened(messageId: number): void {
    const idx: number = this.indexOf(messageId);
    if (idx < 0) {
      return;
    }
    const entry: MessageEntry = this.messages[idx];
    if (entry.contentType !== 'voice' || entry.isOutgoing || entry.voiceListened ||
      this.voiceListenPending.has(messageId)) {
      return;
    }
    this.voiceListenPending.add(messageId);
    this.patch(messageId, (c: MessageEntry): void => {
      c.voiceListened = true;
    });
    const req: TdRequest = { '@type': 'openMessageContent' };
    req['chat_id'] = this.chatId;
    req['message_id'] = messageId;
    this.client.send(req).then((): void => {
      this.voiceListenPending.delete(messageId);
    }).catch((e: TdError): void => {
      this.voiceListenPending.delete(messageId);
      this.patch(messageId, (c: MessageEntry): void => {
        if (c.contentType === 'voice' && !c.isOutgoing) {
          c.voiceListened = false;
        }
      });
      console.error(`MessageStore.openMessageContent failed: ${e.message}`);
    });
  }

  // Forwards from a channel/chat only carry the origin chat id (forwardChatId);
  // resolve it to a display title via getChat, then patch matching messages.
  private resolveForwardTitles(): void {
    for (const e of this.messages) {
      if (e.forwardChatId === 0 || e.forwardFrom !== '') {
        continue;
      }
      const cached = this.forwardTitleCache.get(e.forwardChatId);
      if (cached !== undefined) {
        this.patch(e.id, (c: MessageEntry) => { c.forwardFrom = cached; c.forwardChatId = 0; });
        continue;
      }
      if (this.forwardTitleRequested.has(e.forwardChatId)) {
        continue;
      }
      this.forwardTitleRequested.add(e.forwardChatId);
      const id = e.forwardChatId;
      const req: TdRequest = { '@type': 'getChat' };
      req['chat_id'] = id;
      this.client.send(req).then((chat: TdObject) => {
        const title = (chat['title'] as string | undefined) ?? '';
        this.forwardTitleCache.set(id, title);
        this.resolveForwardTitles();
      }).catch((err: TdError) => {
        console.error(`MessageStore forward title ${id}: ${err.message}`);
      });
    }
  }

  private resolveReplies(): void {
    const missing: number[] = [];
    this.messages = this.messages.map((e: MessageEntry) => {
      if (e.replyToMessageId === 0 || e.replyText !== '') {
        return e;
      }
      const target = this.messages.find((x: MessageEntry) => x.id === e.replyToMessageId);
      if (target === undefined) {
        // 之前拉过的先用缓存补上。loadAround 会整体替换窗口、条目重建，
        // replyText 又变空——而 repliedFetched 记着"已经拉过"，于是请求被挡、
        // 引用块永远空着（点引用跳过去再划回来就必现）。缓存让重建后的条目
        // 不用重新请求就能恢复。
        const cached = this.repliedPreview.get(e.replyToMessageId);
        if (cached !== undefined) {
          const restored = cloneMessage(e);
          restored.replySenderName = cached.senderName;
          restored.replyText = cached.text;
          return restored;
        }
        // 原消息不在已加载窗口里 —— 拉一次，否则引用块永远是空的。
        if (missing.indexOf(e.replyToMessageId) < 0) {
          missing.push(e.replyToMessageId);
        }
        return e;
      }
      const c = cloneMessage(e);
      c.replySenderName = target.senderName;
      c.replyText = target.contentType === 'text' ? target.text : (target.placeholderLabel !== '' ? target.placeholderLabel : str('ms_photo_bracket'));
      return c;
    });
    for (const id of missing) {
      this.fetchRepliedMessage(id);
    }
  }

  // 按需拉取被回复的原消息。只拉一次：请求过的记在 repliedFetched 里，
  // 失败（原消息已删除等）同样不再重试，否则每次 notify 都会再发一轮。
  private fetchRepliedMessage(messageId: number): void {
    if (this.repliedFetched.indexOf(messageId) >= 0) {
      return;
    }
    this.repliedFetched.push(messageId);
    const req: TdRequest = { '@type': 'getMessage' };
    req['chat_id'] = this.chatId;
    req['message_id'] = messageId;
    this.client.send(req).then((res: TdObject): void => {
      const entry = buildMessageEntry(res, this.users);
      const preview: string = entry.contentType === 'text'
        ? entry.text
        : (entry.placeholderLabel !== '' ? entry.placeholderLabel : str('ms_photo_bracket'));
      if (preview === '' && entry.senderName === '') {
        this.markReplyUnavailable(messageId);
        return;
      }
      // Remember it: the window can be replaced (loadAround) any number of
      // times, and the fetch guard would refuse to ask again.
      this.repliedPreview.set(messageId, { senderName: entry.senderName, text: preview });
      this.messages = this.messages.map((e: MessageEntry): MessageEntry => {
        if (e.replyToMessageId !== messageId || e.replyText !== '') {
          return e;
        }
        const c = cloneMessage(e);
        c.replySenderName = entry.senderName;
        c.replyText = preview;
        return c;
      });
      this.notifySoon();
    }).catch((e: TdError): void => {
      console.error(`MessageStore.getMessage(reply ${messageId}) failed: ${e.message}`);
      this.markReplyUnavailable(messageId);
    });
  }

  // 拉不到原消息（已删除、无权限）时也得落一个结果。气泡现在只要
  // replyToMessageId 非 0 就画引用块——不落结果的话那块会永远空着。
  private markReplyUnavailable(messageId: number): void {
    const label: string = str('mb_reply_unavailable');
    this.repliedPreview.set(messageId, { senderName: '', text: label });
    this.messages = this.messages.map((e: MessageEntry): MessageEntry => {
      if (e.replyToMessageId !== messageId || e.replyText !== '') {
        return e;
      }
      const c = cloneMessage(e);
      c.replyText = label;
      return c;
    });
    this.notifySoon();
  }

  private indexOf(id: number): number {
    for (let i = 0; i < this.messages.length; i++) {
      if (this.messages[i].id === id) {
        return i;
      }
    }
    return -1;
  }

  // History pages arrive ~30 messages at a time; merging them one upsert()
  // each costs a full array copy + sort per message. One copy and one sort
  // for the whole page keeps the prepend cheap however long the window grows.
  private upsertBatch(entries: MessageEntry[]): void {
    if (entries.length === 0) {
      return;
    }
    const next = this.messages.slice();
    const indexById = new Map<number, number>();
    for (let i = 0; i < next.length; i++) {
      indexById.set(next[i].id, i);
    }
    let appended = false;
    for (const entry of entries) {
      const hydrated = this.hydrateFromFileCache(entry);
      const idx = indexById.get(hydrated.id);
      if (idx !== undefined) {
        next[idx] = hydrated;
      } else {
        indexById.set(hydrated.id, next.length);
        next.push(hydrated);
        appended = true;
      }
    }
    if (appended) {
      next.sort((a: MessageEntry, b: MessageEntry) => a.id - b.id);
    }
    this.messages = next;
  }

  private upsert(entry: MessageEntry): void {
    const hydrated = this.hydrateFromFileCache(entry);
    const idx = this.indexOf(hydrated.id);
    if (idx >= 0) {
      const next = this.messages.slice();
      next[idx] = hydrated;
      this.messages = next;
      return;
    }
    const next = this.messages.slice();
    next.push(hydrated);
    next.sort((a: MessageEntry, b: MessageEntry) => a.id - b.id);
    this.messages = next;
  }

  private hydrateFromFileCache(entry: MessageEntry): MessageEntry {
    // The picker commonly downloads the selected sticker before sendMessage
    // returns. Hydrate a new entry from that completed-file cache instead of
    // flashing an indefinite loading ring or downloading the same file again.
    if (entry.videoFileId !== 0 && entry.videoPath !== '') {
      this.completedFilePaths.set(entry.videoFileId, entry.videoPath);
      publishThumbPath(entry.videoFileId, entry.videoPath);
    }
    if (entry.photoFileId !== 0 && entry.photoPath !== '') {
      this.completedFilePaths.set(entry.photoFileId, entry.photoPath);
      publishThumbPath(entry.photoFileId, entry.photoPath);
    }
    if (entry.stickerFileId !== 0 && entry.stickerPath !== '') {
      this.completedFilePaths.set(entry.stickerFileId, entry.stickerPath);
      publishThumbPath(entry.stickerFileId, entry.stickerPath);
    }
    const cachedPhotoPath = entry.photoFileId !== 0
      ? (this.completedFilePaths.get(entry.photoFileId) ?? '') : '';
    const cachedFullPhotoPath = entry.photoFullFileId !== 0
      ? (this.completedFilePaths.get(entry.photoFullFileId) ?? '') : '';
    const cachedVideoPath = entry.videoFileId !== 0
      ? (this.completedFilePaths.get(entry.videoFileId) ?? '') : '';
    const cachedStickerPath = entry.stickerFileId !== 0
      ? (this.completedFilePaths.get(entry.stickerFileId) ?? '') : '';
    let hydrated = entry;
    if ((entry.photoPath === '' && cachedPhotoPath !== '') ||
      (entry.photoFullPath === '' && cachedFullPhotoPath !== '') ||
      (entry.videoPath === '' && cachedVideoPath !== '') ||
      (entry.stickerPath === '' && cachedStickerPath !== '')) {
      hydrated = cloneMessage(entry);
      if (hydrated.photoPath === '' && cachedPhotoPath !== '') {
        hydrated.photoPath = cachedPhotoPath;
        hydrated.photoProgress = 100;
        hydrated.photoFailed = false;
      }
      if (hydrated.photoFullPath === '' && cachedFullPhotoPath !== '') {
        hydrated.photoFullPath = cachedFullPhotoPath;
        if (hydrated.photoPath === '') {
          hydrated.photoPath = cachedFullPhotoPath;
          hydrated.photoProgress = 100;
          hydrated.photoFailed = false;
        }
      }
      if (hydrated.videoPath === '' && cachedVideoPath !== '') {
        hydrated.videoPath = cachedVideoPath;
        hydrated.videoProgress = 100;
        hydrated.videoFailed = false;
        hydrated.mediaDownloadActive = false;
      }
      if (hydrated.stickerPath === '' && cachedStickerPath !== '') {
        hydrated.stickerPath = cachedStickerPath;
        hydrated.stickerProgress = 100;
        hydrated.stickerFailed = false;
        hydrated.stickerDownloadActive = false;
      }
    }
    return hydrated;
  }

  private patch(id: number, fn: (c: MessageEntry) => void): void {
    const idx = this.indexOf(id);
    if (idx < 0) {
      return;
    }
    const c = cloneMessage(this.messages[idx]);
    fn(c);
    // 发送状态走旁路直达气泡的状态图标（见 sendStateChannel）：它不在行 key
    // 里，不这样发布就没人知道它变了。通道在状态未变时早退，所以这里不必
    // 挑调用点。
    publishSendState(c.rowId, c.sendState);
    const next = this.messages.slice();
    next[idx] = c;
    this.messages = next;
    this.notifySoon();
  }

  // Telegram may reuse one file id for forwards or repeated media. Keep every
  // visible consumer synchronized instead of updating only the message that
  // happened to start the download.
  private patchVideoEntries(fileId: number, fn: (c: MessageEntry) => void): void {
    if (fileId === 0) {
      return;
    }
    let changed = false;
    this.messages = this.messages.map((m: MessageEntry): MessageEntry => {
      if (m.videoFileId !== fileId) {
        return m;
      }
      const c = cloneMessage(m);
      fn(c);
      changed = true;
      return c;
    });
    if (changed) {
      this.notifySoon();
    }
  }

  // Coalesced publish for download-progress updates.
  //
  // TDLib emits updateFile many times a second per downloading file, and every
  // publish makes ChatPage re-collapse the WHOLE loaded message list to rebuild
  // its row keys — a ~60-field signature per message, with loops over poll
  // options, reactions, buttons and text entities. During a fling, thumbnails
  // for the rows coming into view are downloading, so that ran continuously on
  // the UI thread and showed up as dropped frames.
  //
  // One publish per frame instead. A progress ring that advances at 60Hz rather
  // than whatever rate the network happens to produce is indistinguishable; the
  // whole-list rebuild is not. Only file progress goes through here — pagination
  // and initial-history transitions still publish immediately, because ChatPage
  // anchors scroll position on them.
  // The ONLY publication path for plain 'update' notifications. Every bare
  // this.notify() used to publish immediately, and page entry is exactly when
  // they cluster: avatars, reply quotes, forward titles and thumbnails all
  // resolve within the first ~30ms, which used to mean ~10 dataset passes and
  // every freshly built row rebuilt three or four times — the measured
  // first-entry jank. One frame of coalescing collapses the storm; kinds with
  // ordering semantics ('latest'/'around'/...) still go through notify(kind)
  // directly.
  // 初始历史落地的时刻；其后 INITIAL_SETTLE_WINDOW_MS 内视为安置期。
  private initialSettleStart: number = 0;

  private notifySoon(): void {
    if (this.coalesceTimer !== -1) {
      return;
    }
    // 安置期内所有 'update' 发布被整体压到窗口末尾一次放行：进页后首屏刚
    // 建完的那一秒完全不做行重建，头像/引用/缩略图在 1 秒末一波补齐。
    // （150ms 滚动窗的版本仍出现 2 波近整页重建；压到单次是当前形态。）
    const remaining: number = this.initialSettleStart > 0
      ? this.initialSettleStart + INITIAL_SETTLE_WINDOW_MS - Date.now() : 0;
    this.coalesceTimer = setTimeout((): void => {
      this.coalesceTimer = -1;
      this.notify();
    }, remaining > 0 ? remaining : NOTIFY_COALESCE_MS);
  }

  private notify(kind: string = 'update'): void {
    // openChat may emit updateNewMessage before the first getChatHistory page
    // returns (commonly just the newest message of a newly visited channel).
    // Keep those updates in `messages`, but publish the initial timeline only
    // when history is ready; otherwise ChatPage treats that one-message
    // snapshot as its completed first page and anchors the viewport to it.
    // 已读水位是对 messages 的纯状态计算，与"是否发布快照"无关：必须在
    // 下面的提前返回之前执行，否则初始历史加载期间到达的 updateChatReadOutbox
    // 会被整个丢弃（要等下一次 notify 才自愈）。
    this.applyReadOutbox();
    if (kind === 'update' && this.initialHistoryState === 'loading') {
      return;
    }
    this.currentNotifyKind = kind;
    try {
      for (const l of this.msgSubs) {
        l(this.messages);
      }
    } finally {
      this.currentNotifyKind = 'update';
    }
  }
}
