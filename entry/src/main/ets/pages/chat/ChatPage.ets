import { router, promptAction } from '@kit.ArkUI';
import { DeleteMessagesDialog } from './DeleteMessagesDialog';
import { pasteboard } from '@kit.BasicServicesKit';
import { i18n } from '@kit.LocalizationKit';
import { PollOptionInfo } from '../../util/formatMsgContent';
import { getStickersForEmoji, rememberRecentSticker } from '../../store/StickerApi';
import { botMiniAppUrl, openMiniApp } from '../../store/BotApi';
import {
  InlineQueryPage, InlineResultRow, getInlineResults, sendInlineResult
} from '../../store/BotApi';
import { common, abilityAccessCtrl, Permissions } from '@kit.AbilityKit';
import { geoLocationManager } from '@kit.LocationKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { PollComposeSheet } from './PollComposeSheet';
import { ContactPickerSheet, PickedContact } from './ContactPickerSheet';
import { VideoNoteRecorderView } from './VideoNoteRecorderView';
import { picker, fileIo as fs } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { VoiceRecorder } from '../../services/VoiceRecorder';
import { formatDateSeparator } from '../../util/formatDateSeparator';
import { fileOpenMimeType } from '../../util/fileMessage';
import { resolveEmojiStatus } from '../../util/emojiStatus';
import { TgsStickerView } from './TgsStickerView';
import { WebmStickerView } from './WebmStickerView';
import { EmojiPanel } from './EmojiPanel';
import { StickerItem } from './StickerPicker';
import { GifItem } from './GifPicker';
import { getVoicePlayback } from '../../services/VoicePlayback';
import { openLocalFile } from '../../util/openLocalFile';
import { saveMediaToGallery, saveFileToLocal } from '../../util/mediaSaver';
import { getTdClient, getUserStore, getChatStore, getChatThemeStore } from '../../tdkit/Globals';
import { MessageStore, MediaSendItem } from '../../store/MessageStore';
import { MessageEntry, buildMessageEntry } from '../../store/MessageEntry';
import { ReplyKeyboard, KeyboardBtn, KB_TEXT } from '../../store/ReplyKeyboard';
import { ChatEntry, computeInitials, isMutedFrom } from '../../store/ChatEntry';
import { MessageBubble } from './MessageBubble';
import { PlaySlotRegistry } from './PlaySlotRegistry';
import { shouldCompete, slotKeyMessageId } from './playSlot';
import { MediaViewerOverlay } from './MediaViewerOverlay';
import { ForwardSheet } from './ForwardSheet';
import { ScheduledSheet } from './ScheduledSheet';
import { ReactionSheet } from './ReactionSheet';
import { cacheDestPath, isVideoPath } from '../../util/mediaPick';
import {
  ChatBackgroundState, ChatBackgroundStore, emptyChatBackground
} from '../../store/ChatBackgroundStore';
import { gradientStops } from '../../util/backgroundPresentation';
import {
  BackgroundRasterParams, backgroundBlurRadius, cachedRaster, patternTileGrid,
  patternTileGridLayer, rasterSignature, rasterizeBackground
} from '../../util/chatBackgroundRaster';
import {
  chatHeaderPresentation, chatHeaderTitle, ChatHeaderPresentation
} from '../../util/chatHeaderPresentation';
import { MusicQueue } from '../../services/MusicQueue';
import { VoiceState } from '../../services/VoicePlayback';
import { setMediaViewerOrientation } from './LiveViewerUi';
import { actionMenuRow } from './ActionMenuRow';
import { AlbumGroupDataSource, contentFingerprint, DataSourceUpdateKind } from './AlbumGroupDataSource';
import { BasicPrefetcher } from '@kit.ArkUI';
import { guardKey } from '../../util/keyGuard';
import { CachedImage } from '../common/CachedImage';
import { collapseAlbums, groupIndexOf, AlbumGroup } from '../../util/collapseAlbums';
import { AvatarView } from '../chatlist/AvatarView';
import {
  KEY_POWER_ACTIVE, KEY_POWER_CHAT_EFFECTS, KEY_POWER_EMOJI, KEY_POWER_EMOJI_REACTIONS,
  KEY_POWER_EFFECT_BACKGROUND, KEY_POWER_EFFECT_BLUR, KEY_POWER_EFFECT_MENU,
  KEY_POWER_EFFECT_REACTION, KEY_POWER_EFFECT_REPLY, KEY_POWER_PARTICLES,
  KEY_POWER_SMOOTH_TRANSITIONS, KEY_POWER_AUTOPLAY_VIDEO,
  KEY_REDUCE_ANIM, KEY_SEND_BY_ENTER, KEY_TRANSLATE_CHATS,
  KEY_AUTOPLAY_MUTED, KEY_BG_BLUR, BG_BLUR_DEFAULT,
  powerAnimationDuration,
  powerFeatureEnabled, powerGroupAnimationDuration, powerGroupFeatureEnabled, autosaveEnabled,
  translateOptedOut, setTranslateOptedOut
} from '../../store/AppSettings';
import {
  getTranslationService, languageDisplayName, looksLikeTargetLanguage, resolveTranslateTarget,
  TRANSLATE_LANG_CODES
} from '../../services/TranslationService';
import {
  COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY, botButtonBg, darkResourceMode
} from '../../util/theme';
import {
  normalizeTelegramLink, bareUsernameOf, inviteLinkOf, chatLinkActionOf,
  chatFolderInviteLinkOf, stickerSetLinkOf
} from '../../util/linkNav';
import {
  openTelegramLink, openInviteLink, openChatLinkAction, openChatFolderInviteLink, openStickerSetLink
} from '../../util/openTelegramLink';
import { openUrl } from '../../util/openUrl';
import {
  reactionDisplayLabel, reactionTypeOf
} from '../../util/reactions';
import { openWebUrl } from '../../util/webBrowserNav';
import { TdObject, TdRequest, TdError } from '../../tdkit/TdTypes';
import {
  searchMentions, mentionOfUser, loadBotCommands, MentionItem, CommandItem
} from '../../store/InputSuggestions';
import { appendMention, mentionToken } from '../../util/mentionDraft';
import { floatingLiveWindow } from './LiveFloatingWindow';
import { MUTE_LONG, setMute } from '../../store/ChatActions';
import { liveLocation, LiveLocationState } from '../../services/LiveLocationService';
import { plural, str } from '../../util/strings';
import { LANGUAGE_EPOCH } from '../../util/appLanguage';
import { audioQueueApplies } from '../../util/audioQueueGate';

// One emoji-triggered sticker hint shown above the composer.
interface StickerSuggestion {
  fileId: number;
  thumbId: number;
  thumbPath: string;
}

const PINNED_SEG_MAX: number = 5;
// Scroll-to-bottom FAB: beyond this many groups from the end, reload the newest
// page instead of scrolling row by row through the loaded history.
const JUMP_RELOAD_THRESHOLD: number = 40;
// Grace period before an entered-from-global-search chat runs its in-chat search.
const SEARCH_ENTRY_DELAY_MS: number = 400;
// 等上下文菜单收起再弹确认框：菜单是独立子窗口，收起过程中弹出的
// 对话框会挂死（Promise 既不 resolve 也不 reject）。
const MENU_DISMISS_MS: number = 150;
const NOW_SEC_TICK_MS: number = 30000;
const STICKER_FLY_MS: number = 260;
const STICKER_GHOST_SIDE: number = 92;
// 绝对像素半径。在高密度屏上 18 远达不到"糊掉"的观感。
const HEADER_BLUR_RADIUS: number = 140;
// 实时位置的上报间隔。Telegram 官方客户端也是分钟级——秒级上报既费电又没有
// 实际意义，收到的一方看到的地图精度远达不到那个粒度。

// 稳定后的预建行数，以及首屏之后隔多久补上。
const LIST_CACHED_COUNT: number = 4;
const CACHED_COUNT_GROW_MS: number = 450;

const CHAT_HEADER_ACTION_SIZE: number = 42;
const CHAT_HEADER_RADIUS: number = 22;
const CHAT_HEADER_NAV_GUARD_MS: number = 700;
const TOP_CARD_LOADING_DELAY_MS: number = 180;
const TOP_CARD_ACTION_GUARD_MS: number = 650;

// Composer geometry. These three have to agree with the TextArea's own
// lineHeight/padding: the editor height is computed from them, and a mismatch
// clips the last line instead of scrolling to it.
const COMPOSER_LINE_H: number = 22;
const COMPOSER_EDITOR_PAD: number = 9;
const COMPOSER_MAX_LINES: number = 4;

// Emoji offered in the full reaction picker (opened from the long-press menu's
// chevron). Ordered roughly like the official client's reaction sheet.
@Entry
@Preview
@Component
struct ChatPage {
  // @Watch, because the row key below embeds this value: bumping it renames
  // every row, and the data source has to be told or LazyForEach keeps a key
  // table that no longer matches anything.
  @StorageProp(LANGUAGE_EPOCH) @Watch('onLanguageEpochChanged') langEpoch: number = 0;
  @StorageProp('topSafeHeight') topSafe: number = 0;
  @StorageProp('bottomSafeHeight') bottomSafe: number = 0;  // ✅ 新增
  @StorageProp('keyboardHeightVp') @Watch('onKeyboardHeightChanged') keyboardH: number = 0;
  @StorageProp('appIsForeground') @Watch('onAppForegroundChanged') appIsForeground: boolean = true;
  @State messages: MessageEntry[] = [];
  @State messageLoadState: string = 'loading'; // loading | ready | error
  @State messageLoadError: string = '';
  @State olderLoadState: string = 'idle'; // idle | loading | error | end
  @State newerLoadState: string = 'idle'; // idle | loading | error | end
  @State visibleGroupCount: number = 0;
  // Rendered through the LazyForEach data source (incremental notifications keep
  // scroll position on prepend); the plain array mirror serves index lookups.
  // Keep the count reactive because groups itself is intentionally not @State.
  // @State (not a plain field) so MediaViewerOverlay can take it by @Link:
  // @Link requires its source to be a state variable, and a plain field handed
  // to a child would freeze at its construction-time value, breaking album
  // paging in the viewer once more history loads.
  @State groups: AlbumGroup[] = [];
  private groupsData: AlbumGroupDataSource = new AlbumGroupDataSource();

  // The ONE definition of a message row's LazyForEach key. Both the key
  // generator below and the data source's operations go through this: the data
  // source names the keys its ADD/CHANGE operations affect instead of leaving
  // the framework to re-derive them, and two spellings of the format would put
  // the two tables out of step with nothing to catch it.
  //
  // The content fingerprint is the load-bearing part: LazyForEach reuse is
  // key-driven (reload's contract is "key unchanged -> original component
  // reused"), so a key that doesn't change with the content resurrects stale
  // nodes on every reload — see contentFingerprint. langEpoch is in the key so
  // a language switch rebuilds every row exactly once; the alternative — a
  // @StorageProp on MessageBubble — registers an AppStorage observer per ROW,
  // paid on every mount and every scroll recycle, to serve something that
  // changes once in a session.
  private rowKeyOf: (g: AlbumGroup) => string = (g: AlbumGroup): string =>
    `message_group_${g.head.id}_${g.memberIds.join('_')}` +
    `_${contentFingerprint(g.key)}_${this.langEpoch}`;

  // Whether this page is currently visible (between onPageShow and onPageHide),
  // and whether the list dataset changed while it was not.
  //
  // Notifications delivered while the page is hidden are the root of the
  // "messages scrambled after returning from the background" report. The store
  // keeps publishing while the app is backgrounded, so the data source keeps
  // emitting ADD/CHANGE — but a hidden List does not fully apply them: on the
  // device, "Use repeat key" warnings start the moment the page becomes visible
  // again, BEFORE any new notification, meaning the framework's key -> node
  // table came back from the hidden period already inconsistent. It then
  // re-associates recycled rows against that stale table: the newest rows are
  // freshly built and correct, the rows above them come back as some other
  // row's content. The data and the notifications are provably clean — the
  // snapshot duplicate scan and a mirrored key table both stayed silent while
  // the framework warned — so the fix is not to notify better but to stop
  // trusting the hidden-period bookkeeping: one RELOAD on return rebuilds the
  // framework's table from the (correct) dataset, and the viewport is restored
  // around the anchor row.
  private pageVisible: boolean = true;
  private hiddenListDirty: boolean = false;

  // The single gate for publishing a dataset while the page may be hidden.
  private publishGroups(groups: AlbumGroup[]): DataSourceUpdateKind {
    const kind: DataSourceUpdateKind = this.groupsData.update(groups);
    if (!this.pageVisible && kind !== 'none') {
      this.hiddenListDirty = true;
    }
    return kind;
  }

  private resyncListAfterHidden(): void {
    let anchorId: number = 0;
    let anchorY: number = 0;
    if (!this.atBottom && this.didInitialScroll &&
      this.curStartIdx >= 0 && this.curStartIdx < this.groups.length) {
      anchorId = this.groups[this.curStartIdx].head.id;
      try {
        anchorY = this.scroller.getItemRect(this.curStartIdx).y;
      } catch (e) {
        anchorY = 0;
      }
    }
    this.groupsData.reload();
    if (anchorId > 0) {
      this.restorePrependAnchor(this.groups, anchorId, anchorY);
    } else if (this.atBottom && this.didInitialScroll) {
      const actionSeq: number = ++this.scrollActionSeq;
      setTimeout((): void => {
        if (actionSeq === this.scrollActionSeq) {
          this.scroller.scrollEdge(Edge.Bottom);
        }
      }, 0);
    }
  }
  // 官方预取算法：按可见区域变化决定预取/取消哪些行的图片解码。
  private imagePrefetcher: BasicPrefetcher = new BasicPrefetcher(this.groupsData);
  // 首屏只建可见行，落地后再补预建（见 List.cachedCount）。
  @State listCachedCount: number = 1;
  private cachedCountTimer: number = -1;
  @State subtitle: string = '';
  // "×× 正在输入…" — shown as the composer placeholder while live, not in the
  // header subtitle (see composerPlaceholder).
  @State typingLabel: string = '';
  private typingSenders: Map<number, number> = new Map(); // senderId -> expiry ms
  private typingTimer: number = -1;
  private unsubChatAction: (() => void) | null = null;
  @State title: string = '';
  @State avatarPath: string = '';
  @State initials: string = '?';
  @State draft: string = '';
  // 聊天设置 → 回车键发送.
  @StorageProp(KEY_SEND_BY_ENTER) sendByEnter: boolean = false;
  @StorageProp('screenWidthVp') screenW: number = 360;
  @StorageProp('screenHeightVp') screenH: number = 780;
  @StorageProp(KEY_POWER_ACTIVE) @Watch('onAutoplayPolicyChanged') powerSaving: boolean = false;
  @StorageProp(KEY_POWER_CHAT_EFFECTS) powerChatEffects: boolean = true;
  @StorageProp(KEY_POWER_EFFECT_BACKGROUND) powerBackgroundEffect: boolean = false;
  @StorageProp(KEY_POWER_PARTICLES) powerParticles: boolean = true;
  @StorageProp(KEY_POWER_EMOJI) powerEmoji: boolean = true;
  @StorageProp(KEY_POWER_EMOJI_REACTIONS) powerEmojiReactions: boolean = true;
  @StorageProp(KEY_REDUCE_ANIM) @Watch('onAutoplayPolicyChanged') reduceAnimations: boolean = false;
  // 「自动播放视频」开关。播放位竞选的总闸门之一，见 playSlotsEnabled()。
  @StorageProp(KEY_POWER_AUTOPLAY_VIDEO) @Watch('onAutoplayPolicyChanged')
  autoplayVideo: boolean = true;
  // 聊天背景设置页的「模糊度」滑块（KEY_BG_BLUR）。拖动时要立即重算离屏合成图，
  // 否则拖完滑块背景看起来没反应（命中旧签名的缓存图）。
  @StorageProp(KEY_BG_BLUR) @Watch('onBgBlurChanged') bgBlur: number = BG_BLUR_DEFAULT;
  @State powerBackgroundPhase: boolean = false;
  // TDLib per-chat wallpaper. Solid/gradient fills render immediately;
  // wallpaper and pattern documents appear as soon as downloadFile completes.
  // One snapshot in place of the nine background state variables this replaces.
  // Resolution (chat background → theme → account default → installed default)
  // and its four TDLib subscriptions live in ChatBackgroundStore.
  @State chatBg: ChatBackgroundState = emptyChatBackground();
  private bgStore: ChatBackgroundStore | null = null;
  private unsubBg: (() => void) | null = null;
  private unsubTranslatable: (() => void) | null = null;
  private powerBackgroundTimer: number = -1;
  private readonly powerParticleIds: number[] = [0, 1, 2, 3, 4, 5, 6, 7];
  @State replyToId: number = 0;      // message being replied to (0 = none)
  @State replyToName: string = '';
  @State replyToText: string = '';
  @State editingId: number = 0;      // message being edited (0 = none)
  @State editingPreview: string = '';
  @State editingKind: string = 'text'; // 'text' | 'caption'
  private draftBeforeEdit: string = ''; // composer text stashed while editing
  @State showReactionSheet: boolean = false; // full emoji reaction picker
  @State reactionTargetId: number = 0;
  // The allowed-emoji list and custom-emoji thumbnails live in ReactionSheet,
  // which fetches them per open. Only the in-flight key stays here: the quick
  // reaction row on each bubble issues the same request and shares the guard.
  @State reactionPendingKey: string = '';
  @State paidMediaPendingIds: number[] = [];
  // Forwarding is deliberately kept as an in-page sheet: leaving ChatPage to
  // pick a destination used to discard the long-press/selection context.
  @State showForwardSheet: boolean = false;
  @State showPollSheet: boolean = false;
  @State showContactSheet: boolean = false;
  @State showVideoNoteRecorder: boolean = false;
  // The list itself lives in ScheduledSheet and reloads on each open.
  @State showScheduledSheet: boolean = false;
  // Which messages the picker will forward. The picker's own list/query/send
  // state lives in ForwardSheet and resets with it on each open.
  private forwardMessageIds: number[] = [];
  @State nowSec: number = 0;
  private nowSecTimer: number = -1;
  @State @Watch('onViewerTargetChanged') viewerMsgId: number = 0;
  @State chromeVisible: boolean = true;
  @State viewerVideoLandscape: boolean = false;
  @State viewerClosing: boolean = false;
  // 播放器为播放拉起的下载（见 notePlaybackRequest）。不参与渲染，普通字段。
  private playbackRequestedIds: number[] = [];
  // GIF playback is page-owned rather than row-owned: LazyForEach replaces a
  // row key as download progress/reactions change, but a user's pause/play
  // choice must survive that replacement.
  @State pausedAnimationIds: number[] = [];
  @State forcedAnimationIds: number[] = [];
  @State failedAnimationIds: number[] = [];
  // Swiper's initial page when the viewer opens. Plain field, not @State: it is
  // read once when MediaViewerOverlay is constructed, which happens after this
  // has already been set by onMediaTap.
  private viewerInitIdx: number = 0;
  @State swipeDir: number = 1; // 1 = advancing forward (next), -1 = going back — drives the slide direction
  // Window coordinates (vp) of the tap that opened the viewer — anchor for its
  // expand-from-tap open / shrink-back-to-tap close transition.
  @State tapX: number = 0;
  @State tapY: number = 0;
  @State pinnedPreview: string = '';
  @State pinnedCount: number = 0;
  @State pinnedLoadState: string = 'loading'; // loading | ready | error
  @State pinnedJumpBusy: boolean = false;
  // 正在直播入口条:chat.video_chat.group_call_id > 0 时显示("正在直播").
  @State liveGroupCallId: number = 0;
  @State liveCallIsActive: boolean = false;
  @State liveCallIsRtmp: boolean = false;
  @State liveParticipantCount: number = 0;
  @State livePulseExpanded: boolean = false;
  @State liveLoadState: string = 'loading'; // loading | ready | error
  @State liveDialogOpening: boolean = false;
  @State liveNavigationBusy: boolean = false;
  @State topCardLoadingVisible: boolean = false;
  private unsubVideoChat: (() => void) | null = null;
  private unsubGroupCall: (() => void) | null = null;
  private livePulseTimer: number = -1;
  private liveStateRefreshTimer: number = -1;
  private liveChatRefreshInFlight: boolean = false;
  private liveGroupRefreshInFlight: boolean = false;
  private liveChatResolveSeq: number = 0;
  private liveGroupResolveSeq: number = 0;
  private liveGroupRequestId: number = 0;
  private topCardLoadingTimer: number = -1;
  private topCardActionTimer: number = -1;
  private chatId: number = 0;
  private botCallbackPending: Set<string> = new Set();
  // >0: comment-thread view over the linked discussion group (see onCommentTap)
  private threadRootId: number = 0;
  private topicName: string = '';
  private forumTopicId: number = 0;
  @State isGroup: boolean = false;
  @State isChannel: boolean = false;
  // TDLib keeps membership on the underlying basicGroup/supergroup rather
  // than on chat itself. Public chats opened from search can therefore have
  // readable history while the current user is still outside the chat.
  // writable = normal composer, joinable = bottom "加入" action,
  // blocked = banned/unavailable, checking = waiting for the group object.
  @State membershipState: string = 'writable';
  @State joiningChat: boolean = false;
  // TDLib doesn't consistently return the local "joined" service message in
  // getChatHistory. Keep the confirmed join event as a client-only timeline
  // row until the real service message arrives. It deliberately has no member
  // ids, so it can never leak into viewMessages/read or pagination requests.
  private clientJoinNoticeVisible: boolean = false;
  private clientJoinNoticeIsChannel: boolean = false;
  private clientJoinNoticeDate: number = 0;
  private clientJoinNoticeEntryCache: MessageEntry | null = null;
  private clientJoinNoticeRouteChatId: number = 0;
  private membershipSupergroupId: number = 0;
  private membershipBasicGroupId: number = 0;
  private membershipSeq: number = 0;
  private store: MessageStore | null = null;
  private scroller: Scroller = new Scroller();
  private didInitialScroll: boolean = false;
  // 播放位竞选：滚动停下后选出唯一播放/下载的视频气泡（见 PlaySlotRegistry）。
  private playSlots: PlaySlotRegistry = new PlaySlotRegistry();
  private unsubPlaySlot: (() => void) | null = null;
  @State playSlotKey: string = '';
  // 新上位的播放位从哪一毫秒起播。换届时从 bubblePositionMs 查一次（见
  // subscribe 回调），随 playSlotKey 一起下发给气泡——查看器交还的进度就是
  // 靠这条路真正接到 VideoBubbleSurface.startPositionMs 上的。
  @State playSlotStartMs: number = 0;
  // 缓存设置 → 自动播放静音开关，唯一消费点：下发给气泡播放器的 muted。
  @StorageProp(KEY_AUTOPLAY_MUTED) autoplayMuted: boolean = true;
  // 气泡播放位的播放进度，按 messageId 记录。onPlaySlotPositionChanged 是
  // 350ms 一次的高频回调，故意用普通 Map 而不是 @State/@Link/AppStorage——
  // 写状态会让消息列表每 350ms 重建一次。打开全屏查看器时读它作为
  // startPositionMs，关闭查看器时把最终进度写回。整个会话关闭时清空
  // （见 aboutToDisappear），避免无界增长。
  private bubblePositionMs: Map<number, number> = new Map<number, number>();
  // 全屏查看器当前播放进度：只在查看器打开期间被 onPositionChanged 回调更新，
  // 关闭时读一次写回 bubblePositionMs，同样是普通字段，不驱动渲染。
  private viewerPositionMs: number = 0;
  // 打开查看器那一刻从 bubblePositionMs 取到的起播位置，一次性字段，供
  // MediaViewerOverlay 构造时读取（与 viewerInitIdx 同一模式）。
  private viewerStartPositionMs: number = 0;
  private slotTickTimer: number = -1;
  private lastMaxId: number = 0;
  @State atBottom: boolean = true;
  @State isMuted: boolean = false;
  // 整聊天翻译有两层，菜单里的那一项在两层之间切换含义：
  //   总开关开着 —— 默认所有会话都翻，菜单是"关掉这个会话"（本地排除名单）。
  //   总开关关着 —— 默认都不翻，菜单是"只翻这个会话"（服务端 is_translatable，
  //                 跟官方客户端同一个字段，多端同步）。
  // 早先只认服务端那个字段，它对没碰过的会话默认 false，结果开了总开关每个群
  // 还得手动点一次才翻，实际不可用。
  @State isTranslatable: boolean = false;
  @State translateChatOptOut: boolean = false;
  @StorageProp(KEY_TRANSLATE_CHATS) @Watch('onTranslateSettingChanged')
  translateChatsEnabled: boolean = false;
  // 是否正在共享实时位置（全局单例状态，不限于当前会话）。
  @State liveLocationActive: boolean = false;
  @State liveLocationMessageId: number = 0;
  // 贴纸"飞出"动画：从点击处向上收缩淡出，动画收尾时才关面板 —— 关面板要
  // 同步卸载整个贴纸网格并触发全页重排（实测 51ms），压在点击那一帧就是可感
  // 的顿挫；挪到运动尾声则被动作本身盖住。
  @State stickerGhostPath: string = '';
  @State stickerGhostX: number = 0;
  @State stickerGhostY: number = 0;
  @State stickerGhostFly: boolean = false;
  private stickerGhostTimer: number = -1;
  private deleteDialog: CustomDialogController | null = null;
  private unsubLiveLocation: (() => void) | null = null;
  @State unreadBadge: number = 0;
  private firstUnreadId: number = 0;
  // Set once the initial scroll parks on the unread boundary; suppresses every
  // auto-scroll-to-bottom until the user first touches the list, so a short
  // unread run isn't glued past the divider by async in-place content growth.
  private stayAtUnread: boolean = false;
  private curStartIdx: number = -1; // topmost visible row index (from onScrollIndex)
  private curEndIdx: number = -1;   // bottom visible row index (from onScrollIndex)
  private pendingScrollBottom: boolean = false; // snap to the end once jumpToLatest's page arrives
  @State scrollToBottomBusy: boolean = false;
  private scrollActionSeq: number = 0;
  // Keep the exact viewport when this cached page is temporarily covered by a
  // profile/media route and then becomes visible again.
  private resumeScrollPending: boolean = false;
  private resumeScrollChatId: number = 0;
  private resumeScrollThreadId: number = 0;
  private resumeScrollMessageId: number = 0;
  private resumeScrollItemY: number = 0;
  private resumeScrollAtBottom: boolean = true;
  // @State: the segment indicator renders from this — a plain field wouldn't
  // trigger a re-render when scrolling/tapping moves the shown pinned index.
  @State pinnedCycle: number = 0;
  private pendingJumpId: number = 0;
  private jumpLayoutSeq: number = 0;
  // One-shot gate for loading older pages: a fast fling to the very top used to
  // chain-load page after page (the list stays pinned at the edge, so the
  // trigger zone never clears). Re-armed when the user scrolls clear of the
  // top zone or starts a new touch gesture.
  private olderArmed: boolean = true;
  // Jump-target highlight: a translucent overlay over the target row that
  // gently blinks twice after a reply/pinned/link jump lands.
  @State flashTop: number = 0;
  @State flashHeight: number = 0;
  @State flashAlpha: number = 0;
  @State flashShown: boolean = false;
  private flashSeq: number = 0;
  // Floating date chip: shows the topmost visible message's date while the
  // list scrolls, fades out shortly after scrolling stops (the in-list date
  // pills stay — this is the always-visible companion).
  @State floatDate: string = '';
  @State floatDateShown: boolean = false;
  private floatDateHideTimer: number = -1;
  private floatDateIndex: number = -1;
  private floatDateTimerArmedAt: number = 0;
  private listTouchActive: boolean = false;
  private listUserScrollActive: boolean = false;
  // RESIZE shortens the List while the IME animates in. Preserve the live-tail
  // anchor captured before that resize; otherwise onDidScroll observes the
  // temporary clipped viewport, flips atBottom to false and leaves the last
  // messages behind the newly raised composer.
  private imeTailPinned: boolean = false;
  private imeLayoutSeq: number = 0;
  private lastKeyboardH: number = 0;
  // Message id of a video waiting to be saved to the gallery once downloaded.
  private pendingGallerySaveId: number = 0;
  private autoSavePendingIds: number[] = [];
  private autoSaveInFlight: boolean = false;
  // Separate intents keep "tap to open" and the explicit save action honest:
  // a completed download performs exactly the action the user requested.
  private pendingFileOpenId: number = 0;
  // Message id of a document waiting for the "save as" picker once downloaded.
  private pendingFileSaveId: number = 0;
  private fileOpenInFlightId: number = 0;
  private utilityActionAtMs: number = 0;
  // A tapped music message starts automatically once its on-demand download
  // completes. Only the latest tap owns this slot, so rapid track changes
  // cannot make an older download steal playback later.
  // Audio playback queue over this chat's music messages. Its logic (ordering,
  // the download-then-play hand-off, previous-vs-rewind) lives in MusicQueue and
  // is unit-tested there; this page only supplies the I/O.
  private musicQueue: MusicQueue = new MusicQueue({
    currentState: (): VoiceState => getVoicePlayback().current(),
    toggleMusic: (id: number, path: string, dur: number): void => {
      getVoicePlayback().toggleMusic(id, path, dur);
    },
    startMusic: (id: number, path: string, dur: number): void => {
      getVoicePlayback().startMusic(id, path, dur);
    },
    seek: (id: number, fraction: number): void => { getVoicePlayback().seek(id, fraction); },
    requestDownload: (id: number, failed: boolean): void => {
      this.store?.requestVideoDownload(id, false, failed);
    },
    toast: (message: string, durationMs: number): void => {
      promptAction.showToast({ message, duration: durationMs });
    }
  });
  // Messages with id above this slide in from the bottom (live arrivals only —
  // 0 disables, so rows created while scrolling history never animate).
  @State freshSinceId: number = 0;
  private freshClearSeq: number = 0;
  private prependRestoreSeq: number = 0;
  // '@' mention / '/' command suggestion panels above the input bar.
  @State mentionItems: MentionItem[] = [];
  @State stickerSuggestions: StickerSuggestion[] = []; // emoji-typed sticker hints
  private stickerSuggestSeq: number = 0;
  @State botMiniAppUrlValue: string = ''; // bot menu-button Mini App ('' = none)
  @State inlineResults: InlineResultRow[] = [];  // @bot query results
  private inlineQueryId: string = '';
  private inlineSeq: number = 0;
  private inlineTimer: number = -1;
  @State commandItems: CommandItem[] = [];
  private allCommands: CommandItem[] = [];
  @State commandLoadState: string = 'idle'; // idle | loading | ready | error
  @State commandLoadError: string = '';
  @State commandMenuOpen: boolean = false;
  private commandLoadSeq: number = 0;
  private mentionSeq: number = 0; // drops stale searchChatMembers responses
  // Bot "菜单" pill (private bot chats with registered commands).
  @State botMenuAvailable: boolean = false;
  // Emoji panel above the input bar.
  @State showEmojiPanel: boolean = false;
  @State emojiPanelTab: number = 0;
  @State emojiPanelClosing: boolean = false;
  // Bot custom reply keyboard (null = this chat has none). Always docked when
  // present — no toggle, so there's no state to track beyond the keyboard itself.
  @State replyKeyboard: ReplyKeyboard | null = null;
  // Bot keyboard collapsed by the input-bar toggle (or a one_time keyboard
  // after use). A NEW keyboard from the bot un-collapses automatically.
  @State replyKbCollapsed: boolean = false;
  @State replyKeyboardSendingKey: string = '';
  // Voice recording state.
  @State isRecording: boolean = false;
  @State recordingStarting: boolean = false;
  @State recordSeconds: number = 0;
  private recordTimer: number = -1;
  private voiceRec: VoiceRecorder | null = null;
  private recordingSeq: number = 0;
  @State composerSending: boolean = false;
  @State composerFocused: boolean = false;
  private composerController: TextAreaController = new TextAreaController();
  private mediaPickerOpen: boolean = false;
  private mediaCopySeq: number = 0;
  @State headerMenuShow: boolean = false; // header ⋮ dropdown
  // Header state is kept separate from message-history state. getChat can
  // resolve before history, fail independently, or arrive after a cached row.
  @State headerState: string = 'loading'; // loading | ready | error
  @State headerLoadError: string = '';
  @State headerVisible: boolean = false;
  @State headerProfileOpening: boolean = false;
  @State headerMuteUpdating: boolean = false;
  @State pageClosing: boolean = false;
  private headerPeerUserId: number = 0;
  private headerKind: string = '';
  private headerIdentityResolved: boolean = false;
  private headerResolveSeq: number = 0;
  private headerNavigationTimer: number = -1;
  private headerEntranceTimer: number = -1;
  // In-chat message search (search-mode header + result navigation).
  @State searchMode: boolean = false;
  // Multi-select mode (entered via the long-press menu's 选择 item).
  @State selecting: boolean = false;
  @State selectedIds: number[] = [];
  @State searchQuery: string = '';
  @State searchResults: number[] = []; // message ids, newest → oldest
  @State searchTotal: number = 0;
  @State searchIdx: number = 0;        // 0-based index into searchResults
  // Message id the chat was opened on from global search — becomes the current
  // hit instead of the search jumping to the newest one. 0 = no anchor.
  private searchAnchorId: number = 0;
  private searchSeq: number = 0;       // drops stale responses
  private unsubMsg: (() => void) | null = null;
  private unsubSub: (() => void) | null = null;
  // Peer's premium emoji status (private chats) shown beside the header title.
  @State headerEmojiPath: string = '';
  @State headerEmojiFormat: string = '';
  private headerEmojiFetched: boolean = false;
  private unsubChat: (() => void) | null = null;
  private unsubPinned: (() => void) | null = null;
  private unsubHeaderAvatar: (() => void) | null = null;
  private unsubHeaderTitle: (() => void) | null = null;
  private unsubReplyKb: (() => void) | null = null;
  private unsubMembershipSupergroup: (() => void) | null = null;
  private unsubMembershipBasicGroup: (() => void) | null = null;

  private clearFloatingDate(): void {
    if (this.floatDateHideTimer !== -1) {
      clearTimeout(this.floatDateHideTimer);
      this.floatDateHideTimer = -1;
    }
    this.floatDate = '';
    this.floatDateShown = false;
    this.floatDateIndex = -1;
    this.floatDateTimerArmedAt = 0;
    this.listTouchActive = false;
    this.listUserScrollActive = false;
  }

  private resetScrollSession(): void {
    this.scrollActionSeq++;
    this.jumpLayoutSeq++;
    this.prependRestoreSeq++;
    this.bottomChromeLayoutSeq++;
    this.didInitialScroll = false;
    this.lastMaxId = 0;
    this.atBottom = true;
    this.firstUnreadId = 0;
    this.stayAtUnread = false;
    this.curStartIdx = -1;
    this.pendingScrollBottom = false;
    this.scrollToBottomBusy = false;
    this.pendingJumpId = 0;
    this.pendingFileOpenId = 0;
    this.pendingFileSaveId = 0;
    this.fileOpenInFlightId = 0;
    this.musicQueue.reset();
    this.olderArmed = true;
    this.freshSinceId = 0;
    this.freshClearSeq++;
    this.imeTailPinned = false;
    this.imeLayoutSeq++;
    this.lastKeyboardH = this.keyboardH;
    this.cancelFlash();
    this.clearFloatingDate();
    this.messages = [];
    this.messageLoadError = '';
    this.olderLoadState = 'idle';
    this.newerLoadState = 'idle';
    this.groups = [];
    this.visibleGroupCount = 0;
    this.publishGroups([]);
    this.pausedAnimationIds = [];
    this.forcedAnimationIds = [];
    this.failedAnimationIds = [];
  }

  private resetComposerSession(): void {
    this.recordingSeq++;
    if (this.voiceRec !== null || this.isRecording || this.recordingStarting) {
      this.cancelRecording();
    }
    this.panelReadySeq++;
    this.showEmojiPanel = false;
    this.panelContentReady = false;
    this.emojiPanelClosing = false;
    this.draft = '';
    this.composerSending = false;
    this.composerFocused = false;
    this.imeTailPinned = false;
    this.imeLayoutSeq++;
    this.lastKeyboardH = this.keyboardH;
    this.mentionItems = [];
    this.commandItems = [];
    this.allCommands = [];
    this.commandLoadSeq++;
    this.commandLoadState = 'idle';
    this.commandLoadError = '';
    this.commandMenuOpen = false;
    this.botMenuAvailable = false;
    this.replyKeyboard = null;
    this.replyKbCollapsed = false;
    this.replyKeyboardSendingKey = '';
    this.clearReply();
  }

  private resetMessageActionSession(): void {
    this.selecting = false;
    this.selectedIds = [];
    this.showReactionSheet = false;
    this.reactionTargetId = 0;
    this.reactionPendingKey = '';
    this.paidMediaPendingIds = [];
    this.closeForwardSheet();
  }

  private isRealClientJoinNotice(message: MessageEntry): boolean {
    if (message.contentType !== 'system' || !message.isOutgoing) {
      return false;
    }
    // NOTE: the first two clauses compare display text, which is fragile — the
    // label is whatever the server sent, and it is compared against this app's
    // own copy. Both sides now go through str() so they at least stay in the
    // same language, but the structural systemType checks below are the ones
    // that actually hold. Worth replacing with a marker on the synthetic row.
    return message.placeholderLabel === str('cp_joined_group') ||
      message.placeholderLabel === str('cp_joined_channel') ||
      message.systemType === 'messageChatJoinByLink' ||
      message.systemType === 'messageChatJoinByRequest';
  }

  private clientJoinNoticeEntry(): MessageEntry {
    if (this.clientJoinNoticeEntryCache !== null) {
      return this.clientJoinNoticeEntryCache;
    }
    const content: TdObject = this.clientJoinNoticeIsChannel
      ? { '@type': 'messageCustomServiceAction', 'text': str('cp_joined_channel') }
      : { '@type': 'messageChatJoinByLink' };
    const raw: TdObject = {
      '@type': 'message',
      // The row is page-local and memberIds is cleared below. A negative id
      // also makes accidental lookup/action matching impossible.
      'id': -1,
      'chat_id': this.chatId,
      'date': this.clientJoinNoticeDate,
      'is_outgoing': true,
      'content': content
    };
    this.clientJoinNoticeEntryCache = buildMessageEntry(raw, getUserStore());
    return this.clientJoinNoticeEntryCache;
  }

  private groupsWithClientJoinNotice(list: MessageEntry[]): AlbumGroup[] {
    if (this.clientJoinNoticeVisible &&
      list.some((message: MessageEntry): boolean => this.isRealClientJoinNotice(message))) {
      // Replace the local row atomically when TDLib eventually supplies the
      // canonical service message, avoiding a one-frame duplicate.
      this.clientJoinNoticeVisible = false;
      this.clientJoinNoticeEntryCache = null;
    }
    if (!this.clientJoinNoticeVisible) {
      return collapseAlbums(list);
    }
    const displayList: MessageEntry[] = list.slice();
    displayList.push(this.clientJoinNoticeEntry());
    const groups: AlbumGroup[] = collapseAlbums(displayList);
    if (groups.length > 0) {
      const notice: AlbumGroup = groups[groups.length - 1];
      if (notice.head.id === -1) {
        notice.memberIds = [];
        notice.key = `client_join_${this.chatId}_${this.clientJoinNoticeDate}`;
      }
    }
    return groups;
  }

  private showClientJoinNotice(isChannel: boolean): void {
    this.clientJoinNoticeVisible = true;
    this.clientJoinNoticeIsChannel = isChannel;
    this.clientJoinNoticeDate = Math.floor(Date.now() / 1000);
    this.clientJoinNoticeEntryCache = null;
    const groups: AlbumGroup[] = this.groupsWithClientJoinNotice(this.messages);
    this.groups = groups;
    this.visibleGroupCount = groups.length;
    this.publishGroups(groups);
    if (this.didInitialScroll && this.atBottom) {
      const actionSeq: number = ++this.scrollActionSeq;
      setTimeout((): void => {
        if (actionSeq === this.scrollActionSeq) {
          this.scroller.scrollEdge(Edge.Bottom);
          this.refreshAtBottom();
        }
      }, 0);
    }
  }

  private captureScrollResume(): void {
    this.resumeScrollPending = false;
    if (!this.didInitialScroll || this.groups.length === 0 ||
      this.curStartIdx < 0 || this.curStartIdx >= this.groups.length) {
      return;
    }
    this.resumeScrollChatId = this.chatId;
    this.resumeScrollThreadId = this.threadRootId;
    this.resumeScrollMessageId = this.groups[this.curStartIdx].head.id;
    this.resumeScrollItemY = 0;
    try {
      this.resumeScrollItemY = this.scroller.getItemRect(this.curStartIdx).y;
    } catch (e) {
      this.resumeScrollItemY = 0;
    }
    this.resumeScrollAtBottom = this.atBottom;
    this.resumeScrollPending = true;
  }

  aboutToAppear(): void {
    // Before anything can publish a dataset: the data source names the keys of
    // the rows its operations touch, and it has to name them the same way the
    // LazyForEach key generator does.
    this.groupsData.setKeyBuilder(this.rowKeyOf);
    this.unsubPlaySlot = this.playSlots.subscribe((key: string): void => {
      // 起播位置必须在 playSlotKey 之前落下：气泡是靠 playSlotKey 的变化才
      // 挂载 VideoBubbleSurface 的，晚一步这条播放器就已经从 0 开始了。
      this.playSlotStartMs = key === '' ? 0 : (this.bubblePositionMs.get(slotKeyMessageId(key)) ?? 0);
      this.playSlotKey = key;
    });
    this.nowSec = Math.floor(Date.now() / 1000);
    const params = router.getParams() as Record<string, Object> | undefined;
    this.chatId = params !== undefined ? (params['chatId'] as number) : 0;
    this.threadRootId = params !== undefined ? ((params['threadRootId'] as number | undefined) ?? 0) : 0;
    // 话题模式（从 ForumTopicsPage 进入）：标题显示话题名而非"评论"。
    this.topicName = params !== undefined ? ((params['topicName'] as string | undefined) ?? '') : '';
    this.forumTopicId = params !== undefined
      ? ((params['forumTopicId'] as number | undefined) ?? 0) : 0;
    // 排除名单是本地的，chatId 一确定就能读，不用等 getChat 回来。
    this.translateChatOptOut = translateOptedOut(this.chatId);
    const incomingJoinNotice: boolean = params !== undefined
      ? ((params['showJoinedNotice'] as boolean | undefined) ?? false) : false;
    if (incomingJoinNotice && this.clientJoinNoticeRouteChatId !== this.chatId) {
      this.clientJoinNoticeRouteChatId = this.chatId;
      this.clientJoinNoticeVisible = true;
      this.clientJoinNoticeIsChannel = params !== undefined
        ? ((params['joinedNoticeIsChannel'] as boolean | undefined) ?? false) : false;
      this.clientJoinNoticeDate = Math.floor(Date.now() / 1000);
      this.clientJoinNoticeEntryCache = null;
    }
    getVoicePlayback().setMusicCompletionListener((messageId: number): void => {
      this.musicQueue.onCompleted(this.messages, messageId);
    });
    let scrollResumeWaiting: boolean = this.resumeScrollPending &&
      this.resumeScrollChatId === this.chatId &&
      this.resumeScrollThreadId === this.threadRootId &&
      this.groups.length > 0;
    if (!scrollResumeWaiting) {
      this.resumeScrollPending = false;
      this.resetScrollSession();
      this.resetComposerSession();
      this.resetMessageActionSession();
    } else {
      // Old rows remain visible until the replacement page has arrived. Clear
      // transient overlays/actions, but preserve the captured viewport.
      this.scrollActionSeq++;
      this.jumpLayoutSeq++;
      this.pendingJumpId = 0;
      this.pendingScrollBottom = false;
      this.scrollToBottomBusy = false;
      this.didInitialScroll = true;
      this.clearFloatingDate();
    }
    const cachedChat: ChatEntry | undefined = getChatStore().entryOf(this.chatId);
    if (cachedChat !== undefined &&
      (cachedChat.kind === 'basicGroup' || cachedChat.kind === 'supergroup' || cachedChat.kind === 'channel')) {
      // Avoid briefly exposing a working input field before the async member
      // status of a newly opened public chat arrives.
      this.membershipState = 'checking';
    }
    const jumpTo = params !== undefined ? (params['jumpTo'] as number | undefined) : undefined;
    this.resetHeaderState(cachedChat);
    this.resetTopCardState();
    this.resolveHeaderIdentity();
    // Entered from global search: open directly on this chat's results for the
    // same query (the search header, the hit list and ∧/∨ navigation). With a
    // message hit, that message is the jump target and becomes the current hit
    // — searchAnchorId keeps the search from jumping somewhere else.
    // Deep links like t.me/<name>?text=… open the chat with a prefilled draft.
    const incomingDraft = params !== undefined ? ((params['draftText'] as string | undefined) ?? '') : '';
    if (incomingDraft !== '') {
      this.draft = incomingDraft;
    } else {
      this.restoreServerDraft();
    }
    const incomingQuery = params !== undefined ? ((params['searchQuery'] as string | undefined) ?? '') : '';
    if (incomingQuery !== '') {
      this.searchMode = true;
      this.searchQuery = incomingQuery;
      this.searchAnchorId = jumpTo !== undefined ? jumpTo : 0;
    } else if (params !== undefined && ((params['startSearch'] as boolean | undefined) ?? false)) {
      // Profile-page 搜索 button: open the chat with an empty, focused search.
      this.searchMode = true;
    }
    this.refreshHeader();
    this.unsubChatAction = getTdClient().onUpdate('updateChatAction',
      (u: TdObject): void => this.onChatAction(u));
    // ForwardSheet subscribes to the chat list itself while it is open, so this
    // no longer has to push updates into it.
    this.unsubChat = getChatStore().subscribe(() => {
      this.refreshHeader();
    }, 'main');
    // Chat backgrounds have their own TDLib update and can change without a
    // title/message update. Listen directly so setting or clearing one is
    // visible while the conversation is open.
    this.unsubLiveLocation = liveLocation.subscribe((st: LiveLocationState): void => {
      this.liveLocationActive = st.active;
      // 只有共享发生在当前会话时才在气泡上显示停止按钮。
      this.liveLocationMessageId = st.active && st.chatId === this.chatId ? st.messageId : 0;
    });
    // 在其它设备改了这个开关时同步过来，否则菜单文案会和实际状态不符。
    this.unsubTranslatable = getTdClient().onUpdate('updateChatIsTranslatable',
      (u: TdObject): void => {
        if ((u['chat_id'] as number | undefined) === this.chatId) {
          this.isTranslatable = (u['is_translatable'] as boolean | undefined) ?? false;
        }
      });
    // Background resolution and its four TDLib subscriptions now live in the
    // store; the page only mirrors its snapshot into state.
    this.bgStore = new ChatBackgroundStore(
      getTdClient(), getChatStore(), getChatThemeStore(),
      (): boolean => darkResourceMode(getContext(this) as common.UIAbilityContext)
    );
    // Seeds the store's state with the last known account-default background
    // (captured process-wide by ChatBackgroundStore, warmed at app start by
    // MainScreen's preload) BEFORE subscribe() below synchronously hands the
    // listener the store's initial state. Without this, every freshly opened
    // chat starts on emptyChatBackground() — colors.length === 0 — which
    // paints the near-white chat_bg resource for however long the real
    // resolution's TDLib round trip takes. Most chats resolve to the account
    // default anyway, so this seed is usually the final answer, not a guess
    // that gets thrown away; a chat with its own background still corrects
    // itself as soon as refresh()/open() resolves it, same as before.
    this.bgStore.seedFromDefault();
    this.unsubBg = this.bgStore.subscribe((state: ChatBackgroundState): void => {
      this.chatBg = state;
      this.syncBackgroundRaster();
    });
    this.bgStore.open(this.chatId);
    this.unsubMembershipSupergroup = getTdClient().onUpdate('updateSupergroup', (u: TdObject) => {
      const supergroup = u['supergroup'] as TdObject | undefined;
      if (supergroup !== undefined &&
        ((supergroup['id'] as number | undefined) ?? 0) === this.membershipSupergroupId) {
        this.applyMembershipStatus(supergroup['status'] as TdObject | undefined);
      }
    });
    this.unsubMembershipBasicGroup = getTdClient().onUpdate('updateBasicGroup', (u: TdObject) => {
      const basicGroup = u['basic_group'] as TdObject | undefined;
      if (basicGroup !== undefined &&
        ((basicGroup['id'] as number | undefined) ?? 0) === this.membershipBasicGroupId) {
        this.applyMembershipStatus(basicGroup['status'] as TdObject | undefined);
      }
    });
    this.refreshMembership();
    this.refreshVideoChat(true);
    this.unsubVideoChat = getTdClient().onUpdate('updateChatVideoChat', (u: TdObject) => {
      if ((u['chat_id'] as number | undefined) === this.chatId) {
        this.liveChatResolveSeq++;
        this.liveChatRefreshInFlight = false;
        this.liveLoadState = 'ready';
        const vc = u['video_chat'] as TdObject | undefined;
        this.setLiveGroupCallId(vc !== undefined ? ((vc['group_call_id'] as number | undefined) ?? 0) : 0);
        this.settleTopCardLoading();
      }
    });
    this.unsubGroupCall = getTdClient().onUpdate('updateGroupCall', (u: TdObject) => {
      const groupCall = u['group_call'] as TdObject | undefined;
      if (groupCall !== undefined &&
        ((groupCall['id'] as number | undefined) ?? 0) === this.liveGroupCallId) {
        this.liveGroupResolveSeq++;
        this.liveGroupRefreshInFlight = false;
        this.liveGroupRequestId = 0;
        this.applyLiveGroupCall(groupCall);
      }
    });
    this.livePulseTimer = setInterval((): void => {
      if (!this.liveCallIsActive || !powerFeatureEnabled(KEY_POWER_PARTICLES)) {
        this.livePulseExpanded = false;
        return;
      }
      this.livePulseExpanded = !this.livePulseExpanded;
    }, 780);
    this.powerBackgroundTimer = setInterval((): void => {
      if (powerGroupFeatureEnabled(KEY_POWER_CHAT_EFFECTS, KEY_POWER_EFFECT_BACKGROUND) ||
        powerFeatureEnabled(KEY_POWER_PARTICLES)) {
        this.powerBackgroundPhase = !this.powerBackgroundPhase;
      } else {
        this.powerBackgroundPhase = false;
      }
    }, 4200);
    // Updates remain the fast path. Polling is a small safety net for devices
    // that resume this cached page after an update was delivered while its
    // subscriptions were inactive.
    this.liveStateRefreshTimer = setInterval((): void => {
      this.refreshVideoChat();
    }, 2000);
    const store = new MessageStore(
      getTdClient(), getUserStore(), this.chatId, this.threadRootId, 30, this.forumTopicId);
    this.store = store;
    if (!scrollResumeWaiting || this.groups.length === 0) {
      this.messageLoadState = 'loading';
    }
    this.unsubMsg = store.subscribe((list: MessageEntry[]) => {
      const historyState: string = store.getInitialHistoryState();
      this.olderLoadState = store.getOlderLoadState();
      this.newerLoadState = store.getNewerLoadState();
      if (!(scrollResumeWaiting && this.groups.length > 0 && historyState === 'loading')) {
        this.messageLoadState = historyState;
        this.messageLoadError = store.getInitialHistoryError();
      }
      // Do not turn an openChat real-time update into the first positioned
      // timeline. MessageStore normally withholds these partial snapshots, and
      // this page-side guard also protects cached-page resume and future data
      // sources that may publish while their initial history is still loading.
      if (historyState === 'loading') {
        return;
      }
      // During a cached-page resume, hold the old viewport until a snapshot
      // arrives that is actually a timeline rather than a fragment of one.
      //
      // The empty-snapshot case is not the only fragment. openChat makes TDLib
      // push the newest message immediately, and its first getChatHistory reply
      // may legally contain fewer messages than asked for — and onHistory marks
      // the store 'ready' the moment that reply lands. So a one-message,
      // already-'ready' snapshot reached this point and replaced 34 rows with
      // one, which the log shows the list then rebuilding back to thirty. That
      // collapse and rebuild is the "messages scrambled after coming back from
      // the background" report.
      //
      // The test is a size collapse, not emptiness: a fragment is an order of
      // magnitude smaller than what is on screen, while messages deleted in the
      // background shrink the list by a few rows. The halving threshold draws
      // that line. It errs by holding a stale viewport for one update if more
      // than half a chat is deleted while backgrounded; the next snapshot
      // clears it.
      const fragment: boolean = this.groups.length > 0 && list.length * 2 < this.groups.length;
      if (scrollResumeWaiting && (list.length === 0 || fragment)) {
        return;
      }
      const notifyKind: string = store.getCurrentNotifyKind();
      const maxId: number = list.length > 0 ? list[list.length - 1].id : 0;
      const groups: AlbumGroup[] = this.groupsWithClientJoinNotice(list);
      let prependAnchorId: number = 0;
      let prependAnchorY: number = 0;
      if (this.didInitialScroll && this.groups.length > 0 && groups.length > this.groups.length) {
        const previousFirstIndex: number = groupIndexOf(groups, this.groups[0].head.id);
        const visibleIndex: number = this.curStartIdx;
        if (previousFirstIndex > 0 && visibleIndex >= 0 && visibleIndex < this.groups.length) {
          prependAnchorId = this.groups[visibleIndex].head.id;
          try {
            prependAnchorY = this.scroller.getItemRect(visibleIndex).y;
          } catch (e) {
            prependAnchorY = 0;
          }
        }
      }
      this.messages = list;
      this.reconcileMessageActionTargets(list);
      this.groups = groups;
      this.visibleGroupCount = groups.length;
      if (this.viewerMsgId !== 0 &&
        list.findIndex((m: MessageEntry): boolean => m.id === this.viewerMsgId) < 0) {
        this.closeViewer();
      }
      const updateKind: string = this.publishGroups(groups);
      // 翻译和媒体窗口原来只挂在 onScrollIndex 上 —— 进页面不滑动就永远不
      // 触发（用户报的"这个页面不会自动翻译"），新消息到达也一样。数据一变
      // 就按当前视口驱动一次；curStartIdx/curEndIdx 在首帧前是 -1，此时用
      // 首屏兜底，滑动事件来了会立刻纠正。
      this.driveVisibleWork();
      this.musicQueue.settlePending(list);
      // Incremental ops (the normal prepend) keep the viewport anchored via
      // maintainVisibleContentPosition; forcing scrollToIndex on top of that
      // cancelled the user's fling mid-scroll — the load-more stutter. Only a
      // RELOAD rebuild loses the anchor and needs the manual restore.
      if (prependAnchorId > 0 && updateKind === 'reload') {
        this.restorePrependAnchor(groups, prependAnchorId, prependAnchorY);
      }
      let positionHandled: boolean = false;
      if (scrollResumeWaiting && list.length > 0) {
        scrollResumeWaiting = false;
        this.resumeScrollPending = false;
        this.didInitialScroll = true;
        this.lastMaxId = maxId;
        this.firstUnreadId = 0;
        this.stayAtUnread = false;
        positionHandled = true;
        if (this.resumeScrollAtBottom) {
          this.atBottom = false;
          const actionSeq: number = ++this.scrollActionSeq;
          this.scroller.scrollEdge(Edge.Bottom);
          setTimeout((): void => {
            if (actionSeq === this.scrollActionSeq) {
              this.scroller.scrollEdge(Edge.Bottom);
              this.refreshAtBottom();
            }
          }, 60);
        } else {
          const resumeIndex: number = groupIndexOf(groups, this.resumeScrollMessageId);
          this.atBottom = false;
          if (resumeIndex >= 0) {
            this.restoreScrollAnchor(resumeIndex, this.resumeScrollItemY);
          } else {
            this.scroller.scrollEdge(Edge.Bottom);
          }
        }
      }
      // isChannel resolves asynchronously (getSupergroup round-trip) after the
      // first message page can already be showing, so refresh it every notify.
      this.isChannel = this.store !== null ? this.store.getIsChannel() : false;
      // A global-search hit opens around jumpTo and marks the initial scroll as
      // handled before history arrives. Keep the group flag independent of that
      // scroll state; otherwise every incoming bubble is rendered like a private
      // chat and its sender-avatar column is omitted.
      this.isGroup = this.store !== null ? this.store.getIsGroup() : false;
      const liveMediaIds: number[] = store.consumeLiveIncomingMediaIds();
      const autoScope: string = this.isChannel ? 'channel' : (this.isGroup ? 'group' : 'private');
      if (autosaveEnabled(autoScope)) {
        for (const mediaId of liveMediaIds) {
          if (this.autoSavePendingIds.indexOf(mediaId) < 0) {
            this.autoSavePendingIds.push(mediaId);
          }
        }
      }
      // Private peer resolved: probe once for commands. The centralized loader
      // also serves '/' autocomplete, so fast typing cannot start a competing
      // request that overwrites a newer result.
      if (this.commandLoadState === 'idle' && this.store !== null &&
        this.store.getPeerUserId() > 0) {
        this.ensureCommandsLoaded();
      }
      if (!positionHandled && !this.didInitialScroll && list.length > 0) {
        // First real page: jump to the first unread message (Android-style);
        // fully-read chats land at the bottom. (Never anchor on
        // last_read_inbox_message_id here — it only tracks incoming messages,
        // so with an outgoing tail it points at a stale mid-history position.)
        this.didInitialScroll = true;
        this.lastMaxId = maxId;
        const fu: number = this.store !== null ? this.store.getFirstUnreadId() : 0;
        const gidx: number = fu > 0 ? groupIndexOf(groups, fu) : -1;
        this.firstUnreadId = fu > 0 && gidx >= 0 ? groups[gidx].head.id : 0;
        if (gidx >= 0) {
          // Landing mid-history at the unread boundary: atBottom defaults to
          // true, and the bottom-glue branch below would otherwise drag the
          // view to the tail (chain-loading every newer page) before the
          // first scroll event corrects it.
          this.atBottom = false;
          // With only a few unread, ScrollAlign.START can't lift the boundary to
          // the top (too little content below), so it lands near the bottom and
          // the last group becomes visible — onScrollIndex then flips atBottom
          // back to true, and the very next in-place notify (thumbnails/reply
          // quotes filling in) would glue us to the tail, skipping past the
          // unread divider. Latch here so no auto-scroll overrides the boundary
          // until the user actually touches the list.
          this.stayAtUnread = true;
          this.scroller.scrollToIndex(gidx, false, ScrollAlign.START);
        } else {
          this.scroller.scrollEdge(Edge.Bottom);
        }
      } else if (!positionHandled && this.didInitialScroll && maxId > this.lastMaxId) {
        // Only follow to the bottom for genuinely new messages AND only when the
        // user is already near the bottom — never yank them down while they read
        // history or on photo/read-receipt updates.
        // Mark the arrivals as fresh for a beat so their bubbles gently enter;
        // rows rebuilt while scrolling history never animate.
        if (notifyKind === 'update') {
          this.freshSinceId = this.lastMaxId;
          const clearSeq = ++this.freshClearSeq;
          setTimeout(() => {
            if (clearSeq === this.freshClearSeq) {
              this.freshSinceId = 0;
            }
          }, 1500);
        }
        this.lastMaxId = maxId;
        // Never follow while parked at the unread boundary (until the user
        // touches) or while the fullscreen viewer is open — the chat should
        // return to the same underlying message after the preview closes.
        if (notifyKind === 'update' && this.atBottom && !this.stayAtUnread && this.viewerMsgId === 0) {
          this.scroller.scrollEdge(Edge.Bottom);
        }
      } else if (this.didInitialScroll && this.atBottom && !this.stayAtUnread && this.viewerMsgId === 0
        && (this.store === null || !this.store.getHasMoreNewer())) {
        // In-place content growth (thumbnails, reply quotes, forward headers
        // filling in async) changes row heights; when the user is at the
        // bottom, stay glued there instead of letting the tail drift. Never
        // glue while unloaded newer pages exist — being at the window's edge
        // there is NOT the live tail, and gluing chain-loads every page.
        // Also never move the underlying list while the media viewer is open.
        this.scroller.scrollEdge(Edge.Bottom);
      }
      // jumpToLatest's newest page arrived — snap to the end. The dataset was
      // just replaced wholesale, so scroll once now and once after the List has
      // laid the new rows out: the immediate call alone lands at the top of the
      // reloaded page because the final row heights aren't known yet.
      if (this.pendingScrollBottom && list.length > 0) {
        this.pendingScrollBottom = false;
        this.lastMaxId = maxId;
        this.atBottom = true;
        const actionSeq: number = this.scrollActionSeq;
        this.scroller.scrollEdge(Edge.Bottom);
        setTimeout(() => {
          if (actionSeq === this.scrollActionSeq) {
            this.scroller.scrollEdge(Edge.Bottom);
            this.refreshAtBottom();
          }
        }, 60);
      }
      if (notifyKind === 'newer') {
        // An empty newer page is the signal that this history window has
        // reached the live tail. Re-evaluate after layout even when no visible
        // index changed, otherwise the down button can remain stuck onscreen.
        setTimeout((): void => {
          if (this.store === store) {
            this.refreshAtBottom();
          }
        }, 0);
      }
      // A viewer item queued for gallery save finished downloading — always
      // prefer the original photo rather than silently saving its thumbnail.
      if (this.pendingGallerySaveId !== 0) {
        const pe = list.find((m: MessageEntry) => m.id === this.pendingGallerySaveId);
        if (pe !== undefined) {
          if (this.mediaEntryIsVideo(pe) && pe.videoPath !== '') {
            this.pendingGallerySaveId = 0;
            saveMediaToGallery(getContext(this) as common.UIAbilityContext, pe.videoPath, true);
          } else if (this.mediaEntryIsVideo(pe) && pe.videoFailed) {
            this.pendingGallerySaveId = 0;
            promptAction.showToast({ message: $r('app.string.cp_video_download_failed'), duration: 1800 });
          } else if (this.mediaEntryIsPhoto(pe) && pe.photoFullPath !== '') {
            this.pendingGallerySaveId = 0;
            saveMediaToGallery(getContext(this) as common.UIAbilityContext, pe.photoFullPath, false);
          } else if (this.mediaEntryIsPhoto(pe) && pe.photoFullFailed) {
            this.pendingGallerySaveId = 0;
            promptAction.showToast({ message: $r('app.string.cp_photo_download_failed'), duration: 1800 });
          }
        }
      }
      this.processAutomaticGallerySave(list);
      // A document queued for "save as" finished downloading — open the picker.
      if (this.pendingFileOpenId !== 0) {
        const openEntry: MessageEntry | undefined =
          list.find((m: MessageEntry): boolean => m.id === this.pendingFileOpenId);
        if (openEntry === undefined || openEntry.contentType !== 'file') {
          this.pendingFileOpenId = 0;
        } else if (openEntry.videoFailed) {
          this.pendingFileOpenId = 0;
          promptAction.showToast({ message: $r('app.string.cp_file_download_failed'), duration: 1800 });
        } else if (openEntry.videoPath !== '') {
          this.pendingFileOpenId = 0;
          this.openDownloadedFile(openEntry);
        }
      }
      if (this.pendingFileSaveId !== 0) {
        const fe = list.find((m: MessageEntry) => m.id === this.pendingFileSaveId);
        if (fe === undefined || fe.contentType !== 'file') {
          this.pendingFileSaveId = 0;
        } else if (fe.videoFailed) {
          this.pendingFileSaveId = 0;
          promptAction.showToast({ message: $r('app.string.cp_file_download_failed_save'), duration: 1800 });
        } else if (fe.videoPath !== '') {
          this.pendingFileSaveId = 0;
          saveFileToLocal(getContext(this) as common.UIAbilityContext, fe.videoPath, fe.videoFileName);
        }
      }
      // A pinned/quoted jump target that had to be loaded has now arrived — scroll to it.
      if (this.pendingJumpId !== 0) {
        const jumpTargetId: number = this.pendingJumpId;
        const jg: number = groupIndexOf(groups, jumpTargetId);
        if (jg >= 0) {
          this.pendingJumpId = 0;
          this.finishPinnedJump();
          this.scroller.scrollToIndex(jg, false, ScrollAlign.START);
          // loadAround replaces the window wholesale (list RELOAD) — the
          // immediate scroll can be swallowed before the new rows lay out.
          // Re-issue once layout settles (index recomputed: prepends may have
          // shifted it) and flash after that.
          const jumpSeq: number = ++this.jumpLayoutSeq;
          setTimeout(() => {
            if (jumpSeq !== this.jumpLayoutSeq) {
              return;
            }
            const jg2: number = groupIndexOf(this.groups, jumpTargetId);
            if (jg2 >= 0) {
              this.scroller.scrollToIndex(jg2, false, ScrollAlign.START);
              this.flashAtIndex(jg2);
            }
          }, 80);
        }
      }
    });
    this.unsubSub = store.subscribeSubtitle((s: string) => {
      this.subtitle = s;
      this.fetchHeaderEmojiStatus();
    });
    this.unsubHeaderTitle = store.subscribeHeaderTitle((t: string) => {
      // Fallback header for chats not yet in ChatStore (e.g. opened by t.me link).
      if (t !== '') {
        if (this.threadRootId === 0 && this.forumTopicId === 0) {
          this.title = t;
        }
        this.initials = computeInitials(t);
        this.headerState = 'ready';
        this.headerLoadError = '';
      }
    });
    this.unsubHeaderAvatar = store.subscribeHeaderAvatar((p: string) => {
      if (p !== '') {
        this.avatarPath = p;
        // MessageStore resolves the chat photo independently of ChatStore/FileService
        // (e.g. for a channel only ever surfaced under a folder tab, whose avatar
        // download may never have fired/retried there) — backfill the list entry too,
        // so the chat list shows the avatar without depending on that separate path.
        getChatStore().setAvatarPath(this.chatId, p);
      }
    });
    this.unsubReplyKb = store.subscribeReplyKeyboard((kb: ReplyKeyboard | null) => {
      const prevId = this.replyKeyboard !== null ? this.replyKeyboard.messageId : 0;
      const newId = kb !== null ? kb.messageId : 0;
      if (newId !== prevId) {
        // Present an initial/fresh keyboard, but never yank the composer away
        // while the user is already typing or browsing media.
        this.replyKbCollapsed = this.composerFocused || this.showEmojiPanel;
      }
      this.replyKeyboard = kb;
      if (kb === null) {
        this.replyKbH = 0;
        this.replyKeyboardSendingKey = '';
      }
    });
    this.unsubPinned = store.subscribePinned((s: string) => {
      this.pinnedPreview = s;
      this.pinnedCount = store.getPinnedIds().length;
      this.pinnedLoadState = store.getPinnedLoadState();
      this.pinnedCycle = Math.min(this.pinnedCycle, Math.max(0, this.pinnedCount - 1));
      if (this.pinnedCount === 0) {
        this.pinnedCycle = 0;
        this.finishPinnedJump();
      }
      this.settleTopCardLoading();
    });
    if (scrollResumeWaiting) {
      // Re-open around the captured row unless the old viewport was already
      // at the true live tail, in which case the newest page is sufficient.
      store.open(this.resumeScrollAtBottom || this.resumeScrollMessageId <= 0
        ? undefined : this.resumeScrollMessageId);
    } else if (jumpTo !== undefined && jumpTo > 0) {
      // Opened via a message link: load straight around the target message,
      // without racing an additional latest-history request.
      this.didInitialScroll = true;
      this.pendingJumpId = jumpTo;
      store.open(jumpTo);
    } else if (this.threadRootId > 0) {
      // Comment thread: start at the TOP — the root post — not the newest reply.
      this.didInitialScroll = true;
      this.pendingJumpId = this.threadRootId;
      store.open(this.threadRootId);
    } else {
      store.open();
    }
    if (this.searchMode && this.searchQuery !== '') {
      // Let the initial history land first — runSearch jumps to the newest hit,
      // and that jump would otherwise be undone by the initial scroll-to-bottom.
      setTimeout(() => {
        if (this.searchMode) {
          this.runSearch(0, 0);
        }
      }, SEARCH_ENTRY_DELAY_MS);
    }
  }

  // nowSec 驱动实时位置的倒计时和"已结束"判定，以及消息时间的相对显示。
  // 以前只在 aboutToAppear 赋值一次，于是共享结束后必须重进会话才看得出来。
  // 30 秒一跳：这些标签都是分钟粒度的，再密只是白白唤醒渲染。
  private armNowSecTimer(): void {
    if (this.nowSecTimer !== -1) {
      return;
    }
    this.nowSecTimer = setInterval((): void => {
      this.nowSec = Math.floor(Date.now() / 1000);
    }, NOW_SEC_TICK_MS);
  }

  private clearNowSecTimer(): void {
    if (this.nowSecTimer !== -1) {
      clearInterval(this.nowSecTimer);
      this.nowSecTimer = -1;
    }
  }

  // 停止共享是不可撤销的：一旦结束，那条消息就再也编辑不回来了（服务端直接
  // 判定为不可编辑），只能重新发一条。所以先确认。
  private confirmStopLiveLocation(): void {
    promptAction.showDialog({
      title: $r('app.string.cp_stop_live_location'),
      message: $r('app.string.cp_stop_live_location_body'),
      buttons: [
        { text: $r('app.string.cancel'), color: '#8E8E93' },
        { text: $r('app.string.cp_stop_sharing'), color: '#D95B57' }
      ]
    }).then((result: promptAction.ShowDialogSuccessResponse): void => {
      if (result.index !== 1) {
        return;
      }
      liveLocation.stopSharing();
      promptAction.showToast({ message: $r('app.string.cp_live_location_stopped'), duration: 1500 });
    }).catch((e: Object): void => {
      console.error(`ChatPage.confirmStopLiveLocation failed: ${JSON.stringify(e)}`);
    });
  }

  // 驻留判定是逐候选的，onVisibleAreaApproximateChange 只在跨阈值时触发——
  // 一条视频稳稳停着反而不再有任何回调，所以判定不能只靠回调推动。这里用
  // PlaySlotRegistry.nextCheckDelay() 查询"还有候选没攒满 PLAY_SLOT_DWELL_MS"，
  // 有就排一个一次性定时器，到点再 tick() 一次；没有就什么也不做。
  // scheduleSlotTick 只留一个在途定时器，重复调用安全。
  private scheduleSlotTick(delayMs: number): void {
    this.clearSlotTick();
    this.slotTickTimer = setTimeout((): void => {
      this.slotTickTimer = -1;
      const now = Date.now();
      this.playSlots.tick(now);
      this.maybeScheduleNextSlotCheck(now);
    }, delayMs + 10);
  }

  private clearSlotTick(): void {
    if (this.slotTickTimer !== -1) {
      clearTimeout(this.slotTickTimer);
      this.slotTickTimer = -1;
    }
  }

  // nextCheckDelay() < 0 表示没有候选正在攒驻留（要么无候选达标，要么都已
  // 达标或已经是现任/被 pin），此时什么也不用排。
  private maybeScheduleNextSlotCheck(now: number): void {
    const delay = this.playSlots.nextCheckDelay(now);
    if (delay >= 0) {
      this.scheduleSlotTick(delay);
    }
  }

  // 幂等的"补一次判定"：可以随便重复调用，不需要一次性 flag 挡着。立即跑
  // 一次 tick（用于候选表在此刻已经攒够驻留、只是没有新的可见区回调触发
  // 判定的情况，比如 onPageShow/closeViewer 这类没有新 ratio 上报的恢复路
  // 径），再排一次后续检查。调用点见 driveVisibleWork()/onScrollIndex()/
  // onPageShow()/closeViewer()——任何一次因为候选表还没填满（消息还没到、
  // ratio 还没上报、被查看器盖住清空过）而选不出播放位，都会被下一次自然
  // 发生的调用或已排的定时器补上，不会永久卡死。
  //
  // 守卫：查看器开着，或页面本身不可见时，直接不喂——List/气泡全程挂载，
  // 这两种状态下即便候选表被后台悄悄填回来，也绝不能真的选出播放位去挂
  // 播放器/拉下载（分别是 Critical-2 和 Important-3 的核心不变量）。
  // closeViewer()/onPageShow() 这两条恢复路径都是先把状态改回"已关闭/
  // 可见"再调这个方法，守卫在它们那次调用里天然放行。
  private armPlaySlotSettle(): void {
    if (this.viewerMsgId !== 0 || !this.pageVisible || !this.playSlotsEnabled()) {
      return;
    }
    const now = Date.now();
    // 恢复路径（closeViewer / onPageShow）走到这里时候选表还在（suspend()
    // 保留了它），只是驻留计时被清了；resume() 按此刻重新起算，之后正常
    // 攒满 PLAY_SLOT_DWELL_MS 就能自然选出播放位，不需要用户手动滑一下。
    // 非恢复路径上 resume() 是空操作（见 PlaySlotRegistry.resume）。
    this.playSlots.resume(now);
    this.playSlots.tick(now);
    this.maybeScheduleNextSlotCheck(now);
  }

  // 播放位竞选的总闸门：「自动播放视频」关掉、省电模式开启、减少动效开启，
  // 三者任一成立就完全不竞选 —— 不挂播放器，更不发起任何分片下载。
  // 判定本身是纯函数 shouldCompete()（见 playSlot.ets），这里只是把三个
  // @StorageProp 喂给它。isAnimation 传 false：这是页面级闸门，动图本来就
  // 不参加竞选，由 MessageBubble.isPlaySlot()/isAlbumCellPlaySlot() 兜底。
  private playSlotsEnabled(): boolean {
    return shouldCompete(this.autoplayVideo, this.powerSaving, this.reduceAnimations, false);
  }

  // 三个开关任一变化：关掉就立刻把正在播的那条停掉（reset() 会把播放位置空，
  // 订阅者把 playSlotKey 清成 ''，气泡的 VideoBubbleSurface 随之卸载 →
  // StreamingVideoPlayer.aboutToDisappear → release() → session.close()，
  // 播放和下载一起停）；重新打开则补一次判定让它自然重新选出来。
  private onAutoplayPolicyChanged(): void {
    if (!this.playSlotsEnabled()) {
      this.clearSlotTick();
      this.playSlots.reset();
      return;
    }
    this.armPlaySlotSettle();
  }

  onPageHide(): void {
    console.info(`[ChatDiag] hide msgs=${this.messages.length} groups=${this.groups.length} ds=${this.groupsData.totalCount()}`);
    this.pageVisible = false;
    // 页面不可见时停表，回来时补一次即时值再续上。
    this.clearNowSecTimer();
    // 切走（含被查看器等页面盖住）立刻停播放位——不能等 aboutToDisappear，
    // 那要等到组件真被销毁才会跑，用户已经在别的页面上等了半天下载还在跑。
    this.clearSlotTick();
    this.playSlots.suspend();
  }

  onPageShow(): void {
    this.pageVisible = true;
    // onPageHide 只 suspend() 了播放位：候选表还在，被清掉的是当前播放位和
    // 驻留计时。回到这个页面时几何没变、onVisibleAreaApproximateChange 不会
    // 再触发，候选表也就不会被重新灌满——保留候选正是为了这一刻还能选得出
    // 来。armPlaySlotSettle() 里的 resume() 按此刻重新起算驻留，稳住 400ms
    // 后自然选出播放位。
    this.armPlaySlotSettle();
    // The list changed while this page was hidden. See hiddenListDirty: the
    // framework applies hidden-period notifications incompletely, so rebuild
    // its key table from the dataset before the user can see mismatched rows.
    if (this.hiddenListDirty) {
      this.hiddenListDirty = false;
      this.resyncListAfterHidden();
    }
    this.nowSec = Math.floor(Date.now() / 1000);
    this.armNowSecTimer();
    // The chat page is cached underneath the live viewer. A successful
    // pushUrl can therefore leave the entry button in its transient busy
    // state when this page becomes visible again. Treat page visibility as
    // the end of navigation and re-confirm the current call state.
    this.liveDialogOpening = false;
    this.liveNavigationBusy = false;
    if (this.chatId > 0) {
      this.refreshVideoChat();
    }
  }

  aboutToDisappear(): void {
    // 退出会话时播放器可能还开着（返回手势不走 closeViewer），为播放拉起的
    // 下载得在这里也停掉，否则回到列表页它还在后台跑。
    this.releasePlaybackRequests();
    this.clearSlotTick();
    this.playSlots.reset();
    // 进度表只在这一次会话内有意义（交接回全屏查看器/回到播放位），会话
    // 结束就清空，避免长会话里随刷屏无界增长。
    this.bubblePositionMs.clear();
    if (this.unsubPlaySlot !== null) {
      this.unsubPlaySlot();
      this.unsubPlaySlot = null;
    }
    if (this.cachedCountTimer !== -1) {
      clearTimeout(this.cachedCountTimer);
      this.cachedCountTimer = -1;
    }
    if (this.bgRasterTimer !== -1) {
      clearTimeout(this.bgRasterTimer);
      this.bgRasterTimer = -1;
    }
    this.clearNowSecTimer();
    if (this.unsubChatAction !== null) {
      this.unsubChatAction();
      this.unsubChatAction = null;
    }
    if (this.typingTimer !== -1) {
      clearInterval(this.typingTimer);
      this.typingTimer = -1;
    }
    // Sync the composer draft to the account (other devices see it). While an
    // edit is in progress the real draft is the stashed pre-edit text.
    this.store?.saveDraft(
      this.editingId !== 0 ? this.draftBeforeEdit : this.draft, this.replyToId
    );
    this.exitViewerLandscape();
    this.captureScrollResume();
    this.bottomChromeLayoutSeq++;
    this.imeTailPinned = false;
    this.imeLayoutSeq++;
    this.headerResolveSeq++;
    this.headerMenuShow = false;
    this.showReactionSheet = false;
    this.reactionTargetId = 0;
    this.closeForwardSheet();
    this.headerProfileOpening = false;
    this.headerMuteUpdating = false;
    this.pageClosing = false;
    this.headerVisible = false;
    this.liveChatResolveSeq++;
    this.liveGroupResolveSeq++;
    this.liveChatRefreshInFlight = false;
    this.liveGroupRefreshInFlight = false;
    this.liveGroupRequestId = 0;
    this.liveDialogOpening = false;
    this.liveNavigationBusy = false;
    this.pinnedJumpBusy = false;
    this.topCardLoadingVisible = false;
    this.scrollActionSeq++;
    this.jumpLayoutSeq++;
    this.prependRestoreSeq++;
    this.scrollToBottomBusy = false;
    this.pendingScrollBottom = false;
    this.clearFloatingDate();
    if (this.headerNavigationTimer !== -1) {
      clearTimeout(this.headerNavigationTimer);
      this.headerNavigationTimer = -1;
    }
    if (this.headerEntranceTimer !== -1) {
      clearTimeout(this.headerEntranceTimer);
      this.headerEntranceTimer = -1;
    }
    if (this.topCardLoadingTimer !== -1) {
      clearTimeout(this.topCardLoadingTimer);
      this.topCardLoadingTimer = -1;
    }
    if (this.topCardActionTimer !== -1) {
      clearTimeout(this.topCardActionTimer);
      this.topCardActionTimer = -1;
    }
    this.cancelRecording();
    this.pendingFileOpenId = 0;
    this.pendingFileSaveId = 0;
    this.fileOpenInFlightId = 0;
    this.musicQueue.reset();
    this.autoSavePendingIds = [];
    this.autoSaveInFlight = false;
    getVoicePlayback().setMusicCompletionListener(null);
    getVoicePlayback().stop();
    if (this.unsubMsg !== null) { this.unsubMsg(); this.unsubMsg = null; }
    if (this.unsubSub !== null) { this.unsubSub(); this.unsubSub = null; }
    if (this.unsubChat !== null) { this.unsubChat(); this.unsubChat = null; }
    if (this.unsubLiveLocation !== null) {
      this.unsubLiveLocation();
      this.unsubLiveLocation = null;
    }
    if (this.unsubTranslatable !== null) {
      this.unsubTranslatable();
      this.unsubTranslatable = null;
    }
    if (this.unsubBg !== null) {
      this.unsubBg();
      this.unsubBg = null;
    }
    if (this.bgStore !== null) {
      this.bgStore.close();
      this.bgStore = null;
    }
    if (this.unsubPinned !== null) { this.unsubPinned(); this.unsubPinned = null; }
    if (this.unsubHeaderAvatar !== null) { this.unsubHeaderAvatar(); this.unsubHeaderAvatar = null; }
    if (this.unsubHeaderTitle !== null) { this.unsubHeaderTitle(); this.unsubHeaderTitle = null; }
    if (this.unsubReplyKb !== null) { this.unsubReplyKb(); this.unsubReplyKb = null; }
    if (this.unsubMembershipSupergroup !== null) {
      this.unsubMembershipSupergroup();
      this.unsubMembershipSupergroup = null;
    }
    if (this.unsubMembershipBasicGroup !== null) {
      this.unsubMembershipBasicGroup();
      this.unsubMembershipBasicGroup = null;
    }
    this.membershipSeq++;
    if (this.unsubVideoChat !== null) { this.unsubVideoChat(); this.unsubVideoChat = null; }
    if (this.unsubGroupCall !== null) { this.unsubGroupCall(); this.unsubGroupCall = null; }
    if (this.livePulseTimer !== -1) { clearInterval(this.livePulseTimer); this.livePulseTimer = -1; }
    if (this.powerBackgroundTimer !== -1) {
      clearInterval(this.powerBackgroundTimer);
      this.powerBackgroundTimer = -1;
    }
    if (this.liveStateRefreshTimer !== -1) {
      clearInterval(this.liveStateRefreshTimer);
      this.liveStateRefreshTimer = -1;
    }
    if (this.store !== null) { this.store.close(); this.store = null; }
  }

  private resetTopCardState(): void {
    this.liveChatResolveSeq++;
    this.liveGroupResolveSeq++;
    this.pinnedPreview = '';
    this.pinnedCount = 0;
    this.pinnedCycle = 0;
    this.pinnedLoadState = this.threadRootId > 0 ? 'ready' : 'loading';
    this.pinnedJumpBusy = false;
    this.liveGroupCallId = 0;
    this.liveCallIsActive = false;
    this.liveCallIsRtmp = false;
    this.liveParticipantCount = 0;
    this.livePulseExpanded = false;
    this.liveLoadState = 'loading';
    this.liveDialogOpening = false;
    this.liveNavigationBusy = false;
    this.liveChatRefreshInFlight = false;
    this.liveGroupRefreshInFlight = false;
    this.liveGroupRequestId = 0;
    this.topCardLoadingVisible = false;
    if (this.topCardLoadingTimer !== -1) {
      clearTimeout(this.topCardLoadingTimer);
    }
    this.topCardLoadingTimer = setTimeout((): void => {
      this.topCardLoadingTimer = -1;
      this.topCardLoadingVisible =
        this.pinnedLoadState === 'loading' || this.liveLoadState === 'loading';
    }, powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, TOP_CARD_LOADING_DELAY_MS));
  }

  private settleTopCardLoading(): void {
    if (this.pinnedLoadState === 'loading' || this.liveLoadState === 'loading') {
      return;
    }
    if (this.topCardLoadingTimer !== -1) {
      clearTimeout(this.topCardLoadingTimer);
      this.topCardLoadingTimer = -1;
    }
    this.topCardLoadingVisible = false;
  }

  private topCardHasContent(): boolean {
    return this.pinnedPreview !== '' ||
      (this.liveGroupCallId > 0 && this.liveCallIsActive);
  }

  private topCardShouldShow(): boolean {
    // Pinned/live information is optional chrome. If its background probe
    // fails while TDLib is reconnecting and there is no confirmed content,
    // don't turn that transient transport problem into a persistent banner.
    return this.topCardHasContent() || this.topCardLoadingVisible;
  }

  // Resolve chat.video_chat first, then the referenced group call. Sequence
  // guards make a late response from a previous call/chat unable to restore a
  // banner that has already ended or changed identity.
  private refreshVideoChat(showLoading: boolean = false): void {
    if (this.chatId === 0) {
      this.liveLoadState = 'error';
      this.settleTopCardLoading();
      return;
    }
    if (this.liveChatRefreshInFlight) {
      return;
    }
    this.liveChatRefreshInFlight = true;
    const seq: number = ++this.liveChatResolveSeq;
    if (showLoading && !this.liveCallIsActive) {
      this.liveLoadState = 'loading';
    }
    const req: TdRequest = { '@type': 'getChat' };
    req['chat_id'] = this.chatId;
    getTdClient().send(req).then((chat: TdObject): void => {
      if (seq !== this.liveChatResolveSeq) {
        return;
      }
      this.liveChatRefreshInFlight = false;
      this.liveLoadState = 'ready';
      const vc = chat['video_chat'] as TdObject | undefined;
      this.setLiveGroupCallId(vc !== undefined ? ((vc['group_call_id'] as number | undefined) ?? 0) : 0);
      this.settleTopCardLoading();
    }).catch((e: TdError): void => {
      if (seq !== this.liveChatResolveSeq) {
        return;
      }
      this.liveChatRefreshInFlight = false;
      // A transient refresh failure must not invalidate an active call already
      // confirmed by ChatStore/updateGroupCall.
      if (!this.liveCallIsActive) {
        this.liveLoadState = 'error';
      }
      this.settleTopCardLoading();
      console.error(`ChatPage.refreshVideoChat getChat failed: ${e.message}`);
    });
  }

  private setLiveGroupCallId(groupCallId: number): void {
    const changed = groupCallId !== this.liveGroupCallId;
    if (changed) {
      this.liveGroupResolveSeq++;
      this.liveGroupRefreshInFlight = false;
      this.liveGroupRequestId = 0;
      this.liveGroupCallId = groupCallId;
      this.liveCallIsActive = false;
      this.liveCallIsRtmp = false;
      this.liveParticipantCount = 0;
      this.livePulseExpanded = false;
    }
    if (groupCallId <= 0) {
      this.liveLoadState = 'ready';
      this.settleTopCardLoading();
      return;
    }
    // An unchanged id still needs refreshing because a scheduled call may
    // become active (or an active call end) without changing its identifier.
    if (this.liveGroupRefreshInFlight && this.liveGroupRequestId === groupCallId) {
      return;
    }
    const seq: number = ++this.liveGroupResolveSeq;
    this.liveGroupRefreshInFlight = true;
    this.liveGroupRequestId = groupCallId;
    if (!this.liveCallIsActive) {
      this.liveLoadState = 'loading';
    }
    const request: TdRequest = { '@type': 'getGroupCall' };
    request['group_call_id'] = groupCallId;
    getTdClient().send(request).then((groupCall: TdObject): void => {
      if (seq !== this.liveGroupResolveSeq || this.liveGroupCallId !== groupCallId) {
        return;
      }
      this.liveGroupRefreshInFlight = false;
      this.liveGroupRequestId = 0;
      this.applyLiveGroupCall(groupCall);
    }).catch((error: TdError): void => {
      if (seq !== this.liveGroupResolveSeq || this.liveGroupCallId !== groupCallId) {
        return;
      }
      this.liveGroupRefreshInFlight = false;
      this.liveGroupRequestId = 0;
      if (!this.liveCallIsActive) {
        this.liveLoadState = 'error';
      }
      this.settleTopCardLoading();
      console.error(`ChatPage.getGroupCall failed: ${error.message}`);
    });
  }

  private applyLiveGroupCall(groupCall: TdObject): void {
    this.liveCallIsActive = (groupCall['is_active'] as boolean | undefined) ?? false;
    this.liveCallIsRtmp = (groupCall['is_rtmp_stream'] as boolean | undefined) ?? false;
    this.liveParticipantCount = (groupCall['participant_count'] as number | undefined) ?? 0;
    this.liveLoadState = 'ready';
    if (!this.liveCallIsActive) {
      this.livePulseExpanded = false;
      this.liveDialogOpening = false;
    }
    this.settleTopCardLoading();
  }

  private enterLiveStream(groupCallId: number): void {
    if (this.liveNavigationBusy) {
      return;
    }
    if (groupCallId <= 0 || groupCallId !== this.liveGroupCallId ||
      !this.liveCallIsActive || this.liveLoadState === 'error') {
      promptAction.showToast({ message: $r('app.string.cp_live_ended'), duration: 1500 });
      return;
    }
    const isRtmp: boolean = this.liveCallIsRtmp;
    const params: Record<string, Object> = {
      'groupCallId': groupCallId,
      'chatId': this.chatId,
      'initialTitle': this.title,
      'initialParticipantCount': this.liveParticipantCount
    };
    this.liveNavigationBusy = true;
    // Returning to the live stream that is already floating must hand the
    // existing Session back to the viewer. Closing it here would briefly leave
    // the call and force the page to join again.
    if (floatingLiveWindow.isShowing(groupCallId, isRtmp)) {
      floatingLiveWindow.restoreFullPage().finally((): void => {
        this.liveNavigationBusy = false;
      });
      return;
    }
    floatingLiveWindow.prepareForOpeningFullPage().finally((): void => {
      if (groupCallId !== this.liveGroupCallId || !this.liveCallIsActive) {
        this.liveNavigationBusy = false;
        promptAction.showToast({ message: $r('app.string.cp_live_ended'), duration: 1500 });
        return;
      }
      router.pushUrl({
        url: isRtmp
          ? 'pages/chat/RtmpLiveStreamViewerPage' : 'pages/chat/LiveStreamViewerPage',
        params: params
      }).then((): void => {
        // Busy only represents the route transition. Joining/recovery status
        // belongs to the viewer and must not leak into the chat banner.
        this.liveNavigationBusy = false;
      }).catch((error: Error): void => {
        this.liveNavigationBusy = false;
        console.error(`ChatPage.enterLiveStream failed: ${error.message}`);
        promptAction.showToast({ message: $r('app.string.cp_live_join_failed'), duration: 1600 });
      });
    });
  }

  // All live entry points confirm before joining. The viewer itself joins
  // muted, so the dialog can state the privacy behavior precisely.
  private onLiveStreamTap(): void {
    if (this.liveDialogOpening || this.liveNavigationBusy) {
      return;
    }
    if (this.liveLoadState === 'loading') {
      promptAction.showToast({ message: $r('app.string.cp_live_syncing'), duration: 1200 });
      return;
    }
    if (this.liveLoadState === 'error') {
      this.refreshVideoChat(true);
      promptAction.showToast({ message: $r('app.string.cp_live_refetching'), duration: 1200 });
      return;
    }
    if (this.liveGroupCallId <= 0 || !this.liveCallIsActive) {
      promptAction.showToast({ message: $r('app.string.cp_live_ended'), duration: 1500 });
      return;
    }
    const groupCallId = this.liveGroupCallId;
    const onlineText = this.liveParticipantCount > 0 ? plural('cp_live_online_now', this.liveParticipantCount, this.liveParticipantCount) : '';
    // str(), not $r(): this is concatenated into the dialog's message below, and
    // a Resource in a template literal stringifies to "[object Object]".
    const privacyText: string = this.liveCallIsRtmp
      ? str('cp_live_one_way_body')
      : str('cp_live_two_way_body');
    this.liveDialogOpening = true;
    promptAction.showDialog({
      title: $r('app.string.cp_live_join_title'),
      message: `${onlineText}${privacyText}`,
      buttons: [
        { text: $r('app.string.cancel'), color: '#8E8E93' },
        { text: $r('app.string.cp_live_join'), color: '#FF405C' }
      ]
    }).then((result): void => {
      this.liveDialogOpening = false;
      if (result.index === 1) { this.enterLiveStream(groupCallId); }
    }).catch((error: Object): void => {
      this.liveDialogOpening = false;
      console.error(`ChatPage live confirmation failed: ${JSON.stringify(error)}`);
    });
  }

  // True-bottom detection off the scroller's end edge, not the visible index
  // range: a single tall last message can be scrolled within without changing
  // any index, so an index-based check leaves atBottom stuck true and the glue
  // keeps snapping back down. Frozen while the media viewer is open so the
  // underlying chat position is stable when the preview closes.
  // 首屏之后再把预建行数补回来。用一次性定时器而不是直接赋值：onScrollIndex
  // 在首帧就会触发，那时提高 cachedCount 等于把省下的工作原样搬回同一帧。
  private growCachedCount(): void {
    if (this.listCachedCount >= LIST_CACHED_COUNT || this.cachedCountTimer !== -1) {
      return;
    }
    this.cachedCountTimer = setTimeout((): void => {
      this.cachedCountTimer = -1;
      this.listCachedCount = LIST_CACHED_COUNT;
    }, CACHED_COUNT_GROW_MS);
  }

  private refreshAtBottom(): void {
    if (this.viewerMsgId === 0) {
      // During an IME resize the last row is briefly clipped before List has
      // received its new height. Keep the pre-focus verdict until the layout
      // settles; a real list touch clears imeTailPinned first.
      if (this.imeTailPinned) {
        if (!this.atBottom) {
          this.atBottom = true;
        }
        return;
      }
      // The end of a loadAround window is not the live end of the chat. Keep
      // the down button available until MessageStore has actually exhausted
      // newer history.
      const nextAtBottom = this.scroller.isAtEnd() &&
        (this.store === null || !this.store.getHasMoreNewer());
      if (this.atBottom !== nextAtBottom) {
        this.atBottom = nextAtBottom;
      }
    }
  }

  private syncTailAfterImeResize(releaseAfter: boolean = false): void {
    if (!this.imeTailPinned || this.viewerMsgId !== 0) {
      return;
    }
    const seq: number = ++this.imeLayoutSeq;
    this.atBottom = true;
    this.stayAtUnread = false;
    // First pass follows the current resize frame; the second pass catches the
    // final List measurement after the system IME animation has settled.
    setTimeout((): void => {
      if (seq === this.imeLayoutSeq && this.imeTailPinned) {
        this.scroller.scrollEdge(Edge.Bottom);
      }
    }, 0);
    setTimeout((): void => {
      if (seq !== this.imeLayoutSeq || !this.imeTailPinned) {
        return;
      }
      this.scroller.scrollEdge(Edge.Bottom);
      this.atBottom = true;
      if (releaseAfter) {
        this.imeTailPinned = false;
      }
    }, releaseAfter ? 180 : 80);
  }

  private syncTailOnImeFrame(): void {
    if (!this.imeTailPinned || this.viewerMsgId !== 0) {
      return;
    }
    this.atBottom = true;
    this.stayAtUnread = false;
    this.scroller.scrollEdge(Edge.Bottom);
  }

  private onKeyboardHeightChanged(): void {
    const wasVisible: boolean = this.lastKeyboardH > 0;
    const visible: boolean = this.keyboardH > 0;
    if (!wasVisible && visible && !this.imeTailPinned) {
      this.imeTailPinned = this.composerFocused && this.atBottom &&
        this.viewerMsgId === 0 && !this.stayAtUnread;
    }
    this.lastKeyboardH = this.keyboardH;
    if (this.imeTailPinned) {
      if (visible) {
        // keyboardHeightChange follows the system IME animation. Keep the
        // message tail on the same layout frame instead of adding a separate
        // delayed scroll animation with a visibly different velocity.
        this.syncTailOnImeFrame();
      } else {
        // Closing already tracks naturally; retain one settled correction for
        // the final navigation-inset layout.
        this.syncTailAfterImeResize(true);
      }
    }
  }

  private chatEffectDuration(key: string, duration: number): number {
    if (this.reduceAnimations || !powerFeatureEnabled(KEY_POWER_SMOOTH_TRANSITIONS)) {
      return 0;
    }
    return powerGroupAnimationDuration(KEY_POWER_CHAT_EFFECTS, key, duration);
  }

  private animationPaused(messageId: number): boolean {
    return this.pausedAnimationIds.indexOf(messageId) >= 0;
  }

  private animationForcePlay(messageId: number): boolean {
    return this.forcedAnimationIds.indexOf(messageId) >= 0;
  }

  private animationPlaybackFailed(messageId: number): boolean {
    return this.failedAnimationIds.indexOf(messageId) >= 0;
  }

  private withoutAnimationId(ids: number[], messageId: number): number[] {
    return ids.filter((id: number): boolean => id !== messageId);
  }

  private onAnimationTap(messageId: number, isPlaying: boolean): void {
    const entry = this.entryById(messageId);
    if (entry === null || !entry.isAnimation) {
      return;
    }
    if (entry.videoFileId === 0 && entry.videoPath === '') {
      promptAction.showToast({ message: $r('app.string.cp_gif_unavailable'), duration: 1500 });
      return;
    }
    if (isPlaying) {
      this.forcedAnimationIds = this.withoutAnimationId(this.forcedAnimationIds, messageId);
      if (!this.animationPaused(messageId)) {
        this.pausedAnimationIds = [...this.pausedAnimationIds, messageId];
      }
      return;
    }

    // A manual play request has priority over auto-play/power-saving policy,
    // but remains viewport/foreground scoped by MessageBubble.
    this.pausedAnimationIds = this.withoutAnimationId(this.pausedAnimationIds, messageId);
    this.failedAnimationIds = this.withoutAnimationId(this.failedAnimationIds, messageId);
    if (!this.animationForcePlay(messageId)) {
      this.forcedAnimationIds = [...this.forcedAnimationIds, messageId];
    }
    if (entry.videoPath === '') {
      // 内联播放的 GIF 按定义就在可见窗口里，划走了本来就该停 —— 不需要豁免，
      // 更不该进下载管理器（那是"保存"才有的待遇）。
      this.store?.requestVideoDownload(messageId, false, entry.videoFailed);
    }
  }

  private onAnimationPlaybackFailed(messageId: number): void {
    if (!this.animationPlaybackFailed(messageId)) {
      this.failedAnimationIds = [...this.failedAnimationIds, messageId];
    }
    this.forcedAnimationIds = this.withoutAnimationId(this.forcedAnimationIds, messageId);
    if (!this.animationPaused(messageId)) {
      this.pausedAnimationIds = [...this.pausedAnimationIds, messageId];
    }
  }

  private mediaEntryIsPhoto(entry: MessageEntry): boolean {
    return entry.contentType === 'photo' ||
      (entry.contentType === 'paidMedia' && !entry.paidMediaLocked &&
        entry.paidMediaKind === 'photo');
  }

  private mediaEntryIsVideo(entry: MessageEntry): boolean {
    // 圆形视频不进全屏查看器——它在气泡里原地播放（见 MessageBubble）。
    return entry.contentType === 'video' ||
      (entry.contentType === 'paidMedia' && !entry.paidMediaLocked &&
        entry.paidMediaKind === 'video');
  }

  // Open/close wrapped in animateTo so the viewer's own transition remains
  // smooth without moving/re-parenting the chat thumbnail Image node.
  private openViewer(messageId: number): void {
    if (this.viewerClosing) {
      return;
    }
    const entry = this.entryById(messageId);
    if (entry === null) {
      return;
    }
    if (entry.contentType === 'paidMedia' && entry.paidMediaLocked) {
      this.onPaidMediaUnlock(messageId);
      return;
    }
    if (!this.mediaEntryIsPhoto(entry) && !this.mediaEntryIsVideo(entry)) {
      return;
    }
    if (this.mediaEntryIsPhoto(entry) && entry.photoPath === '' && entry.photoFailed) {
      this.store?.retryPhoto(messageId);
      promptAction.showToast({ message: $r('app.string.cp_reloading_thumb'), duration: 1200 });
      return;
    }
    if (this.mediaEntryIsPhoto(entry) && entry.photoPath === '' &&
      entry.photoFullPath === '' && entry.photoFileId === 0 && entry.photoFullFileId === 0) {
      promptAction.showToast({ message: $r('app.string.cp_photo_unavailable'), duration: 1500 });
      return;
    }
    if (this.mediaEntryIsVideo(entry)) {
      if (entry.videoFileId === 0 && entry.videoPath === '') {
        promptAction.showToast({ message: $r('app.string.cp_video_unavailable'), duration: 1500 });
        return;
      }
      // A cover failure must not block a playable video. Retry it quietly so
      // the viewer can gain a poster while the stream starts.
      if (entry.photoPath === '' && entry.photoFailed) {
        this.store?.retryPhoto(messageId);
      }
      // Streaming needs a total size for byte ranges. If TDLib hasn't supplied
      // one yet, finish a normal download first instead of opening a viewer
      // that can only report "无法获取视频大小".
      if (entry.videoPath === '' && entry.videoFileSize <= 0) {
        // 为看而下，不是为留而下：走 requestVideoForPlayback，关掉播放器时
        // releaseVideoPlayback 才能真的把它停下来。
        this.store?.requestVideoForPlayback(messageId, entry.videoFailed);
        this.notePlaybackRequest(messageId);
        promptAction.showToast({ message: $r('app.string.cp_fetching_video'), duration: 1800 });
        return;
      }
      if (entry.videoFailed) {
        // A failed autoplay/save download is recoverable and doesn't prevent
        // the independent streaming player from opening immediately.
        this.store?.requestVideoDownload(messageId, false, true);
      }
    }
    animateTo({ duration: this.chatEffectDuration(KEY_POWER_EFFECT_BLUR, 300), curve: Curve.Friction }, () => {
      this.onMediaTap(messageId);
    });
  }

  // Zoom/pan state no longer needs resetting here: MediaViewerOverlay owns it
  // and is destroyed with the `viewerMsgId !== 0` branch, so the next open
  // starts from a fresh instance at 1x.
  // 播放器为了播放而拉起的下载。看完就该停，所以要记住是哪些 —— 浏览器可以
  // 左右滑动换条目，关闭时不止一条可能还在下。
  private notePlaybackRequest(messageId: number): void {
    if (this.playbackRequestedIds.indexOf(messageId) < 0) {
      this.playbackRequestedIds = [...this.playbackRequestedIds, messageId];
    }
  }

  private releasePlaybackRequests(): void {
    const store = this.store;
    const ids = this.playbackRequestedIds;
    this.playbackRequestedIds = [];
    if (store === null) {
      return;
    }
    for (const id of ids) {
      store.releaseVideoPlayback(id);
    }
  }

  // 查看目标变了（打开、Swiper 左右滑到相册的另一条、胶片条跳转、关闭）：
  // 进度必须从 0 重记。否则用户滑到下一条后 350ms 内（onPositionChanged 的
  // 上报周期）就关掉查看器，closeViewer 会把上一条的进度写进新消息的
  // bubblePositionMs，回到气泡就从一个莫名其妙的位置起播。
  // closeViewer 在 animateTo 把 viewerMsgId 清零之前已经读走了进度，所以
  // 关闭那一次的清零不会吃掉正确的值。
  private onViewerTargetChanged(): void {
    this.viewerPositionMs = 0;
  }

  private closeViewer(): void {
    if (this.viewerMsgId === 0 || this.viewerClosing) {
      return;
    }
    this.releasePlaybackRequests();
    this.exitViewerLandscape();
    // 交接:把查看器最终播放到的位置写回气泡进度表，并把这条 pin 成播放位——
    // 用户刚看完的这条回到列表后应当继续播。取值/计算都要在 viewerMsgId 被
    // animateTo 里的回调清零之前完成。
    const viewerMessageId = this.viewerMsgId;
    this.bubblePositionMs.set(viewerMessageId, this.viewerPositionMs);
    // pin 是有时效的（PLAY_SLOT_PIN_TTL_MS）：只为「刚看完的这条回到列表后
    // 接着播」服务，过期后它跟别的候选一样要重新攒够驻留才能当选。
    this.playSlots.pin(viewerMessageId, this.albumIndexForViewer(viewerMessageId), Date.now());
    const duration: number = this.chatEffectDuration(KEY_POWER_EFFECT_BLUR, 260);
    this.viewerClosing = true;
    animateTo({ duration, curve: Curve.Friction }, () => {
      this.viewerMsgId = 0;
      this.viewerInitIdx = 0;
      this.chromeVisible = true;
    });
    // 查看器关掉了，重新喂一次"已停止"把播放位判定跑起来。候选表这一刻
    // 可能还是空的（open 时 reset() 清空过，且几何没变不会自然重新上报），
    // 那就先选不出来——下一次真正的滚动/新消息到达会用同一个幂等方法再补
    // 一次，不会永久卡住。pin() 记的目标在候选表补上之前一样选不出来，
    // 是同一个幂等收敛，不需要额外处理。
    this.armPlaySlotSettle();
    setTimeout((): void => { this.viewerClosing = false; }, Math.max(80, duration));
  }

  // Leaving the viewer in landscape would strand the chat page sideways.
  private exitViewerLandscape(): void {
    if (!this.viewerVideoLandscape) {
      return;
    }
    this.viewerVideoLandscape = false;
    setMediaViewerOrientation(getContext(this) as common.UIAbilityContext, false);
  }

  // System back (gesture/hardware button): close the fullscreen viewer first
  // if it's open, rather than popping all the way back to the chat list.
  onBackPress(): boolean {
    // 录制浮层盖住整页，返回键必须先关它（组件退场时会取消录制并删掉临时文件）。
    if (this.showVideoNoteRecorder) {
      this.showVideoNoteRecorder = false;
      return true;
    }
    if (this.headerMenuShow) {
      this.headerMenuShow = false;
      return true;
    }
    if (this.showForwardSheet) {
      this.closeForwardSheet();
      return true;
    }
    if (this.showReactionSheet) {
      this.closeReactionSheet();
      return true;
    }
    if (this.viewerMsgId !== 0) {
      if (this.viewerVideoLandscape) {
        this.exitViewerLandscape();
        return true;
      }
      this.closeViewer();
      return true;
    }
    if (this.selecting) {
      this.exitSelect();
      return true;
    }
    if (this.searchMode) {
      this.exitSearch();
      return true;
    }
    return false;
  }

  // Private chat: the peer's emoji status appears beside the header title.
  private fetchHeaderEmojiStatus(): void {
    if (this.headerEmojiFetched) {
      return;
    }
    const uid = this.headerPeerUserId > 0
      ? this.headerPeerUserId : (this.store !== null ? this.store.getPeerUserId() : 0);
    if (uid <= 0) {
      return;
    }
    const resolveSeq = this.headerResolveSeq;
    this.headerEmojiFetched = true;
    const req: TdRequest = { '@type': 'getUser' };
    req['user_id'] = uid;
    getTdClient().send(req).then((user: TdObject) => {
      resolveEmojiStatus(user['emoji_status'] as TdObject | undefined, (path: string, format: string) => {
        const currentUid = this.headerPeerUserId > 0
          ? this.headerPeerUserId : (this.store !== null ? this.store.getPeerUserId() : 0);
        if (resolveSeq !== this.headerResolveSeq || uid !== currentUid) {
          return;
        }
        this.headerEmojiPath = path;
        this.headerEmojiFormat = format;
      });
    }).catch((e: TdError) => {
      if (resolveSeq === this.headerResolveSeq) {
        this.headerEmojiFetched = false;
      }
      console.error(`ChatPage.fetchHeaderEmojiStatus failed: ${e.message}`);
    });
  }

  // Refresh the floating date chip from the topmost visible row and (re)arm
  // its fade-out. This is called only for a touch-originated scroll session:
  // initial positioning and reply/pinned jumps must not flash the chip.
  private updateFloatDate(start: number): void {
    if (!this.didInitialScroll || start < 0 || start >= this.groups.length) {
      return;
    }
    const now = Date.now();
    // onDidScroll fires every rendered frame. If the top row hasn't changed,
    // skip the group scan, date formatting and @State writes; only refresh the
    // hide timer at a coarse cadence so a long drag keeps the chip visible.
    if (start === this.floatDateIndex && this.floatDateShown) {
      if (now - this.floatDateTimerArmedAt < 180) {
        return;
      }
      this.armFloatDateHide(now);
      return;
    }
    let date: number = 0;
    for (let i = start; i < this.groups.length; i++) {
      if (this.groups[i].head.date > 0) {
        date = this.groups[i].head.date;
        break;
      }
    }
    if (date <= 0) {
      return;
    }
    const nextLabel = formatDateSeparator(date);
    if (this.floatDate !== nextLabel) {
      this.floatDate = nextLabel;
    }
    if (!this.floatDateShown) {
      this.floatDateShown = true;
    }
    if (!this.listUserScrollActive) {
      this.listUserScrollActive = true;
    }
    this.floatDateIndex = start;
    this.armFloatDateHide(now);
  }

  private armFloatDateHide(now: number): void {
    this.floatDateTimerArmedAt = now;
    if (this.floatDateHideTimer !== -1) {
      clearTimeout(this.floatDateHideTimer);
    }
    this.floatDateHideTimer = setTimeout(() => {
      this.floatDateHideTimer = -1;
      this.floatDateShown = false;
      this.listUserScrollActive = false;
      this.floatDateIndex = -1;
    }, 820);
  }

  private prepareUserJump(): void {
    this.clearFloatingDate();
    this.stayAtUnread = false;
    this.jumpLayoutSeq++;
    this.cancelFlash();
  }

  // The banner tracks the scroll position: it shows the newest pinned message
  // strictly ABOVE the viewport top (the one a tap would jump to). Scrolling
  // past a pinned message therefore switches the banner to its neighbor, and
  // after a tap-jump lands this naturally advances to the next older one.
  private updatePinnedFromScroll(start: number): void {
    if (this.store === null || this.pinnedCount === 0 || start < 0 || start >= this.groups.length) {
      return;
    }
    const ids: number[] = this.store.getPinnedIds(); // newest → oldest
    const previews: string[] = this.store.getPinnedPreviews();
    const topId: number = this.groups[start].head.id;
    let idx = -1;
    for (let i = 0; i < ids.length; i++) {
      if (ids[i] < topId) {
        idx = i;
        break;
      }
    }
    if (idx < 0) {
      idx = ids.length - 1; // viewport is above every pinned message → nearest is the oldest
    }
    if (idx !== this.pinnedShownIdx()) {
      this.pinnedCycle = idx;
      if (idx < previews.length) {
        this.pinnedPreview = previews[idx];
      }
    }
  }

  // Tap the pinned banner: jump to the pinned message it currently shows.
  // Once at/above the oldest pinned message, tapping wraps back to the bottom.
  private onPinnedTap(): void {
    if (this.pinnedJumpBusy) {
      return;
    }
    if (this.pinnedLoadState === 'error') {
      this.store?.refreshPinned();
      promptAction.showToast({ message: $r('app.string.cp_resyncing_pinned'), duration: 1200 });
      return;
    }
    if (this.store === null) {
      return;
    }
    const ids: number[] = this.store.getPinnedIds();
    if (ids.length === 0) {
      this.pinnedPreview = '';
      this.pinnedCount = 0;
      return;
    }
    this.startPinnedJumpGuard(2500);
    this.prepareUserJump();
    const idx: number = this.pinnedShownIdx();
    const targetId: number = ids[idx];
    const topId: number = this.curStartIdx >= 0 && this.curStartIdx < this.groups.length
      ? this.groups[this.curStartIdx].head.id : 0;
    if (idx === ids.length - 1 && topId !== 0 && topId <= targetId) {
      this.scrollToLatest();
      this.startPinnedJumpGuard(TOP_CARD_ACTION_GUARD_MS);
      return;
    }
    const gidx: number = groupIndexOf(this.groups, targetId);
    if (gidx >= 0) {
      this.scroller.scrollToIndex(gidx, false, ScrollAlign.START);
      this.flashAtIndex(gidx);
      this.startPinnedJumpGuard(TOP_CARD_ACTION_GUARD_MS);
    } else {
      this.pendingJumpId = targetId;
      this.store.loadAround(targetId, (found: boolean): void => {
        if (!found && this.pendingJumpId === targetId) {
          this.pendingJumpId = 0;
          this.finishPinnedJump();
          this.store?.refreshPinned();
          promptAction.showToast({ message: $r('app.string.cp_pinned_unavailable'), duration: 1500 });
        }
      });
    }
  }

  private startPinnedJumpGuard(duration: number): void {
    this.pinnedJumpBusy = true;
    if (this.topCardActionTimer !== -1) {
      clearTimeout(this.topCardActionTimer);
    }
    this.topCardActionTimer = setTimeout((): void => {
      this.topCardActionTimer = -1;
      this.pinnedJumpBusy = false;
    }, duration);
  }

  private finishPinnedJump(): void {
    this.pinnedJumpBusy = false;
    if (this.topCardActionTimer !== -1) {
      clearTimeout(this.topCardActionTimer);
      this.topCardActionTimer = -1;
    }
  }

  // Fire at most one loadOlder per arm (see olderArmed).
  private maybeLoadOlder(): void {
    if (this.olderArmed && this.store !== null) {
      const started = this.store.loadOlder();
      if (started || !this.store.getHasMoreOlder()) {
        this.olderArmed = false;
      }
    }
  }

  // A history page is inserted before the current window. Keep the exact
  // message and its partial row offset under the user's finger; the newly
  // loaded rows should only appear as they continue scrolling upward.
  private restorePrependAnchor(groups: AlbumGroup[], messageId: number, itemY: number): void {
    const targetIndex: number = groupIndexOf(groups, messageId);
    if (targetIndex < 0) {
      return;
    }
    this.restoreScrollAnchor(targetIndex, itemY);
  }

  private restoreScrollAnchor(targetIndex: number, itemY: number): void {
    const seq: number = ++this.prependRestoreSeq;
    setTimeout((): void => {
      if (seq !== this.prependRestoreSeq || this.pendingJumpId !== 0 || this.pendingScrollBottom) {
        return;
      }
      this.scroller.scrollToIndex(targetIndex, false, ScrollAlign.START);
      if (itemY < -0.5) {
        this.scroller.scrollBy(0, -itemY);
      }
    }, 0);
  }

  private resetHeaderState(cached: ChatEntry | undefined): void {
    this.headerResolveSeq++;
    this.headerState = 'loading';
    this.headerLoadError = '';
    this.headerPeerUserId = 0;
    this.headerKind = '';
    this.headerIdentityResolved = false;
    this.headerEmojiPath = '';
    this.headerEmojiFormat = '';
    this.headerEmojiFetched = false;
    this.headerMenuShow = false;
    this.headerProfileOpening = false;
    this.headerMuteUpdating = false;
    this.pageClosing = false;
    this.headerVisible = false;
    this.subtitle = '';
    this.avatarPath = '';
    this.initials = '?';
    this.title = this.chatHeaderTitleNow('');
    this.isMuted = false;
    if (cached !== undefined) {
      this.title = this.chatHeaderTitleNow(cached.title);
      this.initials = cached.initials;
      this.avatarPath = cached.avatarPath;
      this.isMuted = cached.isMuted;
      if (cached.kind === 'private') {
        // TDLib private-chat identifiers equal the peer user identifier.
        this.headerKind = 'private';
        this.headerPeerUserId = cached.id;
        this.headerIdentityResolved = true;
      } else if (cached.kind === 'basicGroup' || cached.kind === 'supergroup' ||
        cached.kind === 'channel') {
        this.headerKind = cached.kind === 'channel' ? 'channel' : 'group';
        this.headerIdentityResolved = true;
      } else {
        this.headerKind = 'secret';
      }
      if (cached.title !== '') {
        this.headerState = 'ready';
      }
    }
    if (this.headerEntranceTimer !== -1) {
      clearTimeout(this.headerEntranceTimer);
    }
    this.headerEntranceTimer = setTimeout((): void => {
      this.headerEntranceTimer = -1;
      this.headerVisible = true;
    }, powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 24));
  }

  private applyResolvedHeaderChat(chat: TdObject, seq: number): void {
    if (seq !== this.headerResolveSeq) {
      return;
    }
    const resolvedTitle = (chat['title'] as string | undefined) ?? '';
    if (resolvedTitle !== '') {
      if (this.threadRootId === 0 && this.forumTopicId === 0) {
        this.title = resolvedTitle;
      }
      this.initials = computeInitials(resolvedTitle);
    }
    const settings = chat['notification_settings'] as TdObject | undefined;
    if (settings !== undefined && !this.headerMuteUpdating) {
      this.isMuted = isMutedFrom(settings);
      this.isTranslatable = (chat['is_translatable'] as boolean | undefined) ?? false;
    }
    const photo = chat['photo'] as TdObject | undefined;
    const small = photo !== undefined ? (photo['small'] as TdObject | undefined) : undefined;
    const local = small !== undefined ? (small['local'] as TdObject | undefined) : undefined;
    const localPath = local !== undefined ? ((local['path'] as string | undefined) ?? '') : '';
    const localReady = local !== undefined
      ? ((local['is_downloading_completed'] as boolean | undefined) ?? false) : false;
    if (localReady && localPath !== '') {
      this.avatarPath = localPath;
    }
    const type = chat['type'] as TdObject | undefined;
    const typeName = type !== undefined ? ((type['@type'] as string | undefined) ?? '') : '';
    if (typeName === 'chatTypePrivate') {
      this.headerKind = 'private';
      this.headerPeerUserId = (type!['user_id'] as number | undefined) ?? this.chatId;
      this.headerIdentityResolved = this.headerPeerUserId > 0;
      this.isGroup = false;
      this.isChannel = false;
      this.refreshBotMiniApp(this.headerPeerUserId);
    } else if (typeName === 'chatTypeBasicGroup') {
      this.headerKind = 'group';
      this.headerIdentityResolved = true;
      this.isGroup = true;
      this.isChannel = false;
    } else if (typeName === 'chatTypeSupergroup') {
      this.isChannel = (type!['is_channel'] as boolean | undefined) ?? false;
      this.headerKind = this.isChannel ? 'channel' : 'group';
      this.headerIdentityResolved = true;
      this.isGroup = true;
    } else if (typeName === 'chatTypeSecret') {
      this.headerKind = 'secret';
      this.isGroup = false;
      this.isChannel = false;
      const secretId = (type!['secret_chat_id'] as number | undefined) ?? 0;
      if (secretId > 0) {
        const secretReq: TdRequest = { '@type': 'getSecretChat' };
        secretReq['secret_chat_id'] = secretId;
        getTdClient().send(secretReq).then((secret: TdObject): void => {
          if (seq !== this.headerResolveSeq) {
            return;
          }
          this.headerPeerUserId = (secret['user_id'] as number | undefined) ?? 0;
          this.headerIdentityResolved = this.headerPeerUserId > 0;
          this.fetchHeaderEmojiStatus();
        }).catch((error: TdError): void => {
          console.error(`ChatPage.getSecretChat header failed: ${error.message}`);
        });
      }
    }
    this.headerState = resolvedTitle !== '' || this.title !== '' ? 'ready' : 'error';
    this.headerLoadError = this.headerState === 'error' ? str('cp_chat_unavailable') : '';
    this.fetchHeaderEmojiStatus();
  }

  // Header title/subtitle wording lives in chatHeaderPresentation, where the
  // "cached title beats a pending load" and error-fallback rules are tested.
  private chatHeaderTitleNow(chatTitle: string): string {
    return chatHeaderTitle({
      chatTitle,
      topicName: this.topicName,
      forumTopicId: this.forumTopicId,
      threadRootId: this.threadRootId
    });
  }

  private headerText(): ChatHeaderPresentation {
    return chatHeaderPresentation({
      title: this.title,
      subtitle: this.subtitle,
      state: this.headerState,
      loadError: this.headerLoadError,
      kind: this.headerKind
    });
  }

  private resolveHeaderIdentity(): void {
    if (this.chatId === 0) {
      this.headerState = 'error';
      this.headerLoadError = str('cp_chat_params_invalid');
      return;
    }
    const seq = ++this.headerResolveSeq;
    if (this.title === '') {
      this.headerState = 'loading';
      this.headerLoadError = '';
    }
    const request: TdRequest = { '@type': 'getChat' };
    request['chat_id'] = this.chatId;
    getTdClient().send(request).then((chat: TdObject): void => {
      this.applyResolvedHeaderChat(chat, seq);
    }).catch((error: TdError): void => {
      if (seq !== this.headerResolveSeq) {
        return;
      }
      if (this.title === '') {
        this.headerState = 'error';
        this.headerLoadError = str('cp_chat_load_failed');
      }
      console.error(`ChatPage.resolveHeaderIdentity failed: ${error.message}`);
    });
  }

  private refreshHeader(): void {
    const e: ChatEntry | undefined = getChatStore().entryOf(this.chatId);
    // A topic/thread view keeps its own name; the rest of the header still
    // shows the underlying chat's avatar and mute state.
    this.title = this.chatHeaderTitleNow(e !== undefined ? e.title : this.title);
    if (e !== undefined) {
      // Don't clobber a MessageStore-resolved avatar (channels/folders) with an empty one.
      if (e.avatarPath !== '') { this.avatarPath = e.avatarPath; }
      this.initials = e.initials;
      if (!this.headerMuteUpdating) {
        this.isMuted = e.isMuted;
      }
      this.unreadBadge = e.unreadCount; // live unread count for the scroll-to-bottom badge
      if (e.title !== '') {
        this.headerState = 'ready';
        this.headerLoadError = '';
      }
      if (!this.headerIdentityResolved) {
        if (e.kind === 'private') {
          this.headerKind = 'private';
          this.headerPeerUserId = e.id;
          this.headerIdentityResolved = true;
        } else if (e.kind === 'basicGroup' || e.kind === 'supergroup' || e.kind === 'channel') {
          this.headerKind = e.kind === 'channel' ? 'channel' : 'group';
          this.headerIdentityResolved = true;
        }
      }
      if (e.background !== null) {
        this.bgStore?.applyKnownBackground(e.background);
      }
      this.syncLiveFromChatEntry(e);
    }
  }

  // ChatStore already resolves updateChatVideoChat + updateGroupCall for the
  // chat list. Reuse that confirmed state as the fast path when entering or
  // resuming a chat instead of hiding the live banner until a second
  // getChat/getGroupCall round trip finishes. The direct probe below remains
  // authoritative and will still remove a call once TDLib confirms it ended.
  private syncLiveFromChatEntry(entry: ChatEntry): void {
    if (entry.liveGroupCallId <= 0) {
      // A cache miss is not proof that a call ended: getChat may already have
      // found a newer call which hasn't reached ChatStore yet.
      return;
    }
    if (entry.liveGroupCallId !== this.liveGroupCallId) {
      this.setLiveGroupCallId(entry.liveGroupCallId);
    }
    if (!entry.isLive || entry.liveGroupCallId !== this.liveGroupCallId) {
      return;
    }
    this.liveCallIsActive = true;
    this.liveCallIsRtmp = entry.isRtmpLive;
    this.liveLoadState = 'ready';
    this.settleTopCardLoading();
  }

  private refreshMembership(): void {
    const seq: number = ++this.membershipSeq;
    const req: TdRequest = { '@type': 'getChat' };
    req['chat_id'] = this.chatId;
    getTdClient().send(req).then((chat: TdObject): void => {
      if (seq !== this.membershipSeq) {
        return;
      }
      const type = chat['type'] as TdObject | undefined;
      const typeName = (type?.['@type'] as string | undefined) ?? '';
      if (typeName === 'chatTypeSupergroup') {
        this.membershipSupergroupId = (type?.['supergroup_id'] as number | undefined) ?? 0;
        this.membershipBasicGroupId = 0;
        this.isGroup = true;
        this.isChannel = (type?.['is_channel'] as boolean | undefined) ?? this.isChannel;
        this.membershipState = 'checking';
        const groupReq: TdRequest = { '@type': 'getSupergroup' };
        groupReq['supergroup_id'] = this.membershipSupergroupId;
        getTdClient().send(groupReq).then((supergroup: TdObject): void => {
          if (seq === this.membershipSeq) {
            this.applyMembershipStatus(supergroup['status'] as TdObject | undefined);
          }
        }).catch((e: TdError): void => {
          if (seq === this.membershipSeq) {
            this.membershipState = 'writable';
          }
          console.error(`ChatPage.getSupergroup membership failed: ${e.message}`);
        });
        return;
      }
      if (typeName === 'chatTypeBasicGroup') {
        this.membershipBasicGroupId = (type?.['basic_group_id'] as number | undefined) ?? 0;
        this.membershipSupergroupId = 0;
        this.isGroup = true;
        this.isChannel = false;
        this.membershipState = 'checking';
        const groupReq: TdRequest = { '@type': 'getBasicGroup' };
        groupReq['basic_group_id'] = this.membershipBasicGroupId;
        getTdClient().send(groupReq).then((basicGroup: TdObject): void => {
          if (seq === this.membershipSeq) {
            this.applyMembershipStatus(basicGroup['status'] as TdObject | undefined);
          }
        }).catch((e: TdError): void => {
          if (seq === this.membershipSeq) {
            this.membershipState = 'writable';
          }
          console.error(`ChatPage.getBasicGroup membership failed: ${e.message}`);
        });
        return;
      }
      this.membershipSupergroupId = 0;
      this.membershipBasicGroupId = 0;
      this.membershipState = 'writable';
    }).catch((e: TdError): void => {
      if (seq === this.membershipSeq) {
        // Don't leave private/secret chats with a permanently hidden composer
        // if the supplementary status request fails.
        this.membershipState = 'writable';
      }
      console.error(`ChatPage.getChat membership failed: ${e.message}`);
    });
  }

  private applyMembershipStatus(status: TdObject | undefined): void {
    const type: string = (status?.['@type'] as string | undefined) ?? '';
    if (type === '') {
      return;
    }
    let next: string = 'writable';
    if (type === 'chatMemberStatusLeft') {
      next = 'joinable';
    } else if (type === 'chatMemberStatusRestricted') {
      const isMember: boolean = (status?.['is_member'] as boolean | undefined) ?? false;
      next = isMember ? 'writable' : 'joinable';
    } else if (type === 'chatMemberStatusBanned') {
      next = 'blocked';
    } else if (this.isChannel && type === 'chatMemberStatusMember') {
      // Broadcast-channel subscribers can never post — only the creator and
      // admins with posting rights get the composer.
      next = 'readonly';
    } else if (this.isChannel && type === 'chatMemberStatusAdministrator') {
      const rights = status?.['rights'] as TdObject | undefined;
      next = ((rights?.['can_post_messages'] as boolean | undefined) ?? false)
        ? 'writable' : 'readonly';
    }
    this.membershipState = next;
    if (next === 'writable') {
      this.joiningChat = false;
      return;
    }
    // A membership update can arrive while the cached page still has composer
    // UI open. Close every composer-owned surface before replacing the bar.
    this.joiningChat = false;
    this.setEmojiPanel(false);
    this.mentionItems = [];
    this.commandItems = [];
    this.commandMenuOpen = false;
    this.replyToId = 0;
    this.replyToName = '';
    this.replyToText = '';
    if (this.isRecording) {
      this.cancelRecording();
    }
  }

  private joinCurrentChat(): void {
    if (this.joiningChat || this.membershipState !== 'joinable') {
      return;
    }
    this.joiningChat = true;
    const req: TdRequest = { '@type': 'joinChat' };
    req['chat_id'] = this.chatId;
    getTdClient().send(req).then((): void => {
      this.joiningChat = false;
      // updateSupergroup/updateBasicGroup normally arrives first; setting this
      // eagerly keeps the UI responsive even if that update is delayed.
      this.membershipState = 'writable';
      this.showClientJoinNotice(this.isChannel);
      this.refreshMembership();
    }).catch((e: TdError): void => {
      this.joiningChat = false;
      console.error(`ChatPage.joinChat failed: ${e.message}`);
      promptAction.showToast({ message: $r('app.string.cp_join_failed'), duration: 2000 });
    });
  }

  // Mark read up to the bottom-most visible message, so only what the user has
  // actually scrolled past gets marked read (entering without scrolling leaves
  // the rest unread).
  private markVisibleRead(end: number): void {
    if (this.store === null || end < 0 || end >= this.groups.length) {
      return;
    }
    let maxId: number = 0;
    // A client-only service row has no member ids. Walk back to the newest
    // visible real row so its presence can't prevent the actual tail from
    // being marked read.
    for (let groupIndex: number = end; groupIndex >= 0 && maxId === 0; groupIndex--) {
      const g: AlbumGroup = this.groups[groupIndex];
      for (const id of g.memberIds) {
        if (id > maxId) {
          maxId = id;
        }
      }
    }
    if (maxId > 0) {
      this.store.markViewed(maxId);
      getChatStore().markReadLocally(this.chatId, maxId);
    }
  }

  // A tapped in-message link: Telegram links (t.me/<name>, t.me/<name>/<msgId>,
  // @<name>) resolve via TDLib and open the target chat inside the app, jumped
  // to the specific message when the link points to one; everything else opens
  // in the system browser.
  private onLinkTap(url: string): void {
    // Bot commands are active entities in Telegram. A deliberate tap sends
    // the command immediately, while sharing the composer's in-flight guard so
    // double taps cannot enqueue duplicates.
    if (url.startsWith('tg-command:')) {
      const command = url.substring('tg-command:'.length);
      const store: MessageStore | null = this.store;
      if (command === '' || store === null || this.composerSending) {
        return;
      }
      const replyId = this.replyToId;
      this.composerSending = true;
      this.atBottom = true;
      this.stayAtUnread = false;
      store.sendAsync(command, replyId).then((): void => {
        this.composerSending = false;
        if (this.replyToId === replyId) {
          this.clearReply();
        }
      }).catch((e: TdError): void => {
        this.composerSending = false;
        console.error(`ChatPage.botCommand failed: ${e.message}`);
        promptAction.showToast({ message: $r('app.string.cp_command_failed'), duration: 1600 });
      });
      return;
    }
    if (url.startsWith('tg-copy:')) {
      this.copyPlainText(url.substring('tg-copy:'.length), str('cp_number_copied'));
      return;
    }
    // Hashtag tap → global search across all chats.
    if (url.startsWith('tg-hashtag:')) {
      const tag = url.substring('tg-hashtag:'.length);
      if (tag !== '') {
        const params: Record<string, Object> = { 'query': tag };
        router.pushUrl({ url: 'pages/search/GlobalSearchPage', params: params });
      }
      return;
    }
    // Text mention (no username): the entity carries the user id directly.
    if (url.startsWith('tg://user?id=')) {
      const uid = Number(url.substring('tg://user?id='.length));
      if (uid > 0) {
        const params: Record<string, Object> = { 'userId': uid };
        router.pushUrl({ url: 'pages/profile/ProfilePage', params: params });
      }
      return;
    }
    const folderInvite = chatFolderInviteLinkOf(url);
    if (folderInvite !== '') {
      openChatFolderInviteLink(folderInvite);
      return;
    }
    const stickerSet = stickerSetLinkOf(url);
    if (stickerSet !== null) {
      openStickerSetLink(stickerSet);
      return;
    }
    // Private invite link: preview → confirm → join in-app.
    const invite = inviteLinkOf(url);
    if (invite !== '') {
      openInviteLink(getContext(this) as common.UIAbilityContext, invite, url);
      return;
    }
    const linkAction = chatLinkActionOf(url);
    if (linkAction !== null) {
      openChatLinkAction(getContext(this) as common.UIAbilityContext, linkAction, url, true);
      return;
    }
    const bareName = bareUsernameOf(url);
    if (bareName !== '') {
      openTelegramLink(getContext(this) as common.UIAbilityContext, url, true);
      return;
    }
    const tgUrl = normalizeTelegramLink(url);
    if (tgUrl === '') {
      openTelegramLink(getContext(this) as common.UIAbilityContext, url, true);
      return;
    }
    const req: TdRequest = { '@type': 'getMessageLinkInfo' };
    req['url'] = tgUrl;
    getTdClient().send(req).then((info: TdObject) => {
      const chatId = info['chat_id'] as number | undefined;
      if (chatId === undefined || chatId === 0) {
        openTelegramLink(getContext(this) as common.UIAbilityContext, url, true);
        return;
      }
      const msg = info['message'] as TdObject | undefined;
      const msgId = msg !== undefined ? (msg['id'] as number | undefined) : undefined;
      // A link to a message already in this chat: scroll in place (same as the
      // pinned-message jump) instead of pushing a duplicate ChatPage instance —
      // that duplication was why repeat taps looked like they did nothing.
      if (chatId === this.chatId) {
        if (msgId !== undefined && msgId > 0) {
          this.prepareUserJump();
          const gidx = groupIndexOf(this.groups, msgId);
          if (gidx >= 0) {
            this.scroller.scrollToIndex(gidx, false, ScrollAlign.START);
            this.flashAtIndex(gidx);
          } else {
            this.pendingJumpId = msgId;
            if (this.store !== null) {
              const targetId: number = msgId;
              this.store.loadAround(targetId, (found: boolean): void => {
                if (!found && this.pendingJumpId === targetId) {
                  this.pendingJumpId = 0;
                  promptAction.showToast({ message: $r('app.string.cp_cannot_locate'), duration: 1500 });
                }
              });
            }
          }
        }
        return;
      }
      const params: Record<string, Object> = { 'chatId': chatId };
      if (msgId !== undefined && msgId > 0) {
        params['jumpTo'] = msgId;
      }
      router.pushUrl({ url: 'pages/chat/ChatPage', params: params });
    }).catch((e: TdError) => {
      console.error(`ChatPage.getMessageLinkInfo failed: ${e.message}`);
      openTelegramLink(getContext(this) as common.UIAbilityContext, url, true);
    });
  }

  // Resolve a bare @username: a user opens the profile card; a group/channel
  // opens its chat page. `original` is the raw tapped URL for browser fallback.
  private openByUsername(name: string, original: string): void {
    const req: TdRequest = { '@type': 'searchPublicChat' };
    req['username'] = name;
    getTdClient().send(req).then((chat: TdObject) => {
      const chatId = (chat['id'] as number | undefined) ?? 0;
      const type = chat['type'] as TdObject | undefined;
      const typeName = type !== undefined ? ((type['@type'] as string | undefined) ?? '') : '';
      if (typeName === 'chatTypePrivate') {
        const uid = ((type as TdObject)['user_id'] as number | undefined) ?? 0;
        if (uid > 0) {
          const params: Record<string, Object> = { 'userId': uid };
          router.pushUrl({ url: 'pages/profile/ProfilePage', params: params });
          return;
        }
      }
      if (chatId !== 0) {
        const params: Record<string, Object> = { 'chatId': chatId };
        router.pushUrl({ url: 'pages/chat/ChatPage', params: params });
        return;
      }
      openWebUrl(getContext(this) as common.UIAbilityContext, original);
    }).catch((e: TdError) => {
      console.error(`ChatPage.searchPublicChat(${name}) failed: ${e.message}`);
      openWebUrl(getContext(this) as common.UIAbilityContext, original);
    });
  }

  // Reply-quote tap: jump to the quoted original message (same in-place scroll
  // as a same-chat link jump).
  // --- in-chat search ---
  private enterSearch(): void {
    this.searchMode = true;
    this.searchQuery = '';
    this.searchResults = [];
    this.searchTotal = 0;
    this.searchIdx = 0;
  }

  private exitSearch(): void {
    this.searchMode = false;
    this.searchQuery = '';
    this.searchResults = [];
    this.searchTotal = 0;
    this.searchIdx = 0;
    this.searchSeq++;
    this.cancelFlash();
  }

  private updateSearchQuery(value: string): void {
    if (value === this.searchQuery) {
      return;
    }
    this.searchQuery = value;
    this.searchResults = [];
    this.searchTotal = 0;
    this.searchIdx = 0;
    this.searchSeq++;
    this.cancelFlash();
  }

  // Run a search page. fromMsgId 0 = fresh search; otherwise fetch the page
  // older than that message (pagination for the ∧ button past the first 50).
  private runSearch(fromMsgId: number, thenJumpTo: number): void {
    const q = this.searchQuery.trim();
    if (q === '') {
      return;
    }
    const seq = ++this.searchSeq;
    const req: TdRequest = { '@type': 'searchChatMessages' };
    req['chat_id'] = this.chatId;
    req['query'] = q;
    req['from_message_id'] = fromMsgId;
    req['offset'] = 0;
    req['limit'] = 50;
    getTdClient().send(req).then((res: TdObject) => {
      if (seq !== this.searchSeq || !this.searchMode) {
        return;
      }
      const msgs = (res['messages'] as TdObject[] | undefined) ?? [];
      const ids: number[] = [];
      for (const m of msgs) {
        const id = (m['id'] as number | undefined) ?? 0;
        if (id > 0) {
          ids.push(id);
        }
      }
      this.searchTotal = (res['total_count'] as number | undefined) ?? ids.length;
      this.searchResults = fromMsgId === 0 ? ids : [...this.searchResults, ...ids];
      if (this.searchResults.length === 0) {
        promptAction.showToast({ message: $r('app.string.cp_no_messages_found'), duration: 1500 });
        return;
      }
      // Entered on a specific hit (a message tapped in global search): it is
      // already the jump target, so just make it the current hit.
      if (this.searchAnchorId !== 0) {
        const at = this.searchResults.indexOf(this.searchAnchorId);
        this.searchAnchorId = 0;
        if (at >= 0) {
          this.searchIdx = at;
          return;
        }
      }
      this.jumpToResult(thenJumpTo);
    }).catch((e: TdError) => {
      console.error(`ChatPage.searchChatMessages failed: ${e.message}`);
    });
  }

  private jumpToResult(idx: number): void {
    if (idx < 0 || idx >= this.searchResults.length) {
      return;
    }
    this.searchIdx = idx;
    this.onReplyTap(this.searchResults[idx]); // same jump + double-blink flash
  }

  // ∧ = older result. Past the loaded window → fetch the next page first.
  private searchOlder(): void {
    const next = this.searchIdx + 1;
    if (next < this.searchResults.length) {
      this.jumpToResult(next);
    } else if (this.searchResults.length < this.searchTotal && this.searchResults.length > 0) {
      this.runSearch(this.searchResults[this.searchResults.length - 1], next);
    }
  }

  // ∨ = newer result.
  private searchNewer(): void {
    if (this.searchIdx > 0) {
      this.jumpToResult(this.searchIdx - 1);
    }
  }

  private onReplyTap(messageId: number): void {
    if (messageId <= 0) {
      return;
    }
    this.prepareUserJump();
    const gidx = groupIndexOf(this.groups, messageId);
    if (gidx >= 0) {
      this.scroller.scrollToIndex(gidx, false, ScrollAlign.START);
      this.flashAtIndex(gidx);
    } else if (this.store !== null) {
      this.pendingJumpId = messageId;
      this.store.loadAround(messageId, (found: boolean): void => {
        if (!found && this.pendingJumpId === messageId) {
          this.pendingJumpId = 0;
          promptAction.showToast({ message: $r('app.string.cp_original_unavailable'), duration: 1500 });
        }
      });
    }
  }

  // Gently blink the row at gidx twice — visual confirmation of where a
  // reply/pinned/link jump landed. Waits a beat for the scroll to settle so
  // getItemRect sees the laid-out row.
  private flashAtIndex(gidx: number): void {
    const seq = ++this.flashSeq;
    setTimeout(() => {
      if (seq !== this.flashSeq) {
        return;
      }
      let top = 0;
      let height = 0;
      try {
        const rect = this.scroller.getItemRect(gidx);
        top = rect.y;
        height = rect.height;
      } catch (e) {
        return; // row not laid out (jump superseded) — skip the highlight
      }
      if (height <= 0) {
        return;
      }
      this.flashTop = top;
      this.flashHeight = height;
      this.flashShown = true;
      this.flashAlpha = 0;
      this.runBlink(seq, 2);
    }, 150);
  }

  private runBlink(seq: number, remaining: number): void {
    if (seq !== this.flashSeq) {
      return;
    }
    if (remaining <= 0) {
      this.flashShown = false;
      this.flashAlpha = 0;
      return;
    }
    animateTo({
      duration: this.chatEffectDuration(KEY_POWER_EFFECT_REPLY, 320), curve: Curve.EaseInOut
    }, () => { this.flashAlpha = 1; });
    setTimeout(() => {
      if (seq !== this.flashSeq) {
        return;
      }
      animateTo({
        duration: this.chatEffectDuration(KEY_POWER_EFFECT_REPLY, 320), curve: Curve.EaseInOut
      }, () => { this.flashAlpha = 0; });
      setTimeout(() => { this.runBlink(seq, remaining - 1); }, 340);
    }, 340);
  }

  // Any new touch cancels the highlight (it's viewport-anchored, so it would
  // visibly detach from the row once the user scrolls).
  private cancelFlash(): void {
    this.flashSeq++;
    this.flashShown = false;
    this.flashAlpha = 0;
  }

  // "N Comments" tap: resolve the channel post's discussion thread and open it
  // as a normal chat page on the linked discussion group, jumped to the post.
  // "转发自 X" tapped: open the original post in its channel/chat, or — for a
  // forward from a user — that user's private chat.
  private onForwardTap(originChatId: number, originMsgId: number, originUserId: number): void {
    if (originChatId !== 0) {
      const params: Record<string, Object> = { 'chatId': originChatId };
      if (originMsgId !== 0) {
        params['jumpTo'] = originMsgId;
      }
      router.pushUrl({ url: 'pages/chat/ChatPage', params: params });
      return;
    }
    if (originUserId === 0) {
      return;
    }
    const req: TdRequest = { '@type': 'createPrivateChat' };
    req['user_id'] = originUserId;
    req['force'] = true;
    getTdClient().send(req).then((chat: TdObject) => {
      const id = (chat['id'] as number | undefined) ?? 0;
      if (id !== 0) {
        const params: Record<string, Object> = { 'chatId': id };
        router.pushUrl({ url: 'pages/chat/ChatPage', params: params });
      }
    }).catch((e: TdError) => {
      console.error(`ChatPage.onForwardTap createPrivateChat failed: ${e.message}`);
      promptAction.showToast({ message: $r('app.string.cp_cannot_open_source'), duration: 1500 });
    });
  }

  private onCommentTap(messageId: number): void {
    const req: TdRequest = { '@type': 'getMessageThread' };
    req['chat_id'] = this.chatId;
    req['message_id'] = messageId;
    getTdClient().send(req).then((info: TdObject) => {
      const discussionChatId = info['chat_id'] as number | undefined;
      const threadId = info['message_thread_id'] as number | undefined;
      if (discussionChatId === undefined) {
        return;
      }
      const params: Record<string, Object> = { 'chatId': discussionChatId };
      if (threadId !== undefined && threadId > 0) {
        // Thread-scoped view: only this post's replies (getMessageThreadHistory),
        // not the whole discussion group's history.
        params['threadRootId'] = threadId;
      }
      router.pushUrl({ url: 'pages/chat/ChatPage', params: params });
    }).catch((e: TdError) => {
      console.error(`ChatPage.getMessageThread failed: ${e.message}`);
    });
  }

  // Open the fullscreen viewer for a photo/video message. Photos still upgrade
  // to full-res on demand; videos are streamed by the fullscreen AVPlayer.
  private onMediaTap(messageId: number): void {
    if (this.store === null) {
      return;
    }
    const idx = this.messages.findIndex((m: MessageEntry) => m.id === messageId);
    if (idx < 0) {
      return;
    }
    const m = this.messages[idx];
    if (!this.mediaEntryIsPhoto(m) && !this.mediaEntryIsVideo(m)) {
      return;
    }
    if (this.mediaEntryIsPhoto(m)) {
      this.store.requestFullPhoto(messageId);
    }
    // 交接:取气泡播放位记录的进度，必须在 playSlots.suspend() 让气泡播放器
    // 卸载之前完成——bubblePositionMs 本身不受 suspend() 影响，但卸载之后
    // 气泡播放器不会再有新的 onPositionChanged，读早读晚不影响这一次的值；
    // 保险起见仍然按“先取、后卸载”的顺序写。
    this.viewerStartPositionMs = this.bubblePositionMs.get(messageId) ?? 0;
    // 全屏查看器是页内叠层，不是新页面，不会触发 onPageHide——List 和气泡
    // 照样挂着，onVisibleAreaApproximateChange 只算几何不算遮挡，ratio 不
    // 变就不会自己释放播放位。不在这里主动停掉，播放位气泡的播放器会和
    // 查看器自己的播放器同时跑、同一个文件还可能互抢下载分片。
    // 用 suspend() 而不是 reset()：候选表要留着，否则关闭查看器后几何没变、
    // 没有任何新的 ratio 上报，列表就再也选不出播放位（“哑掉”）。
    this.clearSlotTick();
    this.playSlots.suspend();
    // Position the viewer Swiper on the tapped album member.
    const sib = this.siblingIdsFor(messageId);
    this.viewerInitIdx = Math.max(0, sib.indexOf(messageId));
    this.viewerMsgId = messageId;
    this.chromeVisible = true;
    this.viewerVideoLandscape = false;
    this.viewerClosing = false;
  }

  // Album member ids for an arbitrary message (single-element list when the
  // message isn't part of a multi-item album).
  private siblingIdsFor(messageId: number): number[] {
    for (const g of this.groups) {
      if (g.memberIds.indexOf(messageId) >= 0 && g.memberIds.length > 1) {
        return g.memberIds;
      }
    }
    return [messageId];
  }

  // playSlot 的 albumIndex 语义：整条消息传 -1，相册成员传该格在 memberIds
  // 里的下标。查看器交接（closeViewer 里的 pin）用这个把 viewerMsgId 换算
  // 回同一套坐标。
  private albumIndexForViewer(messageId: number): number {
    const sib = this.siblingIdsFor(messageId);
    return sib.length > 1 ? sib.indexOf(messageId) : -1;
  }

  private onLanguageEpochChanged(): void {
    // A hidden page can't be trusted to apply even a RELOAD; re-issue on show.
    if (!this.pageVisible) {
      this.hiddenListDirty = true;
      return;
    }
    this.groupsData.reload();
  }

  private onAppForegroundChanged(): void {
    // 停留在会话页切后台时必须 closeChat，否则 TDLib 认为用户正在看这个
    // 会话，不会为它生成任何通知。
    if (this.appIsForeground) {
      this.store?.resumeOpenChat();
    } else {
      this.store?.suspendOpenChat();
    }
    if (!this.appIsForeground) {
      getVoicePlayback().pauseForBackground();
    }
    if (!this.appIsForeground) {
      this.exitViewerLandscape();
    }
  }

  private entryById(id: number): MessageEntry | null {
    const idx = this.messages.findIndex((m: MessageEntry) => m.id === id);
    return idx >= 0 ? this.messages[idx] : null;
  }

  // Best available image for a viewer page: full-res once downloaded, else thumbnail.
  private onBotCallback(messageId: number, data: string): void {
    const payload: TdObject = { '@type': 'callbackQueryPayloadData' };
    payload['data'] = data;
    this.requestBotCallback(messageId, payload, `data_${data}`);
  }

  private onGameOpen(messageId: number): void {
    const payload: TdObject = { '@type': 'callbackQueryPayloadGame' };
    this.requestBotCallback(messageId, payload, 'game');
  }

  private requestBotCallback(messageId: number, payload: TdObject, suffix: string): void {
    const key = `${messageId}_${suffix}`;
    if (this.botCallbackPending.has(key)) {
      return;
    }
    this.botCallbackPending.add(key);
    const req: TdRequest = { '@type': 'getCallbackQueryAnswer' };
    req['chat_id'] = this.chatId;
    req['message_id'] = messageId;
    req['payload'] = payload;
    getTdClient().send(req).then((answer: TdObject): void => {
      this.botCallbackPending.delete(key);
      const url = (answer['url'] as string | undefined) ?? '';
      const text = (answer['text'] as string | undefined) ?? '';
      const showAlert = (answer['show_alert'] as boolean | undefined) ?? false;
      if (url.trim() !== '') {
        openWebUrl(getContext(this) as common.UIAbilityContext, url, (): void => {
          promptAction.showToast({ message: $r('app.string.cp_cannot_open_interaction'), duration: 1800 });
        });
      }
      if (text.trim() !== '') {
        if (showAlert) {
          promptAction.showDialog({
            title: $r('app.string.cp_notice'),
            message: text,
            buttons: [{ text: $r('app.string.cp_got_it'), color: '#3390EC' }]
          });
        } else {
          promptAction.showToast({ message: text, duration: 1800 });
        }
      }
    }).catch((e: TdError) => {
      this.botCallbackPending.delete(key);
      console.error(`ChatPage.getCallbackQueryAnswer failed: ${e.message}`);
      promptAction.showToast({
        message: suffix === 'game' ? $r('app.string.cp_game_cannot_open') : $r('app.string.action_failed_retry'),
        duration: 1800
      });
    });
  }

  private onPollVote(messageId: number, optionIds: number[]): void {
    if (this.store === null) {
      promptAction.showToast({ message: $r('app.string.cp_poll_unavailable'), duration: 1500 });
      return;
    }
    this.store.votePoll(messageId, optionIds, (ok: boolean, error: string): void => {
      if (!ok && error.trim() !== '') {
        promptAction.showToast({ message: error, duration: 1800 });
      }
    });
  }

  private paidMediaPending(messageId: number): boolean {
    return this.paidMediaPendingIds.indexOf(messageId) >= 0;
  }

  private setPaidMediaPending(messageId: number, pending: boolean): void {
    const next = this.paidMediaPendingIds.filter((id: number): boolean => id !== messageId);
    if (pending) {
      next.push(messageId);
    }
    this.paidMediaPendingIds = next;
  }

  private paidMediaInvoice(messageId: number): TdObject {
    const invoice: TdObject = { '@type': 'inputInvoiceMessage' };
    invoice['chat_id'] = this.chatId;
    invoice['message_id'] = messageId;
    return invoice;
  }

  private onPaidMediaUnlock(messageId: number): void {
    const entry = this.entryById(messageId);
    if (entry === null || entry.contentType !== 'paidMedia' ||
      !entry.paidMediaLocked || entry.paidMediaStarCount <= 0 ||
      this.paidMediaPending(messageId)) {
      return;
    }
    this.setPaidMediaPending(messageId, true);
    const propertiesReq: TdRequest = { '@type': 'getMessageProperties' };
    propertiesReq['chat_id'] = this.chatId;
    propertiesReq['message_id'] = messageId;
    getTdClient().send(propertiesReq).then((properties: TdObject): Promise<TdObject> => {
      if (!((properties['can_be_paid'] as boolean | undefined) ?? false)) {
        throw new TdError(400, str('cp_paid_cannot_buy'));
      }
      const formReq: TdRequest = { '@type': 'getPaymentForm' };
      formReq['input_invoice'] = this.paidMediaInvoice(messageId);
      return getTdClient().send(formReq);
    }).then((form: TdObject): void => {
      const formType = form['type'] as TdObject | undefined;
      const typeName = formType !== undefined
        ? ((formType['@type'] as string | undefined) ?? '') : '';
      if (typeName !== 'paymentFormTypeStars') {
        this.setPaidMediaPending(messageId, false);
        promptAction.showToast({ message: $r('app.string.cp_payment_unsupported'), duration: 1800 });
        return;
      }
      const formStars = Math.max(0,
        (formType!['star_count'] as number | undefined) ?? entry.paidMediaStarCount);
      const formId = (form['id'] as number | undefined) ?? 0;
      if (formStars <= 0 || formId === 0) {
        this.setPaidMediaPending(messageId, false);
        promptAction.showToast({ message: $r('app.string.cp_payment_incomplete'), duration: 1800 });
        return;
      }
      promptAction.showDialog({
        title: $r('app.string.cp_unlock_paid'),
        message: str('cp_pay_stars_body', formStars),
        buttons: [
          { text: $r('app.string.cancel'), color: '#8E8E93' },
          { text: str('cp_pay_stars_button', formStars), color: '#3390EC' }
        ]
      }).then((result): void => {
        if (result.index !== 1) {
          this.setPaidMediaPending(messageId, false);
          return;
        }
        const paymentReq: TdRequest = { '@type': 'sendPaymentForm' };
        paymentReq['input_invoice'] = this.paidMediaInvoice(messageId);
        paymentReq['payment_form_id'] = formId;
        paymentReq['order_info_id'] = '';
        paymentReq['shipping_option_id'] = '';
        paymentReq['tip_amount'] = 0;
        getTdClient().send(paymentReq).then((paymentResult: TdObject): void => {
          this.setPaidMediaPending(messageId, false);
          const success = (paymentResult['success'] as boolean | undefined) ?? false;
          const verificationUrl =
            (paymentResult['verification_url'] as string | undefined) ?? '';
          if (success) {
            promptAction.showToast({ message: $r('app.string.cp_paid_unlocked'), duration: 1600 });
            return;
          }
          if (verificationUrl !== '') {
            openWebUrl(getContext(this) as common.UIAbilityContext, verificationUrl, (): void => {
              promptAction.showToast({ message: $r('app.string.cp_cannot_open_payment'), duration: 1800 });
            });
            return;
          }
          promptAction.showToast({ message: $r('app.string.cp_payment_incomplete_short'), duration: 1600 });
        }).catch((e: TdError): void => {
          this.setPaidMediaPending(messageId, false);
          console.error(`ChatPage.sendPaymentForm failed: ${e.message}`);
          promptAction.showToast({ message: $r('app.string.cp_payment_failed'), duration: 1800 });
        });
      }).catch((): void => {
        this.setPaidMediaPending(messageId, false);
      });
    }).catch((e: TdError): void => {
      this.setPaidMediaPending(messageId, false);
      console.error(`ChatPage.get paid media payment form failed: ${e.message}`);
      promptAction.showToast({
        message: e.message !== '' ? e.message : $r('app.string.cp_no_payment_info'),
        duration: 1800
      });
    });
  }

  private onPaidMediaOpen(messageId: number): void {
    const entry = this.entryById(messageId);
    if (entry === null || entry.contentType !== 'paidMedia' || entry.paidMediaLocked) {
      return;
    }
    this.openViewer(messageId);
  }

  private onGiftCodeCopy(code: string): void {
    if (code.trim() === '') {
      promptAction.showToast({ message: $r('app.string.cp_code_unavailable'), duration: 1500 });
      return;
    }
    this.copyPlainText(code, str('cp_code_copied'));
  }

  private onGiveawayOpen(chatId: number, messageId: number): void {
    if (messageId <= 0) {
      return;
    }
    if (chatId === 0 || chatId === this.chatId) {
      this.onReplyTap(messageId);
      return;
    }
    const params: Record<string, Object> = {
      'chatId': chatId,
      'jumpTo': messageId
    };
    router.pushUrl({ url: 'pages/chat/ChatPage', params });
  }

  // Header avatar/title tap → detail page: users/bots get the personal
  // profile, groups/channels the chat profile.
  private openProfile(): void {
    if (this.headerProfileOpening || this.pageClosing) {
      return;
    }
    if (this.headerState === 'error') {
      this.resolveHeaderIdentity();
      return;
    }
    const storeUid = this.store !== null ? this.store.getPeerUserId() : 0;
    const uid = this.headerPeerUserId > 0 ? this.headerPeerUserId : storeUid;
    let url = '';
    let params: Record<string, Object>;
    if (uid > 0) {
      url = 'pages/profile/ProfilePage';
      params = { 'userId': uid };
    } else if (this.headerIdentityResolved ||
      (this.store !== null && this.store.getIsGroup())) {
      url = 'pages/profile/ChatProfilePage';
      params = { 'chatId': this.chatId };
    } else {
      promptAction.showToast({ message: $r('app.string.cp_profile_loading'), duration: 1200 });
      this.resolveHeaderIdentity();
      return;
    }
    this.headerProfileOpening = true;
    if (this.headerNavigationTimer !== -1) {
      clearTimeout(this.headerNavigationTimer);
    }
    this.headerNavigationTimer = setTimeout((): void => {
      this.headerNavigationTimer = -1;
      this.headerProfileOpening = false;
    }, CHAT_HEADER_NAV_GUARD_MS);
    router.pushUrl({ url, params }).catch((error: Error): void => {
      if (this.headerNavigationTimer !== -1) {
        clearTimeout(this.headerNavigationTimer);
        this.headerNavigationTimer = -1;
      }
      this.headerProfileOpening = false;
      console.error(`ChatPage.openProfile failed: ${error.message}`);
      promptAction.showToast({ message: $r('app.string.cp_cannot_open_profile'), duration: 1600 });
    });
  }

  // Refresh the '@' mention / '/' command suggestion panels for the new draft.
  private updateSuggestions(v: string): void {
    this.commandMenuOpen = false;
    const cmd = v.match(/^\/([a-zA-Z0-9_]*)(?:@([a-zA-Z0-9_]*))?$/);
    if (cmd !== null) {
      this.mentionItems = [];
      this.refreshCommands();
      return;
    }
    this.commandItems = [];
    const at = v.match(/(?:^|\s)@([a-zA-Z0-9_]*)$/);
    if (at !== null && this.isGroup && !this.isChannel) {
      this.refreshMentions(at[1]);
      return;
    }
    this.mentionItems = [];
    this.refreshInlineQuery(v);
    this.refreshStickerSuggestions(v);
  }

  // Bots can expose a Mini App on their menu button — surface it as a composer
  // icon that opens the app in the in-app browser.
  private refreshBotMiniApp(userId: number): void {
    this.botMiniAppUrlValue = '';
    if (userId <= 0) { return; }
    botMiniAppUrl(userId).then((url: string): void => {
      if (this.headerPeerUserId === userId) { this.botMiniAppUrlValue = url; }
    }).catch((): void => {});
  }

  private openBotMiniApp(): void {
    const url = this.botMiniAppUrlValue;
    if (url === '' || this.headerPeerUserId <= 0) { return; }
    openMiniApp(this.chatId, this.headerPeerUserId, url).then((resolved: string): void => {
      if (resolved === '') {
        promptAction.showToast({ message: $r('app.string.cp_cannot_open_miniapp'), duration: 1600 });
        return;
      }
      openWebUrl(getContext(this) as common.UIAbilityContext, resolved);
    }).catch((e: TdError): void => {
      console.error(`ChatPage.openBotMiniApp failed: ${e.message}`);
      promptAction.showToast({ message: $r('app.string.cp_cannot_open_miniapp'), duration: 1600 });
    });
  }

  // "@bot query" in the composer runs an inline query and shows the bot's
  // results above the input bar (tap one to send it).
  private refreshInlineQuery(v: string): void {
    const match = v.match(/^@([A-Za-z0-9_]{3,32})\s+(.*)$/);
    if (match === null) {
      if (this.inlineResults.length > 0) {
        this.inlineResults = [];
        this.inlineQueryId = '';
      }
      return;
    }
    const username = match[1];
    const query = match[2];
    const seq = ++this.inlineSeq;
    if (this.inlineTimer !== -1) { clearTimeout(this.inlineTimer); }
    this.inlineTimer = setTimeout((): void => {
      this.inlineTimer = -1;
      const req: TdRequest = { '@type': 'searchPublicChat' };
      req['username'] = username;
      getTdClient().send(req, 10000).then((chat: TdObject): Promise<InlineQueryPage> => {
        const type = chat['type'] as TdObject | undefined;
        const botId = type !== undefined ? ((type['user_id'] as number | undefined) ?? 0) : 0;
        if (botId === 0) { return Promise.reject(new TdError(404, 'not a bot')); }
        return getInlineResults(botId, this.chatId, query);
      }).then((page: InlineQueryPage): void => {
        if (seq !== this.inlineSeq) { return; }
        this.inlineQueryId = page.queryId;
        this.inlineResults = page.rows.slice(0, 24);
        for (const row of this.inlineResults) { this.downloadInlineThumb(row, seq); }
      }).catch((): void => {
        if (seq !== this.inlineSeq) { return; }
        this.inlineResults = [];
        this.inlineQueryId = '';
      });
    }, 320);
  }

  private downloadInlineThumb(row: InlineResultRow, seq: number): void {
    if (row.thumbFileId === 0) { return; }
    const req: TdRequest = { '@type': 'downloadFile' };
    req['file_id'] = row.thumbFileId;
    req['priority'] = 2;
    req['synchronous'] = true;
    getTdClient().send(req, 15000).then((file: TdObject): void => {
      if (seq !== this.inlineSeq) { return; }
      const local = file['local'] as TdObject | undefined;
      const path = local !== undefined ? ((local['path'] as string | undefined) ?? '') : '';
      if (path === '') { return; }
      this.inlineResults = this.inlineResults.map(
        (it: InlineResultRow): InlineResultRow => it.resultId === row.resultId
          ? {
            resultId: it.resultId, title: it.title, description: it.description,
            thumbFileId: it.thumbFileId, thumbPath: path, kind: it.kind
          } : it);
    }).catch((): void => {});
  }

  private pickInlineResult(row: InlineResultRow): void {
    if (this.inlineQueryId === '') { return; }
    const replyId = this.replyToId;
    sendInlineResult(this.chatId, this.inlineQueryId, row.resultId, replyId).then((): void => {
      this.draft = '';
      this.inlineResults = [];
      this.inlineQueryId = '';
      this.clearReply();
      this.atBottom = true;
    }).catch((e: TdError): void => {
      console.error(`ChatPage.sendInlineResult failed: ${e.message}`);
      promptAction.showToast({ message: $r('app.string.cp_inline_send_failed'), duration: 1600 });
    });
  }

  @Builder
  inlineResultsBar() {
    Scroll() {
      Row({ space: 8 }) {
        ForEach(this.inlineResults, (row: InlineResultRow) => {
          Column({ space: 3 }) {
            Stack({ alignContent: Alignment.Center }) {
              if (row.thumbPath !== '') {
                Image(`file://${row.thumbPath}`).draggable(false).width(56).height(56)
                  .objectFit(ImageFit.Cover).borderRadius(8);
              } else {
                SymbolGlyph($r('sys.symbol.doc')).fontSize(22)
                  .fontColor([COLOR_TEXT_SECONDARY]);
              }
            }.width(58).height(58)
            .backgroundColor($r('app.color.surface_alt')).borderRadius(8);
            if (row.title !== '') {
              Text(row.title).fontSize(10).fontColor(COLOR_TEXT_SECONDARY)
                .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                .constraintSize({ maxWidth: 62 });
            }
          }
          .onClick((): void => this.pickInlineResult(row));
        }, (row: InlineResultRow): string => `ir_${row.resultId}`);
      }.padding({ left: 10, right: 10, top: 6, bottom: 6 });
    }
    .scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
    .width('100%').height(88)
    .backgroundColor($r('app.color.surface'))
    .border({ width: { top: 0.7 }, color: $r('app.color.divider') });
  }

  // Typing a bare emoji offers matching stickers above the composer, as the
  // official clients do.
  private refreshStickerSuggestions(v: string): void {
    const text = v.trim();
    // Only a short pure-emoji draft qualifies (no letters/digits/spaces).
    const isEmojiOnly = text.length > 0 && text.length <= 8 &&
      !/[A-Za-z0-9\s]/.test(text);
    if (!isEmojiOnly) {
      if (this.stickerSuggestions.length > 0) { this.stickerSuggestions = []; }
      return;
    }
    const seq = ++this.stickerSuggestSeq;
    getStickersForEmoji(text).then((raw: TdObject[]): void => {
      if (seq !== this.stickerSuggestSeq) { return; }
      const items: StickerSuggestion[] = [];
      for (const st of raw.slice(0, 12)) {
        const file = st['sticker'] as TdObject | undefined;
        const fileId = file !== undefined ? ((file['id'] as number | undefined) ?? 0) : 0;
        const thumb = st['thumbnail'] as TdObject | undefined;
        const thumbFile = thumb !== undefined ? (thumb['file'] as TdObject | undefined) : undefined;
        const thumbId = thumbFile !== undefined ? ((thumbFile['id'] as number | undefined) ?? 0) : 0;
        if (fileId === 0) { continue; }
        items.push({ fileId, thumbId, thumbPath: '' });
      }
      this.stickerSuggestions = items;
      for (const item of items) { this.downloadSuggestionThumb(item, seq); }
    }).catch((): void => {});
  }

  private downloadSuggestionThumb(item: StickerSuggestion, seq: number): void {
    if (item.thumbId === 0) { return; }
    const req: TdRequest = { '@type': 'downloadFile' };
    req['file_id'] = item.thumbId;
    req['priority'] = 2;
    req['synchronous'] = true;
    getTdClient().send(req, 15000).then((file: TdObject): void => {
      if (seq !== this.stickerSuggestSeq) { return; }
      const local = file['local'] as TdObject | undefined;
      const path = local !== undefined ? ((local['path'] as string | undefined) ?? '') : '';
      if (path === '') { return; }
      this.stickerSuggestions = this.stickerSuggestions.map(
        (row: StickerSuggestion): StickerSuggestion => row.fileId === item.fileId
          ? { fileId: row.fileId, thumbId: row.thumbId, thumbPath: path } : row);
    }).catch((): void => {});
  }

  private sendSuggestedSticker(fileId: number): void {
    this.store?.sendSticker(fileId, 512, 512);
    rememberRecentSticker(fileId);
    this.draft = '';
    this.stickerSuggestions = [];
    this.stickerSuggestSeq++;
  }

  @Builder
  stickerSuggestionBar() {
    Scroll() {
      Row({ space: 8 }) {
        ForEach(this.stickerSuggestions, (row: StickerSuggestion) => {
          Stack({ alignContent: Alignment.Center }) {
            if (row.thumbPath !== '') {
              Image(`file://${row.thumbPath}`).draggable(false).width(56).height(56).objectFit(ImageFit.Contain);
            } else {
              LoadingProgress().width(20).height(20).color(COLOR_TEXT_SECONDARY);
            }
          }
          .width(62).height(62)
          .onClick((): void => this.sendSuggestedSticker(row.fileId));
        }, (row: StickerSuggestion): string => `sg_${row.fileId}`);
      }.padding({ left: 10, right: 10 });
    }
    .scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
    .width('100%').height(70)
    .backgroundColor($r('app.color.surface'))
    .border({ width: { top: 0.7 }, color: $r('app.color.divider') });
  }

  private refreshCommands(): void {
    this.ensureCommandsLoaded();
    this.applyCommandFilter();
  }

  private ensureCommandsLoaded(force: boolean = false): void {
    if (!force && (this.commandLoadState === 'loading' || this.commandLoadState === 'ready')) {
      return;
    }
    const seq: number = ++this.commandLoadSeq;
    const chatId: number = this.chatId;
    const peer: number = this.store !== null ? this.store.getPeerUserId() : 0;
    this.commandLoadState = 'loading';
    this.commandLoadError = '';
    loadBotCommands(getTdClient(), chatId, peer).then((items: CommandItem[]) => {
      if (seq !== this.commandLoadSeq || chatId !== this.chatId) {
        return;
      }
      this.allCommands = items;
      this.commandLoadState = 'ready';
      this.commandLoadError = '';
      // Telegram's persistent 菜单 pill belongs to a private bot chat. Group
      // commands remain available through '/' and include @bot usernames.
      this.botMenuAvailable = peer > 0 && items.length > 0;
      this.applyCommandFilter();
    }).catch((e: TdError) => {
      if (seq !== this.commandLoadSeq || chatId !== this.chatId) {
        return;
      }
      console.error(`ChatPage.loadBotCommands failed: ${e.message}`);
      this.allCommands = [];
      this.commandItems = [];
      this.commandLoadState = 'error';
      this.commandLoadError = str('cp_commands_failed');
      this.botMenuAvailable = false;
    });
  }

  private commandText(item: CommandItem): string {
    return `/${item.command}${item.botUsername !== '' ? `@${item.botUsername}` : ''}`;
  }

  private commandPanelActive(): boolean {
    return this.commandMenuOpen ||
      this.draft.match(/^\/([a-zA-Z0-9_]*)(?:@([a-zA-Z0-9_]*))?$/) !== null;
  }

  // Filter against the CURRENT draft, so a slow catalog load can't show stale results.
  private applyCommandFilter(): void {
    if (this.commandMenuOpen) {
      this.commandItems = this.commandLoadState === 'ready' ? this.allCommands.slice(0, 20) : [];
      return;
    }
    const m = this.draft.match(/^\/([a-zA-Z0-9_]*)(?:@([a-zA-Z0-9_]*))?$/);
    if (m === null) {
      this.commandItems = [];
      return;
    }
    if (this.commandLoadState !== 'ready') {
      this.commandItems = [];
      return;
    }
    const q = m[1].toLowerCase();
    const botQuery = (m[2] ?? '').toLowerCase();
    this.commandItems = this.allCommands.filter((c: CommandItem): boolean =>
      c.command.toLowerCase().startsWith(q) &&
      (botQuery === '' || c.botUsername.toLowerCase().startsWith(botQuery))).slice(0, 20);
  }

  private refreshMentions(query: string): void {
    const seq = ++this.mentionSeq;
    searchMentions(getTdClient(), this.chatId, query).then((items: MentionItem[]) => {
      // Drop the response if a newer query fired or the '@' trigger is gone.
      if (seq !== this.mentionSeq || this.draft.match(/(?:^|\s)@([a-zA-Z0-9_]*)$/) === null) {
        return;
      }
      this.mentionItems = items;
    });
  }

  // Replace the trailing '@token' with the chosen member.
  private pickMention(item: MentionItem): void {
    const idx = this.draft.lastIndexOf('@');
    const head = idx >= 0 ? this.draft.substring(0, idx) : this.draft;
    this.draft = `${head}${mentionToken(item.name, item.username)} `;
    this.mentionItems = [];
    setTimeout((): void => { focusControl.requestFocus('chat_composer'); }, 0);
  }

  // Long press on a group message avatar → append that sender's mention to the
  // draft. The message entry has the sender's name but not their username, so
  // the username is fetched here; the name is the fallback if it has none.
  private mentionSender(userId: number, fallbackName: string): void {
    mentionOfUser(getTdClient(), userId).then((item: MentionItem): void => {
      const name = item.name !== '' ? item.name : fallbackName;
      const token = mentionToken(name, item.username);
      if (token === '') {
        return;
      }
      this.draft = appendMention(this.draft, token);
      this.mentionItems = [];
      setTimeout((): void => { focusControl.requestFocus('chat_composer'); }, 0);
    });
  }

  private pickCommand(item: CommandItem): void {
    this.draft = this.commandText(item);
    this.commandItems = [];
    this.commandMenuOpen = false;
    this.doSend();
  }

  // Viewer "保存到相册": photos save right away (full-res preferred); a video
  // that isn't fully local yet starts its download and saves automatically on
  // completion (see the pendingGallerySaveId check in the store subscription).
  private saveViewerMedia(): void {
    const e = this.entryById(this.viewerMsgId);
    if (e === null) {
      return;
    }
    const ctx = getContext(this) as common.UIAbilityContext;
    if (this.mediaEntryIsVideo(e)) {
      if (e.videoPath !== '') {
        saveMediaToGallery(ctx, e.videoPath, true);
      } else {
        this.pendingGallerySaveId = e.id;
        if (this.store !== null) {
          this.store.requestVideoDownload(e.id, true, e.videoFailed);
        }
        promptAction.showToast({ message: $r('app.string.cp_video_downloading_save'), duration: 2500 });
      }
      return;
    }
    if (e.photoFullPath !== '') {
      saveMediaToGallery(ctx, e.photoFullPath, false);
      return;
    }
    if (e.photoFullFileId !== 0) {
      this.pendingGallerySaveId = e.id;
      if (this.store !== null) {
        this.store.requestFullPhoto(e.id, e.photoFullFailed);
      }
      promptAction.showToast({ message: $r('app.string.cp_photo_downloading_save'), duration: 2200 });
      return;
    }
    if (e.photoPath !== '') {
      saveMediaToGallery(ctx, e.photoPath, false);
    } else {
      promptAction.showToast({ message: $r('app.string.cp_photo_not_available'), duration: 1800 });
    }
  }

  private processAutomaticGallerySave(list: MessageEntry[]): void {
    if (this.autoSaveInFlight || this.autoSavePendingIds.length === 0) { return; }
    let target: MessageEntry | undefined = undefined;
    let path: string = '';
    let video: boolean = false;
    for (const messageId of this.autoSavePendingIds) {
      const entry = list.find((item: MessageEntry): boolean => item.id === messageId);
      if (entry === undefined || entry.isOutgoing ||
        (entry.contentType !== 'photo' && entry.contentType !== 'video')) {
        this.autoSavePendingIds = this.autoSavePendingIds.filter((id: number): boolean => id !== messageId);
        continue;
      }
      if (entry.contentType === 'video') {
        if (entry.videoFailed) {
          this.autoSavePendingIds = this.autoSavePendingIds.filter((id: number): boolean => id !== messageId);
          continue;
        }
        if (entry.videoPath !== '') { target = entry; path = entry.videoPath; video = true; break; }
      } else {
        if (entry.photoFullFailed) {
          this.autoSavePendingIds = this.autoSavePendingIds.filter((id: number): boolean => id !== messageId);
          continue;
        }
        if (entry.photoFullPath !== '') { target = entry; path = entry.photoFullPath; break; }
        if (entry.photoFullFileId === 0 && entry.photoPath !== '') {
          target = entry; path = entry.photoPath; break;
        }
      }
    }
    if (target === undefined || path === '') { return; }
    const id = target.id;
    this.autoSavePendingIds = this.autoSavePendingIds.filter((value: number): boolean => value !== id);
    this.autoSaveInFlight = true;
    saveMediaToGallery(getContext(this) as common.UIAbilityContext, path, video).then((): void => {
      this.autoSaveInFlight = false;
      this.processAutomaticGallerySave(this.messages);
    }).catch((): void => {
      this.autoSaveInFlight = false;
      this.processAutomaticGallerySave(this.messages);
    });
  }

  private openDownloadedFile(message: MessageEntry): void {
    if (message.videoPath === '' || this.fileOpenInFlightId !== 0) {
      return;
    }
    const messageId: number = message.id;
    this.fileOpenInFlightId = messageId;
    openLocalFile(
      getContext(this) as common.UIAbilityContext,
      message.videoPath,
      fileOpenMimeType(message.videoFileName, message.videoMimeType)
    ).then((opened: boolean): void => {
      if (this.fileOpenInFlightId === messageId) {
        this.fileOpenInFlightId = 0;
      }
      if (!opened) {
        promptAction.showToast({
          message: $r('app.string.cp_no_app_for_file'),
          duration: 2200
        });
      }
    }).catch((caught: Object): void => {
      if (this.fileOpenInFlightId === messageId) {
        this.fileOpenInFlightId = 0;
      }
      console.error(`ChatPage.openDownloadedFile failed: ${JSON.stringify(caught)}`);
      promptAction.showToast({ message: $r('app.string.cp_file_open_failed'), duration: 1800 });
    });
  }

  // Document card tap: an on-demand download retains the open intent, so the
  // file launches immediately when TDLib reports completion.
  private onFileTap(messageId: number): void {
    const m = this.messages.find((x: MessageEntry) => x.id === messageId);
    if (m === undefined || m.contentType !== 'file' || this.store === null) {
      return;
    }
    // The most recent file action wins. This avoids racing an external viewer
    // and the save picker when the user changes intent during a download.
    this.pendingFileSaveId = 0;
    if (m.videoPath !== '') {
      this.pendingFileOpenId = 0;
      this.openDownloadedFile(m);
      return;
    }
    if (m.videoFileId === 0) {
      this.pendingFileOpenId = 0;
      promptAction.showToast({ message: $r('app.string.cp_file_unavailable'), duration: 1600 });
      return;
    }
    this.pendingFileOpenId = messageId;
    this.store.requestVideoDownload(messageId, true, m.videoFailed);
    promptAction.showToast({
      message: m.videoFailed ? $r('app.string.cp_redownloading_file')
        : (m.mediaDownloadActive ? $r('app.string.cp_file_downloading_open') : $r('app.string.cp_file_download_started')),
      duration: 1700
    });
  }

  private utilityActionAllowed(): boolean {
    const now = Date.now();
    if (now - this.utilityActionAtMs < 550) {
      return false;
    }
    this.utilityActionAtMs = now;
    return true;
  }

  private openSharedContact(userId: number, phone: string, vcard: string): void {
    if (!this.utilityActionAllowed()) {
      return;
    }
    if (userId > 0) {
      const params: Record<string, Object> = { 'userId': userId };
      router.pushUrl({ url: 'pages/profile/ProfilePage', params: params }).catch(() => {
        promptAction.showToast({ message: $r('app.string.cp_cannot_open_contact'), duration: 1500 });
      });
      return;
    }
    if (vcard.trim() !== '') {
      const context = getContext(this) as common.UIAbilityContext;
      const path = `${context.cacheDir}/shared_contact_${Date.now()}.vcf`;
      try {
        const file = fs.openSync(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE);
        fs.writeSync(file.fd, vcard);
        fs.closeSync(file);
        openLocalFile(context, path, 'text/vcard').then((opened: boolean): void => {
          if (!opened) {
            this.copyPlainText(vcard, str('cp_contact_copied'));
          }
        }).catch((caught: Object): void => {
          console.error(`ChatPage.openSharedContact failed: ${JSON.stringify(caught)}`);
          this.copyPlainText(vcard, str('cp_contact_copied'));
        });
      } catch (caught) {
        console.error(`ChatPage.write shared contact failed: ${caught}`);
        this.copyPlainText(vcard, str('cp_contact_copied'));
      }
      return;
    }
    this.openSharedPhone(phone, true);
  }

  private openSharedPhone(phone: string, skipGuard: boolean = false): void {
    if (!skipGuard && !this.utilityActionAllowed()) {
      return;
    }
    const normalized = phone.trim().replace(/[^0-9+*#]/g, '');
    if (normalized === '') {
      promptAction.showToast({ message: $r('app.string.cp_contact_no_phone'), duration: 1500 });
      return;
    }
    openUrl(getContext(this) as common.UIAbilityContext, `tel:${normalized}`, (): void => {
      promptAction.showToast({ message: $r('app.string.cp_no_dialer'), duration: 1600 });
    });
  }

  private openSharedLocation(
    latitude: number,
    longitude: number,
    label: string,
    valid: boolean
  ): void {
    if (!this.utilityActionAllowed()) {
      return;
    }
    const cleanLabel = label.trim();
    if (!valid && cleanLabel === '') {
      promptAction.showToast({ message: $r('app.string.cp_no_location'), duration: 1500 });
      return;
    }
    const coordinate = `${latitude},${longitude}`;
    const query = encodeURIComponent(cleanLabel !== '' ? cleanLabel : coordinate);
    const geoUri = valid ? `geo:${latitude},${longitude}?q=${query}` : `geo:0,0?q=${query}`;
    const webFallback = valid
      ? `https://www.openstreetmap.org/?mlat=${latitude}&mlon=${longitude}#map=16/${latitude}/${longitude}`
      : `https://www.openstreetmap.org/search?query=${query}`;
    openUrl(getContext(this) as common.UIAbilityContext, geoUri, (): void => {
      openUrl(getContext(this) as common.UIAbilityContext, webFallback, (): void => {
        promptAction.showToast({ message: $r('app.string.cp_no_map_app'), duration: 1700 });
      });
    });
  }

  // Document card save arrow: opens the system "save as" picker once the file
  // is local; otherwise starts the download and saves automatically when done.
  private onFileSave(messageId: number): void {
    const m = this.messages.find((x: MessageEntry) => x.id === messageId);
    if (m === undefined || m.contentType !== 'file' || this.store === null) {
      return;
    }
    this.pendingFileOpenId = 0;
    if (m.videoPath !== '') {
      this.pendingFileSaveId = 0;
      saveFileToLocal(getContext(this) as common.UIAbilityContext, m.videoPath, m.videoFileName);
      return;
    }
    if (m.videoFileId === 0) {
      this.pendingFileSaveId = 0;
      promptAction.showToast({ message: $r('app.string.cp_file_unavailable'), duration: 1600 });
      return;
    }
    this.pendingFileSaveId = messageId;
    this.store.requestVideoDownload(messageId, true, m.videoFailed);
    promptAction.showToast({
      message: m.videoFailed ? $r('app.string.cp_redownload_then_save')
        : $r('app.string.cp_downloading_then_save'),
      duration: 2200
    });
  }

  // --- header "more" menu actions ---
  private toggleChatMute(): void {
    if (this.headerMuteUpdating) {
      return;
    }
    const previous = this.isMuted;
    const next = !previous;
    this.headerMuteUpdating = true;
    this.isMuted = next;
    // setMute 会先读取完整通知设置，所以在 TDLib 接受修改前保持更新锁；
    // 否则任意一次聊天刷新都会立刻用 ChatStore 的旧值覆盖乐观状态。
    setMute(this.chatId, next ? MUTE_LONG : 0).then((success: boolean): void => {
      if (!success) {
        this.isMuted = previous;
      }
      this.headerMuteUpdating = false;
    });
  }

  private confirmClearHistory(): void {
    AlertDialog.show({
      message: $r('app.string.cp_clear_history_confirm'),
      autoCancel: true,
      primaryButton: {
        value: $r('app.string.cancel'),
        action: (): void => {}
      },
      secondaryButton: {
        value: $r('app.string.clear_all'),
        fontColor: '#FF3B30',
        action: (): void => {
          const req: TdRequest = { '@type': 'deleteChatHistory' };
          req['chat_id'] = this.chatId;
          req['remove_from_chat_list'] = false;
          req['revoke'] = false;
          getTdClient().send(req).then(() => {
            promptAction.showToast({ message: $r('app.string.cp_history_cleared'), duration: 2000 });
          }).catch((e: TdError) => {
            console.error(`ChatPage.deleteChatHistory failed: ${e.message}`);
            promptAction.showToast({ message: $r('app.string.cp_clear_failed'), duration: 2000 });
          });
        }
      }
    });
  }

  private confirmLeaveChat(): void {
    AlertDialog.show({
      message: str('cp_leave_confirm', this.title),
      autoCancel: true,
      primaryButton: {
        value: $r('app.string.cancel'),
        action: (): void => {}
      },
      secondaryButton: {
        value: $r('app.string.cp_leave'),
        fontColor: '#FF3B30',
        action: (): void => {
          const req: TdRequest = { '@type': 'leaveChat' };
          req['chat_id'] = this.chatId;
          getTdClient().send(req).then(() => {
            router.back();
          }).catch((e: TdError) => {
            console.error(`ChatPage.leaveChat failed: ${e.message}`);
            promptAction.showToast({ message: $r('app.string.cp_leave_failed'), duration: 2000 });
          });
        }
      }
    });
  }

  // actionMenuRow's onTap fires directly on click; the header dropdown also
  // needs to close itself first (unlike the bubble menu, whose bindContextMenu
  // host closes on its own), so every row action is wrapped through here.
  private closeHeaderMenuThen(action: () => void): () => void {
    return (): void => {
      this.headerMenuShow = false;
      action();
    };
  }

  @Builder
  headerMenu() {
    Column() {
      actionMenuRow('sys.symbol.magnifyingglass', str('cp_search'), false,
        this.closeHeaderMenuThen((): void => { this.enterSearch(); }));
      Divider().color($r('app.color.divider')).strokeWidth(0.7);
      actionMenuRow('sys.symbol.info_circle', str('cp_profile'), false,
        this.closeHeaderMenuThen((): void => { this.openProfile(); }));
      Divider().color($r('app.color.divider')).strokeWidth(0.7);
      actionMenuRow(this.isMuted ? 'sys.symbol.bell' : 'sys.symbol.bell_slash',
        this.headerMuteUpdating ? str('cp_updating_notifications') : (this.isMuted ? str('cp_unmute') : str('cp_mute')),
        false, this.closeHeaderMenuThen((): void => { this.toggleChatMute(); }));
      Divider().color($r('app.color.divider')).strokeWidth(0.7);
      Divider().color($r('app.color.divider')).strokeWidth(0.7);
      actionMenuRow('sys.symbol.clock', str('cp_auto_delete'), false,
        this.closeHeaderMenuThen((): void => { this.chooseAutoDelete(); }));
      Divider().color($r('app.color.divider')).strokeWidth(0.7);
      actionMenuRow('sys.symbol.calendar', str('sched_title'), false,
        this.closeHeaderMenuThen((): void => { this.openScheduledSheet(); }));
      actionMenuRow('sys.symbol.calendar_badge_clock', str('cp_jump_to_date'), false,
        this.closeHeaderMenuThen((): void => { this.pickJumpDate(); }));
      if (this.liveLocationActive) {
        actionMenuRow('sys.symbol.stop_circle', str('cp_stop_location'), true,
          this.closeHeaderMenuThen((): void => { this.confirmStopLiveLocation(); }));
      }
      Divider().color($r('app.color.divider')).strokeWidth(0.7);
      // 总开关开着时这个会话默认就在翻，所以这一项显示「关闭翻译」；总开关
      // 关着时它就是"只翻这个会话"的入口。单条消息的翻译不受这里影响。
      actionMenuRow('sys.symbol.translate',
        this.translationActive() ? str('cp_translate_chat_off') : str('cp_translate_chat_on'),
        false, this.closeHeaderMenuThen((): void => { this.toggleTranslatable(); }));
      actionMenuRow('sys.symbol.xmark_circle', str('cp_clear_history'), false,
        this.closeHeaderMenuThen((): void => { this.confirmClearHistory(); }));
      if (this.isGroup && this.membershipState === 'writable') {
        Divider().color($r('app.color.divider')).strokeWidth(0.7);
        actionMenuRow('sys.symbol.trash', this.isChannel ? str('cp_leave_channel') : str('cp_leave_group'), true,
          this.closeHeaderMenuThen((): void => { this.confirmLeaveChat(); }));
      }
    }
    .width(262)
    .padding({ top: 6, bottom: 6 });
  }

  // Horizontal center (vp, window coords) of the smiley button — the anchor
  // the emoji panel scales out of / back into.
  private emojiBtnCx: number = 48;
  @State inputBarH: number = 64;
  // 顶部悬浮 chrome（标题栏 + 横幅）的实测高度，用来给列表让位。
  @State headerChromeH: number = 0;
  @State listViewportH: number = 0;
  // Height of every persistent bottom surface (composer/reply/Bot keyboard or
  // membership/search bar). The List uses it only as END offset: rows still
  // travel behind the floating input, while the final row can clear it.
  @State bottomChromeH: number = 76;
  private bottomChromeLayoutSeq: number = 0;
  // Measured bot-keyboard height; with the input bar it makes up the bottom
  // chrome the scroll-to-bottom FAB has to clear.
  @State replyKbH: number = 0;
  // "Fake" animation: the open/close transition flies an empty white shell;
  // the real panel content (hundreds of emoji + sticker players) mounts only
  // after the animation lands, so frames stay cheap.
  @State panelContentReady: boolean = false;
  private panelReadySeq: number = 0;

  private composerBottomGap(): number {
    return this.keyboardH > 0 ? 6 : Math.max(8, this.bottomSafe);
  }

  // TextArea's intrinsic minimum is taller than the old 48vp input capsule on
  // some phones/font scales. Give it an explicit content-driven height so the
  // empty composer keeps the original silhouette and only grows after typing.
  //
  // The cap is derived from the real line box rather than a round number: at
  // lineHeight 22 and 9+9 padding, four lines need 106vp. The old cap of 104
  // was six short, so the fourth line was already clipped — and past the cap
  // the TextArea has to scroll internally, which it can only do if nothing
  // truncates the layout (see the removed maxLines at the call site).
  private composerEditorHeight(): number {
    const chunks: string[] = this.draft.split('\n');
    let lines: number = 0;
    for (let i: number = 0; i < chunks.length; i++) {
      // Rough wrap estimate: the exact break depends on the glyphs, and
      // over-counting only grows the box a line early.
      lines += Math.max(1, Math.ceil(chunks[i].length / 18));
    }
    return COMPOSER_LINE_H * Math.max(1, Math.min(COMPOSER_MAX_LINES, lines))
      + COMPOSER_EDITOR_PAD * 2;
  }

  // 渐变模糊：只在顶部 chrome 那一条区域内从"全糊"过渡到"清晰"。
  // fractionStops 是 [模糊比例, 位置]，位置沿 direction 从 0 到 1；
  // direction 取 Bottom 时 0 就是列表顶端。
  private headerBlurStops(): [number, number][] {
    const viewport: number = this.listViewportH;
    if (viewport <= 0 || this.headerChromeH <= 0) {
      return [[0, 0], [0, 1]];
    }
    // 过渡带正好是 chrome 那一条：列表顶端（也就是屏幕最上沿）全糊，到 bar
    // 的下边缘归零。消息往上滑时是连续糊掉的，不是撞上一条硬边。
    //
    // 上半段是**全糊的平台段**而不是单点：只在位置 0 取 1 的话，全糊处是条
    // 零宽度的线，肉眼看到的最糊程度远达不到 100%。
    const end: number = Math.min(0.6, this.headerChromeH / viewport);
    return [[1, 0], [1, end * 0.62], [0, end]];
  }

  // 只看省电：这里的顾虑是逐帧实时渲染的功耗，跟"聊天背景特效"是两回事。
  // 先前误用了 backgroundEffectsEnabled()，它还附带自定义背景/特效开关的条件，
  // 会把模糊直接打成 0。
  private headerBlurRadius(): number {
    return !this.powerSaving && this.headerChromeH > 0 ? HEADER_BLUR_RADIUS : 0;
  }

  private updateBottomChromeHeight(height: number): void {
    if (height <= 0 || Math.abs(height - this.bottomChromeH) < 0.5) {
      return;
    }
    const keepTailVisible: boolean = this.atBottom && this.viewerMsgId === 0;
    this.bottomChromeH = height;
    if (keepTailVisible) {
      const seq: number = ++this.bottomChromeLayoutSeq;
      setTimeout((): void => {
        if (seq === this.bottomChromeLayoutSeq && this.atBottom) {
          this.scroller.scrollEdge(Edge.Bottom);
        }
      }, 0);
    }
  }

  private toggleReplyKeyboard(): void {
    if (this.replyKeyboard === null || this.replyKeyboardSendingKey !== '') {
      return;
    }
    const openingCustom: boolean = this.replyKbCollapsed;
    this.setEmojiPanel(false);
    this.mentionItems = [];
    this.commandItems = [];
    this.commandMenuOpen = false;
    if (openingCustom) {
      this.composerController.stopEditing();
      this.composerFocused = false;
    }
    this.replyKbCollapsed = !this.replyKbCollapsed;
    if (!openingCustom) {
      // Switching from the Bot keyboard back to text input should actually
      // present the IME rather than leaving an empty gap below the composer.
      setTimeout((): void => { focusControl.requestFocus('chat_composer'); }, 0);
    }
  }

  // Show/hide the emoji/sticker panel without resizing the message viewport.
  // 发出去之后的收尾。残影是独立浮层，和面板收起**并行**跑：先前把关面板
  // 排在飞出动画之后，串行等待让面板要一秒多才下去，感觉像卡住了。
  private finishStickerSend(thumbPath: string, x: number, y: number): void {
    if (this.stickerGhostTimer !== -1) {
      clearTimeout(this.stickerGhostTimer);
      this.stickerGhostTimer = -1;
    }
    // 立刻开始收面板（内部已把卸载与动画分帧）。
    this.setEmojiPanel(false);
    const duration: number = this.chatEffectDuration(KEY_POWER_EFFECT_MENU, STICKER_FLY_MS);
    if (duration === 0 || thumbPath === '') {
      this.stickerGhostPath = '';
      return;
    }
    this.stickerGhostPath = thumbPath;
    this.stickerGhostX = x;
    this.stickerGhostY = y;
    this.stickerGhostFly = false;
    // 起始态先落地一帧，否则终态和初始态在同一帧里，动画不会跑。
    setTimeout((): void => { this.stickerGhostFly = true; }, 16);
    this.stickerGhostTimer = setTimeout((): void => {
      this.stickerGhostTimer = -1;
      this.stickerGhostPath = '';
      this.stickerGhostFly = false;
    }, duration + 40);
  }

  private setEmojiPanel(show: boolean): void {
    if (this.showEmojiPanel === show) {
      return;
    }
    const seq = ++this.panelReadySeq;
    const duration: number = this.chatEffectDuration(KEY_POWER_EFFECT_MENU, 220);
    if (show) {
      this.emojiPanelClosing = false;
      this.composerController.stopEditing();
      this.composerFocused = false;
      this.replyKbCollapsed = true;
      animateTo({
        duration, curve: Curve.EaseOut
      }, () => {
        this.showEmojiPanel = true;
      });
      if (duration === 0) {
        this.panelContentReady = true;
        return;
      }
      setTimeout(() => {
        if (seq === this.panelReadySeq && this.showEmojiPanel) {
          this.panelContentReady = true; // content pops in after the shell lands
        }
      }, duration + 20);
    } else {
      this.emojiPanelClosing = true;
      // 卸载重内容和启动收起动画必须分帧。面板里同时挂着三个 picker（自定义
      // 表情常驻，贴纸/GIF 访问过就常驻），一次性卸掉实测 ~51ms；和 animateTo
      // 挤在同一个同步块里，动画一开场就已经掉帧。
      //
      // 先在没有动画运行时卸载 —— 这一下花在静止状态下，观感是内容一闪而空；
      // 下一帧再对着一个空面板启动收起动画，动画本身就是廉价的。
      this.panelContentReady = false;
      setTimeout((): void => {
        if (seq !== this.panelReadySeq) {
          return;
        }
        animateTo({
          duration, curve: Curve.EaseOut
        }, () => {
          this.showEmojiPanel = false;
          this.emojiPanelClosing = false;
        });
      }, 0);
    }
  }

  // 菜单 pill: toggle the full bot-command catalog in the suggestion panel.
  private toggleBotMenu(): void {
    if (this.commandMenuOpen) {
      this.commandMenuOpen = false;
      this.commandItems = [];
    } else {
      this.mentionItems = [];
      this.setEmojiPanel(false);
      this.replyKbCollapsed = true;
      this.commandMenuOpen = true;
      this.ensureCommandsLoaded();
      this.applyCommandFilter();
    }
  }

  private insertEmoji(e: string): void {
    this.draft = `${this.draft}${e}`;
    this.updateSuggestions(this.draft);
  }

  // Copy a picker URI into the sandbox so TDLib can read it; '' on failure.
  // Single copy path for every picker (media, document, audio): they used to
  // inline three near-copies of this, two of them without the sequence counter.
  private copyUriToCache(uri: string): string {
    try {
      const cacheDir = (getContext(this) as common.UIAbilityContext).cacheDir;
      const dest = cacheDestPath(cacheDir, uri, ++this.mediaCopySeq, Date.now());
      const src = fs.openSync(uri, fs.OpenMode.READ_ONLY);
      fs.copyFileSync(src.fd, dest);
      fs.closeSync(src);
      return dest;
    } catch (e) {
      console.error(`ChatPage.copyUriToCache failed: ${e}`);
      return '';
    }
  }

  // Voice bubble asked for its file (eager download hasn't landed yet).
  private onVoiceTap(messageId: number): void {
    const entry: MessageEntry | null = this.entryById(messageId);
    if (entry === null || entry.contentType !== 'voice') {
      return;
    }
    if (entry.videoFileId === 0) {
      promptAction.showToast({ message: $r('app.string.cp_voice_unavailable'), duration: 1600 });
      return;
    }
    if (this.store !== null) {
      this.store.requestVideoDownload(messageId, false, entry.videoFailed);
    }
    promptAction.showToast({
      message: entry.videoFailed ? $r('app.string.cp_redownloading_voice') : $r('app.string.cp_voice_loading'),
      duration: 1400
    });
  }

  private onVoicePlaybackStarted(messageId: number): void {
    this.store?.markVoiceListened(messageId);
  }

  private replaceMedia(messageId: number): void {
    const msg = this.findMsg(messageId);
    const store = this.store;
    if (msg === null || store === null || this.mediaPickerOpen) { return; }
    this.mediaPickerOpen = true;
    const photoPicker = new photoAccessHelper.PhotoViewPicker();
    const opts = new photoAccessHelper.PhotoSelectOptions();
    opts.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_VIDEO_TYPE;
    opts.maxSelectNumber = 1;
    photoPicker.select(opts).then((res: photoAccessHelper.PhotoSelectResult): void => {
      this.mediaPickerOpen = false;
      if (res.photoUris.length === 0) { return; }
      const path = this.copyUriToCache(res.photoUris[0]);
      if (path === '') {
        promptAction.showToast({ message: $r('app.string.cp_cannot_read_file'), duration: 1600 });
        return;
      }
      store.editMediaAsync(messageId, path, isVideoPath(path), msg.text).then((): void => {
        promptAction.showToast({ message: $r('app.string.cp_media_replaced'), duration: 1500 });
      }).catch((e: TdError): void => {
        console.error(`ChatPage.replaceMedia failed: ${e.message}`);
        promptAction.showToast({ message: $r('app.string.cp_replace_failed'), duration: 1700 });
      });
    }).catch((): void => { this.mediaPickerOpen = false; });
  }

  private pickAndSendMedia(): void {
    if (this.mediaPickerOpen || this.composerSending || this.store === null) {
      return;
    }
    this.mediaPickerOpen = true;
    const photoPicker = new photoAccessHelper.PhotoViewPicker();
    const opts = new photoAccessHelper.PhotoSelectOptions();
    opts.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_VIDEO_TYPE;
    opts.maxSelectNumber = 9;
    photoPicker.select(opts).then((res: photoAccessHelper.PhotoSelectResult) => {
      this.mediaPickerOpen = false;
      if (res.photoUris.length === 0 || this.store === null) {
        return;
      }
      const captionSnapshot = this.draft;
      const caption = captionSnapshot.trim();
      const replyId = this.replyToId;
      const items: MediaSendItem[] = [];
      let skipped = 0;
      for (const uri of res.photoUris) {
        const path = this.copyUriToCache(uri);
        if (path === '') {
          skipped++;
          continue;
        }
        items.push({ path, isVideo: isVideoPath(path) });
      }
      if (items.length === 0) {
        promptAction.showToast({ message: $r('app.string.cp_media_read_failed'), duration: 1800 });
        return;
      }
      if (skipped > 0) {
        promptAction.showToast({ message: plural('cp_media_skipped', skipped, skipped), duration: 1800 });
      }
      const store: MessageStore = this.store;
      this.composerSending = true;
      this.atBottom = true;
      this.stayAtUnread = false;
      store.sendMedia(items, caption, replyId).then((): void => {
        if (this.draft === captionSnapshot) {
          this.draft = '';
        }
        if (this.replyToId === replyId) {
          this.clearReply();
        }
        this.composerSending = false;
      }).catch((e: TdError): void => {
        this.composerSending = false;
        console.error(`ChatPage.sendMedia failed: ${e.message}`);
        promptAction.showToast({ message: $r('app.string.cp_photo_send_failed'), duration: 2000 });
      });
    }).catch((e: Object) => {
      this.mediaPickerOpen = false;
      console.error(`ChatPage.pickAndSendMedia failed: ${JSON.stringify(e)}`);
      promptAction.showToast({ message: $r('app.string.cp_cannot_open_picker'), duration: 1800 });
    });
  }

  // --- voice recording (mic button) ---
  private startRecording(): void {
    if (this.recordingStarting || this.isRecording || this.store === null) {
      return;
    }
    this.setEmojiPanel(false);
    this.replyKbCollapsed = true;
    this.mentionItems = [];
    this.commandItems = [];
    this.commandMenuOpen = false;
    this.composerController.stopEditing();
    this.composerFocused = false;
    this.recordingStarting = true;
    const seq: number = ++this.recordingSeq;
    const rec = new VoiceRecorder();
    this.voiceRec = rec;
    rec.start(getContext(this) as common.UIAbilityContext).then((ok: boolean) => {
      if (seq !== this.recordingSeq) {
        rec.cancel();
        return;
      }
      this.recordingStarting = false;
      if (!ok) {
        this.voiceRec = null;
        promptAction.showToast({ message: $r('app.string.cp_record_failed_permission'), duration: 2500 });
        return;
      }
      this.isRecording = true;
      this.recordSeconds = 0;
      this.recordTimer = setInterval(() => { this.recordSeconds += 1; }, 1000);
    }).catch((e: Object): void => {
      if (seq !== this.recordingSeq) {
        return;
      }
      this.recordingStarting = false;
      this.voiceRec = null;
      console.error(`ChatPage.startRecording failed: ${JSON.stringify(e)}`);
      promptAction.showToast({ message: $r('app.string.cp_record_failed'), duration: 1800 });
    });
  }

  private stopRecordTimer(): void {
    if (this.recordTimer !== -1) {
      clearInterval(this.recordTimer);
      this.recordTimer = -1;
    }
  }

  private finishRecording(): void {
    this.recordingSeq++;
    const rec = this.voiceRec;
    this.voiceRec = null;
    this.recordingStarting = false;
    this.stopRecordTimer();
    this.isRecording = false;
    if (rec === null) {
      return;
    }
    rec.stop().then((duration: number) => {
      if (rec.path !== '' && this.store !== null) {
        this.atBottom = true;
        this.store.sendVoiceNote(rec.path, duration);
      }
    });
  }

  private cancelRecording(): void {
    this.recordingSeq++;
    const rec = this.voiceRec;
    this.voiceRec = null;
    this.recordingStarting = false;
    this.stopRecordTimer();
    this.isRecording = false;
    if (rec !== null) {
      rec.cancel();
    }
  }

  private formatRecSeconds(): string {
    const m = Math.floor(this.recordSeconds / 60);
    const s = this.recordSeconds % 60;
    return `${m}:${`${s}`.padStart(2, '0')}`;
  }

  // --- 定时消息管理 ---

  // Loading and the send-now/delete actions live in ScheduledSheet, which
  // fetches on mount.
  private openScheduledSheet(): void {
    this.headerMenuShow = false;
    this.showScheduledSheet = true;
  }

  private attachMenuItems(): MenuElement[] {
    const items: MenuElement[] = [
      { value: $r('app.string.cp_photo_or_video'), action: (): void => {
        this.setEmojiPanel(false);
        this.pickAndSendMedia();
      } } as MenuElement,
      { value: $r('app.string.cp_video_message'), action: (): void => {
        this.setEmojiPanel(false);
        this.openVideoNoteRecorder();
      } } as MenuElement,
      { value: $r('app.string.storage_file'), action: (): void => {
        this.setEmojiPanel(false);
        this.pickAndSendFile();
      } } as MenuElement,
      { value: $r('app.string.storage_audio'), action: (): void => {
        this.setEmojiPanel(false);
        this.pickAndSendAudio();
      } } as MenuElement,
      { value: $r('app.string.loc_location'), action: (): void => {
        this.setEmojiPanel(false);
        this.chooseLocationKind();
      } } as MenuElement,
      { value: $r('app.string.tab_contacts'), action: (): void => {
        this.setEmojiPanel(false);
        this.openContactPicker();
      } } as MenuElement
    ];
    // 投票仅群/频道可发（Telegram 限制私聊不能发投票）。
    if (this.isGroup || this.isChannel) {
      items.push({ value: $r('app.string.poll_word'), action: (): void => {
        this.setEmojiPanel(false);
        this.openPollComposer();
      } } as MenuElement);
    }
    items.push({ value: $r('app.string.cp_dice'), action: (): void => {
      this.setEmojiPanel(false);
      this.showDiceMenu();
    } } as MenuElement);
    return items;
  }

  private openPollComposer(): void {
    this.showPollSheet = true;
  }

  // 圆形视频走附件菜单而不是麦克风按钮：麦克风已经是"点一下开始录音"的
  // 单击语义，再叠一个长按会和录音的起录竞争，误触率高；附件菜单里它和
  // 照片/文件是同一类"选一种内容发出去"的入口，心智更一致。
  private openVideoNoteRecorder(): void {
    if (this.store === null) {
      return;
    }
    this.cancelRecording();
    this.composerController.stopEditing();
    this.composerFocused = false;
    this.showVideoNoteRecorder = true;
  }

  private openContactPicker(): void {
    this.showContactSheet = true;
  }

  // 音乐：文件选择器按音频后缀过滤，复制沙箱后按音频消息发送。
  private pickAndSendAudio(): void {
    const docPicker = new picker.DocumentViewPicker(getContext(this) as common.UIAbilityContext);
    const opts = new picker.DocumentSelectOptions();
    opts.maxSelectNumber = 1;
    opts.fileSuffixFilters = ['.mp3', '.m4a', '.flac', '.ogg', '.wav', '.aac'];
    docPicker.select(opts).then((uris: string[]) => {
      if (uris.length === 0) {
        return;
      }
      const dest = this.copyUriToCache(uris[0]);
      if (dest === '') {
        promptAction.showToast({ message: $r('app.string.cp_audio_read_failed'), duration: 2000 });
        return;
      }
      if (this.store !== null) {
        this.atBottom = true;
        this.store.sendAudio(dest, this.draft.trim());
        this.draft = '';
      }
    }).catch((e: Object) => {
      console.error(`ChatPage.pickAndSendAudio select failed: ${JSON.stringify(e)}`);
    });
  }

  // 位置入口：先问是发静态点还是实时共享。
  private chooseLocationKind(): void {
    this.getUIContext().getPromptAction().showActionMenu({
      title: $r('app.string.cp_send_location'),
      buttons: [
        { text: $r('app.string.cp_current_location'), color: COLOR_TEXT_PRIMARY as string },
        { text: $r('app.string.cp_live_15m'), color: COLOR_TEXT_PRIMARY as string },
        { text: $r('app.string.cp_live_1h'), color: COLOR_TEXT_PRIMARY as string },
        { text: $r('app.string.cp_live_8h'), color: COLOR_TEXT_PRIMARY as string }
      ]
    }).then((res: promptAction.ActionMenuSuccessResponse): void => {
      const periods: number[] = [0, 15 * 60, 3600, 8 * 3600];
      const period: number = periods[res.index] ?? 0;
      if (period === 0) {
        this.sendCurrentLocation();
      } else {
        this.startLiveLocation(period);
      }
    }).catch((): void => {});
  }

  // 实时位置：发出后按固定间隔用新坐标 editMessageLiveLocation。TDLib 不会
  // 替我们采集位置，更新完全由客户端驱动，所以这里自己维护定时器；页面销毁
  // 或时长到期就停，避免后台一直定位耗电。
  private startLiveLocation(periodSec: number): void {
    this.withLocationPermission((): void => {
      this.currentLocation(10000).then((loc: geoLocationManager.Location): void => {
        const store = this.store;
        if (store === null) { return; }
        this.atBottom = true;
        store.sendLiveLocation(loc.latitude, loc.longitude, periodSec)
          .then((messageId: number): void => {
            if (messageId === 0) {
              promptAction.showToast({ message: $r('app.string.cp_live_location_failed'), duration: 1800 });
              return;
            }
            // 交给独立服务：退出会话、切后台都要继续共享。
            liveLocation.start(this.chatId, messageId, periodSec);
            promptAction.showToast({ message: $r('app.string.cp_live_location_started'), duration: 1600 });
          });
      }).catch((): void => {
        promptAction.showToast({ message: $r('app.string.cp_location_failed'), duration: 2000 });
      });
    });
  }

  private withLocationPermission(run: () => void): void {
    const context = getContext(this) as common.UIAbilityContext;
    const permissions: Permissions[] =
      ['ohos.permission.APPROXIMATELY_LOCATION', 'ohos.permission.LOCATION'];
    abilityAccessCtrl.createAtManager().requestPermissionsFromUser(context, permissions)
      .then((result): void => {
        if (result.authResults.length > 0 && result.authResults[0] === 0) {
          run();
          return;
        }
        promptAction.showToast({ message: $r('app.string.cp_needs_location'), duration: 1800 });
      })
      .catch((e: BusinessError): void => {
        console.error(`ChatPage location permission failed: ${e.message}`);
      });
  }

  private currentLocation(timeoutMs: number): Promise<geoLocationManager.Location> {
    const request: geoLocationManager.SingleLocationRequest = {
      locatingPriority: geoLocationManager.LocatingPriority.PRIORITY_LOCATING_SPEED,
      locatingTimeoutMs: timeoutMs
    };
    return geoLocationManager.getCurrentLocation(request);
  }

  // 位置：申请定位权限 → 取当前坐标 → 发送。无地图选点（Map Kit 需 AGC 凭据）。
  private sendCurrentLocation(): void {
    const context = getContext(this) as common.UIAbilityContext;
    const permissions: Permissions[] =
      ['ohos.permission.APPROXIMATELY_LOCATION', 'ohos.permission.LOCATION'];
    abilityAccessCtrl.createAtManager().requestPermissionsFromUser(context, permissions)
      .then((result): void => {
        const granted: boolean = result.authResults.length > 0 && result.authResults[0] === 0;
        if (!granted) {
          promptAction.showToast({ message: $r('app.string.cp_needs_location'), duration: 1800 });
          return;
        }
        promptAction.showToast({ message: $r('app.string.cp_getting_location'), duration: 1200 });
        const request: geoLocationManager.SingleLocationRequest = {
          locatingPriority: geoLocationManager.LocatingPriority.PRIORITY_LOCATING_SPEED,
          locatingTimeoutMs: 10000
        };
        geoLocationManager.getCurrentLocation(request)
          .then((location: geoLocationManager.Location): void => {
            if (this.store !== null) {
              this.atBottom = true;
              this.store.sendLocation(location.latitude, location.longitude);
            }
          })
          .catch((e: BusinessError): void => {
            console.error(`ChatPage.sendCurrentLocation failed: ${e.message}`);
            promptAction.showToast({ message: $r('app.string.cp_location_failed'), duration: 2000 });
          });
      })
      .catch((e: BusinessError): void => {
        console.error(`ChatPage location permission failed: ${e.message}`);
      });
  }

  // 骰子：系统动作菜单六选一（正好是 showActionMenu 的按钮上限）。
  // 🎰 老虎机由 DiceBubble 叠 5 层 TGS 渲染。
  private showDiceMenu(): void {
    const emojis: string[] = ['🎲', '🎯', '🏀', '⚽', '🎳', '🎰'];
    promptAction.showActionMenu({
      title: $r('app.string.cp_roll_a'),
      buttons: [
        { text: $r('app.string.cp_dice_die'), color: '#007AFF' }, { text: $r('app.string.cp_dice_darts'), color: '#007AFF' },
        { text: $r('app.string.cp_dice_basketball'), color: '#007AFF' }, { text: $r('app.string.cp_dice_football'), color: '#007AFF' },
        { text: $r('app.string.cp_dice_bowling'), color: '#007AFF' }, { text: $r('app.string.cp_dice_slots'), color: '#007AFF' }
      ]
    }).then((result): void => {
      const index: number = result.index;
      if (index >= 0 && index < emojis.length && this.store !== null) {
        this.atBottom = true;
        this.store.sendDice(emojis[index]);
      }
    }).catch((): void => {});
  }

  // Paperclip: pick a document, copy it into the app sandbox (TDLib can't read
  // picker URIs), then send it as a document message.
  private pickAndSendFile(): void {
    const docPicker = new picker.DocumentViewPicker(getContext(this) as common.UIAbilityContext);
    const opts = new picker.DocumentSelectOptions();
    opts.maxSelectNumber = 1;
    docPicker.select(opts).then((uris: string[]) => {
      if (uris.length === 0) {
        return;
      }
      const dest = this.copyUriToCache(uris[0]);
      if (dest === '') {
        promptAction.showToast({ message: $r('app.string.cp_file_read_failed'), duration: 2000 });
        return;
      }
      if (this.store !== null) {
        this.atBottom = true;
        this.store.sendDocument(dest, this.draft.trim());
        this.draft = '';
      }
    }).catch((e: Object) => {
      console.error(`ChatPage.pickAndSendFile select failed: ${JSON.stringify(e)}`);
    });
  }

  private doSend(): void {
    if (this.editingId !== 0) {
      this.commitEdit();
      return;
    }
    const draftSnapshot: string = this.draft;
    const text: string = draftSnapshot.trim();
    const store: MessageStore | null = this.store;
    if (text === '' || store === null || this.composerSending) {
      return;
    }
    const replyId: number = this.replyToId;
    this.composerSending = true;
    this.commandMenuOpen = false;
    this.atBottom = true;
    this.stayAtUnread = false;
    store.sendAsync(text, replyId).then((): void => {
      // The user may already have started the next message while TDLib was
      // accepting this one. Never erase newer input or a newly selected reply.
      if (this.draft === draftSnapshot) {
        this.draft = '';
      }
      if (this.replyToId === replyId) {
        this.clearReply();
      }
      this.mentionItems = [];
      this.commandItems = [];
      this.commandMenuOpen = false;
      this.composerSending = false;
    }).catch((e: TdError): void => {
      this.composerSending = false;
      console.error(`ChatPage.doSend failed: ${e.message}`);
      promptAction.showToast({ message: $r('app.string.cp_send_failed_kept'), duration: 1800 });
    });
  }

  // Bot reply-keyboard button. keyboardButtonTypeText simply sends its own label
  // as an ordinary message. The other types (location / phone number / poll /
  // web app) need capabilities we don't have, so they're rejected rather than
  // silently doing nothing — a button that lies is worse than one that says no.
  private onReplyKeyboardTap(btn: KeyboardBtn, key: string): void {
    // Older TDLib payloads can omit keyboardButtonTypeText entirely; an empty
    // type is still the ordinary text-button behavior.
    if (btn.type !== '' && btn.type !== KB_TEXT) {
      promptAction.showToast({ message: $r('app.string.cp_button_unsupported'), duration: 1500 });
      return;
    }
    if (this.store === null || this.replyKeyboardSendingKey !== '') {
      return;
    }
    const store: MessageStore = this.store;
    const replyId: number = this.replyToId;
    const keyboardId: number = this.replyKeyboard !== null ? this.replyKeyboard.messageId : 0;
    const oneTime: boolean = this.replyKeyboard !== null && this.replyKeyboard.oneTime;
    this.replyKeyboardSendingKey = key;
    this.atBottom = true;
    this.stayAtUnread = false;
    store.sendAsync(btn.text, replyId).then((): void => {
      this.replyKeyboardSendingKey = '';
      if (this.replyToId === replyId) {
        this.clearReply();
      }
      // one_time keyboards fold only after TDLib accepts the message. A failed
      // tap leaves the controls visible so the user can retry.
      if (oneTime && this.replyKeyboard !== null &&
        this.replyKeyboard.messageId === keyboardId) {
        this.replyKbCollapsed = true;
      }
    }).catch((e: TdError): void => {
      this.replyKeyboardSendingKey = '';
      console.error(`ChatPage.replyKeyboard send failed: ${e.message}`);
      promptAction.showToast({ message: $r('app.string.send_failed_retry_short'), duration: 1600 });
    });
  }

  private findMsg(messageId: number): MessageEntry | null {
    for (const m of this.messages) {
      if (m.id === messageId) {
        return m;
      }
    }
    return null;
  }

  private clearReply(): void {
    this.replyToId = 0;
    this.replyToName = '';
    this.replyToText = '';
  }

  private replySnippet(m: MessageEntry): string {
    if (m.text.trim() !== '') {
      return m.text;
    }
    if (m.placeholderLabel.trim() !== '') {
      return m.placeholderLabel;
    }
    if (m.contentType === 'sticker') {
      return str('sticker_tab');
    }
    if (m.contentType === 'photo') {
      return str('storage_photo');
    }
    if (m.contentType === 'video') {
      return str('storage_video');
    }
    if (m.contentType === 'paidMedia') {
      return m.paidMediaLocked ? str('paid_media') : str('cp_unlocked_media');
    }
    if (m.contentType === 'voice') {
      return str('ns_voice_message');
    }
    return str('cp_media_message');
  }

  // Long-press menu: reply. Populates the reply preview above the input bar;
  // doSend() then attaches reply_to.
  private startReply(messageId: number): void {
    const m = this.findMsg(messageId);
    if (m === null) {
      return;
    }
    ContextMenu.close();
    this.closeReactionSheet();
    this.replyToId = messageId;
    this.replyToName = m.senderName !== '' ? m.senderName : this.title;
    this.replyToText = this.replySnippet(m);
    this.setEmojiPanel(false);
    this.replyKbCollapsed = true;
    setTimeout((): void => {
      focusControl.requestFocus('chat_composer');
    }, 0);
  }

  // --- multi-select ---
  private enterSelect(messageId: number): void {
    ContextMenu.close();
    this.closeReactionSheet();
    this.setEmojiPanel(false);
    this.selecting = true;
    this.selectedIds = [messageId];
  }

  private exitSelect(): void {
    this.selecting = false;
    this.selectedIds = [];
  }

  private rowSelected(g: AlbumGroup): boolean {
    for (const id of g.memberIds) {
      if (this.selectedIds.indexOf(id) >= 0) {
        return true;
      }
    }
    return false;
  }

  // Toggle a whole display row (an album row selects all its members).
  private toggleSelectRow(g: AlbumGroup): void {
    if (g.head.contentType === 'system' || g.head.contentType === 'hidden') {
      return;
    }
    if (this.rowSelected(g)) {
      this.selectedIds = this.selectedIds.filter((id: number) => g.memberIds.indexOf(id) < 0);
    } else {
      this.selectedIds = [...this.selectedIds, ...g.memberIds];
    }
    if (this.selectedIds.length === 0) {
      this.exitSelect();
    }
  }

  private reconcileMessageActionTargets(list: MessageEntry[]): void {
    if (this.selecting) {
      this.selectedIds = this.selectedIds.filter((id: number): boolean =>
        list.findIndex((m: MessageEntry): boolean => m.id === id) >= 0
      );
      if (this.selectedIds.length === 0) {
        this.exitSelect();
      }
    }
    if (this.showReactionSheet && this.reactionTargetId !== 0 &&
      list.findIndex((m: MessageEntry): boolean => m.id === this.reactionTargetId) < 0) {
      this.closeReactionSheet();
    }
  }

  private copySelected(): void {
    const sorted = [...this.selectedIds].sort((a: number, b: number) => a - b);
    const parts: string[] = [];
    for (const id of sorted) {
      const m = this.findMsg(id);
      if (m !== null && m.text !== '') {
        parts.push(m.text);
      }
    }
    if (parts.length === 0) {
      promptAction.showToast({ message: $r('app.string.cp_nothing_to_copy'), duration: 1500 });
      return;
    }
    const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, parts.join('\n\n'));
    pasteboard.getSystemPasteboard().setData(data).then(() => {
      promptAction.showToast({ message: plural('cp_copied_n', parts.length, parts.length), duration: 1200 });
      this.exitSelect();
    }).catch((e: Object) => { console.error(`ChatPage.copySelected failed: ${JSON.stringify(e)}`); });
  }

  // "同时为对方删除"是一个开关，不是第三个按钮：做成三按钮时用户要在两个
  // 红色危险项之间辨认，容易点错。所以用带复选框的自定义弹窗。
  private deleteSelected(): void {
    const ids: number[] = [...this.selectedIds];
    if (ids.length === 0) {
      return;
    }
    this.deleteDialog = new CustomDialogController({
      builder: DeleteMessagesDialog({
        peerName: this.isGroup || this.isChannel ? '' : this.headerText().titleText,
        onConfirm: (revoke: boolean): void => { this.doDeleteMessages(ids, revoke); }
      }),
      autoCancel: true,
      customStyle: true,
      alignment: DialogAlignment.Center
    });
    this.deleteDialog.open();
  }

  // 长按菜单里的单条删除：复用 deleteSelected() 的弹窗逻辑，只是目标 id 只有一个。
  // 不处于多选模式时 doDeleteMessages 内部的 exitSelect() 只是把已经为 false/[]
  // 的 selecting/selectedIds 再赋一次同样的值，是无害的空操作。
  private deleteMessage(messageId: number): void {
    const ids: number[] = [messageId];
    this.deleteDialog = new CustomDialogController({
      builder: DeleteMessagesDialog({
        peerName: this.isGroup || this.isChannel ? '' : this.headerText().titleText,
        onConfirm: (revoke: boolean): void => { this.doDeleteMessages(ids, revoke); }
      }),
      autoCancel: true,
      customStyle: true,
      alignment: DialogAlignment.Center
    });
    this.deleteDialog.open();
  }

  private doDeleteMessages(ids: number[], revoke: boolean): void {
    const req: TdRequest = { '@type': 'deleteMessages' };
    req['chat_id'] = this.chatId;
    req['message_ids'] = ids;
    req['revoke'] = revoke;
    getTdClient().send(req).then(() => {
      this.exitSelect();
    }).catch((e: TdError) => {
      console.error(`ChatPage.deleteMessages failed: ${e.message}`);
      promptAction.showToast({ message: str('cp_delete_failed_msg', e.message), duration: 2000 });
    });
  }

  private copyMessageText(messageId: number): void {
    const m = this.findMsg(messageId);
    if (m === null || m.text === '') {
      promptAction.showToast({ message: $r('app.string.cp_nothing_to_copy'), duration: 1500 });
      return;
    }
    this.copyPlainText(m.text, str('copied'));
  }

  private copyPlainText(text: string, successMessage: string): void {
    if (text === '') {
      return;
    }
    const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
    pasteboard.getSystemPasteboard().setData(data).then(() => {
      promptAction.showToast({ message: successMessage, duration: 1200 });
    }).catch((e: Object) => { console.error(`ChatPage.copyPlainText failed: ${JSON.stringify(e)}`); });
  }

  private copyMessageLink(messageId: number): void {
    if (this.store === null) {
      return;
    }
    this.store.messageLink(messageId, (url: string) => {
      if (url === '') {
        promptAction.showToast({ message: $r('app.string.cp_no_link'), duration: 1800 });
        return;
      }
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, url);
      pasteboard.getSystemPasteboard().setData(data).then(() => {
        promptAction.showToast({ message: $r('app.string.link_copied'), duration: 1200 });
      }).catch((e: Object) => { console.error(`ChatPage.copyMessageLink failed: ${JSON.stringify(e)}`); });
    });
  }

  // reactionKey：标准 emoji 原样，自定义 emoji 为 'ce:<custom_emoji_id>'。
  private toggleReaction(messageId: number, reactionKey: string, isChosen: boolean): void {
    const store: MessageStore | null = this.store;
    const key: string = `${messageId}_${reactionKey}`;
    if (store === null || this.reactionPendingKey !== '') {
      return;
    }
    ContextMenu.close();
    this.reactionPendingKey = key;
    store.setReaction(messageId, reactionKey, isChosen).then((): void => {
      if (this.reactionPendingKey === key) {
        this.reactionPendingKey = '';
      }
    }).catch((e: TdError): void => {
      if (this.reactionPendingKey === key) {
        this.reactionPendingKey = '';
      }
      console.error(`ChatPage.toggleReaction failed: ${e.message}`);
      promptAction.showToast({ message: $r('app.string.cp_reaction_failed'), duration: 1600 });
    });
  }

  // 语音转文字。Premium 功能，非会员会被服务端拒绝，这里把原始错误呈现出来
  // 而不是笼统说"失败"——用户能据此判断是要开会员还是网络问题。
  // 会话级自动翻译开关。本地先翻转让菜单立刻反映，失败再回滚——这个操作
  // 很轻，等一次往返反而显得迟钝。
  // 跳转到某一天。用 getChatMessageByDate 而不是 getChatMessageCalendar——
  // 后者明确不支持 searchMessagesFilterEmpty，只能按媒体类型分日统计，做不了
  // "跳到任意一天"。前者直接返回不晚于给定时刻的最后一条消息，正是所需。
  private pickJumpDate(): void {
    const now = new Date();
    // 会话第一条消息之前的日期没有意义，但客户端不知道那是哪天，
    // 下界给 2013（Telegram 上线年份）足够宽松。
    this.getUIContext().showDatePickerDialog({
      start: new Date('2013-01-01'),
      end: now,
      selected: now,
      onDateAccept: (value: Date): void => { this.jumpToDate(value); }
    });
  }

  private jumpToDate(day: Date): void {
    const store = this.store;
    if (store === null) { return; }
    // 取当天 23:59:59：getChatMessageByDate 返回"不晚于该时刻"的最后一条，
    // 用当天结束时刻才能落在这一天之内，用 00:00 会落到前一天。
    const end = new Date(day.getFullYear(), day.getMonth(), day.getDate(), 23, 59, 59);
    const req: TdRequest = { '@type': 'getChatMessageByDate' };
    req['chat_id'] = this.chatId;
    req['date'] = Math.floor(end.getTime() / 1000);
    getTdClient().send(req, 15000).then((message: TdObject): void => {
      const id: number = (message['id'] as number | undefined) ?? 0;
      if (id === 0) {
        promptAction.showToast({ message: $r('app.string.cp_no_messages_that_day'), duration: 1600 });
        return;
      }
      this.jumpToMessageId(id);
    }).catch((e: TdError): void => {
      // 404 是合法结果：该日期之前没有任何消息。
      const code: number = e.code !== undefined ? e.code : 0;
      promptAction.showToast({
        message: code === 404 ? $r('app.string.cp_no_messages_before') : str('cp_jump_failed_msg', e.message),
        duration: 1600
      });
    });
  }

  // 跳到指定消息：已在当前页就直接滚动并高亮，否则围绕它重新拉一页。
  private jumpToMessageId(targetId: number): void {
    const gidx: number = groupIndexOf(this.groups, targetId);
    if (gidx >= 0) {
      this.scroller.scrollToIndex(gidx, false, ScrollAlign.START);
      this.flashAtIndex(gidx);
      return;
    }
    this.pendingJumpId = targetId;
    this.store?.loadAround(targetId, (found: boolean): void => {
      if (!found && this.pendingJumpId === targetId) {
        this.pendingJumpId = 0;
        promptAction.showToast({ message: $r('app.string.cp_cannot_jump'), duration: 1500 });
      }
    });
  }

  // 可见范围（外扩几行缓冲）内还没有当前目标语言译文的消息，交给
  // TranslationService 排队。结果回来经 store.applyTranslation 写入条目，
  // 内容签名变化触发 CHANGE，气泡里长出译文块。
  // 这个会话此刻到底翻不翻。总开关是"默认值"，会话级那一项是对默认值的反转：
  // 开着就是排除名单，关着就是白名单。
  private translationActive(): boolean {
    return this.translateChatsEnabled ? !this.translateChatOptOut : this.isTranslatable;
  }

  // 总开关在设置页被改动后，当前页要立刻跟上：开了就把可见范围补翻，
  // 关了就把已经渲染出来的译文收走（服务的缓存留着，再开秒回）。
  private onTranslateSettingChanged(): void {
    if (this.translationActive()) {
      this.driveVisibleWork();
    } else {
      this.store?.clearTranslations();
    }
  }

  private driveTranslations(startIdx: number, endIdx: number): void {
    const store = this.store;
    if (!this.translationActive() || store === null || this.groups.length === 0) {
      return;
    }
    const lang: string = resolveTranslateTarget();
    const from: number = Math.max(0, startIdx - 3);
    const to: number = Math.min(this.groups.length - 1, endIdx + 3);
    if (from > to) {
      return;
    }
    const fromId: number = this.groups[from].head.id;
    const toGroup: AlbumGroup = this.groups[to];
    const toId: number = toGroup.memberIds[toGroup.memberIds.length - 1];
    const service = getTranslationService(getTdClient());
    for (const m of store.translationCandidates(fromId, toId, lang)) {
      // 已经是目标语言（按文字系统判定）就不发请求。拉丁字母目标语言判不了，
      // 仍交给服务器（结果按内容版本缓存，只花一次往返）。
      if (looksLikeTargetLanguage(m.text, lang)) {
        continue;
      }
      const hit: string | null = service.cached(this.chatId, m.id, m.editDate, lang);
      if (hit !== null) {
        // 译文与原文相同（同语言消息）就什么都不写，气泡不长翻译块。
        if (hit !== '' && hit !== m.text) {
          store.applyTranslation(m.id, lang, hit);
        }
        continue;
      }
      const requestedId: number = m.id;
      const originalText: string = m.text;
      service.request(this.chatId, m.id, m.editDate, lang, (text: string | null): void => {
        if (text !== null && text !== '' && text !== originalText && this.store === store) {
          store.applyTranslation(requestedId, lang, text);
        }
      });
    }
  }

  private toggleTranslationHidden(messageId: number, hidden: boolean): void {
    this.store?.setTranslationHidden(messageId, hidden);
  }

  // 翻译 + 媒体窗口的统一驱动。滑动时由 onScrollIndex 带着真实区间调用，
  // 数据变化时由这里按"当前视口"调用一次 —— 否则进页面不滑动就什么都不发生。
  private driveVisibleWork(): void {
    if (this.groups.length === 0) {
      return;
    }
    // 首帧之前还没有滚动事件，curStartIdx/curEndIdx 是 -1：用首屏兜底
    // （聊天默认停在底部，所以取末尾一屏），滑动事件到了会立刻纠正。
    const hasViewport: boolean = this.curStartIdx >= 0 && this.curEndIdx >= this.curStartIdx;
    const start: number = hasViewport ? this.curStartIdx
      : Math.max(0, this.groups.length - LIST_CACHED_COUNT - 1);
    const end: number = hasViewport ? this.curEndIdx : this.groups.length - 1;
    this.driveTranslations(start, end);
    this.syncMediaWindow(start, end);
    // 同一个道理：数据一变（新消息到达、翻页、被查看器等场景清空候选表后
    // 恢复）就补一次播放位判定，不指望用户正好在这一刻滚动。
    this.armPlaySlotSettle();
  }

  // 把可见行区间换算成消息 id 区间交给 store。外扩几行做缓冲，滑动时不会
  // 因为一行之差反复取消又重下。
  private syncMediaWindow(startIdx: number, endIdx: number): void {
    const store = this.store;
    if (store === null || this.groups.length === 0) {
      return;
    }
    const from: number = Math.max(0, startIdx - 3);
    const to: number = Math.min(this.groups.length - 1, endIdx + 3);
    if (from > to) {
      return;
    }
    const toGroup: AlbumGroup = this.groups[to];
    store.setMediaWindow(
      this.groups[from].head.id,
      toGroup.memberIds[toGroup.memberIds.length - 1]
    );
  }

  // 菜单里那一项永远是"把当前状态反过来"，但落到哪个开关上取决于总开关：
  // 总开关开着时写本地排除名单（纯本地，不会失败）；总开关关着时才走
  // 服务端的 toggleChatIsTranslatable，跟官方客户端保持同一份状态。
  private toggleTranslatable(): void {
    const next: boolean = !this.translationActive();
    if (this.translateChatsEnabled) {
      this.translateChatOptOut = !next;
      setTranslateOptedOut(this.chatId, !next);
      this.afterTranslationToggled(next);
      return;
    }
    const previous: boolean = this.isTranslatable;
    this.isTranslatable = next;
    this.afterTranslationToggled(next);
    const req: TdRequest = { '@type': 'toggleChatIsTranslatable' };
    req['chat_id'] = this.chatId;
    req['is_translatable'] = next;
    getTdClient().send(req).catch((e: TdError): void => {
      this.isTranslatable = previous;
      console.error(`ChatPage.toggleTranslatable failed: ${e.message}`);
      promptAction.showToast({ message: str('cp_setting_failed_msg', e.message), duration: 1800 });
    });
  }

  private afterTranslationToggled(active: boolean): void {
    if (active) {
      this.driveVisibleWork();
    } else {
      // 关掉时立刻把已渲染的译文收走；服务的缓存保留，再开秒回。
      this.store?.clearTranslations();
    }
    promptAction.showToast({
      message: active
        ? $r('app.string.cp_auto_translate_enabled') : $r('app.string.cp_auto_translate_disabled'),
      duration: 1500
    });
  }

  private recognizeSpeech(messageId: number): void {
    this.store?.recognizeSpeech(messageId).catch((e: TdError): void => {
      const message: string = e.message !== undefined ? e.message : '';
      promptAction.showToast({
        message: message.indexOf('PREMIUM') >= 0 || message.indexOf('premium') >= 0
          ? $r('app.string.cp_transcribe_premium') : str('cp_transcribe_failed_msg', message),
        duration: 2200
      });
    });
  }

  private openReactionSheet(messageId: number): void {
    ContextMenu.close();
    if (this.findMsg(messageId) === null) {
      return;
    }
    this.reactionTargetId = messageId;
    this.showReactionSheet = true;
  }

  private showMenuConfirm(
    options: promptAction.ShowDialogOptions, what: string,
    onConfirm: (index: number) => void
  ): void {
    const prompt = this.getUIContext().getPromptAction();
    setTimeout((): void => {
      prompt.showDialog(options).then((res: promptAction.ShowDialogSuccessResponse): void => {
        onConfirm(res.index);
      }).catch((e: Object): void => {
        console.info(`ChatPage.${what} dialog dismissed: ${JSON.stringify(e)}`);
      });
    }, MENU_DISMISS_MS);
  }

  private stopPoll(messageId: number): void {
    this.showMenuConfirm({
      title: $r('app.string.mb_stop_poll'),
      message: $r('app.string.cp_stop_poll_body'),
      buttons: [
        { text: $r('app.string.cancel'), color: '#8E8E93' },
        { text: $r('app.string.cp_stop'), color: '#E5484D' }
      ]
    }, 'stopPoll', (index: number): void => {
      if (index !== 1) { return; }
      this.store?.stopPollAsync(messageId).then((): void => {
        promptAction.showToast({ message: $r('app.string.cp_poll_stopped'), duration: 1500 });
      }).catch((e: TdError): void => {
        console.error(`ChatPage.stopPoll failed: ${e.message}`);
        promptAction.showToast({ message: $r('app.string.cp_stop_poll_failed'), duration: 1600 });
      });
    });
  }

  // Public polls only: list who picked each option.
  private showPollVoters(messageId: number): void {
    const msg = this.findMsg(messageId);
    const store = this.store;
    if (msg === null || store === null) { return; }
    const lines: string[] = [];
    const tasks: Promise<void>[] = [];
    msg.pollOptions.forEach((option: PollOptionInfo, index: number): void => {
      tasks.push(store.pollVotersAsync(messageId, index).then((result: TdObject): void => {
        const senders = (result['senders'] as TdObject[] | undefined) ?? [];
        const names: string[] = [];
        for (const sender of senders) {
          if (sender['@type'] === 'messageSenderUser') {
            const uid = (sender['user_id'] as number | undefined) ?? 0;
            const name = getUserStore().displayName(uid);
            if (name === '') { getUserStore().ensure(uid); }
            names.push(name !== '' ? name : str('cp_user_id', uid));
          }
        }
        if (names.length > 0) {
          lines.push(`${option.text}：${names.join('、')}`);
        }
      }).catch((): void => {}));
    });
    Promise.all(tasks).then((): void => {
      promptAction.showDialog({
        title: $r('app.string.cp_voters'),
        message: lines.length > 0 ? lines.join('\n\n') : $r('app.string.cp_no_public_votes'),
        buttons: [{ text: $r('app.string.close'), color: '#3390EC' }]
      }).catch((): void => {});
    }).catch((): void => {});
  }

  private setDefaultReaction(emoji: string): void {
    const rt: TdObject = { '@type': 'reactionTypeEmoji' };
    rt['emoji'] = emoji;
    const req: TdRequest = { '@type': 'setDefaultReactionType' };
    req['reaction_type'] = rt;
    getTdClient().send(req).then((): void => {
      promptAction.showToast({ message: str('cp_default_reaction_set', emoji), duration: 1600 });
    }).catch((e: TdError): void => {
      console.error(`ChatPage.setDefaultReaction failed: ${e.message}`);
      promptAction.showToast({ message: $r('app.string.cp_default_reaction_failed'), duration: 1600 });
    });
  }

  // Chat-level auto-delete timer (阅后即焚).
  private chooseAutoDelete(): void {
    const labels: string[] = [str('close'), str('ps_1_day'), str('ps_1_week'), str('ps_1_month')];
    const seconds: number[] = [0, 86400, 604800, 2678400];
    promptAction.showActionMenu({
      title: $r('app.string.cp_auto_delete_title'),
      buttons: labels.map((text: string): promptAction.Button =>
        ({ text, color: '#3390EC' } as promptAction.Button)) as
        [promptAction.Button, promptAction.Button?, promptAction.Button?,
          promptAction.Button?, promptAction.Button?, promptAction.Button?]
    }).then((chosen): void => {
      const value = seconds[chosen.index];
      if (value === undefined) { return; }
      this.store?.setAutoDeleteAsync(value).then((): void => {
        promptAction.showToast({
          message: value === 0 ? $r('app.string.cp_auto_delete_off') : str('cp_auto_delete_after', labels[chosen.index]),
          duration: 1800
        });
      }).catch((e: TdError): void => {
        console.error(`ChatPage.autoDelete failed: ${e.message}`);
        promptAction.showToast({ message: $r('app.string.cp_setting_failed_permission'), duration: 1700 });
      });
    }).catch((): void => {});
  }

  // Long-press the send button: schedule or send silently.
  private showSendOptions(): void {
    if (this.draft.trim() === '' || this.editingId !== 0) { return; }
    const labels: string[] = [str('cp_send_silently'), str('cp_send_in_1h'), str('cp_send_tomorrow_9')];
    promptAction.showActionMenu({
      title: $r('app.string.cp_send_options'),
      buttons: labels.map((text: string): promptAction.Button =>
        ({ text, color: '#3390EC' } as promptAction.Button)) as
        [promptAction.Button, promptAction.Button?, promptAction.Button?,
          promptAction.Button?, promptAction.Button?, promptAction.Button?]
    }).then((chosen): void => {
      const nowSeconds = Math.floor(Date.now() / 1000);
      let sendDate = 0;
      let silent = false;
      if (chosen.index === 0) {
        silent = true;
      } else if (chosen.index === 1) {
        sendDate = nowSeconds + 3600;
      } else if (chosen.index === 2) {
        const tomorrow = new Date();
        tomorrow.setDate(tomorrow.getDate() + 1);
        tomorrow.setHours(9, 0, 0, 0);
        sendDate = Math.floor(tomorrow.getTime() / 1000);
      } else {
        return;
      }
      const text = this.draft.trim();
      const replyId = this.replyToId;
      this.store?.sendScheduledAsync(text, replyId, sendDate, silent).then((): void => {
        this.draft = '';
        this.clearReply();
        promptAction.showToast({
          message: sendDate > 0 ? $r('app.string.cp_scheduled') : $r('app.string.cp_sent_silently'), duration: 1600
        });
      }).catch((e: TdError): void => {
        console.error(`ChatPage.sendScheduled failed: ${e.message}`);
        promptAction.showToast({ message: $r('app.string.send_failed'), duration: 1600 });
      });
    }).catch((): void => {});
  }

  private togglePinMessage(messageId: number, unpin: boolean): void {
    const store = this.store;
    if (store === null) { return; }
    const task: Promise<void> = unpin
      ? store.unpinAsync(messageId) : store.pinAsync(messageId);
    task.then((): void => {
      promptAction.showToast({ message: unpin ? $r('app.string.cp_unpinned') : $r('app.string.cp_pinned'), duration: 1400 });
    }).catch((e: TdError): void => {
      console.error(`ChatPage.togglePin failed: ${e.message}`);
      promptAction.showToast({
        message: e.message.indexOf('not enough rights') >= 0 || e.message.indexOf('ADMIN') >= 0
          ? $r('app.string.cp_no_pin_permission') : (unpin ? $r('app.string.cp_unpin_failed') : $r('app.string.cp_pin_failed')),
        duration: 1700
      });
    });
  }

  // Live "typing…" from peers (updateChatAction). Entries expire after 6s —
  // TDLib sends chatActionCancel, but a dropped cancel must not stick forever.
  private onChatAction(update: TdObject): void {
    if (((update['chat_id'] as number | undefined) ?? 0) !== this.chatId) { return; }
    const sender = update['sender_id'] as TdObject | undefined;
    if (sender === undefined || sender['@type'] !== 'messageSenderUser') { return; }
    const uid = (sender['user_id'] as number | undefined) ?? 0;
    if (uid <= 0) { return; }
    const action = update['action'] as TdObject | undefined;
    const actionType = action !== undefined ? ((action['@type'] as string | undefined) ?? '') : '';
    if (actionType === 'chatActionCancel') {
      this.typingSenders.delete(uid);
    } else {
      this.typingSenders.set(uid, Date.now() + 6000);
      getUserStore().ensure(uid);
    }
    this.rebuildTypingLabel();
    if (this.typingTimer === -1 && this.typingSenders.size > 0) {
      this.typingTimer = setInterval((): void => {
        const now = Date.now();
        let changed = false;
        for (const key of Array.from(this.typingSenders.keys())) {
          if ((this.typingSenders.get(key) ?? 0) < now) {
            this.typingSenders.delete(key);
            changed = true;
          }
        }
        if (changed) { this.rebuildTypingLabel(); }
        if (this.typingSenders.size === 0 && this.typingTimer !== -1) {
          clearInterval(this.typingTimer);
          this.typingTimer = -1;
        }
      }, 1500);
    }
  }

  private rebuildTypingLabel(): void {
    const ids = Array.from(this.typingSenders.keys());
    if (ids.length === 0) {
      this.typingLabel = '';
      return;
    }
    if (this.headerKind === 'private' || this.headerKind === 'secret') {
      this.typingLabel = str('cp_typing');
      return;
    }
    if (ids.length > 1) {
      this.typingLabel = plural('cp_n_typing', ids.length, ids.length);
      return;
    }
    const name = getUserStore().displayName(ids[0]);
    this.typingLabel = str('cp_someone_typing', name !== '' ? name.split(' ')[0] : str('cp_someone'));
  }

  // Pick up the draft synced from other devices (chat.draft_message). Only
  // fills an empty composer — never overwrites what the user is typing.
  private restoreServerDraft(): void {
    const req: TdRequest = { '@type': 'getChat' };
    req['chat_id'] = this.chatId;
    getTdClient().send(req).then((chat: TdObject): void => {
      if (this.draft !== '') { return; }
      const draft = chat['draft_message'] as TdObject | undefined;
      const content = draft !== undefined
        ? (draft['input_message_text'] as TdObject | undefined) : undefined;
      const ft = content !== undefined ? (content['text'] as TdObject | undefined) : undefined;
      const text = ft !== undefined ? ((ft['text'] as string | undefined) ?? '') : '';
      if (text !== '') { this.draft = text; }
    }).catch((): void => {});
  }

  // Translate a message's text/caption into the system language and show the
  // result in place (dialog). TDLib needs an explicit ISO 639-1 target code.
  // 单条翻译改半模态面板（可上拉全屏）：原文/译文对照、复制、快速换目标语言。
  // 此前是 promptAction.showDialog 小弹窗，长文没法读。
  @State translateSheetOpen: boolean = false;
  @State translateSheetOriginal: string = '';
  @State translateSheetText: string = '';
  @State translateSheetState: string = 'loading'; // loading | done | failed | empty
  @State translateSheetLang: string = '';
  private translateSheetMsgId: number = 0;
  private translateSheetEditDate: number = 0;
  private translateSheetSeq: number = 0;

  private translateMessage(messageId: number): void {
    const entry: MessageEntry | undefined =
      this.messages.find((m: MessageEntry): boolean => m.id === messageId);
    if (entry === undefined || entry.text.trim() === '') {
      promptAction.showToast({ message: $r('app.string.cp_nothing_to_translate'), duration: 1600 });
      return;
    }
    this.translateSheetMsgId = messageId;
    this.translateSheetEditDate = entry.editDate;
    this.translateSheetOriginal = entry.text;
    this.translateSheetOpen = true;
    this.runSheetTranslation(resolveTranslateTarget());
  }

  private runSheetTranslation(lang: string): void {
    const seq: number = ++this.translateSheetSeq;
    this.translateSheetLang = lang;
    this.translateSheetText = '';
    this.translateSheetState = 'loading';
    const service = getTranslationService(getTdClient());
    const msgId: number = this.translateSheetMsgId;
    const editDate: number = this.translateSheetEditDate;
    const original: string = this.translateSheetOriginal;
    const settle = (text: string | null): void => {
      if (seq !== this.translateSheetSeq) {
        return;
      }
      if (text === null) {
        this.translateSheetState = 'failed';
      } else if (text === '' || text === original) {
        this.translateSheetState = 'empty';
      } else {
        this.translateSheetText = text;
        this.translateSheetState = 'done';
      }
    };
    service.request(this.chatId, msgId, editDate, lang, (text: string | null): void => {
      if (text !== null) {
        settle(text);
        return;
      }
      // null 也可能是"同一条消息正被整聊天翻译在途"——稍后从缓存补一次再定失败。
      setTimeout((): void => {
        settle(service.cached(this.chatId, msgId, editDate, lang));
      }, 2500);
    });
  }

  private pickTranslateSheetLang(): void {
    const codes: string[] = TRANSLATE_LANG_CODES;
    const names: string[] = codes.map((c: string): string => languageDisplayName(c));
    TextPickerDialog.show({
      range: names,
      selected: Math.max(0, codes.indexOf(this.translateSheetLang)),
      onAccept: (value: TextPickerResult): void => {
        const idx: number = value.index as number;
        if (idx >= 0 && idx < codes.length) {
          this.runSheetTranslation(codes[idx]);
        }
      }
    });
  }

  private copySheetTranslation(): void {
    const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, this.translateSheetText);
    pasteboard.getSystemPasteboard().setData(data).then((): void => {
      promptAction.showToast({ message: $r('app.string.copied'), duration: 1300 });
    }).catch((): void => {});
  }

  @Builder
  translateSheet() {
    Column() {
      Row() {
        Text($r('app.string.mb_translate'))
          .fontSize(17).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT_PRIMARY)
          .layoutWeight(1);
        // 目标语言胶囊：点它换语言并重译。
        Row({ space: 4 }) {
          Text(languageDisplayName(this.translateSheetLang))
            .fontSize(13).fontColor(COLOR_PRIMARY).fontWeight(FontWeight.Medium);
          SymbolGlyph($r('sys.symbol.chevron_down')).fontSize(12).fontColor([COLOR_PRIMARY]);
        }
        .padding({ left: 10, right: 10, top: 5, bottom: 5 })
        .borderRadius(14)
        .backgroundColor('#143390EC')
        .onClick((): void => { this.pickTranslateSheetLang(); });
      }
      .width('100%')
      .padding({ left: 18, right: 18, top: 6, bottom: 10 });
      Scroll() {
        Column({ space: 6 }) {
          Text($r('app.string.cp_translate_original'))
            .fontSize(12).fontColor(COLOR_TEXT_SECONDARY)
            .alignSelf(ItemAlign.Start);
          Text(this.translateSheetOriginal)
            .fontSize(16).lineHeight(22).fontColor(COLOR_TEXT_PRIMARY)
            .copyOption(CopyOptions.LocalDevice)
            .alignSelf(ItemAlign.Start);
          Divider().color($r('app.color.divider')).strokeWidth(0.7)
            .margin({ top: 8, bottom: 8 });
          Text(str('mb_translated_into', languageDisplayName(this.translateSheetLang)))
            .fontSize(12).fontColor(COLOR_TEXT_SECONDARY)
            .alignSelf(ItemAlign.Start);
          if (this.translateSheetState === 'loading') {
            LoadingProgress().width(26).height(26).color(COLOR_PRIMARY)
              .alignSelf(ItemAlign.Center).margin({ top: 12 });
          } else if (this.translateSheetState === 'failed') {
            Text($r('app.string.cp_translate_failed'))
              .fontSize(14).fontColor(COLOR_TEXT_SECONDARY).alignSelf(ItemAlign.Start);
            Button($r('app.string.cp_translate_retry'))
              .fontSize(14).height(34)
              .backgroundColor('#143390EC').fontColor(COLOR_PRIMARY)
              .alignSelf(ItemAlign.Start)
              .onClick((): void => { this.runSheetTranslation(this.translateSheetLang); });
          } else if (this.translateSheetState === 'empty') {
            Text($r('app.string.cp_nothing_to_translate'))
              .fontSize(14).fontColor(COLOR_TEXT_SECONDARY).alignSelf(ItemAlign.Start);
          } else {
            Text(this.translateSheetText)
              .fontSize(16).lineHeight(22).fontColor(COLOR_TEXT_PRIMARY)
              .copyOption(CopyOptions.LocalDevice)
              .alignSelf(ItemAlign.Start);
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding({ left: 18, right: 18, bottom: 16 });
      }
      .layoutWeight(1)
      .align(Alignment.TopStart)
      .scrollBar(BarState.Off);
      if (this.translateSheetState === 'done') {
        Button($r('app.string.copy'))
          .width('100%').height(44).fontSize(16)
          .backgroundColor(COLOR_PRIMARY).fontColor(Color.White)
          .margin({ left: 18, right: 18, bottom: this.bottomSafe + 10 })
          .onClick((): void => { this.copySheetTranslation(); });
      }
    }
    .width('100%').height('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ top: 8 });
  }

  // Long-press on a reaction chip: who reacted with it.
  private showReactors(messageId: number, reactionKey: string): void {
    const req: TdRequest = { '@type': 'getMessageAddedReactions' };
    req['chat_id'] = this.chatId;
    req['message_id'] = messageId;
    req['reaction_type'] = reactionTypeOf(reactionKey);
    req['offset'] = '';
    req['limit'] = 50;
    getTdClient().send(req, 10000).then((result: TdObject): void => {
      const rows = (result['reactions'] as TdObject[] | undefined) ?? [];
      const total = (result['total_count'] as number | undefined) ?? rows.length;
      const names: string[] = [];
      for (const row of rows) {
        const sender = row['sender_id'] as TdObject | undefined;
        if (sender === undefined) { continue; }
        if (sender['@type'] === 'messageSenderUser') {
          const uid = (sender['user_id'] as number | undefined) ?? 0;
          const name = getUserStore().displayName(uid);
          if (name === '') { getUserStore().ensure(uid); }
          names.push(name !== '' ? name : str('cp_user_id', uid));
        } else {
          const cid = (sender['chat_id'] as number | undefined) ?? 0;
          const entry = getChatStore().entryOf(cid);
          names.push(entry !== undefined ? entry.title : str('cp_anonymous'));
        }
      }
      promptAction.showDialog({
        title: str('cp_reaction_total', reactionDisplayLabel(reactionKey), total),
        message: names.length > 0 ? names.join('\n') : $r('app.string.cp_no_details'),
        buttons: [{ text: $r('app.string.close'), color: '#3390EC' }]
      }).catch((): void => {});
    }).catch((e: TdError): void => {
      console.error(`ChatPage.showReactors failed: ${e.message}`);
      promptAction.showToast({ message: $r('app.string.cp_no_reaction_details'), duration: 1600 });
    });
  }

  private closeReactionSheet(): void {
    this.showReactionSheet = false;
    this.reactionTargetId = 0;
  }

  private forwardableMessageIds(ids: number[]): number[] {
    const result: number[] = [];
    for (const id of ids) {
      const m: MessageEntry | null = this.findMsg(id);
      if (m !== null && m.contentType !== 'system' && m.contentType !== 'hidden' &&
        result.indexOf(id) < 0) {
        result.push(id);
      }
    }
    return result;
  }

  // Only decides *whether* the picker opens and what it will forward — the chat
  // list, filtering and the forwardMessages request live in ForwardSheet.
  private openForwardPicker(ids: number[]): void {
    const validIds: number[] = this.forwardableMessageIds(ids);
    ContextMenu.close();
    if (validIds.length === 0) {
      promptAction.showToast({ message: $r('app.string.cp_cannot_forward'), duration: 1500 });
      return;
    }
    this.closeReactionSheet();
    this.setEmojiPanel(false);
    this.forwardMessageIds = validIds;
    this.showForwardSheet = true;
  }

  private closeForwardSheet(): void {
    this.showForwardSheet = false;
    this.forwardMessageIds = [];
  }

  @Styles
  headerActionNormalStyle() {
    .backgroundColor($r('app.color.surface'))
    .opacity(1)
    .scale({ x: 1, y: 1 })
  }

  @Styles
  headerActionPressedStyle() {
    .backgroundColor($r('app.color.surface_alt'))
    .opacity(0.72)
    .scale({ x: 0.9, y: 0.9 })
  }

  @Styles
  headerIdentityNormalStyle() {
    .backgroundColor($r('app.color.surface'))
    .opacity(1)
    .scale({ x: 1, y: 1 })
  }

  @Styles
  headerIdentityPressedStyle() {
    .backgroundColor($r('app.color.surface_alt'))
    .opacity(0.78)
    .scale({ x: 0.985, y: 0.96 })
  }

  @Styles
  headerMenuRowNormalStyle() {
    .backgroundColor(Color.Transparent)
    .opacity(1)
  }

  @Styles
  headerMenuRowPressedStyle() {
    .backgroundColor($r('app.color.surface_alt'))
    .opacity(0.68)
  }

  @Styles
  topCardRowNormalStyle() {
    .backgroundColor(Color.Transparent)
    .opacity(1)
    .scale({ x: 1, y: 1 })
  }

  @Styles
  topCardRowPressedStyle() {
    .backgroundColor($r('app.color.surface_alt'))
    .opacity(0.82)
    .scale({ x: 0.992, y: 0.97 })
  }

  @Styles
  timelineStatusNormalStyle() {
    .opacity(1)
    .scale({ x: 1, y: 1 })
  }

  @Styles
  timelineStatusPressedStyle() {
    .opacity(0.76)
    .scale({ x: 0.97, y: 0.97 })
  }

  @Styles
  liveEntryNormalStyle() {
    .backgroundColor('#FF405C')
    .opacity(1)
    .scale({ x: 1, y: 1 })
  }

  @Styles
  liveEntryPressedStyle() {
    .backgroundColor('#E93652')
    .opacity(0.82)
    .scale({ x: 0.94, y: 0.94 })
  }

  @Styles
  scrollFabNormalStyle() {
    .backgroundColor($r('app.color.surface'))
    .opacity(1)
    .scale({ x: 1, y: 1 })
  }

  @Styles
  scrollFabPressedStyle() {
    .backgroundColor($r('app.color.surface_alt'))
    .opacity(0.84)
    .scale({ x: 0.92, y: 0.92 })
  }

  @Styles
  composerIconNormalStyle() {
    .backgroundColor(Color.Transparent)
    .opacity(1)
    .scale({ x: 1, y: 1 })
  }

  @Styles
  composerIconPressedStyle() {
    .backgroundColor($r('app.color.surface_alt'))
    .opacity(0.72)
    .scale({ x: 0.9, y: 0.9 })
  }

  @Styles
  composerPrimaryNormalStyle() {
    .backgroundColor(COLOR_PRIMARY)
    .opacity(1)
    .scale({ x: 1, y: 1 })
  }

  @Styles
  composerPrimaryPressedStyle() {
    .backgroundColor('#287BC8')
    .opacity(0.84)
    .scale({ x: 0.92, y: 0.92 })
  }

  @Styles
  suggestionRowNormalStyle() {
    .backgroundColor(Color.Transparent)
    .opacity(1)
    .scale({ x: 1, y: 1 })
  }

  @Styles
  suggestionRowPressedStyle() {
    .backgroundColor($r('app.color.surface_alt'))
    .opacity(0.76)
    .scale({ x: 0.985, y: 0.96 })
  }

  @Styles
  botKeyboardButtonNormalStyle() {
    .opacity(1)
    .scale({ x: 1, y: 1 })
  }

  @Styles
  botKeyboardButtonPressedStyle() {
    .opacity(0.72)
    .scale({ x: 0.96, y: 0.9 })
  }

  private closeChatPage(): void {
    if (this.pageClosing) {
      return;
    }
    this.pageClosing = true;
    this.headerMenuShow = false;
    if (this.headerNavigationTimer !== -1) {
      clearTimeout(this.headerNavigationTimer);
    }
    this.headerNavigationTimer = setTimeout((): void => {
      this.headerNavigationTimer = -1;
      this.pageClosing = false;
    }, CHAT_HEADER_NAV_GUARD_MS);
    router.back();
  }

  @Builder
  circleButton(symbol: string, onTap: () => void) {
    Row() {
      SymbolGlyph($r(symbol)).fontSize(22).fontColor([COLOR_TEXT_PRIMARY]);
    }
    .width(CHAT_HEADER_ACTION_SIZE)
    .height(CHAT_HEADER_ACTION_SIZE)
    .borderRadius(CHAT_HEADER_RADIUS)
    .justifyContent(FlexAlign.Center)
    .shadow({ radius: 4, color: '#12000000', offsetX: 0, offsetY: 1 })
    .stateStyles({
      normal: this.headerActionNormalStyle,
      pressed: this.headerActionPressedStyle
    })
    .animation({
      duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 120),
      curve: Curve.EaseOut
    })
    .onClick(onTap);
  }

  // Multi-select header: ✕ / count / copy / delete.
  @Builder
  selectionHeader() {
    Row({ space: 8 }) {
      this.circleButton('sys.symbol.xmark', () => { this.exitSelect(); });
      Text(str('cp_selected_n', this.selectedIds.length))
        .fontSize(16).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT_PRIMARY)
        .layoutWeight(1).margin({ left: 6 });
      this.circleButton('sys.symbol.arrowshape_turn_up_right', () => {
        this.openForwardPicker(this.selectedIds);
      });
      this.circleButton('sys.symbol.plus_square_on_square', () => { this.copySelected(); });
      Row() {
        SymbolGlyph($r('sys.symbol.trash')).fontSize(22).fontColor(['#FF3B30']);
      }
      .width(CHAT_HEADER_ACTION_SIZE)
      .height(CHAT_HEADER_ACTION_SIZE)
      .borderRadius(CHAT_HEADER_RADIUS)
      .justifyContent(FlexAlign.Center)
      .shadow({ radius: 4, color: '#12000000', offsetX: 0, offsetY: 1 })
      .stateStyles({
        normal: this.headerActionNormalStyle,
        pressed: this.headerActionPressedStyle
      })
      .animation({
        duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 120),
        curve: Curve.EaseOut
      })
      .onClick(() => { this.deleteSelected(); });
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: this.topSafe + 8, bottom: 8 })
    .alignItems(VerticalAlign.Center)
    .transition(TransitionEffect.OPACITY
      .combine(TransitionEffect.translate({ y: -5 }))
      .animation({
        duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 180),
        curve: Curve.EaseOut
      }));
  }

  // Search owns the complete top bar. Keeping the regular avatar/title beside
  // the field squeezed group/channel queries into a narrow trailing slot and
  // made the mode look like an accessory instead of navigation state.
  @Builder
  searchHeader() {
    Row({ space: 4 }) {
      Row() {
        SymbolGlyph($r('sys.symbol.chevron_left'))
          .fontSize(22).fontColor([COLOR_TEXT_PRIMARY]);
      }
        .width(40).height(40)
        .borderRadius(20)
        .justifyContent(FlexAlign.Center)
        .stateStyles({
          normal: this.headerMenuRowNormalStyle,
          pressed: this.headerMenuRowPressedStyle
        })
        .animation({
          duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 110),
          curve: Curve.EaseOut
        })
        .onClick((): void => { this.exitSearch(); })
        .accessibilityText($r('app.string.cp_back_to_chat'));
      TextInput({ text: this.searchQuery, placeholder: $r('app.string.cp_search_messages') })
        .layoutWeight(1).height(40).fontSize(16)
        .backgroundColor(Color.Transparent).padding(0).borderRadius(0)
        .placeholderColor(COLOR_TEXT_SECONDARY)
        .caretColor(COLOR_PRIMARY)
        .enterKeyType(EnterKeyType.Search)
        .defaultFocus(true)
        .onChange((v: string): void => { this.updateSearchQuery(v); })
        .onSubmit((): void => { this.runSearch(0, 0); });
      if (this.searchQuery !== '') {
        Row() {
          SymbolGlyph($r('sys.symbol.xmark_circle'))
            .fontSize(19).fontColor([COLOR_TEXT_SECONDARY]);
        }
        .width(34).height(34)
        .borderRadius(17)
        .justifyContent(FlexAlign.Center)
        .stateStyles({
          normal: this.headerMenuRowNormalStyle,
          pressed: this.headerMenuRowPressedStyle
        })
        .animation({
          duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 110),
          curve: Curve.EaseOut
        })
        .onClick((): void => { this.updateSearchQuery(''); })
        .accessibilityText($r('app.string.clear_search'));
      }
    }
    .width('calc(100% - 24vp)').height(46)
    .padding({ left: 3, right: 6 })
    .margin({ left: 12, right: 12, top: this.topSafe + 8, bottom: 8 })
    .backgroundColor($r('app.color.surface'))
    .border({ width: 0.5, color: $r('app.color.divider') })
    .borderRadius(23)
    .shadow({ radius: 5, color: '#16000000', offsetX: 0, offsetY: 1 })
    .alignItems(VerticalAlign.Center)
    .opacity(this.headerVisible ? 1 : 0)
    .translate({ y: this.headerVisible ? 0 : -6 })
    .animation({
      duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 220),
      curve: Curve.EaseOut
    })
    .transition(TransitionEffect.OPACITY
      .combine(TransitionEffect.translate({ y: -5 }))
      .animation({
        duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 180),
        curve: Curve.EaseOut
      }));
  }

  @Builder
  header() {
    Row({ space: 8 }) {
      this.circleButton('sys.symbol.chevron_left', () => { this.closeChatPage(); });
      Row({ space: 10 }) {
        AvatarView({
          avatarPath: this.avatarPath,
          initials: this.initials,
          colorSeed: this.chatId,
          avatarSize: 38
        });
        Column() {
          Row() {
            Text(this.headerText().titleText)
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor(COLOR_TEXT_PRIMARY)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .flexShrink(1);
            if (this.headerState === 'loading' || this.headerProfileOpening) {
              LoadingProgress()
                .width(15)
                .height(15)
                .color(COLOR_PRIMARY)
                .margin({ left: 5 });
            } else if (this.headerEmojiPath !== '') {
              if (this.headerEmojiFormat === 'tgs') {
                TgsStickerView({
                  tgsPath: this.headerEmojiPath,
                  boxWidth: 18,
                  boxHeight: 18,
                  powerCategory: 'emojiStatus'
                })
                  .margin({ left: 4 });
              } else if (this.headerEmojiFormat === 'webm') {
                WebmStickerView({
                  webmPath: this.headerEmojiPath,
                  boxWidth: 18,
                  boxHeight: 18,
                  powerCategory: 'emojiStatus'
                })
                  .margin({ left: 4 });
              } else {
                Image(`file://${this.headerEmojiPath}`).draggable(false)
                  .width(18)
                  .height(18)
                  .objectFit(ImageFit.Contain)
                  .margin({ left: 4 });
              }
            }
            if (this.headerMuteUpdating) {
              LoadingProgress()
                .width(14)
                .height(14)
                .color(COLOR_TEXT_SECONDARY)
                .margin({ left: 4 });
            } else if (this.isMuted) {
              SymbolGlyph($r('sys.symbol.bell_slash'))
                .fontSize(14)
                .fontColor([COLOR_TEXT_SECONDARY])
                .margin({ left: 4 });
            }
          }
          .width('100%')
          .alignItems(VerticalAlign.Center);
          Text(this.headerText().subtitleText)
            .fontSize(12)
            .fontColor(this.headerState === 'error' ? '#E64646' : COLOR_TEXT_SECONDARY)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ top: 1 });
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1);
      }
      .layoutWeight(1)
      .constraintSize({ minHeight: CHAT_HEADER_ACTION_SIZE })
      .padding({ left: 7, right: 12, top: 4, bottom: 4 })
      .borderRadius(CHAT_HEADER_RADIUS)
      .shadow({ radius: 4, color: '#12000000', offsetX: 0, offsetY: 1 })
      .stateStyles({
        normal: this.headerIdentityNormalStyle,
        pressed: this.headerIdentityPressedStyle
      })
      .animation({
        duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 140),
        curve: Curve.EaseOut
      })
      .accessibilityText(str('cp_header_a11y', this.headerText().titleText, this.headerText().subtitleText))
      .onClick((): void => {
        if (this.headerState === 'error') {
          this.resolveHeaderIdentity();
        } else {
          this.openProfile();
        }
      });
      Row() {
        // 菜单展开时汉堡变叉。两个图标叠着做交叉淡入淡出 + 反向旋转，比直接
        // 替换更像"同一个东西转过去了"。SVG 是位图路径、没法真正形变，这是
        // 视觉上最接近的做法。
        //
        // 系统符号库里没有汉堡线条（list_bullet 带项目符号，不是一回事），
        // 所以横线用自带的 SVG；fillColor 能染色，深浅色主题下跟其它图标一致。
        Stack() {
          Image($r('app.media.ic_header_menu'))
            .width(18).height(18)
            .fillColor(COLOR_TEXT_PRIMARY)
            .draggable(false)
            .opacity(this.headerMenuShow ? 0 : 1)
            .rotate({ angle: this.headerMenuShow ? 90 : 0 })
            // animation 必须挂在**属性发生变化的那个节点**上。挂在外层 Stack
            // 上不会生效——隐式动画只作用于同一节点自身的属性变化。
            .animation({
              duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 180),
              curve: Curve.EaseInOut
            });
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize(19).fontColor([COLOR_TEXT_PRIMARY])
            .opacity(this.headerMenuShow ? 1 : 0)
            .rotate({ angle: this.headerMenuShow ? 0 : -90 })
            .animation({
              duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 180),
              curve: Curve.EaseInOut
            });
        }
        .width(CHAT_HEADER_ACTION_SIZE).height(CHAT_HEADER_ACTION_SIZE);
      }
      .width(CHAT_HEADER_ACTION_SIZE)
      .height(CHAT_HEADER_ACTION_SIZE)
      .borderRadius(CHAT_HEADER_RADIUS)
      .justifyContent(FlexAlign.Center)
      .shadow({ radius: 4, color: '#12000000', offsetX: 0, offsetY: 1 })
      .stateStyles({
        normal: this.headerActionNormalStyle,
        pressed: this.headerActionPressedStyle
      })
      .animation({
        duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 120),
        curve: Curve.EaseOut
      })
      .bindMenu(this.headerMenuShow, this.headerMenu(), {
        onDisappear: (): void => { this.headerMenuShow = false; }
      })
      .enabled(!this.pageClosing && this.chatId !== 0)
      .accessibilityText($r('app.string.cp_more_actions'))
      .onClick((): void => {
        if (!this.headerMenuShow) {
          this.headerMenuShow = true;
        }
      });
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: this.topSafe + 8, bottom: 8 })
    .alignItems(VerticalAlign.Center)
    .opacity(this.headerVisible ? 1 : 0)
    .translate({ y: this.headerVisible ? 0 : -6 })
    .animation({
      duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 220),
      curve: Curve.EaseOut
    })
    .transition(TransitionEffect.OPACITY
      .combine(TransitionEffect.translate({ y: -5 }))
      .animation({
        duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 180),
        curve: Curve.EaseOut
      }));
  }

  // Suggestion panel above the input bar: group members for a trailing '@',
  // bot commands for a leading '/'.
  @Builder
  suggestionPanel() {
    Column() {
      if (this.commandPanelActive()) {
        Row({ space: 7 }) {
          Text('/').fontSize(18).fontWeight(FontWeight.Bold).fontColor(COLOR_PRIMARY);
          Text($r('app.string.cp_bot_commands')).fontSize(13).fontWeight(FontWeight.Medium).fontColor(COLOR_TEXT_PRIMARY);
          Blank().layoutWeight(1);
          if (this.commandLoadState === 'ready' && this.allCommands.length > 0) {
            Text(`${this.allCommands.length}`)
              .fontSize(11).fontColor(COLOR_TEXT_SECONDARY)
              .padding({ left: 7, right: 7, top: 2, bottom: 2 })
              .backgroundColor($r('app.color.surface_alt')).borderRadius(9);
          }
        }
        .width('100%').height(34).padding({ left: 14, right: 14 })
        .border({ width: { bottom: 0.7 }, color: $r('app.color.divider') });
        if (this.commandLoadState === 'loading' || this.commandLoadState === 'idle') {
          Row({ space: 9 }) {
            LoadingProgress().width(18).height(18).color(COLOR_PRIMARY);
            Text($r('app.string.cp_loading_commands')).fontSize(13).fontColor(COLOR_TEXT_SECONDARY);
          }
          .width('100%').height(72).justifyContent(FlexAlign.Center);
        } else if (this.commandLoadState === 'error') {
          Column({ space: 7 }) {
            Text(this.commandLoadError !== '' ? this.commandLoadError : $r('app.string.cp_commands_failed'))
              .fontSize(13).fontColor(COLOR_TEXT_PRIMARY);
            Text($r('app.string.settings_reload'))
              .fontSize(13).fontColor(COLOR_PRIMARY).fontWeight(FontWeight.Medium)
              .padding({ left: 14, right: 14, top: 6, bottom: 6 })
              .backgroundColor($r('app.color.selected_pill')).borderRadius(14)
              .onClick(() => { this.ensureCommandsLoaded(true); });
          }
          .width('100%').height(86).justifyContent(FlexAlign.Center);
        } else if (this.commandItems.length === 0) {
          Column({ space: 5 }) {
            Text(this.allCommands.length === 0 ? $r('app.string.cp_no_bot_commands') : $r('app.string.cp_no_matching_commands'))
              .fontSize(13).fontColor(COLOR_TEXT_PRIMARY);
            Text(this.allCommands.length === 0 ? $r('app.string.cp_chat_no_commands') : $r('app.string.cp_keep_typing'))
              .fontSize(12).fontColor(COLOR_TEXT_SECONDARY);
          }
          .width('100%').height(82).justifyContent(FlexAlign.Center);
        } else {
          List() {
            ForEach(this.commandItems, (it: CommandItem) => {
              ListItem() {
                Row({ space: 10 }) {
                  Row() {
                    Text('/').fontSize(18).fontWeight(FontWeight.Bold).fontColor(COLOR_PRIMARY);
                  }
                  .width(32).height(32).borderRadius(10)
                  .justifyContent(FlexAlign.Center)
                  .backgroundColor($r('app.color.selected_pill'));
                  Column({ space: 2 }) {
                    Text(this.commandText(it))
                      .fontSize(14).fontColor(COLOR_TEXT_PRIMARY).fontWeight(FontWeight.Medium)
                      .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
                    if (it.description !== '') {
                      Text(it.description).fontSize(12).fontColor(COLOR_TEXT_SECONDARY)
                        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
                    }
                  }
                  .alignItems(HorizontalAlign.Start).layoutWeight(1);
                  SymbolGlyph($r('sys.symbol.paperplane'))
                    .fontSize(14).fontColor([COLOR_TEXT_SECONDARY]);
                }
                .width('100%').padding({ left: 12, right: 12, top: 7, bottom: 7 })
                .alignItems(VerticalAlign.Center)
                .stateStyles({
                  normal: this.suggestionRowNormalStyle,
                  pressed: this.suggestionRowPressedStyle
                })
                .animation({
                  duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 110),
                  curve: Curve.EaseOut
                })
                .onClick(() => { this.pickCommand(it); });
              }
            }, (it: CommandItem) => `c_${it.command}_${it.botUserId}_${it.botUsername}`);
          }
          .width('100%').constraintSize({ maxHeight: 206 })
          .divider({ strokeWidth: 0.7, color: $r('app.color.divider'), startMargin: 54, endMargin: 12 });
        }
      } else {
        List() {
          ForEach(this.mentionItems, (it: MentionItem) => {
            ListItem() {
              Row({ space: 10 }) {
                AvatarView({ avatarPath: '', initials: it.name.substring(0, 1).toUpperCase(),
                  colorSeed: it.userId, avatarSize: 32 });
                Text(it.name).fontSize(15).fontColor(COLOR_TEXT_PRIMARY).maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis });
                if (it.username !== '') {
                  Text(`@${it.username}`).fontSize(13).fontColor(COLOR_TEXT_SECONDARY).maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis });
                }
              }
              .width('100%').padding({ left: 12, right: 12, top: 7, bottom: 7 })
              .alignItems(VerticalAlign.Center)
              .stateStyles({
                normal: this.suggestionRowNormalStyle,
                pressed: this.suggestionRowPressedStyle
              })
              .animation({
                duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 110),
                curve: Curve.EaseOut
              })
              .onClick(() => { this.pickMention(it); });
            }
          }, (it: MentionItem) => `m${it.userId}`);
        }
        .width('100%').constraintSize({ maxHeight: 240 })
        .divider({ strokeWidth: 0.7, color: $r('app.color.divider'), startMargin: 54, endMargin: 12 });
      }
    }
    .width('calc(100% - 28vp)')
    .backgroundColor($r('app.color.surface'))
    .borderRadius(16).clip(true)
    .shadow({ radius: 8, color: '#1A000000', offsetX: 0, offsetY: 2 })
    .margin({ left: 14, right: 14, bottom: 2 })
    .transition(TransitionEffect.OPACITY
      .combine(TransitionEffect.translate({ y: 8 }))
      .animation({ duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 180), curve: Curve.EaseOut }));
  }

  private startEdit(messageId: number): void {
    const msg = this.store?.getMessages().find(
      (m: MessageEntry): boolean => m.id === messageId);
    const captionTypes: string[] = ['photo', 'video', 'file', 'audio', 'voice'];
    if (msg === undefined || !msg.isOutgoing ||
      (msg.contentType !== 'text' && captionTypes.indexOf(msg.contentType) < 0)) {
      return;
    }
    if (this.editingId === 0) {
      this.draftBeforeEdit = this.draft;
    }
    this.editingId = messageId;
    this.editingKind = msg.contentType === 'text' ? 'text' : 'caption';
    this.editingPreview = msg.text !== '' ? msg.text
      : (this.editingKind === 'caption' ? str('cp_no_caption') : '');
    this.draft = msg.text;
  }

  private cancelEdit(): void {
    if (this.editingId === 0) { return; }
    this.editingId = 0;
    this.editingPreview = '';
    this.draft = this.draftBeforeEdit;
    this.draftBeforeEdit = '';
  }

  private commitEdit(): void {
    const store = this.store;
    const editId = this.editingId;
    const text = this.draft.trim();
    // Captions may be cleared (empty); message text may not.
    if (store === null || editId === 0 || this.composerSending ||
      (text === '' && this.editingKind === 'text')) {
      return;
    }
    this.composerSending = true;
    const task: Promise<void> = this.editingKind === 'caption'
      ? store.editCaptionAsync(editId, text) : store.editTextAsync(editId, text);
    task.then((): void => {
      this.composerSending = false;
      if (this.editingId === editId) {
        this.editingId = 0;
        this.editingPreview = '';
        this.draft = this.draftBeforeEdit;
        this.draftBeforeEdit = '';
      }
    }).catch((e: TdError): void => {
      this.composerSending = false;
      console.error(`ChatPage.commitEdit failed: ${e.message}`);
      promptAction.showToast({
        message: e.message.indexOf('MESSAGE_NOT_MODIFIED') >= 0
          ? $r('app.string.cp_no_change') : $r('app.string.cp_edit_failed'),
        duration: 1800
      });
    });
  }

  // Edit strip: pencil accent + original excerpt + ✕. Sits inside the same
  // rounded card as the input row (no own background/border/divider) so the
  // composer reads as one continuous surface.
  @Builder
  editPreview() {
    Row({ space: 10 }) {
      Row().width(3).height(34).borderRadius(2).backgroundColor(COLOR_PRIMARY);
      Column({ space: 1 }) {
        Text(this.editingKind === 'caption' ? $r('app.string.mb_edit_caption') : $r('app.string.cp_edit_message'))
          .fontSize(13).fontColor(COLOR_PRIMARY).fontWeight(FontWeight.Medium);
        Text(this.editingPreview).fontSize(13).fontColor(COLOR_TEXT_SECONDARY)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
      }
      .alignItems(HorizontalAlign.Start).layoutWeight(1);
      Row() {
        SymbolGlyph($r('sys.symbol.xmark')).fontSize(16).fontColor([COLOR_TEXT_SECONDARY]);
      }
      .width(32).height(32).borderRadius(16)
      .justifyContent(FlexAlign.Center)
      .onClick(() => { this.cancelEdit(); });
    }
    .width('100%').height(44).padding({ left: 12, right: 8 });
  }

  // Reply preview strip (Telegram style): accent bar, "回复 <name>", quoted
  // excerpt, and an ✕ to cancel. Sits inside the same rounded card as the
  // input row (no own background/border/divider) so the composer reads as
  // one continuous surface, with the accent bar spanning both text lines.
  @Builder
  replyPreview() {
    Row({ space: 10 }) {
      Row().width(3).height(34).borderRadius(2).backgroundColor(COLOR_PRIMARY);
      Column({ space: 1 }) {
        Text(`${str('mb_reply')} ${this.replyToName}`).fontSize(13).fontColor(COLOR_PRIMARY).fontWeight(FontWeight.Medium)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
        Text(this.replyToText).fontSize(13).fontColor(COLOR_TEXT_SECONDARY)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
      }
      .alignItems(HorizontalAlign.Start).layoutWeight(1)
      .onClick(() => { this.onReplyTap(this.replyToId); });
      Row() {
        SymbolGlyph($r('sys.symbol.xmark')).fontSize(16).fontColor([COLOR_TEXT_SECONDARY]);
      }
      .width(32).height(32).borderRadius(16)
      .justifyContent(FlexAlign.Center)
      .stateStyles({
        normal: this.suggestionRowNormalStyle,
        pressed: this.suggestionRowPressedStyle
      })
      .animation({ duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 110), curve: Curve.EaseOut })
        .onClick(() => { this.clearReply(); });
    }
    .width('100%').padding({ left: 16, right: 16, top: 7, bottom: 7 })
    .alignItems(VerticalAlign.Center)
    .transition(
      TransitionEffect.translate({ y: 12 })
        .combine(TransitionEffect.OPACITY)
        .animation({ duration: this.chatEffectDuration(KEY_POWER_EFFECT_REPLY, 180), curve: Curve.EaseOut })
    );
  }

  private replyKbVisible(): boolean {
    return this.membershipState === 'writable' &&
      this.replyKeyboard !== null && !this.replyKbCollapsed;
  }

  private composerPlaceholder(): string {
    // Live typing state borrows the composer's gray placeholder — costs no
    // space and can never cover a message.
    if (this.typingLabel !== '') {
      return this.typingLabel;
    }
    if (this.replyKbVisible() && this.replyKeyboard !== null &&
      this.replyKeyboard.placeholder.trim() !== '') {
      return this.replyKeyboard.placeholder;
    }
    return str('cp_message_placeholder');
  }

  // Bot custom reply keyboard: full-width button rows under the input bar.
  @Builder
  replyKeyboardPanel() {
    Scroll() {
      Column({ space: 6 }) {
        ForEach(this.replyKeyboard!.rows, (row: KeyboardBtn[], rowIdx: number) => {
          Row({ space: 6 }) {
            ForEach(row, (btn: KeyboardBtn, btnIdx: number) => {
              Row({ space: 6 }) {
                if (this.replyKeyboardSendingKey === `${rowIdx}_${btnIdx}_${btn.text}`) {
                  LoadingProgress()
                    .width(16).height(16)
                    .color(btn.style !== '' ? Color.White : COLOR_PRIMARY);
                }
                Text(btn.text)
                  .fontSize(14)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(btn.style !== '' ? Color.White : COLOR_TEXT_PRIMARY)
                  .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
                  .textAlign(TextAlign.Center);
                if (btn.type !== '' && btn.type !== KB_TEXT) {
                  SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
                    .fontSize(12)
                    .fontColor([btn.style !== '' ? Color.White : COLOR_TEXT_SECONDARY]);
                }
              }
              .layoutWeight(1)
              .constraintSize({ minHeight: 42 })
              .padding({ left: 8, right: 8, top: 7, bottom: 7 })
              .backgroundColor(botButtonBg(btn.style, $r('app.color.surface')))
              .borderRadius(10)
              .justifyContent(FlexAlign.Center)
              .stateStyles({
                normal: this.botKeyboardButtonNormalStyle,
                pressed: this.botKeyboardButtonPressedStyle
              })
              .animation({
                duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 110),
                curve: Curve.EaseOut
              })
              .enabled(this.replyKeyboardSendingKey === '')
              .onClick(() => {
                this.onReplyKeyboardTap(btn, `${rowIdx}_${btnIdx}_${btn.text}`);
              });
            }, (btn: KeyboardBtn, btnIdx: number) => `kb_${rowIdx}_${btnIdx}_${btn.text}`);
          }.width('100%');
        }, (_row: KeyboardBtn[], rowIdx: number) => `kbrow_${rowIdx}`);
      }
      .width('100%');
    }
    .width('calc(100% - 16vp)')
    .constraintSize({ maxHeight: this.replyKeyboard!.resize ? 210 : 280 })
    .scrollBar(BarState.Auto)
    .padding(8)
    .margin({ left: 8, right: 8, bottom: this.composerBottomGap() })
    .backgroundColor($r('app.color.surface_alt'))
    .borderRadius(16)
    .shadow({ radius: 6, color: '#16000000', offsetX: 0, offsetY: 2 })
    .transition(TransitionEffect.OPACITY
      .combine(TransitionEffect.translate({ y: 10 }))
      .animation({ duration: this.chatEffectDuration(KEY_POWER_EFFECT_MENU, 190), curve: Curve.EaseOut }))
    .onAreaChange((_old: Area, area: Area) => { this.replyKbH = area.height as number; });
  }

  // Replaces the composer for public groups/channels the current user hasn't
  // joined yet, and carries the mute toggle for read-only channels.
  //
  // Shaped exactly like the composer — a floating rounded capsule inset from
  // both edges, not a full-width bar with a divider. It occupies the same slot
  // and swaps with the composer as membership changes, so anything else reads
  // as the bottom of the screen changing shape.
  @Builder
  membershipBar() {
    Column() {
    Row({ space: 8 }) {
      if (this.membershipState === 'checking') {
        LoadingProgress()
          .width(20).height(20).color(COLOR_PRIMARY);
        Text($r('app.string.cp_fetching_membership'))
          .fontSize(15).fontColor(COLOR_TEXT_SECONDARY);
      } else if (this.membershipState === 'blocked') {
        Text($r('app.string.cp_cannot_join'))
          .fontSize(16).fontColor(COLOR_TEXT_SECONDARY).fontWeight(FontWeight.Medium);
      } else if (this.membershipState === 'readonly') {
        SymbolGlyph($r(this.isMuted ? 'sys.symbol.bell' : 'sys.symbol.bell_slash'))
          .fontSize(17).fontColor([COLOR_PRIMARY]);
        Text(this.isMuted ? $r('app.string.cp_unmute') : $r('app.string.cp_mute'))
          .fontSize(16).fontColor(COLOR_PRIMARY).fontWeight(FontWeight.Medium);
      } else {
        if (this.joiningChat) {
          LoadingProgress()
            .width(20).height(20).color(COLOR_PRIMARY);
        }
        Text(this.joiningChat ? $r('app.string.cp_joining') : $r('app.string.cp_join'))
          .fontSize(16).fontColor(COLOR_PRIMARY).fontWeight(FontWeight.Medium);
      }
    }
    .width('100%')
    // Same silhouette as the composer's inner pill.
    .constraintSize({ minHeight: 48 })
    .padding({ left: 12, right: 12, top: 4, bottom: 4 })
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .backgroundColor($r('app.color.surface'))
    .borderRadius(24)
    .enabled((this.membershipState === 'joinable' && !this.joiningChat) ||
      this.membershipState === 'readonly')
    .onClick(() => {
      if (this.membershipState === 'readonly') {
        this.toggleChatMute();
      } else {
        this.joinCurrentChat();
      }
    });
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 6, bottom: this.composerBottomGap() })
    .alignItems(HorizontalAlign.Center)
    .onAreaChange((_old: Area, area: Area) => { this.inputBarH = area.height as number; });
  }

  @Builder
  inputBar() {
    Row() {
      Column() {
        if (this.editingId !== 0) {
          this.editPreview();
        } else if (this.replyToId !== 0) {
          this.replyPreview();
        }
        Row({ space: 6 }) {
        if (this.isRecording) {
          // Recording mode: red dot + timer, 取消, send.
          Row({ space: 7 }) {
            Circle({ width: 8, height: 8 }).fill('#FF3B30');
            Text(this.formatRecSeconds()).fontSize(15).fontColor(COLOR_TEXT_PRIMARY);
            Text($r('app.string.cp_recording')).fontSize(13).fontColor(COLOR_TEXT_SECONDARY);
          }.layoutWeight(1).alignItems(VerticalAlign.Center);
          Button($r('app.string.cancel')).fontSize(13).fontColor(COLOR_TEXT_SECONDARY)
            .stateStyles({
              normal: this.composerIconNormalStyle,
              pressed: this.composerIconPressedStyle
            })
            .animation({ duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 120), curve: Curve.EaseOut })
            .onClick(() => { this.cancelRecording(); });
          Button() {
            SymbolGlyph($r('sys.symbol.paperplane')).fontSize(20).fontColor([Color.White]);
          }
          .width(40).height(40).borderRadius(20)
          .stateStyles({
            normal: this.composerPrimaryNormalStyle,
            pressed: this.composerPrimaryPressedStyle
          })
          .animation({ duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 120), curve: Curve.EaseOut })
          .onClick(() => { this.finishRecording(); });
        } else {
          if (this.botMenuAvailable) {
            // Bot 菜单 pill — toggles the full command catalog.
            Row({ space: 4 }) {
              SymbolGlyph($r(this.commandMenuOpen ? 'sys.symbol.xmark' : 'sys.symbol.line_3_horizontal'))
                .fontSize(15).fontColor([Color.White]);
              Text(this.commandMenuOpen ? $r('app.string.close') : $r('app.string.cp_menu')).fontSize(13).fontColor(Color.White);
            }
            .padding({ left: 9, right: 10, top: 6, bottom: 6 })
            .borderRadius(15)
            .stateStyles({
              normal: this.composerPrimaryNormalStyle,
              pressed: this.composerPrimaryPressedStyle
            })
            .animation({ duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 120), curve: Curve.EaseOut })
            .onClick(() => { this.toggleBotMenu(); });
          }
          SymbolGlyph($r(this.showEmojiPanel ? 'sys.symbol.face_smiling_fill' : 'sys.symbol.face_smiling'))
            .fontSize(24)
            .fontColor([this.showEmojiPanel ? COLOR_PRIMARY : COLOR_TEXT_SECONDARY])
            .onAreaChange((_old: Area, area: Area) => {
              const gx = area.globalPosition.x as number;
              this.emojiBtnCx = gx + (area.width as number) / 2;
            })
            .onClick(() => {
              this.setEmojiPanel(!this.showEmojiPanel);
              this.mentionItems = [];
              this.commandItems = [];
              this.commandMenuOpen = false;
            });
          TextArea({ text: this.draft, placeholder: this.composerPlaceholder(), controller: this.composerController })
            .layoutWeight(1)
            .height(this.composerEditorHeight())
            // No maxLines. It caps the LAYOUT, not just the visible box, so
            // anything past the last line never lays out and cannot be scrolled
            // to — a long draft was simply unreachable. The height above is the
            // only cap; beyond it the TextArea scrolls its own content.
            .maxLength(4096)
            .fontSize(15)
            .lineHeight(COMPOSER_LINE_H)
            .fontColor(COLOR_TEXT_PRIMARY)
            .caretColor(COLOR_PRIMARY)
            .padding({
              left: 3, right: 3,
              top: COMPOSER_EDITOR_PAD, bottom: COMPOSER_EDITOR_PAD
            })
            .barState(BarState.Auto)
            .backgroundColor(Color.Transparent)
            .key('chat_composer')
            .onChange((v: string) => {
              this.draft = v;
              this.updateSuggestions(v);
              if (v.trim() !== '' && this.editingId === 0) {
                this.store?.notifyTyping();
              }
            })
            // 聊天设置 → 回车键发送: the IME's action key becomes 发送 and submits;
            // otherwise TextArea keeps the ordinary newline action.
            .enterKeyType(this.sendByEnter ? EnterKeyType.Send : EnterKeyType.NEW_LINE)
            .onSubmit(() => {
              if (this.sendByEnter) {
                this.doSend();
              }
            })
            .onFocus(() => {
              // Capture this before RESIZE starts changing the List viewport.
              // Only a chat already at the live tail should follow the IME;
              // focusing while reading older messages must preserve position.
              this.imeTailPinned = this.atBottom && this.viewerMsgId === 0 &&
                !this.stayAtUnread;
              this.composerFocused = true;
              this.setEmojiPanel(false);
              this.replyKbCollapsed = true;
              this.commandMenuOpen = false;
              if (this.keyboardH > 0) {
                this.syncTailOnImeFrame();
              }
            })
            .onBlur(() => { this.composerFocused = false; });
          if (this.replyKeyboard !== null) {
            // Bot-keyboard toggle: tinted while the keyboard is up, gray when
            // collapsed — tapping flips between the two.
            Row() {
              SymbolGlyph($r('sys.symbol.keyboard'))
                .fontSize(21)
                .fontColor([this.replyKbCollapsed ? COLOR_TEXT_SECONDARY : COLOR_PRIMARY]);
            }
            .width(34).height(34).borderRadius(17)
            .justifyContent(FlexAlign.Center)
            .stateStyles({
              normal: this.composerIconNormalStyle,
              pressed: this.composerIconPressedStyle
            })
            .animation({
              duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 110),
              curve: Curve.EaseOut
            })
            .accessibilityText(this.replyKbCollapsed ? $r('app.string.cp_open_bot_keyboard') : $r('app.string.cp_switch_to_text'))
            .onClick(() => { this.toggleReplyKeyboard(); });
          }
          if (this.botMiniAppUrlValue !== '') {
            SymbolGlyph($r('sys.symbol.square_grid_2x2'))
              .fontSize(22).fontColor([COLOR_PRIMARY])
              .accessibilityText($r('app.string.cp_open_miniapp'))
              .onClick((): void => { this.openBotMiniApp(); });
          }
          SymbolGlyph($r('sys.symbol.paperclip'))
            .fontSize(22)
            .fontColor([COLOR_TEXT_SECONDARY])
            .bindMenu(this.attachMenuItems());
          // Mic ↔ send swap: outgoing icon shrinks/fades while the incoming one
          // scales in (the send button adds a small un-rotate flourish).
          Stack() {
            if (this.draft.trim() === '') {
              Button() {
                if (this.recordingStarting) {
                  LoadingProgress().width(18).height(18).color(Color.White);
                } else {
                  SymbolGlyph($r('sys.symbol.mic')).fontSize(20).fontColor([Color.White]);
                }
              }
              .width(40).height(40).borderRadius(20)
              .stateStyles({
                normal: this.composerPrimaryNormalStyle,
                pressed: this.composerPrimaryPressedStyle
              })
              .animation({ duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 120), curve: Curve.EaseOut })
              .enabled(!this.recordingStarting)
              .transition(TransitionEffect.OPACITY
                .combine(TransitionEffect.scale({ x: 0.3, y: 0.3 }))
                .animation({ duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 200), curve: Curve.EaseOut }))
              .onClick(() => { this.startRecording(); });
            } else {
              Button() {
                if (this.composerSending) {
                  LoadingProgress().width(18).height(18).color(Color.White);
                } else {
                  SymbolGlyph($r('sys.symbol.paperplane')).fontSize(20).fontColor([Color.White]);
                }
              }
              .width(40).height(40).borderRadius(20)
              .stateStyles({
                normal: this.composerPrimaryNormalStyle,
                pressed: this.composerPrimaryPressedStyle
              })
              .animation({ duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 120), curve: Curve.EaseOut })
              .enabled(!this.composerSending)
              .transition(TransitionEffect.OPACITY
                .combine(TransitionEffect.scale({ x: 0.3, y: 0.3 }))
                .combine(TransitionEffect.rotate({ angle: -45 }))
                .animation({ duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 200), curve: Curve.EaseOut }))
              .onClick(() => { this.doSend(); })
              // Long-press: schedule / silent send.
              .gesture(LongPressGesture().onAction(() => { this.showSendOptions(); }));
            }
          }.width(40).height(40);
        }
      }
        .width('100%')
        .constraintSize({ minHeight: 48, maxHeight: 120 })
        .padding({ left: 12, right: 4, top: 4, bottom: 4 })
        .alignItems(VerticalAlign.Center);
      }
      .width('100%')
      .backgroundColor($r('app.color.surface'))
      .borderRadius(24);
    }.width('100%')
    .padding({
      left: 14,
      right: 14,
      top: 6,
      bottom: this.replyKbVisible() ? 8 : this.composerBottomGap()
    })
    .alignItems(VerticalAlign.Center)
    .onAreaChange((_old: Area, area: Area) => { this.inputBarH = area.height as number; });
  }

  @Builder
  searchBottomBar() {
    Row() {
      Text(this.searchResults.length > 0
        ? `${this.searchTotal - this.searchIdx} / ${this.searchTotal}`
        : (this.searchTotal === 0 && this.searchQuery.trim() !== '' ? '' : $r('app.string.cp_search_placeholder')))
        .fontSize(15).fontColor(COLOR_TEXT_PRIMARY);
      Blank().layoutWeight(1);
      if (this.searchResults.length > 0) {
        Row() {
          SymbolGlyph($r('sys.symbol.chevron_up')).fontSize(22).fontColor([COLOR_TEXT_PRIMARY]);
        }
        .width(42).height(42).justifyContent(FlexAlign.Center)
        .opacity(this.searchIdx + 1 < this.searchTotal ? 1 : 0.4)
        .onClick(() => { this.searchOlder(); });
        Row() {
          SymbolGlyph($r('sys.symbol.chevron_down')).fontSize(22).fontColor([COLOR_TEXT_PRIMARY]);
        }
        .width(42).height(42).justifyContent(FlexAlign.Center)
        .opacity(this.searchIdx > 0 ? 1 : 0.4)
        .onClick(() => { this.searchNewer(); });
      }
    }
    .width('100%').height(52 + this.composerBottomGap())
    .padding({ left: 20, right: 10, bottom: this.composerBottomGap() })
    .alignItems(VerticalAlign.Center)
    .backgroundColor($r('app.color.surface'))
    .border({ width: { top: 0.7 }, color: $r('app.color.divider') });
  }

  @Builder
  bottomDock() {
    Column() {
      if (this.selecting) {
        // Selection owns the header actions; removing the composer also drops
        // its reserved list inset so messages expand naturally into the space.
        Column().width('100%').height(0);
      } else if (this.searchMode) {
        this.searchBottomBar();
      } else if (this.membershipState !== 'writable') {
        this.membershipBar();
      } else {
        Column() {
          this.inputBar();
          if (this.replyKbVisible()) {
            this.replyKeyboardPanel();
          }
        }
        .width('100%');
      }
    }
    .width('100%')
    .onAreaChange((_old: Area, area: Area) => {
      this.updateBottomChromeHeight(area.height as number);
    });
  }

  // Segmented indicator like Telegram: short vertical bars, the currently-shown
  // pinned message highlighted. A sliding window of up to PINNED_SEG_MAX bars so
  // the highlight moves on every tap (and the window scrolls past the window size).
  private pinnedShownIdx(): number {
    return Math.min(this.pinnedCycle, Math.max(0, this.pinnedCount - 1));
  }

  private pinnedSegCount(): number {
    return Math.min(this.pinnedCount, PINNED_SEG_MAX);
  }

  // Segments run oldest (top) → newest (bottom), so the newest pinned message
  // highlights the BOTTOM bar. pinnedShownIdx() is in newest-first space and
  // gets flipped into this display space.
  private pinnedDispActive(): number {
    return Math.max(0, this.pinnedCount - 1 - this.pinnedShownIdx());
  }

  private pinnedSegStart(): number {
    const n: number = this.pinnedSegCount();
    if (this.pinnedCount <= n) {
      return 0;
    }
    const s: number = this.pinnedDispActive() - (n - 1);
    return Math.max(0, Math.min(s, this.pinnedCount - n));
  }

  private pinnedSegs(): number[] {
    const n: number = this.pinnedSegCount();
    const a: number[] = [];
    for (let i = 0; i < n; i++) {
      a.push(i);
    }
    return a;
  }

  private pinnedActiveSeg(): number {
    return this.pinnedDispActive() - this.pinnedSegStart();
  }

  @Builder
  pinnedBanner() {
    Row({ space: 10 }) {
      Column() {
        ForEach(this.pinnedSegs(), (i: number) => {
          Column().width(3).layoutWeight(1)
            .backgroundColor(i === this.pinnedActiveSeg() ? COLOR_PRIMARY : '#303E3E40')
            .borderRadius(1.5).margin({ top: 1, bottom: 1 });
        }, (i: number) => `seg_${i}_${i === this.pinnedActiveSeg()}`);
      }.height(34).width(3);
      Column({ space: 2 }) {
        Row({ space: 6 }) {
          Text($r('app.string.cp_pinned_message')).fontSize(12).fontColor(COLOR_PRIMARY).fontWeight(FontWeight.Medium);
          if (this.pinnedCount > 1) {
            Text(`${this.pinnedShownIdx() + 1}/${this.pinnedCount}`)
              .fontSize(10)
              .fontColor(COLOR_TEXT_SECONDARY);
          }
          if (this.pinnedLoadState === 'loading') {
            LoadingProgress().width(12).height(12).color(COLOR_PRIMARY);
          }
        }
        Text(this.pinnedPreview).fontSize(13).fontColor(COLOR_TEXT_PRIMARY)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
      }
      .alignItems(HorizontalAlign.Start).layoutWeight(1);
      if (this.pinnedJumpBusy) {
        LoadingProgress().width(18).height(18).color(COLOR_PRIMARY);
      } else {
        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(15)
          .fontColor([COLOR_TEXT_SECONDARY]);
      }
    }
    .width('100%')
    .constraintSize({ minHeight: 54 })
    .padding({ left: 14, right: 14, top: 8, bottom: 8 })
    .alignItems(VerticalAlign.Center)
    .stateStyles({
      normal: this.topCardRowNormalStyle,
      pressed: this.topCardRowPressedStyle
    })
    .animation({
      duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 130),
      curve: Curve.EaseOut
    })
    .enabled(!this.pinnedJumpBusy)
    .accessibilityText(str('cp_pinned_a11y', this.pinnedPreview))
    .onClick(() => { this.onPinnedTap(); });
  }

  // Pinned and live rows are separate actions inside one shared card. This
  // preserves both features when they coexist while keeping their hierarchy
  // explicit: pinned content first, active live session second.
  @Builder
  liveStreamBanner() {
    Row({ space: 10 }) {
      Column()
        .width(3).height(34).backgroundColor('#FF405C').borderRadius(1.5)
        .opacity(this.livePulseExpanded ? 1 : 0.62)
        .scale({ x: 1, y: this.livePulseExpanded ? 1 : 0.82 })
        .animation({ duration: powerAnimationDuration(KEY_POWER_PARTICLES, 720), curve: Curve.EaseInOut });
      Column({ space: 2 }) {
        Row({ space: 6 }) {
          Text($r('app.string.cp_live_now')).fontSize(12).fontColor('#FF405C').fontWeight(FontWeight.Medium);
          if (this.liveCallIsRtmp) {
            Text($r('app.string.cp_one_way')).fontSize(9).fontColor(Color.White).fontWeight(FontWeight.Bold)
              .padding({ left: 5, right: 5, top: 2, bottom: 2 })
              .backgroundColor('#FF405C').borderRadius(6);
          }
          Circle({ width: 6, height: 6 }).fill('#FF405C')
            .opacity(this.livePulseExpanded ? 1 : 0.45);
        }
        Text(this.liveParticipantCount > 0 ? plural('cp_n_online', this.liveParticipantCount, this.liveParticipantCount) : $r('app.string.cp_live_in_progress'))
          .fontSize(13).fontColor(COLOR_TEXT_PRIMARY)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
      }
      .alignItems(HorizontalAlign.Start).layoutWeight(1);
      Button() {
        Row({ space: 5 }) {
          if (this.liveDialogOpening || this.liveNavigationBusy) {
            LoadingProgress().width(13).height(13).color(Color.White);
          }
          Text(this.liveNavigationBusy ? $r('app.string.cp_entering') : $r('app.string.cp_enter'))
            .fontSize(12)
            .fontColor(Color.White)
            .fontWeight(FontWeight.Medium);
        }
      }
        .height(32).padding({ left: 12, right: 12 })
        .borderRadius(16)
        .stateStyles({
          normal: this.liveEntryNormalStyle,
          pressed: this.liveEntryPressedStyle
        })
        .enabled(!this.liveDialogOpening && !this.liveNavigationBusy)
        .onClick((): void => { this.onLiveStreamTap(); });
    }
    .width('100%')
    .constraintSize({ minHeight: 54 })
    .padding({ left: 14, right: 12, top: 8, bottom: 8 })
    .alignItems(VerticalAlign.Center)
    .stateStyles({
      normal: this.topCardRowNormalStyle,
      pressed: this.topCardRowPressedStyle
    })
    .animation({
      duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 130),
      curve: Curve.EaseOut
    })
    .accessibilityText(`正在直播，${this.liveParticipantCount > 0 ?
      plural('cp_n_online', this.liveParticipantCount, this.liveParticipantCount) : $r('app.string.cp_live_in_progress')}，点击进入`)
    .onClick((): void => { this.onLiveStreamTap(); });
  }

  @Builder
  topCardLoadingBanner() {
    Row({ space: 12 }) {
      LoadingProgress().width(22).height(22).color(COLOR_PRIMARY);
      Column({ space: 2 }) {
        Text($r('app.string.cp_syncing_chat'))
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(COLOR_TEXT_PRIMARY);
        Text($r('app.string.cp_checking_pinned_live'))
          .fontSize(12)
          .fontColor(COLOR_TEXT_SECONDARY);
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1);
    }
    .width('100%')
    .constraintSize({ minHeight: 54 })
    .padding({ left: 14, right: 14, top: 8, bottom: 8 })
    .alignItems(VerticalAlign.Center)
    .accessibilityText($r('app.string.cp_syncing_pinned_live'));
  }

  @Builder
  topBanners() {
    Column() {
      if (this.topCardHasContent()) {
        if (this.pinnedPreview !== '') {
          this.pinnedBanner();
        }
        if (this.pinnedPreview !== '' && this.liveGroupCallId > 0 && this.liveCallIsActive) {
          Divider()
            .strokeWidth(0.5)
            .color($r('app.color.divider'))
            .margin({ left: 14, right: 14 });
        }
        if (this.liveGroupCallId > 0 && this.liveCallIsActive) {
          this.liveStreamBanner();
        }
      } else if (this.topCardLoadingVisible) {
        this.topCardLoadingBanner();
      }
    }
    .width('calc(100% - 24vp)')
    .backgroundColor($r('app.color.surface'))
    .borderRadius(14)
    .margin({ left: 12, right: 12, bottom: 2 })
    .shadow({ radius: 5, color: '#12000000', offsetX: 0, offsetY: 1 })
    .clip(true)
    .transition(TransitionEffect.OPACITY
      .combine(TransitionEffect.translate({ y: -6 }))
      .animation({ duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 240), curve: Curve.EaseOut }));
  }

  private scrollFabBadgeWidth(): number {
    if (this.unreadBadge > 99) {
      return 34;
    }
    return this.unreadBadge > 9 ? 27 : 22;
  }

  @Builder
  scrollFab() {
    Stack() {
      Button() {
        if (this.scrollToBottomBusy) {
          LoadingProgress().width(20).height(20).color(COLOR_PRIMARY);
        } else {
          SymbolGlyph($r('sys.symbol.chevron_down')).fontSize(22).fontColor([COLOR_TEXT_PRIMARY]);
        }
      }
      .width(46).height(46).borderRadius(23)
      .stateStyles({
        normal: this.scrollFabNormalStyle,
        pressed: this.scrollFabPressedStyle
      })
      .animation({ duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 130), curve: Curve.EaseOut })
      .shadow({ radius: 7, color: '#26000000', offsetX: 0, offsetY: 2 })
      .enabled(!this.scrollToBottomBusy)
      .accessibilityText(this.scrollToBottomBusy ? $r('app.string.cp_returning_latest') : $r('app.string.cp_return_latest'))
      .onClick(() => { this.scrollToLatest(); })
      .position({ x: 6, y: 10 });
      if (this.unreadBadge > 0) {
        Row() {
          Text(this.unreadBadge > 99 ? '99+' : `${this.unreadBadge}`)
            .fontSize(12).fontColor(Color.White).fontWeight(FontWeight.Medium)
            .maxLines(1).textAlign(TextAlign.Center);
        }
        .width(this.scrollFabBadgeWidth()).height(22)
        .justifyContent(FlexAlign.Center).alignItems(VerticalAlign.Center)
        .backgroundColor(COLOR_PRIMARY).borderRadius(11)
        .border({ width: 1.5, color: $r('app.color.surface') })
        .shadow({ radius: 3, color: '#24000000', offsetX: 0, offsetY: 1 })
        .position({ x: 52 - this.scrollFabBadgeWidth(), y: 0 })
        .animation({
          duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 140),
          curve: Curve.EaseOut
        })
        .transition(TransitionEffect.OPACITY
          .combine(TransitionEffect.scale({ x: 0.72, y: 0.72 }))
          .animation({
            duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 160),
            curve: Curve.EaseOut
          }))
        .enabled(!this.scrollToBottomBusy)
        .onClick((): void => { this.scrollToLatest(); })
        .accessibilityText(plural('cp_unread_a11y', this.unreadBadge, this.unreadBadge));
      }
    }
    .width(52).height(56)
    .transition(TransitionEffect.OPACITY
      .combine(TransitionEffect.scale({ x: 0.72, y: 0.72 }))
      .combine(TransitionEffect.translate({ y: 10 }))
      .animation({ duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 220), curve: Curve.EaseOut }));
  }

  private scrollToLatest(): void {
    if (this.store === null || this.scrollToBottomBusy) {
      return;
    }
    this.prepareUserJump();
    // Far from the live tail — unloaded pages below, OR a long stretch of
    // already-loaded history (scrollToIndex over thousands of lazy rows still
    // lays them out one by one and visibly crawls): atomically replace the
    // window with the newest page.
    const farFromEnd: boolean = this.groups.length - this.curStartIdx > JUMP_RELOAD_THRESHOLD;
    if (this.store.getHasMoreNewer() || farFromEnd) {
      const actionSeq: number = ++this.scrollActionSeq;
      this.scrollToBottomBusy = true;
      this.pendingScrollBottom = true;
      this.store.jumpToLatest((success: boolean): void => {
        if (actionSeq !== this.scrollActionSeq) {
          return;
        }
        this.scrollToBottomBusy = false;
        if (!success) {
          this.pendingScrollBottom = false;
          this.atBottom = false;
          promptAction.showToast({ message: $r('app.string.cp_latest_failed'), duration: 1600 });
        } else if (this.groups.length === 0) {
          this.pendingScrollBottom = false;
          this.atBottom = true;
        }
      });
      return;
    }
    // Close to the end and fully loaded — snap instantly, no animated crawl.
    const actionSeq: number = ++this.scrollActionSeq;
    this.scroller.scrollToIndex(Math.max(0, this.groups.length - 1), false, ScrollAlign.END);
    setTimeout((): void => {
      if (actionSeq === this.scrollActionSeq) {
        this.scroller.scrollEdge(Edge.Bottom);
        this.refreshAtBottom();
      }
    }, 60);
  }

  private backgroundEffectsEnabled(): boolean {
    return !this.chatBg.custom &&
      !this.powerSaving && this.powerChatEffects && this.powerBackgroundEffect;
  }

  private particlesEnabled(): boolean {
    return !this.chatBg.custom && !this.powerSaving && this.powerParticles;
  }

  private emptyHistoryTitle(): string {
    if (this.threadRootId > 0) {
      return str('cp_no_replies');
    }
    if (this.membershipState === 'blocked') {
      return str('cp_cannot_show');
    }
    if (this.isChannel) {
      return str('cp_channel_empty');
    }
    if (this.isGroup) {
      return str('cp_group_empty');
    }
    return str('cp_no_messages');
  }

  private emptyHistoryIcon(): string {
    if (this.membershipState === 'blocked') {
      return 'sys.symbol.lock_fill';
    }
    if (this.membershipState === 'joinable') {
      return 'sys.symbol.person_badge_plus';
    }
    if (this.threadRootId > 0) {
      return 'sys.symbol.arrowshape_turn_up_left';
    }
    return 'sys.symbol.message';
  }

  private emptyHistoryHint(): string {
    if (this.threadRootId > 0) {
      return this.membershipState === 'writable' ? str('cp_send_first_reply') : str('cp_no_replies_sub');
    }
    if (this.membershipState === 'joinable') {
      return str('cp_join_to_chat');
    }
    if (this.membershipState === 'blocked') {
      return str('cp_maybe_removed');
    }
    if (this.membershipState === 'checking') {
      return str('cp_confirming_membership');
    }
    if (this.isChannel) {
      return str('cp_posts_appear_here');
    }
    if (this.isGroup) {
      return str('cp_send_first_group');
    }
    return str('cp_send_to_start');
  }

  @Builder
  messageListState() {
    Column({ space: 9 }) {
      if (this.messageLoadState === 'loading') {
        Stack({ alignContent: Alignment.Center }) {
          Circle({ width: 56, height: 56 }).fill($r('app.color.surface_alt'));
          LoadingProgress()
            .width(30).height(30).color(COLOR_PRIMARY);
        }.width(56).height(56);
        Text($r('app.string.cp_syncing_messages'))
          .fontSize(16).fontColor(COLOR_TEXT_PRIMARY).fontWeight(FontWeight.Medium);
        Text($r('app.string.cp_history_soon'))
          .fontSize(13).fontColor(COLOR_TEXT_SECONDARY);
      } else if (this.messageLoadState === 'error') {
        Stack({ alignContent: Alignment.Center }) {
          Circle({ width: 56, height: 56 }).fill('#12E64646');
          SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
            .fontSize(30).fontColor(['#E64646']);
        }.width(56).height(56);
        Text($r('app.string.cp_messages_failed'))
          .fontSize(16).fontColor(COLOR_TEXT_PRIMARY).fontWeight(FontWeight.Medium);
        Text(this.messageLoadError !== '' ? this.messageLoadError : $r('app.string.cp_check_network'))
          .fontSize(13).fontColor(COLOR_TEXT_SECONDARY)
          .textAlign(TextAlign.Center).maxLines(2);
        Row({ space: 6 }) {
          SymbolGlyph($r('sys.symbol.arrow_clockwise')).fontSize(14).fontColor([Color.White]);
          Text($r('app.string.settings_retry')).fontSize(13).fontColor(Color.White).fontWeight(FontWeight.Medium);
        }
        .height(34).padding({ left: 14, right: 14 })
        .borderRadius(17)
        .stateStyles({
          normal: this.composerPrimaryNormalStyle,
          pressed: this.composerPrimaryPressedStyle
        })
        .animation({
          duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 120),
          curve: Curve.EaseOut
        })
        .onClick((): void => { this.store?.retryInitialHistory(); });
      } else {
        Stack({ alignContent: Alignment.Center }) {
          Circle({ width: 56, height: 56 }).fill($r('app.color.surface_alt'));
          SymbolGlyph($r(this.emptyHistoryIcon()))
            .fontSize(28).fontColor([COLOR_PRIMARY]);
        }.width(56).height(56);
        Text(this.emptyHistoryTitle())
          .fontSize(16).fontColor(COLOR_TEXT_PRIMARY).fontWeight(FontWeight.Medium);
        Text(this.emptyHistoryHint())
          .fontSize(13).fontColor(COLOR_TEXT_SECONDARY).textAlign(TextAlign.Center);
      }
    }
    .constraintSize({ minWidth: 210, maxWidth: this.screenW - 48 })
    .padding({ left: 24, right: 24, top: 22, bottom: 22 })
    .backgroundColor($r('app.color.surface'))
    .border({ width: 0.5, color: $r('app.color.divider') })
    .borderRadius(20)
    .shadow({ radius: 8, color: '#18000000', offsetX: 0, offsetY: 3 })
    .alignItems(HorizontalAlign.Center)
    .transition(TransitionEffect.OPACITY
      .combine(TransitionEffect.translate({ y: 8 }))
      .combine(TransitionEffect.scale({ x: 0.97, y: 0.97 }))
      .animation({
        duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 200),
        curve: Curve.EaseOut
      }));
  }

  private timelineStateMode(): string {
    if (this.visibleGroupCount <= 0) {
      return '';
    }
    if (this.messageLoadState === 'error') {
      return 'syncError';
    }
    if (this.messageLoadState === 'loading') {
      return 'syncLoading';
    }
    if (this.olderLoadState === 'error') {
      return 'olderError';
    }
    if (this.newerLoadState === 'error') {
      return 'newerError';
    }
    if (this.olderLoadState === 'loading') {
      return 'olderLoading';
    }
    if (this.newerLoadState === 'loading') {
      return 'newerLoading';
    }
    return '';
  }

  private timelineStateText(mode: string): string {
    if (mode === 'syncError') {
      return str('cp_sync_failed');
    }
    if (mode === 'syncLoading') {
      return str('cp_syncing_latest');
    }
    if (mode === 'olderError') {
      return str('cp_older_failed');
    }
    if (mode === 'newerError') {
      return str('cp_newer_failed');
    }
    return mode === 'olderLoading' ? str('cp_loading_older') : str('cp_loading_newer');
  }

  private timelineStateRetry(mode: string): void {
    if (this.store === null) {
      return;
    }
    if (mode === 'syncError') {
      this.store.retryInitialHistory();
    } else if (mode === 'olderError') {
      this.olderArmed = false;
      this.store.retryOlder();
    } else if (mode === 'newerError') {
      this.store.retryNewer();
    }
  }

  @Builder
  timelineStatePill() {
    Column() {
      Row({ space: 7 }) {
        if (this.timelineStateMode().indexOf('Loading') >= 0) {
          LoadingProgress().width(15).height(15).color(COLOR_PRIMARY);
        } else {
          SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
            .fontSize(15).fontColor(['#E64646']);
        }
        Text(this.timelineStateText(this.timelineStateMode()))
          .fontSize(12.5).fontColor(COLOR_TEXT_PRIMARY).fontWeight(FontWeight.Medium);
        if (this.timelineStateMode().indexOf('Error') >= 0) {
          Divider().vertical(true).height(14).color($r('app.color.divider'));
          Text($r('app.string.settings_retry')).fontSize(12.5).fontColor(COLOR_PRIMARY).fontWeight(FontWeight.Medium);
        }
      }
      .height(32)
      .padding({ left: 11, right: 11 })
      .backgroundColor($r('app.color.surface'))
      .border({ width: 0.5, color: $r('app.color.divider') })
      .borderRadius(16)
      .shadow({ radius: 5, color: '#1A000000', offsetX: 0, offsetY: 2 })
      .stateStyles({
        normal: this.timelineStatusNormalStyle,
        pressed: this.timelineStatusPressedStyle
      })
      .animation({
        duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 110),
        curve: Curve.EaseOut
      })
      .onClick((): void => { this.timelineStateRetry(this.timelineStateMode()); })
      .accessibilityText(this.timelineStateMode().indexOf('Error') >= 0
        ? str('cp_timeline_retry_a11y', this.timelineStateText(this.timelineStateMode()))
        : this.timelineStateText(this.timelineStateMode()));
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
    .padding({ top: this.floatDate !== '' ? 42 : 8 })
    .transition(TransitionEffect.OPACITY
      .combine(TransitionEffect.translate({ y: -6 }))
      .animation({
        duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 180),
        curve: Curve.EaseOut
      }));
  }

  @Builder
  messageListStateLayer() {
    Column() {
      this.messageListState();
    }
    .width('100%').height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .padding({ bottom: this.bottomChromeH + 28 })
    .hitTestBehavior(HitTestMode.Transparent);
  }

  // The flattened background, once it exists. Until then the layered version
  // below renders, so the chat never waits on the raster.
  @State bgRasterPath: string = '';

  private backgroundRasterParams(): BackgroundRasterParams {
    return {
      colors: this.chatBg.colors, angle: this.chatBg.angle, path: this.chatBg.path,
      isPattern: this.chatBg.isPattern, imageOpacity: this.chatBg.imageOpacity,
      dimming: this.chatBg.dimming, blurred: this.chatBg.blurred, userBlur: this.bgBlur,
      width: this.screenW, height: this.screenH
    };
  }

  // The blur-amount slider (ChatBackgroundPage) changes KEY_BG_BLUR in
  // AppStorage; @Watch fires this so the chat's background re-composites at
  // the new radius instead of keeping whatever was last rasterised.
  private onBgBlurChanged(): void {
    this.syncBackgroundRaster();
  }

  private bgRasterTimer: number = -1;

  private syncBackgroundRaster(): void {
    const params = this.backgroundRasterParams();
    const sig = rasterSignature(params);
    const hit = cachedRaster(sig);
    if (hit !== '') {
      this.bgRasterPath = hit;
      return;
    }
    // Drop the stale raster first: keeping the previous background on screen
    // while a new one encodes would show the wrong chat's wallpaper.
    this.bgRasterPath = '';
    // Debounced: background resolution publishes several INTERMEDIATE states
    // in quick succession while the theme/custom image settle (measured as
    // three full-screen JPEG encodes, 52+68+58ms, on every first entry). Only
    // the state that survives the quiet window is worth rasterizing — the live
    // layered background renders meanwhile, so nothing is visually missing.
    if (this.bgRasterTimer !== -1) {
      clearTimeout(this.bgRasterTimer);
    }
    this.bgRasterTimer = setTimeout((): void => {
      this.bgRasterTimer = -1;
      const settled = this.backgroundRasterParams();
      const settledSig = rasterSignature(settled);
      const settledHit = cachedRaster(settledSig);
      if (settledHit !== '') {
        this.bgRasterPath = settledHit;
        return;
      }
      rasterizeBackground(this.getUIContext(), settled,
        (getContext(this) as common.UIAbilityContext).cacheDir).then((path: string): void => {
        // The background can change again while this encodes.
        if (path !== '' && rasterSignature(this.backgroundRasterParams()) === settledSig) {
          this.bgRasterPath = path;
        }
      });
    }, 280);
  }

  @Builder
  chatBackgroundLayer() {
    if (this.bgRasterPath !== '') {
      // Through the PixelMap cache, not Image(file://…). The raster is a
      // full-screen JPEG, so decoding it costs ~20ms — and measurement showed
      // that bill being paid again on every single chat open, which is most of
      // why the first entry into a chat stuttered while the second felt fine.
      // Every chat shares the same background, so cached it is decoded once.
      CachedImage({
        path: this.bgRasterPath,
        boxWidth: this.screenW,
        boxHeight: this.screenH,
        radius: 0,
        fit: ImageFit.Cover,
        pin: true
      });
    } else {
    Stack() {
      if (this.chatBg.colors.length > 0) {
        Column()
          .width('100%').height('100%')
          .linearGradient({
            angle: this.chatBg.angle,
            colors: gradientStops(this.chatBg.colors)
          });
      } else {
        Column().width('100%').height('100%')
          .backgroundColor($r('app.color.chat_bg'));
      }
      // A pattern document is a small repeatable motif, not a standalone
      // photo: the official client tiles it edge-to-edge at a fixed density
      // instead of fitting one instance to the screen (see
      // patternTileGrid()'s comment in chatBackgroundRaster.ets — fitting one
      // instance with Contain is what used to leave the screen's off-axis
      // edges bare on devices wider than the pattern's own ratio, e.g.
      // tablets). A wallpaper photo still fills the surface and crops
      // (Cover).
      if (this.chatBg.path !== '' && this.chatBg.isPattern) {
        patternTileGridLayer(
          this.chatBg.path, this.chatBg.imageOpacity,
          patternTileGrid(this.screenW, this.screenH),
          backgroundBlurRadius(this.chatBg.path, this.chatBg.isPattern, this.chatBg.blurred, this.bgBlur));
      } else if (this.chatBg.path !== '') {
        Image(this.chatBg.path.startsWith('/')
          ? `file://${this.chatBg.path}` : this.chatBg.path).draggable(false)
          .width('100%').height('100%')
          .objectFit(ImageFit.Cover)
          .opacity(this.chatBg.imageOpacity)
          // Blurring needs a little overscan or transparent edge pixels become
          // visible around the viewport. Gated on the actual radius (not just
          // the `blurred` flag) so a user-set blur of 0 doesn't overscan either.
          .scale({
            x: backgroundBlurRadius(this.chatBg.path, this.chatBg.isPattern, this.chatBg.blurred, this.bgBlur) > 0
              ? 1.08 : 1,
            y: backgroundBlurRadius(this.chatBg.path, this.chatBg.isPattern, this.chatBg.blurred, this.bgBlur) > 0
              ? 1.08 : 1
          })
          .blur(backgroundBlurRadius(this.chatBg.path, this.chatBg.isPattern, this.chatBg.blurred, this.bgBlur));
      }
      if (this.chatBg.dimming > 0) {
        Column().width('100%').height('100%')
          .backgroundColor(Color.Black)
          .opacity(this.chatBg.dimming);
      }
    }
    .width('100%').height('100%')
    .hitTestBehavior(HitTestMode.None)
    // The tile grid rounds up to a whole number of tiles and is centered by
    // the Stack's default alignment, so it typically overruns the viewport a
    // little on every edge — clip it back instead of letting it push out.
    .clip(true);
    }
  }

  @Builder
  chatPowerBackground() {
    Stack() {
      this.chatBackgroundLayer();
      if (this.backgroundEffectsEnabled()) {
        Circle({ width: 250, height: 250 })
          .fill('#142A9FE8')
          .position({ x: this.powerBackgroundPhase ? this.screenW - 150 : -90, y: 110 })
          .opacity(this.powerBackgroundPhase ? 0.42 : 0.18)
          .animation({
            duration: this.chatEffectDuration(KEY_POWER_EFFECT_BACKGROUND, 4200),
            curve: Curve.EaseInOut
          });
        Circle({ width: 210, height: 210 })
          .fill('#1056C76F')
          .position({ x: this.powerBackgroundPhase ? -70 : this.screenW - 130, y: 500 })
          .opacity(this.powerBackgroundPhase ? 0.16 : 0.36)
          .animation({
            duration: this.chatEffectDuration(KEY_POWER_EFFECT_BACKGROUND, 4200),
            curve: Curve.EaseInOut
          });
      }
      if (this.particlesEnabled()) {
        ForEach(this.powerParticleIds, (id: number) => {
          Circle({ width: 3 + (id % 3), height: 3 + (id % 3) })
            .fill(id % 2 === 0 ? '#462A9FE8' : '#3D56C76F')
            .position({
              x: 22 + ((id * 67 + (this.powerBackgroundPhase ? 34 : 0)) % Math.max(40, this.screenW - 44)),
              y: 120 + ((id * 151 + (this.powerBackgroundPhase ? 90 : 0)) % 650)
            })
            .opacity(this.powerBackgroundPhase ? 0.2 + (id % 3) * 0.12 : 0.48 - (id % 3) * 0.08)
            .animation({ duration: powerAnimationDuration(KEY_POWER_PARTICLES, 4200), curve: Curve.EaseInOut });
        }, (id: number): string => `power_particle_${id}`);
      }
    }
    .width('100%').height('100%')
    .hitTestBehavior(HitTestMode.None);
  }

  build() {
    Stack() {
      this.chatPowerBackground();
      Column() {
        Stack() {
        List({ scroller: this.scroller }) {
          // LazyForEach (not ForEach) is required for maintainVisibleContentPosition
          // to hold the scroll position when older pages are prepended above.
          LazyForEach(this.groupsData, (g: AlbumGroup) => {
            ListItem() {
              Stack({ alignContent: Alignment.Start }) {
              // Selection mode shifts the row right into a left check gutter
              // (instead of overlaying the check on the avatars).
              Row() {
              if (this.selecting && g.head.contentType !== 'system' && g.head.contentType !== 'hidden') {
                Column() {
                  if (this.rowSelected(g)) {
                    SymbolGlyph($r('sys.symbol.checkmark_circle'))
                      .fontSize(22).fontColor([COLOR_PRIMARY]);
                  } else {
                    Row()
                      .width(20).height(20).borderRadius(10)
                      .border({ width: 1.5, color: '#8E8E93' });
                  }
                }
                .width(34)
                .justifyContent(FlexAlign.Center)
                .alignItems(HorizontalAlign.Center);
              }
              Column() {
              MessageBubble({ msg: g.head, nowSec: this.nowSec, isGroup: this.isGroup, isChannel: this.isChannel,
                liveSharingId: this.liveLocationMessageId,
                onStopLiveLocation: (): void => { this.confirmStopLiveLocation(); },
                themeBubbleOut: this.chatBg.bubbleOutColor,
                showUnreadDivider: this.firstUnreadId !== 0 &&
                  g.memberIds.indexOf(this.firstUnreadId) >= 0,
                dateLabel: g.dateLabel,
                albumPaths: g.photoPaths, albumFileIds: g.photoFileIds, albumRatios: g.photoRatios,
                albumMemberIds: g.memberIds, albumIsVideo: g.photoIsVideo,
                albumProgress: g.photoProgress, albumFailed: g.photoFailed,
                albumVideoFileIds: g.videoFileIds, albumVideoFileSizes: g.videoFileSizes,
                albumVideoMimeTypes: g.videoMimeTypes,
                albumCaption: g.caption,
                albumCaptionEntities: g.captionEntities,
                onMediaTap: (id: number, x: number, y: number): void => {
                  this.tapX = x;
                  this.tapY = y;
                  this.openViewer(id);
                },
                onLinkTap: (u: string): void => { this.onLinkTap(u); },
                onCommentTap: (id: number): void => { this.onCommentTap(id); },
                onForwardTap: (cid: number, mid: number, uid: number): void => {
                  this.onForwardTap(cid, mid, uid);
                },
                onBotCallback: (id: number, data: string): void => { this.onBotCallback(id, data); },
                onAvatarTap: (uid: number): void => {
                  const params: Record<string, Object> = { 'userId': uid };
                  router.pushUrl({ url: 'pages/profile/ProfilePage', params: params });
                },
                onAvatarLongPress: (uid: number, name: string): void => {
                  this.mentionSender(uid, name);
                },
                onReplyTap: (id: number): void => { this.onReplyTap(id); },
                onEditMsg: (id: number): void => { this.startEdit(id); },
                onShowReactors: (id: number, emoji: string): void => {
                  this.showReactors(id, emoji);
                },
                onTranslateMsg: (id: number): void => { this.translateMessage(id); },
                onToggleTranslation: (id: number, hidden: boolean): void => {
                  this.toggleTranslationHidden(id, hidden);
                },
                onPinMsg: (id: number, unpin: boolean): void => { this.togglePinMessage(id, unpin); },
                onStopPoll: (id: number): void => { this.stopPoll(id); },
                onReplaceMedia: (id: number): void => { this.replaceMedia(id); },
                onPollVoters: (id: number): void => { this.showPollVoters(id); },
                onSetDefaultReaction: (emoji: string): void => { this.setDefaultReaction(emoji); },
                isPinnedMsg: (this.store?.getPinnedIds() ?? []).indexOf(g.head.id) >= 0,
                onFileTap: (id: number): void => { this.onFileTap(id); },
                onFileSave: (id: number): void => { this.onFileSave(id); },
                onStickerRetry: (id: number): void => { this.store?.retrySticker(id); },
                onLinkPreviewRetry: (id: number): void => { this.store?.retryLinkPreviewPhoto(id); },
                onContactOpen: (userId: number, phone: string, vcard: string): void => {
                  this.openSharedContact(userId, phone, vcard);
                },
                onPhoneOpen: (phone: string): void => { this.openSharedPhone(phone); },
                onLocationOpen: (
                  latitude: number,
                  longitude: number,
                  label: string,
                  valid: boolean
                ): void => {
                  this.openSharedLocation(latitude, longitude, label, valid);
                },
                onPollVote: (id: number, optionIds: number[]): void => {
                  this.onPollVote(id, optionIds);
                },
                onGameOpen: (id: number): void => { this.onGameOpen(id); },
                onGamePhotoRetry: (id: number): void => { this.store?.retryPhoto(id); },
                paidMediaPending: this.paidMediaPending(g.head.id),
                onPaidMediaUnlock: (id: number): void => {
                  this.onPaidMediaUnlock(id);
                },
                onPaidMediaOpen: (id: number): void => {
                  this.onPaidMediaOpen(id);
                },
                onSpecialPhotoRetry: (id: number): void => {
                  this.store?.retryPhoto(id);
                },
                onVideoRetry: (id: number): void => {
                  this.store?.requestVideoDownload(id, true);
                },
                onGiftCodeCopy: (code: string): void => {
                  this.onGiftCodeCopy(code);
                },
                onGiveawayOpen: (chatId: number, messageId: number): void => {
                  this.onGiveawayOpen(chatId, messageId);
                },
                onVoiceTap: (id: number): void => { this.onVoiceTap(id); },
                onVoicePlaybackStarted: (id: number): void => {
                  this.onVoicePlaybackStarted(id);
                },
                // 三元短路是必需的，不是风格问题：这四个值要读整个 messages 数组，而
                // ArkUI 按"build 期实际读取"记录状态依赖。无条件地算它们，等于让每一
                // 条消息行的 build 都依赖整个 messages @State —— store 每 notify 一次
                // （哪怕只是某张图的下载进度动了一下），所有可见行都会重跑 build、拿到
                // 新的 MessageEntry、整行重建。实测 notify≈10/秒时 rebuild≈140/秒，
                // 比值就是可见行数；notify 为 0 的那些秒 rebuild 恰好也是 0。
                // 这四个 prop 只在 MessageBubble 的 contentType === 'audio' 分支里被
                // 消费，非音频行传常量完全等价。不要"化简"掉三元。
                audioQueuePosition: audioQueueApplies(g.head.contentType)
                  ? this.musicQueue.queuePosition(this.messages, g.head.id) : 0,
                audioQueueLength: audioQueueApplies(g.head.contentType)
                  ? this.musicQueue.queueLength(this.messages) : 0,
                audioHasPrevious: audioQueueApplies(g.head.contentType)
                  ? this.musicQueue.hasPrevious(this.messages, g.head.id) : false,
                audioHasNext: audioQueueApplies(g.head.contentType)
                  ? this.musicQueue.hasNext(this.messages, g.head.id) : false,
                onAudioTap: (id: number): void => { this.musicQueue.play(this.messages, id, false); },
                onAudioPrevious: (id: number): void => { this.musicQueue.previous(this.messages, id); },
                onAudioNext: (id: number): void => { this.musicQueue.next(this.messages, id); },
                onAudioSeek: (id: number, fraction: number): void => {
                  this.musicQueue.seek(id, fraction);
                },
                onAutoplayVideoNeedDownload: (id: number): void => {
                  this.store?.requestVideoDownload(id);
                },
                animationPaused: this.animationPaused(g.head.id),
                animationForcePlay: this.animationForcePlay(g.head.id),
                animationPlaybackFailed: this.animationPlaybackFailed(g.head.id),
                onAnimationTap: (id: number, playing: boolean): void => {
                  this.onAnimationTap(id, playing);
                },
                onAnimationPlaybackFailed: (id: number): void => {
                  this.onAnimationPlaybackFailed(id);
                },
                onSetReaction: (id: number, emoji: string, chosen: boolean): void => { this.toggleReaction(id, emoji, chosen); },
                onReplyTo: (id: number): void => { this.startReply(id); },
                editingActive: this.editingId !== 0,
                onCopyText: (id: number): void => { this.copyMessageText(id); },
                onCopyCode: (text: string): void => { this.copyPlainText(text, str('cp_code_copied')); },
                onCopyLink: (id: number): void => { this.copyMessageLink(id); },
                onForwardMsg: (_id: number): void => { this.openForwardPicker(g.memberIds); },
                onReportMsg: (id: number): void => { promptAction.showToast({ message: $r('app.string.cp_report_wip'), duration: 1500 }); },
                onSelectMsg: (id: number): void => { this.enterSelect(id); },
                onDeleteMsg: (id: number): void => { this.deleteMessage(id); },
                onOpenReactions: (id: number): void => { this.openReactionSheet(id); },
                onRecognizeSpeech: (id: number): void => { this.recognizeSpeech(id); },
                onVideoNoteDownload: (id: number): void => {
                  this.store?.requestVideoDownload(id, true);
                },
                liveGroupCallId: this.liveCallIsActive ? this.liveGroupCallId : 0,
                // Reuses the same navigation as the "正在直播" banner (onLiveStreamTap
                // already reads this.liveGroupCallId and no-ops if it's gone stale).
                onLiveStreamTap: (): void => { this.onLiveStreamTap(); },
                showAvatar: g.showAvatar,
                showSenderName: g.showSenderName,
                playSlotKey: this.playSlotKey,
                autoplayMuted: this.autoplayMuted,
                onPlaySlotPositionChanged: (msgId: number, albumIndex: number, positionMs: number): void => {
                  this.bubblePositionMs.set(msgId, positionMs);
                },
                onMediaRatio: (msgId: number, albumIndex: number, ratio: number, centerY: number): void => {
                  // 查看器开着/页面不可见时不灌候选表——不然它在不该增长的
                  // 时候被一批陈旧 ratio 填满，查看器一关或页面一恢复就可能
                  // 直接 elect 出播放位（同一个根因见 armPlaySlotSettle）。
                  if (this.viewerMsgId !== 0 || !this.pageVisible) {
                    return;
                  }
                  // 「自动播放视频」关掉 / 省电模式 / 减少动效：闸门加在这里
                  // 而不是挂载点上——连候选表都不灌，就连分片下载都不会发起
                  // （spec §1：powerSaving 只影响 stream，退回封面 + 播放按钮）。
                  if (!this.playSlotsEnabled()) {
                    return;
                  }
                  const now = Date.now();
                  // report() 内部已经跑过一次 elect：ratio 已经攒够驻留（或
                  // 本来就是现任/被 pin）的候选会立即当选。这里只需要为还
                  // 没攒够的候选补一个"驻留到点后再查一次"的定时器。
                  this.playSlots.report(msgId, albumIndex, ratio, centerY, now);
                  this.maybeScheduleNextSlotCheck(now);
                },
                onMediaGone: (msgId: number, albumIndex: number): void => {
                  // 移除永远安全，不加守卫——挡住反而会在候选表里留幽灵条目。
                  this.playSlots.drop(msgId, albumIndex);
                },
                // 播完 / 内嵌播放失败：立刻让出播放位，由其它候选重新竞选。
                // 不会自我循环，理由见 PlaySlotRegistry.retire()。
                onPlaySlotEnded: (msgId: number, albumIndex: number): void => {
                  const now = Date.now();
                  this.playSlots.retire(msgId, albumIndex, now);
                  this.maybeScheduleNextSlotCheck(now);
                },
                playSlotStartMs: this.playSlotStartMs,
                animateIn: this.freshSinceId !== 0 && g.head.id > this.freshSinceId });
              }
              .layoutWeight(1);
              }
              .width('100%')
              .alignItems(VerticalAlign.Center)
              .backgroundColor(this.selecting && this.rowSelected(g) ? $r('app.color.select_highlight') : Color.Transparent)
              .animation({
                duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 150),
                curve: Curve.EaseOut
              })
              // Selection mode: the row itself takes every tap (children are
              // excluded from hit-testing), so any tap toggles selection.
              .hitTestBehavior(this.selecting && g.head.contentType !== 'system' && g.head.contentType !== 'hidden'
                ? HitTestMode.Block : HitTestMode.Default)
              .onClick(() => {
                if (this.selecting) {
                  this.toggleSelectRow(g);
                }
              });
              }
            }
          }, (g: AlbumGroup, index: number): string =>
            // Format lives in rowKeyOf — see its comment.
            guardKey(this.groupsData.keyTableId, index, this.rowKeyOf(g)));
        }
        .width('100%').height('100%')
        // 顶部 chrome 是悬浮的，用 contentStartOffset 让位——和底部的
        // contentEndOffset 对称。不用 padding：padding 会改变内容区尺寸，
        // 而滚动锚点、getItemRect 那一套都吃列表几何。
        .contentStartOffset(this.headerChromeH)
        // 消息滑到标题栏下面时逐渐糊掉，而不是被一条硬边切断。
        // 省电模式下关掉——渐变模糊是逐帧实时渲染，代价不低。
        .linearGradientBlur(this.headerBlurRadius(), {
          fractionStops: this.headerBlurStops(),
          direction: GradientDirection.Bottom
        })
        .contentEndOffset(this.bottomChromeH + 8)
        // Pre-build a few offscreen rows so a fling doesn't pay the full
        // MessageBubble construction cost inside the visible frame.
        // Starts small and grows once the chat is on screen.
        //
        // Measurement put the first-open jank at page-build time, before any
        // image decode and on the UI thread — and cachedCount is the biggest
        // multiplier there: at 4 the list builds the visible rows plus four
        // above and four below before it can present anything, each one a
        // MessageBubble with its whole content-type branch tree. Deferring the
        // off-screen ones costs nothing visually and takes them off the path
        // between the tap and the first frame.
        .cachedCount(this.listCachedCount)
        // Keep the visible messages pinned in place when an older page is
        // prepended above — without this, the List stays index-anchored and
        // visibly jumps to the top of the newly loaded page.
        .maintainVisibleContentPosition(true)
        .onReachStart(() => { this.maybeLoadOlder(); })
        // Each new touch gesture re-arms one older-page load: a fling that ends
        // pinned at the very top (start index never leaves the trigger zone)
        // would otherwise never re-arm, leaving the user unable to load more.
        .onTouch((e: TouchEvent) => {
          if (e.type === TouchType.Down) {
            // A real gesture transfers scroll ownership to the user; never
            // snap back to the bottom while they inspect older messages.
            this.imeTailPinned = false;
            this.imeLayoutSeq++;
            this.listTouchActive = true;
            this.olderArmed = true;
            // The highlight overlay is viewport-anchored — drop it as soon as
            // the user starts interacting, before it can detach from its row.
            this.cancelFlash();
            // Tapping outside the emoji/sticker panel dismisses it.
            this.setEmojiPanel(false);
          } else if (e.type === TouchType.Up || e.type === TouchType.Cancel) {
            this.listTouchActive = false;
          }
        })
        .onScrollIndex((start: number, end: number) => {
          // List 首次布局完成即触发一次（哪怕用户从未滑动），是首屏唯一能可靠
          // 拿到的信号；正常滚动时它也会随可见区间变化反复触发。判定本身现在
          // 是逐候选驻留（见 PlaySlotRegistry），与列表是否仍在滚动无关，这里
          // 只是幂等地补一次 tick + 重排后续检查——onScrollStop 那次是重复但
          // 无害的（scheduleSlotTick 只留一个在途）。
          this.armPlaySlotSettle();
          this.refreshAtBottom();
          this.curStartIdx = start;
          this.curEndIdx = end;
          this.markVisibleRead(end);
          this.updatePinnedFromScroll(start);
          this.growCachedCount();
          // Image prefetch: the data source decodes the photos of rows about to
          // arrive and cancels the ones scrolled past. Distinct from the page
          // prefetch below, which loads MESSAGES.
          this.imagePrefetcher.visibleAreaChanged(start, end);
          // 整聊天翻译与图片预取同源驱动：翻到哪儿译到哪儿。
          this.driveTranslations(start, end);
          // 媒体自动下载的可见窗口：只有窗口内的动图/语音才自动下载，划出去
          // 的自动取消（见 MessageStore.setMediaWindow）。
          this.syncMediaWindow(start, end);
          // Prefetch: kick off the previous/next page a few rows before the edge,
          // so scrolling never actually hits an empty top/bottom. loadOlder is
          // one-shot per arm (see maybeLoadOlder) so a fling that stays pinned
          // at the top can't chain-load page after page.
          if (start > 4) {
            this.olderArmed = true; // moved clear of the top zone — re-arm
          } else {
            this.maybeLoadOlder();
          }
          if (this.store !== null && end >= this.groups.length - 5) {
            this.store.loadNewer();
          }
        })
        // onScrollIndex only fires when the visible index RANGE changes, so
        // scrolling up inside one tall last message (index unchanged) never
        // updates atBottom. onDidScroll fires on every scroll frame — track the
        // true bottom edge here so the glue stops fighting the user.
        .onDidScroll(() => {
          this.refreshAtBottom();
          if (this.listTouchActive) {
            // A tap alone does not release the initial unread anchor. Only an
            // actual drag gives scroll ownership to the user.
            if (this.stayAtUnread) {
              this.stayAtUnread = false;
            }
            if (!this.listUserScrollActive) {
              this.listUserScrollActive = true;
            }
          }
          if (this.listUserScrollActive) {
            this.updateFloatDate(this.curStartIdx);
          }
        })
        .onScrollStop(() => {
          this.armPlaySlotSettle();
        })
        .onAreaChange((_old: Area, area: Area): void => {
          const y: number = area.globalPosition.y as number;
          const height: number = area.height as number;
          this.playSlots.setViewportCenter(y + height / 2);
        });
        if (this.visibleGroupCount === 0) {
          this.messageListStateLayer();
        } else if (this.timelineStateMode() !== '') {
          this.timelineStatePill();
        }
        // Jump-target highlight overlay (gentle double blink over the row a
        // reply/pinned/link jump just landed on). Coordinates come from
        // scroller.getItemRect, which is relative to the List — hence the Stack.
        if (this.flashShown) {
          Column()
            .width('100%').height(this.flashHeight)
            .backgroundColor('#4D67A0DC')
            .borderRadius(8)
            .opacity(this.flashAlpha)
            .position({ x: 0, y: this.flashTop })
            .hitTestBehavior(HitTestMode.None);
        }
        // Floating date chip at the top of the viewport — tracks the topmost
        // visible message while scrolling, fades away when scrolling stops.
        if (this.floatDate !== '') {
          Row() {
            Row() {
              Text(this.floatDate)
                .fontSize(12)
                .fontColor(COLOR_TEXT_PRIMARY)
                .fontWeight(FontWeight.Medium);
            }
            .height(28)
            .padding({ left: 12, right: 12 })
            .backgroundColor($r('app.color.surface'))
            .border({ width: 0.5, color: $r('app.color.divider') })
            .borderRadius(14)
            .shadow({ radius: 5, color: '#22000000', offsetX: 0, offsetY: 2 });
          }
          .width('100%')
          .justifyContent(FlexAlign.Center)
          .margin({ top: this.headerChromeH + 8 })
          .opacity(this.floatDateShown ? 1 : 0)
          .scale({ x: this.floatDateShown ? 1 : 0.9, y: this.floatDateShown ? 1 : 0.9 })
          .translate({ y: this.floatDateShown ? 0 : -5 })
          .animation({ duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 200), curve: Curve.EaseOut })
          .hitTestBehavior(HitTestMode.None);
        }
        Column() {
          if (this.membershipState === 'writable' && !this.showEmojiPanel && !this.replyKbVisible() &&
            (this.mentionItems.length > 0 || this.commandPanelActive())) {
            this.suggestionPanel();
          }
          if (this.membershipState === 'writable' && !this.showEmojiPanel &&
            this.mentionItems.length === 0 && !this.commandPanelActive() &&
            this.inlineResults.length > 0) {
            this.inlineResultsBar();
          }
          if (this.membershipState === 'writable' && !this.showEmojiPanel &&
            this.mentionItems.length === 0 && !this.commandPanelActive() &&
            this.inlineResults.length === 0 && this.stickerSuggestions.length > 0) {
            this.stickerSuggestionBar();
          }
          this.bottomDock();
        }
        .width('100%').height('100%')
        .justifyContent(FlexAlign.End)
        .hitTestBehavior(HitTestMode.None);

        // 顶部 chrome 放在最后 = 叠在最上层，消息从它下面穿过去。
        Column() {
          if (this.selecting) {
            this.selectionHeader();
          } else if (this.searchMode) {
            this.searchHeader();
          } else {
            this.header();
          }
          if (this.topCardShouldShow()) {
            this.topBanners();
          }
        }
        .width('100%')
        .onAreaChange((_old: Area, area: Area): void => {
          const h: number = area.height as number;
          if (Math.abs(h - this.headerChromeH) > 0.5) {
            this.headerChromeH = h;
          }
        });
        }
        .layoutWeight(1).width('100%')
        .alignContent(Alignment.TopStart)
        // RESIZE changes this viewport in step with the system keyboard. The
        // area callback runs after the new List height is known, so pinning
        // here keeps message and composer motion visually locked together.
        .onAreaChange((_old: Area, area: Area) => {
          const h: number = area.height as number;
          if (Math.abs(h - this.listViewportH) > 0.5) {
            this.listViewportH = h;
          }
          if (this.keyboardH > 0 && this.imeTailPinned) {
            this.syncTailOnImeFrame();
          }
        });
      }
      .width('100%').height('100%')
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .backgroundColor(Color.Transparent);

      // 贴纸飞出的残影。叠在最外层、不参与命中测试，纯视觉。
      if (this.stickerGhostPath !== '') {
        Image(this.stickerGhostPath)
          .width(STICKER_GHOST_SIDE).height(STICKER_GHOST_SIDE)
          .objectFit(ImageFit.Contain)
          .draggable(false)
          .position({
            x: this.stickerGhostX - STICKER_GHOST_SIDE / 2,
            y: this.stickerGhostY - STICKER_GHOST_SIDE / 2
          })
          .scale({
            x: this.stickerGhostFly ? 0.34 : 1,
            y: this.stickerGhostFly ? 0.34 : 1
          })
          .translate({ y: this.stickerGhostFly ? -170 : 0 })
          .opacity(this.stickerGhostFly ? 0 : 0.95)
          .animation({ duration: STICKER_FLY_MS, curve: Curve.FastOutSlowIn })
          .hitTestBehavior(HitTestMode.None);
      }

      // Emoji/sticker panel OVERLAYS the chat (not in the layout flow): the
      // message list keeps its height, so its scrollbar/FAB stay put, and the
      // open/close animation doesn't relayout the LazyForEach every frame.
      if (this.showEmojiPanel && this.membershipState === 'writable') {
        // Full-height wrapper only positions the panel above the input bar;
        // Transparent hit-testing lets taps outside the panel reach the list.
        Column() {
          Column() {
            if (this.panelContentReady) {
              EmojiPanel({
                tab: $emojiPanelTab,
                onPick: (e: string): void => { this.insertEmoji(e); },
                onPickCustomEmoji: (e: string, ceId: string): void => {
                  if (this.store !== null) {
                    this.atBottom = true;
                    this.store.sendCustomEmoji(e, ceId);
                    this.finishStickerSend('', 0, 0);
                  }
                },
                onPickSticker: (s: StickerItem, x: number, y: number): void => {
                  if (this.store !== null) {
                    this.atBottom = true;
                    this.store.sendSticker(s.fileId, s.width, s.height);
                    this.finishStickerSend(s.thumbPath, x, y);
                  }
                },
                onPickGif: (g: GifItem): void => {
                  if (this.store !== null) {
                    this.atBottom = true;
                    this.store.sendAnimation(g.fileId, g.width, g.height, g.duration);
                    this.finishStickerSend('', 0, 0);
                  }
                }
              });
            } else if (!this.emojiPanelClosing) {
              Column({ space: 8 }) {
                LoadingProgress().width(26).height(26).color(COLOR_PRIMARY);
                Text($r('app.string.cp_opening_panel')).fontSize(13).fontColor(COLOR_TEXT_SECONDARY);
              }
              .width('100%').height('100%')
              .justifyContent(FlexAlign.Center);
            }
          }
          .width('calc(100% - 16vp)').height(300)
          .backgroundColor($r('app.color.surface'))
          .border({ width: { top: 0.7 }, color: $r('app.color.divider') })
          .borderRadius(18)
          .clip(true)
          .shadow({ radius: 8, color: '#1A000000', offsetX: 0, offsetY: -2 })
          // 只做位移 + 淡出，不做 scale。缩放一个 300px 高、带 clip 和阴影的
          // 复杂子树，每帧都要重新栅格化 —— 系统 jank 事件实测这一下 80ms，
          // 而卸载内容本身是 0ms。位移和透明度是纯合成操作，不触发重栅格化。
          .transition(TransitionEffect.translate({ y: 18 })
            .combine(TransitionEffect.OPACITY)
            .animation({ duration: this.chatEffectDuration(KEY_POWER_EFFECT_MENU, 220), curve: Curve.EaseOut }));
        }
        .width('100%').height('100%')
        .justifyContent(FlexAlign.End).alignItems(HorizontalAlign.Center)
        .padding({ bottom: this.bottomChromeH + 6 })
        // None (not Transparent): the wrapper itself never hit-tests, so the
        // panel child blocks touches over its own area (Transparent leaked
        // panel taps through to the list, whose onTouch dismissed the panel),
        // while the area outside the panel still reaches the list/input bar.
        .hitTestBehavior(HitTestMode.None);
      }
      if (this.showReactionSheet) {
        ReactionSheet({
          show: this.showReactionSheet,
          messages: this.messages,
          targetId: this.reactionTargetId,
          chatId: this.chatId,
          pendingKey: this.reactionPendingKey,
          effectDuration: (key: string, ms: number): number => this.chatEffectDuration(key, ms),
          onPick: (reactionKey: string, chosen: boolean): void => {
            const targetId: number = this.reactionTargetId;
            this.closeReactionSheet();
            this.toggleReaction(targetId, reactionKey, chosen);
          }
        })
      }
      if (this.showForwardSheet) {
        ForwardSheet({
          show: this.showForwardSheet,
          messageIds: this.forwardMessageIds,
          sourceChatId: this.chatId,
          threadRootId: this.threadRootId,
          effectDuration: (key: string, ms: number): number => this.chatEffectDuration(key, ms),
          onSent: (): void => {
            this.forwardMessageIds = [];
            if (this.selecting) {
              this.exitSelect();
            }
          }
        })
      }
      if (this.showScheduledSheet) {
        ScheduledSheet({
          show: this.showScheduledSheet,
          chatId: this.chatId
        })
      }
      if (this.showPollSheet) {
        PollComposeSheet({
          onSubmit: (question: string, options: string[], isAnonymous: boolean,
            isQuiz: boolean, correctOptionId: number): void => {
            this.showPollSheet = false;
            if (this.store !== null) {
              this.atBottom = true;
              this.store.sendPoll(question, options, isAnonymous, isQuiz, correctOptionId);
            }
          },
          onClose: (): void => {
            this.showPollSheet = false;
          }
        });
      }
      if (this.showContactSheet) {
        ContactPickerSheet({
          onPick: (contact: PickedContact): void => {
            this.showContactSheet = false;
            if (this.store !== null) {
              this.atBottom = true;
              this.store.sendContact(
                contact.phone, contact.firstName, contact.lastName, contact.userId);
            }
          },
          onClose: (): void => {
            this.showContactSheet = false;
          }
        });
      }
      if (this.showVideoNoteRecorder) {
        VideoNoteRecorderView({
          onCaptured: (path: string, durationSec: number, length: number): void => {
            if (this.store !== null) {
              this.atBottom = true;
              this.store.sendVideoNote(path, durationSec, length);
            }
          },
          onClose: (): void => {
            this.showVideoNoteRecorder = false;
          }
        });
      }
      // The latest-message FAB belongs to the chat layer. Keeping it visible
      // while the media panel is open puts it above (and blocks) the GIF tab.
      if (!this.atBottom && !this.searchMode && !this.showEmojiPanel) {
        Column() {
          this.scrollFab();
        }
        .width('100%').height('100%')
        .justifyContent(FlexAlign.End).alignItems(HorizontalAlign.End)
        .padding({ right: 14, bottom: this.bottomChromeH + 8 })
        .hitTestBehavior(HitTestMode.Transparent);
      }

      // Fullscreen media viewer. The page owns which message is open and the
      // hero transition anchored to the tapped thumbnail; the overlay owns
      // zoom/pan, paging, the filmstrip and the chrome layer.
      if (this.viewerMsgId !== 0) {
        MediaViewerOverlay({
          viewerMsgId: this.viewerMsgId,
          chromeVisible: this.chromeVisible,
          videoLandscape: this.viewerVideoLandscape,
          messages: this.messages,
          groups: this.groups,
          initIdx: this.viewerInitIdx,
          initStartPositionMs: this.viewerStartPositionMs,
          tapX: this.tapX,
          tapY: this.tapY,
          store: this.store,
          chatTitle: this.title,
          nowSec: this.nowSec,
          effectDuration: (key: string, ms: number): number => this.chatEffectDuration(key, ms),
          isVideoEntry: (entry: MessageEntry): boolean => this.mediaEntryIsVideo(entry),
          onRequestClose: (): void => { this.closeViewer(); },
          onSaveMedia: (): void => { this.saveViewerMedia(); },
          onPositionChanged: (positionMs: number): void => { this.viewerPositionMs = positionMs; }
        })
      }
    }
    .width('100%').height('100%')
    .bindSheet($$this.translateSheetOpen, this.translateSheet(), {
      detents: [SheetSize.MEDIUM, SheetSize.LARGE],
      backgroundColor: $r('app.color.surface'),
      dragBar: true
    });
  }
}
