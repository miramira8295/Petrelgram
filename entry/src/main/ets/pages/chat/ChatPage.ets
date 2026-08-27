import { router, promptAction } from '@kit.ArkUI';
import { openDeleteMessagesDialog } from './DeleteMessagesDialog';
import { pasteboard } from '@kit.BasicServicesKit';
import { PollOptionInfo } from '../../util/formatMsgContent';
import { setScrollActive } from '../../util/scrollEffects';
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
import { holdPlayerJobs } from './WebmStickerView';
import { setChatTgsSuspended } from './TgsStickerView';
import { EmojiPanel } from './EmojiPanel';
import { StickerItem } from './StickerPicker';
import { GifItem } from './GifPicker';
import { getVoicePlayback } from '../../services/VoicePlayback';
import { openLocalFile } from '../../util/openLocalFile';
import { saveMediaToGallery, saveFileToLocal } from '../../util/mediaSaver';
import { getTdClient, getUserStore, getChatStore, getChatThemeStore } from '../../tdkit/Globals';
import { MessageStore, MediaSendItem } from '../../store/MessageStore';
import { MessageEntry, buildMessageEntry } from '../../store/MessageEntry';
import { ReuseIdLevel, rowReuseId } from '../../util/rowReuseId';
import {
  MIN_MESSAGE_ROW_HEIGHT_VP, capReuseBuckets, globalReusePoolAvailable,
  messageReuseHostCount, messageRowViewportRows, releaseMessageReuseHost,
  retainMessageReuseHost, reuseBucketMaxCount
} from '../../util/messageReusePool';
import { ReplyKeyboard, KeyboardBtn, KB_TEXT } from '../../store/ReplyKeyboard';
import { ChatEntry, computeInitials, isMutedFrom } from '../../store/ChatEntry';
import { ClearHistoryOption, clearHistoryOptions } from '../../store/ClearHistoryOptions';
import {
  MessageBubbleActions, MessageBubbleRenderData, ReusableMessageBubble
} from './ReusableMessageBubble';
import { PlaySlotRegistry } from './PlaySlotRegistry';
import { shouldCompete, slotKey, slotKeyMessageId } from './playSlot';
import { MediaViewerOverlay } from './MediaViewerOverlay';
import { ForwardSheet } from './ForwardSheet';
import { ScheduledSheet } from './ScheduledSheet';
import { ReactionSheet } from './ReactionSheet';
import { cacheDestPath, isVideoPath } from '../../util/mediaPick';
import {
  ChatBackgroundState, ChatBackgroundStore, emptyChatBackground
} from '../../store/ChatBackgroundStore';
import {
  chatHeaderPresentation, chatHeaderTitle, ChatHeaderPresentation
} from '../../util/chatHeaderPresentation';
import { MusicQueue } from '../../services/MusicQueue';
import { VoiceState } from '../../services/VoicePlayback';
import { setMediaViewerOrientation } from './LiveViewerUi';
import { actionMenuRow } from './ActionMenuRow';
import {
  AlbumGroupDataSource, appendBreaksAnchor, clampPrefetchRange, contentFingerprint,
  countDeferredFlips, PrefetchRange, prependBreaksAnchor, reuseUnchangedRows, sameRowArray
} from './AlbumGroupDataSource';
import { BasicPrefetcher, FrameCallback } from '@kit.ArkUI';
// UIUtils 本身从 API 12 起就有；这里用到的 getCustomComponentContext 是 26 起，
// 调用点在 capMessageReuseBuckets 的版本闸门之后。IReusePool 只是类型。
import { IReusePool, UIUtils } from '@kit.ArkUI';
import { ChatBackdrop } from './ChatBackdrop';
import { CHAT_HEADER_ACTION_SIZE, CHAT_HEADER_RADIUS, ChatHeader } from './ChatHeader';
import { TopBanners } from './TopBanners';
import { TranslateSheet } from './TranslateSheet';
import { SelectionHeader } from './SelectionHeader';
import { SearchBottomBar, SearchHeader } from './ChatSearchBars';
import { MessageListStateCard, TimelineStatePill } from './MessageListState';
import { EditStrip, ReplyStrip } from './ComposerStrip';
import { MediaStrip } from './MediaStrip';
import {
  PENDING_MEDIA_MAX, PendingMediaAppend, PendingMediaItem, appendPendingMedia,
  clearPendingMedia, hasPendingMedia, movePendingMedia, pendingMediaCanSend,
  removePendingMedia
} from '../../util/pendingMedia';
import { ComposerSendButton } from './ComposerSendButton';
import { ScrollFab } from './ScrollFab';
import { MembershipBar } from './MembershipBar';
import { BottomDrawerShell } from './BottomDrawerShell';
import { ReplyKeyboardPanel } from './ReplyKeyboardPanel';
import {
  LINK_COMMAND, LINK_COPY, LINK_HASHTAG, LINK_NONE, LINK_USER, LinkAction, linkActionOf
} from '../../util/messageLinkAction';
import { membershipLosesComposer, membershipStateOf } from '../../util/membershipState';
import { AT_BOTTOM_KEEP, AT_BOTTOM_YES, atBottomVerdict } from '../../util/atBottom';
import {
  PINNED_EMPTY, PINNED_IGNORE, PINNED_JUMP, PINNED_LATEST, PINNED_RETRY,
  PinnedTap, pinnedTapAction
} from '../../util/pinnedJump';
import {
  composerBottomGap as bottomGapOf, composerPlaceholder as placeholderOf,
  replyKeyboardVisible
} from '../../util/composerChrome';
import { replySnippetOf } from '../../util/replySnippet';
import {
  TL_NEWER_ERROR, TL_NONE, TL_OLDER_ERROR, TL_SYNC_ERROR,
  timelineStateMode, timelineStateText
} from '../../util/timelineState';
import {
  forwardableIds, pruneSelection, rowSelectable, rowSelected, toggleRow
} from '../../util/messageSelection';
import {
  TRANSLATE_DONE, TRANSLATE_LOADING, TranslateToggle,
  sheetStateOf, toggleTranslation, translationActive as isTranslationActive
} from '../../util/translationMode';
import { pinnedShownIndex } from '../../util/pinnedSegments';
import { SuggestionPanel, commandLabel } from './SuggestionPanel';
import {
  ComposerMode, cancelEdit, clearReply, draftToRestore, enterEdit, enterReply, idleComposer
} from '../../util/composerMode';
import {
  SLOT_ATTACH, SLOT_EMOJI, SLOT_NONE, SLOT_REPLY_KB, claimIfFree, closeAllSlots, closeSlot,
  openSlot, toggleSlot
} from '../../util/bottomSlot';
import {
  AnchorMerge, SEARCH_FETCH, SEARCH_JUMP, SearchStep, mergeAnchorHit, stepNewer, stepOlder
} from '../../util/searchPaging';
import { collapseAlbums, groupIndexOf, AlbumGroup } from '../../util/collapseAlbums';
import { publishMessageRowPresentations } from '../../util/messageRowPresentationChannel';
import {
  KEY_POWER_ACTIVE, KEY_POWER_CHAT_EFFECTS, KEY_POWER_EMOJI, KEY_POWER_EMOJI_REACTIONS,
  KEY_POWER_EFFECT_BACKGROUND, KEY_POWER_EFFECT_BLUR, KEY_POWER_EFFECT_MENU,
  KEY_POWER_EFFECT_REPLY, KEY_POWER_PARTICLES,
  KEY_POWER_SMOOTH_TRANSITIONS, KEY_POWER_AUTOPLAY_VIDEO,
  KEY_REDUCE_ANIM, KEY_SEND_BY_ENTER, KEY_TRANSLATE_CHATS, setTranslateOptedIn,
  translateOptedIn,
  KEY_AUTOPLAY_MUTED, powerAnimationDuration,
  powerFeatureEnabled, powerGroupAnimationDuration, autosaveEnabled,
  translateOptedOut, setTranslateOptedOut
} from '../../store/AppSettings';
import {
  getTranslationService, languageDisplayName, looksLikeTargetLanguage, resolveTranslateTarget,
  TRANSLATE_LANG_CODES
} from '../../services/TranslationService';
import {
  COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY, darkResourceMode, KEY_APP_DARK
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
  AvailableReactionSet, canonicalReactionEmoji, parseAvailableReactions, reactionDisplayLabel, reactionTypeOf, setDefaultReaction
} from '../../util/reactions';
import { openWebUrl } from '../../util/webBrowserNav';
import { TdObject, TdRequest, TdError } from '../../tdkit/TdTypes';
import {
  searchMentions, mentionOfUser, loadBotCommands, MentionItem, CommandItem
} from '../../store/InputSuggestions';
import { appendMention, mentionToken, mentionQueryOf } from '../../util/mentionDraft';
import { buildMentionEntities, NameMention } from '../../util/mentionEntities';
import { floatingLiveWindow } from './LiveFloatingWindow';
import { MUTE_LONG, setMute } from '../../store/ChatActions';
import { liveLocation, LiveLocationState } from '../../services/LiveLocationService';
import { plural, str } from '../../util/strings';
import {
  ReturnState, ReturnTarget, RETURN_JUMP, RETURN_NONE, RETURN_READ,
  advanceRead, dropReachedJumps, emptyReturnState, nextReturnTarget, popJump, pushJump,
  reachedLatest
} from '../../util/readingReturn';
import { LANGUAGE_EPOCH } from '../../util/appLanguage';
import { audioQueueApplies } from '../../util/audioQueueGate';
import {
  overlayBackdropBlur, overlayBlur, overlayGlassFill, overlayMaterial, MATERIAL_EPOCH
} from '../../util/overlayMaterial';
import { materialModifier } from '../../util/materialModifier';
import { BOT_START_COMMAND, composerSlotState } from '../../util/botStart';
import { getAdministrators, AdminRow } from '../../store/ChatAdminApi';
import { adminLabelOf } from '../../util/adminLabel';
import { clearSenderRoles, publishSenderRole, senderRoleKey } from '../../util/senderRoleChannel';
import { logChatNavFailure, navigateToChat } from '../../util/chatNav';
import { HdsNavDestination } from '@kit.UIDesignKit';
import { navigateToChatProfile, navigateToProfile } from '../../util/profileNav';
import { beginLinkNav, endLinkNav, endLinkNavIf } from '../../util/linkTapGuard';
import { attachActions } from '../../util/attachActions';
import { AttachPanel } from './AttachPanel';
import { InlineResultsBar, StickerSuggestion, StickerSuggestionBar } from './ComposerStrips';
import { copyPlainText } from '../../util/clipboard';
import { isRealClientJoinNotice } from '../../util/joinNotice';
import {
  ANCHOR_UNREAD, InitialAnchor, anchorLatchesBottom, initialAnchorOf
} from '../../util/initialAnchor';
import { isAtLiveTail, newestVisibleMessageId } from '../../util/readMarking';
import {
  MediaWindow, VisibleRange, mediaWindowRange, visibleRangeOrFallback
} from '../../util/visibleWindow';
import { openForwardOrigin } from '../../util/chatNavigation';
import { confirmStopLiveLocation, withLocationPermission } from '../../util/locationActions';
import { logE, logI, logW } from '../../util/log';
import { armedPageGate, canFirePageGate, firedPageGate, PageGate, rearmPageGate } from '../../util/pageGate';
import { rememberChatPosition, rememberedChatPosition } from '../../util/chatResume';
import { navigateToSearch } from '../../util/searchNav';
import { forwardDirect } from '../../store/ForwardDirect';
import { getActiveTdUserId } from '../../tdkit/Globals';
import {
  canRenderLightweightPlainText, formattedTextReuseShape,
  MessageBubbleReuseContext
} from '../../util/messageBubbleReuse';
import {
  CHAT_HEADER_BASE_HEIGHT, chatChromeHeight, ChatChromeGeometryInput
} from '../../util/ChatChromeGeometry';
import {
  initialMessagePlaceholderHeight, initialMessageViewportRows, nextInitialMessageRevealCount,
  stageInitialMessageGroups
} from '../../util/initialMessageStage';
import { APPEARANCE_EPOCH } from '../../util/appearance';
// ⚠️ 临时（P6 标定）：cachedCount 档位调试项。标定结束后按
// util/debugListPerf.ets 末尾的清单删除。
import { KEY_DEBUG_LIST_CACHED, LIST_CACHED_COUNT_DEFAULT } from '../../util/debugListPerf';

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

// cachedCount 的取值理由（原写死常量处的注释，值本身搬去了
// util/debugListPerf.ets 的 LIST_CACHED_COUNT_DEFAULT，仍然是 6）：
// 固定预建两行：不再用状态变量从 1 延迟涨到 4。后者会在进页面约 450ms 后让
// 整个可见消息区重跑 build，Insight 里对应两次约 25ms 的帧峰值。
// A short-message viewport commonly contains 10-16 rows. HarmonyOS long-list
// guidance recommends keeping roughly half a viewport ready; two rows were
// exhausted by a single fast 90 Hz fling in the 10:43 device trace. Keep this
// static so changing the value never invalidates every visible row.
// ⚠️ 临时（P6 标定）：档位现在可以在设置 → 日志与诊断里临时切成 4/8。没有人
// 动那个开关时行为与写死 6 的时期逐字节相同。
// 全局复用池按桶封顶的最小间隔。封顶本身只是遍历一个个位数长度的数组，但
// 每次给 maxCount 赋值都会让框架做一次异步清理，没必要在连续 fling 的每次
// 停手上都跑一遍。
const REUSE_CAP_MIN_INTERVAL_MS: number = 1000;
const PREPARED_MESSAGE_CACHE_LIMIT: number = 1024;

const CHAT_HEADER_NAV_GUARD_MS: number = 700;
const TOP_CARD_LOADING_DELAY_MS: number = 180;
const TOP_CARD_ACTION_GUARD_MS: number = 650;
// A delayed frame callback cannot be drained again inside the same VSync. On
// the measured 90 Hz device, 12 ms crosses one 11.1 ms frame boundary and lets
// the row admitted by the previous callback complete layout before the next.
const INITIAL_MESSAGE_RELEASE_DELAY_MS: number = 12;
// Do not flash a ready one-row timeline in the first instant of the destination
// push. Bottom landings now wait for a stable lower slice, so they need a much
// shorter floor than an unread anchor whose complete visible window is prepared.
const INITIAL_TIMELINE_PRESENT_MIN_MS: number = 80;
const INITIAL_BOTTOM_PRESENT_MIN_MS: number = 48;
// The data is already complete and anchored when these animations start. Only
// render transforms are staggered; no row is inserted or resized here.
const INITIAL_TIMELINE_ROW_FADE_MS: number = 90;
const INITIAL_TIMELINE_ROW_STAGGER_MS: number = 14;
const INITIAL_TIMELINE_REVEAL_ROW_LIMIT: number = 8;
// Reveal only after real rows cover the complete visible message viewport.
// Older offscreen rows may continue staging after the page is visible, but
// visible placeholder replacement must not trigger repeated height correction.
// HdsNavDestination.onShown is emitted near the beginning of a push, not when
// the spring has settled. This timer is only a watchdog for a resolved empty
// timeline; it must never reveal chrome while history/row staging is pending,
// otherwise a slow fully-read chat paints header/composer before its bubbles.
const INITIAL_MESSAGE_TRANSITION_SETTLE_MS: number = 640;

// Composer geometry. These three have to agree with the TextArea's own
// lineHeight/padding: the editor height is computed from them, and a mismatch
// clips the last line instead of scrolling to it.
// 系统键盘从请求到落定的大致时间。摁住播放器销毁队列用这个数——量到的
// 键盘弹出被拖到 1859ms，其中绝大部分是销毁占的主线程。
const KEYBOARD_SETTLE_MS: number = 700;
// 跳转落地后多久才允许"用户自己滚回最新"的判定重新生效。
const JUMP_LANDING_GRACE_MS: number = 900;

// Reuse-pool granularity for ReusableMessageBubble's reuseId. Provisional —
// to be measured and tuned in P2 Task 3; 'medium' is a placeholder, not a
// verified-best value.
const REUSE_ID_LEVEL: ReuseIdLevel = 'medium';

interface DiceChoice {
  emoji: string;
  label: ResourceStr;
}

interface PreparedMessageBubble {
  group: AlbumGroup;
  data: MessageBubbleRenderData;
}

interface InitialMessageStageTarget {
  anchorIndex: number;
  alignFromStart: boolean;
  availableRows: number;
}

type InitialMessageReleaseResult = 'released' | 'waiting' | 'finished';

// One-shot UI frame task shared by initial-message staging and the deferred
// composer mount. The caller uses postDelayedFrameCallback so callbacks queued
// by adjacent state notifications cannot drain into the same VSync.
class ChatPageFrameCallback extends FrameCallback {
  private task: () => void;

  constructor(task: () => void) {
    super();
    this.task = task;
  }

  onFrame(_frameTimeInNano: number): void {
    this.task();
  }
}

// 六个骰子表情。原先是 showActionMenu 的按钮上限刚好装得下，现在是 3×2 的格子。
const DICE_CHOICES: DiceChoice[] = [
  { emoji: '🎲', label: $r('app.string.cp_dice_die') },
  { emoji: '🎯', label: $r('app.string.cp_dice_darts') },
  { emoji: '🏀', label: $r('app.string.cp_dice_basketball') },
  { emoji: '⚽', label: $r('app.string.cp_dice_football') },
  { emoji: '🎳', label: $r('app.string.cp_dice_bowling') },
  { emoji: '🎰', label: $r('app.string.cp_dice_slots') }
];
const COMPOSER_LINE_H: number = 22;
const COMPOSER_EDITOR_PAD: number = 9;
const COMPOSER_MAX_LINES: number = 4;

// Emoji offered in the full reaction picker (opened from the long-press menu's
// chevron). Ordered roughly like the official client's reaction sheet.
// 路由表（router_map.json）的 buildFunction 指向这里。系统在跳转时动态加载
// 本模块并调用它，页面因此不再需要进 main_pages.json。
// V1 外壳组件：只做一件事——订阅 AppStorage，把 21 个全局单值透传给 V2 的
// ChatPage。
//
// 为什么需要它：@StorageProp / @StorageLink 是状态管理 V1 独有的装饰器，
// ChatPage 迁 @ComponentV2 之后不能再声明它们；而官方 FAQ《如何实现 V1、V2
// 版本之间父子组件的数据传递与共享》写明「AppStorage 在 V1 向 V2 传递的场景下，
// V2 版本的子组件不能自动同步更新，只能通过 AppStorage.get 手动获取」。
//
// 为什么不直接搬去 AppStorageV2：官方《AppStorageV2》「使用限制」两条都是硬的
// ——「AppStorage 与 AppStorageV2 之间的数据互不共享」、「不支持存储基本类型，
// 如 string、number、boolean」。这 21 个键全是 number/boolean，而且不是本页
// 私有的：全仓 @StorageProp/@StorageLink 共 513 处、分布在 100 个文件，写入方
// 主要在 AppSettings.ets / EntryAbility.ets / Globals.ets。只搬会话页这一份，
// 同一个键就会变成「V1 写、V2 读」，永远读到默认值，而且不报错。
//
// 合法性：《@ReusableV2装饰器：V2组件复用》的混用支持表「V1 普通组件 → V2 普通
// 组件：支持」。基本类型不需要 UIUtils.enableV2Compatibility 桥接——那个接口
// 「不支持非 object 类型」，对 number/boolean 调了也只是返回入参自身。
//
// 代价：某个 epoch 变一次，这一层就重跑一次 build()，把 21 个 @Param 重新交给
// ChatPage。@Param 只在值真的变化（===）时才向下传播刷新，所以代价是一次
// 参数比较，不是一次页面重建。
@Preview
@Component
struct ChatPageChrome {
  @StorageProp(APPEARANCE_EPOCH) appearanceEpoch: number = 0;
  @StorageProp(MATERIAL_EPOCH) materialEpoch: number = 0;
  @StorageProp(LANGUAGE_EPOCH) langEpoch: number = 0;
  @StorageProp(KEY_APP_DARK) appDark: boolean = false;
  @StorageProp('topSafeHeight') topSafe: number = 0;
  @StorageProp('bottomSafeHeight') bottomSafe: number = 0;
  @StorageProp('keyboardHeightVp') keyboardH: number = 0;
  @StorageProp('appIsForeground') appIsForeground: boolean = true;
  @StorageProp(KEY_SEND_BY_ENTER) sendByEnter: boolean = false;
  @StorageProp('screenWidthVp') screenW: number = 360;
  @StorageProp('screenHeightVp') screenH: number = 780;
  @StorageProp(KEY_POWER_ACTIVE) powerSaving: boolean = false;
  @StorageProp(KEY_POWER_CHAT_EFFECTS) powerChatEffects: boolean = true;
  @StorageProp(KEY_POWER_EFFECT_BACKGROUND) powerBackgroundEffect: boolean = false;
  @StorageProp(KEY_POWER_PARTICLES) powerParticles: boolean = true;
  @StorageProp(KEY_POWER_EMOJI) powerEmoji: boolean = true;
  @StorageProp(KEY_POWER_EMOJI_REACTIONS) powerEmojiReactions: boolean = true;
  @StorageProp(KEY_REDUCE_ANIM) reduceAnimations: boolean = false;
  @StorageProp(KEY_POWER_AUTOPLAY_VIDEO) autoplayVideo: boolean = true;
  @StorageProp(KEY_AUTOPLAY_MUTED) autoplayMuted: boolean = true;
  @StorageProp(KEY_TRANSLATE_CHATS) translateChatsEnabled: boolean = false;
  // ⚠️ 临时（P6 标定）：cachedCount 档位。它走这一层而不是 ChatPage 直接读
  // AppStorage，是因为「立即生效」靠的正是这条 V1→V2 的透传链：@StorageProp
  // 观测到键变化 → 本层重跑 build() → @Param 值变了 → ChatPage 里依赖它的
  // .cachedCount() 重新求值。ChatPage 自己 AppStorage.get 是读不到变化的。
  @StorageProp(KEY_DEBUG_LIST_CACHED) listCachedCount: number = LIST_CACHED_COUNT_DEFAULT;

  build() {
    ChatPage({
      appearanceEpoch: this.appearanceEpoch,
      materialEpoch: this.materialEpoch,
      langEpoch: this.langEpoch,
      appDark: this.appDark,
      topSafe: this.topSafe,
      bottomSafe: this.bottomSafe,
      keyboardH: this.keyboardH,
      appIsForeground: this.appIsForeground,
      sendByEnter: this.sendByEnter,
      screenW: this.screenW,
      screenH: this.screenH,
      powerSaving: this.powerSaving,
      powerChatEffects: this.powerChatEffects,
      powerBackgroundEffect: this.powerBackgroundEffect,
      powerParticles: this.powerParticles,
      powerEmoji: this.powerEmoji,
      powerEmojiReactions: this.powerEmojiReactions,
      reduceAnimations: this.reduceAnimations,
      autoplayVideo: this.autoplayVideo,
      autoplayMuted: this.autoplayMuted,
      translateChatsEnabled: this.translateChatsEnabled,
      listCachedCount: this.listCachedCount
    });
  }
}

// 消息行外壳的**全局复用池宿主**（API 26 起）。
//
// 它只做一件事：在 ChatPageChrome 之上多一层，把 reusePool / poolAccepts 挂
// 出去。官方《全局复用：集中化的组件回收与复用》——复用组件创建或销毁时，
// 框架「向上遍历组件树」找接纳该类型的全局池；找不到就退回父组件的默认池。
// 所以宿主只需要是 ReusableMessageBubble 的**任一祖先**，不必是它的父组件，
// 也不必知道列表长什么样。
//
// ── 为什么必须是单独一层，而不是把参数写在 ChatPageChrome 或 ChatPage 上 ──
//
// reusePool / poolAccepts 是**装饰器参数**，编译期就定死，没有任何运行时开关。
// 而这个能力从 API 26 才有，本仓 compatibleSdkVersion 是 6.0.0(20)。要做成
// 双路径，唯一的办法是让「挂了池的组件」和「没挂池的组件」是两个不同的类，
// 在运行时按设备版本二选一地**实例化**——见下面的 ChatPageBuilder。
//
// 低版本上这个 struct 只是一个从不被 new 出来的类：ChatPageBuilder 那条 if
// 永远走 else，池配置一次也不会被触碰，行为与 P4 完全一致（回退到默认复用池）。
//
// ── 为什么是 'shared' 而不是 'perInstance' ──
//
// 本应用的聊天详情页**可以同时存在多个实例**：
//   - 平板分栏（docs 2026-08-21-tablet-split-view-design）左右两栏各一页；
//   - Navigation 栈里从搜索结果进会话、再返回，栈上会先后压着两份；
//   - 会话 → 资料页 → 共同群组 → 另一个会话，栈里两份会话页同时活着。
// perInstance 的池「生命周期与其拥有组件实例相同」——上面每一种情况都是
// 「关掉一栏/弹一层，那一份池连同里面所有回收实例一起销毁」，而下一次打开
// 会话只能从零重建。shared 则是「只要还有任意一个宿主实例活着，池就活着」，
// 分栏切会话、返回再进，都能从池里取。
//
// 官方两处也都指向 shared：能力对比表「shared 模式允许拥有组件类的所有实例
// 共享单个池」，所有权模式一节直接写「建议开发者配置 shared 所有权。这样可以
// 获得更好的复用率和更低的内存占用」。
//
// shared 的代价官方也点了名：「只要拥有组件类的任何实例存在，池就会持续存在
// ……回收的组件可能会累积。使用 maxCount 来控制内存使用」——这正是 ChatPage
// 里 capMessageReuseBuckets() 存在的理由。
//
// freezeWhenInactive 必须显式给（官方使用限制：「配置 reusePool 和 poolAccepts
// 启用全局复用的同时，需要额外配置 freezeWhenInactive 参数」）。给 false 是
// 因为 ChatPageChrome 现在就是不冻结的（@Component 不写这个参数即为 false），
// 这一层不该顺手改变冻结语义。
// ── preRender 为什么没有开：它和首屏分级揭示是打架的 ────────────────────
//
// 全局池的第三项能力是 IReusePool.preRender(builder, times)：调度**空闲任务**
// 提前把复用组件建好放进池子，「加快初始渲染速度」。本页已经有一套解决首屏的
// 机制——首屏分级揭示（initialMessageStage：进页面先只放 1 行真身、其余是估高
// 占位，之后每次 release 只放行 1 行）。两者都在解决首屏，所以必须挑一个，
// 不能两个都开着还不说。
//
// **结论：保留分级揭示，不开 preRender。** 三条理由，从硬到软：
//
// 1. 同一个窗口、同一条线程，而且抢的正是对方赖以成立的那点空隙。
//    分级揭示的整个机制就是「每个 VSync 只允许建一行」这条硬上限——
//    nextInitialMessageRevealCount 的注释记着为什么是 1 而不是 3：一对含贴纸的
//    行能吃掉 26~28ms，六行挤进一次布局是 65ms。而 preRender 是**空闲任务**，
//    它跑的就是每帧建完那一行之后剩下的那段空闲。在首屏窗口里开 preRender，
//    等于一边限流一边从旁路灌水，被拖长的恰好是分级揭示要保护的那几帧。
//
// 2. 首屏那一刻**不知道该预建哪个桶**。全局池是按 reuseId 分区存放的，
//    REUSE_ID_LEVEL = 'medium' 之下 rowReuseId 是一个 12 维的字符串，完全由
//    行自己的数据算出来。而 preRender 必须在数据到达之前调用才谈得上「提前」
//    ——那时一行消息都还没有，猜错的桶里那个实例不会被任何一行取走，只是白建
//    一次、再白占一份内存。
//
// 3. preRender 吃的是 WrappedBuilder<[]>（零参 @Builder），意味着要在里面凭空
//    造一个 AlbumGroup / MessageEntry 喂给 ReusableMessageBubble。而这棵子树
//    挂载时是有副作用的：ReusableMessageBubble.aboutToAppear 会按
//    (chatId, rowId) 去 messageRowPresentationChannel 订阅，更深的 MessageBubble
//    会按内容发起缩略图/媒体的取数。拿一条**不存在的消息**去跑这些，副作用是
//    真的会发出去的。
//
// 而 preRender 本来想给的那份「打开会话时池子已经是热的」，shared 池自己就给了：
// 只要还有任意一个宿主实例活着，上一个会话回收的行就还在池子里，下一个会话
// 直接取。这是不用伪造任何数据、也不占用首屏那段线程的同一份收益。
//
// 什么时候可以回头再看这条：如果上机数据显示首屏的瓶颈不在**建树**而在别处，
// 或者分级揭示被证明可以撤掉，那时 preRender 才有位置——调用点是本组件的
// aboutToAppear（官方示例就在那里），拿 UIUtils.getCustomComponentContext(this)
// .getReusePool() 取池。在那之前，这里刻意什么都不做。
@ComponentV2({
  reusePool: 'shared',
  poolAccepts: [ReusableMessageBubble],
  freezeWhenInactive: false
})
struct ChatPagePoolHost {
  build() {
    ChatPageChrome();
  }
}

@Builder
export function ChatPageBuilder(): void {
  // 双路径。形状照 util/overlayMaterial.ets：判定是一个纯函数吃设备版本，
  // 调用点只问「赢了没有」。
  //
  // 低版本这一支与 P4 逐字节相同：ChatPageChrome 直接上，
  // ReusableMessageBubble 用父组件的默认复用池，rowReuseId 分档照旧生效。
  if (globalReusePoolAvailable()) {
    ChatPagePoolHost();
  } else {
    ChatPageChrome();
  }
}

@ComponentV2
export struct ChatPage {
  @Require @Param appearanceEpoch: number = 0;
  // 强调色是 theme 里的活绑定，读一次 epoch 让 ArkUI 记下依赖，用户改色后即时重绘。
  private accent(): ResourceColor {
    return this.appearanceEpoch < 0 ? Color.Transparent : COLOR_PRIMARY;
  }

  // 材质档位（厚度/光感）改变时重绘。overlayMaterial 是 util，订阅不了
  // AppStorage，只能由调用方订阅，同 LANGUAGE_EPOCH 的做法。
  @Require @Param materialEpoch: number = 0;
  // @Monitor('langEpoch') hangs off this (see onLanguageEpochChanged), because
  // the row key below embeds this value: bumping it renames every row, and the
  // data source has to be told or LazyForEach keeps a key table that no longer
  // matches anything.
  @Require @Param langEpoch: number = 0;
  // 深浅色切换后要重新解析背景。壁纸本身是**按模式选的**（TDLib 的
  // for_dark_theme），而 ChatBackgroundStore 只在 open() 时解析过那一次，
  // 会话开着的时候切换模式没人再跑一遍，壁纸就停在旧模式那张（issue #57）。
  //
  // ChatBackdrop 也订阅了 KEY_APP_DARK，但它只管图案浓度和深色遮罩，换不了
  // 壁纸本身——所以那一份订阅顶不了这一份。
  @Require @Param appDark: boolean = false;
  @Require @Param topSafe: number = 0;
  @Require @Param bottomSafe: number = 0;  // ✅ 新增
  @Require @Param keyboardH: number = 0;
  @Require @Param appIsForeground: boolean = true;
  // ⚠️ 临时（P6 标定）：List 的 cachedCount 档位，由 ChatPageChrome 透传。
  // 不是 @Require —— 少数直接 new ChatPage 的调用点（预览）没有它时用默认档。
  @Param listCachedCount: number = LIST_CACHED_COUNT_DEFAULT;
  @Local messages: MessageEntry[] = [];
  @Local messageLoadState: string = 'loading'; // loading | ready | error
  @Local messageLoadError: string = '';
  @Local olderLoadState: string = 'idle'; // idle | loading | error | end
  @Local newerLoadState: string = 'idle'; // idle | loading | error | end
  // **完整快照**的行数，不是当前渲染的行数——首屏分级渲染期间 groups 里坐着
  // 占位副本，长度一样，所以两者此刻仍然相等；将来若有别的分级形状，这个计数
  // 要跟着"用户最终会看到多少行"走。它驱动的是空/加载中的时间线提示。
  @Local visibleGroupCount: number = 0;
  // 消息列表的**唯一真相**。P4 之前它只是 LazyForEach 数据源的一份镜像，只用来
  // 做下标查找；现在 Repeat 直接渲染它，每次发布整体赋值（见 publishGroupsNow）。
  // @Local（而不是普通字段）有两个理由：Repeat 懒加载必须配状态管理 V2 才能观测
  // 到数组变化；MediaViewerOverlay 的 @Param 也只跟随本身是状态变量的源。
  @Local groups: AlbumGroup[] = [];
  // 只剩图片预取源，不再是列表的数据源（见 AlbumGroupDataSource 文件头）。
  private groupsData: AlbumGroupDataSource = new AlbumGroupDataSource();
  // 强制整表重建用的纪元，进 rowKeyOf。Repeat 没有 LazyForEach 的 reload()——
  // 让每一行的 key 都改变就是它的等价物（官方：键值变化会触发页面刷新）。
  // 两个调用点：语言纪元变化、从后台回来的重新对齐。见 rebuildAllRows()。
  private listRebuildEpoch: number = 0;

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
    `message_group_${g.head.rowId}_${g.rowMemberIds.join('_')}` +
    `_${contentFingerprint(g.key)}_${this.langEpoch}_${this.listRebuildEpoch}`;

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
  private hiddenSinceMs: number = 0;
  // 应用整个进过后台（熄屏、回桌面），而不只是本页被应用内的另一页盖住。
  //
  // hiddenListDirty 只认"隐藏期间数据变过"。但实测下来更常见的是另一路：
  // 熄屏放置一两分钟，数据一个字没变（groups/ds 前后相等、dirty=false），
  // 回来照样错乱——窗口在后台被系统回收，节点树重建时撞上框架里那份陈旧的
  // key→node 表，于是最新几行是新建的、正确，上面那些行拿到别人的内容。
  //
  // 用"进没进过后台"而不是"隐藏了多少毫秒"：熄屏/回桌面会置位，应用内跳
  // 查看器、资料页不会——后者本来就没问题，不必为它们白付一次 RELOAD。
  private appWentBackground: boolean = false;
  // 隐藏那一刻"屏幕最上面那条消息是哪条、它在哪个高度"。
  //
  // 必须在隐藏时就记：恢复时再拿 curStartIdx 去索引数据集，隐藏期间若发生过
  // prepend，这个下标已经指向别的消息了。
  private hiddenAnchorId: number = 0;
  private hiddenAnchorY: number = 0;

  // 发布一份新的行快照。**唯一**给 this.groups 赋值的地方（rebuildAllRows 除外）。
  //
  // reuseUnchangedRows 是这里唯一的"聪明"步骤，理由写在它自己的注释里：
  // collapseAlbums 每次都产出全新对象，而 Repeat 按 item 引用判断要不要刷新，
  // 不还原没变过的行就等于每次发布都刷新整个可见窗口。
  private publishGroupsNow(groups: AlbumGroup[]): void {
    const next: AlbumGroup[] = reuseUnchangedRows(this.groups, groups);
    // [BlankRow] 探针，说明与删除清单见 AlbumGroupDataSource.countDeferredFlips
    // 的注释。**只在首屏分级揭示期间统计**：
    //   · countDeferredFlips 要建两个 Map、扫完整个行数组（长会话 494 行），
    //     而 publishGroupsNow 是这条性能分支唯一的热路径，不该为一个诊断
    //     在每次发布上都付这笔钱；
    //   · 占位↔真身的翻转**只可能**发生在分级揭示期间（initialDeferred 由
    //     stageInitialMessageGroups 打上、由揭示逐行摘掉），揭示结束之后这个
    //     计数恒为 0，跑它纯属白跑。
    // 级别是 logI 不是 logW：flips > 0 是首屏的**正常态**，而 logW 会进用户
    // 可导出/上传的诊断日志环（util/log.ets 的 push），普通用户每开一次会话
    // 写一条 warning 是误导。
    if (this.initialMessageStageActive) {
      const flips: number = countDeferredFlips(this.groups, next);
      if (flips > 0) {
        logI(`[BlankRow] repeat flips=${flips} prev=${this.groups.length} next=${next.length}`);
      }
    }
    const changed: boolean = !sameRowArray(this.groups, next);
    // 全等的一次发布不换数组引用：@Local 的通知是按引用发的，换一个逐项相同
    // 的新数组照样通知 ⇒ Repeat 照样跑一遍 diff。changed 本来就算好了，用上。
    if (changed) {
      this.groups = next;
    }
    // ⚠️ 预取源拿的是 **groups（原始那份）**，不是 next（合并那份）——两者
    // 必须不同，这不是笔误。
    //
    // photoPaths / head.photoPath **刻意不进行 key**（collapseAlbums.ets 里
    // mutableSig 只带 photoFileId），因为缩略图落地要走 mediaThumbChannel 旁路
    // 直达气泡，不该拖着整行重建。代价是：缩略图/原图落地那一次发布里行 key
    // 一个字没变 ⇒ sameRenderSnapshot 为真 ⇒ reuseUnchangedRows 还回**上一份
    // 快照的对象** ⇒ 那一行的 photoPath 在 next 里**永远停在 ''**。
    //
    // 给 Repeat 用的 this.groups 必须是 next（对象身份不变才不会白刷新一整屏），
    // 但 AlbumGroupDataSource.imageRequestFor 是按 head.photoPath 决定预不预取的：
    // 喂它 next，它对这些行 `return null`，BasicPrefetcher 一次都不会预取——
    // 预取整条静默失效。所以数据面喂原始那份，UI 面喂合并那份。
    //
    // 这一行**在 changed 之外**，故意的：合并那份逐项相同（changed === false）
    // 恰恰是「只有旁路字段变了」的那次发布，而那正是预取源唯一需要的更新。
    this.groupsData.setRows(groups);
    if (!this.pageVisible && changed) {
      this.hiddenListDirty = true;
    }
  }

  // 让 Repeat 整表重建：每一行的 key 都换掉。
  //
  // LazyForEach 时代这是 AlbumGroupDataSource.reload()（一条 RELOAD 通知）。
  // Repeat 没有对应的命令式接口，但官方写明「键值变化或数据变化均会触发页面
  // 刷新」，所以把纪元推进一格、再换一个新数组交出去，效果等价：所有 key 都变
  // 成新 key ⇒ 全部删旧插新。行对象本身原样复用，内容一个字都没动。
  private rebuildAllRows(): void {
    this.listRebuildEpoch++;
    this.groups = this.groups.slice();
    // 这里**不碰** groupsData：它持有的是上一次发布的原始快照（见
    // publishGroupsNow 里那段注释），而 this.groups 是合并快照——photoPath 等
    // 旁路字段在它里面是陈旧的。整表重建只改 key 和数组身份、不改任何一行的
    // 内容，长度也不变，所以预取源保持指向那份更新的数据才是对的。
  }

  private syncChatTgsGate(): void {
    setChatTgsSuspended(!this.pageVisible || this.initialMessageStageActive ||
      this.chatTgsScrollActive || this.chatTgsStageSettling);
  }

  private pauseChatTgsForScroll(): void {
    this.chatTgsScrollActive = true;
    this.syncChatTgsGate();
  }

  private scheduleChatTgsResume(delayMs: number = 140): void {
    if (this.chatTgsResumeTimer !== -1) {
      clearTimeout(this.chatTgsResumeTimer);
    }
    this.chatTgsStageSettling = true;
    this.syncChatTgsGate();
    this.chatTgsResumeTimer = setTimeout((): void => {
      this.chatTgsResumeTimer = -1;
      this.chatTgsStageSettling = false;
      this.syncChatTgsGate();
    }, delayMs);
  }

  private resumeChatTgsAfterScroll(): void {
    this.chatTgsScrollActive = false;
    this.scheduleChatTgsResume();
  }

  // The normal publication gate also invalidates an unfinished initial stage.
  private publishGroups(groups: AlbumGroup[]): void {
    const wasStaging: boolean = this.initialMessageStageActive;
    this.initialMessageStageSeq++;
    this.initialMessageStageActive = false;
    this.initialMessagePendingGroups = null;
    this.initialMessageRevealCount = 0;
    this.initialMessageStageScheduledSeq = 0;
    if (wasStaging) {
      this.scheduleChatTgsResume();
    }
    this.publishGroupsNow(groups);
  }

  // MessageStore can publish another ready snapshot while the initial rows are
  // still being revealed (reply/photo metadata often arrives immediately).
  // Keep the newest snapshot for the next batch instead of cancelling staging
  // and putting the complete list back into the very next VSync.
  private publishMessageGroups(groups: AlbumGroup[]): void {
    if (this.initialMessageStageActive) {
      this.initialMessagePendingGroups = groups;
      this.postInitialMessageFrame(this.initialMessageStageSeq);
      return;
    }
    this.publishGroups(groups);
  }

  private initialMessageStageTarget(groups: AlbumGroup[]): InitialMessageStageTarget {
    const firstUnreadId: number = this.store !== null ? this.store.getFirstUnreadId() : 0;
    const anchor: InitialAnchor = initialAnchorOf(
      firstUnreadId,
      firstUnreadId > 0 ? groupIndexOf(groups, firstUnreadId) : -1,
      (index: number): number => groups[index].head.id
    );
    const alignFromStart: boolean = anchor.kind === ANCHOR_UNREAD;
    const anchorIndex: number = alignFromStart ? anchor.index : groups.length - 1;
    const availableRows: number = alignFromStart
      ? Math.max(0, groups.length - anchorIndex) : Math.max(0, anchorIndex + 1);
    return { anchorIndex, alignFromStart, availableRows };
  }

  private initialTimelinePresentRows(groups: AlbumGroup[],
    target: InitialMessageStageTarget): number {
    // contentStartOffset/contentEndOffset define the real message viewport.
    // Both unread and bottom landings prepare that full anchored window before
    // reveal so every row that can affect the first visible frame is stable.
    const viewportHeight: number = Math.max(
      180,
      this.screenH - this.headerChromeHeight() - this.bottomChromeH + 32
    );
    const unreadId: number = this.firstUnreadId > 0
      ? this.firstUnreadId : (this.store !== null ? this.store.getFirstUnreadId() : 0);
    return initialMessageViewportRows(
      groups,
      target.anchorIndex,
      target.alignFromStart,
      this.screenW,
      viewportHeight,
      unreadId
    );
  }

  private finishInitialMessageStage(groups: AlbumGroup[]): void {
    this.publishGroupsNow(groups);
    this.initialMessageStageActive = false;
    this.initialMessagePendingGroups = null;
    this.initialMessageRevealCount = 0;
    this.initialMessageStageScheduledSeq = 0;
    // Keep Lottie startup out of the final placeholder replacement frame.
    this.scheduleChatTgsResume();
    // The timeline stays masked until this full snapshot has been laid out and
    // the final id-based anchor has been applied. Never issue another delayed
    // landing after the mask is gone: that was the visible second jump.
    this.initialTimelineReadyToPresent = true;
    this.scheduleInitialTimelinePresentation();
    // Do not put the editor's stylus bridge into the final message-row frame.
    // scheduleComposerEditorMount adds one more real VSync boundary.
    this.scheduleComposerEditorMount();
  }

  private finishInitialMessageStageForInteraction(): void {
    // Normally the viewport-sized stage finishes before the mask is removed.
    // A bounded initial-history fill can deliberately keep it waiting, though;
    // once the user takes ownership of the visible list, never let that
    // background scheduler compete with their first drag.
    if (!this.initialMessageStageActive || this.initialTimelineMasked) {
      return;
    }
    const groups: AlbumGroup[] = this.initialMessagePendingGroups ?? this.groups;
    this.initialMessageStageSeq++;
    this.finishInitialMessageStage(groups);
  }

  private applyInitialUnreadLanding(seq: number): void {
    if (seq !== this.initialUnreadLayoutSeq || !this.didInitialScroll ||
      !this.stayAtUnread || this.firstUnreadId <= 0) {
      return;
    }
    // Recompute from the latest full snapshot. Initial backfill can prepend
    // rows between the first command and this layout-confirmation pass.
    const index: number = groupIndexOf(this.groups, this.firstUnreadId);
    if (index < 0) {
      return;
    }
    this.scroller.scrollToIndex(index, false, ScrollAlign.START);
  }

  private scheduleInitialUnreadLanding(delayMs: number = 80): void {
    if (!this.didInitialScroll || !this.stayAtUnread || this.firstUnreadId <= 0) {
      return;
    }
    const seq: number = this.initialUnreadLayoutSeq;
    setTimeout((): void => {
      this.applyInitialUnreadLanding(seq);
    }, delayMs);
  }

  private beginInitialUnreadLanding(): void {
    const seq: number = ++this.initialUnreadLayoutSeq;
    // Keep the immediate path for an already-laid-out list, then confirm after
    // ArkUI has consumed the newly published LazyForEach operations.
    this.applyInitialUnreadLanding(seq);
    this.scheduleInitialUnreadLanding();
  }

  private settleInitialTimelineAnchor(): void {
    if (!this.didInitialScroll || this.groups.length === 0) {
      return;
    }
    if (this.stayAtUnread && this.firstUnreadId > 0) {
      const index: number = groupIndexOf(this.groups, this.firstUnreadId);
      if (index >= 0) {
        this.scroller.scrollToIndex(index, false, ScrollAlign.START);
      }
      return;
    }
    this.scroller.scrollToIndex(this.groups.length - 1, false, ScrollAlign.END);
  }

  private scheduleInitialTimelinePresentation(): void {
    if (!this.initialTimelineMasked || !this.initialTimelineReadyToPresent ||
      this.initialTimelinePresentationScheduledSeq !== 0) {
      return;
    }
    const seq: number = ++this.initialTimelinePresentationSeq;
    this.initialTimelinePresentationScheduledSeq = seq;
    const delayMs: number = Math.max(0, this.initialTimelineEarliestAt - Date.now());
    this.getUIContext().postDelayedFrameCallback(new ChatPageFrameCallback((): void => {
      if (seq !== this.initialTimelinePresentationSeq || !this.pageVisible ||
        !this.initialTimelineMasked || !this.initialTimelineReadyToPresent) {
        if (this.initialTimelinePresentationScheduledSeq === seq) {
          this.initialTimelinePresentationScheduledSeq = 0;
        }
        return;
      }
      // First frame consumes the scroll command while the list is still
      // invisible. The next frame confirms against final row heights and only
      // then removes the mask, so no intermediate position can be painted.
      // Keep the scheduled marker locked across BOTH frames. Clearing it here
      // let the next one-row staging publication start a new presentation and
      // invalidate this second frame; a 101-row bottom timeline therefore
      // restarted the landing 99 times and stayed blank for about two seconds.
      this.settleInitialTimelineAnchor();
      this.getUIContext().postDelayedFrameCallback(new ChatPageFrameCallback((): void => {
        if (seq !== this.initialTimelinePresentationSeq || !this.pageVisible ||
          !this.initialTimelineMasked || !this.initialTimelineReadyToPresent) {
          if (this.initialTimelinePresentationScheduledSeq === seq) {
            this.initialTimelinePresentationScheduledSeq = 0;
          }
          return;
        }
        this.settleInitialTimelineAnchor();
        // Reveal the complete chat surface as one visual event. Header and
        // composer start their fade in the same frame as the first real bubble;
        // the remaining bubbles keep their per-row stagger below.
        this.cancelInitialMessageTransitionSettle();
        this.initialMessageTransitionSettled = true;
        this.initialTimelineMasked = false;
        if (this.initialTimelinePresentationScheduledSeq === seq) {
          this.initialTimelinePresentationScheduledSeq = 0;
        }
      }), INITIAL_MESSAGE_RELEASE_DELAY_MS);
    }), delayMs);
  }

  private releaseNextInitialMessageBatch(stageSeq: number): InitialMessageReleaseResult {
    if (stageSeq !== this.initialMessageStageSeq || !this.initialMessageStageActive) {
      return 'finished';
    }
    // A short first TDLib page immediately starts a bounded older-page fill.
    // Do not reveal against that moving snapshot: the unread/bottom anchor can
    // move when the prepend arrives, turning a nominal one-row admission into
    // several MessageBubble builds in one layout. The 11:04 device trace caught
    // exactly that shape (six bubbles and a 48.7 ms frame just after the push).
    // The final onHistory notification calls publishMessageGroups(), which
    // posts this callback again once isInitialFillPending() becomes false.
    const groups: AlbumGroup[] = this.initialMessagePendingGroups ?? this.groups;
    const target: InitialMessageStageTarget = this.initialMessageStageTarget(groups);
    const fillPending: boolean = this.store !== null && this.store.isInitialFillPending();
    if (fillPending && target.alignFromStart) {
      return 'waiting';
    }
    // The visible landing window is already stable. While a bounded history
    // fill is still moving the snapshot, keep the current geometry and wait
    // for its final publication instead of proactively materializing every
    // off-screen row. When the fill completes, publish the real snapshot once;
    // LazyForEach then builds only its visible/cache window.
    if (this.initialTimelineReadyToPresent) {
      if (fillPending) {
        return 'waiting';
      }
      this.finishInitialMessageStage(groups);
      return 'finished';
    }
    const nextRevealCount: number = nextInitialMessageRevealCount(
      this.initialMessageRevealCount,
      target.availableRows
    );
    if (nextRevealCount <= this.initialMessageRevealCount) {
      // A newly visited chat can publish a one-row `latest` page and then chain
      // one or more `older` requests. Keep admission open while that bounded
      // chain is in flight; its next snapshot restarts the frame scheduler via
      // publishMessageGroups instead of dumping every added row at once.
      if (this.store !== null && this.store.isInitialFillPending()) {
        return 'waiting';
      }
      // Unread anchoring can leave older, off-screen rows deferred even after
      // every row below the unread marker is real. Publish those in one final
      // frame; bottom anchoring normally completes in the branch below.
      this.finishInitialMessageStage(groups);
      return 'finished';
    }

    const staged: AlbumGroup[] = stageInitialMessageGroups(
      groups,
      target.anchorIndex,
      target.alignFromStart,
      nextRevealCount
    );
    this.initialMessageRevealCount = nextRevealCount;
    this.publishGroupsNow(staged);
    const presentRows: number = Math.min(
      this.initialTimelinePresentRows(groups, target), target.availableRows);
    // A short page may still be growing through the bounded initial fill. Do
    // not reveal a lone bottom row and then let older rows visibly climb upward.
    // The presentation target above is a stable lower slice for bottom landings
    // and the complete anchored window for unread landings.
    if (!this.initialTimelineReadyToPresent && nextRevealCount >= presentRows &&
      (!fillPending || presentRows > 0)) {
      this.initialTimelineReadyToPresent = true;
      this.scheduleInitialTimelinePresentation();
      if (!fillPending) {
        this.finishInitialMessageStage(groups);
        return 'finished';
      }
      // Do not keep walking the off-screen history one row per VSync after the
      // complete landing window is ready. A later store publication restarts
      // this callback when the bounded initial fill settles.
      return 'waiting';
    }
    if (staged === groups) {
      if (fillPending) {
        // The rows currently available are real, but a short-page backfill is
        // still running. Stay active and let that next snapshot extend the
        // same staged dataset.
        this.initialMessagePendingGroups = groups;
        return 'waiting';
      }
      this.finishInitialMessageStage(groups);
      return 'finished';
    }
    return 'released';
  }

  private postInitialMessageFrame(stageSeq: number): void {
    if (this.initialMessageStageScheduledSeq === stageSeq) {
      return;
    }
    this.initialMessageStageScheduledSeq = stageSeq;
    this.getUIContext().postDelayedFrameCallback(new ChatPageFrameCallback((): void => {
      if (this.initialMessageStageScheduledSeq === stageSeq) {
        this.initialMessageStageScheduledSeq = 0;
      }
      if (stageSeq !== this.initialMessageStageSeq || !this.initialMessageStageActive) {
        return;
      }
      const result: InitialMessageReleaseResult = this.releaseNextInitialMessageBatch(stageSeq);
      if (result === 'released') {
        this.postInitialMessageFrame(stageSeq);
      }
    }), INITIAL_MESSAGE_RELEASE_DELAY_MS);
  }

  private publishInitialMessageGroups(groups: AlbumGroup[]): void {
    const target: InitialMessageStageTarget = this.initialMessageStageTarget(groups);
    // Publish a placeholder-only list first. The initial MessageStore snapshot
    // also changes title/load/list state and makes ChatPage rerender as a whole;
    // the frame trace measured 8 ms in that rerender before message layout even
    // began. Releasing real rows here would put both jobs back into one 52 ms
    // VSync. The delayed callback gives this cheap dataset one full page frame,
    // then releaseNextInitialMessageBatch() admits exactly one row per VSync.
    const firstRevealCount: number = 0;
    const staged: AlbumGroup[] = stageInitialMessageGroups(
      groups,
      target.anchorIndex,
      target.alignFromStart,
      firstRevealCount
    );
    if (staged === groups) {
      this.publishGroups(groups);
      return;
    }

    const stageSeq: number = ++this.initialMessageStageSeq;
    this.initialTimelineMasked = true;
    this.initialTimelineReadyToPresent = false;
    this.initialTimelinePresentationSeq++;
    this.initialTimelinePresentationScheduledSeq = 0;
    this.initialTimelineEarliestAt = Date.now() + (target.alignFromStart
      ? INITIAL_TIMELINE_PRESENT_MIN_MS : INITIAL_BOTTOM_PRESENT_MIN_MS);
    this.initialMessageStageActive = true;
    this.syncChatTgsGate();
    this.initialMessagePendingGroups = groups;
    this.initialMessageRevealCount = firstRevealCount;
    this.publishGroupsNow(staged);
    this.postInitialMessageFrame(stageSeq);
  }

  // 隐藏时把视口位置记下来，供回来后还原。
  //
  // **包括当时正停在底部的情况**：停在底部只说明那一刻那里是最新的，不代表
  // 用户愿意把隐藏期间到达的消息当成看过的划走。原来那一支直接 glueBottom，
  // 表现就是"切出去、来了消息、切回来直接甩到最底下"。还原到原位之后，新消息
  // 留在下方，「↓」带未读数指回去，要不要下去由用户决定。
  private captureHiddenAnchor(): void {
    this.hiddenAnchorId = 0;
    this.hiddenAnchorY = 0;
    if (!this.didInitialScroll ||
      this.curStartIdx < 0 || this.curStartIdx >= this.groups.length) {
      return;
    }
    this.hiddenAnchorId = this.groups[this.curStartIdx].head.id;
    try {
      this.hiddenAnchorY = this.scroller.getItemRect(this.curStartIdx).y;
    } catch (e) {
      this.hiddenAnchorY = 0;
    }
  }

  // 诊断：把视口附近这一段数据集原样打出来，供和屏幕逐行对照。
  //

  private resyncListAfterHidden(): void {
    const anchorId: number = this.hiddenAnchorId;
    const anchorY: number = this.hiddenAnchorY;
    this.hiddenAnchorId = 0;
    this.hiddenAnchorY = 0;
    // 迁 Repeat 之前这里是 groupsData.reload()。等价物见 rebuildAllRows()。
    this.rebuildAllRows();
    // 再打一次：此时框架已经渲染完，屏幕上如果是错的，这一份就是"数据本来
    // 长什么样"的对照。
    const dumpSeq: number = this.scrollActionSeq;
    setTimeout((): void => {
      if (dumpSeq === this.scrollActionSeq) {
      }
    }, 2500);
    if (anchorId > 0) {
      // 先松开贴底：还原发起到 onScrollIndex 回调落地之间，atBottom 还是隐藏
      // 前那个 true，这期间任何一条到达通知都会走"在底部就跟随"那一支
      // （见 L1242）把视口又拽回底部。同文件 1216 / 1227 两处也是这个写法。
      this.atBottom = false;
      this.restorePrependAnchor(this.groups, anchorId, anchorY);
    } else if (this.atBottom && this.didInitialScroll) {
      const actionSeq: number = ++this.scrollActionSeq;
      setTimeout((): void => {
        if (actionSeq === this.scrollActionSeq) {
          this.glueBottom('L279');
        }
      }, 0);
    }
  }
  // 官方预取算法：按可见区域变化决定预取/取消哪些行的图片解码。
  private imagePrefetcher: BasicPrefetcher = new BasicPrefetcher(this.groupsData);
  private messageActionsCache: MessageBubbleActions | null = null;
  // ArkUI may ask the same visible/cache row to build again after unrelated
  // page state changes. Keep the immutable render bundle by row fingerprint
  // and the small set of dynamic inputs it actually consumes.
  private preparedMessageCache: Map<string, PreparedMessageBubble> =
    new Map<string, PreparedMessageBubble>();
  private messageListRevision: number = 0;
  private chatBackgroundRevision: number = 0;

  private messageActions(): MessageBubbleActions {
    if (this.messageActionsCache === null) {
      this.messageActionsCache = {
        onStopLiveLocation: (): void => { confirmStopLiveLocation(); },
        onMediaTap: (messageId: number, x: number, y: number): void => {
          this.tapX = x;
          this.tapY = y;
          this.openViewer(messageId);
        },
        onAvatarTap: (userId: number): void => {
          const params: Record<string, Object> = { 'userId': userId };
          navigateToProfile(params);
        },
        onAvatarLongPress: (userId: number, name: string): void => {
          this.mentionSender(userId, name);
        },
        onLinkTap: (url: string): void => { this.onLinkTap(url); },
        onCommentTap: (messageId: number): void => { this.onCommentTap(messageId); },
        onBotCallback: (messageId: number, data: string): void => {
          this.onBotCallback(messageId, data);
        },
        onReplyTap: (messageId: number, fromId: number): void => {
          this.onReplyTap(messageId, fromId);
        },
        onFileTap: (messageId: number): void => { this.onFileTap(messageId); },
        onFileSave: (messageId: number): void => { this.onFileSave(messageId); },
        onFilePause: (messageId: number): void => { this.store?.pauseFileDownload(messageId); },
        onStickerRetry: (messageId: number): void => { this.store?.retrySticker(messageId); },
        onContactOpen: (userId: number, phone: string, vcard: string): void => {
          this.openSharedContact(userId, phone, vcard);
        },
        onPhoneOpen: (phone: string): void => { this.openSharedPhone(phone); },
        onLocationOpen: (latitude: number, longitude: number, label: string,
          valid: boolean): void => {
          this.openSharedLocation(latitude, longitude, label, valid);
        },
        onPollVote: (messageId: number, optionIds: number[]): void => {
          this.onPollVote(messageId, optionIds);
        },
        onGameOpen: (messageId: number): void => { this.onGameOpen(messageId); },
        onGamePhotoRetry: (messageId: number): void => { this.store?.retryPhoto(messageId); },
        onPaidMediaUnlock: (messageId: number): void => { this.onPaidMediaUnlock(messageId); },
        onPaidMediaOpen: (messageId: number): void => { this.onPaidMediaOpen(messageId); },
        onSpecialPhotoRetry: (messageId: number): void => { this.store?.retryPhoto(messageId); },
        onVideoRetry: (messageId: number): void => {
          this.store?.requestVideoDownload(messageId, true);
        },
        onGiftCodeCopy: (code: string): void => { this.onGiftCodeCopy(code); },
        onGiveawayOpen: (chatId: number, messageId: number): void => {
          this.onGiveawayOpen(chatId, messageId);
        },
        onVoiceTap: (messageId: number): void => { this.onVoiceTap(messageId); },
        onVoicePlaybackStarted: (messageId: number): void => {
          this.onVoicePlaybackStarted(messageId);
        },
        onAudioTap: (messageId: number): void => {
          this.musicQueue.play(this.messages, messageId, false);
        },
        onAudioPrevious: (messageId: number): void => {
          this.musicQueue.previous(this.messages, messageId);
        },
        onAudioNext: (messageId: number): void => {
          this.musicQueue.next(this.messages, messageId);
        },
        onAudioSeek: (messageId: number, fraction: number): void => {
          this.musicQueue.seek(messageId, fraction);
        },
        onAutoplayVideoNeedDownload: (messageId: number): void => {
          this.store?.requestVideoDownload(messageId);
        },
        onMediaRatio: (messageId: number, albumIndex: number, ratio: number,
          centerY: number): void => {
          if (this.viewerMsgId !== 0 || !this.pageVisible || !this.playSlotsEnabled()) {
            return;
          }
          const now: number = Date.now();
          this.playSlots.report(messageId, albumIndex, ratio, centerY, now);
          this.maybeScheduleNextSlotCheck(now);
        },
        onMediaGone: (messageId: number, albumIndex: number): void => {
          this.playSlots.drop(messageId, albumIndex);
        },
        onPlaySlotPositionChanged: (messageId: number, _albumIndex: number,
          positionMs: number): void => {
          this.bubblePositionMs.set(messageId, positionMs);
        },
        onPlaySlotEnded: (messageId: number, albumIndex: number): void => {
          const now: number = Date.now();
          this.playSlots.retire(messageId, albumIndex, now);
          this.maybeScheduleNextSlotCheck(now);
        },
        onAnimationTap: (messageId: number, playing: boolean): void => {
          this.onAnimationTap(messageId, playing);
        },
        onAnimationPlaybackFailed: (messageId: number): void => {
          this.onAnimationPlaybackFailed(messageId);
        },
        onForwardTap: (originChatId: number, messageId: number, userId: number): void => {
          openForwardOrigin(originChatId, messageId, userId);
        },
        onEditMsg: (messageId: number): void => { this.startEdit(messageId); },
        onShowReactors: (messageId: number, emoji: string): void => {
          this.showReactors(messageId, emoji);
        },
        onTranslateMsg: (messageId: number): void => {
          this.translateMessage(messageId);
        },
        onToggleTranslation: (messageId: number, hidden: boolean): void => {
          this.toggleTranslationHidden(messageId, hidden);
        },
        onRetryTranslation: (messageId: number): void => {
          this.translateInline(messageId);
        },
        onPinMsg: (messageId: number, unpin: boolean): void => {
          this.togglePinMessage(messageId, unpin);
        },
        onStopPoll: (messageId: number): void => { this.stopPoll(messageId); },
        onReplaceMedia: (messageId: number): void => { this.replaceMedia(messageId); },
        onPollVoters: (messageId: number): void => { this.showPollVoters(messageId); },
        onSetDefaultReaction: (emoji: string): void => { setDefaultReaction(emoji); },
        onSetReaction: (messageId: number, emoji: string, chosen: boolean): void => {
          this.toggleReaction(messageId, emoji, chosen);
        },
        onReplyTo: (messageId: number): void => { this.startReply(messageId); },
        onCopyText: (messageId: number): void => { this.copyMessageText(messageId); },
        onCopyLink: (messageId: number): void => { this.copyMessageLink(messageId); },
        onForwardMessages: (messageIds: number[]): void => { this.openForwardPicker(messageIds); },
        onSaveMessages: (messageIds: number[]): void => { this.saveToSavedMessages(messageIds); },
        onRepeatMessages: (messageIds: number[]): void => { this.repeatMessages(messageIds); },
        onViewSenderHistory: (senderId: number): void => { this.viewSenderHistory(senderId); },
        onReportMsg: (_messageId: number): void => {
          promptAction.showToast({ message: $r('app.string.cp_report_wip'), duration: 1500 });
        },
        onSelectMessages: (messageIds: number[]): void => { this.enterSelect(messageIds); },
        onDeleteMsg: (messageId: number): void => { this.deleteMessage(messageId); },
        onOpenReactions: (messageId: number): void => { this.openReactionSheet(messageId); },
        onLinkPreviewRetry: (messageId: number): void => {
          this.store?.retryLinkPreviewPhoto(messageId);
        },
        onCopyCode: (value: string): void => {
          copyPlainText(value, str('cp_code_copied'));
        },
        onRecognizeSpeech: (messageId: number): void => { this.recognizeSpeech(messageId); },
        onVideoNoteDownload: (messageId: number): void => {
          this.store?.requestVideoDownload(messageId, true);
        },
        onLiveStreamTap: (_groupCallId: number): void => { this.onLiveStreamTap(); }
      };
    }
    return this.messageActionsCache;
  }

  private albumReuseShape(g: AlbumGroup): string {
    let shape: string = `${g.photoPaths.length}`;
    for (let i = 0; i < g.photoPaths.length; i++) {
      const memberId: number = g.memberIds[i] ?? 0;
      shape += `:${g.photoIsVideo[i] ? 'v' : 'p'}` +
        `${g.photoPaths[i] !== '' ? 'r' : 'n'}${g.photoFileIds[i] !== 0 ? 'f' : 'z'}` +
        `${g.photoFailed[i] ? 'e' : 'o'}${this.playSlotKey === slotKey(memberId, i) ? 's' : 'i'}`;
    }
    return shape;
  }

  // Prepare the row once for this build invocation. `data` used to repeat all
  // of these derived lookups independently for every visible row.
  private prepareMessageBubble(g: AlbumGroup): PreparedMessageBubble {
    const paused: boolean = this.animationPaused(g.head.id);
    const forcePlay: boolean = this.animationForcePlay(g.head.id);
    const playbackFailed: boolean = this.animationPlaybackFailed(g.head.id);
    const audio: boolean = audioQueueApplies(g.head.contentType);
    const showUnreadDivider: boolean = this.firstUnreadId !== 0 &&
      g.memberIds.indexOf(this.firstUnreadId) >= 0;
    const translationActive: boolean = this.translationActive();
    const isPinnedMsg: boolean = (this.store?.getPinnedIds() ?? []).indexOf(g.head.id) >= 0;
    const paidMediaPending: boolean = this.paidMediaPending(g.head.id);
    const editingActive: boolean = this.editingId !== 0;
    const animateIn: boolean = this.freshSinceId !== 0 && g.head.id > this.freshSinceId;
    const liveGroupCallId: number = this.liveCallIsActive ? this.liveGroupCallId : 0;
    // nowSec changes every second, but only these two reuse decisions cross a
    // time boundary. Key the decisions instead of invalidating every prepared
    // row every second; the live clock itself is passed outside the cache.
    const menuEditable: boolean = g.head.isOutgoing && this.nowSec - g.head.date < 172800;
    const pollExpired: boolean = g.head.pollCloseDate > 0 && this.nowSec >= g.head.pollCloseDate;
    const cacheKey: string = `${this.rowKeyOf(g)}|c${this.chatId}` +
      `|g${this.isGroup ? 1 : 0}${this.isChannel ? 1 : 0}` +
      `|u${showUnreadDivider ? 1 : 0}|tr${translationActive ? 1 : 0}` +
      `|editable${menuEditable ? 1 : 0}|poll${pollExpired ? 1 : 0}` +
      `|pin${isPinnedMsg ? 1 : 0}|paid${paidMediaPending ? 1 : 0}` +
      `|anim${paused ? 1 : 0}${forcePlay ? 1 : 0}${playbackFailed ? 1 : 0}` +
      `|edit${editingActive ? 1 : 0}|fresh${animateIn ? 1 : 0}` +
      `|live${this.liveLocationMessageId}|call${liveGroupCallId}` +
      `|slot${this.playSlotKey}|slotms${this.playSlotStartMs}` +
      `|mute${this.autoplayMuted ? 1 : 0}|msg${audio ? this.messageListRevision : 0}` +
      `|bg${this.chatBackgroundRevision}|appearance${this.appearanceEpoch}` +
      `|material${this.materialEpoch}|dark${this.appDark ? 1 : 0}`;
    const cached: PreparedMessageBubble | undefined = this.preparedMessageCache.get(cacheKey);
    if (cached !== undefined) {
      return cached;
    }
    // Queue lookup walks the loaded message list. It now runs only when an
    // audio row or the list revision genuinely changes, not on every page-wide
    // rerender of an otherwise stable cached row.
    const audioQueuePosition: number = audio
      ? this.musicQueue.queuePosition(this.messages, g.head.id) : 0;
    const audioQueueLength: number = audio ? this.musicQueue.queueLength(this.messages) : 0;
    const audioHasPrevious: boolean = audio
      ? this.musicQueue.hasPrevious(this.messages, g.head.id) : false;
    const audioHasNext: boolean = audio
      ? this.musicQueue.hasNext(this.messages, g.head.id) : false;
    const context: MessageBubbleReuseContext = {
      albumItemCount: g.photoPaths.length,
      memberCount: g.memberIds.length,
      hasDateSeparator: g.dateLabel !== '',
      showUnreadDivider,
      isGroup: this.isGroup,
      isChannel: this.isChannel,
      showAvatar: g.showAvatar,
      showSenderName: g.showSenderName,
      translationActive,
      menuEditable,
      albumShape: this.albumReuseShape(g),
      albumCaptionShape: formattedTextReuseShape(
        g.caption,
        g.captionEntities,
        g.head.inlineCustomEmojiIds,
        g.head.inlineCustomEmojiPaths
      ),
      playSlotActive: this.playSlotKey === slotKey(g.head.id, -1),
      animationPaused: paused,
      animationForcePlay: forcePlay,
      animationPlaybackFailed: playbackFailed,
      isPinnedMsg,
      liveSharing: this.liveLocationMessageId === g.head.id,
      paidMediaPending,
      liveVideoChatTappable: g.head.isVideoChatStarted && this.liveCallIsActive,
      audioQueuePosition,
      audioQueueLength,
      pollExpired
    };
    const lightweightPlainText: boolean = canRenderLightweightPlainText(g.head, context);
    const data: MessageBubbleRenderData = {
      chatId: this.chatId, isGroup: this.isGroup, isChannel: this.isChannel,
      liveSharingId: this.liveLocationMessageId, themeBubbleOut: this.chatBg.bubbleOutColor,
      showUnreadDivider,
      paidMediaPending,
      audioQueuePosition,
      audioQueueLength,
      audioHasPrevious,
      audioHasNext,
      playSlotKey: this.playSlotKey, autoplayMuted: this.autoplayMuted,
      playSlotStartMs: this.playSlotStartMs,
      animationPaused: paused,
      animationForcePlay: forcePlay,
      animationPlaybackFailed: playbackFailed,
      editingActive,
      isPinnedMsg,
      liveGroupCallId: this.liveCallIsActive ? this.liveGroupCallId : 0,
      animateIn,
      lightweightPlainText
    };
    const prepared: PreparedMessageBubble = {
      group: g,
      data
    };
    if (this.preparedMessageCache.size >= PREPARED_MESSAGE_CACHE_LIMIT) {
      this.preparedMessageCache.clear();
    }
    this.preparedMessageCache.set(cacheKey, prepared);
    return prepared;
  }

  // ── 全局复用池：按 reuseId 分桶封顶 ──────────────────────────────────
  //
  // 这是全局池相对默认池的实质收益之一（默认池根本没有这个旋钮），治的是
  // 官方点名的「缓存池溢出：短时间内产生大量待回收项，超出缓存容量 → 旧实例
  // 被丢弃，新项仍需重建」，同时也是 shared 所有权那条使用限制的解药——
  // 「只要拥有组件类的任何实例存在，池就会持续存在……回收的组件可能会累积。
  // 使用 maxCount 来控制内存使用」。
  //
  // 上限怎么来的写在 messageReusePool.reuseBucketMaxCount 的注释里，一句话：
  // 一个桶在一次最坏回收潮里能收到的实例数 = 可视窗口行数 + 2 × cachedCount，
  // 再乘上当前并存的会话页数（shared 池同时服务它们，见 hostPages）。
  //
  // 每桶封顶之外还有一层（F-6）：桶数**本身**也要封顶。medium 档的 rowReuseId
  // 取值空间约 3000 个，而 shared 池只要栈上还压着任意会话页就不销毁，逛过的
  // 会话的形状分桶会一直累积。planReuseBuckets 因此在同一趟里把最久未用的桶
  // 淘汰掉，把活着的桶数压回 REUSE_LIVE_BUCKET_LIMIT 之内。
  //
  // 视口高度这里传的是**整屏高度** this.screenH，而不是 List 的实测高度：
  // 列表上下还压着头部和输入区，整屏高度是列表高度的上界，于是算出来的行数
  // 也是上界。方向是对的——上限估高了只是多留几个空实例，估低了会把还要用的
  // 实例赶出池子，正是要治的那条溢出。
  //
  // 只在**滚动停下**和**页面隐藏**时跑，不在滚动中跑：赋值 maxCount 会触发
  // 框架的异步清理，滚动中做这件事等于自己制造抖动。滚动停下正好是一次回收潮
  // 刚过、池子最满的时刻；页面隐藏则是 shared 池跨会话累积之前的最后一道闸。
  //
  // 低于 API 26 直接返回：UIUtils.getCustomComponentContext 是 API 26 的接口，
  // 这一句是本页唯一会碰到它的地方，闸门就在函数第一行。
  private lastReuseCapMs: number = 0;

  private capMessageReuseBuckets(): void {
    if (!globalReusePoolAvailable()) {
      return;
    }
    const now: number = Date.now();
    if (now - this.lastReuseCapMs < REUSE_CAP_MIN_INTERVAL_MS) {
      return;
    }
    this.lastReuseCapMs = now;
    try {
      const pool: IReusePool | undefined =
        UIUtils.getCustomComponentContext(this).getReusePool();
      if (pool === undefined) {
        // 走到这里说明宿主那层没生效（池宿主没被 new 出来，或者本页不在它
        // 之下）。不是错误：默认复用池仍然在工作，只是没有封顶这项能力。
        return;
      }
      const rows: number = messageRowViewportRows(this.screenH, MIN_MESSAGE_ROW_HEIGHT_VP);
      capReuseBuckets(pool, ReusableMessageBubble,
        reuseBucketMaxCount(rows, this.listCachedCount, messageReuseHostCount()));
    } catch (err) {
      // 封顶是纯优化，失败了不该影响任何一行的渲染——吞掉但留痕。
      logW('[ReusePool] cap failed', err);
    }
  }

  // @ReusableV2 用 .reuse({ reuseId })（API 18 起）取代 V1 的 .reuseId()。
  //
  // ⚠️ 官方《复用选项》对 reuseId 有一条版本相关的行为差，调研没有覆盖到：
  // 「在 API 版本 26.0.0 之前，当 reuseId 不是**显式返回字符串字面量**的回调
  // 方法时，实际的复用标识 id 为该自定义组件的名称」。下面这个回调不是字面量，
  // 所以在旧行为下会被降级成单一的 'ReusableMessageBubble'，REUSE_ID_LEVEL 的
  // 分档静默失效、所有行共用一个池。
  //
  // 走的是哪一侧，看编译产物就知道——ets-loader 把它编成了运行时判断：
  //   getReuseId: getUINativeModule().common.getApiTargetVersion() >= 26
  //     ? () => rowReuseId(...) : () => "ReusableMessageBubble"
  // 闸门是 **getApiTargetVersion()**，也就是 build-profile 里的 targetSdkVersion
  // （本仓 "26.0.0"），不是 compatibleSdkVersion("6.0.0(20)")、也不是设备版本。
  // 按这条推断分档是生效的，但这是读产物推出来的，**没上机验过**，列入待验清单。
  //
  // ⚠️ **别再试图用「低版本不走 .reuse()」绕开那段探测——试过了，绕不掉。**
  // 2026-08-26 的编译实验（把 .reuse({ reuseId }) 整个删掉、只留裸的
  // ReusableMessageBubble({...})，重新 assembleHap 再读产物）结果是：
  //   getReuseId: getUINativeModule().common.getApiTargetVersion() >= 26
  //     ? () => "ReusableMessageBubble" : () => "ReusableMessageBubble",
  // 探测**照样生成**，两侧只是塌成了同一个组件名。也就是说这段代码是
  // **@ReusableV2 子组件实例化**的产物，与 reuseId 是不是字符串字面量、与
  // 有没有 .reuse() 都**无关**。同一次实验里 V1 的 @Reusable（ChatRow）产物
  // 里一处都没有，全仓 getApiTargetVersion 只出现在本文件。
  //
  // 结论：如果 getUINativeModule().common.getApiTargetVersion 在 API 20~25 的
  // 运行时不存在，那是 **d949bde（P3 批 1 迁 @ReusableV2）** 带进来的风险，
  // 不是 P5 的 .reuse() 带进来的；唯一的移除路径是退回 V1 @Reusable，那是
  // 整轮回滚，不是一处旁路。低版本设备是否真的会炸只能上机确认。
  //
  // 入参是**整个 RepeatItem**，不是从它里面取出来的值。官方《Repeat》使用限制：
  // 「当 Repeat 与自定义组件或 @Builder 函数混用时，必须将 RepeatItem 类型整体
  // 进行传参，组件才能监听到数据变化」，反例正是按值传 ri.item —— 那样 Repeat
  // 更新这一行时（它只换 RepeatItem 里的 item，不重跑 .each()）这个 @Builder
  // 里的 UI 不会刷新。所以 ri 一路传到这里，group/data 都在本作用域内现取。
  @Builder
  private preparedMessageBubble(ri: RepeatItem<AlbumGroup>) {
    ReusableMessageBubble({
      group: ri.item,
      nowSec: this.nowSec,
      data: this.prepareMessageBubble(ri.item).data,
      actions: this.messageActions()
    }).reuse({
      reuseId: (): string =>
        rowReuseId(this.prepareMessageBubble(ri.item).data, ri.item, REUSE_ID_LEVEL)
    });
  }
  @Local subtitle: string = '';
  // "×× 正在输入…" — shown as the composer placeholder while live, not in the
  // header subtitle (see composerPlaceholder).
  @Local typingLabel: string = '';
  private typingSenders: Map<number, number> = new Map(); // senderId -> expiry ms
  private typingTimer: number = -1;
  private unsubChatAction: (() => void) | null = null;
  @Local title: string = '';
  @Local avatarPath: string = '';
  // 聊天页头部的动态头像（MP4 循环）。issue #63：资料页会动、对话里不动——
  // 头部一直只拿静态图。动画文件挂在 full info 的 chatPhoto.animation 里，
  // getChat 的 chatPhotoInfo 只有 has_animation 标志，必须多要一次。
  @Local headerAvatarAnimPath: string = '';
  @Local initials: string = '?';
  @Local draft: string = '';
  // 聊天设置 → 回车键发送.
  @Require @Param sendByEnter: boolean = false;
  @Require @Param screenW: number = 360;
  private lastScreenW: number = 0;
  @Require @Param screenH: number = 780;
  @Require @Param powerSaving: boolean = false;
  @Require @Param powerChatEffects: boolean = true;
  @Require @Param powerBackgroundEffect: boolean = false;
  @Require @Param powerParticles: boolean = true;
  @Require @Param powerEmoji: boolean = true;
  @Require @Param powerEmojiReactions: boolean = true;
  @Require @Param reduceAnimations: boolean = false;
  // 「自动播放视频」开关。播放位竞选的总闸门之一，见 playSlotsEnabled()。
  @Require @Param autoplayVideo: boolean = true;
  // 否则拖完滑块背景看起来没反应（命中旧签名的缓存图）。
  // TDLib per-chat wallpaper. Solid/gradient fills render immediately;
  // wallpaper and pattern documents appear as soon as downloadFile completes.
  // One snapshot in place of the nine background state variables this replaces.
  // Resolution (chat background → theme → account default → installed default)
  // and its four TDLib subscriptions live in ChatBackgroundStore.
  @Local chatBg: ChatBackgroundState = emptyChatBackground();
  private bgStore: ChatBackgroundStore | null = null;
  private unsubBg: (() => void) | null = null;
  private unsubTranslatable: (() => void) | null = null;
  @Local replyToId: number = 0;      // message being replied to (0 = none)
  @Local replyToName: string = '';
  @Local replyToText: string = '';
  @Local editingId: number = 0;      // message being edited (0 = none)
  @Local editingPreview: string = '';
  @Local editingKind: string = 'text'; // 'text' | 'caption'
  private draftBeforeEdit: string = ''; // composer text stashed while editing
  @Local showReactionSheet: boolean = false; // full emoji reaction picker
  @Local reactionTargetId: number = 0;
  // The allowed-emoji list and custom-emoji thumbnails live in ReactionSheet,
  // which fetches them per open. Only the in-flight key stays here: the quick
  // reaction row on each bubble issues the same request and shares the guard.
  @Local reactionPendingKey: string = '';
  @Local paidMediaPendingIds: number[] = [];
  // Forwarding is deliberately kept as an in-page sheet: leaving ChatPage to
  // pick a destination used to discard the long-press/selection context.
  @Local showForwardSheet: boolean = false;
  @Local showPollSheet: boolean = false;
  @Local showContactSheet: boolean = false;
  @Local showVideoNoteRecorder: boolean = false;
  // The list itself lives in ScheduledSheet and reloads on each open.
  @Local showScheduledSheet: boolean = false;
  // Which messages the picker will forward. The picker's own list/query/send
  // state lives in ForwardSheet and resets with it on each open.
  private forwardMessageIds: number[] = [];
  @Local nowSec: number = 0;
  private nowSecTimer: number = -1;
  @Local viewerMsgId: number = 0;
  @Local chromeVisible: boolean = true;
  @Local viewerVideoLandscape: boolean = false;
  @Local viewerClosing: boolean = false;
  // 播放器为播放拉起的下载（见 notePlaybackRequest）。不参与渲染，普通字段。
  private playbackRequestedIds: number[] = [];
  // GIF playback is page-owned rather than row-owned: LazyForEach replaces a
  // row key as download progress/reactions change, but a user's pause/play
  // choice must survive that replacement.
  @Local pausedAnimationIds: number[] = [];
  @Local forcedAnimationIds: number[] = [];
  @Local failedAnimationIds: number[] = [];
  // Swiper's initial page when the viewer opens. Plain field, not @Local: it is
  // read once when MediaViewerOverlay is constructed, which happens after this
  // has already been set by onMediaTap.
  private viewerInitIdx: number = 0;
  @Local swipeDir: number = 1; // 1 = advancing forward (next), -1 = going back — drives the slide direction
  // Window coordinates (vp) of the tap that opened the viewer — anchor for its
  // expand-from-tap open / shrink-back-to-tap close transition.
  @Local tapX: number = 0;
  @Local tapY: number = 0;
  @Local pinnedPreview: string = '';
  @Local pinnedCount: number = 0;
  @Local pinnedLoadState: string = 'loading'; // loading | ready | error
  @Local pinnedJumpBusy: boolean = false;
  // 正在直播入口条:chat.video_chat.group_call_id > 0 时显示("正在直播").
  @Local liveGroupCallId: number = 0;
  @Local liveCallIsActive: boolean = false;
  @Local liveCallIsRtmp: boolean = false;
  @Local liveParticipantCount: number = 0;
  @Local livePulseExpanded: boolean = false;
  @Local liveLoadState: string = 'loading'; // loading | ready | error
  @Local liveDialogOpening: boolean = false;
  @Local liveNavigationBusy: boolean = false;
  @Local topCardLoadingVisible: boolean = false;
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
  // 私聊对方是机器人。空会话时输入框让位给「开始」，见 util/botStart。
  @Local isBotChat: boolean = false;
  @Local isGroup: boolean = false;
  @Local isChannel: boolean = false;
  // TDLib keeps membership on the underlying basicGroup/supergroup rather
  // than on chat itself. Public chats opened from search can therefore have
  // readable history while the current user is still outside the chat.
  // writable = normal composer, joinable = bottom "加入" action,
  // blocked = banned/unavailable, checking = waiting for the group object.
  @Local membershipState: string = 'writable';
  @Local joiningChat: boolean = false;
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
  // Invalidates delayed initial-unread layout confirmations when the page is
  // reset or another landing supersedes the current one.
  private initialUnreadLayoutSeq: number = 0;
  private initialMessageStageSeq: number = 0;
  private initialMessageStageActive: boolean = false;
  private initialMessagePendingGroups: AlbumGroup[] | null = null;
  private initialMessageRevealCount: number = 0;
  // 0 means no callback is queued. Storing the stage sequence rather than a
  // boolean prevents an invalidated old callback from clearing a newer stage's
  // scheduled marker when it eventually arrives.
  private initialMessageStageScheduledSeq: number = 0;
  // The initial LazyForEach still lays out while masked. Once a complete
  // viewport has real rows and its unread/bottom anchor has been applied, the
  // mask is removed in one frame. This prevents both row-by-row appearance and
  // a visible placeholder-height correction jump.
  @Local private initialTimelineMasked: boolean = false;
  private initialTimelineReadyToPresent: boolean = false;
  private initialTimelinePresentationSeq: number = 0;
  private initialTimelinePresentationScheduledSeq: number = 0;
  private initialTimelineEarliestAt: number = 0;
  @Local private initialMessageTransitionSettled: boolean = false;
  private initialMessageReleaseTimer: number = -1;
  private chatTgsScrollActive: boolean = false;
  private chatTgsStageSettling: boolean = false;
  private chatTgsResumeTimer: number = -1;
  // 播放位竞选：滚动停下后选出唯一播放/下载的视频气泡（见 PlaySlotRegistry）。
  private playSlots: PlaySlotRegistry = new PlaySlotRegistry();
  private unsubPlaySlot: (() => void) | null = null;
  @Local playSlotKey: string = '';
  // 新上位的播放位从哪一毫秒起播。换届时从 bubblePositionMs 查一次（见
  // subscribe 回调），随 playSlotKey 一起下发给气泡——查看器交还的进度就是
  // 靠这条路真正接到 VideoBubbleSurface.startPositionMs 上的。
  @Local playSlotStartMs: number = 0;
  // 缓存设置 → 自动播放静音开关，唯一消费点：下发给气泡播放器的 muted。
  @Require @Param autoplayMuted: boolean = true;
  // 气泡播放位的播放进度，按 messageId 记录。onPlaySlotPositionChanged 是
  // 350ms 一次的高频回调，故意用普通 Map 而不是 @Local/AppStorage——
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
  @Local atBottom: boolean = true;
  @Local isMuted: boolean = false;
  // 整聊天翻译有两层，菜单里的那一项在两层之间切换含义：
  //   总开关开着 —— 默认所有会话都翻，菜单是"关掉这个会话"（本地排除名单）。
  //   总开关关着 —— 默认都不翻，菜单是"只翻这个会话"（服务端 is_translatable，
  //                 跟官方客户端同一个字段，多端同步）。
  // 早先只认服务端那个字段，它对没碰过的会话默认 false，结果开了总开关每个群
  // 还得手动点一次才翻，实际不可用。
  @Local isTranslatable: boolean = false;
  @Local translateChatOptOut: boolean = false;
  // 总开关关着时，本地记下的"这个会话开了翻译"。见 translationMode 的说明。
  @Local translateChatOptIn: boolean = false;
  @Require @Param translateChatsEnabled: boolean = false;
  // 是否正在共享实时位置（全局单例状态，不限于当前会话）。
  @Local liveLocationActive: boolean = false;
  @Local liveLocationMessageId: number = 0;
  // 贴纸"飞出"动画：从点击处向上收缩淡出，动画收尾时才关面板 —— 关面板要
  // 同步卸载整个贴纸网格并触发全页重排（实测 51ms），压在点击那一帧就是可感
  // 的顿挫；挪到运动尾声则被动作本身盖住。
  @Local stickerGhostPath: string = '';
  @Local stickerGhostX: number = 0;
  @Local stickerGhostY: number = 0;
  @Local stickerGhostFly: boolean = false;
  private stickerGhostTimer: number = -1;
  private unsubLiveLocation: (() => void) | null = null;
  @Local unreadBadge: number = 0;
  private firstUnreadId: number = 0;
  // Set once the initial scroll parks on the unread boundary; suppresses every
  // auto-scroll-to-bottom until the user first touches the list, so a short
  // unread run isn't glued past the divider by async in-place content growth.
  private stayAtUnread: boolean = false;
  private curStartIdx: number = -1; // topmost visible row index (from onScrollIndex)
  private curEndIdx: number = -1;   // bottom visible row index (from onScrollIndex)
  // onScrollIndex 上报那一刻的 groups.length。行号只有配上它才有意义。
  private indexGroupsLen: number = -1;
  // 右下角「↓」的去向状态。它不是"回到底部"，而是"回到该继续看的地方"：
  // 引用返回 > 阅读进度 > 最新消息。规则在 util/readingReturn（有单测），
  // 这里只负责喂状态和执行结果。
  @Local returnState: ReturnState = emptyReturnState();
  // 视口最底下那条真实消息的 id。既是"当前位置"，也是跳走时要记下的返回点。
  private curBottomId: number = 0;
  // 跳转落地的宽限期。跳到贴近尾部的引用时视口会短暂判为"在最新"，若不设防
  // 就会把返回栈当成"用户自己滚回来了"清掉，一步都退不回去。
  private jumpLandingUntil: number = 0;
  private pendingScrollBottom: boolean = false; // snap to the end once jumpToLatest's page arrives
  @Local scrollToBottomBusy: boolean = false;
  private scrollActionSeq: number = 0;
  // Keep the exact viewport when this cached page is temporarily covered by a
  // profile/media route and then becomes visible again.
  private resumeScrollPending: boolean = false;
  private resumeScrollChatId: number = 0;
  private resumeScrollThreadId: number = 0;
  private resumeScrollMessageId: number = 0;
  private resumeScrollItemY: number = 0;
  private resumeScrollAtBottom: boolean = true;
  // @Local: the segment indicator renders from this — a plain field wouldn't
  // trigger a re-render when scrolling/tapping moves the shown pinned index.
  @Local pinnedCycle: number = 0;
  private pendingJumpId: number = 0;
  private jumpLayoutSeq: number = 0;
  // One-shot gate for loading older pages: a fast fling to the very top used to
  // chain-load page after page (the list stays pinned at the edge, so the
  // trigger zone never clears). Re-armed when the user scrolls clear of the
  // top zone or starts a new touch gesture.
  private olderArmed: boolean = true;
  // 向下分页的一次性闸，语义和上面的 olderArmed 一致：打一发就下膛，只有
  // 真实用户输入才重新上膛（见 util/pageGate）。
  //
  // 光靠"end 越过上次开枪的位置"这道弱闸挡不住自持回路：stackFromEnd 是底部
  // 锚定，一页 newer 追加到末尾就把视口往下推，end 自己变大，弱闸每次都放行。
  // 真机上一次开会话连锁拉了 9 页（rowsBefore 132 → 356）。弱闸留着防同一个
  // end 被重复敲，真正止血的是 armed。
  private newerGate: PageGate = armedPageGate();
  // 内容铺不满一屏时主动补页的上限。到这个行数还说"整份都可见"，说明判据
  // 本身出了问题，停手比无限拉更安全。
  private static readonly FILL_VIEWPORT_MAX_ROWS: number = 80;
  // Jump-target highlight: a translucent overlay over the target row that
  // gently blinks twice after a reply/pinned/link jump lands.
  @Local flashTop: number = 0;
  @Local flashHeight: number = 0;
  @Local flashAlpha: number = 0;
  @Local flashShown: boolean = false;
  private flashSeq: number = 0;
  // 高亮当前钉着的行。高亮层是按视口坐标定位的，行高一变（链接预览、缩略图、
  // 翻译状态异步到货把上面的行撑开）它就和句子错开——用户看到的是「高亮在
  // 句子上方」（issue #80）。闪烁期间每一拍都按这两个重新对一次位置。
  private flashTargetIdx: number = -1;
  private flashTargetId: number = 0;
  // Floating date chip: shows the topmost visible message's date while the
  // list scrolls, fades out shortly after scrolling stops (the in-list date
  // pills stay — this is the always-visible companion).
  @Local floatDate: string = '';
  @Local floatDateShown: boolean = false;
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
  // 挂起的保存要去相册还是文件（下载完成后照原样执行）。
  private pendingGallerySaveToFiles: boolean = false;
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
  @Local freshSinceId: number = 0;
  private freshClearSeq: number = 0;
  private prependRestoreSeq: number = 0;
  // '@' mention / '/' command suggestion panels above the input bar.
  @Local mentionItems: MentionItem[] = [];
  @Local stickerSuggestions: StickerSuggestion[] = []; // emoji-typed sticker hints
  private stickerSuggestSeq: number = 0;
  @Local botMiniAppUrlValue: string = ''; // bot menu-button Mini App ('' = none)
  @Local inlineResults: InlineResultRow[] = [];  // @bot query results
  private inlineQueryId: string = '';
  private inlineSeq: number = 0;
  private inlineTimer: number = -1;
  @Local commandItems: CommandItem[] = [];
  private allCommands: CommandItem[] = [];
  @Local commandLoadState: string = 'idle'; // idle | loading | ready | error
  @Local commandLoadError: string = '';
  @Local commandMenuOpen: boolean = false;
  private commandLoadSeq: number = 0;
  private mentionSeq: number = 0; // drops stale searchChatMembers responses
  // Bot "菜单" pill (private bot chats with registered commands).
  @Local botMenuAvailable: boolean = false;
  // Emoji panel above the input bar.
  @Local showEmojiPanel: boolean = false;
  // 附件抽屉是否打开。它是 dock 里的一段布局，不是自定义键盘——后者虽然让
  // 系统接管了顶起动画，但自定义键盘**无法获取焦点**（官方明写），面板里的
  // 搜索框永远输不进字；而且它在另一个图层，背后没有页面背景，得自己画一份
  // 副本去对齐，那条路走了很久也接不上。
  @Local attachPanelOpen: boolean = false;
  @Local diceSheetOpen: boolean = false;

  // 当前打开的底部抽屉占据的高度（附件或表情，两者互斥）。supportAvoidance
  // 只保证输入框不被挡，列表内容它不管——官方《自定义键盘》文档明说这一段
  // 要开发者自己做：监听面板根节点 onAreaChange 拿高度，再设置布局避让。
  @Local emojiPanelTab: number = 0;
  @Local emojiPanelClosing: boolean = false;
  // Bot custom reply keyboard (null = this chat has none). Always docked when
  // present — no toggle, so there's no state to track beyond the keyboard itself.
  @Local replyKeyboard: ReplyKeyboard | null = null;
  // Bot keyboard collapsed by the input-bar toggle (or a one_time keyboard
  // after use). A NEW keyboard from the bot un-collapses automatically.
  @Local replyKbCollapsed: boolean = false;
  @Local replyKeyboardSendingKey: string = '';
  // Voice recording state.
  @Local isRecording: boolean = false;
  @Local recordingStarting: boolean = false;
  @Local recordSeconds: number = 0;
  private recordTimer: number = -1;
  private voiceRec: VoiceRecorder | null = null;
  private recordingSeq: number = 0;
  @Local composerSending: boolean = false;
  @Local composerFocused: boolean = false;
  // TextArea creation loads the stylus service and performs its first paragraph
  // layout. The 17:04 trace confirmed the one-frame placeholder moved it out of
  // page creation, but it then shared a 22 ms frame with the first real message.
  // Keep the placeholder until initial-message admission finishes, then cross
  // one more VSync before mounting the editor.
  @Local composerEditorReady: boolean = false;
  private composerMountScheduled: boolean = false;
  private composerMountSeq: number = 0;
  private composerController: TextAreaController = new TextAreaController();
  private mediaPickerOpen: boolean = false;
  // 选好但还没发出去的媒体。和 replyToId 正交——回复某条 + 附图 + 配文是
  // 一次完整操作，所以不进 composerMode 那个互斥状态机（见 util/pendingMedia）。
  @Local private pendingMedia: PendingMediaItem[] = [];

  private mediaCopySeq: number = 0;
  @Local headerMenuShow: boolean = false; // header ⋮ dropdown
  // Header state is kept separate from message-history state. getChat can
  // resolve before history, fail independently, or arrive after a cached row.
  @Local headerState: string = 'loading'; // loading | ready | error
  @Local headerLoadError: string = '';
  @Local headerProfileOpening: boolean = false;
  @Local headerMuteUpdating: boolean = false;
  @Local pageClosing: boolean = false;
  private headerPeerUserId: number = 0;
  private headerKind: string = '';
  private headerIdentityResolved: boolean = false;
  private headerResolveSeq: number = 0;
  private headerNavigationTimer: number = -1;
  // In-chat message search (search-mode header + result navigation).
  // 输入框上方那一条的当前状态。字段仍在（读取处很多），但**只由
  // applyComposerMode 写**，转换逻辑在 util/composerMode。
  @Local composerMode: ComposerMode = idleComposer();
  // 输入框下面那块高度归谁（none / attach / emoji / replyKeyboard）。
  // 三个既有字段仍在（读取处很多），但**只由 applyBottomSlot 写**。
  @Local bottomSlot: string = SLOT_NONE;
  @Local searchMode: boolean = false;
  // Multi-select mode (entered via the long-press menu's 选择 item).
  @Local selecting: boolean = false;
  @Local selectedIds: number[] = [];
  @Local searchQuery: string = '';
  @Local searchResults: number[] = []; // message ids, newest → oldest
  @Local searchTotal: number = 0;
  @Local searchIdx: number = 0;        // 0-based index into searchResults
  // Message id the chat was opened on from global search — becomes the current
  // hit instead of the search jumping to the newest one. 0 = no anchor.
  private searchAnchorId: number = 0;
  private searchSeq: number = 0;
  // 「查看历史」筛的那个发送者；0 = 不按发送者筛（普通关键词搜索）。
  // 按发送者筛时 query 允许为空——TDLib 支持"空 query + sender_id"列出此人全部消息。
  @Local private searchSenderId: number = 0;       // drops stale responses
  private unsubMsg: (() => void) | null = null;
  private unsubSub: (() => void) | null = null;
  // Peer's premium emoji status (private chats) shown beside the header title.
  @Local headerEmojiPath: string = '';
  @Local headerEmojiFormat: string = '';
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
    this.initialUnreadLayoutSeq++;
    this.initialTimelinePresentationSeq++;
    this.initialTimelinePresentationScheduledSeq = 0;
    this.initialTimelineMasked = false;
    this.initialTimelineReadyToPresent = false;
    this.initialTimelineEarliestAt = 0;
    this.initialMessageTransitionSettled = false;
    this.cancelInitialMessageTransitionSettle();
    this.didInitialScroll = false;
    this.lastMaxId = 0;
    this.atBottom = true;
    this.firstUnreadId = 0;
    this.stayAtUnread = false;
    this.curStartIdx = -1;
    // curEndIdx 和 indexGroupsLen 也要一起清。它们是上一个会话的可见行号，
    // 换会话后 groups 从 0 重新长起来，长度一旦碰巧和旧值相等，refreshAtBottom
    // 的新鲜度检查就会认下这批陈旧行号，据此否决"在底部"，于是刚进会话就
    // 挂出「↓」。清成 -1 后 indexFresh 恒为假，判定退回宽松侧，等第一次
    // onScrollIndex 落地再收紧。
    this.curEndIdx = -1;
    this.indexGroupsLen = -1;
    // 「↓」的返回关系和"底部看到的是哪条"同样是会话级的。消息 id 在每个会话
    // 里独立编号，把上一个会话的跳转栈带过来，↓ 就会指向本会话里一条恰好同号
    // 的无关消息——或者一条根本不存在的 id，点下去只是空转。
    this.returnState = emptyReturnState();
    this.curBottomId = 0;
    this.jumpLandingUntil = 0;
    this.pendingScrollBottom = false;
    this.scrollToBottomBusy = false;
    this.pendingJumpId = 0;
    this.pendingFileOpenId = 0;
    this.pendingFileSaveId = 0;
    this.fileOpenInFlightId = 0;
    this.musicQueue.reset();
    this.olderArmed = true;
    this.newerGate = armedPageGate();
    this.freshSinceId = 0;
    this.freshClearSeq++;
    this.imeTailPinned = false;
    this.imeLayoutSeq++;
    this.lastKeyboardH = this.keyboardH;
    this.cancelFlash();
    this.clearFloatingDate();
    this.messages = [];
    this.messageListRevision++;
    this.preparedMessageCache.clear();
    this.messageLoadError = '';
    this.olderLoadState = 'idle';
    this.newerLoadState = 'idle';
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
    // 暂存的媒体不跨会话保留：草稿有 TDLib 的 setChatDraftMessage 可以落盘，
    // 本地文件路径没有，要留就得自建一套持久化，不值。
    this.pendingMedia = clearPendingMedia();
    this.composerSending = false;
    this.composerFocused = false;
    this.composerMountSeq++;
    this.composerMountScheduled = false;
    this.composerEditorReady = false;
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
    this.applyBottomSlot(closeAllSlots());
    this.replyKeyboardSendingKey = '';
    // 整个清成普通输入，而不是只 clearReply()。clearReply 按设计只处理回复态，
    // 编辑态下是空操作——换会话时编辑态因此能活下来，editingId 还指着上一个
    // 会话的消息，下一次提交就编辑到别的会话去了。
    this.applyComposerMode(idleComposer());
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
      list.some((message: MessageEntry): boolean => isRealClientJoinNotice({
        contentType: message.contentType, isOutgoing: message.isOutgoing,
        placeholderLabel: message.placeholderLabel, systemType: message.systemType
      }))) {
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
    this.visibleGroupCount = groups.length;
    this.publishGroups(groups);
    if (this.didInitialScroll && this.atBottom) {
      const actionSeq: number = ++this.scrollActionSeq;
      setTimeout((): void => {
        if (actionSeq === this.scrollActionSeq) {
          this.glueBottom('L846');
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
    // 同一份位置也记到模块级表里：页面销毁后（退出会话再进来）还能落回去，
    // issue #98。在底部的不记——那种情况下次该跟到最新。
    rememberChatPosition(this.chatId, this.threadRootId,
      this.resumeScrollMessageId, this.atBottom);
    this.resumeScrollPending = true;
  }

  // 路由参数。router 时代靠 router.getParams() 现取，NavDestination 要在
  // onReady 里从 NavDestinationContext 拿。
  //
  // 实测（平板 API 26，commit 8046f73 上机）：**onReady 晚于 aboutToAppear**。
  // 官方文档写 onReady 在「即将构建子组件之前」触发，但 aboutToAppear 比它更早，
  // 所以 aboutToAppear 里读不到 navParams。用参数的那一段因此整体挪进了
  // applyRouteParams()，由 onReady 存完 navParams 之后立即调用。
  private navParams: Record<string, Object> | undefined = undefined;
  // applyRouteParams() 的一次性守卫，理由见那个方法上的注释。
  private paramsApplied: boolean = false;
  // 本页所在的 Navigation 栈，同样在 onReady 里拿。返回键必须靠它出栈，
  // 理由见 goBack()。
  private navStack: NavPathStack | undefined = undefined;

  // 返回上一层。**不能用 router.back()**：本页是 HdsNavDestination，router 页栈里
  // 只剩 Index 一层，router.back() 弹掉的是 Index——平板模拟器实测（Task 7 修复轮 1）
  // 的现象是「点返回箭头直接退到桌面」。要出的是 Navigation 栈。
  //
  // Task 6 迁移本页时这两处（closeChatPage、leaveChat 成功回调）原样留了
  // router.back()，是漏改，不是有意为之。
  private goBack(): void {
    const stack = this.navStack;
    if (stack === undefined) {
      // navStack 由 onReady(ctx.pathStack) 填，而 onReady 必先于本页可见，所以
      // 这一支不该发生。这里**故意不回退到 router.back()**：那正是会退出应用的
      // 那条路，把返回键做成"什么都不做 + 一条日志"远比把应用关掉好。
      logE('ChatPage.goBack: navStack missing, back ignored');
      return;
    }
    // pop() 弹的就是本页这一层。栈空时它返回 undefined，但那意味着"本页正显示
    // 却不在栈里"，不可能发生，故不另做处理。
    stack.pop();
  }

  aboutToAppear(): void {
    // shared 复用池同时服务所有活着的会话页（平板分栏、Navigation 栈上先后
    // 压着的两份）。每桶上限的推导前提是「一个页面的最坏回收潮」，所以要数一数
    // 实际有几个——见 messageReusePool.reuseBucketMaxCount 的 hostPages。
    retainMessageReuseHost();
    // The navigation/build frame owns the main thread; chat stickers can start
    // only after the initial row gate has settled.
    this.chatTgsStageSettling = true;
    this.syncChatTgsGate();
    this.unsubPlaySlot = this.playSlots.subscribe((key: string): void => {
      // 起播位置必须在 playSlotKey 之前落下：气泡是靠 playSlotKey 的变化才
      // 挂载 VideoBubbleSurface 的，晚一步这条播放器就已经从 0 开始了。
      this.playSlotStartMs = key === '' ? 0 : (this.bubblePositionMs.get(slotKeyMessageId(key)) ?? 0);
      this.playSlotKey = key;
    });
    this.nowSec = Math.floor(Date.now() / 1000);
    // 下面原本还有一大段（读 params → 定 chatId → 建 MessageStore 与十几个
    // 订阅）。实测 onReady 晚于 aboutToAppear（平板 API 26，commit 8046f73 上机：
    // aboutToAppear 读 this.navParams 时还是 undefined，chatId 落成 0，标题栏报
    // 「会话参数无效」、内容区报「消息加载失败」）——所以那段整体搬进了
    // applyRouteParams()，由 onReady 在存完 navParams 之后调用。
    //
    // 留在这里的两件事与路由参数无关（播放位订阅、秒表初值），时机保持原样：
    // 它们必须在任何一次行数组发布之前就绪。
  }

  // 路由参数就绪后的初始化。这就是迁移前 aboutToAppear 的后半段，顺序一字未改，
  // 只是改由 onReady 触发——onReady 才是 NavDestination 拿得到 pathInfo.param 的
  // 第一个时机。
  //
  // 只跑一次：这段里建了 MessageStore、十几个 TDLib 订阅和两个 setInterval，句柄都
  // 存在 this.unsubXxx / this.xxxTimer 上。第二次进来会把旧句柄直接覆盖掉，旧订阅和
  // 旧定时器就再也退订不了了——aboutToDisappear 只认得最后一份句柄。HdsNavDestination
  // 在页面被复用时（MOVE_TO_TOP_SINGLETON、onNewParam）可能不止触发一次 onReady，
  // 所以这个守卫是必须的。当前的 navigateToChat 走的是 clearAndPush，每次都是新实例，
  // 守卫在正常路径上不会拦到东西——它挡的是复用路径。
  private applyRouteParams(): void {
    if (this.paramsApplied) {
      return;
    }
    this.paramsApplied = true;
    const params = this.navParams;
    this.chatId = params !== undefined ? (params['chatId'] as number) : 0;
    this.threadRootId = params !== undefined ? ((params['threadRootId'] as number | undefined) ?? 0) : 0;
    // 话题模式（从 ForumTopicsPage 进入）：标题显示话题名而非"评论"。
    this.topicName = params !== undefined ? ((params['topicName'] as string | undefined) ?? '') : '';
    this.forumTopicId = params !== undefined
      ? ((params['forumTopicId'] as number | undefined) ?? 0) : 0;
    // 排除名单是本地的，chatId 一确定就能读，不用等 getChat 回来。
    this.translateChatOptOut = translateOptedOut(this.chatId);
    this.translateChatOptIn = translateOptedIn(this.chatId);
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
      this.chatBackgroundRevision++;
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
      const firstMessageStage: boolean = !scrollResumeWaiting && !this.didInitialScroll &&
        this.groups.length === 0;
      const notifyKind: string = store.getCurrentNotifyKind();
      const maxId: number = list.length > 0 ? list[list.length - 1].id : 0;
      const groups: AlbumGroup[] = this.groupsWithClientJoinNotice(list);
      // Transfer completion/failure and translation state keep the stable list
      // key. Publish them directly to the mounted row before the data-source
      // diff, so a key-equal snapshot still updates the one affected bubble.
      publishMessageRowPresentations(this.chatId, groups);
      // ── 向上翻页的锚点复位 ──────────────────────────────────────────
      //
      // P4 迁 Repeat 时把这一段删了，并留下一句"只有相册跨页合并那一行的 key 会
      // 变"——**那句话是错的**：每次向上翻页，边界那一行的 key 都会变（判据与
      // 完整推导见 AlbumGroupDataSource.prependBreaksAnchor 的注释）。key 变了在
      // Repeat 之下就是删旧插新，被删的正是视口顶端那一行，
      // maintainVisibleContentPosition(true) 守不守得住文档答不了。所以按那条
      // 判据把手动复位接回来，防的是"向上翻页跳到已加载页顶部"那个历史 bug。
      //
      // 判据不成立时**不复位**：纯追加、纯编辑、以及 key 没变的前插，都由
      // maintainVisibleContentPosition 自己守住；在那些情形上强行 scrollToIndex
      // 会打断用户的惯性滑动（当年"加载更多时一顿"就是这么来的）。
      let prependAnchorId: number = 0;
      let prependAnchorY: number = 0;
      if (this.didInitialScroll && prependBreaksAnchor(this.groups, groups)) {
        const visibleIndex: number = this.curStartIdx;
        if (visibleIndex >= 0 && visibleIndex < this.groups.length) {
          prependAnchorId = this.groups[visibleIndex].head.id;
          try {
            prependAnchorY = this.scroller.getItemRect(visibleIndex).y;
          } catch (e) {
            prependAnchorY = 0;
          }
        }
      }
      // ── 向下翻页的锚点复位 ──────────────────────────────────────────
      //
      // 上面那一段的镜像。列表是 stackFromEnd(true)（底部锚定），末尾追加一页
      // 就把可见内容整体往上顶 ⇒ 视口被拽到底。maintainVisibleContentPosition
      // 已经开着，真机上仍然跳，所以这一侧也手动复位。判据与推导见
      // AlbumGroupDataSource.appendBreaksAnchor。
      //
      // `!this.atBottom` 是这里唯一的额外闸：用户确实停在会话末尾时，新消息
      // 把内容往上顶正是想要的跟随行为，绝不能复位。atBottom 在还有更新的历史
      // 没拉时恒为假（util/atBottom 里的 hasMoreNewer 一条），所以向下翻页途中
      // 这道闸天然是开的。
      let appendAnchorId: number = 0;
      let appendAnchorY: number = 0;
      if (prependAnchorId === 0 && this.didInitialScroll && !this.atBottom &&
        appendBreaksAnchor(this.groups, groups)) {
        const visibleIndex: number = this.curStartIdx;
        if (visibleIndex >= 0 && visibleIndex < this.groups.length) {
          appendAnchorId = this.groups[visibleIndex].head.id;
          try {
            appendAnchorY = this.scroller.getItemRect(visibleIndex).y;
          } catch (e) {
            appendAnchorY = 0;
          }
          logW(`[AppendAnchor] hold id=${appendAnchorId} idx=${visibleIndex} y=${appendAnchorY}` +
            ` rows=${this.groups.length}->${groups.length}`);
        }
      }
      this.messages = list;
      this.messageListRevision++;
      this.reconcileMessageActionTargets(list);
      this.visibleGroupCount = groups.length;
      if (this.viewerMsgId !== 0 &&
        list.findIndex((m: MessageEntry): boolean => m.id === this.viewerMsgId) < 0) {
        this.closeViewer();
      }
      if (firstMessageStage) {
        this.publishInitialMessageGroups(groups);
      } else {
        this.publishMessageGroups(groups);
      }
      if (firstMessageStage && groups.length === 0) {
        // There is no bubble that can drive the coordinated presentation.
        // Reveal the resolved empty/error surface now. Non-empty histories are
        // released only by scheduleInitialTimelinePresentation(), keeping the
        // header, composer, and first real bubble in the same render frame.
        this.cancelInitialMessageTransitionSettle();
        this.initialMessageTransitionSettled = true;
      } else if (!firstMessageStage && !this.initialMessageTransitionSettled &&
        !this.initialMessageStageActive) {
        // Message-link/search/thread entries set didInitialScroll before their
        // around-target history arrives because pendingJumpId owns positioning.
        // They intentionally bypass bottom/unread staging, so they also need a
        // direct presentation completion path. Release chrome in the same
        // state publication as the resolved timeline (including an empty/error
        // result) without issuing another scroll that could override the jump.
        this.cancelInitialMessageTransitionSettle();
        this.initialMessageTransitionSettled = true;
      }
      // 翻译和媒体窗口原来只挂在 onScrollIndex 上 —— 进页面不滑动就永远不
      // 触发（用户报的"这个页面不会自动翻译"），新消息到达也一样。数据一变
      // 就按当前视口驱动一次；curStartIdx/curEndIdx 在首帧前是 -1，此时用
      // 首屏兜底，滑动事件来了会立刻纠正。
      this.driveVisibleWork();
      this.fillViewportIfNeeded();
      this.musicQueue.settlePending(list);
      // 复位跑在发布之后：this.groups 此刻已经是新快照，按消息 id 找得到锚点行
      // 的新下标。restorePrependAnchor 内部是一个 setTimeout(0) + 代次守卫，
      // 跳转/贴底这些更强的定位意图会把它作废。
      if (prependAnchorId > 0) {
        this.restorePrependAnchor(this.groups, prependAnchorId, prependAnchorY);
      } else if (appendAnchorId > 0) {
        // 复位走的是和向上那侧同一个 restoreScrollAnchor：setTimeout(0) + 代次
        // 守卫，跳转/贴底这些更强的定位意图会把它作废。
        this.restoreAppendAnchor(this.groups, appendAnchorId, appendAnchorY);
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
          this.glueBottom('L1153');
          setTimeout((): void => {
            if (actionSeq === this.scrollActionSeq) {
              this.glueBottom('L1156');
              this.refreshAtBottom();
            }
          }, 60);
        } else {
          const resumeIndex: number = groupIndexOf(groups, this.resumeScrollMessageId);
          this.atBottom = false;
          if (resumeIndex >= 0) {
            this.restoreScrollAnchor(resumeIndex, this.resumeScrollItemY);
          } else {
            this.glueBottom('L1166');
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
      const fillPending: boolean = this.store !== null && this.store.isInitialFillPending();
      if (!positionHandled && !this.didInitialScroll && list.length > 0) {
        // First real page: jump to the first unread message (Android-style);
        // fully-read chats land at the bottom. (Never anchor on
        // last_read_inbox_message_id here — it only tracks incoming messages,
        // so with an outgoing tail it points at a stale mid-history position.)
        this.didInitialScroll = true;
        this.lastMaxId = maxId;
        const fu: number = this.store !== null ? this.store.getFirstUnreadId() : 0;
        // 落点判定在 util/initialAnchor（6 条测），两个分支各自的理由写在那里。
        const anchor: InitialAnchor = initialAnchorOf(
          fu, fu > 0 ? groupIndexOf(groups, fu) : -1,
          (index: number): number => groups[index].head.id);
        this.firstUnreadId = anchor.dividerId;
        // 首屏定位的落点诊断。**未读分支原来一条日志都没有**，只有底部分支
        // 打 glueBottom，于是"没跳到未读"和"压根没落定"在日志上长得一模一样，
        // 排查时分不开——正是这次浪费掉一轮的原因。
        logW(`[Anchor] latch fu=${fu} kind=${anchor.kind} index=${anchor.index}` +
          ` rows=${groups.length} fillPending=${fillPending}`);
        if (anchor.kind === ANCHOR_UNREAD) {
          // 两个标志必须一起动，各自挡一个已经发生过的问题，见 util 里的说明。
          this.atBottom = false;
          this.stayAtUnread = anchorLatchesBottom(anchor);
          // The initial-message performance path has only just published
          // placeholder rows here. An immediate scroll alone can be swallowed
          // before List layout; beginInitialUnreadLanding reissues it after the
          // real anchor row is laid out and recomputes the index after backfill.
          this.beginInitialUnreadLanding();
        } else {
          this.glueBottom('L1220');
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
        if (notifyKind === 'update') {
          // 诊断（issue #62）：新消息到了，跟不跟随只取决于这三个标志。用户
          // 报的现象是"手滑到底之后新消息不跟随，点箭头到底就跟随"——两条路
          // 的差别一定落在这三个之一，打出来就不用猜了。
          logW(`[Follow62] atBottom=${this.atBottom} stayAtUnread=${this.stayAtUnread}` +
            ` viewerOpen=${this.viewerMsgId !== 0}` +
            ` hasMoreNewer=${this.store !== null && this.store.getHasMoreNewer()}` +
            ` endIdx=${this.curEndIdx} rows=${this.groups.length}`);
        }
        // 新消息到达且最后一条已在底部可见：跟随，并解除未读闩。闩防的是缩略图
        // 这类原地通知把分界线贴底滑走（下面那一支仍受它约束）；新消息把内容往上
        // 顶是官方行为，不该被它挡住——真机日志：atBottom=true stayAtUnread=true 不跟随。
        if (notifyKind === 'update' && this.atBottom && this.viewerMsgId === 0) {
          this.stayAtUnread = false;
          this.glueBottom('L1242');
        }
      } else if (this.didInitialScroll && this.atBottom && !this.stayAtUnread && this.viewerMsgId === 0
        && (this.store === null || !this.store.getHasMoreNewer())) {
        // In-place content growth (thumbnails, reply quotes, forward headers
        // filling in async) changes row heights; when the user is at the
        // bottom, stay glued there instead of letting the tail drift. Never
        // glue while unloaded newer pages exist — being at the window's edge
        // there is NOT the live tail, and gluing chain-loads every page.
        // Also never move the underlying list while the media viewer is open.
        this.glueBottom('L1252');
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
        this.glueBottom('L1263');
        setTimeout(() => {
          if (actionSeq === this.scrollActionSeq) {
            this.glueBottom('L1266');
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
            this.saveMediaTo(getContext(this) as common.UIAbilityContext, pe.videoPath, true,
              pe.videoFileName, this.pendingGallerySaveToFiles);
          } else if (this.mediaEntryIsVideo(pe) && pe.videoFailed) {
            this.pendingGallerySaveId = 0;
            promptAction.showToast({ message: $r('app.string.cp_video_download_failed'), duration: 1800 });
          } else if (this.mediaEntryIsPhoto(pe) && pe.photoFullPath !== '') {
            this.pendingGallerySaveId = 0;
            this.saveMediaTo(getContext(this) as common.UIAbilityContext, pe.photoFullPath, false,
              '', this.pendingGallerySaveToFiles);
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
        logW(`[Jump80] pending land target=${jumpTargetId} idx=${jg} rows=${groups.length}`);
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
              this.flashAtIndex(jg2, jumpTargetId);
            }
          }, 80);
        }
      }
      // Empty/error chats never start message admission, while populated chats
      // reach this call again after the staged release completes. The method's
      // store/stage guards make both paths converge without a timer race.
      this.scheduleComposerEditorMount();
    });
    this.unsubSub = store.subscribeSubtitle((s: string) => {
      this.subtitle = s;
      this.fetchHeaderEmojiStatus();
    });
    this.unsubHeaderTitle = store.subscribeHeaderTitle((t: string) => {
      // Fallback header for chats not yet in ChatStore (e.g. opened by t.me link).
      if (t !== '') {
        if (this.threadRootId === 0 && this.forumTopicId === 0) {
          this.title = this.headerTitleFor(t);
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
        // 新键盘到了就让它占位，但只在这块高度空着时——用户正开着抽屉或
        // 正在打字，都不该被一条异步到达的消息把输入区换掉。
        this.applyBottomSlot(this.composerFocused
          ? this.bottomSlot : claimIfFree(this.bottomSlot, SLOT_REPLY_KB));
      }
      this.replyKeyboard = kb;
      if (kb === null) {
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
      //
      // issue #80 诊断：搜索结果点进来落点不对，而这条链一个埋点都没有，报告人
      // 导的日志看不出断在哪一步。开→加载→落点→高亮各记一行。
      logW(`[Jump80] open chat=${this.chatId} jumpTo=${jumpTo} search=${this.searchMode}`);
      this.didInitialScroll = true;
      this.pendingJumpId = jumpTo;
      store.open(jumpTo);
    } else if (this.threadRootId > 0) {
      // Comment thread: start at the TOP — the root post — not the newest reply.
      this.didInitialScroll = true;
      this.pendingJumpId = this.threadRootId;
      store.open(this.threadRootId);
    } else {
      // 记住的浏览位置（issue #98）。未读优先：有未读时交给未读锚点，官方也是
      // 这个顺序；只有「没有未读」才落回上次看到的地方。
      const remembered: number = rememberedChatPosition(this.chatId, this.threadRootId);
      if (remembered > 0) {
        this.pendingJumpId = remembered;
        store.open(remembered);
      } else {
        store.open();
      }
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
  // 手动滑动消息列表就收起键盘。
  //
  // 判据是 listTouchActive（手指正按在列表上），不是"发生了滚动"——程序性
  // 滚动同样会触发 onScrollStart：发完消息贴底、点引用跳转、点「↓」回底部
  // 都是。那些时候把键盘收掉，用户接着想再打一条就得重新点输入框。
  //
  // 只在键盘确实立着时才动手。stopEditing 在没有焦点时是空操作，但白跑一次
  // 就意味着每一次滑动都要过一遍输入法的 IPC。
  private dismissKeyboardOnUserScroll(): void {
    if (!this.listTouchActive || this.keyboardH <= 0) {
      return;
    }
    this.composerController.stopEditing();
    this.composerFocused = false;
  }

  private scheduleComposerEditorMount(): void {
    if (this.composerEditorReady || this.composerMountScheduled) {
      return;
    }
    const store: MessageStore | null = this.store;
    if (this.initialMessageStageActive || store === null ||
      store.getInitialHistoryState() === 'loading' || store.isInitialFillPending()) {
      return;
    }
    this.composerMountScheduled = true;
    const seq: number = ++this.composerMountSeq;
    this.getUIContext().postDelayedFrameCallback(new ChatPageFrameCallback((): void => {
      if (seq !== this.composerMountSeq || this.composerEditorReady) {
        return;
      }
      this.composerMountScheduled = false;
      const currentStore: MessageStore | null = this.store;
      if (this.initialMessageStageActive || currentStore === null ||
        currentStore.getInitialHistoryState() === 'loading' || currentStore.isInitialFillPending()) {
        return;
      }
      this.composerEditorReady = true;
    }), INITIAL_MESSAGE_RELEASE_DELAY_MS);
  }

  private activateComposerEditor(): void {
    // Automatic mounting remains outside the transition-critical path, but a
    // user tap always wins over that scheduler. Replace the text shell now and
    // focus the real TextArea on the next task, after its keyed node exists.
    if (!this.composerEditorReady) {
      this.composerMountSeq++;
      this.composerMountScheduled = false;
      this.composerEditorReady = true;
    }
    // An early user tap must never wait for the coordinated visual reveal.
    this.cancelInitialMessageTransitionSettle();
    this.initialMessageTransitionSettled = true;
    setTimeout((): void => {
      focusControl.requestFocus('chat_composer');
    }, 0);
  }

  private activateInitialChrome(action: () => void): void {
    // Lightweight header controls are not decorative: the first tap promotes
    // the full header and then performs the requested action against it.
    this.cancelInitialMessageTransitionSettle();
    this.initialMessageTransitionSettled = true;
    setTimeout((): void => { action(); }, 0);
  }

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
  // @Param 喂给它（源头仍是 AppStorage，经 ChatPageChrome 透传）。isAnimation
  // 传 false：这是页面级闸门，动图本来就
  // 不参加竞选，由 MessageBubble.isPlaySlot()/isAlbumCellPlaySlot() 兜底。
  private playSlotsEnabled(): boolean {
    return shouldCompete(this.autoplayVideo, this.powerSaving, this.reduceAnimations, false);
  }

  // 三个开关任一变化：关掉就立刻把正在播的那条停掉（reset() 会把播放位置空，
  // 订阅者把 playSlotKey 清成 ''，气泡的 VideoBubbleSurface 随之卸载 →
  // StreamingVideoPlayer.aboutToDisappear → release() → session.close()，
  // 播放和下载一起停）；重新打开则补一次判定让它自然重新选出来。
  @Monitor('powerSaving', 'reduceAnimations', 'autoplayVideo')
  private onAutoplayPolicyChanged(): void {
    if (!this.playSlotsEnabled()) {
      this.clearSlotTick();
      this.playSlots.reset();
      return;
    }
    this.armPlaySlotSettle();
  }

  private handleHidden(): void {
    // 页面离开时必须清零，否则标志留在 true、别处的动画被误伤。
    setScrollActive(false);
    // 跳走了就是解析成功了：闸门开，加载态收掉，免得退回来还亮着。
    endLinkNav();
    this.cancelInitialMessageTransitionSettle();
    this.pageVisible = false;
    this.syncChatTgsGate();
    this.hiddenSinceMs = Date.now();
    this.captureHiddenAnchor();
    // 页面不可见时停表，回来时补一次即时值再续上。
    this.clearNowSecTimer();
    // 切走（含被查看器等页面盖住）立刻停播放位——不能等 aboutToDisappear，
    // 那要等到组件真被销毁才会跑，用户已经在别的页面上等了半天下载还在跑。
    this.clearSlotTick();
    this.playSlots.suspend();
    // shared 池不随本页销毁：离开之前先把每个桶收到上限内，免得跨会话累积。
    this.capMessageReuseBuckets();
  }

  private handleWillHide(): void {
    // onHidden is delivered after the outgoing transition has already begun.
    // Stop the expensive moving-page work at onWillHide so the incoming page
    // does not composite against a live TGS/video timeline underneath it.
    this.cancelInitialMessageTransitionSettle();
    this.pageVisible = false;
    this.syncChatTgsGate();
    this.clearNowSecTimer();
    this.clearSlotTick();
    this.playSlots.suspend();
  }

  private handleShown(): void {
    this.pageVisible = true;
    this.armInitialMessageTransitionSettle();
    this.scheduleInitialTimelinePresentation();
    this.scheduleChatTgsResume();
    // 回到这一页说明上一次链接解析已经有了结局（开了页又退回来，或者只弹了
    // 个提示），闸门必须开——否则那个链接会一直卡在加载态直到看门狗到点。
    endLinkNav();
    // onPageHide 只 suspend() 了播放位：候选表还在，被清掉的是当前播放位和
    // 驻留计时。回到这个页面时几何没变、onVisibleAreaApproximateChange 不会
    // 再触发，候选表也就不会被重新灌满——保留候选正是为了这一刻还能选得出
    // 来。armPlaySlotSettle() 里的 resume() 按此刻重新起算驻留，稳住 400ms
    // 后自然选出播放位。
    this.armPlaySlotSettle();
    // The list changed while this page was hidden. See hiddenListDirty: the
    // framework applies hidden-period notifications incompletely, so rebuild
    // its key table from the dataset before the user can see mismatched rows.
    const hiddenMs: number = this.hiddenSinceMs > 0 ? Date.now() - this.hiddenSinceMs : -1;
    this.hiddenSinceMs = 0;
    const wasBackgrounded: boolean = this.appWentBackground;
    this.appWentBackground = false;
    // 两条触发路径：隐藏期间数据变过，或者应用整个进过后台。后者即便数据
    // 没变也必须重建——框架的 key 表在窗口回收后就不可信了。
    if (this.hiddenListDirty || wasBackgrounded) {
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

  private cancelInitialMessageTransitionSettle(): void {
    if (this.initialMessageReleaseTimer !== -1) {
      clearTimeout(this.initialMessageReleaseTimer);
      this.initialMessageReleaseTimer = -1;
    }
  }

  private armInitialMessageTransitionSettle(): void {
    if (this.initialMessageTransitionSettled) {
      return;
    }
    this.cancelInitialMessageTransitionSettle();
    this.initialMessageReleaseTimer = setTimeout((): void => {
      this.initialMessageReleaseTimer = -1;
      if (!this.pageVisible) {
        return;
      }
      // This used to be an unconditional 640 ms fallback. When TDLib needed
      // longer, it exposed the header/composer while the timeline was still
      // empty, so messages visibly arrived afterwards. A non-empty timeline
      // has one authoritative release point: scheduleInitialTimelinePresentation.
      if (this.messageLoadState === 'loading' || this.visibleGroupCount > 0 ||
        this.initialMessageStageActive || this.initialTimelineMasked) {
        return;
      }
      this.initialMessageTransitionSettled = true;
    }, INITIAL_MESSAGE_TRANSITION_SETTLE_MS);
  }

  aboutToDisappear(): void {
    releaseMessageReuseHost();
    // Invalidate the staged-row and composer frame callbacks. The page may be
    // popped while either delayed task is queued.
    this.initialMessageStageSeq++;
    this.initialMessageStageActive = false;
    this.initialMessagePendingGroups = null;
    this.initialMessageRevealCount = 0;
    this.initialMessageStageScheduledSeq = 0;
    this.initialTimelinePresentationSeq++;
    this.initialTimelinePresentationScheduledSeq = 0;
    this.cancelInitialMessageTransitionSettle();
    if (this.chatTgsResumeTimer !== -1) {
      clearTimeout(this.chatTgsResumeTimer);
      this.chatTgsResumeTimer = -1;
    }
    this.pageVisible = false;
    this.chatTgsScrollActive = false;
    this.chatTgsStageSettling = true;
    this.syncChatTgsGate();
    this.composerMountSeq++;
    this.composerMountScheduled = false;
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

  private topCardShouldShow(): boolean {
    // Pinned/live information is optional chrome. If its background probe
    // fails while TDLib is reconnecting and there is no confirmed content,
    // don't turn that transient transport problem into a persistent banner.
    return this.pinnedPreview !== '' ||
      (this.liveGroupCallId > 0 && this.liveCallIsActive) ||
      this.topCardLoadingVisible;
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
      logE(`ChatPage.refreshVideoChat getChat failed: ${e.message}`);
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
      logE(`ChatPage.getGroupCall failed: ${error.message}`);
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
        logE(`ChatPage.enterLiveStream failed: ${error.message}`);
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
      logE(`ChatPage live confirmation failed: ${JSON.stringify(error)}`);
    });
  }

  // True-bottom detection off the scroller's end edge, not the visible index
  // range: a single tall last message can be scrolled within without changing
  // any index, so an index-based check leaves atBottom stuck true and the glue
  // keeps snapping back down. Frozen while the media viewer is open so the
  // underlying chat position is stable when the preview closes.
  // 诊断：屏宽本该恒定，任何变化都值得记一笔——气泡摊平那类问题第一个要
  // 排除的就是它。变化极少，不会刷日志。
  @Monitor('screenW')
  private onScreenWidthChanged(): void {
    if (Math.abs(this.screenW - this.lastScreenW) > 0.5) {
      logW(`screenW ${Math.round(this.lastScreenW)} -> ${Math.round(this.screenW)}`);
      this.lastScreenW = this.screenW;
    }
  }

  // 判定本身在 util/atBottom（10 条测）：那里记着两条上线过的 bug——
  // isAtEnd() 瞬时误报导致把用户从中间拽到最新，以及拿陈旧行号否决导致的自锁死。
  private refreshAtBottom(): void {
    const scrollerAtEnd: boolean = this.viewerMsgId !== 0 ? false : this.scroller.isAtEnd();
    const hasMoreNewer: boolean = this.store !== null && this.store.getHasMoreNewer();
    const verdict: string = atBottomVerdict({
      viewerOpen: this.viewerMsgId !== 0,
      imeTailPinned: this.imeTailPinned,
      scrollerAtEnd: scrollerAtEnd,
      visibleEndIdx: this.curEndIdx,
      indexGroupsLen: this.indexGroupsLen,
      groupsLen: this.groups.length,
      hasMoreNewer: hasMoreNewer
    });
    if (verdict === AT_BOTTOM_KEEP) {
      return;
    }
    const next: boolean = verdict === AT_BOTTOM_YES;
    if (this.atBottom !== next) {
      // 诊断（issue #62）：报告人给的复现极精确——点右下角箭头到底之后，新消息
      // 会自动跟随；自己手滑到底就不会。两条路的差别只可能落在这四个输入之一，
      // 但光看代码分不出是哪个。**只在翻转时打**，稳态不打：那是每次滚动帧都
      // 会走的路，逐次记会把环形缓冲刷满。
      logW(`[Bottom62] ${this.atBottom}->${next} scrollerAtEnd=${scrollerAtEnd}` +
        ` endIdx=${this.curEndIdx} idxLen=${this.indexGroupsLen} rows=${this.groups.length}` +
        ` hasMoreNewer=${hasMoreNewer} imePinned=${this.imeTailPinned}`);
      this.atBottom = next;
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
        this.glueBottom('L2057');
      }
    }, 0);
    setTimeout((): void => {
      if (seq !== this.imeLayoutSeq || !this.imeTailPinned) {
        return;
      }
      this.glueBottom('L2064');
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
    this.glueBottom('L2078');
  }

  @Monitor('keyboardH')
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
  @Monitor('viewerMsgId')
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
  private handleBackPressed(): boolean {
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
      logE(`ChatPage.fetchHeaderEmojiStatus failed: ${e.message}`);
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
    // skip the group scan, date formatting and @Local writes; only refresh the
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
    if (idx !== pinnedShownIndex(this.pinnedCycle, this.pinnedCount)) {
      this.pinnedCycle = idx;
      if (idx < previews.length) {
        this.pinnedPreview = previews[idx];
      }
    }
  }

  // Tap the pinned banner: jump to the pinned message it currently shows.
  // Once at/above the oldest pinned message, tapping wraps back to the bottom.
  private onPinnedTap(): void {
    const store = this.store;
    if (store === null) {
      return;
    }
    // 这一下该做什么，判定在 util/pinnedJump（10 条测）——尤其是"转到最后
    // 一条且已经滚过它就循环回最新"那条规则。
    const action: PinnedTap = pinnedTapAction({
      busy: this.pinnedJumpBusy,
      loadState: this.pinnedLoadState,
      pinnedIds: store.getPinnedIds(),
      cycle: this.pinnedCycle,
      topVisibleId: this.curStartIdx >= 0 && this.curStartIdx < this.groups.length
        ? this.groups[this.curStartIdx].head.id : 0
    }, (messageId: number): number => groupIndexOf(this.groups, messageId));

    if (action.kind === PINNED_IGNORE) {
      return;
    }
    if (action.kind === PINNED_RETRY) {
      store.refreshPinned();
      promptAction.showToast({ message: $r('app.string.cp_resyncing_pinned'), duration: 1200 });
      return;
    }
    if (action.kind === PINNED_EMPTY) {
      this.pinnedPreview = '';
      this.pinnedCount = 0;
      return;
    }
    this.startPinnedJumpGuard(2500);
    this.prepareUserJump();
    if (action.kind === PINNED_LATEST) {
      this.scrollToLatest();
      this.startPinnedJumpGuard(TOP_CARD_ACTION_GUARD_MS);
      return;
    }
    if (action.kind === PINNED_JUMP) {
      this.scroller.scrollToIndex(action.index, false, ScrollAlign.START);
      this.flashAtIndex(action.index);
      this.startPinnedJumpGuard(TOP_CARD_ACTION_GUARD_MS);
      return;
    }
    const targetId: number = action.targetId;
    this.pendingJumpId = targetId;
    store.loadAround(targetId, (found: boolean): void => {
      if (!found && this.pendingJumpId === targetId) {
        this.pendingJumpId = 0;
        this.finishPinnedJump();
        this.store?.refreshPinned();
        promptAction.showToast({ message: $r('app.string.cp_pinned_unavailable'), duration: 1500 });
      }
    });
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
    // 诊断：用户报"999+ 却滑不动"，而日志里 loadOlder 一次都没被调用过——
    // 需要看清是没被叫、还是被 olderArmed 挡住、还是 store 拒绝。
    if (this.olderArmed && this.store !== null) {
      const started = this.store.loadOlder();
      if (started || !this.store.getHasMoreOlder()) {
        this.olderArmed = false;
      }
    }
  }

  // 内容不足一屏时主动补页。
  //
  // 向上分页全靠滚动事件驱动（onReachStart / onScrollIndex 里 start<=4），
  // 可内容铺不满一屏时列表根本滚不动，这两个事件永远不来，于是卡在初始那点
  // 内容上——用户看到的就是"999+ 却滑不动"。平板尤其容易中招：屏幕更高，
  // 要更多行才铺得满。
  //
  // 判据用"最后一行是否可见"：onScrollIndex 报的可见末行已经是最后一行，
  // 说明整份数据都在屏幕上、列表滚不动。此时不能等下一次滚动，得自己敲门。
  private fillViewportIfNeeded(): void {
    if (this.store === null || !this.store.getHasMoreOlder()) {
      return;
    }
    if (this.groups.length === 0 || this.groups.length >= ChatPage.FILL_VIEWPORT_MAX_ROWS) {
      return;
    }
    // 首帧之前 curEndIdx 是 -1，那时还不知道能看见多少，交给后续的滚动/数据
    // 变化再判一次。
    if (this.curEndIdx < 0 || this.curEndIdx < this.groups.length - 1) {
      return;
    }
    this.olderArmed = true;
    this.maybeLoadOlder();
  }

  // 只有闸在膛上、且视口确实往下走过，才再取一页。见 util/pageGate。
  private maybeLoadNewer(end: number): void {
    if (this.store === null) {
      return;
    }
    const gate: PageGate = this.newerGate;
    // 诊断：向下预取跑飞过两次，判据本身要能看见——armed 是不是真的合上了，
    // 推动 end 的是用户还是程序性位移。
    //
    // 只在弱闸放行（end 越过上次开枪位置）时打：这一支同时覆盖"打成了"和
    // "被 armed 挡住"两种结果，正是要看的两格；底部区里每次 onScrollIndex
    // 都打会把环形缓冲刷满，最该看的那段反而被挤掉。
    if (end > gate.firedAtEnd) {
      logW(`[NewerFire] end=${end} rows=${this.groups.length} firedAt=${gate.firedAtEnd}` +
        ` armed=${gate.armed} touch=${this.listTouchActive} userScroll=${this.listUserScrollActive}` +
        ` deferredLeft=${this.countDeferredRows()}`);
    }
    if (!canFirePageGate(gate, end)) {
      return;
    }
    const started: boolean = this.store.loadNewer();
    if (started || !this.store.getHasMoreNewer()) {
      this.newerGate = firedPageGate(gate, end);
    }
  }

  // [NewerFire] 用：还剩多少行是首屏占位。用循环而不是 filter，这行日志在
  // 底部区里会反复打，不该每次都拷一份数组出来。
  private countDeferredRows(): number {
    let count: number = 0;
    for (const row of this.groups) {
      if (row.initialDeferred === true) {
        count++;
      }
    }
    return count;
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

  // A newer page is appended after the current window. The list is
  // end-anchored (stackFromEnd), so the append alone pushes the visible content
  // upward; put the same message back under the user's finger.
  private restoreAppendAnchor(groups: AlbumGroup[], messageId: number, itemY: number): void {
    const targetIndex: number = groupIndexOf(groups, messageId);
    if (targetIndex < 0) {
      logW(`[AppendAnchor] lost id=${messageId} rows=${groups.length}`);
      return;
    }
    logW(`[AppendAnchor] restore id=${messageId} idx=${targetIndex} y=${itemY}` +
      ` rows=${groups.length}`);
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
  }

  private applyResolvedHeaderChat(chat: TdObject, seq: number): void {
    if (seq !== this.headerResolveSeq) {
      return;
    }
    const resolvedTitle = (chat['title'] as string | undefined) ?? '';
    if (resolvedTitle !== '') {
      if (this.threadRootId === 0 && this.forumTopicId === 0) {
        this.title = this.headerTitleFor(resolvedTitle);
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
      this.refreshIsBot(this.headerPeerUserId, seq);
      this.refreshHeaderAvatarAnimation(type);
    } else if (typeName === 'chatTypeBasicGroup') {
      this.isBotChat = false;
      this.headerKind = 'group';
      this.headerIdentityResolved = true;
      this.isGroup = true;
      this.isChannel = false;
      this.refreshHeaderAvatarAnimation(type);
      // 必须在 isGroup 赋值**之后**：refreshAdminLabels 开头就按 !isGroup 早退，
      // 原来这行在赋值之前，普通群（非超级群）的管理员标签从来没取到过。
      this.refreshAdminLabels();
    } else if (typeName === 'chatTypeSupergroup') {
      this.isBotChat = false;
      this.isChannel = (type!['is_channel'] as boolean | undefined) ?? false;
      this.headerKind = this.isChannel ? 'channel' : 'group';
      this.headerIdentityResolved = true;
      this.isGroup = true;
      this.refreshAdminLabels();
      this.refreshHeaderAvatarAnimation(type);
    } else if (typeName === 'chatTypeSecret') {
      // 密聊对面不可能是机器人。
      this.isBotChat = false;
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
          logE(`ChatPage.getSecretChat header failed: ${error.message}`);
        });
      }
    }
    this.headerState = resolvedTitle !== '' || this.title !== '' ? 'ready' : 'error';
    this.headerLoadError = this.headerState === 'error' ? str('cp_chat_unavailable') : '';
    this.fetchHeaderEmojiStatus();
  }

  // Header title/subtitle wording lives in chatHeaderPresentation, where the
  // "cached title beats a pending load" and error-fallback rules are tested.
  // 和自己的私聊就是「我的收藏」。TDLib 对它没有任何标记，标题是自己的昵称、
  // 头像是自己的头像；判据只能是 chat.id === 自己的 user id（见 ChatStore）。
  private isSavedMessagesChat(): boolean {
    const entry = getChatStore().entryOf(this.chatId);
    return entry !== undefined && entry.isSavedMessages;
  }

  // 标题的统一出口：三处赋值都先过这里，「我的收藏」在这一处换掉就够了。
  private headerTitleFor(chatTitle: string): string {
    return this.isSavedMessagesChat() ? str('cl_saved_messages') : chatTitle;
  }

  private chatHeaderTitleNow(chatTitle: string): string {
    return chatHeaderTitle({
      chatTitle: this.headerTitleFor(chatTitle),
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
      logE(`ChatPage.resolveHeaderIdentity failed: ${error.message}`);
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
          logE(`ChatPage.getSupergroup membership failed: ${e.message}`);
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
          logE(`ChatPage.getBasicGroup membership failed: ${e.message}`);
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
      logE(`ChatPage.getChat membership failed: ${e.message}`);
    });
  }

  private applyMembershipStatus(status: TdObject | undefined): void {
    const type: string = (status?.['@type'] as string | undefined) ?? '';
    if (type === '') {
      return;
    }
    const rights = status?.['rights'] as TdObject | undefined;
    // 判定本身在 util/membershipState（有单测）：几条规则都不直观——被限制但
    // 仍在群里照样能发言、频道订阅者只读、频道管理员还要看有没有发帖权。
    const next: string = membershipStateOf({
      statusType: type,
      isMember: (status?.['is_member'] as boolean | undefined) ?? false,
      isChannel: this.isChannel,
      canPostMessages: (rights?.['can_post_messages'] as boolean | undefined) ?? false
    });
    this.membershipState = next;
    if (!membershipLosesComposer(next)) {
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
    this.applyComposerMode(idleComposer());
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
      logE(`ChatPage.joinChat failed: ${e.message}`);
      promptAction.showToast({ message: $r('app.string.cp_join_failed'), duration: 2000 });
    });
  }

  // Mark read up to the bottom-most visible message, so only what the user has
  // actually scrolled past gets marked read (entering without scrolling leaves
  // the rest unread).
  // 视口最底下那条真实消息的 id。系统行没有 member id，往回走到最近的真消息。
  private bottomVisibleId(end: number): number {
    if (end < 0 || end >= this.groups.length) {
      return this.curBottomId;
    }
    for (let i: number = end; i >= 0; i--) {
      const id: number = this.groups[i].head.id;
      if (id > 0) {
        return id;
      }
    }
    return this.curBottomId;
  }

  // 每次视口变化后更新返回状态。两件事：读到哪了（只前进），以及用户是不是
  // 自己滚回了最新——后者意味着这趟"返回"他已经自己完成，整套关系作废。
  private syncReturnState(): void {
    // 手动滑到（或越过）某个返回点，那一层就出栈——和按「↓」返回是同一件事。
    // 落地宽限期内不判：刚跳走时视口还停在返回点上，不设防会立刻把刚压进去
    // 的那层弹掉，一步都退不回去。
    if (Date.now() >= this.jumpLandingUntil) {
      this.returnState = dropReachedJumps(this.returnState, this.curBottomId);
    }
    if (this.atBottom) {
      if (Date.now() >= this.jumpLandingUntil) {
        this.returnState = reachedLatest();
      }
      return;
    }
    this.returnState = advanceRead(this.returnState, this.curBottomId);
  }

  // 「↓」这一下该去哪。显隐也读它：没有可返回的位置就不该出现。
  private returnTarget(): ReturnTarget {
    return nextReturnTarget(this.returnState, this.curBottomId, this.atBottom);
  }

  private onScrollFabTap(): void {
    const target: ReturnTarget = this.returnTarget();
    if (target.kind === RETURN_JUMP) {
      this.returnState = popJump(this.returnState);
      this.jumpToMessageId(target.messageId);
      return;
    }
    if (target.kind === RETURN_READ) {
      this.jumpToMessageId(target.messageId);
      return;
    }
    this.scrollToLatest();
  }

  // 诊断：视口明明停在中段却触发了"贴底"。正常贴底不打——那是每次新消息
  // 到达都会走的路，逐次记会把环形缓冲刷满，导出日志时最该看的那段反而被
  // 挤掉。只在自相矛盾时打：说自己在底部，可见的最后一行却离末尾很远。
  private glueBottom(tag: string): void {
    if (this.curEndIdx >= 0 && this.groups.length - this.curEndIdx > 3) {
      logW(`glueBottom ${tag} atBottom=${this.atBottom} endIdx=${this.curEndIdx}` +
        ` rows=${this.groups.length} stayUnread=${this.stayAtUnread}`);
    }
    this.scroller.scrollEdge(Edge.Bottom);
  }

  private markVisibleRead(end: number): void {
    if (this.store === null || end < 0 || end >= this.groups.length) {
      return;
    }
    // 往回找第一条"真实"消息行、以及"是不是实时尾部"，两个判定都在
    // util/readMarking（8 条测）——已读是高水位，报高了就吞掉没看过的消息。
    const maxId: number = newestVisibleMessageId(
      this.groups.length, (index: number): number[] => this.groups[index].memberIds, end);
    if (maxId > 0) {
      this.store.markViewed(maxId);
      // 本地摘角标只在**确实站在实时尾部**时做。
      //
      // markReadLocally 自己只能拿会话列表快照里的 lastMessageId 作参照，那个
      // 值可能慢一拍；只凭它判断"读到最新了"，用户停在中段也可能满足条件，
      // 角标被提前摘掉而下面还有新消息。"最新"的权威在 MessageStore：
      // hasMoreNewer 为假 + 最后一组已可见，才是真尾部。
      //
      // 这个错还不会自愈——0 一旦写进缓存，若该会话此后没有任何更新，TDLib
      // 不会再下发一次把它纠回来。
      if (isAtLiveTail(end, this.groups.length, this.store.getHasMoreNewer())) {
        getChatStore().markReadLocally(this.chatId, maxId);
      }
    }
  }

  // A tapped in-message link: Telegram links (t.me/<name>, t.me/<name>/<msgId>,
  // @<name>) resolve via TDLib and open the target chat inside the app, jumped
  // to the specific message when the link points to one; everything else opens
  // in the system browser.
  // 机器人命令是 Telegram 里的可点实体：点一下立刻发出去，并共用输入框那把
  // 发送锁，所以连点不会排出重复的两条。
  private sendBotCommand(command: string): void {
    const store: MessageStore | null = this.store;
    if (store === null || this.composerSending) {
      return;
    }
    const replyId = this.replyToId;
    this.atBottom = true;
    this.stayAtUnread = false;
    this.withSendLock((): Promise<void> => store.sendAsync(command, replyId).then((): void => {
      if (this.replyToId === replyId) {
        this.clearReply();
      }
    }).catch((e: TdError): void => {
      logE(`ChatPage.botCommand failed: ${e.message}`);
      promptAction.showToast({ message: $r('app.string.cp_command_failed'), duration: 1600 });
    }));
  }

  // 点了消息里的链接。分派本身（走哪一路、载荷是什么）在
  // util/messageLinkAction，有单测；这里只负责执行。
  // 外部链接的「打开 / 复制」选择。beginLinkNav 的闸门在调用前已经过了，
  // 无论选什么（包括点空白取消）都要把忙碌态收掉，否则那段链接文字会一直
  // 呼吸下去。
  private offerExternalLink(url: string): void {
    promptAction.showActionMenu({
      title: url.length > 60 ? url.substring(0, 57) + '…' : url,
      buttons: [
        { text: $r('app.string.lk_open'), color: '#3390EC' },
        { text: $r('app.string.mb_copy_url'), color: '#3390EC' }
      ]
    }).then((result: promptAction.ActionMenuSuccessResponse): void => {
      if (result.index === 0) {
        openTelegramLink(getContext(this) as common.UIAbilityContext, url, true);
        return;
      }
      endLinkNavIf(url);
      copyPlainText(url, str('link_copied'));
    }).catch((): void => {
      endLinkNavIf(url); // 点空白取消
    });
  }

  private onLinkTap(url: string): void {
    const action: LinkAction = linkActionOf(url);
    if (action.kind === LINK_NONE) {
      return;
    }
    if (action.kind === LINK_COMMAND) {
      this.sendBotCommand(action.text);
      return;
    }
    if (action.kind === LINK_COPY) {
      copyPlainText(action.text, str('cp_number_copied'));
      return;
    }
    if (action.kind === LINK_HASHTAG) {
      const params: Record<string, Object> = { 'query': action.text };
      navigateToSearch(params);
      return;
    }
    if (action.kind === LINK_USER) {
      const params: Record<string, Object> = { 'userId': action.userId };
      // 曾经是 router.pushUrl('pages/profile/ProfilePage')——ProfilePage 迁成
      // HdsNavDestination 并从 main_pages.json 摘出后整页路由跳不动，走漏斗。
      navigateToProfile(params);
      return;
    }
    // 从这里往下每一条分支都要往返一次服务器才知道该开哪一页。网络一慢，
    // 用户看不到反馈就会再点，同一个群于是被开出好几层。闸门放行一次、
    // 挡住其余，并把这个 url 广播出去让那段文字自己表现成加载中。
    if (!beginLinkNav(url)) {
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
      // 纯外部网页链接：弹一个「打开/复制」的选择，而不是直接开——用户点链接
      // 的意图经常只是想拿到地址。Telegram 内部链接（进群/贴纸包/消息跳转）
      // 不走这里，照旧直接开。
      this.offerExternalLink(url);
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
            this.flashAtIndex(gidx, msgId);
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
        endLinkNavIf(url);
        return;
      }
      const params: Record<string, Object> = { 'chatId': chatId };
      if (msgId !== undefined && msgId > 0) {
        params['jumpTo'] = msgId;
      }
      navigateToChat(params, 'content').catch(logChatNavFailure);
      endLinkNavIf(url);
    }).catch((e: TdError) => {
      logE(`ChatPage.getMessageLinkInfo failed: ${e.message}`);
      openTelegramLink(getContext(this) as common.UIAbilityContext, url, true);
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
    // 发送者过滤必须跟着一起清：留着的话下一次普通关键词搜索会被悄悄限定在
    // 那个人身上，用户完全看不出为什么搜不到。
    this.searchSenderId = 0;
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
    // 关键词为空时通常没什么可搜的，但**按发送者筛是例外**：空 query + sender_id
    // 正是 TDLib 列出"此人在本会话的全部消息"的用法（「查看历史」走这条）。
    if (q === '' && this.searchSenderId === 0) {
      return;
    }
    const seq = ++this.searchSeq;
    const req: TdRequest = { '@type': 'searchChatMessages' };
    req['chat_id'] = this.chatId;
    req['query'] = q;
    if (this.searchSenderId > 0) {
      const sender: TdObject = { '@type': 'messageSenderUser' };
      sender['user_id'] = this.searchSenderId;
      req['sender_id'] = sender;
    }
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
      // 从全局搜索点某条消息进来：那一条就是跳转目标，已经落到位了，这次
      // 搜索只是为了把 ∧/∨ 的列表填上——**任何情况下都不再跳**。
      //
      // 原来是 indexOf 找不到锚点就 jumpToResult(0)。两边匹配口径不同时这就
      // 会把用户刚落对的位置甩开（issue #80：全局搜索命中「opengram，还有最近
      // 那个」，会话内搜索用同一串词只回了另一条含 "opengram" 的消息，页面
      // 于是自己滑走）。锚点是用户的选择，按 id 序插进结果里，不推翻它。
      if (this.searchAnchorId !== 0) {
        const merged: AnchorMerge = mergeAnchorHit(this.searchResults, this.searchAnchorId);
        this.searchAnchorId = 0;
        this.searchResults = merged.results;
        this.searchIdx = merged.index;
        if (merged.inserted) {
          this.searchTotal = this.searchTotal + 1;
        }
        return;
      }
      this.jumpToResult(thenJumpTo);
    }).catch((e: TdError) => {
      logE(`ChatPage.searchChatMessages failed: ${e.message}`);
    });
  }

  private jumpToResult(idx: number): void {
    if (idx < 0 || idx >= this.searchResults.length) {
      return;
    }
    this.searchIdx = idx;
    this.onReplyTap(this.searchResults[idx]); // same jump + double-blink flash
  }

  // ∧ / ∨ 的决策交给纯函数（util/searchPaging，有单测）：下标越界、总数为 0、
  // 已加载等于总数、空结果集——这几个边界混在异步回调之间最容易写错。
  private applySearchStep(step: SearchStep): void {
    if (step.action === SEARCH_JUMP) {
      this.jumpToResult(step.index);
    } else if (step.action === SEARCH_FETCH) {
      this.runSearch(step.fromMessageId, step.index);
    }
  }

  private searchOlder(): void {
    this.applySearchStep(stepOlder(this.searchResults, this.searchIdx, this.searchTotal));
  }

  private searchNewer(): void {
    this.applySearchStep(stepNewer(this.searchIdx));
  }

  // 点引用块：先把"跳走之前在哪"压进返回栈，再跳。
  // 返回点取**被点的那条消息**，不是视口底部那条：引用块可能在屏幕靠上，
  // 跨屏的长消息里两者能差一整屏。fromId 为 0（拿不到）时退回视口底部。
  private onReplyTap(messageId: number, fromId: number = 0): void {
    if (messageId <= 0) {
      return;
    }
    this.returnState = pushJump(this.returnState, fromId > 0 ? fromId : this.curBottomId);
    this.jumpLandingUntil = Date.now() + JUMP_LANDING_GRACE_MS;
    this.prepareUserJump();
    const gidx = groupIndexOf(this.groups, messageId);
    if (gidx >= 0) {
      this.scroller.scrollToIndex(gidx, false, ScrollAlign.START);
      this.flashAtIndex(gidx, messageId);
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
  //
  // targetId：这一跳要照亮的那条消息。下标是**现在**算出来的，而矩形要等
  // 150ms 布局稳了才取——这中间往上补进一页历史，同一个下标就指向别人了
  // （issue #80 的视频里，高亮框落在目标上方五行的另一条上）。给了 id 就在
  // 取矩形前重新解析一次下标；没有 id（置顶跳转那种只有下标的调用）沿用旧行为。
  private flashAtIndex(gidx: number, targetId: number = 0): void {
    const seq = ++this.flashSeq;
    setTimeout(() => {
      if (seq !== this.flashSeq) {
        return;
      }
      let idx = gidx;
      if (targetId > 0) {
        const re: number = groupIndexOf(this.groups, targetId);
        if (re < 0) {
          return;
        }
        idx = re;
      }
      let top = 0;
      let height = 0;
      try {
        const rect = this.scroller.getItemRect(idx);
        top = rect.y;
        height = rect.height;
      } catch (e) {
        return; // row not laid out (jump superseded) — skip the highlight
      }
      if (height <= 0) {
        return;
      }
      logW(`[Jump80] flash idx=${idx} target=${targetId} top=${Math.round(top)} h=${Math.round(height)} rows=${this.groups.length}`);
      this.flashTargetIdx = idx;
      this.flashTargetId = targetId;
      this.flashTop = top;
      this.flashHeight = height;
      this.flashShown = true;
      this.flashAlpha = 0;
      this.runBlink(seq, 2);
    }, 150);
  }

  // 把高亮层重新对到目标行上。行还在就跟着它走；找不到（被滚出窗口、数据换了）
  // 就收掉，别留一条悬空的色带。有 id 就按 id 重解下标——prepend 会让下标漂移。
  private syncFlashRect(): void {
    if (!this.flashShown) {
      return;
    }
    let idx: number = this.flashTargetIdx;
    if (this.flashTargetId > 0) {
      idx = groupIndexOf(this.groups, this.flashTargetId);
    }
    if (idx < 0) {
      this.cancelFlash();
      return;
    }
    let top: number = 0;
    let height: number = 0;
    try {
      const rect = this.scroller.getItemRect(idx);
      top = rect.y;
      height = rect.height;
    } catch (e) {
      this.cancelFlash();
      return;
    }
    if (height <= 0) {
      return;
    }
    if (Math.abs(top - this.flashTop) > 0.5 || Math.abs(height - this.flashHeight) > 0.5) {
      this.flashTop = top;
      this.flashHeight = height;
    }
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
    // 每一拍开始前先对一次位置（issue #80）。
    this.syncFlashRect();
    animateTo({
      duration: this.chatEffectDuration(KEY_POWER_EFFECT_REPLY, 320), curve: Curve.EaseInOut
    }, () => { this.flashAlpha = 1; });
    setTimeout(() => {
      if (seq !== this.flashSeq) {
        return;
      }
      this.syncFlashRect();
      animateTo({
        duration: this.chatEffectDuration(KEY_POWER_EFFECT_REPLY, 320), curve: Curve.EaseInOut
      }, () => { this.flashAlpha = 0; });
      setTimeout(() => { this.runBlink(seq, remaining - 1); }, 340);
    }, 340);
  }

  // Any new touch cancels the highlight: it is viewport-anchored, and while a
  // programmatic shift is re-synced by syncFlashRect, a user drag moves faster
  // than the blink cadence and the band would visibly lag the row.
  private cancelFlash(): void {
    this.flashSeq++;
    this.flashShown = false;
    this.flashAlpha = 0;
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
      navigateToChat(params, 'content').catch(logChatNavFailure);
    }).catch((e: TdError) => {
      logE(`ChatPage.getMessageThread failed: ${e.message}`);
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
    // 挂载查看器必须在 animateTo 闭包里：geometryTransition 只在动画闭包中
    // 改变绑定节点的存在性时才会做几何过渡，直接赋值就是瞬间出现（关闭那侧
    // 早就这么写了，见 closeViewer）。
    animateTo({
      duration: this.chatEffectDuration(KEY_POWER_EFFECT_BLUR, 300),
      curve: Curve.Friction
    }, (): void => {
      this.viewerMsgId = messageId;
    });
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

  // 见 appDark 的说明：store 注入的 isDarkMode 回调是实时读的，

  // 所以这里只要让它重新解析一次就够，不必重新订阅。

  @Monitor('appDark')
  private onAppDarkChanged(): void {

    if (this.bgStore !== null) {

      this.bgStore.refresh();

    }

  }


  @Monitor('langEpoch')
  private onLanguageEpochChanged(): void {
    // A hidden page can't be trusted to apply even a full rebuild; re-issue on show.
    if (!this.pageVisible) {
      this.hiddenListDirty = true;
      return;
    }
    this.rebuildAllRows();
  }

  @Monitor('appIsForeground')
  private onAppForegroundChanged(): void {
    // 停留在会话页切后台时必须 closeChat，否则 TDLib 认为用户正在看这个
    // 会话，不会为它生成任何通知。
    if (this.appIsForeground) {
      this.store?.resumeOpenChat();
    } else {
      this.appWentBackground = true;
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
      logE(`ChatPage.getCallbackQueryAnswer failed: ${e.message}`);
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
          logE(`ChatPage.sendPaymentForm failed: ${e.message}`);
          promptAction.showToast({ message: $r('app.string.cp_payment_failed'), duration: 1800 });
        });
      }).catch((): void => {
        this.setPaidMediaPending(messageId, false);
      });
    }).catch((e: TdError): void => {
      this.setPaidMediaPending(messageId, false);
      logE(`ChatPage.get paid media payment form failed: ${e.message}`);
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
    copyPlainText(code, str('cp_code_copied'));
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
    navigateToChat(params, 'content').catch(logChatNavFailure);
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
    // 曾经是一个 url 字符串变量 + 末尾一次 router.pushUrl；两张资料页都迁成了
    // HdsNavDestination，改成用 openUserProfile 记住该开哪一张，末尾分发到对应
    // 漏斗。分支条件与参数一字未改。
    let openUserProfile: boolean = false;
    let params: Record<string, Object>;
    if (uid > 0) {
      openUserProfile = true;
      params = { 'userId': uid };
    } else if (this.headerIdentityResolved ||
      (this.store !== null && this.store.getIsGroup())) {
      openUserProfile = false;
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
    // 迁移前这里是 router.pushUrl(...).catch(...)：失败时提前解掉防连点闸门并
    // 弹「打不开资料页」。漏斗是同步 void，推进一个已注册的栈不会失败，那个
    // catch 分支因此不再可达——闸门仍由上面那个 CHAT_HEADER_NAV_GUARD_MS 的
    // 定时器按时解掉，行为与「跳转成功」那一路完全一致。栈没注册时的回退路径
    // 由 profileNav 内部记日志。
    if (openUserProfile) {
      navigateToProfile(params);
    } else {
      navigateToChatProfile(params);
    }
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
    // 判定在 util/mentionDraft（mentionQueryOf，9 条测）：那里说明了为什么放宽
    // 到非 ASCII，以及 @ 的位置和终止条件各自挡的是什么（issue #95）。
    const at: string | null = mentionQueryOf(v);
    if (at !== null && this.isGroup && !this.isChannel) {
      this.refreshMentions(at);
      return;
    }
    this.mentionItems = [];
    this.refreshInlineQuery(v);
    this.refreshStickerSuggestions(v);
  }

  // Bots can expose a Mini App on their menu button — surface it as a composer
  // icon that opens the app in the in-app browser.
  // 对方是不是机器人。先清成 false 再异步确认：换会话时留着上一个会话的
  // true，新会话空历史的一瞬间会错误地亮出「开始」。
  // 群里发送者名字旁边那枚身份标签的数据源。
  //
  // 一次 getChatAdministrators 就够：管理员是少数，且变动很少。拿到后发进
  // 旁路通道，由每条消息旁边的 SenderRoleTag 自己订阅——不写进 MessageEntry，
  // 否则名单到货会让整页每行的 key 都变、列表整体重建。
  //
  // 频道不取：频道消息的署名走的是 author_signature，不是成员身份。
  // 头部动态头像。full info 的 photo 是 chatPhoto，可选的 animation 是一小段
  // MP4；有就下下来交给 AvatarView（它自己看省电开关决定放不放）。
  private refreshHeaderAvatarAnimation(type: TdObject | undefined): void {
    this.headerAvatarAnimPath = '';
    const chatId: number = this.chatId;
    const typeName: string = type !== undefined
      ? ((type['@type'] as string | undefined) ?? '') : '';
    let req: TdRequest | null = null;
    if (typeName === 'chatTypePrivate') {
      req = { '@type': 'getUserFullInfo' };
      req['user_id'] = (type!['user_id'] as number | undefined) ?? 0;
    } else if (typeName === 'chatTypeSupergroup') {
      req = { '@type': 'getSupergroupFullInfo' };
      req['supergroup_id'] = (type!['supergroup_id'] as number | undefined) ?? 0;
    } else if (typeName === 'chatTypeBasicGroup') {
      req = { '@type': 'getBasicGroupFullInfo' };
      req['basic_group_id'] = (type!['basic_group_id'] as number | undefined) ?? 0;
    }
    if (req === null) {
      return;
    }
    getTdClient().send(req, 15000).then((full: TdObject): void => {
      if (this.chatId !== chatId) {
        return; // 期间换了会话
      }
      const photo = (full['photo'] as TdObject | undefined)
        ?? (full['personal_photo'] as TdObject | undefined)
        ?? (full['public_photo'] as TdObject | undefined);
      const anim = photo !== undefined ? (photo['animation'] as TdObject | undefined) : undefined;
      const file = anim !== undefined ? (anim['file'] as TdObject | undefined) : undefined;
      const fileId = file !== undefined ? ((file['id'] as number | undefined) ?? 0) : 0;
      if (fileId <= 0) {
        return;
      }
      const dl: TdRequest = { '@type': 'downloadFile' };
      dl['file_id'] = fileId;
      dl['priority'] = 2;
      dl['synchronous'] = true;
      getTdClient().send(dl, 30000).then((f: TdObject): void => {
        if (this.chatId !== chatId) {
          return;
        }
        const local = f['local'] as TdObject | undefined;
        const path = local !== undefined ? ((local['path'] as string | undefined) ?? '') : '';
        if (path !== '') {
          this.headerAvatarAnimPath = path;
        }
      }).catch((e: TdError): void => {
        logE(`ChatPage.headerAvatarAnimation download failed: ${e.message}`);
      });
    }).catch((e: TdError): void => {
      // 拿不到 full info 就保持静态头像，不打扰。
      logE(`ChatPage.headerAvatarAnimation fullInfo failed: ${e.message}`);
    });
  }

  private refreshAdminLabels(): void {
    if (this.chatId === 0 || !this.isGroup || this.isChannel) {
      return;
    }
    const chatId: number = this.chatId;
    // 先清掉这个群的旧标签：管理员被撤销时名单里不会再有他，只发布新名单
    // 的话那枚旧标签会一直挂着。
    clearSenderRoles(chatId);
    getAdministrators(chatId).then((rows: AdminRow[]): void => {
      if (this.chatId !== chatId) {
        return; // 期间换了会话
      }
      for (const row of rows) {
        publishSenderRole(senderRoleKey(chatId, row.userId),
          adminLabelOf(row.isCreator, row.customTitle));
      }
    }).catch((error: TdError): void => {
      // 拿不到就不显示标签，不打扰用户——这不是功能主线。
      logE(`ChatPage.getAdministrators failed: ${error.message}`);
    });
  }

  private refreshIsBot(userId: number, seq: number): void {
    this.isBotChat = false;
    if (userId <= 0) {
      return;
    }
    const req: TdRequest = { '@type': 'getUser' };
    req['user_id'] = userId;
    getTdClient().send(req).then((user: TdObject): void => {
      if (seq !== this.headerResolveSeq) {
        return;
      }
      const type = user['type'] as TdObject | undefined;
      const typeName: string = type !== undefined ? ((type['@type'] as string | undefined) ?? '') : '';
      this.isBotChat = typeName === 'userTypeBot';
    }).catch((error: TdError): void => {
      logE(`ChatPage.getUser isBot failed: ${error.message}`);
    });
  }

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
      logE(`ChatPage.openBotMiniApp failed: ${e.message}`);
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
      logE(`ChatPage.sendInlineResult failed: ${e.message}`);
      promptAction.showToast({ message: $r('app.string.cp_inline_send_failed'), duration: 1600 });
    });
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
      logE(`ChatPage.loadBotCommands failed: ${e.message}`);
      this.allCommands = [];
      this.commandItems = [];
      this.commandLoadState = 'error';
      this.commandLoadError = str('cp_commands_failed');
      this.botMenuAvailable = false;
    });
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
      // 和上面共用同一个判定——两边不一致会出现「面板该弹却把结果丢掉」。
      if (seq !== this.mentionSeq || mentionQueryOf(this.draft) === null) {
        return;
      }
      this.mentionItems = items;
    });
  }

  // 本次草稿里"按名字"提及过的成员。没有用户名的人，@ 出去只是一串普通
  // 文字，服务器识别不了、对方收不到提及通知——发送时要靠这份记录补上
  // textEntityTypeMentionName 实体（见 mentionEntities）。
  private pendingNameMentions: NameMention[] = [];

  // 记下一次"按名字"的提及。有用户名的走 @username，服务器自己认得，不必记。
  private rememberNameMention(item: MentionItem, name: string): void {
    if (item.username !== '' || name === '' || item.userId <= 0) {
      return;
    }
    const known: boolean = this.pendingNameMentions.some(
      (m: NameMention): boolean => m.userId === item.userId && m.name === name);
    if (!known) {
      this.pendingNameMentions = [...this.pendingNameMentions, { name, userId: item.userId }];
    }
  }

  // Replace the trailing '@token' with the chosen member.
  private pickMention(item: MentionItem): void {
    const idx = this.draft.lastIndexOf('@');
    const head = idx >= 0 ? this.draft.substring(0, idx) : this.draft;
    this.draft = `${head}${mentionToken(item.name, item.username)} `;
    this.rememberNameMention(item, item.name.trim());
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
      this.rememberNameMention(item, name.trim());
      this.mentionItems = [];
      setTimeout((): void => { focusControl.requestFocus('chat_composer'); }, 0);
    });
  }

  private pickCommand(item: CommandItem): void {
    this.draft = commandLabel(item);
    this.commandItems = [];
    this.commandMenuOpen = false;
    this.doSend();
  }

  // Viewer "保存到相册": photos save right away (full-res preferred); a video
  // that isn't fully local yet starts its download and saves automatically on
  // completion (see the pendingGallerySaveId check in the store subscription).
  // 保存到相册还是任意文件夹，由菜单里点的是哪一项决定（issue #97/#65）。
  private saveMediaTo(ctx: common.UIAbilityContext, path: string, isVideo: boolean,
    fileName: string, toFiles: boolean): void {
    if (toFiles) {
      const name: string = fileName.trim() !== ''
        ? fileName : path.substring(path.lastIndexOf('/') + 1);
      saveFileToLocal(ctx, path, name);
      return;
    }
    saveMediaToGallery(ctx, path, isVideo);
  }

  private saveViewerMedia(toFiles: boolean): void {
    const e = this.entryById(this.viewerMsgId);
    if (e === null) {
      return;
    }
    const ctx = getContext(this) as common.UIAbilityContext;
    if (this.mediaEntryIsVideo(e)) {
      if (e.videoPath !== '') {
        this.saveMediaTo(ctx, e.videoPath, true, e.videoFileName, toFiles);
      } else {
        this.pendingGallerySaveId = e.id;
        this.pendingGallerySaveToFiles = toFiles;
        if (this.store !== null) {
          this.store.requestVideoDownload(e.id, true, e.videoFailed);
        }
        promptAction.showToast({ message: $r('app.string.cp_video_downloading_save'), duration: 2500 });
      }
      return;
    }
    if (e.photoFullPath !== '') {
      this.saveMediaTo(ctx, e.photoFullPath, false, '', toFiles);
      return;
    }
    if (e.photoFullFileId !== 0) {
      this.pendingGallerySaveId = e.id;
      this.pendingGallerySaveToFiles = toFiles;
      if (this.store !== null) {
        this.store.requestFullPhoto(e.id, e.photoFullFailed);
      }
      promptAction.showToast({ message: $r('app.string.cp_photo_downloading_save'), duration: 2200 });
      return;
    }
    if (e.photoPath !== '') {
      this.saveMediaTo(ctx, e.photoPath, false, '', toFiles);
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
      logE(`ChatPage.openDownloadedFile failed: ${JSON.stringify(caught)}`);
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
    if (m.mediaDownloadActive) {
      // 下载中再点一下 = 暂停（issue #45 子项：下载开始后没法暂停取消）。
      // 已下的部分留着，下次点从断点继续。
      this.pendingFileOpenId = 0;
      this.store.pauseFileDownload(messageId);
      promptAction.showToast({ message: $r('app.string.cp_file_paused'), duration: 1500 });
      return;
    }
    this.pendingFileOpenId = messageId;
    this.store.requestVideoDownload(messageId, true, m.videoFailed);
    promptAction.showToast({
      message: m.videoFailed ? $r('app.string.cp_redownloading_file')
        : $r('app.string.cp_file_download_started'),
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
      // 迁移前是 router.pushUrl(...).catch(弹「打不开联系人」)。漏斗是同步 void，
      // 推进已注册的栈不会失败，那个 toast 分支不再可达；成功路径完全一致。
      navigateToProfile(params);
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
            copyPlainText(vcard, str('cp_contact_copied'));
          }
        }).catch((caught: Object): void => {
          logE(`ChatPage.openSharedContact failed: ${JSON.stringify(caught)}`);
          copyPlainText(vcard, str('cp_contact_copied'));
        });
      } catch (caught) {
        logE(`ChatPage.write shared contact failed: ${caught}`);
        copyPlainText(vcard, str('cp_contact_copied'));
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

  // 清空历史的可行方式由 chat 的两个能力位决定（见 ClearHistoryOptions）。
  // 这里的确认框只有一个执行按钮，所以取破坏性最小的那个可行选项：私聊/普通
  // 群拿到 revoke=false（和以前一样），只能为所有人清的会话（群主的超级群、
  // 活跃密聊）拿到 revoke=true，两个位都为假则返回 undefined、菜单项不出现。
  // 老代码对所有会话硬写 revoke=false，超级群必然报
  // "Can't delete history of X only for self"。
  private clearHistoryChoice(): ClearHistoryOption | undefined {
    const e: ChatEntry | undefined = getChatStore().entryOf(this.chatId);
    if (e === undefined) {
      return undefined;
    }
    const options: ClearHistoryOption[] =
      clearHistoryOptions(e.canDeleteOnlyForSelf, e.canDeleteForAllUsers, e.kind);
    return options.length > 0 ? options[0] : undefined;
  }

  private confirmClearHistory(): void {
    const choice: ClearHistoryOption | undefined = this.clearHistoryChoice();
    if (choice === undefined) {
      return;
    }
    const revoke: boolean = choice.revoke;
    AlertDialog.show({
      message: $r('app.string.cp_clear_history_confirm'),
      autoCancel: true,
      primaryButton: {
        value: $r('app.string.cancel'),
        action: (): void => {}
      },
      secondaryButton: {
        value: str(choice.labelKey),
        fontColor: '#FF3B30',
        action: (): void => {
          const req: TdRequest = { '@type': 'deleteChatHistory' };
          req['chat_id'] = this.chatId;
          req['remove_from_chat_list'] = false;
          req['revoke'] = revoke;
          getTdClient().send(req).then(() => {
            promptAction.showToast({ message: $r('app.string.cp_history_cleared'), duration: 2000 });
          }).catch((e: TdError) => {
            logE(`ChatPage.deleteChatHistory failed: ${e.message}`);
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
            this.goBack();
          }).catch((e: TdError) => {
            logE(`ChatPage.leaveChat failed: ${e.message}`);
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
          this.closeHeaderMenuThen((): void => { confirmStopLiveLocation(); }));
      }
      Divider().color($r('app.color.divider')).strokeWidth(0.7);
      // 总开关开着时这个会话默认就在翻，所以这一项显示「关闭翻译」；总开关
      // 关着时它就是"只翻这个会话"的入口。单条消息的翻译不受这里影响。
      actionMenuRow('sys.symbol.translate',
        this.translationActive() ? str('cp_translate_chat_off') : str('cp_translate_chat_on'),
        false, this.closeHeaderMenuThen((): void => { this.toggleTranslatable(); }));
      if (this.clearHistoryChoice() !== undefined) {
        actionMenuRow('sys.symbol.xmark_circle', str('cp_clear_history'), false,
          this.closeHeaderMenuThen((): void => { this.confirmClearHistory(); }));
      }
      if (this.isGroup && this.membershipState === 'writable') {
        Divider().color($r('app.color.divider')).strokeWidth(0.7);
        actionMenuRow('sys.symbol.trash', this.isChannel ? str('cp_leave_channel') : str('cp_leave_group'), true,
          this.closeHeaderMenuThen((): void => { this.confirmLeaveChat(); }));
      }
    }
    // 262 太宽，菜单项最长的也只占一半，右边空一大片。224 刚好容下最长的一条。
    .width(224)
    .padding({ top: 6, bottom: 6 });
  }

  // Horizontal center (vp, window coords) of the smiley button — the anchor
  // the emoji panel scales out of / back into.
  private emojiBtnCx: number = 48;
  @Local inputBarH: number = 64;
  @Local listViewportH: number = 0;
  // Height of every persistent bottom surface (composer/reply/Bot keyboard or
  // membership/search bar). The List uses it only as END offset: rows still
  // travel behind the floating input, while the final row can clear it.
  @Local bottomChromeH: number = 76;
  private bottomChromeLayoutSeq: number = 0;
  // Measured bot-keyboard height; with the input bar it makes up the bottom
  // chrome the scroll-to-bottom FAB has to clear.
  // 输入框的真实宽度，composerEditorHeight() 拿它做排版约束。
  @Local composerEditorW: number = 0;
  // "Fake" animation: the open/close transition flies an empty white shell;
  // the real panel content (hundreds of emoji + sticker players) mounts only
  // after the animation lands, so frames stay cheap.
  @Local panelContentReady: boolean = false;
  private panelReadySeq: number = 0;

  // 顶栏高度只由结构状态决定。标题、副标题、头像加载状态的变化不再经过
  // onAreaChange 写回状态变量，也就不会把 List.contentStartOffset 一起拖进重排。
  private headerChromeHeight(): number {
    const input: ChatChromeGeometryInput = {
      topSafe: this.topSafe,
      searchMode: this.searchMode,
      pinnedVisible: this.pinnedPreview !== '',
      liveVisible: this.liveGroupCallId > 0 && this.liveCallIsActive,
      loadingVisible: this.topCardLoadingVisible
    };
    return chatChromeHeight(input);
  }

  // 纯函数以 bottomGapOf 引入：裸名在方法体里解析到的是导入而不是本方法
  // （方法必须带 this.），同名并存太容易读错。placeholderOf 同理。
  // 输入框那块位置归谁：空的机器人会话给「开始」，其余交回成员状态。
  // 判定在 util/botStart（有单测），这里只把当前字段喂进去。
  private composerSlot(): string {
    return composerSlotState({
      isBot: this.isBotChat,
      membershipState: this.membershipState,
      loadState: this.messageLoadState,
      visibleGroupCount: this.visibleGroupCount,
      threadRootId: this.threadRootId
    });
  }

  private composerBottomGap(): number {
    return bottomGapOf(this.keyboardH, this.bottomPanelOpen(), this.bottomSafe);
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
    const oneLine: number = COMPOSER_LINE_H + COMPOSER_EDITOR_PAD * 2;
    const cap: number = COMPOSER_LINE_H * COMPOSER_MAX_LINES + COMPOSER_EDITOR_PAD * 2;
    if (this.draft === '' || this.composerEditorW <= 0) {
      return oneLine;
    }
    // 真实测量，不再按"每行 18 个字"硬估。
    //
    // 那个 18 是拍的：一行能装多少字取决于屏宽、字号缩放和中英文混排，在宽屏
    // 上实际只装得下约 15 个，于是第 16 个字文本已经换行、而 ceil(16/18) 仍是
    // 1，盒子要等到第 19 个字才长高——表现为"输到第二行第 4 个字才展开"
    // （Mate 80 Pro Max 稳定复现）。
    //
    // TextArea 本身是自适应内容高度的（不设 height 时），这里之所以还锁着
    // 高度，是因为它的固有最小高度在某些机型/字号下比一行还高，空输入框会
    // 变胖（见下方 .height 调用点的原注释）。所以保留显式高度，只把估算换成
    // measureTextSize —— 它按给定的约束宽度做真实排版，返回的高度已经算好了
    // 换行。
    let measured: number = oneLine;
    try {
      const size: SizeOptions = this.getUIContext().getMeasureUtils().measureTextSize({
        textContent: this.draft,
        fontSize: 15,
        lineHeight: COMPOSER_LINE_H,
        // 左右各 3 的内边距要从可用宽度里扣掉，否则会少算一行。
        constraintWidth: Math.max(1, this.composerEditorW - 6)
      });
      // measureTextSize 返回的是 px。
      measured = px2vp(size.height as number) + COMPOSER_EDITOR_PAD * 2;
    } catch (e) {
      // 量不出来就退回一行，宁可矮也不要抖：TextArea 超出部分自己能滚。
      logE(`composerEditorHeight measure failed: ${(e as Error).message}`);
    }
    return Math.max(oneLine, Math.min(cap, Math.ceil(measured)));
  }

  // 渐变模糊：只在顶部 chrome 那一条区域内从"全糊"过渡到"清晰"。
  // fractionStops 是 [模糊比例, 位置]，位置沿 direction 从 0 到 1；
  // direction 取 Bottom 时 0 就是列表顶端。
  private headerBlurStops(): [number, number][] {
    const viewport: number = this.listViewportH;
    const chromeHeight: number = this.headerChromeHeight();
    if (viewport <= 0 || chromeHeight <= 0) {
      return [[0, 0], [0, 1]];
    }
    // 过渡带正好是 chrome 那一条：列表顶端（也就是屏幕最上沿）全糊，到 bar
    // 的下边缘归零。消息往上滑时是连续糊掉的，不是撞上一条硬边。
    //
    // 上半段是**全糊的平台段**而不是单点：只在位置 0 取 1 的话，全糊处是条
    // 零宽度的线，肉眼看到的最糊程度远达不到 100%。
    const end: number = Math.min(0.6, chromeHeight / viewport);
    return [[1, 0], [1, end * 0.62], [0, end]];
  }

  // 只看省电：这里的顾虑是逐帧实时渲染的功耗，跟"聊天背景特效"是两回事。
  // 先前误用了 backgroundEffectsEnabled()，它还附带自定义背景/特效开关的条件，
  // 会把模糊直接打成 0。
  private headerBlurRadius(): number {
    return !this.powerSaving && this.headerChromeHeight() > 0 ? HEADER_BLUR_RADIUS : 0;
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
          this.glueBottom('L4617');
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
    this.applyBottomSlot(toggleSlot(this.bottomSlot, SLOT_REPLY_KB));
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
    if (show) {
      // 两个底部面板互斥：同一块高度不能有两个主人。
      this.closeAttachPanel();
    }
    const seq = ++this.panelReadySeq;
    // 抽屉是 dock 里的一段布局，出现/消失由 dock 的高度变化带动，这里只管
    // 内容的分帧挂载。
    const settle: number = this.chatEffectDuration(KEY_POWER_EFFECT_MENU, 220);
    if (show) {
      this.emojiPanelClosing = false;
      this.composerFocused = false;
      this.applyBottomSlot(openSlot(this.bottomSlot, SLOT_EMOJI));
      this.showEmojiPanel = true;
      // 收起系统键盘，把这块高度让给抽屉。
      this.composerController.stopEditing();
      if (settle === 0) {
        this.panelContentReady = true;
        return;
      }
      // 先让壳落地，内容下一拍再进来。三个 picker 一次性挂上实测 ~51ms，
      // 和键盘的滑入挤在一起就是开场即掉帧。
      setTimeout(() => {
        if (seq === this.panelReadySeq && this.showEmojiPanel) {
          this.panelContentReady = true;
        }
      }, settle + 20);
    } else {
      this.emojiPanelClosing = true;
      // 卸载重内容和解绑键盘同样要分帧，理由同上：卸掉三个 picker 是 ~51ms，
      // 和键盘的滑出撞在一帧里，动画一开场就掉。先在静止状态下卸掉内容
      // （观感是内容一闪而空），下一帧再对着一个空壳解绑。
      this.panelContentReady = false;
      setTimeout((): void => {
        if (seq !== this.panelReadySeq) {
          return;
        }
        this.showEmojiPanel = false;
        this.emojiPanelClosing = false;
        this.applyBottomSlot(closeSlot(this.bottomSlot, SLOT_EMOJI));
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
      this.applyBottomSlot(closeSlot(this.bottomSlot, SLOT_REPLY_KB));
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
      logE(`ChatPage.copyUriToCache failed: ${e}`);
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
        logE(`ChatPage.replaceMedia failed: ${e.message}`);
        promptAction.showToast({ message: $r('app.string.cp_replace_failed'), duration: 1700 });
      });
    }).catch((): void => { this.mediaPickerOpen = false; });
  }

  private pickMedia(): void {
    if (this.mediaPickerOpen || this.composerSending || this.store === null) {
      return;
    }
    // 选择器自己就按"还能再放几张"限制，好过让用户挑满九张再被截断。
    const room: number = PENDING_MEDIA_MAX - this.pendingMedia.length;
    if (room <= 0) {
      promptAction.showToast({
        message: str('cp_pending_media_full', PENDING_MEDIA_MAX, 0), duration: 2000
      });
      return;
    }
    this.mediaPickerOpen = true;
    const photoPicker = new photoAccessHelper.PhotoViewPicker();
    const opts = new photoAccessHelper.PhotoSelectOptions();
    opts.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_VIDEO_TYPE;
    opts.maxSelectNumber = room;
    photoPicker.select(opts).then((res: photoAccessHelper.PhotoSelectResult) => {
      this.mediaPickerOpen = false;
      if (res.photoUris.length === 0 || this.store === null) {
        return;
      }
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
      // 不直接发：先攒到输入框上方那一条，等用户配完文字再一起发。
      // 追加而不是替换——用户分几次从不同相册挑图是常见操作。超出九张
      // （Telegram 相册上限）时截断并**明确告知截了几张**，不静默丢弃。
      const merged: PendingMediaAppend = appendPendingMedia(this.pendingMedia, items);
      this.pendingMedia = merged.items;
      if (merged.dropped > 0) {
        promptAction.showToast({
          message: str('cp_pending_media_full', PENDING_MEDIA_MAX, merged.dropped),
          duration: 2200
        });
      }
    }).catch((e: Object) => {
      this.mediaPickerOpen = false;
      logE(`ChatPage.pickMedia failed: ${JSON.stringify(e)}`);
      promptAction.showToast({ message: $r('app.string.cp_cannot_open_picker'), duration: 1800 });
    });
  }

  // --- voice recording (mic button) ---
  private startRecording(): void {
    if (this.recordingStarting || this.isRecording || this.store === null) {
      return;
    }
    this.setEmojiPanel(false);
    this.applyBottomSlot(closeSlot(this.bottomSlot, SLOT_REPLY_KB));
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
      logE(`ChatPage.startRecording failed: ${JSON.stringify(e)}`);
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
      logE(`ChatPage.pickAndSendAudio select failed: ${JSON.stringify(e)}`);
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
    withLocationPermission(getContext(this) as common.UIAbilityContext, (): void => {
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
            logE(`ChatPage.sendCurrentLocation failed: ${e.message}`);
            promptAction.showToast({ message: $r('app.string.cp_location_failed'), duration: 2000 });
          });
      })
      .catch((e: BusinessError): void => {
        logE(`ChatPage location permission failed: ${e.message}`);
      });
  }

  // 骰子六选一。原来走 promptAction.showActionMenu，那是系统弹窗，外观完全
  // 由系统定——ActionMenuOptions 里没有模糊或材质字段，套不上玻璃。改成自绘
  // 的 sheet，和翻译面板同一套 blurStyle + systemMaterial。
  // 🎰 老虎机由 DiceBubble 叠 5 层 TGS 渲染。
  private showDiceMenu(): void {
    this.diceSheetOpen = true;
  }

  private sendDiceEmoji(emoji: string): void {
    this.diceSheetOpen = false;
    if (this.store !== null) {
      this.atBottom = true;
      this.store.sendDice(emoji);
    }
  }

  @Builder
  diceSheet() {
    Column() {
      Text($r('app.string.cp_roll_a'))
        .fontSize(15).fontColor(COLOR_TEXT_SECONDARY)
        .margin({ top: 6, bottom: 10 });
      Grid() {
        ForEach(DICE_CHOICES, (d: DiceChoice) => {
          GridItem() {
            Column({ space: 6 }) {
              Text(d.emoji).fontSize(34);
              Text(d.label).fontSize(13).fontColor(COLOR_TEXT_PRIMARY).maxLines(1);
            }
            .width('100%').height(88)
            .justifyContent(FlexAlign.Center)
            .borderRadius(14)
            .backgroundColor($r('app.color.surface_alt'))
            .onClick((): void => { this.sendDiceEmoji(d.emoji); });
          }
        }, (d: DiceChoice) => d.emoji);
      }
      .columnsTemplate('1fr 1fr 1fr')
      .rowsGap(10).columnsGap(10)
      .width('100%').height(186);
    }
    .width('100%')
    // 顶部这 44 是给 bindSheet 自带的关闭按钮让位——它浮在右上角，内容从
    // 顶端开始排就会压在它下面。
    .padding({ left: 16, right: 16, top: 44, bottom: 16 });
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
      logE(`ChatPage.pickAndSendFile select failed: ${JSON.stringify(e)}`);
    });
  }

  // 发送闸门：同一时刻只允许一个发送在途，**且无论成败都必须放行**。
  //
  // 四条发送路径（文本、命令、媒体、编辑）此前各自在 then 和 catch 里复位
  // composerSending，13 个写入点。只要有一条异步分支漏掉复位，输入框就永久
  // 卡在"发送中"——四个守卫都读这一个标志，会一起拒绝后续发送，而且没有任何
  // 出口能把它掰回来（除非退出重进会话）。
  //
  // 用 finally 而不是在两个分支各写一遍：放行不再依赖调用方记得写。调用方
  // 自己的 then/catch 照常挂在 task 上，只是不用再管这个标志。
  private withSendLock(task: () => Promise<void>): void {
    if (this.composerSending) {
      // 静默 return 是"点了没反应"的来源。文本发送已经不走这个闸门了，
      // 剩下三条（媒体、命令、编辑）本来就该一次一件，但至少要说一声。
      promptAction.showToast({ message: $r('app.string.sending'), duration: 1200 });
      return;
    }
    this.composerSending = true;
    task().finally((): void => {
      this.composerSending = false;
    });
  }

  // 把暂存的媒体连同正文一起发出去。正文可以为空——媒体本身就是内容。
  //
  // 和 doSend 的文本路径不同，这里**不能**在发送前就清空暂存：媒体走的是
  // sendMedia 一次请求带全部文件，失败了得把用户挑好的九张还回去，而那些
  // 只存在于这个数组里（文本失败还有 draftSnapshot 兜底）。所以清空放在
  // 成功回调里，期间由 withSendLock 挡住重复点击。
  private sendPendingMedia(): void {
    const store: MessageStore | null = this.store;
    if (store === null || !hasPendingMedia(this.pendingMedia)) {
      return;
    }
    const items: MediaSendItem[] = this.pendingMedia.map(
      (item: PendingMediaItem): MediaSendItem => ({ path: item.path, isVideo: item.isVideo }));
    const captionSnapshot: string = this.draft;
    const caption: string = captionSnapshot.trim();
    const replyId: number = this.replyToId;
    this.commandMenuOpen = false;
    this.atBottom = true;
    this.stayAtUnread = false;
    this.withSendLock((): Promise<void> => store.sendMedia(items, caption, replyId).then((): void => {
      this.pendingMedia = clearPendingMedia();
      if (this.draft === captionSnapshot) {
        this.draft = '';
        this.pendingNameMentions = [];
      }
      if (this.replyToId === replyId) {
        this.clearReply();
      }
    }).catch((e: TdError): void => {
      logE(`ChatPage.sendMedia failed: ${e.message}`);
      promptAction.showToast({ message: $r('app.string.cp_photo_send_failed'), duration: 2000 });
    }));
  }

  private doSend(): void {
    if (this.editingId !== 0) {
      this.commitEdit();
      return;
    }
    // 有暂存媒体就走相册路径，正文当说明。判断放在文本的空串闸门之前——
    // 只挑了图没打字也要能发。
    if (hasPendingMedia(this.pendingMedia)) {
      this.sendPendingMedia();
      return;
    }
    const draftSnapshot: string = this.draft;
    const text: string = draftSnapshot.trim();
    const store: MessageStore | null = this.store;
    // 这里**不再看 composerSending**。它原本横跨整个 TDLib 往返，于是走代理
    // 时输入框会连着几秒既不清空也不接受新的发送，而且两处闸门都是静默
    // return——用户点了没反应、也没有任何提示（issue #47 的"被吞"）。
    //
    // 防重复提交现在由"立刻清空输入框"本身承担：草稿空了，第二次点击在
    // text === '' 这一关就停住了，比一个横跨网络往返的标志可靠得多。
    // 上传媒体的时候照样能发文字，官方端也是这样。
    if (text === '' || store === null) {
      return;
    }
    const replyId: number = this.replyToId;
    const mentionsSnapshot: NameMention[] = this.pendingNameMentions;
    this.commandMenuOpen = false;
    this.atBottom = true;
    this.stayAtUnread = false;
    // 按名字提及的实体在这里生成：偏移必须相对**实际发出去的那串文本**，
    // 所以用 trim 之后的 text，不是原始草稿。
    const entities: TdObject[] = buildMentionEntities(text, this.pendingNameMentions);
    // 清空放在**发送之前**，不等应答。消息本身不用我们伪造回显：TDLib 会先
    // 发 updateNewMessage（自己发的消息在 onNewMessage 里是放行的），列表那边
    // 立刻就有一条 pending 的气泡。
    this.draft = '';
    this.pendingNameMentions = [];
    if (this.replyToId === replyId) {
      this.clearReply();
    }
    this.mentionItems = [];
    this.commandItems = [];
    store.sendAsync(text, replyId, entities).catch((e: TdError): void => {
      logE(`ChatPage.doSend failed: ${e.message}`);
      // 提示语说的是"草稿已保留"，那就真的还回去。但用户可能已经开始写下
      // 一条了——那种情况不覆盖他的输入，只报错。
      if (this.draft === '') {
        this.draft = draftSnapshot;
        this.pendingNameMentions = mentionsSnapshot;
      }
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
        this.applyBottomSlot(closeSlot(this.bottomSlot, SLOT_REPLY_KB));
      }
    }).catch((e: TdError): void => {
      this.replyKeyboardSendingKey = '';
      logE(`ChatPage.replyKeyboard send failed: ${e.message}`);
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

  // 输入框上方那一条的状态机在 util/composerMode（有单测）。所有写入都经过
  // 这里：转换函数算出新状态，这里摊到字段上。**不要再单独改那七个字段**——
  // 回复和编辑共用同一条，分开改必然出现"编辑条盖住回复条、回复却仍生效"
  // 那类互相不知道的状态。
  private applyComposerMode(next: ComposerMode): void {
    this.composerMode = next;
    this.replyToId = next.replyToId;
    this.replyToName = next.replyName;
    this.replyToText = next.replyText;
    this.editingId = next.editingId;
    this.editingKind = next.editingKind;
    this.editingPreview = next.editingPreview;
    this.draftBeforeEdit = next.draftBeforeEdit;
  }

  private clearReply(): void {
    this.applyComposerMode(clearReply(this.composerMode));
  }

  private replySnippet(m: MessageEntry): string {
    return replySnippetOf({
      text: m.text, placeholderLabel: m.placeholderLabel,
      contentType: m.contentType, paidMediaLocked: m.paidMediaLocked
    });
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
    this.applyComposerMode(enterReply(this.composerMode, messageId,
      m.senderName !== '' ? m.senderName : this.title, this.replySnippet(m)));
    this.setEmojiPanel(false);
    this.applyBottomSlot(closeSlot(this.bottomSlot, SLOT_REPLY_KB));
    setTimeout((): void => {
      focusControl.requestFocus('chat_composer');
    }, 0);
  }

  // --- multi-select ---
  // 从消息菜单进多选：选中的是**整行**，不是被长按的那一条。
  //
  // messageSelection 开篇写明的不变量是"一行要么整体选中、要么整体不选"，而
  // 这里原来只放被长按消息的 id。相册行被长按时，那是相册的头一条：行在 UI 上
  // 显示为选中（rowSelected 是"沾上就算"），计数却是 1，接着转发也只发出这一
  // 张——九图相册转发成一张。
  private enterSelect(memberIds: number[]): void {
    ContextMenu.close();
    this.closeReactionSheet();
    this.setEmojiPanel(false);
    this.selecting = true;
    this.selectedIds = toggleRow([], memberIds);
  }

  private exitSelect(): void {
    this.selecting = false;
    this.selectedIds = [];
  }

  private rowSelected(g: AlbumGroup): boolean {
    return rowSelected(this.selectedIds, g.memberIds);
  }

  // Toggle a whole display row (an album row selects all its members).
  private toggleSelectRow(g: AlbumGroup): void {
    if (!rowSelectable(g.head.contentType)) {
      return;
    }
    this.selectedIds = toggleRow(this.selectedIds, g.memberIds);
    if (this.selectedIds.length === 0) {
      this.exitSelect();
    }
  }

  private reconcileMessageActionTargets(list: MessageEntry[]): void {
    if (this.selecting) {
      this.selectedIds = pruneSelection(this.selectedIds,
        list.map((m: MessageEntry): number => m.id));
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
    }).catch((e: Object) => { logE(`ChatPage.copySelected failed: ${JSON.stringify(e)}`); });
  }

  // "同时为对方删除"是一个开关，不是第三个按钮：做成三按钮时用户要在两个
  // 红色危险项之间辨认，容易点错。所以用带复选框的自定义弹窗。
  private deleteSelected(): void {
    const ids: number[] = [...this.selectedIds];
    if (ids.length === 0) {
      return;
    }
    this.openDeleteConfirm(ids);
  }

  // 长按菜单里的单条删除：复用 deleteSelected() 的弹窗逻辑，只是目标 id 只有一个。
  // 不处于多选模式时 doDeleteMessages 内部的 exitSelect() 只是把已经为 false/[]
  // 的 selecting/selectedIds 再赋一次同样的值，是无害的空操作。
  private deleteMessage(messageId: number): void {
    this.openDeleteConfirm([messageId]);
  }

  // 弹窗走 ComponentContent + UIContext.openCustomDialog，不再走
  // CustomDialogController：后者官方明写只在状态管理 V1 中使用，而本页要迁 V2。
  private openDeleteConfirm(ids: number[]): void {
    openDeleteMessagesDialog(this.getUIContext(),
      this.isGroup || this.isChannel ? '' : this.headerText().titleText,
      (revoke: boolean): void => { this.doDeleteMessages(ids, revoke); });
  }

  private doDeleteMessages(ids: number[], revoke: boolean): void {
    const req: TdRequest = { '@type': 'deleteMessages' };
    req['chat_id'] = this.chatId;
    req['message_ids'] = ids;
    req['revoke'] = revoke;
    getTdClient().send(req).then(() => {
      this.exitSelect();
    }).catch((e: TdError) => {
      logE(`ChatPage.deleteMessages failed: ${e.message}`);
      promptAction.showToast({ message: str('cp_delete_failed_msg', e.message), duration: 2000 });
    });
  }

  private copyMessageText(messageId: number): void {
    const m = this.findMsg(messageId);
    if (m === null || m.text === '') {
      promptAction.showToast({ message: $r('app.string.cp_nothing_to_copy'), duration: 1500 });
      return;
    }
    copyPlainText(m.text, str('copied'));
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
      }).catch((e: Object) => { logE(`ChatPage.copyMessageLink failed: ${JSON.stringify(e)}`); });
    });
  }

  // reactionKey：标准 emoji 原样，自定义 emoji 为 'ce:<custom_emoji_id>'。
  // 本会话允许的表情（服务端的规范写法）。我们内置的快捷表情带变体选择符，
  // 服务端的可能不带，差一个码位 TDLib 就判 REACTION_INVALID——所以发之前先换成
  // 它认的那一个。拉一次缓存在页面上，失败就当没有（不拦着用户发）。
  private allowedReactions: string[] = [];
  private allowedReactionsTask: Promise<string[]> | null = null;

  // **要等它回来再发**：第一次点的时候列表还是空的，直接发就等于发我们内置的
  // 原串（带 U+FE0F），必被判 REACTION_INVALID——用户看到的是「第一个表情第一次
  // 永远失败，再点才行」。拉一次缓存在页面上，之后都是同步命中。
  private ensureAllowedReactions(messageId: number): Promise<string[]> {
    if (this.allowedReactions.length > 0) {
      return Promise.resolve(this.allowedReactions);
    }
    const running: Promise<string[]> | null = this.allowedReactionsTask;
    if (running !== null) {
      return running;
    }
    const req: TdRequest = { '@type': 'getMessageAvailableReactions' };
    req['chat_id'] = this.chatId;
    req['message_id'] = messageId;
    req['row_size'] = 8;
    const task: Promise<string[]> = getTdClient().send(req).then((result: TdObject): string[] => {
      const set: AvailableReactionSet = parseAvailableReactions(result);
      this.allowedReactions = set.emojis;
      this.allowedReactionsTask = null;
      return this.allowedReactions;
    }).catch((e: TdError): string[] => {
      // 拉不到就按原串发（可能成功，也可能报错——总比拦着用户强）。
      this.allowedReactionsTask = null;
      logE(`ChatPage.getMessageAvailableReactions failed: ${e.message}`);
      return [];
    });
    this.allowedReactionsTask = task;
    return task;
  }

  private toggleReaction(messageId: number, reactionKey: string, isChosen: boolean): void {
    const store: MessageStore | null = this.store;
    const key: string = `${messageId}_${reactionKey}`;
    if (store === null || this.reactionPendingKey !== '') {
      return;
    }
    ContextMenu.close();
    this.reactionPendingKey = key;
    // 自定义表情（'ce:' 前缀）不做映射：它按 id 走，不涉及变体选择符。
    const custom: boolean = reactionKey.startsWith('ce:');
    const ready: Promise<string[]> = custom
      ? Promise.resolve(this.allowedReactions) : this.ensureAllowedReactions(messageId);
    let sendKey: string = reactionKey;
    ready.then((allowed: string[]): Promise<void> => {
      sendKey = custom ? reactionKey : canonicalReactionEmoji(reactionKey, allowed);
      return store.setReaction(messageId, sendKey, isChosen);
    }).then((): void => {
      if (this.reactionPendingKey === key) {
        this.reactionPendingKey = '';
      }
    }).catch((e: TdError): void => {
      if (this.reactionPendingKey === key) {
        this.reactionPendingKey = '';
      }
      logE(`ChatPage.toggleReaction(${sendKey}) failed: ${e.message}`);
      // 带上服务端的原因：光说「失败」用户没法反馈，我们也查不动。
      promptAction.showToast({
        message: `${str('cp_reaction_failed')} · ${e.message}`, duration: 2200
      });
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
  // 高亮就是那两下蓝色闪烁（flashAtIndex），「↓」的返回也走这里，所以返回
  // 落点同样会闪一下，和点引用跳过去的观感一致。
  private jumpToMessageId(targetId: number): void {
    this.jumpLandingUntil = Date.now() + JUMP_LANDING_GRACE_MS;
    const gidx: number = groupIndexOf(this.groups, targetId);
    logW(`[Jump80] jumpToMessageId target=${targetId} idxInLoaded=${gidx} rows=${this.groups.length}`);
    if (gidx >= 0) {
      this.scroller.scrollToIndex(gidx, false, ScrollAlign.START);
      this.flashAtIndex(gidx, targetId);
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
  // 同名的纯函数以 isTranslationActive 引入：裸名 translationActive 在方法体里
  // 解析到的是导入而不是这个方法（方法必须带 this.），两个名字并存太容易读错。
  private translationActive(): boolean {
    return isTranslationActive(
      this.translateChatsEnabled, this.translateChatOptOut, this.isTranslatable,
      this.translateChatOptIn);
  }

  // 总开关在设置页被改动后，当前页要立刻跟上：开了就把可见范围补翻，
  // 关了就把已经渲染出来的译文收走（服务的缓存留着，再开秒回）。
  @Monitor('translateChatsEnabled')
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

  // 就地翻译一条消息：长按菜单的「翻译」和失败行上的「重试」共用。
  //
  // 先调 service.retry() 清掉失败冷却：TranslationService 失败后有 60 秒静默
  // 期，不清掉的话紧接着的 request() 会被直接挡下、界面上什么都不会发生。
  // 对从没失败过的消息，这一步是无副作用的空操作。
  private translateInline(messageId: number): void {
    const store = this.store;
    if (store === null) {
      return;
    }
    const target: MessageEntry | undefined =
      store.getMessages().find((e: MessageEntry): boolean => e.id === messageId);
    if (target === undefined) {
      return;
    }
    const lang: string = resolveTranslateTarget();
    const service = getTranslationService(getTdClient());
    service.retry(this.chatId, messageId, target.editDate, lang);
    const originalText: string = target.text;
    service.request(this.chatId, messageId, target.editDate, lang,
      (text: string | null): void => {
        if (text !== null && text !== '' && text !== originalText && this.store === store) {
          store.applyTranslation(messageId, lang, text);
        }
      });
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
    const range: VisibleRange = visibleRangeOrFallback(
      this.curStartIdx, this.curEndIdx, this.groups.length, this.listCachedCount);
    this.driveTranslations(range.start, range.end);
    this.syncMediaWindow(range.start, range.end);
    // 同一个道理：数据一变（新消息到达、翻页、被查看器等场景清空候选表后
    // 恢复）就补一次播放位判定，不指望用户正好在这一刻滚动。
    this.armPlaySlotSettle();
  }

  // 把可见行区间换算成消息 id 区间交给 store。外扩几行做缓冲，滑动时不会
  // 因为一行之差反复取消又重下。
  private syncMediaWindow(startIdx: number, endIdx: number): void {
    const store = this.store;
    if (store === null) {
      return;
    }
    // 外扩与夹取在 util/visibleWindow（10 条测）：上界取末行的最后一个成员，
    // 相册一整行多条，取行首会把更新的那几条漏在窗外。
    const w: MediaWindow = mediaWindowRange(
      startIdx, endIdx, this.groups.length,
      (index: number): number => this.groups[index].head.id,
      (index: number): number => {
        const members: number[] = this.groups[index].memberIds;
        return members[members.length - 1];
      });
    if (w.valid) {
      store.setMediaWindow(w.fromId, w.toId);
    }
  }

  // 菜单里那一项永远是"把当前状态反过来"，但落到哪个开关上取决于总开关：
  // 总开关开着时写本地排除名单（纯本地，不会失败）；总开关关着时才走
  // 服务端的 toggleChatIsTranslatable，跟官方客户端保持同一份状态。
  private toggleTranslatable(): void {
    const decision: TranslateToggle = toggleTranslation(
      this.translateChatsEnabled, this.translateChatOptOut, this.isTranslatable,
      this.translateChatOptIn);
    const next: boolean = decision.active;
    if (decision.writesOptOut) {
      this.translateChatOptOut = decision.optOut;
      setTranslateOptedOut(this.chatId, decision.optOut);
      this.afterTranslationToggled(next);
      return;
    }
    const previous: boolean = this.isTranslatable;
    this.isTranslatable = decision.translatable;
    // 本地也记一份：服务端那次写未必落盘（见 translationMode 的说明），
    // 只靠它的话用户下次进来又得手动开一遍。
    this.translateChatOptIn = next;
    setTranslateOptedIn(this.chatId, next);
    this.afterTranslationToggled(next);
    const req: TdRequest = { '@type': 'toggleChatIsTranslatable' };
    req['chat_id'] = this.chatId;
    req['is_translatable'] = next;
    getTdClient().send(req).catch((e: TdError): void => {
      this.isTranslatable = previous;
      logE(`ChatPage.toggleTranslatable failed: ${e.message}`);
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
        logI(`ChatPage.${what} dialog dismissed: ${JSON.stringify(e)}`);
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
        logE(`ChatPage.stopPoll failed: ${e.message}`);
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
        logE(`ChatPage.autoDelete failed: ${e.message}`);
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
        logE(`ChatPage.sendScheduled failed: ${e.message}`);
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
      logE(`ChatPage.togglePin failed: ${e.message}`);
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
  @Local translateSheetOpen: boolean = false;
  @Local translateSheetOriginal: string = '';
  @Local translateSheetText: string = '';
  @Local translateSheetState: string = TRANSLATE_LOADING;
  @Local translateSheetLang: string = '';
  private translateSheetMsgId: number = 0;
  private translateSheetEditDate: number = 0;
  private translateSheetSeq: number = 0;

  // 长按菜单里的「翻译」。原来会弹一个 sheet 单独展示译文，现在改成就地
  // 翻译：进行中/失败/译文都长在气泡里（见 translationChannel 与
  // MessageBubble.translationBlock），和整聊天翻译是同一条路径、同一套缓存。
  // sheet 相关状态与 runSheetTranslation 暂时保留，翻译面板的入口还在用。
  private translateMessage(messageId: number): void {
    const entry: MessageEntry | undefined =
      this.messages.find((m: MessageEntry): boolean => m.id === messageId);
    if (entry === undefined || entry.text.trim() === '') {
      promptAction.showToast({ message: $r('app.string.cp_nothing_to_translate'), duration: 1600 });
      return;
    }
    this.translateInline(messageId);
  }

  private runSheetTranslation(lang: string): void {
    const seq: number = ++this.translateSheetSeq;
    this.translateSheetLang = lang;
    this.translateSheetText = '';
    this.translateSheetState = TRANSLATE_LOADING;
    const service = getTranslationService(getTdClient());
    const msgId: number = this.translateSheetMsgId;
    const editDate: number = this.translateSheetEditDate;
    const original: string = this.translateSheetOriginal;
    const settle = (text: string | null): void => {
      if (seq !== this.translateSheetSeq) {
        return;
      }
      const next: string = sheetStateOf(text, original);
      if (next === TRANSLATE_DONE) {
        this.translateSheetText = text as string;
      }
      this.translateSheetState = next;
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

  // bindSheet 只吃 @Builder，所以留一层薄壳把组件包进去。
  @Builder
  translateSheetBody() {
    TranslateSheet({
      original: this.translateSheetOriginal,
      translated: this.translateSheetText,
      state: this.translateSheetState,
      lang: this.translateSheetLang,
      bottomSafe: this.bottomSafe,
      onPickLang: (): void => { this.pickTranslateSheetLang(); },
      onRetry: (): void => { this.runSheetTranslation(this.translateSheetLang); },
      onCopy: (): void => { this.copySheetTranslation(); }
    });
  }

  private copySheetTranslation(): void {
    const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, this.translateSheetText);
    pasteboard.getSystemPasteboard().setData(data).then((): void => {
      promptAction.showToast({ message: $r('app.string.copied'), duration: 1300 });
    }).catch((): void => {});
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
      logE(`ChatPage.showReactors failed: ${e.message}`);
      promptAction.showToast({ message: $r('app.string.cp_no_reaction_details'), duration: 1600 });
    });
  }

  private closeReactionSheet(): void {
    this.showReactionSheet = false;
    this.reactionTargetId = 0;
  }

  private forwardableMessageIds(ids: number[]): number[] {
    // 查不到的消息给一个不可选的类型，等价于过滤掉——原来的写法是
    // m !== null 单独判一次，合进 contentTypeOf 之后语义一样。
    return forwardableIds(ids, (id: number): string => {
      const m: MessageEntry | null = this.findMsg(id);
      return m !== null ? m.contentType : 'hidden';
    });
  }

  // Only decides *whether* the picker opens and what it will forward — the chat
  // list, filtering and the forwardMessages request live in ForwardSheet.
  // 「保存消息」：直接转发到收藏（和自己的会话），不弹选择面板。
  //
  // Telegram 里"收藏"就是和自己的私聊，chat_id 等于自己的 user id。拿不到
  // （getMe 还没回）时不静默失败——给一句提示，否则用户点了没反应会以为卡了。
  private saveToSavedMessages(messageIds: number[]): void {
    const me: number = getActiveTdUserId();
    if (me === 0) {
      promptAction.showToast({ message: $r('app.string.mb_forward_failed'), duration: 1800 });
      return;
    }
    // 保留来源抬头：收藏里回头看，得认得出这条是谁在哪儿说的。
    forwardDirect(getTdClient(), this.chatId, me, messageIds, this.threadRootId, false)
      .then((sent: number): void => {
        promptAction.showToast({
          message: sent > 0 ? $r('app.string.mb_saved_done') : $r('app.string.mb_forward_failed'),
          duration: 1600
        });
      });
  }

  // 「复读」：把内容原样再发一遍到本会话。目标就是当前 chatId，话题模式下带上
  // 话题号，否则会落到群的主时间线而不是用户正在看的话题里。
  //
  // asCopy=true —— 发副本、不带"转发自"抬头，看上去就是自己说的。群里的"复读"
  // 本来就是这个意思；带着抬头的那种官方转发两步就能做到，不必再加一项。
  private repeatMessages(messageIds: number[]): void {
    forwardDirect(getTdClient(), this.chatId, this.chatId, messageIds, this.threadRootId, true)
      .then((sent: number): void => {
        if (sent === 0) {
          promptAction.showToast({ message: $r('app.string.mb_forward_failed'), duration: 1800 });
        }
      });
  }

  // 「查看历史」：在本会话里筛出这个人的全部消息。
  //
  // 复用会话内搜索的整套界面（结果计数、上/下一条、跳转高亮），只是把
  // sender_id 填上、query 留空——TDLib 支持这种组合。
  private viewSenderHistory(senderId: number): void {
    if (senderId <= 0) {
      return;
    }
    this.searchSenderId = senderId;
    this.searchQuery = '';
    this.searchMode = true;
    this.runSearch(0, 0);
  }

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
  liveEntryPressedStyle() {
    .backgroundColor('#E93652')
    .opacity(0.82)
    .scale({ x: 0.94, y: 0.94 })
  }

  // 底色交给材质：材质渲染在 backgroundColor **之下**，填一层不透明的
  // surface 就把它整个盖住了。overlayGlassFill 在材质可用时返回透明，
  // 不可用的设备上返回可见的降级色。
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
    .backgroundColor(this.accent())
    .opacity(1)
    .scale({ x: 1, y: 1 })
  }

  @Styles
  composerPrimaryPressedStyle() {
    .backgroundColor('#287BC8')
    .opacity(0.84)
    .scale({ x: 0.92, y: 0.92 })
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
    this.goBack();
  }

  // Search owns the complete top bar. Keeping the regular avatar/title beside
  // the field squeezed group/channel queries into a narrow trailing slot and
  // made the mode look like an accessory instead of navigation state.
  // Suggestion panel above the input bar: group members for a trailing '@',
  // bot commands for a leading '/'.
  private startEdit(messageId: number): void {
    // 编辑改的是旧消息，发媒体是发新消息，发送键做哪件事说不清。宁可拒绝，
    // 也不静默丢掉用户刚挑好的九张图（对照 enterEdit 会清掉待回复——那里
    // 丢的只是一个引用）。
    if (hasPendingMedia(this.pendingMedia)) {
      promptAction.showToast({
        message: $r('app.string.cp_pending_media_blocks_edit'), duration: 2000
      });
      return;
    }
    const msg = this.store?.getMessages().find(
      (m: MessageEntry): boolean => m.id === messageId);
    const captionTypes: string[] = ['photo', 'video', 'file', 'audio', 'voice'];
    if (msg === undefined || !msg.isOutgoing ||
      (msg.contentType !== 'text' && captionTypes.indexOf(msg.contentType) < 0)) {
      return;
    }
    const editKind: string = msg.contentType === 'text' ? 'text' : 'caption';
    const preview: string = msg.text !== '' ? msg.text
      : (editKind === 'caption' ? str('cp_no_caption') : '');
    this.applyComposerMode(
      enterEdit(this.composerMode, messageId, editKind, preview, this.draft));
    this.draft = msg.text;
  }

  private cancelEdit(): void {
    if (this.editingId === 0) { return; }
    const restored: string = draftToRestore(this.composerMode);
    this.applyComposerMode(cancelEdit(this.composerMode));
    this.draft = restored;
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
    const editKind: string = this.editingKind;
    this.withSendLock((): Promise<void> => (editKind === 'caption'
      ? store.editCaptionAsync(editId, text) : store.editTextAsync(editId, text)
    ).then((): void => {
      if (this.editingId === editId) {
        const restored: string = draftToRestore(this.composerMode);
        this.applyComposerMode(cancelEdit(this.composerMode));
        this.draft = restored;
      }
    }).catch((e: TdError): void => {
      logE(`ChatPage.commitEdit failed: ${e.message}`);
      promptAction.showToast({
        message: e.message.indexOf('MESSAGE_NOT_MODIFIED') >= 0
          ? $r('app.string.cp_no_change') : $r('app.string.cp_edit_failed'),
        duration: 1800
      });
    }));
  }

  private replyKbVisible(): boolean {
    return replyKeyboardVisible(
      this.membershipState, this.replyKeyboard !== null, this.replyKbCollapsed);
  }

  private composerPlaceholder(): string {
    return placeholderOf(this.typingLabel, this.replyKbVisible(),
      this.replyKeyboard !== null ? this.replyKeyboard.placeholder : '');
  }

  // Bot custom reply keyboard: full-width button rows under the input bar.

  // Replaces the composer for public groups/channels the current user hasn't
  // joined yet, and carries the mute toggle for read-only channels.
  //
  // Shaped exactly like the composer — a floating rounded capsule inset from
  // both edges, not a full-width bar with a divider. It occupies the same slot
  // and swaps with the composer as membership changes, so anything else reads
  // as the bottom of the screen changing shape.

  // 附件抽屉的内容。高度写死而不是自适应：抽屉要顶起输入框和聊天内容，
  // 那个高度得在内容挂上来之前就确定，否则第一帧会先塌一下再弹开。

  private bottomPanelOpen(): boolean {
    return this.attachPanelOpen || (this.showEmojiPanel && this.membershipState === 'writable');
  }

  // @LocalBuilder 而不是 @Builder：这两个抽屉内容是**传给 BottomDrawerShell 的
  // @BuilderParam** 的，而官方《@LocalBuilder》写得很清楚——@Builder 里的 this
  // 指向**实际调用点**的组件（也就是 BottomDrawerShell），@LocalBuilder 里的
  // this 才指向声明它的组件。
  //
  // 写成 @Builder 时两个抽屉都是坏的，而且症状完全不同、看不出同源：附件那边
  // this.chatEffectDuration 取到 undefined，一开就 TypeError 崩掉；表情那边
  // this.panelContentReady 取到 undefined（假值），于是永远停在"正在打开面板"。
  //
  // 本文件其它几处（headerMenu、缩略图占位）传的都是 `() => { this.x(); }`，
  // 箭头函数按词法捕获 this，所以一直是好的。保证放在声明上而不是指望每个
  // 调用点都写对。
  @LocalBuilder
  attachDrawerContent() {
    AttachPanel({
      actions: attachActions(this.isGroup, this.isChannel),
      onPick: (key: string): void => { this.runAttachAction(key); },
      effectDuration: (ms: number): number => this.chatEffectDuration(KEY_POWER_EFFECT_MENU, ms)
    })
  }

  // 同上，必须是 @LocalBuilder。
  @LocalBuilder
  emojiDrawerContent() {
    if (this.panelContentReady) {
      EmojiPanel({
        tab: this.emojiPanelTab,
        onTabChange: (tab: number): void => { this.emojiPanelTab = tab; },
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
        LoadingProgress().width(26).height(26).color(this.accent());
        Text($r('app.string.cp_opening_panel')).fontSize(13).fontColor(COLOR_TEXT_SECONDARY);
      }
      .width('100%').height('100%')
      .justifyContent(FlexAlign.Center);
    }
  }

  // 两个抽屉共用同一身外壳（见 BottomDrawerShell），这里只挑内容。
  @Builder
  bottomDrawer() {
    if (this.attachPanelOpen) {
      BottomDrawerShell({ bottomSafe: this.bottomSafe, content: this.attachDrawerContent });
    } else if (this.showEmojiPanel && this.membershipState === 'writable') {
      BottomDrawerShell({ bottomSafe: this.bottomSafe, content: this.emojiDrawerContent });
    }
  }

  // 底部那块高度的归属，状态机在 util/bottomSlot（有单测）。所有开关都经过
  // 这里：状态机决定谁占着，这里把结果摊到三个既有字段上。
  //
  // 表情面板的分帧挂载（panelContentReady / emojiPanelClosing / 那两个
  // setTimeout）留在页面——那是渲染时序，状态机不该知道。
  private applyBottomSlot(next: string): void {
    this.bottomSlot = next;
    this.attachPanelOpen = next === SLOT_ATTACH;
    this.replyKbCollapsed = next !== SLOT_REPLY_KB;
  }

  private closeBottomPanels(): void {
    this.closeAttachPanel();
    this.setEmojiPanel(false);
  }

  private toggleAttachPanel(): void {
    const next: string = toggleSlot(this.bottomSlot, SLOT_ATTACH);
    if (next !== SLOT_ATTACH) {
      this.closeAttachPanel();
      return;
    }
    // 打开抽屉要收起系统键盘，把这块高度让出来。表情面板由状态机顶掉，
    // 但它的卸载分帧仍要走 setEmojiPanel。
    this.setEmojiPanel(false);
    this.composerController.stopEditing();
    this.applyBottomSlot(next);
  }

  private closeAttachPanel(): void {
    this.applyBottomSlot(closeSlot(this.bottomSlot, SLOT_ATTACH));
  }

  // 面板只说"点了哪一格"，这里说"那一格做什么"。两边靠 key 对上，
  // AttachActions.test 钉住了不会出现分发表之外的 key。
  private runAttachAction(key: string): void {
    this.closeAttachPanel();
    if (key === 'media') {
      this.pickMedia();
    } else if (key === 'file') {
      this.pickAndSendFile();
    } else if (key === 'audio') {
      this.pickAndSendAudio();
    } else if (key === 'videoNote') {
      this.openVideoNoteRecorder();
    } else if (key === 'location') {
      this.chooseLocationKind();
    } else if (key === 'contact') {
      this.openContactPicker();
    } else if (key === 'poll') {
      this.openPollComposer();
    } else if (key === 'dice') {
      this.showDiceMenu();
    }
  }

  // 表情/贴纸抽屉。和附件抽屉同一套机制（dock 里的一段布局），两者在同一块
  // 高度上、互斥，都会把输入框和聊天内容顶起来。
  //
  // 外观从"浮在列表上的圆角卡片"改成齐边抽屉：不再有左右留白、圆角和阴影，
  // 也不用自己写出入场 transition——键盘的滑入滑出由系统负责。
  //
  // panelContentReady 那套延迟挂载保留：面板里同时挂着三个 picker（自定义表情
  // 常驻，贴纸/GIF 访问过就常驻），一次性挂/卸实测 ~51ms，和挂载位置无关。
  // 先让壳落地，内容下一拍再进来。

  @Builder
  inputBar() {
    Row({ space: 6 }) {
      // 附件按钮在输入框**外面**：它是一个独立动作，不属于正在编辑的这段
      // 文本。放在胶囊里时它会跟着输入框一起长高（胶囊随文本涨到四行），
      // 位置飘忽；移出来之后固定贴着左边，和右侧的发送键左右呼应。
      //
      // 录音态不显示：那时整条输入区被"红点 + 计时 + 取消 + 发送"接管，
      // 再挂一个附件入口没有意义。
      if (!this.isRecording) {
        // 和胶囊同一块底色、同一种材质，读起来是"输入框旁边的一个键"，
        // 而不是浮在聊天背景上的一个裸图标。
        Stack() {
          // 换字形而不是切 fill 变体：回形针没有 fill 版。开合各自转半圈，
          // 和输入框里麦克风↔发送键的互换是同一套时序。
          SymbolGlyph($r('sys.symbol.paperclip'))
            .fontSize(23)
            .fontColor([this.attachPanelOpen ? this.accent() : COLOR_TEXT_SECONDARY])
            .opacity(this.attachPanelOpen ? 0 : 1)
            .rotate({ angle: this.attachPanelOpen ? 45 : 0 })
            .animation({
              duration: this.chatEffectDuration(KEY_POWER_EFFECT_MENU, 150),
              curve: Curve.EaseOut
            });
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize(21)
            .fontColor([this.accent()])
            .opacity(this.attachPanelOpen ? 1 : 0)
            .rotate({ angle: this.attachPanelOpen ? 0 : -45 })
            .animation({
              duration: this.chatEffectDuration(KEY_POWER_EFFECT_MENU, 150),
              curve: Curve.EaseOut
            });
        }
        .width(46)
        .height(46)
        .borderRadius(23)
        // 46 + 1 的底边距，圆盘顶到胶囊上沿差 1px——比 48 的满格轻一点，
        // 又不至于像 40 那样在胶囊旁边缩成一颗小扣子。
        .alignSelf(ItemAlign.End)
        .margin({ bottom: 1 })
        .backgroundColor(overlayGlassFill('card', $r('app.color.surface')))
        .backdropBlur(overlayBackdropBlur('card'))
        .attributeModifier(materialModifier('card'))
        .onClick((): void => { this.toggleAttachPanel(); });
      }
      Column() {
        if (hasPendingMedia(this.pendingMedia)) {
          MediaStrip({
            items: this.pendingMedia,
            onRemoveAt: (index: number): void => {
              this.pendingMedia = removePendingMedia(this.pendingMedia, index);
            },
            onMove: (from: number, to: number): void => {
              this.pendingMedia = movePendingMedia(this.pendingMedia, from, to);
            },
            onCancel: (): void => { this.pendingMedia = clearPendingMedia(); }
          });
        }
        if (this.editingId !== 0) {
          EditStrip({
            editingKind: this.editingKind,
            preview: this.editingPreview,
            onCancel: (): void => { this.cancelEdit(); }
          });
        } else if (this.replyToId !== 0) {
          ReplyStrip({
            name: this.replyToName,
            snippet: this.replyToText,
            enterDuration: this.chatEffectDuration(KEY_POWER_EFFECT_REPLY, 180),
            onTapQuote: (): void => { this.onReplyTap(this.replyToId); },
            onCancel: (): void => { this.clearReply(); }
          });
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
            .fontColor([this.showEmojiPanel ? this.accent() : COLOR_TEXT_SECONDARY])
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
          if (this.composerEditorReady) {
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
            .caretColor(this.accent())
            .padding({
              left: 3, right: 3,
              top: COMPOSER_EDITOR_PAD, bottom: COMPOSER_EDITOR_PAD
            })
            .barState(BarState.Auto)
            .backgroundColor(Color.Transparent)
            .key('chat_composer')
            // null 而不是 undefined：ArkUI 里 undefined 往往是"保持上次的值"，
            // 只有显式 null 才解绑（官方示例用的也是 null）。写成 undefined 时
            // 面板关掉后再点输入框还会把它弹回来。
            .onAreaChange((_old: Area, area: Area): void => {
              const next: number = area.width as number;
              if (Math.abs(next - this.composerEditorW) > 0.5) {
                this.composerEditorW = next;
              }
            })
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
              // 键盘要来了：把贴纸播放器的销毁摁到它落定之后再做。
              holdPlayerJobs(KEYBOARD_SETTLE_MS);
              // 点输入框 = 要打字，收起抽屉把高度让给系统键盘。
              this.setEmojiPanel(false);
              this.applyBottomSlot(closeAllSlots());
              this.commandMenuOpen = false;
              if (this.keyboardH > 0) {
                this.syncTailOnImeFrame();
              }
            })
            .onBlur(() => { this.composerFocused = false; });
          } else {
            // Same one-line geometry as TextArea, but no editor controller,
            // input-method bridge, stylus library or paragraph editor tree.
            Text(this.draft !== '' ? this.draft : this.composerPlaceholder())
              .layoutWeight(1)
              .height(this.composerEditorHeight())
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .fontSize(15)
              .lineHeight(COMPOSER_LINE_H)
              .fontColor(this.draft !== '' ? COLOR_TEXT_PRIMARY : COLOR_TEXT_SECONDARY)
              .padding({
                left: 3, right: 3,
                top: COMPOSER_EDITOR_PAD, bottom: COMPOSER_EDITOR_PAD
              })
              .backgroundColor(Color.Transparent)
              .key('chat_composer_placeholder')
              .accessibilityText(this.composerPlaceholder())
              .onClick((): void => { this.activateComposerEditor(); })
              .onAppear((): void => { this.scheduleComposerEditorMount(); });
          }
          if (this.replyKeyboard !== null) {
            // Bot-keyboard toggle: tinted while the keyboard is up, gray when
            // collapsed — tapping flips between the two.
            Row() {
              SymbolGlyph($r('sys.symbol.keyboard'))
                .fontSize(21)
                .fontColor([this.replyKbCollapsed ? COLOR_TEXT_SECONDARY : this.accent()]);
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
              .fontSize(22).fontColor([this.accent()])
              .accessibilityText($r('app.string.cp_open_miniapp'))
              .onClick((): void => { this.openBotMiniApp(); });
          }
          ComposerSendButton({
            // 有暂存媒体时正文可以为空，按钮也该是"发送"而不是麦克风。
            hasDraft: pendingMediaCanSend(this.pendingMedia, this.draft),
            recordingStarting: this.recordingStarting,
            sending: this.composerSending,
            onRecord: (): void => { this.startRecording(); },
            onSend: (): void => { this.doSend(); },
            onSendOptions: (): void => { this.showSendOptions(); }
          });
        }
      }
        .width('100%')
        .constraintSize({ minHeight: 48, maxHeight: 120 })
        .padding({ left: 12, right: 4, top: 4, bottom: 4 })
        .alignItems(VerticalAlign.Center);
      }
      .layoutWeight(1)
      .backgroundColor(overlayGlassFill('card', $r('app.color.surface')))
      .borderRadius(24)
      // 材质接管时它自带填充，把上面的实心色清成透明玻璃；低于 API 26 材质
      // 是 undefined，改由 backdropBlur + 半透明底色自己画。
      .backdropBlur(overlayBackdropBlur('card'))
      .attributeModifier(materialModifier('card'));
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
  initialHeaderShell() {
    // Keep the final material from the first frame. Only the expensive dynamic
    // contents (animated avatar/status and bound menu subtree) are deferred;
    // using a solid surface here caused a visible white -> glass swap.
    Row({ space: 8 }) {
      Row() {
        SymbolGlyph($r('sys.symbol.chevron_left'))
          .fontSize(22).fontColor([COLOR_TEXT_PRIMARY]);
      }
      .width(CHAT_HEADER_ACTION_SIZE).height(CHAT_HEADER_ACTION_SIZE)
      .borderRadius(CHAT_HEADER_RADIUS)
      .backgroundColor(overlayGlassFill('bar', $r('app.color.surface')))
      .justifyContent(FlexAlign.Center)
      .shadow({ radius: 4, color: '#12000000', offsetX: 0, offsetY: 1 })
      .backdropBlur(overlayBackdropBlur('bar'))
      .attributeModifier(materialModifier('bar'))
      .onClick((): void => { this.closeChatPage(); });
      Row() {
        Text(this.headerText().titleText)
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor(COLOR_TEXT_PRIMARY)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis });
      }
      .layoutWeight(1)
      .height(CHAT_HEADER_ACTION_SIZE)
      .padding({ left: 12, right: 12 })
      .backgroundColor(overlayGlassFill('bar', $r('app.color.surface')))
      .borderRadius(CHAT_HEADER_RADIUS)
      .shadow({ radius: 4, color: '#12000000', offsetX: 0, offsetY: 1 })
      .backdropBlur(overlayBackdropBlur('bar'))
      .attributeModifier(materialModifier('bar'))
      .alignItems(VerticalAlign.Center)
      .onClick((): void => {
        this.activateInitialChrome((): void => {
          if (this.headerState === 'error') {
            this.resolveHeaderIdentity();
          } else {
            this.openProfile();
          }
        });
      });
      Row() {
        Image($r('app.media.ic_header_menu'))
          .width(18).height(18)
          .fillColor(COLOR_TEXT_PRIMARY)
          .draggable(false);
      }
      .width(CHAT_HEADER_ACTION_SIZE).height(CHAT_HEADER_ACTION_SIZE)
      .borderRadius(CHAT_HEADER_RADIUS)
      .backgroundColor(overlayGlassFill('bar', $r('app.color.surface')))
      .justifyContent(FlexAlign.Center)
      .shadow({ radius: 4, color: '#12000000', offsetX: 0, offsetY: 1 })
      .backdropBlur(overlayBackdropBlur('bar'))
      .attributeModifier(materialModifier('bar'))
      .onClick((): void => {
        this.activateInitialChrome((): void => {
          if (!this.pageClosing && this.chatId !== 0) {
            this.headerMenuShow = true;
          }
        });
      });
    }
    .width('100%')
    .height(this.topSafe + CHAT_HEADER_BASE_HEIGHT)
    .padding({ left: 12, right: 12, top: this.topSafe + 8, bottom: 8 })
    .alignItems(VerticalAlign.Center);
  }

  @Builder
  bottomDock() {
    Column() {
      if (this.selecting) {
        // Selection owns the header actions; removing the composer also drops
        // its reserved list inset so messages expand naturally into the space.
        Column().width('100%').height(0);
      } else if (this.searchMode) {
        SearchBottomBar({
          query: this.searchQuery,
          loadedCount: this.searchResults.length,
          total: this.searchTotal,
          currentIndex: this.searchIdx,
          bottomGap: this.composerBottomGap(),
          onOlder: (): void => { this.searchOlder(); },
          onNewer: (): void => { this.searchNewer(); }
        });
      } else if (this.composerSlot() !== 'writable') {
        MembershipBar({
          state: this.composerSlot(),
          isMuted: this.isMuted,
          joining: this.joiningChat,
          bottomGap: this.composerBottomGap(),
          onJoin: (): void => { this.joinCurrentChat(); },
          onToggleMute: (): void => { this.toggleChatMute(); },
          onStartBot: (): void => { this.sendBotCommand(BOT_START_COMMAND); },
          onHeightChange: (height: number): void => { this.inputBarH = height; }
        });
      } else {
        Column() {
          this.inputBar();
          if (this.replyKbVisible()) {
            ReplyKeyboardPanel({
            rows: this.replyKeyboard!.rows,
            sendingKey: this.replyKeyboardSendingKey,
            resize: this.replyKeyboard!.resize,
            bottomGap: this.composerBottomGap(),
            enterDuration: this.chatEffectDuration(KEY_POWER_EFFECT_MENU, 190),
            onTap: (btn: KeyboardBtn, key: string): void => {
              this.onReplyKeyboardTap(btn, key);
            }
          });
          }
          // 抽屉是 dock 的一部分，不是自定义键盘。这样它和聊天内容共享同一个
          // 页面背景——壁纸就在它后面，不需要再画副本去对齐（那条路走了很久，
          // 副本永远接不上）。输入框被它自然顶高，列表的避让也自动跟上：
          // dock 的 onAreaChange → bottomChromeH → List.contentEndOffset 这条
          // 链路本来就在为回复预览条服务。
          // 试过"关面板只隐藏、不卸载"：Grid 的虚拟化会因为容器尺寸变 0 把
          // 所有格子当成划出视口回收掉，节点根本留不住，白搭一层复杂度。
          if (this.bottomPanelOpen()) {
            this.bottomDrawer();
          }
        }
        .width('100%');
      }
    }
    .width('100%')
    .onAreaChange((_old: Area, area: Area) => {
      this.updateBottomChromeHeight(area.height as number);
    })
    // 骰子面板挂在 dock 上，不挂页面根节点：同一个节点上串两个 bindSheet
    // 只有最后一个生效（根节点上已经有翻译面板了，骰子那个就永远弹不出来）。
    .bindSheet($$this.diceSheetOpen, this.diceSheet(), {
      height: 320,
      backgroundColor: Color.Transparent,
      dragBar: false,
      blurStyle: overlayBlur('dialog'), systemMaterial: overlayMaterial('dialog')
    });
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
        this.glueBottom('L7961');
        this.refreshAtBottom();
      }
    }, 60);
  }

  private timelinePillMode(): string {
    return timelineStateMode(this.visibleGroupCount, this.messageLoadState,
      this.olderLoadState, this.newerLoadState);
  }

  private initialTimelineRowRevealDelay(index: number): number {
    let first: number = this.curStartIdx;
    let last: number = this.curEndIdx;
    if (first < 0 || last < first || last >= this.groups.length) {
      if (this.stayAtUnread && this.firstUnreadId > 0) {
        first = Math.max(0, groupIndexOf(this.groups, this.firstUnreadId));
        last = Math.min(this.groups.length - 1,
          first + INITIAL_TIMELINE_REVEAL_ROW_LIMIT - 1);
      } else {
        last = this.groups.length - 1;
        first = Math.max(0, last - INITIAL_TIMELINE_REVEAL_ROW_LIMIT + 1);
      }
    }
    if (index < first || index > last) {
      return 0;
    }
    // Bottom landings read naturally from the composer upward. An unread
    // landing starts at its top anchor and flows down into the unread block.
    const visualRank: number = this.stayAtUnread ? index - first : last - index;
    const cappedRank: number = Math.min(
      INITIAL_TIMELINE_REVEAL_ROW_LIMIT - 1, Math.max(0, visualRank));
    return powerAnimationDuration(
      KEY_POWER_SMOOTH_TRANSITIONS, cappedRank * INITIAL_TIMELINE_ROW_STAGGER_MS);
  }

  private timelineStateRetry(mode: string): void {
    if (this.store === null) {
      return;
    }
    if (mode === TL_SYNC_ERROR) {
      this.store.retryInitialHistory();
    } else if (mode === TL_OLDER_ERROR) {
      this.olderArmed = false;
      this.store.retryOlder();
    } else if (mode === TL_NEWER_ERROR) {
      this.store.retryNewer();
    }
  }

  // The flattened background, once it exists. Until then the layered version
  // below renders, so the chat never waits on the raster.
  build() {
    HdsNavDestination() {
    Stack() {
      // 整层背景搬到了 ChatBackdrop：它只吃输入不回调，所以这里只传三个入参。
      ChatBackdrop({ chatBg: this.chatBg, screenW: this.screenW, screenH: this.screenH });
      Column() {
        Stack() {
        List({ scroller: this.scroller }) {
          // Repeat.virtualScroll（不是 ForEach / LazyForEach）。三条硬约束都满足：
          //   · 「Repeat 必须在滚动类容器组件内使用」——这里是 List；
          //   · 「滚动容器组件内只能包含一个 Repeat」——这个 List 的 children 只有
          //     它一个，逐行确认过；
          //   · 「Repeat 懒加载模式不支持与状态管理 V1 配合使用」——ChatPage 在
          //     P3 批 1 已经是 @ComponentV2。
          //
          // reusable: false —— **故意关掉 Repeat 自身的复用**。官方原话：「当
          // Repeat 的子组件为 @ReusableV2 装饰的自定义组件时，Repeat 自身的复用
          // 能力优先于 @ReusableV2 的复用能力……在懒加载模式下，正常滑动场景、
          // 更新场景不会触发 @ReusableV2 的回收和复用，若开发者希望使用
          // @ReusableV2 的复用能力，建议关闭 Repeat 自身的复用能力。」本行的复用
          // 是 ReusableMessageBubble（@ReusableV2）+ rowReuseId 分档的全局池，
          // P5 的既定方案就是保住它，所以按官方的建议关掉 Repeat 这一层。
          // 起始版本：virtualScroll / totalCount / key / each 都是 API 12，
          // reusable 是 API 18，本仓 compatibleSdkVersion "6.0.0(20)" 全部够用。
          //
          // 没有用 .templateId()/.template()：template 是 **Repeat 自己的**复用池
          // 分档，reusable: false 之下它本就不生效；而且 rowReuseId 的取值空间是
          // 十二个维度的组合（medium 档最多 4096 种），没法逐个声明成 .template()，
          // 声明不全的那些按文档会落回 .each()。分档继续由 @ReusableV2 的
          // .reuse({ reuseId }) 承担，rowReuseId.ets 一个字符没动。
          Repeat<AlbumGroup>(this.groups)
            .each((ri: RepeatItem<AlbumGroup>) => {
              ListItem() {
                if (ri.item.initialDeferred === true) {
                  Column()
                    .width('100%')
                    .height(initialMessagePlaceholderHeight(
                      ri.item,
                      this.screenW,
                      this.firstUnreadId !== 0 &&
                        ri.item.memberIds.indexOf(this.firstUnreadId) >= 0
                    ))
                    .hitTestBehavior(HitTestMode.None);
                } else {
                Stack({ alignContent: Alignment.Start }) {
                // Selection mode shifts the row right into a left check gutter
                // (instead of overlaying the check on the avatars).
                Row() {
                if (this.selecting && ri.item.head.contentType !== 'system' && ri.item.head.contentType !== 'hidden') {
                  Column() {
                    if (this.rowSelected(ri.item)) {
                      SymbolGlyph($r('sys.symbol.checkmark_circle'))
                        .fontSize(22).fontColor([this.accent()]);
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
                  this.preparedMessageBubble(ri);
                }
                .layoutWeight(1)
                // 多选态下消息本体整体不响应触摸：BLOCK_DESCENDANTS 只封住自己和
                // 后代，**不影响祖先**（官方原话），所以外层 List 的滑动照常。
                // 原来用的是 Block，它连兄弟一起封，实测多选时列表滑不动。
                // 点击判定放在外面那层，那层保持 Default。
                .hitTestBehavior(this.selecting && ri.item.head.contentType !== 'system' &&
                  ri.item.head.contentType !== 'hidden'
                  ? HitTestMode.BLOCK_DESCENDANTS : HitTestMode.Default);
                }
                .width('100%')
                .alignItems(VerticalAlign.Center)
                .backgroundColor(this.selecting && this.rowSelected(ri.item) ? $r('app.color.select_highlight') : Color.Transparent)
                .animation({
                  duration: this.chatTgsScrollActive ? 0 :
                    powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 150),
                  curve: Curve.EaseOut
                })
                .onClick(() => {
                  if (this.selecting) {
                    this.toggleSelectRow(ri.item);
                  }
                });
                }
                }
              }
              // Deferred rows continue reserving geometry after an early bottom
              // reveal. Keep each one invisible until its stable-key replacement
              // is real, then reuse the same per-row fade/transform wave.
              .opacity(this.initialTimelineMasked || ri.item.initialDeferred === true ? 0 : 1)
              .translate({
                y: this.initialTimelineMasked || ri.item.initialDeferred === true ? 2 : 0
              })
              .scale({
                x: this.initialTimelineMasked || ri.item.initialDeferred === true ? 0.99 : 1,
                y: this.initialTimelineMasked || ri.item.initialDeferred === true ? 0.99 : 1
              })
              .animation({
                // Newly materialized rows read the plain scroll gate without
                // invalidating already visible rows at onScrollStart. During a
                // fling they paint immediately; the entry stagger remains for
                // the coordinated first presentation.
                duration: this.chatTgsScrollActive ? 0 : powerAnimationDuration(
                  KEY_POWER_SMOOTH_TRANSITIONS, INITIAL_TIMELINE_ROW_FADE_MS),
                delay: this.chatTgsScrollActive ? 0 : this.initialTimelineRowRevealDelay(ri.index),
                curve: Curve.EaseOut
              });
            })
            // Format lives in rowKeyOf — see its comment.
            .key((g: AlbumGroup): string => this.rowKeyOf(g))
            .virtualScroll({ totalCount: this.groups.length, reusable: false });
        }
        .width('100%').height('100%')
        // Keep layout/build work alive behind a visual mask. The mask is
        // removed only after a complete viewport and its final anchor are
        // ready, so users never see placeholder replacement or a second jump.
        .opacity(this.initialTimelineMasked ? 0 : 1)
        .enabled(!this.initialTimelineMasked)
        // 顶部 chrome 是悬浮的，用 contentStartOffset 让位——和底部的
        // contentEndOffset 对称。不用 padding：padding 会改变内容区尺寸，
        // 而滚动锚点、getItemRect 那一套都吃列表几何。
        .contentStartOffset(this.headerChromeHeight())
        // 消息滑到标题栏下面时逐渐糊掉，而不是被一条硬边切断。
        // 省电模式下关掉——渐变模糊是逐帧实时渲染，代价不低。
        .linearGradientBlur(this.headerBlurRadius(), {
          fractionStops: this.headerBlurStops(),
          direction: GradientDirection.Bottom
        })
        .contentEndOffset(this.bottomChromeH + 8)
        // 固定预建半屏左右的短消息。图片预取仍由 BasicPrefetcher 按可见区
        // 独立驱动；这里不延迟修改状态变量，避免首屏落地后把可见行全部重建。
        .cachedCount(this.listCachedCount)
        // Keep the visible messages pinned in place when an older page is
        // prepended above — without this, the List stays index-anchored and
        // visibly jumps to the top of the newly loaded page.
        .maintainVisibleContentPosition(true)
        // 从末尾开始布局——聊天列表本该是"底部锚定"的。
        //
        // 默认的顶部锚定意味着：内容比视口短时贴顶，末尾插入一条时上面的内容
        // 不动、新消息落在视口之外，得靠我们自己判"在不在底部"再补一次
        // scrollToIndex。那套判定（util/atBottom）依赖 onScrollIndex 报的行号，
        // 而行号落后于数据一帧，pad 屏高、可见行多，时序更容易错开——用户反馈
        // 的"停在底部却不跟新消息"就出在这里。
        //
        // stackFromEnd 把锚点换到末尾，由布局本身保证：
        //   内容短于视口时底部对齐；显示区域内插入 ListItem 时，上方内容上移。
        // 用户滑上去看历史时，新消息插在可视区之外，位置不动——正是想要的语义。
        //
        // API 19 起支持，compatibleSdkVersion 是 6.0.0(20)，所有目标设备都有，
        // 不需要运行时判版本。
        //
        // 原有的贴底逻辑保留：它和这里指向同一个位置，最坏是多做一次无效功，
        // 而在真机上验证之前，删掉它的风险更大。
        .stackFromEnd(true)
        .onReachStart(() => {
          this.maybeLoadOlder();
        })
        // Each new touch gesture re-arms one older-page load: a fling that ends
        // pinned at the very top (start index never leaves the trigger zone)
        // would otherwise never re-arm, leaving the user unable to load more.
        .onTouch((e: TouchEvent) => {
          if (e.type === TouchType.Down) {
            this.finishInitialMessageStageForInteraction();
            // A real gesture transfers scroll ownership to the user; never
            // snap back to the bottom while they inspect older messages.
            this.imeTailPinned = false;
            this.imeLayoutSeq++;
            this.listTouchActive = true;
            this.olderArmed = true;
            // 向下分页同样按手势重新上膛：一次手势最多多取一页，和 older 一致。
            this.newerGate = armedPageGate();
            // The highlight overlay is viewport-anchored — drop it as soon as
            // the user starts interacting, before it can detach from its row.
            this.cancelFlash();
            // 点面板外面收起。
            this.closeBottomPanels();
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
          // 记下这批行号对应的数据长度，refreshAtBottom 据此判断行号是否新鲜。
          this.indexGroupsLen = this.groups.length;
          // 首帧之前 curEndIdx 是 -1，数据先到那次判不出来；这里是可见行号第一
          // 次变得可用的地方，补判一次，否则铺不满一屏时就永远没人敲门了。
          this.fillViewportIfNeeded();
          this.curBottomId = this.bottomVisibleId(end);
          this.syncReturnState();
          this.markVisibleRead(end);
          this.updatePinnedFromScroll(start);
          // Image prefetch: the data source decodes the photos of rows about to
          // arrive and cancels the ones scrolled past. Distinct from the page
          // prefetch below, which loads MESSAGES.
          //
          // 下标必须先钳进 [0, totalCount()-1]：BasicPrefetcher 内部用
          // IndexRange 表达区间，而 IndexRange 的构造函数对 start > end 是
          // **抛异常**，visibleAreaChanged 的 catch 又是转抛——越界一次就是一次
          // 应用崩溃（2026-08-27 的 'Invalid range' 崩溃栈）。这里的 start / end
          // 报的是上一帧布局的可见行号，而 groupsData 可能已经在这一帧里变短
          // 了。判据与理由见 clampPrefetchRange。
          const visible: PrefetchRange | null =
            clampPrefetchRange(start, end, this.groupsData.totalCount());
          if (visible !== null) {
            this.imagePrefetcher.visibleAreaChanged(visible.start, visible.end);
          }
          // Translation results can mutate several rows at once. Keep the
          // request/refresh lane quiet during a fling and catch up once the
          // list settles; image prefetch above remains active and directional.
          if (!this.chatTgsScrollActive) {
            this.driveTranslations(start, end);
          }
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
          if (end < this.groups.length - 5) {
            // 离开底部触发区。但这个位置判据会被内容追加自己顶成立（groups
            // 变长而视口没动），所以必须叠一条"这一下是用户在滚"——程序性
            // 位移不上膛。older 那侧靠 onTouch(Down) 和真实滚动上膛，同一套。
            this.newerGate = rearmPageGate(this.newerGate, this.listUserScrollActive);
          } else {
            this.maybeLoadNewer(end);
          }
        })
        // onScrollIndex only fires when the visible index RANGE changes, so
        // scrolling up inside one tall last message (index unchanged) never
        // updates atBottom. onDidScroll fires on every scroll frame — track the
        // true bottom edge here so the glue stops fighting the user.
        .onDidScroll(() => {
          this.refreshAtBottom();
          // 列表被程序性挪动（贴底、prepend 复位）时高亮跟着行走（issue #80）。
          this.syncFlashRect();
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
        .onScrollStart(() => {
          setScrollActive(true);
          this.finishInitialMessageStageForInteraction();
          this.pauseChatTgsForScroll();
          this.dismissKeyboardOnUserScroll();
        })
        .onScrollStop(() => {
          setScrollActive(false);
          this.resumeChatTgsAfterScroll();
          this.driveVisibleWork();
          this.armPlaySlotSettle();
          // 一次回收潮刚过，池子最满，正是封顶该动手的时刻。
          this.capMessageReuseBuckets();
        })
        .onAreaChange((_old: Area, area: Area): void => {
          const y: number = area.globalPosition.y as number;
          const height: number = area.height as number;
          this.playSlots.setViewportCenter(y + height / 2);
        });
        if (!this.initialTimelineMasked && this.visibleGroupCount === 0 &&
          this.messageLoadState !== 'loading') {
          // 首屏同步期间保持安静：消息在转场背后完成定位后一次性呈现。
          // 这里只展示真正的空会话或错误，避免用 Loading 卡片制造二次视觉切换。
          Column() {
            MessageListStateCard({
              loadState: this.messageLoadState,
              loadError: this.messageLoadError,
              threadRootId: this.threadRootId,
              membershipState: this.membershipState,
              isChannel: this.isChannel,
              isGroup: this.isGroup,
              screenW: this.screenW,
              onRetry: (): void => { this.store?.retryInitialHistory(); }
            });
          }
          .width('100%').height('100%')
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .padding({ bottom: this.bottomChromeH + 28 })
          .hitTestBehavior(HitTestMode.Transparent);
        } else if (this.timelinePillMode() !== TL_NONE) {
          TimelineStatePill({
            mode: this.timelinePillMode(),
            label: timelineStateText(this.timelinePillMode()),
            floatDateShown: this.floatDate !== '',
            onRetry: (): void => { this.timelineStateRetry(this.timelinePillMode()); }
          });
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
          .margin({ top: this.headerChromeHeight() + 8 })
          .opacity(this.floatDateShown ? 1 : 0)
          .scale({ x: this.floatDateShown ? 1 : 0.9, y: this.floatDateShown ? 1 : 0.9 })
          .translate({ y: this.floatDateShown ? 0 : -5 })
          .animation({ duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 200), curve: Curve.EaseOut })
          .hitTestBehavior(HitTestMode.None);
        }
        Column() {
          // The composer itself is interactive from the first frame. Only its
          // optional result panels stay behind the transition gate; replacing
          // the whole dock with a decorative shell made the first tap a no-op.
          if (this.initialMessageTransitionSettled) {
            if (this.membershipState === 'writable' && !this.showEmojiPanel && !this.replyKbVisible() &&
              (this.mentionItems.length > 0 || this.commandPanelActive())) {
              SuggestionPanel({
                commandMode: this.commandPanelActive(),
                commands: this.commandItems,
                mentions: this.mentionItems,
                loadState: this.commandLoadState,
                loadError: this.commandLoadError,
                catalogSize: this.allCommands.length,
                onPickCommand: (it: CommandItem): void => { this.pickCommand(it); },
                onPickMention: (it: MentionItem): void => { this.pickMention(it); },
                onRetryCommands: (): void => { this.ensureCommandsLoaded(true); }
              });
            }
            if (this.membershipState === 'writable' && !this.showEmojiPanel &&
              this.mentionItems.length === 0 && !this.commandPanelActive() &&
              this.inlineResults.length > 0) {
              InlineResultsBar({
                results: this.inlineResults,
                onPick: (row: InlineResultRow): void => { this.pickInlineResult(row); }
              });
            }
            if (this.membershipState === 'writable' && !this.showEmojiPanel &&
              this.mentionItems.length === 0 && !this.commandPanelActive() &&
              this.inlineResults.length === 0 && this.stickerSuggestions.length > 0) {
              StickerSuggestionBar({
                suggestions: this.stickerSuggestions,
                onPick: (fileId: number): void => { this.sendSuggestedSticker(fileId); }
              });
            }
          }
          this.bottomDock();
        }
        .width('100%').height('100%')
        .justifyContent(FlexAlign.End)
        .opacity(this.initialMessageTransitionSettled ? 1 : 0)
        .translate({ y: this.initialMessageTransitionSettled ? 0 : 2 })
        .scale({
          x: this.initialMessageTransitionSettled ? 1 : 0.99,
          y: this.initialMessageTransitionSettled ? 1 : 0.99
        })
        .animation({
          duration: powerAnimationDuration(
            KEY_POWER_SMOOTH_TRANSITIONS, INITIAL_TIMELINE_ROW_FADE_MS),
          curve: Curve.EaseOut
        })
        .hitTestBehavior(HitTestMode.None);

        // 顶部 chrome 放在最后 = 叠在最上层，消息从它下面穿过去。
        Column() {
          // Keep the real header mounted behind the initial visual gate. This
          // removes the lightweight-shell -> full-header intermediate page;
          // only opacity/transform changes when the message anchor is ready.
          if (this.selecting) {
            SelectionHeader({
              selectedCount: this.selectedIds.length,
              topSafe: this.topSafe,
              onExit: (): void => { this.exitSelect(); },
              onForward: (): void => { this.openForwardPicker(this.selectedIds); },
              onCopy: (): void => { this.copySelected(); },
              onDelete: (): void => { this.deleteSelected(); }
            });
          } else if (this.searchMode) {
            SearchHeader({
              query: this.searchQuery,
              topSafe: this.topSafe,
              onExit: (): void => { this.exitSearch(); },
              onQueryChange: (v: string): void => { this.updateSearchQuery(v); },
              onSubmit: (): void => { this.runSearch(0, 0); }
            });
          } else {
            ChatHeader({
              titleText: this.headerText().titleText,
              subtitleText: this.headerText().subtitleText,
              headerState: this.headerState,
              avatarPath: this.avatarPath,
              avatarAnimPath: this.headerAvatarAnimPath,
              initials: this.initials,
              savedMessages: this.isSavedMessagesChat(),
              chatId: this.chatId,
              emojiPath: this.headerEmojiPath,
              emojiFormat: this.headerEmojiFormat,
              isMuted: this.isMuted,
              muteUpdating: this.headerMuteUpdating,
              profileOpening: this.headerProfileOpening,
              topSafe: this.topSafe,
              pageClosing: this.pageClosing,
              menuShow: this.headerMenuShow,
              onMenuShowChange: (show: boolean): void => { this.headerMenuShow = show; },
              menu: (): void => { this.headerMenu(); },
              onBack: (): void => { this.closeChatPage(); },
              onOpenProfile: (): void => { this.openProfile(); },
              onResolveIdentity: (): void => { this.resolveHeaderIdentity(); }
            });
          }
          if (this.initialMessageTransitionSettled && this.topCardShouldShow()) {
            TopBanners({
              pinnedPreview: this.pinnedPreview,
              pinnedCount: this.pinnedCount,
              pinnedCycle: this.pinnedCycle,
              pinnedLoadState: this.pinnedLoadState,
              pinnedJumpBusy: this.pinnedJumpBusy,
              liveGroupCallId: this.liveGroupCallId,
              liveCallIsActive: this.liveCallIsActive,
              liveCallIsRtmp: this.liveCallIsRtmp,
              liveParticipantCount: this.liveParticipantCount,
              livePulseExpanded: this.livePulseExpanded,
              liveDialogOpening: this.liveDialogOpening,
              liveNavigationBusy: this.liveNavigationBusy,
              topCardLoadingVisible: this.topCardLoadingVisible,
              onPinnedTap: (): void => { this.onPinnedTap(); },
              onLiveStreamTap: (): void => { this.onLiveStreamTap(); }
            });
          }
        }
        .width('100%')
        .opacity(this.initialMessageTransitionSettled ? 1 : 0)
        .translate({ y: this.initialMessageTransitionSettled ? 0 : -2 })
        .scale({
          x: this.initialMessageTransitionSettled ? 1 : 0.99,
          y: this.initialMessageTransitionSettled ? 1 : 0.99
        })
        .animation({
          duration: powerAnimationDuration(
            KEY_POWER_SMOOTH_TRANSITIONS, INITIAL_TIMELINE_ROW_FADE_MS),
          curve: Curve.EaseOut
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

      if (this.showReactionSheet) {
        ReactionSheet({
          show: this.showReactionSheet,
          onShowChange: (show: boolean): void => { this.showReactionSheet = show; },
          messages: this.messages,
          targetId: this.reactionTargetId,
          chatId: this.chatId,
          pendingKey: this.reactionPendingKey,
          // ReactionSheet 迁 @ComponentV2 之后没有 @StorageProp 可用，安全区/
          // 键盘高度由页面透传（页面自己就持有这两个键）。
          bottomSafe: this.bottomSafe,
          keyboardH: this.keyboardH,
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
          onShowChange: (show: boolean): void => { this.showForwardSheet = show; },
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
          onShowChange: (show: boolean): void => { this.showScheduledSheet = show; },
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
      // 显隐跟着"有没有可返回的位置"走，而不是"在不在底部"：站在最新消息上
      // 但引用链还没退完时，箭头仍然该在。
      if (this.returnTarget().kind !== RETURN_NONE && !this.searchMode && !this.showEmojiPanel) {
        Column() {
          ScrollFab({
            unreadCount: this.unreadBadge,
            busy: this.scrollToBottomBusy,
            onTap: (): void => { this.onScrollFabTap(); }
          });
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
          // 迁 @ComponentV2 之后这一层没有 @StorageProp 可用，三个全局键由页面
          // 透传（页面自己就持有它们）。
          langEpoch: this.langEpoch,
          materialEpoch: this.materialEpoch,
          topSafe: this.topSafe,
          viewerMsgId: this.viewerMsgId,
          onViewerMsgIdChange: (msgId: number): void => { this.viewerMsgId = msgId; },
          chromeVisible: this.chromeVisible,
          onChromeVisibleChange: (visible: boolean): void => { this.chromeVisible = visible; },
          videoLandscape: this.viewerVideoLandscape,
          onVideoLandscapeChange: (landscape: boolean): void => { this.viewerVideoLandscape = landscape; },
          messages: this.messages,
          groups: this.groups,
          onNeedHistory: (dir: number): void => {
            // 查看器切组切到已加载窗口的边缘：-1 要更旧的，+1 要更新的。
            if (dir < 0) {
              this.store?.loadOlder();
            } else if (dir > 0) {
              this.store?.loadNewer();
            }
          },
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
          onSaveMedia: (): void => { this.saveViewerMedia(false); },
          onSaveMediaToFiles: (): void => { this.saveViewerMedia(true); },
          onPositionChanged: (positionMs: number): void => { this.viewerPositionMs = positionMs; }
        })
      }
    }
    .width('100%').height('100%')
    .bindSheet($$this.translateSheetOpen, this.translateSheetBody(), {
      detents: [SheetSize.MEDIUM, SheetSize.LARGE],
      backgroundColor: $r('app.color.surface'),
      dragBar: true,
      blurStyle: overlayBlur('dialog'), systemMaterial: overlayMaterial('dialog')
    });
    }
    // ChatPage 自己画标题栏（会话头像/名称/在线状态那一条），不要 HDS 的。
    .hideTitleBar(true)
    // 入参：router 时代是 aboutToAppear 里 router.getParams() 现取，现在从
    // NavDestinationContext 的 pathInfo 里取——而 onReady 实测晚于 aboutToAppear，
    // 所以吃参数的初始化也在这里触发，不能留在 aboutToAppear。
    .onReady((ctx: NavDestinationContext): void => {
      this.navStack = ctx.pathStack;
      this.navParams = ctx.pathInfo.param as Record<string, Object> | undefined;
      // 必须在这里调而不是等 aboutToAppear：实测 onReady 晚于 aboutToAppear。
      this.applyRouteParams();
    })
    // 下面三条对应迁移前的 onPageShow / onPageHide / onBackPress，方法体一字未动：
    // onBackPress 返回 true「已处理不返回」与 onBackPressed 返回 true「重写返回键
    // 不出栈」语义等价。
    .onShown((): void => { this.handleShown(); })
    .onWillHide((): void => { this.handleWillHide(); })
    .onHidden((): void => { this.handleHidden(); })
    .onBackPressed((): boolean => { return this.handleBackPressed(); })
    .width('100%').height('100%');
  }
}
