import { promptAction, UIContext } from '@kit.ArkUI';
import { openDeleteMessagesDialog } from './DeleteMessagesDialog';
import { pasteboard } from '@kit.BasicServicesKit';
import { PollOptionInfo } from '../../util/formatMsgContent';
import { setScrollActive } from '../../util/scrollEffects';
import { rememberRecentSticker } from '../../store/StickerApi';
import { openMiniApp } from '../../store/BotApi';
import { InlineResultRow, sendInlineResult } from '../../store/BotApi';
import { common } from '@kit.AbilityKit';
import { PickedContact } from './ContactPickerSheet';
import { fileIo as fs } from '@kit.CoreFileKit';
import { formatDateSeparator } from '../../util/formatDateSeparator';
import { holdPlayerJobs } from './WebmStickerView';
import { setChatTgsSuspended } from './TgsStickerView';
import { EmojiPanel } from './EmojiPanel';
import { StickerItem } from './StickerPicker';
import { GifItem } from './GifPicker';
import { getVoicePlayback } from '../../services/VoicePlayback';
import { openLocalFile } from '../../util/openLocalFile';
import { getTdClient, getUserStore, getChatStore, getChatThemeStore } from '../../tdkit/Globals';
// B14 的四个建议控制器经宿主取值器拿 TDLib 客户端（缝的理由见
// ComposerSuggestionState.ets 文件里 client 取值器上方那段），这里只需要类型。
import { TdClient } from '../../tdkit/TdClient';
import { MessageStore, MediaSendItem } from '../../store/MessageStore';
import { MessageEntry, buildMessageEntry } from '../../store/MessageEntry';
import {
  allocateChatPageReuseScope, CHAT_PAGE_REUSE_ID_LEVEL, rowReuseId
} from '../../util/rowReuseId';
import {
  MIN_MESSAGE_ROW_HEIGHT_VP, capReuseBuckets, globalReusePoolAvailable,
  messageRowViewportRows, reuseBucketMaxCount
} from '../../util/messageReusePool';
import { ReplyKeyboard, KeyboardBtn, KB_TEXT } from '../../store/ReplyKeyboard';
import { ChatEntry } from '../../store/ChatEntry';
import { ClearHistoryOption, clearHistoryOptions } from '../../store/ClearHistoryOptions';
import {
  MessageBubbleActions, MessageBubbleRenderData, ReusableMessageBubble
} from './ReusableMessageBubble';
import { PlaySlotDriver } from './PlaySlotDriver';
import { shouldCompete, slotKey } from './playSlot';
import { MediaViewerOverlay } from './MediaViewerOverlay';
import { openSelectTextOverlay, selectTextPayload } from './SelectTextOverlay';
import { ChatOverlayHost } from './ChatOverlayHost';
import { ChatOverlayState, ChatOverlaySheetKind } from './ChatOverlayState';
import { ChatTimelineHost } from './ChatTimelineHost';
import { AttachActions } from './AttachActions';
import {
  ChatBackgroundState, ChatBackgroundStore, emptyChatBackground
} from '../../store/ChatBackgroundStore';
import { MusicQueue } from '../../services/MusicQueue';
import { VoiceState } from '../../services/VoicePlayback';
import { setMediaViewerOrientation } from './LiveViewerUi';
import {
  AlbumGroupDataSource, appendBreaksAnchor, clampPrefetchRange, PrefetchRange,
  repeatRowKey, reuseUnchangedRows, sameRowArray
} from './AlbumGroupDataSource';
import { BasicPrefetcher } from '@kit.ArkUI';
// UIUtils 本身从 API 12 起就有；这里用到的 getCustomComponentContext 是 26 起，
// 调用点在 capMessageReuseBuckets 的版本闸门之后。IReusePool 只是类型。
import { IReusePool, UIUtils } from '@kit.ArkUI';
import { ChatBackdrop } from './ChatBackdrop';
import { ChatHeader } from './ChatHeader';
import { HeaderIdentitySession, ResolvedChatKind } from './HeaderIdentitySession';
import {
  ChatHeaderMenuController, ChatHeaderMenuParams, PANEL_MAIN, createChatHeaderMenuId
} from './ChatHeaderMenu';
import { TopBanners } from './TopBanners';
import { SelectionHeader } from './SelectionHeader';
import { SearchBottomBar, SearchHeader } from './ChatSearchBars';
import { FloatingDateState } from './FloatingDateOverlay';
import { firstRowBelowChrome, floatDateNeedsRescan } from '../../util/floatDateGate';
import { isInteriorRowRemoval } from '../../util/rowRemoval';
import {
  PendingMediaAppend, PendingMediaItem, appendPendingMedia,
  clearPendingMedia, hasPendingMedia, movePendingMedia, pendingMediaCanSend, toMediaSendItems,
  removePendingMedia
} from '../../util/pendingMedia';
import {
  ChatComposerInput, COMPOSER_EDITOR_PADDING, COMPOSER_LINE_HEIGHT, COMPOSER_MAX_LINES
} from './ChatComposerInput';
import { ScrollFab } from './ScrollFab';
import { MembershipBar } from './MembershipBar';
import { BottomDrawerShell } from './BottomDrawerShell';
import { EMOJI_DRAWER_HEIGHT } from '../../util/drawerMetrics';
import { ReplyKeyboardPanel } from './ReplyKeyboardPanel';
import {
  LINK_COMMAND, LINK_COPY, LINK_HASHTAG, LINK_NONE, LINK_USER, LinkAction, linkActionOf
} from '../../util/messageLinkAction';
import { SecretChatInfo } from '../../util/secretChat';
import { watchSecretChat } from '../../store/SecretChatWatch';
import { AT_BOTTOM_KEEP, AT_BOTTOM_YES, atBottomVerdict } from '../../util/atBottom';
import {
  APPEND_ANCHOR_RESTORE_BYPASSED,
  newerPageIsUserDriven, shouldHoldAppendAnchor, useUserDrivenAppendMark
} from '../../util/appendAnchor';
import { stackFromEndWanted } from '../../util/stackFromEnd';
import { shouldCapturePrependAnchor, shouldPrimePrependAnchor } from '../../util/anchorRestore';
import {
  composerBottomGap as bottomGapOf, composerPlaceholder as placeholderOf,
  replyKeyboardVisible
} from '../../util/composerChrome';
import {
  TL_NEWER_ERROR, TL_OLDER_ERROR, TL_SYNC_ERROR
} from '../../util/timelineState';
import { forwardableIds } from '../../util/messageSelection';
import { SuggestionPanel, commandLabel } from './SuggestionPanel';
// cancelEdit/draftToRestore：commitEdit（留页面）用来把编辑态摊回 idle。
// ComposerMode/clearReply/enterEdit/enterReply/idleComposer 随 composerMode
// 七字段状态机整体搬进了 ComposerSession（B9 批），页面不再需要。
import { cancelEdit, draftToRestore } from '../../util/composerMode';
import {
  SLOT_ATTACH, SLOT_EMOJI, SLOT_NONE, SLOT_REPLY_KB, claimIfFree, closeAllSlots, closeSlot,
  openSlot, toggleSlot
} from '../../util/bottomSlot';
import {
  collapseAlbums, groupIndexOf, AlbumGroup, albumSiblingIds, albumIndexOfMember
} from '../../util/collapseAlbums';
import { publishMessageRowPresentations } from '../../util/messageRowPresentationChannel';
import { shouldFillViewport } from '../../util/viewportFill';
import {
  RowFadeTransition, initialRowRevealDelay, rowFadeAnimationActive, rowFadeTransition
} from '../../util/rowFadeGate';
import {
  KEY_POWER_EFFECT_BLUR, KEY_POWER_EFFECT_MENU,
  KEY_POWER_EFFECT_REPLY,
  KEY_POWER_SMOOTH_TRANSITIONS,
  powerAnimationDuration
} from '../../store/AppSettings';
// setTranslateOptedIn/translateOptedIn/translateOptedOut/setTranslateOptedOut
// 与 getTranslationService/looksLikeTargetLanguage/resolveTranslateTarget 随
// 整簇翻译判定/驱动搬进了 TranslationDriver（B10 批），页面不再直接引用。
import {
  COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY, darkResourceMode
} from '../../util/theme';
import {
  normalizeTelegramLink, bareUsernameOf, inviteLinkOf, chatLinkActionOf,
  chatFolderInviteLinkOf, isTelegramInternalUrl, stickerSetLinkOf
} from '../../util/linkNav';
import {
  openTelegramLink, openInviteLink, openChatLinkAction, openChatFolderInviteLink, openStickerSetLink
} from '../../util/openTelegramLink';
import { openUrl } from '../../util/openUrl';
import { setDefaultReaction } from '../../util/reactions';
import { openWebUrl } from '../../util/webBrowserNav';
import { TdObject, TdRequest, TdError } from '../../tdkit/TdTypes';
import { MentionItem, CommandItem } from '../../store/InputSuggestions';
import { mentionQueryOf } from '../../util/mentionDraft';
import { buildMentionEntities, NameMention } from '../../util/mentionEntities';
import { LiveTopCardController } from './LiveTopCardController';
import { SearchSession } from './SearchSession';
import { SelectionSession } from './SelectionSession';
import { ComposerSession } from './ComposerSession';
import {
  MentionSuggestionState, CommandSuggestionState, InlineQueryState, StickerSuggestionState
} from './ComposerSuggestionState';
import { TranslationDriver } from './TranslationDriver';
import { TypingIndicatorState } from './TypingIndicatorState';
import { JumpFlashState } from './JumpFlashState';
import { VoiceRecordingState } from './VoiceRecordingState';
// bind 里 newRecorder 取值器的返回类型（等价于搬之前那句 new VoiceRecorder()）。
import { VoiceRecorder } from '../../services/VoiceRecorder';
import { MediaSaveState } from './MediaSaveState';
import { MembershipSession } from './MembershipSession';
import { ScrollAnchorController } from './ScrollAnchorController';
import { showChatFolderPicker } from '../../store/ChatActions';
import { liveLocation, LiveLocationState } from '../../services/LiveLocationService';
import { plural, str } from '../../util/strings';
import {
  ReturnState, ReturnTarget, RETURN_JUMP, RETURN_NONE, RETURN_READ,
  advanceRead, dropReachedJumps, emptyReturnState, nextReturnTarget, popJump, pushJump,
  reachedLatest
} from '../../util/readingReturn';
import { audioQueueApplies } from '../../util/audioQueueGate';
import {
  glassTintHex, overlayBlur, overlayMaterial
} from '../../util/overlayMaterial';
import { BOT_START_COMMAND, composerSlotState } from '../../util/botStart';
import { getAdministrators, AdminRow } from '../../store/ChatAdminApi';
import { adminLabelOf } from '../../util/adminLabel';
import { clearSenderRoles, publishSenderRole, senderRoleKey } from '../../util/senderRoleChannel';
import { logChatNavFailure, navigateToChat } from '../../util/chatNav';
import { hasPrefetchedPage } from '../../util/chatPrefetch';
import { subscribeChatJump } from '../../util/chatJumpChannel';
import { clearNowPlaying, NowPlaying, publishNowPlaying } from '../../util/nowPlayingChannel';
import { isSplitLayout } from '../../util/splitMetrics';
import { viewerFullScreenWanted, viewerHidesTitleBar } from '../../util/navFullScreen';
import {
  HdsNavDestination, HdsNavDestinationTitleMode, TitleBarContentOptions
} from '@kit.UIDesignKit';
import { titleBarStyle } from '../../util/hdsTitleBar';
import { navigateToChatProfile, navigateToProfile } from '../../util/profileNav';
import { beginLinkNav, endLinkNav, endLinkNavIf } from '../../util/linkTapGuard';
import { attachActions } from '../../util/attachActions';
import { AttachPanel } from './AttachPanel';
import { InlineResultsBar, StickerSuggestionBar } from './ComposerStrips';
import { copyPlainText } from '../../util/clipboard';
import {
  clientJoinNoticeRaw, hasRealClientJoinNotice, tagClientJoinNoticeGroup
} from '../../util/joinNotice';
import {
  ANCHOR_UNREAD, InitialAnchor, anchorLatchesBottom, initialAnchorOf
} from '../../util/initialAnchor';
import { isAtLiveTail, newestVisibleMessageId } from '../../util/readMarking';
import {
  MediaWindow, VisibleRange, mediaWindowRange, visibleRangeOrFallback
} from '../../util/visibleWindow';
import { openForwardOrigin } from '../../util/chatNavigation';
import {
  confirmStopLiveLocation, normalizePhoneForDial, SharedLocationUris, sharedLocationUris
} from '../../util/locationActions';
import { utilityActionAllowedAt } from '../../util/utilityActionGuard';
import { albumReuseShape, rowPlaySlotKey } from '../../util/messageBubblePrepare';
// applyTypingUpdate/pruneExpiredTyping/typingLabelOf 随 typingSenders/
// typingTimer/typingLabel 整套搬进了 TypingIndicatorState（B10 批），页面不再
// 直接引用。
import { logE, logI, logW } from '../../util/log';
import {
  chromeDarkMaskOf, chromeIconColorOf, chromeOnLightBgOf, chromeTextColorOf
} from '../../util/chatChrome';
import { requestOutcomeUncertain } from '../../util/tdRequestTimeout';
import {
  armedPageGate, canFirePageGate, draggedPageGate, firedPageGate,
  PAGE_GATE_REARM_DRAG_VP, PageGate, pageGateShotIsUserDriven, reachedNewerPageTrigger
} from '../../util/pageGate';
import {
  RememberedChatViewport, isResumeFragment, rememberChatPosition, rememberedChatViewport
} from '../../util/chatResume';
import { conversationScopeId } from '../../util/messageTopicScope';
import { navigateToSearch } from '../../util/searchNav';
import { forwardDirect } from '../../store/ForwardDirect';
import { getActiveTdUserId } from '../../tdkit/Globals';
import {
  canRenderLightweightPlainText, formattedTextReuseShape,
  MessageBubbleReuseContext
} from '../../util/messageBubbleReuse';
import { chatChromeHeight, ChatChromeGeometryInput, chatTopBannerHeight } from '../../util/ChatChromeGeometry';
import {
  initialMessageViewportRows, nextInitialMessageRevealCount, stageInitialMessageGroups
} from '../../util/initialMessageStage';
import {
  ChatTimelineSnapshot, coalesceChatTimelineSnapshot, emptyChatTimelineSnapshot
} from '../../util/chatTimelineSnapshot';
import { ChatViewportGeometry } from '../../util/chatViewportGeometry';
// ⚠️ 临时（P6 标定）：cachedCount 档位调试项。标定结束后按
// util/debugListPerf.ets 末尾的清单删除。
import { LIST_CACHED_COUNT_DEFAULT } from '../../util/debugListPerf';
import {
  ChatPageHiddenHooks, ChatPageShownHooks, ChatPageShownState, ChatPageWillHideHooks,
  coordinateChatPageHidden, coordinateChatPageShown, coordinateChatPageWillHide,
} from '../../util/chatPageLifecycle';
import {
  ChatPageNavigationCoordinator, parseChatRouteParams
} from '../../util/ChatPageNavigationCoordinator';
import { ChatPageSubscriptionRegistry } from '../../util/ChatPageSubscriptionRegistry';
// 以下五组是 B1 从本文件顶部搬走的模块级声明，现在从 util 导入。
import { chatEffectDurationOf } from '../../util/chatEffects';
import {
  INITIAL_BOTTOM_PRESENT_MIN_MS,
  INITIAL_MESSAGE_RELEASE_DELAY_MS, INITIAL_MESSAGE_TRANSITION_SETTLE_MS,
  INITIAL_TIMELINE_PRESENT_MIN_MS, INITIAL_TIMELINE_REVEAL_ROW_LIMIT,
  INITIAL_TIMELINE_ROW_FADE_MS, INITIAL_TIMELINE_ROW_STAGGER_MS,
  JUMP_LANDING_GRACE_MS, JUMP_RELOAD_THRESHOLD, KEYBOARD_SETTLE_MS,
  MENU_DISMISS_MS, NOW_SEC_TICK_MS, PREPARED_MESSAGE_CACHE_LIMIT,
  REUSE_CAP_MIN_INTERVAL_MS, STICKER_FLY_MS,
  STICKER_GHOST_SIDE
} from '../../util/chatPageTuning';
import { DICE_CHOICES, DiceChoice } from '../../util/diceChoices';
import { mediaEntryIsPhoto, mediaEntryIsVideo } from '../../util/mediaEntryKind';
// 别名保持原类名，4 处 new ChatPageFrameCallback(...) 调用点一字未动。
import { OneShotFrameCallback as ChatPageFrameCallback } from '../../util/oneShotFrameCallback';

// 锚点补偿：量不到锚点行时下一帧再量，最多几次、每次隔多久（见 restoreScrollAnchor）。

interface PreparedMessageBubble {
  group: AlbumGroup;
  data: MessageBubbleRenderData;
}

interface InitialMessageStageTarget {
  anchorIndex: number;
  alignFromStart: boolean;
  availableRows: number;
}

// applyRouteParams 的阶段间上下文：只在 A->C 之间传递的路由派生量。
interface RouteApplyContext {
  jumpTo: number | undefined;
}

// 向上翻页的锚点采样（与下面 append 那组是镜像判据，不是重复代码，不合并）。
interface PrependAnchorSample {
  id: number;
  y: number;
  userOffset: number;
  prime: boolean;
}

// 向下翻页的锚点采样。
interface AppendAnchorSample {
  id: number;
  y: number;
  userOffset: number;
}

type InitialMessageReleaseResult = 'released' | 'waiting' | 'finished';

// Emoji offered in the full reaction picker (opened from the long-press menu's
// chevron). Ordered roughly like the official client's reaction sheet.
@ComponentV2
export struct ChatPage {
  // The API 26 pool is shared by every ChatPage still in the navigation stack.
  // Scope bucket ids to this concrete page so a row recycled by chat A can
  // never be re-parented into chat B while chat A is still alive underneath.
  private reusePageScope: number = allocateChatPageReuseScope();
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
  // 本机自选壁纸的代次。V2 组件用不了 @StorageProp，照既有分工由 ChatPageChrome
  // 订阅后作为 @Param 传下来（materialEpoch / appDark 都是这么走的）。
  @Require @Param localBgEpoch: number = 0;
  // 聊天壁纸的三根滑杆。由 ChatPageChrome 订阅后传下来（V2 用不了 @StorageProp）。
  //
  // 模糊度这一根（KEY_BG_BLUR）拖动时要立即重算离屏合成图，否则拖完滑块背景看
  // 起来没反应（命中旧签名的缓存图）。这句原本是 366df3e 写在字段上方的两行注释，
  // 字段搬去 ChatPageChrome 时上半句跟着走了、下半句被落在 autoplayVideo 后面成了
  // 没有上文的「否则…」，2026-09-05 瘦身批 B3 归位。
  @Require @Param chatBgBlur: number = 0;
  @Require @Param chatBgPattern: number = 0;
  @Require @Param chatBgDim: number = 0;
  @Require @Param topSafe: number = 0;
  @Require @Param bottomSafe: number = 0;  // ✅ 新增
  @Require @Param keyboardH: number = 0;
  @Require @Param appIsForeground: boolean = true;
  // ⚠️ 临时（P6 标定）：List 的 cachedCount 档位，由 ChatPageChrome 透传。
  // 不是 @Require —— 少数直接 new ChatPage 的调用点（预览）没有它时用默认档。
  @Param listCachedCount: number = LIST_CACHED_COUNT_DEFAULT;
  @Local messages: MessageEntry[] = [];
  private messageLoadState: string = 'loading'; // loading | ready | error
  private messageLoadError: string = '';
  private olderLoadState: string = 'idle'; // idle | loading | error | end
  private newerLoadState: string = 'idle'; // idle | loading | error | end
  // **完整快照**的行数，不是当前渲染的行数——首屏分级渲染期间 groups 里坐着
  // 占位副本，长度一样，所以两者此刻仍然相等；将来若有别的分级形状，这个计数
  // 要跟着"用户最终会看到多少行"走。它驱动的是空/加载中的时间线提示。
  private visibleGroupCount: number = 0;
  // 消息列表的内部真相。Repeat 和 MediaViewerOverlay 不直接订阅这个普通字段；
  // publishGroupsNow 把它连同加载/分页状态一次性装进 timelineSnapshot 发布。
  private groups: AlbumGroup[] = [];
  @Local private timelineSnapshot: ChatTimelineSnapshot = emptyChatTimelineSnapshot();
  private viewportGeometry: ChatViewportGeometry = new ChatViewportGeometry();
  // 只剩图片预取源，不再是列表的数据源（见 AlbumGroupDataSource 文件头）。
  private groupsData: AlbumGroupDataSource = new AlbumGroupDataSource();
  // 强制整表重建用的纪元，进 rowKeyOf。Repeat 没有 LazyForEach 的 reload()——
  // 让每一行的 key 都改变就是它的等价物（官方：键值变化会触发页面刷新）。
  // 两个调用点：语言纪元变化、从后台回来的重新对齐。见 rebuildAllRows()。
  private listRebuildEpoch: number = 0;

  // Repeat key identifies the logical row, not its current contents. Repeat
  // refreshes a stable-key node when its item object changes; using content or
  // album members here deletes the visible boundary row when an older page
  // completes an album, which makes List lose its position anchor.
  private rowKeyOf: (g: AlbumGroup) => string = (g: AlbumGroup): string =>
    repeatRowKey(g, this.langEpoch, this.listRebuildEpoch);

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
  // 隐藏那一刻是不是正贴着底，以及当时最后一行的消息 id。两者一起回答「隐藏
  // 期间列表动没动」——没动就别松开贴底（issue #62），见 resyncListAfterHidden。
  private hiddenAtBottom: boolean = false;
  private hiddenNewestId: number = 0;

  private timelineGeometryDividerId(): number {
    if (this.resumeDividerId > 0) {
      return this.resumeDividerId;
    }
    if (this.firstUnreadId > 0) {
      return this.firstUnreadId;
    }
    return this.store !== null ? this.store.getFirstUnreadId() : 0;
  }

  private replaceTimelineGroups(groups: AlbumGroup[]): void {
    this.viewportGeometry.reconcile(
      this.chatId,
      conversationScopeId(this.threadRootId, this.forumTopicId, this.directMessagesTopicId),
      groups,
      this.screenW,
      this.langEpoch,
      this.timelineGeometryDividerId()
    );
    this.groups = groups;
  }

  private commitTimelineSnapshot(): void {
    const next: ChatTimelineSnapshot = coalesceChatTimelineSnapshot(this.timelineSnapshot, {
      groups: this.groups, visibleGroupCount: this.visibleGroupCount,
      messageLoadState: this.messageLoadState, messageLoadError: this.messageLoadError,
      olderLoadState: this.olderLoadState, newerLoadState: this.newerLoadState,
      isChannel: this.isChannel, isGroup: this.isGroup
    });
    if (next !== this.timelineSnapshot) {
      this.timelineSnapshot = next;
    }
  }

  // 发布一份新的行快照。**唯一**给 this.groups 赋值的地方（rebuildAllRows 除外）。
  //
  // reuseUnchangedRows 是这里唯一的"聪明"步骤，理由写在它自己的注释里：
  // collapseAlbums 每次都产出全新对象，而 Repeat 按 item 引用判断要不要刷新，
  // 不还原没变过的行就等于每次发布都刷新整个可见窗口。
  private publishGroupsNow(groups: AlbumGroup[]): void {
    const next: AlbumGroup[] = reuseUnchangedRows(this.groups, groups);
    const changed: boolean = !sameRowArray(this.groups, next);
    // 全等的一次发布不换数组引用：@Local 的通知是按引用发的，换一个逐项相同
    // 的新数组照样通知 ⇒ Repeat 照样跑一遍 diff。changed 本来就算好了，用上。
    if (changed) {
      // 删消息时让剩下的行平滑合拢（issue #149）。**只有这一种发布带动画**：
      // 判据见 util/rowRemoval —— 行变少、且少掉的那几行前后都还有行留着。
      // 往上翻页时从一头砍掉旧行同样是"行变少"，但那是滚动热路径，绝不能动画。
      // 判据只在行数变少时才跑，平时零成本。
      if (next.length < this.groups.length &&
        isInteriorRowRemoval(
          this.groups.map((g: AlbumGroup): number => g.head.id),
          next.map((g: AlbumGroup): number => g.head.id))) {
        animateTo({
          duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 200),
          curve: Curve.EaseOut
        }, (): void => {
          this.replaceTimelineGroups(next);
          this.commitTimelineSnapshot();
        });
      } else {
        this.replaceTimelineGroups(next);
      }
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
    // Loading/paging flags and rows become visible to ChatTimelineHost through
    // one immutable publication, after this whole transaction is complete.
    this.commitTimelineSnapshot();
  }

  // 让 Repeat 整表重建：每一行的 key 都换掉。
  //
  // LazyForEach 时代这是 AlbumGroupDataSource.reload()（一条 RELOAD 通知）。
  // Repeat 没有对应的命令式接口，但官方写明「键值变化或数据变化均会触发页面
  // 刷新」，所以把纪元推进一格、再换一个新数组交出去，效果等价：所有 key 都变
  // 成新 key ⇒ 全部删旧插新。行对象本身原样复用，内容一个字都没动。
  private rebuildAllRows(): void {
    this.listRebuildEpoch++;
    this.replaceTimelineGroups(this.groups.slice());
    this.commitTimelineSnapshot();
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
    // A selected remembered position is a first-frame START anchor just like
    // unread, but it has no read-state semantics. Check it before asking the
    // store for firstUnreadId (which is correctly 0 in a fully-read chat).
    if (this.resumeDividerId > 0) {
      const resumeIndex: number = groupIndexOf(groups, this.resumeDividerId);
      if (resumeIndex >= 0) {
        return {
          anchorIndex: resumeIndex,
          alignFromStart: true,
          availableRows: Math.max(0, groups.length - resumeIndex)
        };
      }
    }
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
    const unreadId: number = this.resumeDividerId > 0
      ? this.resumeDividerId
      : (this.firstUnreadId > 0
        ? this.firstUnreadId : (this.store !== null ? this.store.getFirstUnreadId() : 0));
    return initialMessageViewportRows(
      groups,
      target.anchorIndex,
      target.alignFromStart,
      this.screenW,
      viewportHeight,
      unreadId,
      (group: AlbumGroup, _screenWidth: number, _showDivider: boolean): number =>
        this.viewportGeometry.rowHeight(group)
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
    // Normally the viewport-sized stage finishes before the mask is removed. A
    // bounded initial-history fill can deliberately keep it waiting, though;
    // once the user touches the list, ownership must transfer in that same
    // gesture. The old code returned while initialTimelineMasked was true and
    // the List itself was disabled during that interval. A finger that went
    // down in the first layout window therefore stayed attached to a disabled
    // target for its whole 3~5 second drag, even after the timeline appeared.
    if (!this.initialMessageStageActive && !this.initialTimelineMasked) {
      return;
    }
    if (this.initialMessageStageActive) {
      const groups: AlbumGroup[] = this.initialMessagePendingGroups ?? this.groups;
      this.initialMessageStageSeq++;
      this.finishInitialMessageStage(groups);
    }
    if (!this.initialTimelineMasked) {
      return;
    }
    // finishInitialMessageStage may just have queued the normal two-frame
    // presentation. Invalidate it before exposing the list: otherwise its
    // settleInitialTimelineAnchor() would run after the user's drag begins and
    // visibly pull the viewport back to the unread marker/bottom.
    this.initialTimelinePresentationSeq++;
    this.initialTimelinePresentationScheduledSeq = 0;
    this.initialTimelineReadyToPresent = false;
    this.settleInitialTimelineAnchor();
    this.cancelInitialMessageTransitionSettle();
    this.initialMessageTransitionSettled = true;
    this.revealInitialTimeline();
  }

  // 遮罩掀开的那一下。
  //
  // 逐行的淡入由行自己的 transition 负责（visibility 由 Hidden 翻 Visible 是它
  // 的触发条件之一，stagger 一并保住）。这里再包一次 animateTo，是给整层
  // List 的 opacity 一个兜底的淡入：万一某一帧行的 transition 没能起跑，用户
  // 看到的仍是一次 90ms 的整屏淡入，而不是硬跳。时长与曲线同为
  // INITIAL_TIMELINE_ROW_FADE_MS / EaseOut。
  //
  // 只包这一句：initialMessageTransitionSettled 归底部 dock 自己的动画管，
  // 一起包进来会变成双重动画。
  private revealInitialTimeline(): void {
    animateTo({
      duration: powerAnimationDuration(
        KEY_POWER_SMOOTH_TRANSITIONS, INITIAL_TIMELINE_ROW_FADE_MS),
      curve: Curve.EaseOut
    }, (): void => {
      this.initialTimelineMasked = false;
    });
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

  private scrollToTimelineIndexAtY(index: number, itemY: number = 0): void {
    this.scroller.scrollToIndex(index, false, ScrollAlign.START);
    if (Number.isFinite(itemY) && Math.abs(itemY) > 0.5) {
      // START puts the row at y=0. Restore the captured partial-row offset so
      // leaving and reopening a chat returns to the same viewport geometry.
      this.scroller.scrollBy(0, -itemY);
    }
  }

  private settleInitialTimelineAnchor(): void {
    if (!this.didInitialScroll || this.groups.length === 0) {
      return;
    }
    if (this.resumeDividerId > 0) {
      const resumeIndex: number = groupIndexOf(this.groups, this.resumeDividerId);
      if (resumeIndex >= 0) {
        this.scrollToTimelineIndexAtY(resumeIndex, this.resumeDividerItemY);
      }
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
        this.revealInitialTimeline();
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
    this.hiddenAtBottom = false;
    this.hiddenNewestId = 0;
    if (!this.didInitialScroll ||
      this.curStartIdx < 0 || this.curStartIdx >= this.groups.length) {
      return;
    }
    this.hiddenAtBottom = this.atBottom;
    this.hiddenNewestId = this.groups[this.groups.length - 1].head.id;
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
    const wasAtBottom: boolean = this.hiddenAtBottom;
    const newestBefore: number = this.hiddenNewestId;
    this.hiddenAnchorId = 0;
    this.hiddenAnchorY = 0;
    this.hiddenAtBottom = false;
    this.hiddenNewestId = 0;
    // 迁 Repeat 之前这里是 groupsData.reload()。等价物见 rebuildAllRows()。
    this.rebuildAllRows();
    const newestNow: number = this.groups.length > 0
      ? this.groups[this.groups.length - 1].head.id : 0;
    if (anchorId > 0 && wasAtBottom && newestBefore > 0 && newestNow === newestBefore) {
      // 隐藏期间一条新消息都没来，而隐藏时正贴着底：列表没动过，没什么可还原的，
      // **贴底也不能松**（issue #62）。松开之后只有 onScrollIndex 会把它判回来，
      // 而没有位移就没有滚动回调，atBottom 从此一直是 false，之后每条新消息都
      // 被当成"用户不在底部"不跟随——「锁屏解锁后就不滚了」正是这条路。
      //
      // 不改成"还原完再补判一次"：还原本身跑在 setTimeout 里、量不到还会重试
      // （attemptAnchorRestore），补判会插在中间，用一个还没落位的 isAtEnd 下
      // 结论，反而可能把用户从还原点拽到底部。
      logW(`[Follow62] resume kept atBottom rows=${this.groups.length} newest=${newestNow}`);
    } else if (anchorId > 0) {
      // 先松开贴底：还原发起到 onScrollIndex 回调落地之间，atBottom 还是隐藏
      // 前那个 true，这期间任何一条到达通知都会走"在底部就跟随"那一支
      // （见 L1242）把视口又拽回底部。同文件 1216 / 1227 两处也是这个写法。
      //
      // 走到这里的两种情况：隐藏时不在底部（本来就该还原到原位），或者隐藏期间
      // 来了新消息——后者按 3ff77fc 的有意设计仍然停在原位，新消息留在下方由
      // 「↓」带未读数指回去，不自动甩到最新。
      this.atBottom = false;
      this.anchor.restorePrependAnchor(this.groups, anchorId, anchorY);
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
        onFileTap: (messageId: number): void => { this.mediaSave.onFileTap(messageId); },
        onFileSave: (messageId: number): void => { this.mediaSave.onFileSave(messageId); },
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
          this.playSlot.reportMedia(messageId, albumIndex, ratio, centerY);
        },
        onMediaGone: (messageId: number, albumIndex: number): void => {
          this.playSlot.dropMedia(messageId, albumIndex);
        },
        onPlaySlotPositionChanged: (messageId: number, _albumIndex: number,
          positionMs: number): void => {
          this.playSlot.recordPosition(messageId, positionMs);
        },
        onPlaySlotEnded: (messageId: number, albumIndex: number): void => {
          this.playSlot.retire(messageId, albumIndex);
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
        onEditMsg: (messageId: number): void => { this.composer.startEdit(messageId); },
        onShowReactors: (messageId: number, emoji: string): void => {
          this.overlayState.showReactors(messageId, emoji);
        },
        onTranslateMsg: (messageId: number): void => {
          this.translateMessage(messageId);
        },
        onToggleTranslation: (messageId: number, hidden: boolean): void => {
          this.translation.toggleHidden(messageId, hidden);
        },
        onRetryTranslation: (messageId: number): void => {
          this.translation.translateInline(messageId);
        },
        onPinMsg: (messageId: number, unpin: boolean): void => {
          this.togglePinMessage(messageId, unpin);
        },
        onStopPoll: (messageId: number): void => { this.stopPoll(messageId); },
        onReplaceMedia: (messageId: number): void => { this.attach.replaceMedia(messageId); },
        onPollVoters: (messageId: number): void => { this.showPollVoters(messageId); },
        onSetDefaultReaction: (emoji: string): void => { setDefaultReaction(emoji); },
        onSetReaction: (messageId: number, emoji: string, chosen: boolean): void => {
          this.overlayState.toggleReaction(messageId, emoji, chosen);
        },
        onReplyTo: (messageId: number): void => { this.composer.startReply(messageId); },
        onCopyText: (messageId: number): void => { this.copyMessageText(messageId); },
        onSelectText: (messageId: number): void => { this.openSelectText(messageId); },
        onCopyLink: (messageId: number): void => { this.copyMessageLink(messageId); },
        onForwardMessages: (messageIds: number[]): void => { this.openForwardPicker(messageIds); },
        onSaveMessages: (messageIds: number[]): void => { this.saveToSavedMessages(messageIds); },
        onRepeatMessages: (messageIds: number[]): void => { this.repeatMessages(messageIds); },
        onViewSenderHistory: (senderId: number): void => { this.search.enterForSender(senderId); },
        onReportMsg: (_messageId: number): void => {
          promptAction.showToast({ message: $r('app.string.cp_report_wip'), duration: 1500 });
        },
        onSelectMessages: (messageIds: number[]): void => { this.selection.enter(messageIds); },
        onDeleteMsg: (messageId: number): void => { this.deleteMessage(messageId); },
        onOpenReactions: (messageId: number): void => { this.overlayState.openReactionSheet(messageId); },
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
        onLiveStreamTap: (_groupCallId: number): void => { this.topCard.onLiveStreamTap(); }
      };
    }
    return this.messageActionsCache;
  }

  // 两个形状串的算法住在 util/messageBubblePrepare.ets（连同它们的【为什么】
  // 注释），由 entry/src/test/MessageBubblePrepare.test.ets 钉住。这里只剩最薄
  // 的一层：读 this.playSlotKey 传进去，不新建对象、不打日志——每行每帧各调
  // 一次，是消息行的热路径。
  private albumReuseShape(g: AlbumGroup): string {
    return albumReuseShape(g, this.playSlotKey);
  }

  private rowPlaySlotKey(g: AlbumGroup): string {
    return rowPlaySlotKey(g, this.playSlotKey);
  }

  // Prepare the row once for this build invocation. `data` used to repeat all
  // of these derived lookups independently for every visible row.
  private prepareMessageBubble(g: AlbumGroup): PreparedMessageBubble {
    // 行局部的播放位。起播位置同理：只有拥有播放位的那一行才谈得上续播位置，
    // 其余行给 0——否则它一变，整屏的缓存又一起作废。
    const rowSlot: string = this.rowPlaySlotKey(g);
    const rowSlotStartMs: number = rowSlot === '' ? 0 : this.playSlotStartMs;
    const paused: boolean = this.animationPaused(g.head.id);
    const forcePlay: boolean = this.animationForcePlay(g.head.id);
    const playbackFailed: boolean = this.animationPlaybackFailed(g.head.id);
    const audio: boolean = audioQueueApplies(g.head.contentType);
    const showUnreadDivider: boolean = this.firstUnreadId !== 0 &&
      g.memberIds.indexOf(this.firstUnreadId) >= 0;
    const showResumeDivider: boolean = this.resumeDividerId !== 0 &&
      g.memberIds.indexOf(this.resumeDividerId) >= 0;
    const showTimelineDivider: boolean = showUnreadDivider || showResumeDivider;
    const translationActive: boolean = this.translation.active(this.translateChatsEnabled);
    const isPinnedMsg: boolean = (this.store?.getPinnedIds() ?? []).indexOf(g.head.id) >= 0;
    const paidMediaPending: boolean = this.paidMediaPending(g.head.id);
    const editingActive: boolean = this.composer.isEditing();
    const animateIn: boolean = this.freshSinceId !== 0 && g.head.id > this.freshSinceId;
    const liveGroupCallId: number = this.topCard.liveCallIsActive ? this.topCard.liveGroupCallId : 0;
    // nowSec changes every second, but only these two reuse decisions cross a
    // time boundary. Key the decisions instead of invalidating every prepared
    // row every second; the live clock itself is passed outside the cache.
    const menuEditable: boolean = g.head.isOutgoing && this.nowSec - g.head.date < 172800;
    const pollExpired: boolean = g.head.pollCloseDate > 0 && this.nowSec >= g.head.pollCloseDate;
    const cacheKey: string = `${this.rowKeyOf(g)}|c${this.chatId}` +
      `|g${this.isGroup ? 1 : 0}${this.isChannel ? 1 : 0}` +
      `|u${showUnreadDivider ? 1 : 0}|r${showResumeDivider ? 1 : 0}` +
      `|tr${translationActive ? 1 : 0}` +
      `|editable${menuEditable ? 1 : 0}|poll${pollExpired ? 1 : 0}` +
      `|pin${isPinnedMsg ? 1 : 0}|paid${paidMediaPending ? 1 : 0}` +
      `|anim${paused ? 1 : 0}${forcePlay ? 1 : 0}${playbackFailed ? 1 : 0}` +
      `|edit${editingActive ? 1 : 0}|fresh${animateIn ? 1 : 0}` +
      `|live${this.liveLocationMessageId}|call${liveGroupCallId}` +
      `|slot${rowSlot}|slotms${rowSlotStartMs}` +
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
      showUnreadDivider: showTimelineDivider,
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
      playSlotActive: rowSlot === slotKey(g.head.id, -1),
      animationPaused: paused,
      animationForcePlay: forcePlay,
      animationPlaybackFailed: playbackFailed,
      isPinnedMsg,
      liveSharing: this.liveLocationMessageId === g.head.id,
      paidMediaPending,
      liveVideoChatTappable: g.head.isVideoChatStarted && this.topCard.liveCallIsActive,
      audioQueuePosition,
      audioQueueLength,
      pollExpired
    };
    const lightweightPlainText: boolean = canRenderLightweightPlainText(g.head, context);
    const data: MessageBubbleRenderData = {
      chatId: this.chatId, isGroup: this.isGroup, isChannel: this.isChannel,
      liveSharingId: this.liveLocationMessageId, themeBubbleOut: this.chatBg.bubbleOutColor,
      showUnreadDivider: showTimelineDivider,
      dividerIsResume: showResumeDivider,
      paidMediaPending,
      audioQueuePosition,
      audioQueueLength,
      audioHasPrevious,
      audioHasNext,
      playSlotKey: rowSlot, autoplayMuted: this.autoplayMuted,
      playSlotStartMs: rowSlotStartMs,
      animationPaused: paused,
      animationForcePlay: forcePlay,
      animationPlaybackFailed: playbackFailed,
      editingActive,
      isPinnedMsg,
      liveGroupCallId: this.topCard.liveCallIsActive ? this.topCard.liveGroupCallId : 0,
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
  // 页面作用域已经进 reuseId，所以一个桶只属于一个 ChatPage；容量按单页算。
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
  // 只在**滚动停下**时跑，不在滚动中或页面退出时跑：赋值 maxCount 会触发框架
  // 的异步清理，前者会制造滚动抖动，后者会与 NavDestination 销毁转场争抢帧预算。
  // 用户实际滚过列表时自然会走 scrollStop；若在 fling 中直接退出，下一次会话的
  // scrollStop 再收口即可，shared 池短暂多留几项比退出掉帧更可控。
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
        reuseBucketMaxCount(rows, this.listCachedCount));
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
  // 所以在旧行为下会被降级成单一的 'ReusableMessageBubble'，CHAT_PAGE_REUSE_ID_LEVEL 的
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
        `chatPage${this.reusePageScope}_` +
          rowReuseId(this.prepareMessageBubble(ri.item).data, ri.item, CHAT_PAGE_REUSE_ID_LEVEL)
    });
  }
  // "×× 正在输入…" 提示的状态与轮询定时器整套搬进了 TypingIndicatorState
  // （B10 批）：composerPlaceholder 改读 this.typing.label（原 @Local
  // typingLabel），到期表与定时器句柄收进了控制器的私有普通字段。
  //
  // 字段初始化器 new：首帧前就已存在、引用全生命周期稳定、类型非空。禁止做成
  // 模块级单例：平板分栏/导航栈多层时同时活着多个 ChatPage，各自会话的输入
  // 提示互不相干。
  private typing: TypingIndicatorState = new TypingIndicatorState();
  private subscriptions: ChatPageSubscriptionRegistry = new ChatPageSubscriptionRegistry();
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
  // TDLib per-chat wallpaper. Solid/gradient fills render immediately;
  // wallpaper and pattern documents appear as soon as downloadFile completes.
  // One snapshot in place of the nine background state variables this replaces.
  // Resolution (chat background → theme → account default → installed default)
  // and its four TDLib subscriptions live in ChatBackgroundStore.
  @Local chatBg: ChatBackgroundState = emptyChatBackground();

  // ── chrome 的前景要跟着**壁纸**翻，不是跟着深浅色模式 ───────────────────
  //
  // 判据、叠加公式与真机对比度数字全部住在 util/chatChrome.ets，由
  // entry/src/test/ChatChrome.test.ets 钉住；这里只剩「读字段 → 调纯函数」的
  // 薄包装。glassTintHex(true) 留在页面侧：玻璃厚度是设备态（依赖
  // immersiveMaterialAvailable()），不能进纯函数。
  private chromeOnLightBg(): boolean {
    return chromeOnLightBgOf(this.appDark, this.chatBg.colors, glassTintHex(true),
      this.chromeDarkMask());
  }

  private chromeDarkMask(): number {
    return chromeDarkMaskOf(this.chatBg.dimming, this.chatBgDim);
  }

  private chromeIcon(): ResourceColor {
    return chromeIconColorOf(this.chromeOnLightBg(), this.appDark);
  }

  private chromeText(): ResourceColor {
    return chromeTextColorOf(this.chromeOnLightBg());
  }
  private bgStore: ChatBackgroundStore | null = null;
  // 输入框上方那一条（普通输入 / 回复某条 / 编辑某条）的状态机整套搬进了
  // ComposerSession（B9 批）：9 个 @Local（replyToId/replyToName/replyToText/
  // replyToThumb/replyToThumbSticker/editingId/editingKind/editingPreview 与
  // 内部机件 draftBeforeEdit）全部住进了控制器，变成 @Trace（draftBeforeEdit
  // 仍是不带 @Trace 的私有字段），字段名与初值一字未改。ChatComposerInput
  // 还没有改成直读控制器（本轮任务范围未触达该文件），页面继续把
  // this.composer.xxx 当标量转手传给它，依赖粒度与搬之前一一对应。
  //
  // 字段初始化器 new：首帧前就已存在、引用全生命周期稳定、类型非空。禁止做成
  // 模块级单例：平板分栏/导航栈多层时同时活着多个 ChatPage，各自的回复/编辑态
  // 互不相干。
  private composer: ComposerSession = new ComposerSession();
  // 反应弹层（showReactionSheet/reactionTargetId/reactionPendingKey）、转发
  // 弹层（showForwardSheet/forwardMessageIds）、投票/联系人/录像笔记/定时消息
  // 四个弹层开关，以及贴纸"飞出"残影动画（stickerGhostPath/X/Y/Fly/Timer）
  // 整簇搬进了 ChatOverlayState（B11 批），字段名与初值一字未改，原有注释随
  // 字段一并搬进 ChatOverlayState.ets，此处不再重复。页面侧统一经
  // this.overlayState.xxx 读写。`paidMediaPendingIds` 不属于本簇，原地留在页面。
  //
  // 字段初始化器 new：首帧前就已存在、引用全生命周期稳定、类型非空。禁止做成
  // 模块级单例：平板分栏/导航栈多层时同时活着多个 ChatPage，各自会话的弹层
  // 状态互不相干。
  private overlayState: ChatOverlayState = new ChatOverlayState();
  @Local paidMediaPendingIds: number[] = [];
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
  // 顶栏下挂那张浮卡（置顶消息条 + 直播/群通话条）的整套状态机（B5 批）。原来
  // 摊在这里的 14 个 @Local（pinnedPreview/pinnedCount/pinnedLoadState/
  // pinnedJumpBusy/pinnedCycle/liveGroupCallId/liveCallIsActive/liveCallIsRtmp/
  // liveParticipantCount/livePulseExpanded/liveLoadState/liveDialogOpening/
  // liveNavigationBusy/topCardLoadingVisible）与 9 个内部机件字段（4 个定时器
  // 句柄、2 个在途标志、2 个序号守卫、1 个请求 id）全部住进了控制器，字段名和
  // 初值一字未改，只是 @Local 变成了 @Trace。
  //
  // 字段初始化器 new：首帧前就已存在、引用全生命周期稳定、类型非空——TopBanners
  // 拿 @Param 收它，引用不变，那层 `!==` 永不成立，页面重建不会让浮卡整体白刷。
  // 禁止做成模块级单例：平板分栏/导航栈多层时同时活着多个 ChatPage，每个都有
  // 自己的 chatId、自己的 group call、自己的置顶轮转位置。
  //
  // 【收窄】livePulseExpanded 每 780ms 翻一次。搬之前那是本页的 @Local，于是每
  // 780ms 都要重跑 chatTitleBarBottom 闭包 + 逐个比较 TopBanners 的 13 个 @Param；
  // 现在 TopBanners 直接读控制器的 @Trace，翻转只刷新读到它的那几个节点，本页
  // 一个字都不读。页面仍要读的只剩三处：chatTitleBarContent 的 shouldShow()、
  // chromeGeometryInput 的三个几何输入、prepareMessageBubble cacheKey 里的
  // liveCallIsActive/liveGroupCallId——都是 this.x → this.topCard.x 的逐处替换，
  // 依赖粒度与搬之前一一对应。
  private topCard: LiveTopCardController = new LiveTopCardController();
  private chatId: number = 0;
  private botCallbackPending: Set<string> = new Set();
  // >0: comment-thread view over the linked discussion group (see onCommentTap)
  private threadRootId: number = 0;
  private topicName: string = '';
  private forumTopicId: number = 0;
  private directMessagesTopicId: number = 0;
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
  // 成员资格状态机控制器（第二轮 R2-A 批）：refreshMembership/
  // applyMembershipStatus 连同 membershipSupergroupId/membershipBasicGroupId/
  // membershipSeq 三个记账字段一并搬入。membershipState 本身按 B8 的所有权
  // 裁决留在上面（@Local membershipState），只经 setMembershipState 这个
  // setter 被写；详见 MembershipSession.ets 文件头【甲】节。
  private membership: MembershipSession = new MembershipSession();
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
  // 首屏逐条淡入这条动画的时间戳闩，**故意不进状态**：它只被 build 读，
  // 自己变化不该引起重渲染（那正是要治的病）。见 util/rowFadeGate。
  private initialRowFadeArmedAt: number = 0;
  private initialTimelineReadyToPresent: boolean = false;
  private initialTimelinePresentationSeq: number = 0;
  private initialTimelinePresentationScheduledSeq: number = 0;
  private initialTimelineEarliestAt: number = 0;
  @Local private initialMessageTransitionSettled: boolean = false;
  private initialMessageReleaseTimer: number = -1;
  private chatTgsScrollActive: boolean = false;
  private chatTgsStageSettling: boolean = false;
  private chatTgsResumeTimer: number = -1;
  // 播放位竞选簇整簇搬进了 PlaySlotDriver（第二轮 R2-C）：候选表、定时器闭环、
  // 气泡进度表与两处查看器交接都在那边，页面只留下面两个 @Local（它们的读点在
  // prepareMessageBubble 的热路径上，搬走没有半径收益、只有一跳开销）。
  private playSlot: PlaySlotDriver = new PlaySlotDriver();
  @Local playSlotKey: string = '';
  // 新上位的播放位从哪一毫秒起播。换届时从 bubblePositionMs 查一次（见
  // subscribe 回调），随 playSlotKey 一起下发给气泡——查看器交还的进度就是
  // 靠这条路真正接到 VideoBubbleSurface.startPositionMs 上的。
  @Local playSlotStartMs: number = 0;
  // 缓存设置 → 自动播放静音开关，唯一消费点：下发给气泡播放器的 muted。
  @Require @Param autoplayMuted: boolean = true;
  // 全屏查看器当前播放进度：只在查看器打开期间被 onPositionChanged 回调更新，
  // 关闭时读一次写回 bubblePositionMs，同样是普通字段，不驱动渲染。
  private viewerPositionMs: number = 0;
  // 打开查看器那一刻从 bubblePositionMs 取到的起播位置，一次性字段，供
  // MediaViewerOverlay 构造时读取（与 viewerInitIdx 同一模式）。
  private viewerStartPositionMs: number = 0;
  private lastMaxId: number = 0;
  @Local atBottom: boolean = true;
  // 整聊天翻译有两层，菜单里的那一项在两层之间切换含义：
  //   总开关开着 —— 默认所有会话都翻，菜单是"关掉这个会话"（本地排除名单）。
  //   总开关关着 —— 默认都不翻，菜单是"只翻这个会话"（服务端 is_translatable，
  //                 跟官方客户端同一个字段，多端同步）。
  // 早先只认服务端那个字段，它对没碰过的会话默认 false，结果开了总开关每个群
  // 还得手动点一次才翻，实际不可用。
  @Local isTranslatable: boolean = false;
  // 会话级排除/加入名单（原 translateChatOptOut/translateChatOptIn 两个
  // @Local）连同三态判定、批量翻译驱动、单条重译/隐藏、会话级开关切换整套
  // 搬进了 TranslationDriver（B10 批），变成控制器的 optOut/optIn 两个
  // @Trace。isTranslatable 按 B8 的所有权裁决留在页面（被 cacheKey、成员资格
  // 状态机、ScrollFab 未读徽标等身份簇之外的多个域共同读写），控制器经
  // host.isTranslatable()/setIsTranslatable() 现取现写，不存影子拷贝；
  // translateChatsEnabled（@Param）同样不进控制器，由每个需要它的调用点
  // 显式传参。
  //
  // 字段初始化器 new：首帧前就已存在、引用全生命周期稳定、类型非空。禁止做成
  // 模块级单例：平板分栏/导航栈多层时同时活着多个 ChatPage，每个会话的翻译
  // 开关互不相干。
  private translation: TranslationDriver = new TranslationDriver();
  @Require @Param translateChatsEnabled: boolean = false;
  // 是否正在共享实时位置（全局单例状态，不限于当前会话）。
  @Local liveLocationActive: boolean = false;
  @Local liveLocationMessageId: number = 0;
  // 贴纸"飞出"残影（stickerGhostPath/X/Y/Fly）与其收尾定时器句柄
  // （stickerGhostTimer）搬进了 ChatOverlayState（B11 批），原注释随字段一并
  // 搬走，页面侧改经 this.overlayState.stickerGhostXxx / this.overlayState.flyStickerGhost()。
  @Local unreadBadge: number = 0;
  private firstUnreadId: number = 0;
  // Set once the initial scroll parks on the unread boundary; suppresses every
  // auto-scroll-to-bottom until the user first touches the list, so a short
  // unread run isn't glued past the divider by async in-place content growth.
  private stayAtUnread: boolean = false;
  private curStartIdx: number = -1; // topmost visible row index (from onScrollIndex)
  private curEndIdx: number = -1;   // bottom visible row index (from onScrollIndex)
  // Cumulative signed sum of user-originated scroll frames. A history page can
  // land while the finger/fling is still moving; anchor restoration subtracts
  // the delta since capture so it fixes only data/layout movement and never
  // cancels the user's gesture. onWillScroll supplies the source, onDidScroll
  // supplies the actual applied offset.
  private userScrollOffsetTotal: number = 0;
  private nextDidScrollIsUserDriven: boolean = false;
  // A pending anchor correction yields while the list is still moving. This
  // keeps an in-flight page response from racing the active drag/fling.
  private timelineScrollActive: boolean = false;
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
  // ⚠️ 临时探针 [JumpLatest] 用：↓ 的点击序号，把同一次点击的日志串起来。
  private jumpLatestSeq: number = 0;
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
  // applyRouteParams 一次性守卫下只写一次，等价于拆分前那个局部量；不加 @Local——
  // 加了会让每次消息快照回调都触发一次页面 build。
  private routeResumeWaiting: boolean = false;
  private pendingJumpId: number = 0;
  // A module-level remembered position is only a candidate until MessageStore
  // resolves the chat's authoritative unread count. Once selected it becomes
  // pendingJumpId and resumeDividerId together.
  private pendingResumeId: number = 0;
  private pendingResumeItemY: number = 0;
  private resumeDividerId: number = 0;
  private resumeDividerItemY: number = 0;
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
  // 跳转目标高亮（回复/置顶/链接跳转落地后闪烁两拍）整簇搬进了 JumpFlashState
  // （B13 批），字段名与初值一字未改（四个 @Local 变成 @Trace，去掉了在类名里
  // 已经说过一遍的 flash 前缀：top/height/alpha/shown；三个普通私有字段
  // flashSeq/flashTargetIdx/flashTargetId 原名照抄），原有注释随字段一并搬进
  // JumpFlashState.ets，此处不再重复。页面侧统一经 this.flash.xxx 读写。
  //
  // 字段初始化器 new：首帧前就已存在、引用全生命周期稳定、类型非空。禁止做成
  // 模块级单例：平板分栏/导航栈多层时同时活着多个 ChatPage，各自的跳转高亮
  // 互不相干。
  private flash: JumpFlashState = new JumpFlashState();
  // Floating date chip: shows the topmost visible message's date while the
  // list scrolls, fades out shortly after scrolling stops (the in-list date
  // pills stay — this is the always-visible companion).
  //
  // 日期文字、显隐、820ms 隐藏定时器全部住在 FloatingDateOverlay 那边的
  // @ObservedV2 对象里。这里只留一个**普通私有字段**持有引用：ChatPage.build
  // 一个字都不读它，日期变化因此不再让整页重绘。
  private floatDateState: FloatingDateState = new FloatingDateState();
  // 留在 ChatPage 的只有"顶行下标"——它是"要不要重新扫 groups 算日期"的判据，
  // 而 groups 是 ChatPage 的数据。同样是非响应式字段。
  private floatDateIndex: number = -1;
  // 上一次 onScrollIndex 报的顶行下标（不是日期条认的那个）。日期条要量布局才
  // 知道哪一行真正露在标题栏下面，而 onDidScroll 每帧都来——下标没变就连量都
  // 不量，见 updateFloatDate。
  private floatDateStartIdx: number = -1;
  private listTouchActive: boolean = false;
  private listUserScrollActive: boolean = false;
  // RESIZE shortens the List while the IME animates in. Preserve the live-tail
  // anchor captured before that resize; otherwise onDidScroll observes the
  // temporary clipped viewport, flips atBottom to false and leaves the last
  // messages behind the newly raised composer.
  private imeTailPinned: boolean = false;
  private imeLayoutSeq: number = 0;
  private lastKeyboardH: number = 0;
  // 媒体保存/下载簇（查看器"保存到相册"单槽等待 + 新消息自动保存队列 + 文档
  // 下载后自动打开）整体搬进 MediaSaveState（B15 批），原六个字段
  // （pendingGallerySaveId/pendingGallerySaveProgress/autoSavePendingIds/
  // autoSaveInFlight/pendingFileOpenId/fileOpenInFlightId）随之搬走，原有的
  // 两段解释性注释一并带走，此处不再重复。字段初始化器 new：per-ChatPage
  // 实例，不做模块级单例。
  private mediaSave: MediaSaveState = new MediaSaveState();
  private utilityActionAtMs: number = 0;
  // A tapped music message starts automatically once its on-demand download
  // completes. Only the latest tap owns this slot, so rapid track changes
  // cannot make an older download steal playback later.
  // Audio playback queue over this chat's music messages. Its logic (ordering,
  // the download-then-play hand-off, previous-vs-rewind) lives in MusicQueue and
  // is unit-tested there; this page only supplies the I/O.
  private musicQueue: MusicQueue = new MusicQueue({
    currentState: (): VoiceState => getVoicePlayback().current(),
    // 起播的两个出口都在这里把曲目信息**送出页面**——底栏的迷你播放条要用，
    // 而回到会话列表时本页已经销毁（见 util/nowPlayingChannel 的说明）。
    toggleMusic: (id: number, path: string, dur: number): void => {
      getVoicePlayback().toggleMusic(id, path, dur);
      this.publishNowPlayingFor(id, path, dur);
    },
    startMusic: (id: number, path: string, dur: number): void => {
      getVoicePlayback().startMusic(id, path, dur);
      this.publishNowPlayingFor(id, path, dur);
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
  // 锚点复位簇（前插/追加/恢复落位三条路径的"把那一行按回原来的 y"）整簇
  // 搬进了 ScrollAnchorController（第二轮 R2-B）。原来的 prependRestoreSeq 代次
  // 守卫是它的内部机件，页面只经 invalidate() 作废，见该文件文件头。
  private anchor: ScrollAnchorController = new ScrollAnchorController();
  // 输入条上方三块建议面板（'@' 成员 / '/' 命令 / "@bot query" 内联结果 /
  // 纯 emoji 贴纸建议）的状态与并发守卫整簇搬进了 ComposerSuggestionState.ets
  // 四个类——MentionSuggestionState/CommandSuggestionState/InlineQueryState/
  // StickerSuggestionState（B14 批），字段名与初值一字未改，原有注释随字段
  // 一并搬进该文件，此处不再重复。页面侧统一经 this.mention/this.command/
  // this.inline/this.sticker 读写；updateSuggestions 作为唯一路由入口留在
  // 页面，本批未改动它内部三条分支（command/mention/inline+sticker）的顺序。
  //
  // 字段初始化器 new：首帧前就已存在、引用全生命周期稳定、类型非空。禁止做成
  // 模块级单例：平板分栏/导航栈多层时同时活着多个 ChatPage，各自会话的输入
  // 建议互不相干。
  private mention: MentionSuggestionState = new MentionSuggestionState();
  private command: CommandSuggestionState = new CommandSuggestionState();
  private inline: InlineQueryState = new InlineQueryState();
  private sticker: StickerSuggestionState = new StickerSuggestionState();
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
  // 麦克风录音状态机（isRecording/recordingStarting/recordSeconds/
  // recordTimer/voiceRec/recordingSeq 六个字段 + start/finish/cancel/
  // secondsLabel 逻辑）整体搬进 VoiceRecordingState（B15 批），原
  // "Voice recording state." 注释随字段一并带走，此处不再重复。字段初始化器
  // new：per-ChatPage 实例，不做模块级单例。
  private recording: VoiceRecordingState = new VoiceRecordingState();
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
  // 选好但还没发出去的媒体。和 composer.replyToId 正交——回复某条 + 附图 +
  // 配文是一次完整操作，所以不进 ComposerSession 那个互斥状态机（B9 批搬迁
  // 前叫 composerMode，见 util/pendingMedia）。
  @Local private pendingMedia: PendingMediaItem[] = [];

  // 附件面板分发（媒体/文件/音频/位置/骰子/联系人/投票/录像笔记）与长按气泡
  // 「替换媒体」整簇（B12）。普通类，不驱动 UI 重渲染——mediaCopySeq/
  // mediaPickerOpen 两个原页面字段变成了它的私有并发闸门，全仓核实过只在本簇
  // 内引用，页面不再需要读它们。
  private attach: AttachActions = new AttachActions();
  @Local headerMenuShow: boolean = false; // header ⋮ dropdown
  private headerMenuId: string = createChatHeaderMenuId();
  private headerMenuController: ChatHeaderMenuController = new ChatHeaderMenuController();
  // 顶栏身份解析与展示态（标题/头像/静音/密聊副标题/表情状态/资料跳转/Mini App
  // 入口）的整套状态机（B8 批）。原来摊在这里的 15 个 @Local（title/avatarPath/
  // headerAvatarAnimPath/initials/subtitle/secretSubtitle/secretOutbound/
  // headerState/headerLoadError/headerProfileOpening/headerMuteUpdating/
  // isMuted/headerEmojiPath/headerEmojiFormat/botMiniAppUrlValue）与 6 个内部
  // 机件字段（headerPeerUserId/headerKind/headerIdentityResolved/
  // headerResolveSeq/headerEmojiFetched/headerNavigationTimer）全部住进了
  // 控制器，字段名做了瘦身重命名（如 headerState → state），前者变成 @Trace，
  // 后者仍是 private 的普通字段。
  //
  // 字段初始化器 new：首帧前就已存在、引用全生命周期稳定、类型非空——
  // ChatHeader 拿 @Require @Param 收它，直接在自己的 build() 里读 @Trace，
  // 页面不再算 titleText/subtitleText 经 @Param 转手。禁止做成模块级单例：
  // 平板分栏/导航栈多层时同时活着多个 ChatPage，各自的顶栏身份解析进度互不相干。
  //
  // headerMenuShow/headerMenuId/headerMenuController 三个头部菜单域字段本轮
  // 不动，仍留在页面（HeaderIdentitySession.reset() 里仍会调用
  // host.closeHeaderMenu() 转发给它们）。
  private header: HeaderIdentitySession = new HeaderIdentitySession();
  // 输入框下面那块高度归谁（none / attach / emoji / replyKeyboard）。
  // 三个既有字段仍在（读取处很多），但**只由 applyBottomSlot 写**。
  @Local bottomSlot: string = SLOT_NONE;
  // 会话内搜索（关键词 / 按发送者筛选 + 结果导航）的整套状态机（B6 批）。原来
  // 摊在这里的 6 个 @Local（searchMode/searchQuery/searchResults/searchTotal/
  // searchIdx/searchSenderId）与 2 个内部机件字段（searchAnchorId/searchSeq）
  // 全部住进了控制器，字段名和初值一字未改，只是 @Local 变成了 @Trace。
  //
  // 字段初始化器 new：首帧前就已存在、引用全生命周期稳定、类型非空。禁止做成
  // 模块级单例：平板分栏/导航栈多层时同时活着多个 ChatPage，每个都有自己的
  // 搜索关键词、自己的结果列表、自己的请求 seq。
  //
  // 页面仍要读的只剩 mode 一处判据，散在 bottomDock/chatTitleBar/
  // chromeGeometryInput/ScrollFab 显隐/handleBackPressed 五个调用点——都是
  // this.x → this.search.x 的逐处替换，依赖粒度与搬之前一一对应。
  private search: SearchSession = new SearchSession();
  // Multi-select mode (entered via the long-press menu's 选择 item).
  // 消息多选状态机（B7 批）。原来的 2 个 @Local（selecting/selectedIds）住进
  // 了控制器，变成 @Trace，字段名与初值一字未改。页面（chatTitleBar/
  // bottomDock/timelineRow）仍直读 this.selection.active/this.selection.ids，
  // 依赖粒度与搬之前一一对应——本簇没有像 B5 的 TopBanners 那样把宿主也改成
  // 直读控制器，只是把状态和判定收进一个能单测的对象。
  //
  // 字段初始化器 new：首帧前就已存在、引用全生命周期稳定、类型非空。禁止做成
  // 模块级单例：平板分栏/导航栈多层时同时活着多个 ChatPage，各自的多选态
  // 互不相干。
  private selection: SelectionSession = new SelectionSession();

  private clearFloatingDate(): void {
    // 定时器与两个显示态一起归 FloatingDateState 管；clear() 不回调 onHidden，
    // 下面这两个标志本来就在同一句里清。
    this.floatDateState.clear();
    this.floatDateIndex = -1;
    this.floatDateStartIdx = -1;
    this.listTouchActive = false;
    this.listUserScrollActive = false;
  }

  private resetScrollSession(): void {
    this.scrollActionSeq++;
    this.jumpLayoutSeq++;
    this.anchor.invalidate();
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
    this.userScrollOffsetTotal = 0;
    this.nextDidScrollIsUserDriven = false;
    this.timelineScrollActive = false;
    // 「↓」的返回关系和"底部看到的是哪条"同样是会话级的。消息 id 在每个会话
    // 里独立编号，把上一个会话的跳转栈带过来，↓ 就会指向本会话里一条恰好同号
    // 的无关消息——或者一条根本不存在的 id，点下去只是空转。
    this.returnState = emptyReturnState();
    this.curBottomId = 0;
    this.jumpLandingUntil = 0;
    this.clearPendingScrollBottom('resetScrollSession');
    this.scrollToBottomBusy = false;
    this.pendingJumpId = 0;
    this.pendingResumeId = 0;
    this.pendingResumeItemY = 0;
    this.resumeDividerId = 0;
    this.resumeDividerItemY = 0;
    // 原 `this.pendingFileOpenId = 0; this.fileOpenInFlightId = 0;` 两行（B15）。
    // 这是本簇六个字段里**只有这一对**会在换会话时单独清空的地方，另外四个在这
    // 条路径上从来不动——所以 MediaSaveState 单开了 resetFileOpenIntent()，
    // 不能用 dispose() 顶替（理由写在那个方法上方）。
    this.mediaSave.resetFileOpenIntent();
    this.musicQueue.reset();
    this.olderArmed = true;
    this.newerGate = armedPageGate();
    this.freshSinceId = 0;
    this.freshClearSeq++;
    this.imeTailPinned = false;
    this.imeLayoutSeq++;
    this.lastKeyboardH = this.keyboardH;
    this.flash.cancelFlash();
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
    // 原文四行 `this.recordingSeq++; if (this.voiceRec !== null ||
    // this.isRecording || this.recordingStarting) { this.cancelRecording();
    // }` 收成这一次 `this.recording.cancel()` 调用——voiceRec/recordingSeq
    // 现在是控制器私有字段，页面读不到，无法逐字保留这个三项判据。改成
    // 无条件调用是经证明的等价简化，不是近似值：cancel() 内部本来就会
    // `recordingSeq++`，原文那一次判据为假时的额外自增本身就是空操作
    // （没有任何在途 Promise 会去比较它——voiceRec 为 null 意味着没有
    // start() 仍在等待落地）；判据为真时原文会自增两次，但两次自增和一次
    // 自增对"seq !== recordingSeq"这个不等式判断没有任何可观察差异；
    // cancel() 在 rec===null、各标志已是初值时的其余步骤
    // （voiceRec=null/recordingStarting=false/stopTimer()/isRecording=false）
    // 也都是各自的空操作。与页面别处已有的无条件转发写法
    // （disposeTimersAndSeqGuards 里的 `this.cancelRecording();`、
    // AttachActions host 的 `cancelRecording: () => this.cancelRecording()`）
    // 是同一种模式。
    this.recording.cancel();
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
    this.mention.clear();
    this.command.clear();
    this.replyKeyboard = null;
    this.applyBottomSlot(closeAllSlots());
    this.replyKeyboardSendingKey = '';
    // 整个清成普通输入，而不是只 clearReply()。clearReply 按设计只处理回复态，
    // 编辑态下是空操作——换会话时编辑态因此能活下来，editingId 还指着上一个
    // 会话的消息，下一次提交就编辑到别的会话去了。
    this.composer.reset();
  }

  private resetMessageActionSession(): void {
    this.selection.reset();
    // 原 showReactionSheet=false; reactionTargetId=0; reactionPendingKey='' 三行
    // 搬进了 this.overlayState.resetSession()（B11 批）。第四行 closeForwardSheet()
    // 也是本簇的，但它在原文里排在 paidMediaPendingIds 之后——不并进
    // resetSession()，就是为了不动这个顺序（理由写在 ChatOverlayState 那边）。
    this.overlayState.resetSession();
    this.paidMediaPendingIds = [];
    this.overlayState.closeForwardSheet();
  }


  private clientJoinNoticeEntry(): MessageEntry {
    if (this.clientJoinNoticeEntryCache !== null) {
      return this.clientJoinNoticeEntryCache;
    }
    const raw: TdObject = clientJoinNoticeRaw(
      this.chatId, this.clientJoinNoticeDate, this.clientJoinNoticeIsChannel);
    this.clientJoinNoticeEntryCache = buildMessageEntry(raw, getUserStore());
    return this.clientJoinNoticeEntryCache;
  }

  private groupsWithClientJoinNotice(list: MessageEntry[]): AlbumGroup[] {
    if (this.clientJoinNoticeVisible && hasRealClientJoinNotice(list)) {
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
    tagClientJoinNoticeGroup(groups, this.chatId, this.clientJoinNoticeDate);
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
    this.resumeScrollThreadId = conversationScopeId(
      this.threadRootId, this.forumTopicId, this.directMessagesTopicId);
    this.resumeScrollMessageId = this.groups[this.curStartIdx].head.id;
    const itemY: number = this.anchorItemY(this.curStartIdx);
    this.resumeScrollItemY = Number.isNaN(itemY) ? 0 : itemY;
    this.resumeScrollAtBottom = this.atBottom;
    // 同一份位置也记到模块级表里：页面销毁后（退出会话再进来）还能落回去，
    // issue #98。在底部的不记——那种情况下次该跟到最新。
    rememberChatPosition(this.chatId, this.resumeScrollThreadId,
      this.resumeScrollMessageId, this.atBottom, this.resumeScrollItemY);
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
  private navigationCoordinator: ChatPageNavigationCoordinator =
    new ChatPageNavigationCoordinator();

  // 返回上一层。**不能用 router.back()**：本页是 NavDestination（导航页，不是 router 页），router 页栈里
  // 只剩 Index 一层，router.back() 弹掉的是 Index——平板模拟器实测（Task 7 修复轮 1）
  // 的现象是「点返回箭头直接退到桌面」。要出的是 Navigation 栈。
  //
  // Task 6 迁移本页时 leaveChat 成功回调原样留了 router.back()，是漏改，
  // 不是有意为之。标题栏返回键现在由 HDS 自己弹出同一条 Navigation 栈。
  private goBack(): void {
    if (!this.navigationCoordinator.pop()) {
      // navStack 由 onReady(ctx.pathStack) 填，而 onReady 必先于本页可见，所以
      // 这一支不该发生。这里**故意不回退到 router.back()**：那正是会退出应用的
      // 那条路，把返回键做成"什么都不做 + 一条日志"远比把应用关掉好。
      logE('ChatPage.goBack: navStack missing, back ignored');
      return;
    }
  }

  aboutToAppear(): void {
    // 顶栏浮卡控制器接上宿主（B5）。全是箭头函数字段：前六个是取值器——控制器
    // 不缓存页面的值，每次要用就现取；后五个是动作回调——共享的滚动/跳转真源
    // （scroller、pendingJumpId）留在页面，控制器只把意图交回来。
    // 必须在 applyRouteParams 之前绑好：那里会调 topCard.resetTopCardState()，
    // 而它要读 threadRootId 决定置顶条的初始加载态。
    this.topCard.bind({
      chatId: (): number => this.chatId,
      threadRootId: (): number => this.threadRootId,
      title: (): string => this.header.title,
      store: (): MessageStore | null => this.store,
      groups: (): AlbumGroup[] => this.groups,
      curStartIdx: (): number => this.curStartIdx,
      prepareUserJump: (): void => { this.prepareUserJump(); },
      scrollToLatest: (): void => { this.scrollToLatest(); },
      // scroller 是页面独有的（不变量 10），所以这条动作回调把
      // scrollToIndex(i, false, ScrollAlign.START) 这个细节挡在控制器之外，
      // 顺带让 ArkUI 的滚动类型不必进那个文件。
      scrollToIndex: (index: number): void => {
        this.scroller.scrollToIndex(index, false, ScrollAlign.START);
      },
      flashAtIndex: (index: number): void => { this.flash.flashAtIndex(index); },
      jumpToPinned: (messageId: number): void => { this.jumpToPinned(messageId); }
    });
    // 顶栏身份解析控制器接上宿主（B8）。前九个是取值器——控制器不缓存页面的
    // 值，每次要用就现取；isGroup/isChannel/isBotChat/isTranslatable/
    // membershipState/unreadBadge 六个字段的所有权裁决留在页面（被 cacheKey/
    // 成员资格状态机/翻译总开关/ScrollFab 未读徽标等身份簇之外的多个域共同
    // 读写），控制器算出新值后经 onChatKindResolved 一次性回传。必须在
    // applyRouteParams 之前绑好：那里会调 header.reset()/header.resolveIdentity()。
    this.header.bind({
      chatId: (): number => this.chatId,
      store: (): MessageStore | null => this.store,
      topicName: (): string => this.topicName,
      forumTopicId: (): number => this.forumTopicId,
      directMessagesTopicId: (): number => this.directMessagesTopicId,
      threadRootId: (): number => this.threadRootId,
      isTranslatable: (): boolean => this.isTranslatable,
      membershipState: (): string => this.membershipState,
      unreadBadge: (): number => this.unreadBadge,
      // **必须先写 isGroup 再调 refreshAdminLabels**：这是早年的 bug（
      // refreshAdminLabels 读 isGroup 时它还没被赋新值，普通群的管理员标签
      // 从来没取到过）——原来钉在 applyResolvedHeaderChat 的 chatTypeBasicGroup
      // 分支里，B8 搬迁后这条顺序改钉在这个回调里。refreshAdminLabels 自己开头
      // 按 !isGroup 早退，refreshIsBot/applySecretChat/chatTypePrivate/
      // chatTypeSecret 触发的调用都是无害的早退，多来几次不发请求。
      onChatKindResolved: (k: ResolvedChatKind): void => {
        this.isGroup = k.isGroup;
        this.isChannel = k.isChannel;
        this.isBotChat = k.isBotChat;
        this.isTranslatable = k.isTranslatable;
        this.membershipState = k.membershipState;
        this.unreadBadge = k.unreadBadge;
        this.refreshAdminLabels();
      },
      // header.refresh()（原 refreshHeader）对未读徽标的写入单独一条通道，不
      // 经 onChatKindResolved——它由消息/会话列表更新驱动，触发频率远高于一次
      // 身份解析，见 HeaderIdentitySession.ets 的说明。
      onUnreadCount: (count: number): void => { this.unreadBadge = count; },
      onLiveEntry: (entry: ChatEntry): void => { this.topCard.syncLiveFromChatEntry(entry); },
      onKnownBackground: (background: TdObject): void => {
        this.bgStore?.applyKnownBackground(background);
      },
      commitTimelineSnapshot: (): void => { this.commitTimelineSnapshot(); },
      onMembershipLosesComposer: (): void => { this.composer.reset(); },
      closeHeaderMenu: (): void => { this.closeHeaderMenu(); },
      clearSecretChatSubscription: (): void => { this.subscriptions.clear('secretChat'); },
      // chatTypeSecret 分支的订阅登记转交页面：订阅表是页面字段。回调只做一件
      // 事——把 seq 和推送内容原样转交回 applySecretChat，过期比对仍在控制器
      // 内部完成（resolveSeq 本身不出户）。
      subscribeSecretChat: (secretChatId: number, seq: number): void => {
        this.subscriptions.set('secretChat', watchSecretChat(secretChatId,
          (info: SecretChatInfo): void => { this.header.applySecretChat(seq, info); }));
      }
    });
    // 会话内搜索控制器接上宿主（B6）。前四个是取值器；jumpToMessage 命中后交回
    // 页面走 onReplyTap（压回返回栈、滚动、两拍高亮闪烁，与点引用块/点置顶条
    // 同一条路径）；cancelFlash 是搬之前 exit()/updateQuery() 就顺手碰的、与
    // 搜索簇本身无关的高亮闪烁子系统。
    this.search.bind({
      chatId: (): number => this.chatId,
      threadRootId: (): number => this.threadRootId,
      forumTopicId: (): number => this.forumTopicId,
      directMessagesTopicId: (): number => this.directMessagesTopicId,
      jumpToMessage: (messageId: number): void => { this.onReplyTap(messageId); },
      cancelFlash: (): void => { this.flash.cancelFlash(); }
    });
    // 多选控制器接上宿主（B7）。chatTgsScrollActive 是取值器；
    // closeReactionSheet/setEmojiPanel 是伸到多选簇之外的页面子系统，仅由
    // enter() 触达。
    this.selection.bind({
      chatTgsScrollActive: (): boolean => this.chatTgsScrollActive,
      closeReactionSheet: (): void => { this.overlayState.closeReactionSheet(); },
      setEmojiPanel: (show: boolean): void => { this.setEmojiPanel(show); }
    });
    // 输入框上方那一条（回复/编辑）控制器接上宿主（B9）。headerTitle 是
    // HeaderIdentitySession（B8）title 的转发——控制器之间不互相持有引用，
    // 只经页面这个宿主中转；draft/pendingMedia 等留页面的字段只经取值器/
    // setter 读写，本类不存影子拷贝。
    this.composer.bind({
      headerTitle: (): string => this.header.title,
      store: (): MessageStore | null => this.store,
      findMsg: (messageId: number): MessageEntry | null => this.findMsg(messageId),
      pendingMedia: (): PendingMediaItem[] => this.pendingMedia,
      draft: (): string => this.draft,
      setDraft: (value: string): void => { this.draft = value; },
      closeReactionSheet: (): void => { this.overlayState.closeReactionSheet(); },
      setEmojiPanel: (show: boolean): void => { this.setEmojiPanel(show); },
      closeReplyKeyboardSlot: (): void => {
        this.applyBottomSlot(closeSlot(this.bottomSlot, SLOT_REPLY_KB));
      }
    });
    // 反应/转发/投票/联系人/录像笔记/定时消息弹层控制器接上宿主（B11）。
    // messages/store/chatId 留页面的会话级状态，经取值器现取；setEmojiPanel/
    // effectDuration 是伸到弹层簇之外的页面子系统（表情面板域、性能开关），
    // 仅由 flyStickerGhost/openForwardPicker 触达。
    this.overlayState.bind({
      store: (): MessageStore | null => this.store,
      chatId: (): number => this.chatId,
      findMsg: (messageId: number): MessageEntry | null => this.findMsg(messageId),
      setEmojiPanel: (show: boolean): void => { this.setEmojiPanel(show); },
      effectDuration: (key: string, ms: number): number => this.chatEffectDuration(key, ms)
    });
    // 会话翻译驱动接上宿主（B10）。isTranslatable 的所有权裁决留页面（B8），
    // 控制器经 isTranslatable()/setIsTranslatable() 现取现写，不存影子拷贝；
    // driveVisibleWork 是翻译/媒体窗口/播放位三件事的汇合点，留页面作协调器，
    // 控制器只经这条回调触发页面那份完整协调。
    this.translation.bind({
      chatId: (): number => this.chatId,
      store: (): MessageStore | null => this.store,
      groups: (): AlbumGroup[] => this.groups,
      isTranslatable: (): boolean => this.isTranslatable,
      setIsTranslatable: (value: boolean): void => { this.isTranslatable = value; },
      driveVisibleWork: (): void => { this.driveVisibleWork(); }
    });
    // "正在输入…" 提示控制器接上宿主（B10）。currentKind 转发 B8
    // HeaderIdentitySession.currentKind()——本类不得直接持有 header 控制器的
    // 引用，也不得用 isGroup 之类的近似值顶替。
    this.typing.bind({
      chatId: (): number => this.chatId,
      threadRootId: (): number => this.threadRootId,
      forumTopicId: (): number => this.forumTopicId,
      directMessagesTopicId: (): number => this.directMessagesTopicId,
      currentKind: (): string => this.header.currentKind()
    });
    // 附件面板分发簇接上宿主（B12）。context 是"控制器不缓存页面值"这条铁律
    // 的唯一例外：这里把 getContext(this) 求值一次、闭包成常量传进去——
    // UIAbilityContext 在同一个 Ability 生命周期内本来就是稳定值，且任何会
    // 触发 picker 的用户操作都严格晚于这里（组件树先要 build 完，用户还要先
    // 手动点开附件抽屉）。uiContext 不具备这条"同生命周期内稳定"的依据，
    // 所以是逐次现取。pendingMedia/atBottom/diceSheetOpen/composerFocused/
    // draft/composerSending 等留页面的字段只经这里的取值器/回调读写，本类不
    // 存影子拷贝；overlayState 的四个 sheet 开关经 setSheet 转发，控制器之间
    // 不互相持有引用（B8 起立的规矩）。
    const attachContext = getContext(this) as common.UIAbilityContext;
    this.attach.bind({
      context: (): common.UIAbilityContext => attachContext,
      uiContext: (): UIContext => this.getUIContext(),
      chatId: (): number => this.chatId,
      store: (): MessageStore | null => this.store,
      findMsg: (messageId: number): MessageEntry | null => this.findMsg(messageId),
      pendingMediaCount: (): number => this.pendingMedia.length,
      appendPendingMedia: (items: MediaSendItem[]): number => {
        const merged: PendingMediaAppend = appendPendingMedia(this.pendingMedia, items);
        this.pendingMedia = merged.items;
        return merged.dropped;
      },
      composerSending: (): boolean => this.composerSending,
      draftText: (): string => this.draft,
      clearDraft: (): void => { this.draft = ''; },
      setAtBottom: (value: boolean): void => { this.atBottom = value; },
      closeAttachPanel: (): void => { this.closeAttachPanel(); },
      stopEditing: (): void => { this.composerController.stopEditing(); },
      setComposerFocused: (value: boolean): void => { this.composerFocused = value; },
      cancelRecording: (): void => { this.recording.cancel(); },
      setSheet: (kind: ChatOverlaySheetKind, show: boolean): void => {
        this.overlayState.setSheet(kind, show);
      },
      setDiceSheetOpen: (open: boolean): void => { this.diceSheetOpen = open; }
    });
    // 跳转目标高亮控制器接上宿主（B13）。scroller/groups 是页面独有/共享滚动
    // 真源，只经取值器只读现取，不缓存；effectDuration 转发
    // this.chatEffectDuration，是伸到本簇之外的页面子系统（省电/特效开关）。
    this.flash.bind({
      scroller: (): Scroller => this.scroller,
      groups: (): AlbumGroup[] => this.groups,
      effectDuration: (key: string, ms: number): number => this.chatEffectDuration(key, ms)
    });
    // 输入条上方四块建议面板的控制器接上宿主（B14）。applyDraft 是
    // MentionSuggestionHost 里唯一的动作回调而非取值器：mentionSender 内部是
    // mentionOfUser(...).then() 异步回调，算出新草稿时早已不在原调用点上，
    // 只能靠这个回调把"赋 this.draft"与原来那句
    // `setTimeout(() => focusControl.requestFocus('chat_composer'), 0)`
    // 一并交回页面执行。
    //
    // 【这里确实改了语句顺序，如实记下来】原 mentionSender 里这两句**不**紧挨：
    //   this.draft = appendMention(...);      ← 第 1 句
    //   this.rememberNameMention(item, ...);  ← 第 2 句
    //   this.mentionItems = [];               ← 第 3 句
    //   setTimeout(... requestFocus ...);     ← 第 4 句
    // 现在 applyDraft 把第 4 句提到了第 2、3 句之前。0ms 是宏任务，要等当前
    // 同步段跑完才执行，那时第 2、3 句早已完成——可观察行为不变，但"顺序没动"
    // 这句话是不对的，不能这么写。
    this.mention.bind({
      chatId: (): number => this.chatId,
      draft: (): string => this.draft,
      applyDraft: (next: string): void => {
        this.draft = next;
        setTimeout((): void => { focusControl.requestFocus('chat_composer'); }, 0);
      },
      client: (): TdClient => getTdClient()
    });
    this.command.bind({
      chatId: (): number => this.chatId,
      store: (): MessageStore | null => this.store,
      draft: (): string => this.draft,
      client: (): TdClient => getTdClient()
    });
    this.inline.bind({
      chatId: (): number => this.chatId,
      client: (): TdClient => getTdClient()
    });
    this.sticker.bind({
      client: (): TdClient => getTdClient()
    });
    // 麦克风录音状态机接上宿主（B15）。context 是"控制器不缓存页面值"这条
    // 铁律的既有例外，用法与 attach.bind 那条一致：这里把
    // getContext(this) 求值一次、闭包成常量传进去。beforeStart 打包
    // start()（原 startRecording）开头五条真连续的跨簇语句——
    // setEmojiPanel(false)/applyBottomSlot(closeSlot(...))/mention.clear()/
    // command.closePanel()/composerController.stopEditing()（原
    // 6218-6222 行，侦察报告 (B) 核实过真的连续）；紧接着的
    // `this.composerFocused = false;`（原 6223 行，页面自留字段，方案 6.9
    // 节裁决不进任何控制器）单独经 setComposerFocused 转发，不并入
    // beforeStart；afterSent 对应 finish()（原 finishRecording）发送成功后
    // 的 `this.atBottom = true;`（页面自留字段，跨簇写）。
    const recordingContext = getContext(this) as common.UIAbilityContext;
    this.recording.bind({
      store: (): MessageStore | null => this.store,
      context: (): common.UIAbilityContext => recordingContext,
      beforeStart: (): void => {
        this.setEmojiPanel(false);
        this.applyBottomSlot(closeSlot(this.bottomSlot, SLOT_REPLY_KB));
        this.mention.clear();
        this.command.closePanel();
        this.composerController.stopEditing();
      },
      setComposerFocused: (value: boolean): void => { this.composerFocused = value; },
      afterSent: (): void => { this.atBottom = true; },
      // 与搬之前 start() 里那句 `new VoiceRecorder()` 逐字等价；开成宿主取值器
      // 只是为了让单测能注入一个可手动兑现的假录音器，把 recordingSeq 那道
      // 守卫钉住（理由写在 VoiceRecordingState 的接口上方）。
      newRecorder: (): VoiceRecorder => new VoiceRecorder()
    });
    // 媒体保存/下载簇接上宿主（B15）。context 同上一条的一次性求值例外。
    // viewerEntry/findMsg/latestMessages 对应原文三种不同的"查消息"方式——
    // `this.entryById(this.viewerMsgId)`/`this.messages.find(...)`/
    // `this.messages` 本身，返回类型（null 还是 undefined）逐字保留，不
    // 合并成一个万能取值器（理由见 MediaSaveState.ets 文件头）。
    const mediaSaveContext = getContext(this) as common.UIAbilityContext;
    this.mediaSave.bind({
      context: (): common.UIAbilityContext => mediaSaveContext,
      store: (): MessageStore | null => this.store,
      chatId: (): number => this.chatId,
      viewerEntry: (): MessageEntry | null => this.entryById(this.viewerMsgId),
      findMsg: (messageId: number): MessageEntry | undefined =>
        this.messages.find((x: MessageEntry): boolean => x.id === messageId),
      latestMessages: (): MessageEntry[] => this.messages
    });
    // 成员资格状态机接上宿主（第二轮 R2-A 批）。isChannel 是双重用途取值器
    // （refresh() 的 supergroup 分支拿它当 is_channel 缺省回退值，
    // applyStatus() 拼 membershipStateOf 入参再读一次），两处都现取不缓存。
    // membershipState 按 B8 裁决留在页面，控制器只经 setMembershipState 写它。
    // client() 恒为 () => getTdClient()，是本批的注入缝（见
    // MembershipSession.ets 文件头【client() 注入缝】节）。本批一共两处刻意
    // 偏离逐字搬迁：这条缝，以及三条 logE 的前缀改名（见那边文件头）。
    this.membership.bind({
      chatId: (): number => this.chatId,
      isChannel: (): boolean => this.isChannel,
      setMembershipState: (next: string): void => { this.membershipState = next; },
      setIsGroup: (value: boolean): void => { this.isGroup = value; },
      setIsChannel: (value: boolean): void => { this.isChannel = value; },
      commitTimelineSnapshot: (): void => { this.commitTimelineSnapshot(); },
      setJoiningChat: (value: boolean): void => { this.joiningChat = value; },
      closeComposerSurfaces: (): void => {
        this.setEmojiPanel(false);
        this.mention.clear();
        this.command.closePanel();
        this.composer.reset();
        if (this.recording.isRecording) {
          this.recording.cancel();
        }
      },
      client: (): TdClient => getTdClient()
    });
    // 锚点复位簇（R2-B）。七个取值器全部只读，没有动作回调——本控制器对页面
    // 状态零写入，只借 scroller 发滚动指令。位置放在最后一批 bind 之后即可：
    // 它没有 reset/resolve 类方法，不参与 applyRouteParams 的时序。
    this.anchor.bind({
      scroller: (): Scroller => this.scroller,
      userScrollOffsetTotal: (): number => this.userScrollOffsetTotal,
      timelineScrollActive: (): boolean => this.timelineScrollActive,
      pendingJumpId: (): number => this.pendingJumpId,
      pendingScrollBottom: (): boolean => this.pendingScrollBottom,
      headerChromeHeight: (): number => this.headerChromeHeight(),
      appendGateProbe: (groups: AlbumGroup[]): string => this.appendAnchorGateProbe(groups)
    });
    // The navigation/build frame owns the main thread; chat stickers can start
    // only after the initial row gate has settled.
    this.chatTgsStageSettling = true;
    this.syncChatTgsGate();
    this.playSlot.bind({
      viewerMsgId: (): number => this.viewerMsgId,
      pageVisible: (): boolean => this.pageVisible,
      competeEnabled: (): boolean => this.playSlotsEnabled(),
      applySlot: (key: string, startMs: number): void => {
        // 起播位置必须在 playSlotKey 之前落下：气泡是靠 playSlotKey 的变化才
        // 挂载 VideoBubbleSurface 的，晚一步这条播放器就已经从 0 开始了。
        // 这两句是这条顺序契约的**唯一**落点，PlaySlotHost.applySlot 之所以
        // 是一个动作而不是两个 setter，就是为了把它封在这里。
        this.playSlotStartMs = startMs;
        this.playSlotKey = key;
      }
    });
    this.subscriptions.set('playSlot', this.playSlot.subscribe());
    this.nowSec = Math.floor(Date.now() / 1000);
    // 日期条隐藏的那一刻 listUserScrollActive 必须跟着翻假——原来它和显隐写在
    // 同一个定时器体里，定时器下沉之后靠这个回调保住同一时刻。
    this.floatDateState.setOnHidden((): void => { this.onFloatDateHidden(); });
    // 下面原本还有一大段（读 params → 定 chatId → 建 MessageStore 与十几个
    // 订阅）。实测 onReady 晚于 aboutToAppear（平板 API 26，commit 8046f73 上机：
    // aboutToAppear 读 this.navParams 时还是 undefined，chatId 落成 0，标题栏报
    // 「会话参数无效」、内容区报「消息加载失败」）——所以那段整体搬进了
    // applyRouteParams()，由 onReady 在存完 navParams 之后调用。
    //
    // 留在这里的两件事与路由参数无关（播放位订阅、秒表初值），时机保持原样：
    // 它们必须在任何一次行数组发布之前就绪。
    // B5 更正：现在是三件——最前面那次 topCard.bind() 同样与路由参数无关，且
    // 必须早于 applyRouteParams。
    // B6/B7 更正：现在是五件——search.bind()/selection.bind() 与 topCard.bind()
    // 同理，都必须早于 applyRouteParams（seedFromRoute/scheduleEntrySearch 会
    // 用到 search 的 host）。
    // B8 更正：现在是六件——header.bind() 同理必须早于 applyRouteParams，
    // resolveRouteAndResetSession() 里紧跟着就会调 header.reset()/
    // header.resolveIdentity()。
  }

  // 路由参数就绪后的初始化。这就是迁移前 aboutToAppear 的后半段，顺序一字未改，
  // 只是改由 onReady 触发——onReady 才是 NavDestination 拿得到 pathInfo.param 的
  // 第一个时机。
  //
  // 只跑一次：这段里建了 MessageStore、十几个 TDLib 订阅和两个 setInterval，句柄都
  // 存在 this.unsubXxx / this.xxxTimer 上。第二次进来会把旧句柄直接覆盖掉，旧订阅和
  // 旧定时器就再也退订不了了——aboutToDisappear 只认得最后一份句柄。NavDestination
  // 在页面被复用时（MOVE_TO_TOP_SINGLETON、onNewParam）可能不止触发一次 onReady，
  // 所以这个守卫是必须的。当前的 navigateToChat 走的是 clearAndPush，每次都是新实例，
  // 守卫在正常路径上不会拦到东西——它挡的是复用路径。
  private applyRouteParams(): void {
    if (!this.navigationCoordinator.beginRouteApply()) {
      return;
    }
    const ctx: RouteApplyContext = this.resolveRouteAndResetSession();
    this.registerChatLevelSubscriptions();
    const store: MessageStore = this.createMessageStore();
    this.subscriptions.set('messages', store.subscribe((list: MessageEntry[]) => {
      this.onMessagesSnapshot(store, list);
    }));
    this.registerHeaderDerivedSubscriptions(store);
    this.openStoreForRoute(store, ctx);
    this.search.scheduleEntrySearch();
  }

  // 阶段 A（前半）：路由解析、会话重置、头部/草稿/进入即搜索的初始状态。
  // 语句顺序与拆分前逐行一致；jumpTo 经 RouteApplyContext 交给 openStoreForRoute。
  private resolveRouteAndResetSession(): RouteApplyContext {
    const params = this.navParams;
    const route = parseChatRouteParams(params);
    this.chatId = route.chatId;
    this.threadRootId = route.threadRootId;
    // 话题模式（从 ForumTopicsPage 进入）：标题显示话题名而非"评论"。
    this.topicName = route.topicName;
    this.forumTopicId = route.forumTopicId;
    this.directMessagesTopicId = route.directMessagesTopicId;
    // 会话翻译驱动的会话重置（B10）：排除/加入名单都是本地的，chatId 一确定
    // 就能读，不用等 getChat 回来。
    this.translation.load(this.chatId);
    if (route.showJoinedNotice && this.clientJoinNoticeRouteChatId !== this.chatId) {
      this.clientJoinNoticeRouteChatId = this.chatId;
      this.clientJoinNoticeVisible = true;
      this.clientJoinNoticeIsChannel = route.joinedNoticeIsChannel;
      this.clientJoinNoticeDate = Math.floor(Date.now() / 1000);
      this.clientJoinNoticeEntryCache = null;
    }
    getVoicePlayback().setMusicCompletionListener((messageId: number): void => {
      this.musicQueue.onCompleted(this.messages, messageId);
    });
    this.resetOrPreserveScrollSession();
    const cachedChat: ChatEntry | undefined = getChatStore().entryOf(this.chatId);
    if (cachedChat !== undefined &&
      (cachedChat.kind === 'basicGroup' || cachedChat.kind === 'supergroup' || cachedChat.kind === 'channel')) {
      // Avoid briefly exposing a working input field before the async member
      // status of a newly opened public chat arrives.
      this.membershipState = 'checking';
    }
    const jumpTo = route.jumpTo;
    this.header.reset(cachedChat);
    this.topCard.resetTopCardState();
    this.header.resolveIdentity();
    // Entered from global search: open directly on this chat's results for the
    // same query (the search header, the hit list and ∧/∨ navigation). With a
    // message hit, that message is the jump target and becomes the current hit
    // — seedFromRoute's anchorId keeps the search from jumping somewhere else.
    // Deep links like t.me/<name>?text=… open the chat with a prefilled draft.
    if (route.draftText !== '') {
      this.draft = route.draftText;
    } else {
      this.restoreServerDraft();
    }
    this.search.seedFromRoute(route.searchQuery, route.startSearch, jumpTo !== undefined ? jumpTo : 0);
    const ctx: RouteApplyContext = { jumpTo: jumpTo };
    return ctx;
  }

  // 会话重置决策。结果留在 routeResumeWaiting 字段上——拆分前它是 applyRouteParams
  // 的局部量 scrollResumeWaiting，既被消息回调读写，也被 store.open 的分支读。
  private resetOrPreserveScrollSession(): void {
    this.routeResumeWaiting = this.resumeScrollPending &&
      this.resumeScrollChatId === this.chatId &&
      this.resumeScrollThreadId === conversationScopeId(
        this.threadRootId, this.forumTopicId, this.directMessagesTopicId) &&
      this.groups.length > 0;
    if (!this.routeResumeWaiting) {
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
      this.clearPendingScrollBottom('pageShowResume');
      this.scrollToBottomBusy = false;
      this.didInitialScroll = true;
      this.clearFloatingDate();
    }
  }

  // 阶段 A（后半）：聊天级订阅与两个 setInterval。四个子阶段的相对顺序即原文顺序。
  private registerChatLevelSubscriptions(): void {
    this.subscribeChatLevelUpdates();
    this.startChatBackgroundStore();
    this.subscribeMembershipUpdates();
    this.subscribeLiveCallUpdatesAndTimers();
  }

  private subscribeChatLevelUpdates(): void {
    this.header.refresh();
    this.subscriptions.set('chatAction', getTdClient().onUpdate('updateChatAction',
      (u: TdObject): void => this.typing.onChatAction(u)));
    // 会话已经开着时，navigateToChat 只出栈不传参，跳转目标走旁路送进来
    // （issue #80、#102，见 util/chatJumpChannel 的说明）。
    this.subscriptions.set('jump', subscribeChatJump(this.chatId,
      (messageId: number): void => { this.jumpToMessageId(messageId); }));
    // ForwardSheet subscribes to the chat list itself while it is open, so this
    // no longer has to push updates into it.
    this.subscriptions.set('chat', getChatStore().subscribe(() => {
      this.header.refresh();
    }, 'main'));
    // Chat backgrounds have their own TDLib update and can change without a
    // title/message update. Listen directly so setting or clearing one is
    // visible while the conversation is open.
    this.subscriptions.set('liveLocation', liveLocation.subscribe((st: LiveLocationState): void => {
      this.liveLocationActive = st.active;
      // 只有共享发生在当前会话时才在气泡上显示停止按钮。
      this.liveLocationMessageId = st.active && st.chatId === this.chatId ? st.messageId : 0;
    }));
    // 在其它设备改了这个开关时同步过来，否则菜单文案会和实际状态不符。
    this.subscriptions.set('translatable', getTdClient().onUpdate('updateChatIsTranslatable',
      (u: TdObject): void => {
        if ((u['chat_id'] as number | undefined) === this.chatId) {
          this.isTranslatable = (u['is_translatable'] as boolean | undefined) ?? false;
        }
      }));
  }

  private startChatBackgroundStore(): void {
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
    this.subscriptions.set('background', this.bgStore.subscribe((state: ChatBackgroundState): void => {
      this.chatBg = state;
      this.chatBackgroundRevision++;
    }));
    this.bgStore.open(this.chatId);
  }

  private subscribeMembershipUpdates(): void {
    this.subscriptions.set('membershipSupergroup', getTdClient().onUpdate('updateSupergroup', (u: TdObject) => {
      const supergroup = u['supergroup'] as TdObject | undefined;
      if (supergroup !== undefined &&
        ((supergroup['id'] as number | undefined) ?? 0) === this.membership.supergroupId()) {
        this.membership.applyStatus(supergroup['status'] as TdObject | undefined);
      }
    }));
    this.subscriptions.set('membershipBasicGroup', getTdClient().onUpdate('updateBasicGroup', (u: TdObject) => {
      const basicGroup = u['basic_group'] as TdObject | undefined;
      if (basicGroup !== undefined &&
        ((basicGroup['id'] as number | undefined) ?? 0) === this.membership.basicGroupId()) {
        this.membership.applyStatus(basicGroup['status'] as TdObject | undefined);
      }
    }));
    this.membership.refresh();
    this.topCard.refreshVideoChat(true);
  }

  private subscribeLiveCallUpdatesAndTimers(): void {
    this.subscriptions.set('videoChat', getTdClient().onUpdate('updateChatVideoChat', (u: TdObject) => {
      if ((u['chat_id'] as number | undefined) === this.chatId) {
        const vc = u['video_chat'] as TdObject | undefined;
        this.topCard.applyVideoChatUpdate(
          vc !== undefined ? ((vc['group_call_id'] as number | undefined) ?? 0) : 0);
      }
    }));
    this.subscriptions.set('groupCall', getTdClient().onUpdate('updateGroupCall', (u: TdObject) => {
      const groupCall = u['group_call'] as TdObject | undefined;
      if (groupCall !== undefined &&
        ((groupCall['id'] as number | undefined) ?? 0) === this.topCard.liveGroupCallId) {
        this.topCard.applyGroupCallUpdate(groupCall);
      }
    }));
    // 两个 setInterval（780ms 脉冲 / 2000ms 兜底轮询）随整簇搬进了控制器，
    // 注册点仍是这里、仍在两个订阅之后，时机一字未改。两个订阅本身留在页面：
    // 它们要 set 进 this.subscriptions，由 disposeSubscriptionsInOrder 按既定
    // 顺序摘除。
    this.topCard.open();
  }

  // this.store 必须在 store.subscribe() 之前赋值：subscribe 注册时会同步喂一次
  // 监听器，那一趟回调体里读的就是 this.store。
  private createMessageStore(): MessageStore {
    const store = new MessageStore(
      getTdClient(), getUserStore(), this.chatId, this.threadRootId, 30,
      this.forumTopicId, this.directMessagesTopicId);
    // 预取在手时**不下围栏**：那道围栏防的是"页面滑到一半才闪出内容"，
    // 而预取意味着首帧就已经有行了——页面是带着内容滑进来的，没有可闪的东西。
    // 见 util/chatPrefetch。
    store.deferInitialPublication(
      (isSplitLayout(this.screenW, this.screenH) || hasPrefetchedPage(this.chatId))
        ? 0 : INITIAL_MESSAGE_TRANSITION_SETTLE_MS);
    this.store = store;
    if (!this.routeResumeWaiting || this.groups.length === 0) {
      this.messageLoadState = 'loading';
    }
    return store;
  }

  // 阶段 B：messages 订阅的回调体。store 逐层按参数传递（而不是读 this.store），
  // scheduleNewerTailRefresh 里的 this.store === store 身份判定要靠它。
  private onMessagesSnapshot(store: MessageStore, list: MessageEntry[]): void {
    const historyState: string = store.getInitialHistoryState();
    this.olderLoadState = store.getOlderLoadState();
    this.newerLoadState = store.getNewerLoadState();
    if (!(this.routeResumeWaiting && this.groups.length > 0 && historyState === 'loading')) {
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
    // 「碎片」的判据与它的成因见 util/chatResume.isResumeFragment。
    const fragment: boolean = isResumeFragment(this.groups.length, list.length);
    if (this.routeResumeWaiting && (list.length === 0 || fragment)) {
      return;
    }
    const notifyKind: string = store.getCurrentNotifyKind();
    const maxId: number = list.length > 0 ? list[list.length - 1].id : 0;
    const groups: AlbumGroup[] = this.groupsWithClientJoinNotice(list);
    const resumeLandingPrepared: boolean = this.resolveResumeLandingChoice(store, groups);
    const firstMessageStage: boolean = !this.routeResumeWaiting && this.groups.length === 0 &&
      (resumeLandingPrepared || !this.didInitialScroll);
    // Transfer completion/failure and translation state keep the stable list
    // key. Publish them directly to the mounted row before the data-source
    // diff, so a key-equal snapshot still updates the one affected bubble.
    publishMessageRowPresentations(this.chatId, groups);
    const prependAnchor: PrependAnchorSample =
      this.capturePrependAnchorSample(list, groups, notifyKind);
    const appendAnchor: AppendAnchorSample =
      this.captureAppendAnchorSample(store, groups, prependAnchor);
    this.publishSnapshotAndChrome(store, list, groups, firstMessageStage);
    this.restoreCapturedAnchors(prependAnchor, appendAnchor);
    const positionHandled: boolean = this.applyResumeLanding(list, groups, maxId);
    this.consumeLiveIncomingMediaAndCommands();
    const fillPending: boolean = this.store !== null && this.store.isInitialFillPending();
    this.applyInitialOrFollowLanding(
      list, groups, maxId, notifyKind, positionHandled, fillPending);
    this.consumeJumpToLatestIntent(list, groups, maxId);
    this.scheduleNewerTailRefresh(store, notifyKind);
    // B15 批注：原 `this.landPendingGallerySave(list); this.landPendingFileOpen
    // (list);` 两行、连同原 consumeLiveIncomingMediaAndCommands 里与本簇相关
    // 的 autoScope 计算 + 入队那一段（原注释随之带下来，逐字未改），一并收进
    // 这一次 `this.mediaSave.onSnapshot(...)` 调用——三段各自的内部顺序、
    // 判据、分支在 MediaSaveState.onSnapshot 里逐字未改，只是把入队这一段
    // 挪到了 applyInitialOrFollowLanding/consumeJumpToLatestIntent/
    // scheduleNewerTailRefresh 三次调用之后（原来在之前）；这三次调用都不读
    // 写这六个字段，挪动顺序不可观察（见 MediaSaveState.ets 文件头专项
    // 说明）。
    //
    // isChannel/isGroup were resolved before the timeline publication above,
    // so the host receives row data and chat kind in the same snapshot.
    const autoScope: string = this.isChannel ? 'channel' : (this.isGroup ? 'group' : 'private');
    this.mediaSave.onSnapshot(list, store, autoScope);
    this.landPendingJump(groups);
    // Empty/error chats never start message admission, while populated chats
    // reach this call again after the staged release completes. The method's
    // store/stage guards make both paths converge without a timer race.
    this.scheduleComposerEditorMount();
    if (this.didInitialScroll && list.length > 0) {
      store.prefetchOlder();
    }
  }

  private resolveResumeLandingChoice(store: MessageStore, groups: AlbumGroup[]): boolean {
    // A remembered target is conditional: if getChat says new unread
    // messages exist, MessageStore opened around the unread boundary instead.
    // Resolve that choice BEFORE firstMessageStage is computed. Otherwise the
    // same first snapshot is first staged/positioned as a fully-read bottom
    // landing and then pulled to another anchor, which is the visible
    // "bottom first, suddenly jump upward" reported on entry.
    let resumeLandingPrepared: boolean = false;
    if (!this.routeResumeWaiting && !this.didInitialScroll && this.pendingResumeId > 0) {
      const rememberedId: number = this.pendingResumeId;
      const rememberedIndex: number = groupIndexOf(groups, rememberedId);
      if (store.isResumeLandingSelected() && rememberedIndex >= 0) {
        this.didInitialScroll = true;
        this.atBottom = false;
        this.pendingJumpId = rememberedId;
        this.resumeDividerId = groups[rememberedIndex].head.id;
        this.resumeDividerItemY = this.pendingResumeItemY;
        resumeLandingPrepared = true;
      }
      // Whether selected or superseded by unread, the decision is final once
      // the first ready history snapshot arrives.
      this.pendingResumeId = 0;
      this.pendingResumeItemY = 0;
    }
    return resumeLandingPrepared;
  }

  private capturePrependAnchorSample(list: MessageEntry[], groups: AlbumGroup[],
    notifyKind: string): PrependAnchorSample {
    // ── 向上翻页的锚点复位 ──────────────────────────────────────────
    //
    // API 20 起官方已经明确：maintainVisibleContentPosition(true) 支持 Repeat
    // 的懒加载场景，但真机媒体相册推翻了“普通区外前插一定能保位”这个前提：
    // older 页发布时旧首行 key 可以不变，甚至会跨页并入同一相册、旧身份直接
    // 消失；Repeat 重排超高媒体行后，整个可见窗口仍会换位置。
    //
    // 因此判据改为 MessageStore 的事务语义：notifyKind 是 older，且原始消息窗口
    // 确实增长。纯追加、编辑和空页都不复位。即使用户仍在滑也要记锚点；后面的
    // userScrollOffset 会保留采样后的真实手势位移，只抵消数据/布局造成的跳动。
    let prependAnchorId: number = 0;
    let prependAnchorY: number = 0;
    let prependAnchorUserOffset: number = 0;
    let primePrependAnchor: boolean = false;
    const olderPageGrowth: boolean = notifyKind === 'older' && list.length > this.messages.length;
    if (shouldCapturePrependAnchor({
      didInitialScroll: this.didInitialScroll,
      anchorIndexFresh: this.anchorIndexFresh(),
      olderPageGrowth: olderPageGrowth
    })) {
      const visibleIndex: number = this.curStartIdx;
      if (visibleIndex >= 0 && visibleIndex < this.groups.length) {
        const y: number = this.anchorItemY(visibleIndex);
        // 量不到就整个不记锚点：宁可不补，也不要拿一个假 0 去算 dy
        // （见 anchorItemY 的说明）。
        if (!Number.isNaN(y)) {
          prependAnchorId = this.groups[visibleIndex].head.id;
          prependAnchorY = y;
          prependAnchorUserOffset = this.userScrollOffsetTotal;
          primePrependAnchor = shouldPrimePrependAnchor(
            visibleIndex, y, this.headerChromeHeight(), this.listTouchActive);
          this.anchor.captureAnchorOffset();
          logW(`[PrependAnchor] hold id=${prependAnchorId} idx=${visibleIndex}` +
            ` y=${prependAnchorY} rows=${this.groups.length}->${groups.length}` +
            ` messages=${this.messages.length}->${list.length} prime=${primePrependAnchor}` +
            ` touch=${this.listTouchActive} active=${this.timelineScrollActive}`);
        } else {
          logW(`[PrependAnchor] skip reason=measure idx=${visibleIndex}` +
            ` rows=${this.groups.length}->${groups.length}` +
            ` messages=${this.messages.length}->${list.length}`);
        }
      } else {
        logW(`[PrependAnchor] skip reason=index idx=${visibleIndex}` +
          ` rows=${this.groups.length}->${groups.length}` +
          ` messages=${this.messages.length}->${list.length}`);
      }
    } else if (olderPageGrowth && this.didInitialScroll) {
      logW(`[PrependAnchor] skip reason=stale-index startIdx=${this.curStartIdx}` +
        ` idxLen=${this.indexGroupsLen} rows=${this.groups.length}->${groups.length}` +
        ` messages=${this.messages.length}->${list.length}`);
    }
    const sample: PrependAnchorSample = {
      id: prependAnchorId,
      y: prependAnchorY,
      userOffset: prependAnchorUserOffset,
      prime: primePrependAnchor
    };
    return sample;
  }

  private captureAppendAnchorSample(store: MessageStore, groups: AlbumGroup[],
    prependAnchor: PrependAnchorSample): AppendAnchorSample {
    // ── 向下翻页的锚点复位 ──────────────────────────────────────────
    //
    // 上面那一段的镜像。底部锚定时末尾追加会把可见内容整体往上顶；顶部锚定
    // 理论上应当不动，但 Repeat + 超高相册行在真机上仍会重排整个窗口。两侧都
    // 记录同一可见消息；普通追加若已由框架守住，发布后 dy 自然为 0。判据与
    // 真机证据见 util/appendAnchor。
    //
    // 额外那道闸判的是「**这次追加是不是用户主动向下翻页的结果**」，判据与
    // 完整推导见 util/appendAnchor。
    //
    // 它原来是 `!this.atBottom`——那问的是另一件事（"用户此刻在不在会话实时
    // 尾部"），而 atBottomVerdict 里带着 !hasMoreNewer，于是向下翻页的整个
    // 过程中恒为真、闸恒开，每一次追加都把视口按回锚点。那正是真机上"进会话
    // 落在中间之后持续闪、滑不动、↓ 按不下去"的动力来源。
    let appendAnchorId: number = 0;
    let appendAnchorY: number = 0;
    let appendAnchorUserOffset: number = 0;
    const appendsRows: boolean = appendBreaksAnchor(this.groups, groups);
    // 标记**无条件**取走：一次请求最多影响一次发布，绝不跨页残留。用不用得
    // 上再看这次发布有没有真的追加行。原来只在 appendsRows 为真时才取，于是
    // "置了位却一行没追加"的请求（短页补链、缓存预热重问、整页丢弃——在
    // loadNewer 的过滤下是常态）会把标记永久闩住，此后每一次追加都误判成用户
    // 翻出来的。真机上 hold 40 / skip 0 就是这么来的。见 util/appendAnchor。
    const appendMarkPending: boolean = store.consumeUserDrivenAppend();
    const userDrivenAppend: boolean =
      useUserDrivenAppendMark(appendMarkPending, appendsRows);
    const holdAppendAnchor: boolean = shouldHoldAppendAnchor({
      bypassed: APPEND_ANCHOR_RESTORE_BYPASSED,
      didInitialScroll: this.didInitialScroll,
      prependAnchorHeld: prependAnchor.id !== 0,
      appendBreaksAnchor: appendsRows,
      atLiveTail: this.atBottom,
      scrollIntentPending: this.pendingJumpId !== 0 || this.pendingScrollBottom
    });
    if (holdAppendAnchor && this.anchorIndexFresh()) {
      const visibleIndex: number = this.curStartIdx;
      const y: number = visibleIndex >= 0 && visibleIndex < this.groups.length
        ? this.anchorItemY(visibleIndex) : Number.NaN;
      if (!Number.isNaN(y)) {
        appendAnchorId = this.groups[visibleIndex].head.id;
        appendAnchorY = y;
        appendAnchorUserOffset = this.userScrollOffsetTotal;
        this.anchor.captureAnchorOffset();
        logW(`[AppendAnchor] hold id=${appendAnchorId} idx=${visibleIndex} y=${appendAnchorY}` +
          ` mark=${appendMarkPending} userDrivenAppend=${userDrivenAppend}` +
          ` rows=${this.groups.length}->${groups.length} ${this.appendAnchorGateProbe(groups)}`);
      }
    } else if (appendsRows && prependAnchor.id === 0 && this.didInitialScroll) {
      // 闸关上时也留一条：判读时要能看见「这一次追加本来会不会复位」。与 hold
      // 那条同格式，随探针一起删。
      logW(`[AppendAnchor] skip bypass=${APPEND_ANCHOR_RESTORE_BYPASSED}` +
        ` mark=${appendMarkPending} userDrivenAppend=${userDrivenAppend}` +
        ` rows=${this.groups.length}->${groups.length} ${this.appendAnchorGateProbe(groups)}`);
    }
    const sample: AppendAnchorSample = {
      id: appendAnchorId,
      y: appendAnchorY,
      userOffset: appendAnchorUserOffset
    };
    return sample;
  }

  private publishSnapshotAndChrome(store: MessageStore, list: MessageEntry[],
    groups: AlbumGroup[], firstMessageStage: boolean): void {
    this.isChannel = store.getIsChannel();
    this.isGroup = store.getIsGroup();
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
  }

  private restoreCapturedAnchors(prependAnchor: PrependAnchorSample,
    appendAnchor: AppendAnchorSample): void {
    // 复位跑在发布之后：this.groups 此刻已经是新快照，按消息 id 找得到锚点行
    // 的新下标。restorePrependAnchor 内部是一个 setTimeout(0) + 代次守卫，
    // 跳转/贴底这些更强的定位意图会把它作废。
    if (prependAnchor.id > 0) {
      this.anchor.restorePrependAnchor(
        this.groups, prependAnchor.id, prependAnchor.y, prependAnchor.userOffset,
        prependAnchor.prime);
    } else if (appendAnchor.id > 0) {
      // 复位走的是和向上那侧同一个 restoreScrollAnchor：setTimeout(0) + 代次
      // 守卫，跳转/贴底这些更强的定位意图会把它作废。
      this.anchor.restoreAppendAnchor(
        this.groups, appendAnchor.id, appendAnchor.y, appendAnchor.userOffset);
    }
  }

  private applyResumeLanding(list: MessageEntry[], groups: AlbumGroup[],
    maxId: number): boolean {
    let positionHandled: boolean = false;
    if (this.routeResumeWaiting && list.length > 0) {
      this.routeResumeWaiting = false;
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
          this.anchor.restoreScrollAnchor(resumeIndex, this.resumeScrollItemY);
        } else {
          this.glueBottom('L1166');
        }
      }
    }
    return positionHandled;
  }

  // B15 批注：原方法体前半段（liveMediaIds 拉取 + autoScope 计算 +
  // autoSavePendingIds 入队循环）整体搬进了 MediaSaveState.onSnapshot——那
  // 部分是媒体保存簇自己的入队逻辑，与本方法剩下的这半段（command 面板加载
  // 探测）不相干，是 B14 的控制器。方法名保留未改：调用点未变，剩下的这半段
  // 仍是原文件里"consumeLiveIncomingMediaAndCommands"这一步该做的事的
  // 后半截。
  private consumeLiveIncomingMediaAndCommands(): void {
    // Private peer resolved: probe once for commands. The centralized loader
    // also serves '/' autocomplete, so fast typing cannot start a competing
    // request that overwrites a newer result.
    if (this.command.commandLoadState === 'idle' && this.store !== null &&
      this.store.getPeerUserId() > 0) {
      this.command.ensureCommandsLoaded();
    }
  }

  // 四条落点分支的互斥链：resume 已定位 / 首屏落点 / 新消息跟随 / 原地增高贴底。
  // if / else-if 结构原样保留，只把两条长分支的方法体搬进各自的方法。
  private applyInitialOrFollowLanding(list: MessageEntry[], groups: AlbumGroup[],
    maxId: number, notifyKind: string, positionHandled: boolean, fillPending: boolean): void {
    if (!positionHandled && !this.didInitialScroll && list.length > 0) {
      this.applyFirstScreenLanding(list, groups, maxId, fillPending);
    } else if (!positionHandled && this.didInitialScroll && maxId > this.lastMaxId) {
      this.followNewTailIfAtBottom(maxId, notifyKind);
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
  }

  private applyFirstScreenLanding(list: MessageEntry[], groups: AlbumGroup[],
    maxId: number, fillPending: boolean): void {
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
    // 方向一（进会话落在中间）的落点侧证据：这里说的是"选了哪条落点路径"，
    // 而 hasMoreNewer 说的是"贴的是已加载窗口的底还是真尾部"——两者要一起
    // 看才分得清"没跳到未读"和"跳到了但窗口本身没够到尾部"。
    const anchorHasMoreNewer: boolean =
      this.store !== null && this.store.getHasMoreNewer();
    logW(`[Anchor] latch fu=${fu} kind=${anchor.kind} index=${anchor.index}` +
      ` rows=${groups.length} fillPending=${fillPending}` +
      ` hasMoreNewer=${anchorHasMoreNewer}` +
      ` windowLast=${list.length > 0 ? list[list.length - 1].id : 0}`);
    const landSeq: number = this.scrollActionSeq;
    setTimeout((): void => {
      if (landSeq !== this.scrollActionSeq) {
        logW(`[Anchor] landed stale seq=${landSeq} cur=${this.scrollActionSeq}`);
        return;
      }
      logW(`[Anchor] landed kind=${anchor.kind} ${this.scrollStateProbe()}`);
    }, 400);
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
  }

  private followNewTailIfAtBottom(maxId: number, notifyKind: string): void {
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
  }

  private consumeJumpToLatestIntent(list: MessageEntry[], groups: AlbumGroup[],
    maxId: number): void {
    // jumpToLatest's newest page arrived — snap to the end. The dataset was
    // just replaced wholesale, so scroll once now and once after the List has
    // laid the new rows out: the immediate call alone lands at the top of the
    // reloaded page because the final row heights aren't known yet.
    if (this.pendingScrollBottom && list.length > 0) {
      this.pendingScrollBottom = false;
      this.lastMaxId = maxId;
      this.atBottom = true;
      const actionSeq: number = this.scrollActionSeq;
      const probeSeq: number = this.jumpLatestSeq;
      logW(`[JumpLatest] #${probeSeq} publish consume call=scrollEdge` +
        ` rows=${groups.length} list=${list.length} ${this.scrollStateProbe()}`);
      this.glueBottom('L1263');
      setTimeout(() => {
        if (actionSeq !== this.scrollActionSeq) {
          logW(`[JumpLatest] #${probeSeq} publish settle stale actionSeq=${actionSeq}` +
            ` cur=${this.scrollActionSeq}`);
          return;
        }
        this.glueBottom('L1266');
        this.refreshAtBottom();
        logW(`[JumpLatest] #${probeSeq} landed ${this.scrollStateProbe()}`);
      }, 60);
    } else if (this.pendingScrollBottom) {
      // 意图还挂着但这次发布没有内容可落——留着等下一次发布，别悄悄丢掉。
      logW(`[JumpLatest] #${this.jumpLatestSeq} publish kept intent list=0` +
        ` rows=${groups.length}`);
    }
  }

  private scheduleNewerTailRefresh(store: MessageStore, notifyKind: string): void {
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
  }

  // B15 批注：landPendingGallerySave(list)/landPendingFileOpen(list) 两个
  // 方法体（连同 processAutomaticGallerySave/saveMediaTo/openDownloadedFile
  // 三个私有方法）整体搬进了 MediaSaveState.onSnapshot/内部私有方法，逐字
  // 未改；调用点见 onMessagesSnapshot 里的 `this.mediaSave.onSnapshot(...)`。

  private landPendingJump(groups: AlbumGroup[]): void {
    // A pinned/quoted jump target that had to be loaded has now arrived — scroll to it.
    if (this.pendingJumpId !== 0) {
      const jumpTargetId: number = this.pendingJumpId;
      const jg: number = groupIndexOf(groups, jumpTargetId);
      logW(`[Jump80] pending land target=${jumpTargetId} idx=${jg} rows=${groups.length}`);
      if (jg >= 0) {
        const itemY: number = jumpTargetId === this.resumeDividerId
          ? this.resumeDividerItemY : 0;
        this.pendingJumpId = 0;
        // 落地宽限从**此刻**起算（issue #51）：原来只在点击时上了 900ms，目标不在
        // 窗口里要先 loadAround，慢链路上一超时，刚压进返回栈的那层就被
        // syncReturnState 当成"手动滑过"弹掉了。
        this.jumpLandingUntil = Date.now() + JUMP_LANDING_GRACE_MS;
        this.topCard.finishPinnedJump();
        this.scrollToTimelineIndexAtY(jg, itemY);
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
            this.scrollToTimelineIndexAtY(jg2, itemY);
            this.flash.flashAtIndex(jg2, jumpTargetId);
          }
        }, 80);
      }
    }
  }

  // 阶段 C：store 派生订阅、五路互斥的 open、进入即搜索。
  private registerHeaderDerivedSubscriptions(store: MessageStore): void {
    this.subscriptions.set('subtitle', store.subscribeSubtitle((s: string) => {
      this.header.applySubtitle(s);
    }));
    this.subscriptions.set('headerTitle', store.subscribeHeaderTitle((t: string) => {
      this.header.applyTitle(t);
    }));
    this.subscriptions.set('headerAvatar', store.subscribeHeaderAvatar((p: string) => {
      this.header.applyAvatar(p);
    }));
    this.subscriptions.set('replyKeyboard', store.subscribeReplyKeyboard((kb: ReplyKeyboard | null) => {
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
    }));
    // 三个值仍在这里从**订阅时的那个 store 形参**现取（不是 this.store），再交给
    // 控制器落库——控制器不去猜数据源是谁。夹紧 pinnedCycle、清空时收掉跳转闸门、
    // 结算同步态这三步整体搬进了 applyPinned()（B5）。
    this.subscriptions.set('pinned', store.subscribePinned((s: string) => {
      this.topCard.applyPinned(s, store.getPinnedIds().length, store.getPinnedLoadState());
    }));
  }

  // 五路互斥分支整体留在同一个方法里：它们共享 didInitialScroll / pendingJumpId /
  // pendingResumeId 的选择逻辑，拆开就可能同时命中两支。
  private openStoreForRoute(store: MessageStore, ctx: RouteApplyContext): void {
    const jumpTo: number | undefined = ctx.jumpTo;
    if (this.routeResumeWaiting) {
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
      logW(`[Jump80] open chat=${this.chatId} jumpTo=${jumpTo} search=${this.search.mode}`);
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
      const remembered: RememberedChatViewport = rememberedChatViewport(
        this.chatId,
        conversationScopeId(this.threadRootId, this.forumTopicId, this.directMessagesTopicId)
      );
      if (remembered.messageId > 0) {
        // The store resolves the authoritative unread count asynchronously.
        // Keep this as a candidate until the first ready snapshot says whether
        // resume or unread won; only then does it become the single landing.
        this.pendingResumeId = remembered.messageId;
        this.pendingResumeItemY = remembered.itemY;
        store.open(remembered.messageId, false, true);
      } else {
        store.open();
      }
    }
  }

  // scheduleEntrySearchIfNeeded 搬进了 SearchSession.scheduleEntrySearch()
  // （B6 批）；applyRouteParams 阶段 A 收尾时的调用点改走 this.search.
  // scheduleEntrySearch()。

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
    // 装饰器与这具 if/else 骨架必须留在页面：@Monitor 只能监听页面自己的
    // @Param/@Local，且不在 @ObservedV2 类里新增（不变量 7）。仿 B10 的
    // @Monitor('translateChatsEnabled') 先例。
    if (!this.playSlotsEnabled()) {
      this.playSlot.onPolicyDisabled();
      return;
    }
    this.playSlot.armSettle();
  }

  private handleHidden(): void {
    coordinateChatPageHidden({
      stopScrollActivity: (): void => { setScrollActive(false); },
      endLinkNavigation: (): void => { endLinkNav(); },
      cancelInitialTransition: (): void => { this.cancelInitialMessageTransitionSettle(); },
      setPageVisible: (visible: boolean): void => { this.pageVisible = visible; },
      syncChatTgsGate: (): void => { this.syncChatTgsGate(); },
      captureHiddenAnchor: (): void => {
        this.hiddenSinceMs = Date.now();
        this.captureHiddenAnchor();
      },
      clearNowSecTimer: (): void => { this.clearNowSecTimer(); },
      clearSlotTick: (): void => { this.playSlot.clearTick(); },
      suspendPlaySlots: (): void => { this.playSlot.suspend(); }
    });
  }

  private handleWillHide(): void {
    coordinateChatPageWillHide({
      stopScrollActivity: (): void => { setScrollActive(false); },
      cancelInitialTransition: (): void => { this.cancelInitialMessageTransitionSettle(); },
      setPageVisible: (visible: boolean): void => { this.pageVisible = visible; },
      syncChatTgsGate: (): void => { this.syncChatTgsGate(); },
      clearNowSecTimer: (): void => { this.clearNowSecTimer(); },
      clearSlotTick: (): void => { this.playSlot.clearTick(); },
      suspendPlaySlots: (): void => { this.playSlot.suspend(); }
    });
  }

  private handleShown(): void {
    const state: ChatPageShownState = {
      hiddenSinceMs: this.hiddenSinceMs,
      appWentBackground: this.appWentBackground,
      hiddenListDirty: this.hiddenListDirty
    };
    coordinateChatPageShown(state, {
      setPageVisible: (visible: boolean): void => { this.pageVisible = visible; },
      armInitialTransitionSettle: (): void => { this.armInitialMessageTransitionSettle(); },
      scheduleInitialTimelinePresentation: (): void => { this.scheduleInitialTimelinePresentation(); },
      scheduleChatTgsResume: (): void => { this.scheduleChatTgsResume(); },
      endLinkNavigation: (): void => { endLinkNav(); },
      armPlaySlotSettle: (): void => { this.playSlot.armSettle(); },
      resyncListAfterHidden: (): void => { this.resyncListAfterHidden(); },
      setNowSec: (value: number): void => { this.nowSec = value; },
      armNowSecTimer: (): void => { this.armNowSecTimer(); },
      // B5：清 liveDialogOpening/liveNavigationBusy 这两句原样搬进了
      // topCard.onPageShown()。本批的任务书写的是「handleHidden 里清 → onPageHidden()」，
      // 那是计划文档 B5 小节的笔误：handleHidden / handleWillHide 一个字都不碰这一簇，
      // 清忙标志的一直是这里（handleShown → coordinateChatPageShown 的
      // clearLiveNavigationBusy 钩子）。控制器因此只有 onPageShown()，没有 onPageHidden()——
      // 凭空造一个「隐藏时清」会是真的行为变更（今天隐藏时不清，标志一直留到页面回来）。
      clearLiveNavigationBusy: (): void => { this.topCard.onPageShown(); },
      chatId: (): number => this.chatId,
      refreshVideoChat: (): void => { this.topCard.refreshVideoChat(); }
    });
    this.hiddenSinceMs = state.hiddenSinceMs;
    this.appWentBackground = state.appWentBackground;
    this.hiddenListDirty = state.hiddenListDirty;
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
    this.disposeInitialStageAndTgs();
    this.disposePlaybackAndSlots();
    this.persistDraftAndViewport();
    this.disposeTimersAndSeqGuards();
    this.stopVoicePlaybackKeepingMusic();
    this.disposeSubscriptionsInOrder();
    this.closeStores();
  }

  private disposeInitialStageAndTgs(): void {
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
  }

  private disposePlaybackAndSlots(): void {
    // 退出会话时播放器可能还开着（返回手势不走 closeViewer），为播放拉起的
    // 下载得在这里也停掉，否则回到列表页它还在后台跑。
    this.releasePlaybackRequests();
    this.playSlot.dispose();
    this.subscriptions.clear('playSlot');
    this.clearNowSecTimer();
    this.subscriptions.clear('chatAction');
    this.subscriptions.clear('jump');
    // "正在输入…" 控制器的退场（B10）。本簇没有序号守卫，dispose() 只清
    // 1500ms 轮询定时器句柄——原来这三行 clearInterval 就放在这个位置。
    this.typing.dispose();
  }

  private persistDraftAndViewport(): void {
    // Sync the composer draft to the account (other devices see it). While an
    // edit is in progress the real draft is the stashed pre-edit text.
    this.store?.saveDraft(this.composer.draftToPersist(this.draft), this.composer.replyToId);
    this.exitViewerLandscape();
    this.captureScrollResume();
  }

  private disposeTimersAndSeqGuards(): void {
    this.bottomChromeLayoutSeq++;
    this.imeTailPinned = false;
    this.imeLayoutSeq++;
    this.closeHeaderMenu();
    // 原 showReactionSheet=false; reactionTargetId=0; closeForwardSheet() 三行
    // 搬进了 this.overlayState.dispose()（B11 批）——与 resetSession() 字段集合不
    // 对称，原代码在这条路径上就没有清 reactionPendingKey，如实保留，没有
    // 补齐。dispose() 额外清 stickerGhostTimer，是本批新增的加固：原
    // aboutToDisappear 全链路对这个定时器没有任何清理动作，不是逐字搬迁。
    this.overlayState.dispose();
    // 顶栏身份解析控制器的退场（B8）。resolveSeq++/profileOpening/
    // muteUpdating/navigationTimer 清理整簇搬进了 header.dispose()——原来这四样
    // 分两处（这里一处，openProfile 定时器那里一处），控制器统一收口到
    // dispose() 里，顺序仍是 ++resolveSeq 在最前。closeHeaderMenu() 不在
    // dispose() 里：头部菜单域本轮不动，仍由页面自己在这里直接调用（就是上面
    // 这一句）。
    this.header.dispose();
    // 顶栏浮卡整簇的退场（B5）。位置就是原来那九句 live*/pinnedJumpBusy/
    // topCardLoadingVisible 清理所在的位置，相对于 clearInOrder 三组退订的先后
    // 一字未动；两个 clearTimeout（topCardLoadingTimer/topCardActionTimer）原本
    // 在本方法靠后处，也一并进了 dispose()。
    // 顺序在控制器里照搬：两个 seq++ 在最前（作废在途的 getChat/getGroupCall），
    // 再清在途与忙标志，最后才清定时器句柄。
    // 唯一的时序变化：两个 setInterval 原本是最后一步 closeStores 清的，现在提前
    // 到这里。中间隔着的 stopVoicePlaybackKeepingMusic 与 disposeSubscriptionsInOrder
    // 都不 await，定时器插不进去，等价。
    this.topCard.dispose();
    // 会话内搜索控制器的退场（B6）。原来的 search* 字段一直没有对应的
    // aboutToDisappear 清理——整个 ChatPage 实例随导航栈弹出一起丢弃。搬进
    // entryTimer 这个真句柄之后就需要一处收口，与 topCard 同放一组：先
    // ++seq 作废在途的 searchChatMessages 响应，再清 entryTimer。
    this.search.dispose();
    // 多选控制器的退场（B7）。本簇没有定时器/序号守卫，dispose() 只是裸清
    // active/ids——与其余控制器统一 bind/dispose 生命周期，同样没有对应的
    // 旧清理位置可循，放在这一组里。
    this.selection.dispose();
    // 输入框上方那一条控制器的退场（B9）。本簇没有异步在途请求要守（commitEdit
    // 的 TDLib 请求留页面自己管），只清 startReply 那一次 setTimeout(0) 的句柄
    // ——与其余控制器统一 bind/dispose 生命周期，同样没有对应的旧清理位置
    // 可循，放在这一组里。
    this.composer.dispose();
    // 会话翻译驱动的退场（B10）。本簇没有需要在换会话/页面销毁时作废的异步
    // 在途请求或定时器句柄（批量翻译/单条重译各自靠调用时刻捕获的
    // this.store === store 判陈旧），dispose() 是空实现，仅为与其余控制器
    // 统一 bind/dispose 生命周期而保留、调用。
    this.translation.dispose();
    // 附件面板分发簇的退场（B12）。逐行核对过原 aboutToDisappear 全链路七个
    // 子方法，对 mediaPickerOpen/mediaCopySeq 从来没有任何清理——两个字段随
    // 页面实例一起被丢弃，不产生可观察副作用。dispose() 是空实现，仅为与
    // 其余控制器统一 bind/dispose 生命周期而保留、调用，不替原代码编造一份
    // 清理逻辑。
    this.attach.dispose();
    // 跳转目标高亮控制器的退场（B13）。侦察确认过原 aboutToDisappear 全链路
    // 对 flashSeq/flashShown/flashTop/flashHeight/flashAlpha/flashTargetIdx/
    // flashTargetId 或 cancelFlash/syncFlashRect/runBlink/flashAtIndex 从来
    // 没有任何清理——裸露的 setTimeout 句柄从未存储，靠 flashSeq 比较自然
    // 失效，页面随实例整体丢弃。dispose() 是空实现，仅为与其余控制器统一
    // bind/dispose 生命周期而保留、调用，不替原代码编造一份清理逻辑。
    this.flash.dispose();
    // 输入条上方四块建议面板控制器的退场（B14）。逐字核对过原
    // aboutToDisappear 全链路（含本方法），对 mentionItems/pendingNameMentions/
    // mentionSeq、commandItems/allCommands/commandLoadState/commandLoadError/
    // commandMenuOpen/botMenuAvailable/commandLoadSeq、inlineResults/
    // inlineQueryId/inlineSeq/inlineTimer、stickerSuggestions/
    // stickerSuggestSeq 这四簇字段一个匹配都没有——包括那个眼看着像该清的
    // 320ms 内联查询防抖定时器。四个 dispose() 都是空实现，仅为与其余控制器
    // 统一 bind/dispose 生命周期而保留、调用，不替原代码编造一份清理逻辑。
    this.mention.dispose();
    this.command.dispose();
    this.inline.dispose();
    this.sticker.dispose();
    this.scrollActionSeq++;
    this.jumpLayoutSeq++;
    this.anchor.invalidate();
    this.scrollToBottomBusy = false;
    this.clearPendingScrollBottom('pageHide');
    this.clearFloatingDate();
    // 麦克风录音状态机的退场（B15）。原裸调 `this.cancelRecording();` 改经
    // `this.recording.dispose()`——控制器自己的 dispose() 逐字等价为
    // cancel()，不新增、不少做（见 VoiceRecordingState.ets 文件头）。
    this.recording.dispose();
    // 媒体保存/下载簇的退场（B15）。原 `pendingGallerySaveId=0 →
    // pendingGallerySaveProgress.dispose() → 置空 → pendingFileOpenId=0 →
    // fileOpenInFlightId=0 → (musicQueue.reset()) → autoSavePendingIds=[] →
    // autoSaveInFlight=false` 八行里，除 musicQueue.reset() 外的七行原样
    // 收进 `this.mediaSave.dispose()`；musicQueue.reset() 操作的是页面另一个
    // 字段，不属于本簇，继续原地留在页面（顺序上从"夹在中间"挪到
    // "mediaSave.dispose() 之后"，两者互不读写对方的状态，不可观察，见
    // MediaSaveState.ets 文件头「dispose() 的 8 行 vs 7 行」一节）。
    this.mediaSave.dispose();
    this.musicQueue.reset();
  }

  private stopVoicePlaybackKeepingMusic(): void {
    getVoicePlayback().setMusicCompletionListener(null);
    // **音乐不随本页退场而停**——这是底栏迷你播放条的前提：退回会话列表后曲子
    // 还得在放，否则那条播放条永远没东西可显示。VoicePlayback 本来就挂着
    // mediaPlaybackKeepAlive（audioPlayback 后台任务），能力一直是有的，只是被
    // 这一行无条件掐掉了。
    //
    // 语音（mode === 'voice'）维持原样立刻停：一条语音消息在你已经离开会话之后
    // 还在念，是没人想要的。自动连播也确实随本页结束——它要整份 messages 数组
    // （MusicQueue.next），页面一销毁就没有了，所以上面那行监听器照旧摘掉。
    if (getVoicePlayback().current().mode !== 'music') {
      getVoicePlayback().stop();
    }
  }

  private disposeSubscriptionsInOrder(): void {
    this.subscriptions.clearInOrder([
      'messages', 'subtitle', 'chat', 'liveLocation', 'translatable', 'background'
    ]);
    if (this.bgStore !== null) {
      this.bgStore.close();
      this.bgStore = null;
    }
    this.subscriptions.clearInOrder([
      'pinned', 'headerAvatar', 'headerTitle', 'replyKeyboard'
    ]);
    // 成员资格状态机的退场（第二轮 R2-A 批）：dispose() 只做原来这里那一行
    // membershipSeq++，作废在途的三层异步（getChat/getSupergroup/
    // getBasicGroup），紧邻退订下面这两个推送监听器之前，位置未动。
    this.membership.dispose();
    this.subscriptions.clearInOrder([
      'membershipSupergroup', 'membershipBasicGroup', 'videoChat', 'groupCall'
    ]);
  }

  private closeStores(): void {
    // 两个直播定时器（脉冲/轮询）的 clearInterval 随整簇进了 topCard.dispose()，
    // 在本方法之前的 disposeTimersAndSeqGuards 里执行（B5）。
    if (this.store !== null) { this.store.close(); this.store = null; }
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
    this.replaceTimelineGroups(this.groups);
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

  // 换算规则整条搬到 util/chatEffects.ets 的 chatEffectDurationOf（注释也在那边）；
  // 这里只补上 this.reduceAnimations 这一个参数，十余处调用点保持原样。
  private chatEffectDuration(key: string, duration: number): number {
    return chatEffectDurationOf(this.reduceAnimations, key, duration);
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
      // 正在播的 GIF 点一下开大图（issue #105）。原来这里是「点一下暂停」——图库
      // 里的 GIF 改成按 inputMessageAnimation 发出去之后，它们从 messagePhoto
      // 变成了 messageAnimation，走到这条分支，用户发现「能动了，但点不开了」。
      // 官方客户端就是点开大图，内联没有暂停这回事；没在播的那条分支照旧：
      // 先起播（自动播放关着时这就是"点一下播"）。
      this.openViewer(messageId);
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
    if (!mediaEntryIsPhoto(entry) && !mediaEntryIsVideo(entry)) {
      return;
    }
    if (mediaEntryIsPhoto(entry) && entry.photoPath === '' && entry.photoFailed) {
      this.store?.retryPhoto(messageId);
      promptAction.showToast({ message: $r('app.string.cp_reloading_thumb'), duration: 1200 });
      return;
    }
    if (mediaEntryIsPhoto(entry) && entry.photoPath === '' &&
      entry.photoFullPath === '' && entry.photoFileId === 0 && entry.photoFullFileId === 0) {
      promptAction.showToast({ message: $r('app.string.cp_photo_unavailable'), duration: 1500 });
      return;
    }
    if (mediaEntryIsVideo(entry)) {
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
    // **这一句必须留在 animateTo 之前**：@Monitor('viewerMsgId') 会在
    // viewerMsgId 归零那一刻同步把 viewerPositionMs 清成 0，挪到后面就永远记 0。
    this.playSlot.handoffFromViewer(viewerMessageId,
      albumIndexOfMember(this.groups, viewerMessageId), this.viewerPositionMs);
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
    this.playSlot.armSettle();
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
    if (this.overlayState.showVideoNoteRecorder) {
      this.overlayState.showVideoNoteRecorder = false;
      return true;
    }
    if (this.headerMenuShow) {
      this.closeHeaderMenu();
      return true;
    }
    if (this.overlayState.showForwardSheet) {
      this.overlayState.closeForwardSheet();
      return true;
    }
    if (this.overlayState.showReactionSheet) {
      this.overlayState.closeReactionSheet();
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
    if (this.selection.active) {
      this.selection.exit();
      return true;
    }
    if (this.search.mode) {
      this.search.exit();
      return true;
    }
    return false;
  }

  // Refresh the floating date chip from the topmost visible row and (re)arm
  // its fade-out. This is called only for a touch-originated scroll session:
  // initial positioning and reply/pinned jumps must not flash the chip.
  private updateFloatDate(start: number): void {
    if (!this.didInitialScroll || start < 0 || start >= this.groups.length) {
      return;
    }
    // 行号得是新鲜的：往上翻插进一页后 groups 已经换了，而 curStartIdx 要等下一次
    // onScrollIndex 才刷新，这期间拿旧行号查新 groups 会差出一整页（issue #163
    // 的另一半）。refreshAtBottom 用的是同一道判据。
    if (this.indexGroupsLen !== this.groups.length) {
      return;
    }
    const now: number = Date.now();
    // onDidScroll fires every rendered frame. If the top row hasn't changed,
    // skip the group scan and the date formatting; only refresh the hide timer
    // at a coarse cadence so a long drag keeps the chip visible.
    //
    // **这道早退必须排在下面那次量布局之前**：firstRowBelowChrome 要 getItemRect
    // （布局查询，每帧最多三次），而顶行下标没变时它的结果一定和上次一样。原来
    // 这里是拿 start 直接比的，加了 chrome 让位之后仍然拿 start 当第一道闸。
    if (start === this.floatDateStartIdx && this.floatDateIndex >= 0) {
      this.floatDateState.keepAlive(now);
      return;
    }
    this.floatDateStartIdx = start;
    // start 是 List「显示区」的第一行，包括已经滚到浮动标题栏底下的那一行；
    // 日期条要报的是用户看得见的第一行，见 util/floatDateGate.firstRowBelowChrome。
    const top: number = firstRowBelowChrome(start, this.groups.length,
      this.headerChromeHeight(), (index: number): number => this.rowBottomVp(index));
    // 两道判据的归属见 util/floatDateGate 的注释：扫不扫 groups 由这里判（数据
    // 在这边），续不续期由日期条自己判（定时器在那边）。
    if (!floatDateNeedsRescan(top, this.floatDateIndex)) {
      this.floatDateState.keepAlive(now);
      return;
    }
    let date: number = 0;
    for (let i = top; i < this.groups.length; i++) {
      if (this.groups[i].head.date > 0) {
        date = this.groups[i].head.date;
        break;
      }
    }
    if (date <= 0) {
      return;
    }
    if (!this.listUserScrollActive) {
      this.listUserScrollActive = true;
    }
    this.floatDateIndex = top;
    this.floatDateState.show(formatDateSeparator(date), now);
  }

  // 锚点采样：第 index 行相对 List 顶的 y。**量不到时返回 NaN，绝不返回 0**。
  //
  // 官方（faqs-arkui-572）：getItemRect 的下标必须是当前显示区域内的子组件，
  // 否则视为非法值，**非法值返回的大小和位置均为 0**。原来两处采样都是
  // `try { y = getItemRect(i).y } catch { y = 0 }` —— 非法下标和"行正好贴在
  // 视口顶端(y=0)"取到的是同一个 0，分不开。而 anchorRestore 的
  // dy = rect.y - itemY 会把这个假 0 当成真位置，补出整行级别的位移。
  private anchorItemY(index: number): number {
    try {
      const rect = this.scroller.getItemRect(index);
      // width/height 两维都为 0 才是非法（正常停在视口顶端的行 y 就是 0，
      // x 在单列列表里恒为 0——照抄"四维都不为 0"会把它误判成不可见）。
      if (!(rect.width > 0) || !(rect.height > 0)) {
        return Number.NaN;
      }
      return rect.y;
    } catch (e) {
      return Number.NaN;
    }
  }

  // 行号是不是描述当前这份数据。锚点采样读的是 curStartIdx，它由 onScrollIndex
  // 给出、落后于数据一帧；拿旧行号去 groups 里取消息 id，会差出一整页
  // （updateFloatDate 为同一件事加过这道守卫，见 issue #163 的另一半）。
  private anchorIndexFresh(): boolean {
    return this.indexGroupsLen === this.groups.length;
  }

  // 第 index 行相对 List 顶的下沿（vp）；量不到返回 NaN，调用方按"看得见"处理。
  //
  // 高度为 0 也算量不到：还没布局的行 getItemRect 返回**全 0 矩形**
  // （faqs-arkui-572，同 attemptAnchorRestore 里那条注释），而 0 会被当成
  // "整行都在标题栏上面"往下跳，日期条就报成了视口下方那一天。
  private rowBottomVp(index: number): number {
    try {
      const rect = this.scroller.getItemRect(index);
      if (!(rect.height > 0)) {
        return Number.NaN;
      }
      return rect.y + rect.height;
    } catch (e) {
      return Number.NaN;
    }
  }

  // 隐藏定时器烧到底时由 FloatingDateState 回调（aboutToAppear 里挂上）。
  //
  // 【为什么时序等价】搬走之前，这三件事写在**同一个** 820ms 定时器体里：
  // floatDateShown = false、listUserScrollActive = false、floatDateIndex = -1。
  // 现在定时器还是同一条、时长还是 820ms，只是拆成"日期条自己翻 shown" +
  // "回调里翻另外两个"，两段在同一次回调的同一个同步块里先后执行，中间没有
  // await、没有再一次 setTimeout。对读 listUserScrollActive 的那两方（翻页闸
  // util/pageGate、锚点判据 appendAnchorGateProbe）来说，它翻假的那一刻与原来
  // 分毫不差。
  private onFloatDateHidden(): void {
    this.listUserScrollActive = false;
    this.floatDateIndex = -1;
    this.floatDateStartIdx = -1;
  }

  private prepareUserJump(): void {
    this.clearFloatingDate();
    this.stayAtUnread = false;
    this.jumpLayoutSeq++;
    this.flash.cancelFlash();
  }

  // 点置顶条时目标不在当前窗口内，要先去取。这是 onPinnedTap 的 PINNED_LOAD
  // 兜底分支原样搬过来的（B5 所有权裁决）：pendingJumpId 是整个跳转系统的共享
  // 字段（landPendingJump / openStoreForRoute / resetOrPreserveScrollSession
  // 都读写它），按不变量 10 留在页面，所以这条链也留在页面，由控制器经
  // host.jumpToPinned(messageId) 发起。
  // 取不到时复位 pendingJumpId、收掉跳转闸门、重拉置顶列表并弹提示；取到了则
  // 由 landPendingJump 在行数组发布后落地（那里同样调 topCard.finishPinnedJump()）。
  // 控制器侧在调进来之前已经上了一道 2500ms 的 busy 守卫——比另两支的
  // TOP_CARD_ACTION_GUARD_MS 长，就是为了等这趟异步 loadAround。
  private jumpToPinned(messageId: number): void {
    const store: MessageStore | null = this.store;
    if (store === null) {
      return;
    }
    const targetId: number = messageId;
    this.pendingJumpId = targetId;
    store.loadAround(targetId, (found: boolean): void => {
      if (!found && this.pendingJumpId === targetId) {
        this.pendingJumpId = 0;
        this.topCard.finishPinnedJump();
        this.store?.refreshPinned();
        promptAction.showToast({ message: $r('app.string.cp_pinned_unavailable'), duration: 1500 });
      }
    });
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
  // 判据是"整份数据都在屏幕上"（首行和末行同时可见）⇒ 列表滚不动 ⇒ 滚动事件
  // 永远不来，得自己敲门。判据与完整推导见 util/viewportFill——第一版只问
  // "最后一行可见吗"，而列表是 stackFromEnd(true)、最后一行几乎恒可见，于是
  // 用户停在底部时也会一路往上补页，正是"带未读进会话立刻下滑却滑不动"的直接
  // 成因之一。
  private fillViewportIfNeeded(): void {
    if (this.store === null) {
      return;
    }
    const fill: boolean = shouldFillViewport({
      hasMoreOlder: this.store.getHasMoreOlder(),
      rows: this.groups.length,
      maxRows: ChatPage.FILL_VIEWPORT_MAX_ROWS,
      startIdx: this.curStartIdx,
      endIdx: this.curEndIdx,
      indexRows: this.indexGroupsLen
    });
    if (!fill) {
      return;
    }
    logW(`[FillViewport] fill rows=${this.groups.length}` +
      ` start=${this.curStartIdx} end=${this.curEndIdx}` +
      ` idxLen=${this.indexGroupsLen} maxRows=${ChatPage.FILL_VIEWPORT_MAX_ROWS}`);
    this.olderArmed = true;
    this.maybeLoadOlder();
  }

  // 只有闸在膛上、且视口确实往下走过，才再取一页。见 util/pageGate。
  private maybeLoadNewer(end: number): void {
    if (this.store === null) {
      return;
    }
    const gate: PageGate = this.newerGate;
    const canFire: boolean = canFirePageGate(gate, end);
    // ⚠️ 诊断 [NewerFire]：用户报"下滑也推不动"。要能分清两件完全不同的事：
    //   闸挡住了      → 这里 canFire=false，且写明是 armed 还是弱闸挡的；
    //   闸放行了没进展 → canFire=true / started=true，但后面 rows 不涨、
    //                    或者 rows 涨了而 endIdx 原地不动（位置被布局吃掉）。
    // 按 end 去重：onScrollIndex 只在可见区间变化时触发，但布局抖动会让它高频
    // 变化，不去重会把环形缓冲刷满（logW 攒 300 行才落盘）。
    if (end !== this.newerFireLoggedEnd) {
      this.newerFireLoggedEnd = end;
      const blockedBy: string = canFire
        ? 'none' : (gate.armed ? 'weakGate' : 'disarmed');
      logW(`[NewerFire] end=${end} rows=${this.groups.length} firedAt=${gate.firedAtEnd}` +
        ` armed=${gate.armed} byUser=${gate.armedByUser}` +
        ` dragSinceFire=${Math.round(gate.dragSinceFire)}/${PAGE_GATE_REARM_DRAG_VP}` +
        ` canFire=${canFire} blockedBy=${blockedBy}` +
        ` touch=${this.listTouchActive} userScroll=${this.listUserScrollActive}` +
        ` hasMoreNewer=${this.store.getHasMoreNewer()}` +
        ` newerState=${this.store.getNewerLoadState()}` +
        ` deferredLeft=${this.countDeferredRows()}`);
    }
    if (!canFire) {
      return;
    }
    // 谁扣的这一枪的扳机。判据是**这一膛是谁压上去的**：手指位移上膛的是用户
    // （armedByUser=true），会话开局给首屏自动补页留的那一发不是。标记随请求带
    // 到发布点，决定那一页落地时复不复位锚点。
    // 不能读 listTouchActive / listUserScrollActive——那两个标志的语义不对，而且
    // 和上膛条件同源，会让 skip 结构上不可达（见 util/appendAnchor）。
    const userDriven: boolean = newerPageIsUserDriven(pageGateShotIsUserDriven(gate));
    const started: boolean = this.store.loadNewer(userDriven);
    logW(`[NewerFire] request end=${end} started=${started} userDriven=${userDriven}` +
      ` hasMoreNewer=${this.store.getHasMoreNewer()}` +
      ` newerState=${this.store.getNewerLoadState()} rows=${this.groups.length}`);
    if (started || !this.store.getHasMoreNewer()) {
      this.newerGate = firedPageGate(gate, end);
    }
  }

  // 用户手指拖动列表：攒够位移就给向下分页的闸重新上膛。
  //
  // 只从 onDidScroll 的 ScrollState.Scroll 那一支进来（见那里的说明）。上膛的
  // 那一帧在**仍处于末端触发区**时立刻补敲一次门：onScrollIndex 只在可见行号
  // 区间变化时触发，而用户正贴在末尾时 end 恒等于 rows - 1，纹丝不动——光等
  // onScrollIndex 的话，刚上膛的这一发会一直没机会打出去。
  //
  // 末端检查不能少：append 锚点复位若发生在手指仍按住时，ArkUI 会把控制器位移
  // 也报成 Scroll。真机日志里它在 rows=70/end=41 时重新上膛；旧代码无条件补敲，
  // 于是远离末端仍继续拉页并再次复位，正是进入未读很多的频道后 3~5 秒内滑动
  // 不跟手、松手弹回的闭环。
  private accumulateNewerDrag(offset: number): void {
    const before: PageGate = this.newerGate;
    if (before.armed) {
      return;
    }
    const after: PageGate = draggedPageGate(before, offset);
    this.newerGate = after;
    if (!after.armed) {
      return;
    }
    logW(`[NewerFire] rearm reason=drag end=${this.curEndIdx} rows=${this.groups.length}` +
      ` byUser=${after.armedByUser} thresholdVp=${PAGE_GATE_REARM_DRAG_VP}`);
    if (reachedNewerPageTrigger(this.curEndIdx, this.groups.length)) {
      this.maybeLoadNewer(this.curEndIdx);
    }
  }

  // [NewerFire] 去重用：上一条已经记过的 end。
  private newerFireLoggedEnd: number = -1;

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


  // ⚠️ 临时探针（随 APPEND_ANCHOR_RESTORE_BYPASSED 一起删）：把决定这道闸开合的
  // 全部输入打在同一行上——旧判据（hasMoreNewer/atBottom/verdict）留着，好和新
  // 判据（reqUserDriven 及其两个输入）对照，上机时一眼能看出闸是按哪一维开合的。
  // 新判据下 hold 应当只出现在用户手势翻页那一页上，自动追加一律是 skip。
  //
  // 刻意不调 refreshAtBottom：那个会写 this.atBottom。这里只读，绝不改状态。
  // groupsLen 用**新快照**的长度，因为闸是在发布这份快照时判的。
  private appendAnchorGateProbe(groups: AlbumGroup[]): string {
    const hasMoreNewer: boolean = this.store !== null && this.store.getHasMoreNewer();
    let scrollerAtEnd: boolean = false;
    try {
      scrollerAtEnd = this.viewerMsgId !== 0 ? false : this.scroller.isAtEnd();
    } catch (e) {
      scrollerAtEnd = false;
    }
    const verdict: string = atBottomVerdict({
      viewerOpen: this.viewerMsgId !== 0,
      imeTailPinned: this.imeTailPinned,
      scrollerAtEnd: scrollerAtEnd,
      visibleEndIdx: this.curEndIdx,
      indexGroupsLen: this.indexGroupsLen,
      groupsLen: groups.length,
      hasMoreNewer: hasMoreNewer
    });
    return `hasMoreNewer=${hasMoreNewer} atBottom=${this.atBottom} verdict=${verdict}` +
      ` scrollerAtEnd=${scrollerAtEnd} startIdx=${this.curStartIdx} endIdx=${this.curEndIdx}` +
      ` idxLen=${this.indexGroupsLen} userScroll=${this.listUserScrollActive}` +
      ` touch=${this.listTouchActive} newerArmed=${this.newerGate.armed}` +
      ` gateByUser=${this.newerGate.armedByUser}` +
      ` reqUserDriven=${newerPageIsUserDriven(pageGateShotIsUserDriven(this.newerGate))}`;
  }

  // ⚠️ 临时探针（[InitialPage] / [Anchor] / [JumpLatest] 共用，判读完一起删）：
  // 当前视口与分页状态的一行快照。首屏落点和 ↓ 的走向都要靠这几个值判读，
  // 尤其是"贴的是已加载窗口的底（hasMoreNewer=true）还是真尾部"。
  private scrollStateProbe(): string {
    const hasMoreNewer: boolean = this.store !== null && this.store.getHasMoreNewer();
    let scrollerAtEnd: boolean = false;
    try {
      scrollerAtEnd = this.viewerMsgId !== 0 ? false : this.scroller.isAtEnd();
    } catch (e) {
      scrollerAtEnd = false;
    }
    const verdict: string = atBottomVerdict({
      viewerOpen: this.viewerMsgId !== 0,
      imeTailPinned: this.imeTailPinned,
      scrollerAtEnd: scrollerAtEnd,
      visibleEndIdx: this.curEndIdx,
      indexGroupsLen: this.indexGroupsLen,
      groupsLen: this.groups.length,
      hasMoreNewer: hasMoreNewer
    });
    return `hasMoreNewer=${hasMoreNewer} atBottom=${this.atBottom} verdict=${verdict}` +
      ` scrollerAtEnd=${scrollerAtEnd} startIdx=${this.curStartIdx} endIdx=${this.curEndIdx}` +
      ` rows=${this.groups.length} pendingBottom=${this.pendingScrollBottom}` +
      ` pendingJumpId=${this.pendingJumpId} busy=${this.scrollToBottomBusy}`;
  }


  // refreshMembership/applyMembershipStatus 逐字搬进了 MembershipSession
  // （第二轮 R2-A 批，见文件头字段声明处的注释与该类文件头）。此处只留
  // joinCurrentChat：它除了读写页面自留的 membershipState/joiningChat 之外
  // 还要调页面自己的 showClientJoinNotice()，不是"整方法体搬迁"的候选，见
  // MembershipSession.ets 文件头【本批未迁移的两处】节。
  // 这里对 membershipState/joiningChat 的写**全部保持页面直写**（HEAD 就是
  // 这样）：它们是页面自留 @Local，setMembershipState 只是控制器回调页面的
  // 入口，页面自己写自己的字段不绕道。本批只把 this.refreshMembership()
  // 那一行改成了 this.membership.refresh()。
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
      this.membership.refresh();
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
    // 跳转还在路上（目标不在窗口里、正在 loadAround）时不判：这期间视口还停在
    // 出发点，onScrollIndex 却会因为拉回来的那页插入而触发；900ms 的落地宽限是
    // 从点击起算的，慢链路上一超时就把刚压进去的那层弹掉（atBottom 时更是整套
    // 作废），「↓」从此只会回到底（issue #51）。
    if (this.pendingJumpId !== 0) {
      return;
    }
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

  private stackFromEndWanted(): boolean {
    return stackFromEndWanted(this.store !== null && this.store.getHasMoreNewer());
  }

  private onScrollFabTap(): void {
    const target: ReturnTarget = this.returnTarget();
    // ⚠️ 临时探针 [JumpLatest]：↓ 不是"回到底部"而是三级返回（引用栈 > 阅读
    // 进度 > 最新，见 util/readingReturn）。用户说"要点好几次"时，第一件要分
    // 清的就是前几下究竟去了返回点还是真的走了 scrollToLatest——这行日志把
    // 每一次点击各自选的分支和当时的返回栈都记下来。
    this.jumpLatestSeq++;
    logW(`[JumpLatest] #${this.jumpLatestSeq} tap route=${target.kind}` +
      ` targetId=${target.messageId} curBottomId=${this.curBottomId}` +
      ` readAnchor=${this.returnState.readAnchor}` +
      ` jumpStack=${this.returnState.jumpStack.length} ${this.scrollStateProbe()}`);
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
    const replyId = this.composer.replyToId;
    this.atBottom = true;
    this.stayAtUnread = false;
    this.withSendLock((): Promise<void> => store.sendAsync(command, replyId).then((): void => {
      if (this.composer.replyToId === replyId) {
        this.composer.clearReply();
      }
    }).catch((e: TdError): void => {
      logE(`ChatPage.botCommand failed: ${e.message}`);
      promptAction.showToast({ message: $r('app.string.cp_command_failed'), duration: 1600 });
    }));
  }

  // 点了消息里的链接。分派本身（走哪一路、载荷是什么）在
  // util/messageLinkAction，有单测；这里只负责执行。
  // 真 URL 统一先让用户选择「打开 / 复制」。机器人命令、话题标签、号码等
  // 本地伪链接在 onLinkTap 的前几条分支直接处理，不会多弹这一层。
  private offerLinkAction(url: string): void {
    promptAction.showActionMenu({
      title: url.length > 60 ? url.substring(0, 57) + '…' : url,
      buttons: [
        { text: $r('app.string.lk_open'), color: '#3390EC' },
        { text: $r('app.string.mb_copy_url'), color: '#3390EC' }
      ]
    }).then((result: promptAction.ActionMenuSuccessResponse): void => {
      if (result.index === 0) {
        this.onLinkTap(url, true);
        return;
      }
      copyPlainText(url, str('link_copied'));
    }).catch((): void => {});
  }

  private onLinkTap(url: string, openConfirmed: boolean = false): void {
    const action: LinkAction = linkActionOf(url);
    if (this.handleLocalLinkAction(action)) {
      return;
    }
    // Telegram 内链（t.me/@名/tg://）应用内直接解析，不弹「打开/复制」层
    // ——那层是给外部网页链接的（用户反馈 t.me 被当浏览器链接多问了一道）。
    if (!openConfirmed && !isTelegramInternalUrl(url)) {
      this.offerLinkAction(url);
      return;
    }
    // 从这里往下每一条分支都要往返一次服务器才知道该开哪一页。网络一慢，
    // 用户看不到反馈就会再点，同一个群于是被开出好几层。闸门放行一次、
    // 挡住其余，并把这个 url 广播出去让那段文字自己表现成加载中。
    if (!beginLinkNav(url)) {
      return;
    }
    if (this.openKnownTelegramLink(url)) {
      return;
    }
    this.resolveMessageLink(url);
  }

  private handleLocalLinkAction(action: LinkAction): boolean {
    if (action.kind === LINK_NONE) {
      return true;
    }
    if (action.kind === LINK_COMMAND) {
      this.sendBotCommand(action.text);
      return true;
    }
    if (action.kind === LINK_COPY) {
      copyPlainText(action.text, str('cp_number_copied'));
      return true;
    }
    if (action.kind === LINK_HASHTAG) {
      const params: Record<string, Object> = { 'query': action.text };
      navigateToSearch(params);
      return true;
    }
    if (action.kind === LINK_USER) {
      const params: Record<string, Object> = { 'userId': action.userId };
      // 曾经是 router.pushUrl('pages/profile/ProfilePage')——ProfilePage 迁成
      // NavDestination 并从 main_pages.json 摘出后整页路由跳不动，走漏斗。
      navigateToProfile(params);
      return true;
    }
    return false;
  }

  private openKnownTelegramLink(url: string): boolean {
    const folderInvite = chatFolderInviteLinkOf(url);
    if (folderInvite !== '') {
      openChatFolderInviteLink(folderInvite);
      return true;
    }
    const stickerSet = stickerSetLinkOf(url);
    if (stickerSet !== null) {
      openStickerSetLink(stickerSet);
      return true;
    }
    // Private invite link: preview → confirm → join in-app.
    const invite = inviteLinkOf(url);
    if (invite !== '') {
      openInviteLink(getContext(this) as common.UIAbilityContext, invite, url);
      return true;
    }
    const linkAction = chatLinkActionOf(url);
    if (linkAction !== null) {
      openChatLinkAction(getContext(this) as common.UIAbilityContext, linkAction, url, true);
      return true;
    }
    const bareName = bareUsernameOf(url);
    if (bareName !== '') {
      openTelegramLink(getContext(this) as common.UIAbilityContext, url, true);
      return true;
    }
    return false;
  }

  private resolveMessageLink(url: string): void {
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
          this.jumpToLinkedMessageInThisChat(msgId);
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

  private jumpToLinkedMessageInThisChat(messageId: number): void {
    this.prepareUserJump();
    const gidx = groupIndexOf(this.groups, messageId);
    if (gidx >= 0) {
      this.scroller.scrollToIndex(gidx, false, ScrollAlign.START);
      this.flash.flashAtIndex(gidx, messageId);
    } else {
      this.pendingJumpId = messageId;
      if (this.store !== null) {
        const targetId: number = messageId;
        this.store.loadAround(targetId, (found: boolean): void => {
          if (!found && this.pendingJumpId === targetId) {
            this.pendingJumpId = 0;
            promptAction.showToast({ message: $r('app.string.cp_cannot_locate'), duration: 1500 });
          }
        });
      }
    }
  }


  // Reply-quote tap: jump to the quoted original message (same in-place scroll
  // as a same-chat link jump).
  // --- in-chat search ---
  // 整簇状态机（enterSearch/exitSearch/updateSearchQuery/runSearch/
  // jumpToResult/applySearchStep/searchOlder/searchNewer）搬进了
  // SearchSession（B6 批）；调用方改走 this.search.enter()/exit()/
  // updateQuery()/run()/older()/newer()。SearchSession.jumpToMessage host
  // 回调仍是 this.onReplyTap，与搬之前同一条跳转路径。

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
      this.flash.flashAtIndex(gidx, messageId);
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

  // flashAtIndex/syncFlashRect/runBlink/cancelFlash 四个方法整簇搬进了
  // JumpFlashState（B13 批），原有注释随方法一并搬进 JumpFlashState.ets，此处
  // 不再重复。调用方改走 this.flash.flashAtIndex()/this.flash.cancelFlash()/
  // this.flash.syncFlashRect()；runBlink 是纯内部递归，无外部调用点，留在
  // JumpFlashState 内部，页面不再持有同名方法。

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
    if (!mediaEntryIsPhoto(m) && !mediaEntryIsVideo(m)) {
      return;
    }
    if (mediaEntryIsPhoto(m)) {
      this.store.requestFullPhoto(messageId);
    }
    // 交接:取气泡播放位记录的进度，必须在 playSlots.suspend() 让气泡播放器
    // 卸载之前完成——bubblePositionMs 本身不受 suspend() 影响，但卸载之后
    // 气泡播放器不会再有新的 onPositionChanged，读早读晚不影响这一次的值；
    // 保险起见仍然按“先取、后卸载”的顺序写。
    this.viewerStartPositionMs = this.playSlot.handoffToViewer(messageId);
    // Position the viewer Swiper on the tapped album member.
    const sib = albumSiblingIds(this.groups, messageId);
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
  // 见 appDark 的说明：store 注入的 isDarkMode 回调是实时读的，

  // 所以这里只要让它重新解析一次就够，不必重新订阅。

  // 本机自选壁纸换了图：纯本地改动没有 TDLib update 推回来，靠这个代次通知。
  @Monitor('localBgEpoch')
  private onLocalWallpaperChanged(): void {
    if (this.bgStore !== null) {
      this.bgStore.refresh();
    }
  }

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
      // 客户端超时不等于操作失败（issue #178）：按钮已经送到机器人那边，机器人
      // 多半也已经把消息编辑好了——频道搜索里翻页/换链接就是这么生效的——只是
      // answerCallbackQuery 的回执没在 15s 内回来。这时弹「操作失败，请重试」
      // 既是假的，又引诱用户再按一次，那才会真的翻两页。判据见 util/tdRequestTimeout。
      if (requestOutcomeUncertain(e.message)) {
        return;
      }
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

  // Refresh the '@' mention / '/' command suggestion panels for the new draft.
  private updateSuggestions(v: string): void {
    this.command.closeMenu();
    const cmd = v.match(/^\/([a-zA-Z0-9_]*)(?:@([a-zA-Z0-9_]*))?$/);
    if (cmd !== null) {
      this.mention.clear();
      this.command.refreshCommands();
      return;
    }
    this.command.clearItems();
    // 判定在 util/mentionDraft（mentionQueryOf，9 条测）：那里说明了为什么放宽
    // 到非 ASCII，以及 @ 的位置和终止条件各自挡的是什么（issue #95）。
    const at: string | null = mentionQueryOf(v);
    if (at !== null && this.isGroup && !this.isChannel) {
      this.mention.refreshMentions(at);
      return;
    }
    this.mention.clear();
    this.inline.refreshInlineQuery(v);
    this.sticker.refreshStickerSuggestions(v);
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

  // B8 issue（未在四条"不能碰"里，也不在 HeaderIdentitySession 的 15 个迁移
  // 方法之列，需要复核）：openBotMiniApp 原来直接读页面的 headerPeerUserId——
  // 迁移后那是控制器内部的 private peerUserId，没有任何 host getter 或公开
  // 方法能取到它。这里改用 this.store?.getPeerUserId()，和 openProfile 迁移前
  // 就已经在用的同一个回退取值一致：MessageStore 对 chatTypePrivate 的
  // peerUserId 解析读的是同一个 getChat 响应的 type.user_id，值恒等；唯一的
  // 差异是两次 getChat 各自独立发出，理论上存在极短的时间窗——
  // header.botMiniAppUrl 已经落地但 store.getPeerUserId() 还没跟上——这个窗口
  // 里点开 Mini App 入口会被这里的 `<= 0` 挡住，原实现不会。这是行为改变，
  // 需要确认是否可接受，或者要不要把 openBotMiniApp 也一并搬进控制器。
  private openBotMiniApp(): void {
    const url = this.header.botMiniAppUrl;
    const uid = this.header.currentPeerUserId();
    if (url === '' || uid <= 0) { return; }
    openMiniApp(this.chatId, uid, url).then((resolved: string): void => {
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

  // pickInlineResult（涉及 sendInlineResult 与 composer.clearReply，方案点名
  // 留页面）：refreshInlineQuery/downloadInlineThumb 整簇搬进了
  // InlineQueryState（B14 批），this.inlineQueryId 换成只读取值器
  // this.inline.queryId()，两处清空换成 this.inline.clear()（原样两行
  // `this.inlineResults = []; this.inlineQueryId = '';`，见该方法注释）。
  private pickInlineResult(row: InlineResultRow): void {
    if (this.inline.queryId() === '') { return; }
    const replyId = this.composer.replyToId;
    sendInlineResult(this.chatId, this.inline.queryId(), row.resultId, replyId).then((): void => {
      this.draft = '';
      this.inline.clear();
      this.composer.clearReply();
      this.atBottom = true;
    }).catch((e: TdError): void => {
      logE(`ChatPage.sendInlineResult failed: ${e.message}`);
      promptAction.showToast({ message: $r('app.string.cp_inline_send_failed'), duration: 1600 });
    });
  }

  // sendSuggestedSticker（调用 this.store?.sendSticker(...)，方案点名留
  // 页面）：refreshStickerSuggestions/downloadSuggestionThumb 整簇搬进了
  // StickerSuggestionState（B14 批）。原样两行
  // `this.stickerSuggestions = []; this.stickerSuggestSeq++;` 换成
  // this.sticker.clearAfterSend()——两个字段现在都是私有的，打包成这一个方法。
  private sendSuggestedSticker(fileId: number): void {
    this.store?.sendSticker(fileId, 512, 512);
    rememberRecentSticker(fileId);
    this.draft = '';
    this.sticker.clearAfterSend();
  }

  // refreshCommands/ensureCommandsLoaded/commandPanelActive/applyCommandFilter
  // 整簇搬进了 CommandSuggestionState（B14 批），调用点改经 this.command，
  // 本页不再重复方法体。

  // Replace the trailing '@token' with the chosen member.
  //
  // refreshMentions/rememberNameMention 整簇搬进了 MentionSuggestionState
  // （B14 批）。pickMention 原来直接写 this.draft 并在 0ms 之后
  // focusControl.requestFocus('chat_composer')。控制器不碰宿主字段，因此
  // 改成返回新草稿串，这里赋 this.draft 并补回原来紧跟着的那一行 setTimeout，
  // 顺序与原来一致（方案 249 行"pick 类方法返回新草稿字符串由页面写
  // this.draft"）。
  private pickMention(item: MentionItem): void {
    this.draft = this.mention.pickMention(item);
    setTimeout((): void => { focusControl.requestFocus('chat_composer'); }, 0);
  }

  // Long press on a group message avatar → append that sender's mention to the
  // draft. The message entry has the sender's name but not their username, so
  // the username is fetched here; the name is the fallback if it has none.
  //
  // 本方法内部是异步回调，没法像 pickMention 那样直接返回新草稿串给一个早已
  // return 过的调用点，因此整个方法体搬进了 MentionSuggestionState（B14
  // 批），经 aboutToAppear 里注入的 host.applyDraft 回调在异步回调触发的当下
  // 写 this.draft 并补上那一行 setTimeout（效果与原方法两行紧挨着执行一致，
  // 见 bind() 处注释）。这里保留一个同名同签名的转发方法，是因为调用点在
  // messageActions() 那个单例闭包（不变量#1保护，禁止改动结构）里，转发法
  // 让闭包体内那一行 `this.mentionSender(userId, name)` 一个字都不用改。
  private mentionSender(userId: number, fallbackName: string): void {
    this.mention.mentionSender(userId, fallbackName);
  }

  private pickCommand(item: CommandItem): void {
    this.draft = commandLabel(item);
    this.command.closePanel();
    this.doSend();
  }

  // B15 批注：saveMediaTo/saveViewerMedia/processAutomaticGallerySave/
  // openDownloadedFile/onFileTap 五个方法整体搬进了 MediaSaveState（连同
  // saveViewerMedia 上方那两段原有注释，逐字带走）。saveViewerMedia/onFileTap
  // 的调用点分别改经 `this.mediaSave.saveViewerMedia(...)`/
  // `this.mediaSave.onFileTap(...)`。

  // 联系人卡片 / 拨号 / 打开位置三个动作共用的防连点闸。判据（含「一把闸不是
  // 三把」的理由）在 util/utilityActionGuard.ets，由
  // entry/src/test/UtilityActionGuard.test.ets 钉住；这里只保留时间戳字段和
  // 「判定通过才刷新」的写入顺序——拒绝时不刷新，连点不会把闸无限续期。
  private utilityActionAllowed(): boolean {
    const now: number = Date.now();
    if (!utilityActionAllowedAt(this.utilityActionAtMs, now)) {
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
    const normalized: string = normalizePhoneForDial(phone);
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
    // 拼串在 util/locationActions.sharedLocationUris。空 geoUri = 「坐标无效且
    // 标签也是空的」，原实现在这一步直接弹「无位置信息」并 return，判断顺序
    // （防连点闸 → 空判 → 拉起）不变。
    const uris: SharedLocationUris = sharedLocationUris(latitude, longitude, label, valid);
    if (uris.geoUri === '') {
      promptAction.showToast({ message: $r('app.string.cp_no_location'), duration: 1500 });
      return;
    }
    openUrl(getContext(this) as common.UIAbilityContext, uris.geoUri, (): void => {
      openUrl(getContext(this) as common.UIAbilityContext, uris.webFallback, (): void => {
        promptAction.showToast({ message: $r('app.string.cp_no_map_app'), duration: 1700 });
      });
    });
  }

  // B15 批注：onFileSave 方法体（连同上方原有的 "Document card save arrow"
  // 注释，逐字带走）整体搬进了 MediaSaveState。调用点改经
  // `this.mediaSave.onFileSave(...)`。

  // --- header "more" menu actions ---
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
      message: str('cp_leave_confirm', this.header.title),
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

  private openHeaderMenu(): void {
    if (this.chatId === 0 || this.headerMenuController.isOpen()) {
      return;
    }
    const params: ChatHeaderMenuParams = {
      chatId: this.chatId,
      // 面板与切换由 ChatHeaderMenuController 自己接管（见那边的 swapPanel）。
      panel: PANEL_MAIN,
      onOpenFolders: (): void => {},
      onBackToMain: (): void => {},
      isMuted: this.header.isMuted,
      muteUpdating: this.header.muteUpdating,
      isGroup: this.isGroup,
      isChannel: this.isChannel,
      liveLocationActive: this.liveLocationActive,
      translationActive: this.translation.active(this.translateChatsEnabled),
      canClearHistory: this.clearHistoryChoice() !== undefined,
      canLeaveChat: this.isGroup && this.membershipState === 'writable',
      onSearch: (): void => { this.search.enter(); },
      onToggleMute: (): void => { this.header.toggleMute(); },
      onAddToFolder: (): void => { showChatFolderPicker(this.getUIContext(), this.chatId); },
      onAutoDelete: (): void => { this.chooseAutoDelete(); },
      onJumpToDate: (): void => { this.pickJumpDate(); },
      onStopLocation: (): void => { confirmStopLiveLocation(); },
      onToggleTranslation: (): void => { this.translation.toggleTranslatable(this.translateChatsEnabled); },
      onClearHistory: (): void => { this.confirmClearHistory(); },
      onLeaveChat: (): void => { this.confirmLeaveChat(); }
    };
    this.headerMenuController.open(this.getUIContext(), this.headerMenuId, this.topBannerHeight(), params,
      (visible: boolean): void => { this.headerMenuShow = visible; });
  }

  private closeHeaderMenu(): void {
    this.headerMenuController.close();
  }

  // 这里原来有三个只写不读的字段（emojiBtnCx / inputBarH / listViewportH），
  // 连同喂它们的三条 @Event 链一起删了（第二轮第 11 项）。判据不是 grep 命中数：
  // listViewportH 是有一处“读”的，但那处只是 `Math.abs(h - this.listViewportH)
  // > 0.5` 给它自己的写做去抖，值没有任何第三方消费者——按命中数会误判成
  // “有读点不能删”。
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

  private chromeGeometryInput(): ChatChromeGeometryInput {
    return {
      topSafe: this.topSafe,
      searchMode: this.search.mode,
      pinnedVisible: this.topCard.pinnedPreview !== '',
      liveVisible: this.topCard.liveGroupCallId > 0 && this.topCard.liveCallIsActive,
      loadingVisible: this.topCard.topCardLoadingVisible
    };
  }

  // 顶栏高度只由结构状态决定。标题、副标题、头像加载状态的变化不再经过
  // onAreaChange 写回状态变量，也就不会把 List.contentStartOffset 一起拖进重排。
  private headerChromeHeight(): number {
    return chatChromeHeight(this.chromeGeometryInput());
  }

  private topBannerHeight(): number {
    return chatTopBannerHeight(this.chromeGeometryInput());
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
    const oneLine: number = COMPOSER_LINE_HEIGHT + COMPOSER_EDITOR_PADDING * 2;
    const cap: number = COMPOSER_LINE_HEIGHT * COMPOSER_MAX_LINES + COMPOSER_EDITOR_PADDING * 2;
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
        lineHeight: COMPOSER_LINE_HEIGHT,
        // 左右各 3 的内边距要从可用宽度里扣掉，否则会少算一行。
        constraintWidth: Math.max(1, this.composerEditorW - 6)
      });
      // measureTextSize 返回的是 px。
      measured = px2vp(size.height as number) + COMPOSER_EDITOR_PADDING * 2;
    } catch (e) {
      // 量不出来就退回一行，宁可矮也不要抖：TextArea 超出部分自己能滚。
      logE(`composerEditorHeight measure failed: ${(e as Error).message}`);
    }
    return Math.max(oneLine, Math.min(cap, Math.ceil(measured)));
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
    this.mention.clear();
    this.command.closePanel();
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

  // finishStickerSend 整体搬进了 ChatOverlayState（B11 批），改名为
  // flyStickerGhost（任务书指定新名，方法体逐字未改）；setEmojiPanel/
  // chatEffectDuration 经 host 转发。调用点改为
  // this.overlayState.flyStickerGhost(path, x, y)。

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
    if (this.command.commandMenuOpen) {
      this.command.closePanel();
    } else {
      this.mention.clear();
      this.setEmojiPanel(false);
      this.applyBottomSlot(closeSlot(this.bottomSlot, SLOT_REPLY_KB));
      this.command.commandMenuOpen = true;
      this.command.ensureCommandsLoaded();
      this.command.applyCommandFilter();
    }
  }

  private insertEmoji(e: string): void {
    this.draft = `${this.draft}${e}`;
    this.updateSuggestions(this.draft);
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

  // B15 批注：startRecording/stopRecordTimer/finishRecording/
  // cancelRecording/formatRecSeconds 五个方法（连同上方原有的
  // "--- voice recording (mic button) ---" 分节注释，逐字带走）整体搬进了
  // VoiceRecordingState，按方案改名为 start/stopTimer/finish/cancel/
  // secondsLabel。调用点改经 `this.recording.start()`/`.finish()`/
  // `.cancel()`；`this.formatRecSeconds()` 原来的唯一调用点（composerDock()
  // 传 recordingSecondsLabel）随三个标量 @Param 一并被 ChatComposerInput 侧
  // 改成整个 `recording: this.recording` 控制器引用，组件自己内部调
  // `this.recording.secondsLabel()`，页面不再需要转手这一步。

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
            .onClick((): void => { this.attach.sendDiceEmoji(d.emoji); });
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
    // 搬运在 util/pendingMedia：这里曾经是个 `{ path, isVideo }` 字面量，
    // 把实况导出时算好的封面与旋转后宽高在发送前丢了个干净。
    const items: MediaSendItem[] = toMediaSendItems(this.pendingMedia);
    const captionSnapshot: string = this.draft;
    const caption: string = captionSnapshot.trim();
    const replyId: number = this.composer.replyToId;
    this.command.closeMenu();
    this.atBottom = true;
    this.stayAtUnread = false;
    this.withSendLock((): Promise<void> => store.sendMedia(items, caption, replyId).then((): void => {
      this.pendingMedia = clearPendingMedia();
      if (this.draft === captionSnapshot) {
        this.draft = '';
        this.mention.clearPendingNameMentions();
      }
      if (this.composer.replyToId === replyId) {
        this.composer.clearReply();
      }
    }).catch((e: TdError): void => {
      logE(`ChatPage.sendMedia failed: ${e.message}`);
      promptAction.showToast({ message: $r('app.string.cp_photo_send_failed'), duration: 2000 });
    }));
  }

  private doSend(): void {
    if (this.composer.editingId !== 0) {
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
    const replyId: number = this.composer.replyToId;
    const mentionsSnapshot: NameMention[] = this.mention.readPendingNameMentions();
    this.command.closeMenu();
    this.atBottom = true;
    this.stayAtUnread = false;
    // 按名字提及的实体在这里生成：偏移必须相对**实际发出去的那串文本**，
    // 所以用 trim 之后的 text，不是原始草稿。
    const entities: TdObject[] = buildMentionEntities(text, this.mention.readPendingNameMentions());
    // 清空放在**发送之前**，不等应答。消息本身不用我们伪造回显：TDLib 会先
    // 发 updateNewMessage（自己发的消息在 onNewMessage 里是放行的），列表那边
    // 立刻就有一条 pending 的气泡。
    this.draft = '';
    this.mention.clearPendingNameMentions();
    if (this.composer.replyToId === replyId) {
      this.composer.clearReply();
    }
    this.mention.clear();
    this.command.clearItems();
    store.sendAsync(text, replyId, entities).catch((e: TdError): void => {
      logE(`ChatPage.doSend failed: ${e.message}`);
      // 提示语说的是"草稿已保留"，那就真的还回去。但用户可能已经开始写下
      // 一条了——那种情况不覆盖他的输入，只报错。
      if (this.draft === '') {
        this.draft = draftSnapshot;
        this.mention.restorePendingNameMentions(mentionsSnapshot);
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
    const replyId: number = this.composer.replyToId;
    const keyboardId: number = this.replyKeyboard !== null ? this.replyKeyboard.messageId : 0;
    const oneTime: boolean = this.replyKeyboard !== null && this.replyKeyboard.oneTime;
    this.replyKeyboardSendingKey = key;
    this.atBottom = true;
    this.stayAtUnread = false;
    store.sendAsync(btn.text, replyId).then((): void => {
      this.replyKeyboardSendingKey = '';
      if (this.composer.replyToId === replyId) {
        this.composer.clearReply();
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

  // applyComposerMode（composerMode 九字段唯一写入口）/clearReply/
  // replySnippet/startReply 整套搬进了 ComposerSession（B9 批）：调用点改
  // this.composer.apply(...)/this.composer.clearReply()/
  // this.composer.startReply(messageId)。

  // --- multi-select ---
  // 整簇状态机（enterSelect/animateSelection/exitSelect/clearSelectionState/
  // rowSelected/toggleSelectRow）搬进了 SelectionSession（B7 批）；
  // reconcileMessageActionTargets 的 selecting/selectedIds 半边一并搬走，
  // reactionSheet 半边（与多选无关）仍在这里自己清。

  private reconcileMessageActionTargets(list: MessageEntry[]): void {
    this.selection.reconcile(list);
    if (this.overlayState.showReactionSheet && this.overlayState.reactionTargetId !== 0 &&
      list.findIndex((m: MessageEntry): boolean => m.id === this.overlayState.reactionTargetId) < 0) {
      this.overlayState.closeReactionSheet();
    }
  }

  private copySelected(): void {
    const sorted = [...this.selection.ids].sort((a: number, b: number) => a - b);
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
      this.selection.exit();
    }).catch((e: Object) => { logE(`ChatPage.copySelected failed: ${JSON.stringify(e)}`); });
  }

  // "同时为对方删除"是一个开关，不是第三个按钮：做成三按钮时用户要在两个
  // 红色危险项之间辨认，容易点错。所以用带复选框的自定义弹窗。
  private deleteSelected(): void {
    const ids: number[] = [...this.selection.ids];
    if (ids.length === 0) {
      return;
    }
    this.openDeleteConfirm(ids);
  }

  // 长按菜单里的单条删除：复用 deleteSelected() 的弹窗逻辑，只是目标 id 只有一个。
  // 不处于多选模式时 doDeleteMessages 内部的 exit() 只是把已经为 false/[]
  // 的 active/ids 再赋一次同样的值，是无害的空操作。
  private deleteMessage(messageId: number): void {
    this.openDeleteConfirm([messageId]);
  }

  // 弹窗走 ComponentContent + UIContext.openCustomDialog，不再走
  // CustomDialogController：后者官方明写只在状态管理 V1 中使用，而本页要迁 V2。
  private openDeleteConfirm(ids: number[]): void {
    openDeleteMessagesDialog(this.getUIContext(),
      this.isGroup || this.isChannel ? '' : this.header.titleTextOf(),
      (revoke: boolean): void => { this.doDeleteMessages(ids, revoke); });
  }

  private doDeleteMessages(ids: number[], revoke: boolean): void {
    const req: TdRequest = { '@type': 'deleteMessages' };
    req['chat_id'] = this.chatId;
    req['message_ids'] = ids;
    req['revoke'] = revoke;
    getTdClient().send(req).then(() => {
      this.selection.exit();
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

  // 「选择文本」：把这条消息另画到一个全屏浮层上，那一层的文字可以划选。
  // 不给时间轴里的气泡开 copyOption——那会和长按菜单、左滑回复抢手势
  // （#114 那一族）。判据和渲染都在 SelectTextOverlay 里，这里只开关。
  // 把当前曲目送进全局通道。停止播放（toggleMusic 把同一条切成暂停不算停止，
  // 底栏那条仍然要在、只是按钮变成"继续"）时由 clearNowPlaying 收尾。
  private publishNowPlayingFor(messageId: number, path: string, durationSec: number): void {
    const m = this.findMsg(messageId);
    if (m === null) {
      return;
    }
    const state: NowPlaying = {
      chatId: this.chatId,
      messageId,
      title: m.audioTitle,
      performer: m.audioPerformer,
      coverPath: m.photoPath,
      path,
      durationSec
    };
    publishNowPlaying(state);
  }

  private openSelectText(messageId: number): void {
    const m = this.findMsg(messageId);
    if (m === null || (m.text === '' && m.translatedText === '')) {
      promptAction.showToast({ message: $r('app.string.cp_nothing_to_copy'), duration: 1500 });
      return;
    }
    openSelectTextOverlay(this.getUIContext(), selectTextPayload(m), this.topSafe);
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

  // allowedReactions/allowedReactionsTask 缓存字段、ensureAllowedReactions、
  // toggleReaction 整套搬进了 ChatOverlayState（B11 批）：原注释随代码一并
  // 搬走，reactionPendingKey 互斥锁的两处 ===key 比较逐字保留。调用点改为
  // this.overlayState.toggleReaction(...)。

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
      this.flash.flashAtIndex(gidx, targetId);
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

  // translationActive/driveTranslations/translateInline/
  // toggleTranslationHidden/toggleTranslatable/afterTranslationToggled 整套
  // 搬进了 TranslationDriver（B10 批）。@Monitor('translateChatsEnabled') 装饰器
  // 留在页面（类中 @Monitor 解注册依赖 GC，销毁时机不可靠；且它本来就只能监听
  // 本 struct 自己的 @Param/@Local/@Trace），方法体改一行转发，显式传
  // this.translateChatsEnabled——驱动器不缓存这个 @Param。
  @Monitor('translateChatsEnabled')
  private onTranslateSettingChanged(): void {
    this.translation.onSettingChanged(this.translateChatsEnabled);
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
    this.translation.drive(this.translateChatsEnabled, range.start, range.end);
    this.syncMediaWindow(range.start, range.end);
    // 同一个道理：数据一变（新消息到达、翻页、被查看器等场景清空候选表后
    // 恢复）就补一次播放位判定，不指望用户正好在这一刻滚动。
    this.playSlot.armSettle();
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

  // openReactionSheet 整体搬进了 ChatOverlayState（B11 批），经
  // host.findMsg 转发；调用点改为 this.overlayState.openReactionSheet(messageId)。

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
    if (this.draft.trim() === '' || this.composer.editingId !== 0) { return; }
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
      const replyId = this.composer.replyToId;
      this.store?.sendScheduledAsync(text, replyId, sendDate, silent).then((): void => {
        this.draft = '';
        this.composer.clearReply();
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

  // "正在输入…" 提示的状态与轮询定时器整套搬进了 TypingIndicatorState
  // （B10 批）：onChatAction/rebuildTypingLabel 与 typingSenders/typingTimer/
  // typingLabel 一起住进了控制器，页面只在 subscribeChatLevelUpdates() 里转发
  // updateChatAction 给 this.typing.onChatAction(u)，composerPlaceholder 改读
  // this.typing.label（详见 TypingIndicatorState.ets）。

  // Pick up the draft synced from other devices (chat.draft_message). Only
  // fills an empty composer — never overwrites what the user is typing.
  private restoreServerDraft(): void {
    const req: TdRequest = { '@type': 'getChat' };
    req['chat_id'] = this.chatId;
    getTdClient().send(req).then((chat: TdObject): void => {
      const draft = chat['draft_message'] as TdObject | undefined;
      const content = draft !== undefined
        ? (draft['input_message_text'] as TdObject | undefined) : undefined;
      const ft = content !== undefined ? (content['text'] as TdObject | undefined) : undefined;
      const text = ft !== undefined ? ((ft['text'] as string | undefined) ?? '') : '';
      // [Draft] 探针：serverLen 是服务端记的草稿长度，localLen 是此刻输入框里的。
      logW(`[Draft] restore chat=${this.chatId} serverLen=${text.length} localLen=${this.draft.length}`);
      if (this.draft !== '') { return; }
      if (text !== '') { this.draft = text; }
    }).catch((e: TdError): void => {
      logW(`[Draft] restore chat=${this.chatId} failed: ${e.message}`);
    });
  }

  // 长按菜单里的「翻译」。原来会弹一个 sheet 单独展示译文，现在改成就地
  // 翻译：进行中/失败/译文都长在气泡里（见 translationChannel 与
  // MessageBubble.translationBlock），和整聊天翻译是同一条路径、同一套缓存。
  // 那张 sheet（TranslateSheet + translateSheet* 状态 + runSheetTranslation 一族）
  // 已在 B1 连同 pages/chat/TranslateSheet.ets 一并删除：它的开关 translateSheetOpen
  // 全仓零处赋 true，是打不开的孤儿状态机。这里是「翻译」现在唯一的活入口。
  private translateMessage(messageId: number): void {
    const entry: MessageEntry | undefined =
      this.messages.find((m: MessageEntry): boolean => m.id === messageId);
    if (entry === undefined || entry.text.trim() === '') {
      promptAction.showToast({ message: $r('app.string.cp_nothing_to_translate'), duration: 1600 });
      return;
    }
    this.translation.translateInline(messageId);
  }

  // showReactors、closeReactionSheet 整体搬进了 ChatOverlayState（B11 批），
  // 经 host.chatId 转发；调用点分别改为 this.overlayState.showReactors(...)、
  // this.overlayState.closeReactionSheet()。

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

  // 「查看历史」：在本会话里筛出这个人的全部消息，复用会话内搜索的整套界面
  // （结果计数、上/下一条、跳转高亮）。搬进了 SearchSession.enterForSender()
  // （B6 批）；长按菜单的 onViewSenderHistory 直接调 this.search.
  // enterForSender(senderId)。

  private openForwardPicker(ids: number[]): void {
    const validIds: number[] = this.forwardableMessageIds(ids);
    ContextMenu.close();
    if (validIds.length === 0) {
      promptAction.showToast({ message: $r('app.string.cp_cannot_forward'), duration: 1500 });
      return;
    }
    // 尾段（closeReactionSheet/setEmojiPanel(false)/写 forwardMessageIds+
    // showForwardSheet）搬进了 this.overlayState.openForwardPicker()（B11 批）；
    // 前面的过滤与空列表提前返回依赖页面的 this.messages/this.findMsg，留在
    // 这里。
    this.overlayState.openForwardPicker(validIds);
  }

  // closeForwardSheet 整体搬进了 ChatOverlayState（B11 批）；调用点改为
  // this.overlayState.closeForwardSheet()。

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

  // Search owns the complete top bar. Keeping the regular avatar/title beside
  // the field squeezed group/channel queries into a narrow trailing slot and
  // made the mode look like an accessory instead of navigation state.
  // Suggestion panel above the input bar: group members for a trailing '@',
  // bot commands for a leading '/'.
  // startEdit/cancelEdit 整套搬进了 ComposerSession（B9 批）：调用点改
  // this.composer.startEdit(messageId)/this.composer.cancelEdit()。
  //
  // commitEdit 依赖 withSendLock/store（页面留存的发送闸门与 TDLib 客户端），
  // 按所有权裁决整个留页面；只经 composer.editingId/editingKind 两个 @Trace
  // 直读，成功回调里改调 this.composer.apply(cancelEdit(this.composer.mode))
  // 走回 ComposerSession 唯一写入口。
  private commitEdit(): void {
    const store = this.store;
    const editId = this.composer.editingId;
    const text = this.draft.trim();
    // Captions may be cleared (empty); message text may not.
    if (store === null || editId === 0 || this.composerSending ||
      (text === '' && this.composer.editingKind === 'text')) {
      return;
    }
    const editKind: string = this.composer.editingKind;
    this.withSendLock((): Promise<void> => (editKind === 'caption'
      ? store.editCaptionAsync(editId, text) : store.editTextAsync(editId, text)
    ).then((): void => {
      if (this.composer.editingId === editId) {
        const restored: string = draftToRestore(this.composer.mode);
        this.composer.apply(cancelEdit(this.composer.mode));
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
    return placeholderOf(this.typing.label, this.replyKbVisible(),
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
      onPick: (key: string): void => { this.attach.runAttachAction(key); },
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
            this.overlayState.flyStickerGhost('', 0, 0);
          }
        },
        onPickSticker: (s: StickerItem, x: number, y: number): void => {
          if (this.store !== null) {
            this.atBottom = true;
            this.store.sendSticker(s.fileId, s.width, s.height);
            this.overlayState.flyStickerGhost(s.thumbPath, x, y);
          }
        },
        onPickGif: (g: GifItem): void => {
          if (this.store !== null) {
            this.atBottom = true;
            this.store.sendAnimation(g.fileId, g.width, g.height, g.duration);
            this.overlayState.flyStickerGhost('', 0, 0);
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
      BottomDrawerShell({
        bottomSafe: this.bottomSafe,
        drawerHeight: EMOJI_DRAWER_HEIGHT,
        content: this.emojiDrawerContent
      });
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
  bottomDock() {
    Column() {
      if (this.selection.active) {
        // Selection owns the header actions; removing the composer also drops
        // its reserved list inset so messages expand naturally into the space.
        Column().width('100%').height(0);
      } else if (this.search.mode) {
        this.searchDock();
      } else if (this.composerSlot() !== 'writable') {
        this.membershipDock();
      } else {
        this.composerDock();
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

  // 搜索态底栏：结果计数 + 上一条/下一条导航。
  @Builder
  private searchDock() {
    SearchBottomBar({
      search: this.search,
      bottomGap: this.composerBottomGap(),
      onOlder: (): void => { this.search.older(); },
      onNewer: (): void => { this.search.newer(); }
    });
  }

  // 不可写态底栏：入群 / 静音开关 / 启动 bot 的成员资格条。
  @Builder
  private membershipDock() {
    MembershipBar({
      materialEpoch: this.materialEpoch,
      state: this.composerSlot(),
      isMuted: this.header.isMuted,
      joining: this.joiningChat,
      secretOutbound: this.header.secretOutbound,
      bottomGap: this.composerBottomGap(),
      onJoin: (): void => { this.joinCurrentChat(); },
      onToggleMute: (): void => { this.header.toggleMute(); },
      onStartBot: (): void => { this.sendBotCommand(BOT_START_COMMAND); }
    });
  }

  // 可写态底栏：输入框 + 回复键盘 + 抽屉。ChatComposerInput 只在这一支出现
  // 一次，换态时不会跨分支重建、不丢焦点。
  @Builder
  private composerDock() {
    Column() {
      ChatComposerInput({
        attachPanelOpen: this.attachPanelOpen,
        pendingMedia: this.pendingMedia,
        // 控制器整个交过去，不再逐个转手八个标量（B9b）：在这里读
        // this.composer.editingId 之类的 @Trace，建立的是**页面**对它们的依赖，
        // 编辑/回复一开一关就重跑整页 build。this.composer 是普通私有字段、
        // 引用恒定，读它不建立任何依赖，八个 @Trace 的读点全在
        // ChatComposerInput 自己的 build 里。
        composer: this.composer,
        // botMenuAvailable/commandMenuOpen 原来是两个标量 @Param，随 B14
        // 搬进了 CommandSuggestionState 的持有者也一并改成整个控制器引用交过去
        // （与上面 composer 那次改造同一模式）：ChatComposerInput 侧改名接收
        // 为 commandSuggestion。
        commandSuggestion: this.command,
        // isRecording/recordingStarting/recordingSecondsLabel 原来是三个标量
        // @Param，由页面逐个转手（B15 之前，见侦察报告 3）；现在整个控制器
        // 交过去，理由与上面 composer/commandSuggestion 两次改造同一模式。
        recording: this.recording,
        showEmojiPanel: this.showEmojiPanel,
        composerEditorReady: this.composerEditorReady,
        draft: this.draft,
        composerPlaceholder: this.composerPlaceholder(),
        composerController: this.composerController,
        composerEditorHeight: this.composerEditorHeight(),
        sendByEnter: this.sendByEnter,
        replyKeyboard: this.replyKeyboard,
        replyKbCollapsed: this.replyKbCollapsed,
        botMiniAppUrlValue: this.header.botMiniAppUrl,
        composerSending: this.composerSending,
        replyKeyboardVisible: this.replyKbVisible(),
        bottomGap: this.composerBottomGap(),
        hasDraft: pendingMediaCanSend(this.pendingMedia, this.draft),
        accentColor: this.accent(),
        chromeIconColor: this.chromeIcon(),
        onToggleAttach: (): void => { this.toggleAttachPanel(); },
        onRemoveMedia: (index: number): void => {
          this.pendingMedia = removePendingMedia(this.pendingMedia, index);
        },
        onMoveMedia: (from: number, to: number): void => {
          this.pendingMedia = movePendingMedia(this.pendingMedia, from, to);
        },
        onClearMedia: (): void => { this.pendingMedia = clearPendingMedia(); },
        onCancelEdit: (): void => { this.composer.cancelEdit(); },
        onReplyTap: (messageId: number): void => { this.onReplyTap(messageId); },
        onClearReply: (): void => { this.composer.clearReply(); },
        onCancelRecording: (): void => { this.recording.cancel(); },
        onFinishRecording: (): void => { this.recording.finish(); },
        onToggleBotMenu: (): void => { this.toggleBotMenu(); },
        onEmojiButtonTap: (): void => {
          this.setEmojiPanel(!this.showEmojiPanel);
          this.mention.clear();
          this.command.closePanel();
        },
        onEditorWidthChange: (width: number): void => {
          if (Math.abs(width - this.composerEditorW) > 0.5) {
            this.composerEditorW = width;
          }
        },
        onDraftChange: (value: string): void => {
          this.draft = value;
          this.updateSuggestions(value);
          if (value.trim() !== '' && this.composer.editingId === 0) {
            this.store?.notifyTyping();
          }
        },
        onSubmit: (): void => {
          if (this.sendByEnter) {
            this.doSend();
          }
        },
        onEditorFocus: (): void => {
          this.imeTailPinned = this.atBottom && this.viewerMsgId === 0 &&
            !this.stayAtUnread;
          this.composerFocused = true;
          holdPlayerJobs(KEYBOARD_SETTLE_MS);
          this.setEmojiPanel(false);
          this.applyBottomSlot(closeAllSlots());
          this.command.closeMenu();
          if (this.keyboardH > 0) {
            this.syncTailOnImeFrame();
          }
        },
        onEditorBlur: (): void => { this.composerFocused = false; },
        onActivateEditor: (): void => { this.activateComposerEditor(); },
        onScheduleEditorMount: (): void => { this.scheduleComposerEditorMount(); },
        onToggleReplyKeyboard: (): void => { this.toggleReplyKeyboard(); },
        onOpenMiniApp: (): void => { this.openBotMiniApp(); },
        onRecord: (): void => { this.recording.start(); },
        onSend: (): void => { this.doSend(); },
        onSendOptions: (): void => { this.showSendOptions(); },
        menuEffectDuration: (duration: number): number =>
          this.chatEffectDuration(KEY_POWER_EFFECT_MENU, duration),
        replyEffectDuration: (duration: number): number =>
          this.chatEffectDuration(KEY_POWER_EFFECT_REPLY, duration),
        smoothEffectDuration: (duration: number): number =>
          powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, duration)
      });
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

  // pendingScrollBottom 是"点了 ↓，等页回来就贴底"这个意图。它在往返期间被谁
  // 清掉过，是判"点一次丢一次"的关键，所以每一次清除都记来源。
  // 只在意图确实挂着时才打，日常复位不刷屏。
  private clearPendingScrollBottom(source: string): void {
    if (!this.pendingScrollBottom) {
      return;
    }
    this.pendingScrollBottom = false;
    logW(`[JumpLatest] #${this.jumpLatestSeq} pendingBottom cleared by=${source}`);
  }

  private scrollToLatest(): void {
    if (this.store === null || this.scrollToBottomBusy) {
      logW(`[JumpLatest] #${this.jumpLatestSeq} abort reason=` +
        `${this.store === null ? 'storeNull' : 'busy'} ${this.scrollStateProbe()}`);
      return;
    }
    this.prepareUserJump();
    // Far from the live tail — unloaded pages below, OR a long stretch of
    // already-loaded history (scrollToIndex over thousands of lazy rows still
    // lays them out one by one and visibly crawls): atomically replace the
    // window with the newest page.
    const farFromEnd: boolean = this.groups.length - this.curStartIdx > JUMP_RELOAD_THRESHOLD;
    const probeSeq: number = this.jumpLatestSeq;
    if (this.store.getHasMoreNewer() || farFromEnd) {
      const actionSeq: number = ++this.scrollActionSeq;
      this.scrollToBottomBusy = true;
      this.pendingScrollBottom = true;
      logW(`[JumpLatest] #${probeSeq} path=reload farFromEnd=${farFromEnd}` +
        ` actionSeq=${actionSeq} ${this.scrollStateProbe()}`);
      this.store.jumpToLatest((success: boolean): void => {
        if (actionSeq !== this.scrollActionSeq) {
          // 早退：这次点击的意图已经被更强的定位动作作废。不打这一行的话，
          // scrollToBottomBusy 卡住导致后续点击全被吞掉就查不出来。
          logW(`[JumpLatest] #${probeSeq} reload stale actionSeq=${actionSeq}` +
            ` cur=${this.scrollActionSeq} busyStuck=${this.scrollToBottomBusy}`);
          return;
        }
        this.scrollToBottomBusy = false;
        logW(`[JumpLatest] #${probeSeq} reload done success=${success}` +
          ` ${this.scrollStateProbe()}`);
        if (!success) {
          this.clearPendingScrollBottom('reloadFailed');
          this.atBottom = false;
          promptAction.showToast({ message: $r('app.string.cp_latest_failed'), duration: 1600 });
        } else if (this.groups.length === 0) {
          this.clearPendingScrollBottom('emptyGroups');
          this.atBottom = true;
        }
      }, probeSeq);
      return;
    }
    // Close to the end and fully loaded — snap instantly, no animated crawl.
    const actionSeq: number = ++this.scrollActionSeq;
    const snapIndex: number = Math.max(0, this.groups.length - 1);
    logW(`[JumpLatest] #${probeSeq} path=snap call=scrollToIndex index=${snapIndex}` +
      ` actionSeq=${actionSeq} ${this.scrollStateProbe()}`);
    this.scroller.scrollToIndex(snapIndex, false, ScrollAlign.END);
    setTimeout((): void => {
      if (actionSeq !== this.scrollActionSeq) {
        logW(`[JumpLatest] #${probeSeq} snap settle stale actionSeq=${actionSeq}` +
          ` cur=${this.scrollActionSeq}`);
        return;
      }
      this.glueBottom('L7961');
      this.refreshAtBottom();
      logW(`[JumpLatest] #${probeSeq} snap landed call=scrollEdge ${this.scrollStateProbe()}`);
    }, 60);
  }

  // masked / initialDeferred 期间持续续期，揭示之后再放行一个窗口。
  // 读的同时续期，所以每一次 build 都会把闩推到当前帧。
  private initialRowFadeArmed(rowDeferred: boolean): boolean {
    const now: number = Date.now();
    if (this.initialTimelineMasked || rowDeferred) {
      this.initialRowFadeArmedAt = now;
      return true;
    }
    return rowFadeAnimationActive(false, now, this.initialRowFadeArmedAt);
  }

  // 首屏逐条淡入的**一次性**动画。
  //
  // 原来是一条常驻的 .animation()，窗口外把 duration / delay 给 0。真机 trace
  // 说那不够：修饰器常驻，普通 rerender 照样进 JSAnimation duration:0。现在改
  // 成 transition——官方只在"组件插入/删除"和"visibility 在可见与不可见之间
  // 改变"两种情形触发它（API 参考「组件内转场 (transition)」把触发条件穷举成
  // 了这两条），普通属性更新一概不建上下文。
  //
  // 两条触发条件在这里各管一段：
  //   · 遮罩掀开 = 行的 visibility 由 Hidden 翻 Visible ⇒ 首屏那一波逐条淡入，
  //     stagger 由下面的 delay 给；
  //   · 占位行换成真行 = key 变了、节点重插 ⇒ 同一套效果，同一条路。
  //
  // 关掉时必须整个换成 IDENTITY，不能靠把 duration 给 0：否则滚动中新建的每
  // 一行都会淡入一次（官方 FAQ faqs-arkui-1136 记的就是这个现象）。
  //
  // 出场一律 IDENTITY：虚拟滚动每帧都在拆行，给出场挂效果等于把节点的销毁往后
  // 拖，那是纯粹的负收益。
  private initialRowFadeTransition(index: number, rowDeferred: boolean): TransitionEffect {
    const plan: RowFadeTransition = rowFadeTransition(
      this.chatTgsScrollActive,
      this.initialRowFadeArmed(rowDeferred),
      powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, INITIAL_TIMELINE_ROW_FADE_MS),
      this.initialTimelineRowRevealDelay(index)
    );
    if (!plan.enabled) {
      return TransitionEffect.IDENTITY;
    }
    // animation() 挂在链首：官方原话"如果通过 combine 进行 TransitionEffect
    // 的组合，前一 TransitionEffect 的动画参数也可用于后一 TransitionEffect"，
    // 所以这一份 duration / delay / curve 覆盖后面两段。视觉与摘掉的那条
    // .animation() 逐条一致：opacity 0→1、y 2→0、scale 0.99→1，EaseOut。
    return TransitionEffect.asymmetric(
      TransitionEffect.OPACITY
        .animation({ duration: plan.duration, delay: plan.delay, curve: Curve.EaseOut })
        .combine(TransitionEffect.translate({ y: 2 }))
        .combine(TransitionEffect.scale({ x: 0.99, y: 0.99 })),
      TransitionEffect.IDENTITY
    );
  }

  // stagger 的算法在 util/rowFadeGate.initialRowRevealDelay（返回裸毫秒），
  // 「动效强度」换算读 AppStorage，所以留在这里外面套一层。
  //
  // ⚠️ anchorIndex 用负数当「本次不是锚点落点」的哨兵，**不是**「groupIndexOf
  // 没找到」：命中锚点分支时才传 Math.max(0, groupIndexOf(...))（找不到就夹到
  // 0，同原实现），否则传 -1。另外选分支用的判据带着 firstUnreadId > 0 那一半，
  // 而 stagger 方向用的没有——两者在原方法里就各管各的，不要合并。
  private initialTimelineRowRevealDelay(index: number): number {
    // 只有窗口还没量出来时纯函数才会用到 anchorIndex，而 groupIndexOf 是一次
    // 线性扫描、这里每行每帧都会走一遍——所以这道 windowValid 闸必须留着，
    // 与原实现「groupIndexOf 只在 fallback 分支里跑」一致。窗口有效时传 -1，
    // 纯函数根本不看它。
    const windowValid: boolean = this.curStartIdx >= 0 && this.curEndIdx >= this.curStartIdx &&
      this.curEndIdx < this.groups.length;
    const anchored: boolean = (this.stayAtUnread && this.firstUnreadId > 0) ||
      this.resumeDividerId > 0;
    let anchorIndex: number = -1;
    if (!windowValid && anchored) {
      const startAnchorId: number = this.resumeDividerId > 0
        ? this.resumeDividerId : this.firstUnreadId;
      anchorIndex = Math.max(0, groupIndexOf(this.groups, startAnchorId));
    }
    return powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, initialRowRevealDelay(
      index, this.curStartIdx, this.curEndIdx, this.groups.length,
      anchorIndex, this.stayAtUnread || this.resumeDividerId > 0,
      INITIAL_TIMELINE_REVEAL_ROW_LIMIT, INITIAL_TIMELINE_ROW_STAGGER_MS));
  }

  // mode 由 ChatTimelineHost 传进来，**页面不再自己算**（第二轮第 12 项）。
  //
  // 原来两边各有一份逐字相同的 timelinePillMode()，但读的不是同一份数据：
  // 宿主读 @Param 进来的 timelineSnapshot（也就是用户眼前那枚 pill 的来源），
  // 页面读自己的活字段。onMessagesSnapshot 先写 olderLoadState/newerLoadState，
  // 再在 `historyState === 'loading'` 那条路上早退——**那条路不 commit 快照**。
  // 于是 pill 还显示着"加载更早失败"，而活字段已经不是 error 了；用户点重试，
  // 页面算出来三个分支一个都不进，按钮点了没反应。
  // 现在只有一个算的地方（宿主），重试永远作用在用户真正看到的那个状态上。
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

  // Repeat supplies the complete item metadata here. Keeping the row builder
  // on the page preserves the existing message-bubble/reuse and selection
  // behavior while ChatTimelineHost owns only the scrolling shell.
  @Builder
  timelineRow(ri: RepeatItem<AlbumGroup>) {
    ListItem() {
      if (ri.item.initialDeferred === true) {
        Column()
          .width('100%')
          .height(this.viewportGeometry.rowHeight(ri.item))
          .hitTestBehavior(HitTestMode.None);
      } else {
        Stack({ alignContent: Alignment.Start }) {
          // Selection mode shifts the row right into a left check gutter.
          Row() {
            if (this.selection.active && ri.item.head.contentType !== 'system' &&
              ri.item.head.contentType !== 'hidden') {
              Column() {
                if (this.selection.isRowSelected(ri.item)) {
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
            // BLOCK_DESCENDANTS keeps the outer List draggable in selection mode.
            .hitTestBehavior(this.selection.active && ri.item.head.contentType !== 'system' &&
              ri.item.head.contentType !== 'hidden'
              ? HitTestMode.BLOCK_DESCENDANTS : HitTestMode.Default);
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
          .backgroundColor(this.selection.active && this.selection.isRowSelected(ri.item)
            ? $r('app.color.select_highlight') : Color.Transparent)
          .onClick((): void => {
            if (this.selection.active) {
              this.selection.toggleRow(ri.item);
            }
          });
        }
      }
    }
    .visibility(this.initialTimelineMasked || ri.item.initialDeferred === true
      ? Visibility.Hidden : Visibility.Visible)
    .transition(this.initialRowFadeTransition(
      ri.index, ri.item.initialDeferred === true))
    .onAreaChange((_old: Area, area: Area): void => {
      this.viewportGeometry.record(
        ri.index,
        ri.item,
        area.height as number,
        ri.item.initialDeferred !== true && !this.selection.active
      );
    });
  }

  @Builder
  chatTitleBar() {
    Column() {
      if (this.selection.active) {
        SelectionHeader({
          materialEpoch: this.materialEpoch,
          selection: this.selection,
          topSafe: 0,
          onExit: (): void => { this.selection.exit(); },
          onForward: (): void => { this.openForwardPicker(this.selection.ids); },
          onCopy: (): void => { this.copySelected(); },
          onDelete: (): void => { this.deleteSelected(); }
        });
      } else if (this.search.mode) {
        SearchHeader({
          search: this.search,
          topSafe: 0,
          onExit: (): void => { this.search.exit(); },
          onQueryChange: (v: string): void => { this.search.updateQuery(v); },
          onSubmit: (): void => { this.search.run(0, 0); }
        });
      } else {
        ChatHeader({
          appearanceEpoch: this.appearanceEpoch,
          materialEpoch: this.materialEpoch,
          onLightBg: this.chromeOnLightBg(),
          appDark: this.appDark,
          // B8：上面那 12 个标量 @Param 换成一个控制器引用——ChatHeader 直接
          // 持有 header、在自己的 build()/@Builder 里读 @Trace，本页不再算
          // titleText/subtitleText 等经 @Param 转手。
          header: this.header,
          chatId: this.chatId,
          menuShow: this.headerMenuShow,
          menuAnchorId: this.headerMenuId,
          onBack: (): void => { this.goBack(); },
          onMenuTap: (): void => { this.openHeaderMenu(); },
          onOpenProfile: (): void => { this.header.openProfile(); },
          onResolveIdentity: (): void => { this.header.resolveIdentity(); }
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

  @Builder
  chatTitleBarBottom() {
    // 13 个标量 @Param 换成一个控制器引用（B5）。this.topCard 是字段初始化器
    // new 出来的，引用全生命周期不变——@Param 那层的 `!==` 永不成立，本页重建
    // 不会让浮卡整体白刷；显示态由 TopBanners 自己在 build() 里读 @Trace。
    // 千万不要在这里现场 new 任何对象传下去，那会破坏引用稳定、让子组件每帧白刷。
    TopBanners({
      materialEpoch: this.materialEpoch,
      topCard: this.topCard,
      onPinnedTap: (): void => { this.topCard.onPinnedTap(); },
      onLiveStreamTap: (): void => { this.topCard.onLiveStreamTap(); }
    });
  }

  private chatTitleBarContent(): TitleBarContentOptions {
    const content: TitleBarContentOptions = {
      stackBuilder: (): void => { this.chatTitleBar(); }
    };
    const bannerHeight: number = this.topBannerHeight();
    if (this.initialMessageTransitionSettled && this.topCard.shouldShow() && bannerHeight > 0) {
      content.bottomBuilder = {
        builder: (): void => { this.chatTitleBarBottom(); },
        height: bannerHeight
      };
    }
    return content;
  }

  @Builder
  mediaViewer() {
    MediaViewerOverlay({
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
      groups: this.timelineSnapshot.groups,
      onNeedHistory: (dir: number): void => {
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
      chatTitle: this.header.title,
      nowSec: this.nowSec,
      effectDuration: (key: string, ms: number): number => this.chatEffectDuration(key, ms),
      isVideoEntry: (entry: MessageEntry): boolean => mediaEntryIsVideo(entry),
      onRequestClose: (): void => { this.closeViewer(); },
      onSaveMedia: (): void => { this.mediaSave.saveViewerMedia(false); },
      onSaveMediaToFiles: (): void => { this.mediaSave.saveViewerMedia(true); },
      onPositionChanged: (positionMs: number): void => { this.viewerPositionMs = positionMs; }
    });
  }

  private handleTimelineTouch(e: TouchEvent): void {
    if (e.type === TouchType.Down) {
      this.finishInitialMessageStageForInteraction();
      this.imeTailPinned = false;
      this.imeLayoutSeq++;
      this.listTouchActive = true;
      this.olderArmed = true;
      this.flash.cancelFlash();
      this.closeBottomPanels();
    } else if (e.type === TouchType.Up || e.type === TouchType.Cancel) {
      this.listTouchActive = false;
    }
  }

  private handleTimelineScrollIndex(start: number, end: number): void {
    this.playSlot.armSettle();
    this.refreshAtBottom();
    this.curStartIdx = start;
    this.curEndIdx = end;
    this.indexGroupsLen = this.groups.length;
    this.fillViewportIfNeeded();
    this.curBottomId = this.bottomVisibleId(end);
    this.syncReturnState();
    this.markVisibleRead(end);
    this.topCard.updatePinnedFromScroll(start);
    const visible: PrefetchRange | null =
      clampPrefetchRange(start, end, this.groupsData.totalCount());
    if (visible !== null) {
      this.imagePrefetcher.visibleAreaChanged(visible.start, visible.end);
    }
    if (!this.chatTgsScrollActive) {
      this.translation.drive(this.translateChatsEnabled, start, end);
    }
    this.syncMediaWindow(start, end);
    if (start > 4) {
      this.olderArmed = true;
    } else {
      this.maybeLoadOlder();
    }
    if (reachedNewerPageTrigger(end, this.groups.length)) {
      this.maybeLoadNewer(end);
    }
  }

  private handleTimelineWillScroll(_offset: number, _state: ScrollState, source: ScrollSource): void {
    this.nextDidScrollIsUserDriven = source !== ScrollSource.SCROLLER &&
      source !== ScrollSource.SCROLLER_ANIMATION;
  }

  private handleTimelineDidScroll(offset: number, state: ScrollState): void {
    if (this.nextDidScrollIsUserDriven && state !== ScrollState.Idle) {
      this.userScrollOffsetTotal += offset;
    }
    this.nextDidScrollIsUserDriven = false;
    this.refreshAtBottom();
    this.flash.syncFlashRect();
    if (state === ScrollState.Scroll) {
      this.accumulateNewerDrag(offset);
    }
    if (this.listTouchActive) {
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
  }

  private handleTimelineScrollStart(): void {
    this.timelineScrollActive = true;
    setScrollActive(true);
    this.finishInitialMessageStageForInteraction();
    this.pauseChatTgsForScroll();
    this.dismissKeyboardOnUserScroll();
  }

  private handleTimelineScrollStop(): void {
    this.timelineScrollActive = false;
    this.nextDidScrollIsUserDriven = false;
    setScrollActive(false);
    // 滚动中冻结的 update 发布在这里冲刷（调度中枢批 1）。先于
    // driveVisibleWork：让本轮可见性工作拿到冲刷后的最新行。
    this.store?.flushScrollDeferredUpdate();
    this.resumeChatTgsAfterScroll();
    this.driveVisibleWork();
    this.playSlot.armSettle();
    this.capMessageReuseBuckets();
  }

  private handleTimelineAreaChange(area: Area): void {
    const y: number = area.globalPosition.y as number;
    const height: number = area.height as number;
    this.playSlot.setViewportCenter(y + height / 2);
  }

  // The flattened background, once it exists. Until then the layered version
  // below renders, so the chat never waits on the raster.
  build() {
    HdsNavDestination() {
    Stack() {
      // 整层背景搬到了 ChatBackdrop：它只吃输入不回调，所以这里只传三个入参。
      // 聊天槽位的三根滑杆由页面按当前深浅色挑好传进去——见 ChatBackdrop 里
      // 那段说明：那一层不再自己读全局键。
      ChatBackdrop({
        chatBg: this.chatBg, screenW: this.screenW, screenH: this.screenH,
        bgBlur: this.chatBgBlur, bgPattern: this.chatBgPattern, chatDim: this.chatBgDim
      });
      Column() {
        Stack() {
        ChatTimelineHost({
          timeline: this.timelineSnapshot,
          scroller: this.scroller,
          initialTimelineMasked: this.initialTimelineMasked,
          headerStartOffset: this.headerChromeHeight(),
          bottomChromeH: this.bottomChromeH,
          listCachedCount: this.listCachedCount,
          stackFromEnd: this.stackFromEndWanted(),
          threadRootId: this.threadRootId,
          membershipState: this.membershipState,
          screenW: this.screenW,
          langEpoch: this.langEpoch,
          floatDateState: this.floatDateState,
          materialEpoch: this.materialEpoch,
          flash: this.flash,
          timelineTopMargin: this.headerChromeHeight() + 8,
          timelineRow: (ri: RepeatItem<AlbumGroup>): void => { this.timelineRow(ri); },
          rowKey: (group: AlbumGroup): string => this.rowKeyOf(group),
          onTimelineReachStart: (): void => { this.maybeLoadOlder(); },
          onTimelineTouch: (e: TouchEvent): void => { this.handleTimelineTouch(e); },
          onTimelineScrollIndex: (start: number, end: number): void => { this.handleTimelineScrollIndex(start, end); },
          onTimelineWillScroll: (_offset: number, _state: ScrollState, source: ScrollSource): void => {
            this.handleTimelineWillScroll(_offset, _state, source);
          },
          onTimelineDidScroll: (offset: number, state: ScrollState): void => {
            this.handleTimelineDidScroll(offset, state);
          },
          onTimelineScrollStart: (): void => { this.handleTimelineScrollStart(); },
          onTimelineScrollStop: (): void => { this.handleTimelineScrollStop(); },
          onTimelineAreaChange: (area: Area): void => { this.handleTimelineAreaChange(area); },
          onEmptyRetry: (): void => { this.store?.retryInitialHistory(); },
          // mode 由宿主传上来——它是**用户实际看到的那枚 pill** 算出来的。
          // 页面自己重算过一版，读的是活字段而不是发布出去的快照，两者会分叉
          // （见 timelineStateRetry 上方的说明），分叉时这个按钮点了没反应。
          onTimelinePillRetry: (mode: string): void => {
            this.timelineStateRetry(mode);
          }
        });
        Column() {
          // The composer itself is interactive from the first frame. Only its
          // optional result panels stay behind the transition gate; replacing
          // the whole dock with a decorative shell made the first tap a no-op.
          if (this.initialMessageTransitionSettled) {
            if (this.membershipState === 'writable' && !this.showEmojiPanel && !this.replyKbVisible() &&
              (this.mention.mentionItems.length > 0 || this.command.commandPanelActive())) {
              SuggestionPanel({
                commandMode: this.command.commandPanelActive(),
                commands: this.command.commandItems,
                mentions: this.mention.mentionItems,
                loadState: this.command.commandLoadState,
                loadError: this.command.commandLoadError,
                catalogSize: this.command.catalogSize(),
                onPickCommand: (it: CommandItem): void => { this.pickCommand(it); },
                onPickMention: (it: MentionItem): void => { this.pickMention(it); },
                onRetryCommands: (): void => { this.command.ensureCommandsLoaded(true); }
              });
            }
            if (this.membershipState === 'writable' && !this.showEmojiPanel &&
              this.mention.mentionItems.length === 0 && !this.command.commandPanelActive() &&
              this.inline.inlineResults.length > 0) {
              InlineResultsBar({
                results: this.inline.inlineResults,
                onPick: (row: InlineResultRow): void => { this.pickInlineResult(row); }
              });
            }
            if (this.membershipState === 'writable' && !this.showEmojiPanel &&
              this.mention.mentionItems.length === 0 && !this.command.commandPanelActive() &&
              this.inline.inlineResults.length === 0 && this.sticker.stickerSuggestions.length > 0) {
              StickerSuggestionBar({
                suggestions: this.sticker.stickerSuggestions,
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

        }
        .layoutWeight(1).width('100%')
        .alignContent(Alignment.TopStart)
        // RESIZE changes this viewport in step with the system keyboard. The
        // area callback runs after the new List height is known, so pinning
        // here keeps message and composer motion visually locked together.
        .onAreaChange((_old: Area, _area: Area) => {
          // 这里原来还把 area.height 去抖后存进 listViewportH，那个字段没有任何
          // 消费者，已随第 11 项删除；这个回调保留是因为下面这半——IME 期间
          // 视口每帧变化时把尾部重新贴住。
          if (this.keyboardH > 0 && this.imeTailPinned) {
            this.syncTailOnImeFrame();
          }
        });
      }
      .width('100%').height('100%')
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .backgroundColor(Color.Transparent);

      // 贴纸飞出的残影。叠在最外层、不参与命中测试，纯视觉。
      if (this.overlayState.stickerGhostPath !== '') {
        Image(this.overlayState.stickerGhostPath)
          .width(STICKER_GHOST_SIDE).height(STICKER_GHOST_SIDE)
          .objectFit(ImageFit.Contain)
          .draggable(false)
          .position({
            x: this.overlayState.stickerGhostX - STICKER_GHOST_SIDE / 2,
            y: this.overlayState.stickerGhostY - STICKER_GHOST_SIDE / 2
          })
          .scale({
            x: this.overlayState.stickerGhostFly ? 0.34 : 1,
            y: this.overlayState.stickerGhostFly ? 0.34 : 1
          })
          .translate({ y: this.overlayState.stickerGhostFly ? -170 : 0 })
          .opacity(this.overlayState.stickerGhostFly ? 0 : 0.95)
          .animation({ duration: STICKER_FLY_MS, curve: Curve.FastOutSlowIn })
          .hitTestBehavior(HitTestMode.None);
      }

      // 【B11】9 个标量 @Param（showReactionSheet/showForwardSheet/
      // showScheduledSheet/showPollSheet/showContactSheet/
      // showVideoNoteRecorder/reactionTargetId/reactionPendingKey/
      // forwardMessageIds）收口成 overlayState: this.overlayState 一个 @Param；
      // onReactionShowChange/onForwardShowChange/onScheduledShowChange 三个
      // @Event 被 ChatOverlayHost 内部收掉（直接调 this.overlayState.setSheet），
      // 不再需要在这里转发。其余 @Param/@Event 逐字对应原样。
      //
      // 【B11b：外层那道 if 判据也收进组件了，本组件现在常驻挂载】
      // B11 保留了 HEAD 就有的那道 `if (showReactionSheet || ... )` 外层判据，
      // 于是页面 build 仍然订阅着这六个 @Trace——开合任意一个 sheet 都要重跑
      // 整页 build，方案给 B11 定的 perf 目标（开关反应面板 10 次页面 update
      // 20→0）拿不到 0，只拿到了 reactionTargetId/reactionPendingKey/
      // forwardMessageIds 那三个字段的收窄。
      // B11b 把判据搬进 ChatOverlayHost.anyOpen()，页面这里只传一个引用常量，
      // 一个 @Trace 都不读。代价是那个 width/height 100% 的根 Stack 一直挂着，
      // 命中测试要按开合切——处理在 ChatOverlayHost.build() 末尾的
      // hitTestBehavior 那一行，改动那一行之前先读它上面的说明。
      ChatOverlayHost({
        overlayState: this.overlayState,
        messages: this.messages,
        chatId: this.chatId,
        threadRootId: this.threadRootId,
        bottomSafe: this.bottomSafe,
        keyboardH: this.keyboardH,
        onReactionPick: (reactionKey: string, chosen: boolean): void => {
          const targetId: number = this.overlayState.reactionTargetId;
          this.overlayState.closeReactionSheet();
          this.overlayState.toggleReaction(targetId, reactionKey, chosen);
        },
        onForwardSent: (): void => {
          this.overlayState.forwardMessageIds = [];
          if (this.selection.active) {
            this.selection.exit();
          }
        },
        onPollSubmit: (question: string, options: string[], isAnonymous: boolean,
          isQuiz: boolean, correctOptionId: number): void => {
          this.overlayState.showPollSheet = false;
          if (this.store !== null) {
            this.atBottom = true;
            this.store.sendPoll(question, options, isAnonymous, isQuiz, correctOptionId);
          }
        },
        onPollClose: (): void => {
          this.overlayState.showPollSheet = false;
        },
        onContactPick: (contact: PickedContact): void => {
          this.overlayState.showContactSheet = false;
          if (this.store !== null) {
            this.atBottom = true;
            this.store.sendContact(
              contact.phone, contact.firstName, contact.lastName, contact.userId);
          }
        },
        onContactClose: (): void => {
          this.overlayState.showContactSheet = false;
        },
        onVideoCaptured: (path: string, durationSec: number, length: number): void => {
          if (this.store !== null) {
            this.atBottom = true;
            this.store.sendVideoNote(path, durationSec, length);
          }
        },
        onVideoClose: (): void => {
          this.overlayState.showVideoNoteRecorder = false;
        },
        effectDuration: (key: string, ms: number): number => this.chatEffectDuration(key, ms)
      });
      // The latest-message FAB belongs to the chat layer. Keeping it visible
      // while the media panel is open puts it above (and blocks) the GIF tab.
      // 显隐跟着"有没有可返回的位置"走，而不是"在不在底部"：站在最新消息上
      // 但引用链还没退完时，箭头仍然该在。
      if (this.returnTarget().kind !== RETURN_NONE && !this.search.mode && !this.showEmojiPanel) {
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
      if (viewerHidesTitleBar(isSplitLayout(this.screenW, this.screenH), this.viewerMsgId !== 0)) {
        this.mediaViewer();
      }
    }
    .width('100%').height('100%');
    }
    .titleBar({
      avoidLayoutSafeArea: true,
      // 消息 List 自己用 contentStartOffset 保留稳定锚点；这里不重复挤内容区。
      enableComponentSafeArea: false,
      // 第三个参数 false = 静态栏：滑动时不变（见 util/hdsTitleBar）。
      style: titleBarStyle(Color.Transparent, $r('app.color.text_primary'), false),
      content: this.chatTitleBarContent()
    })
    .titleMode(HdsNavDestinationTitleMode.MINI)
    // **HDS 自己的返回键和菜单一颗都不用**，三个胶囊全部由 stackBuilder 自绘
    // ——理由见 ChatHeader 文件头（玻璃/按压/动画 HDS 那三个字段都给不了，
    // 且把展开态接进 TitleBarContentOptions 会让整条栏按点击重建）。
    // 首页 ChatListPage 早就是这个结构。
    .hideBackButton(true)
    // 单栏下查看器盖不住框架标题栏（判据与上面那个 if 同源，见 navFullScreen）。
    // animated 取 true：查看器根节点是 300ms 的黑底渐入，第 0 帧直接摘掉顶栏会
    // 在还透着的黑底上闪一下。
    .hideTitleBar(viewerHidesTitleBar(
      isSplitLayout(this.screenW, this.screenH), this.viewerMsgId !== 0), true)
    // HDS 的标题栏模糊必须绑定实际滚动的同一个 Scroller。
    //
    // **转场期间先不绑**（09-04 GPU trace）。这条绑定给 NavDestination 层挂了一个
    // 覆盖整页的滤镜节点；推入动画期间 RS 要为整页开一张 1378×2832 的离屏缓存，
    // 而滤镜缓存被动画反复判失效（`forceClearCache_:1, hashChange`），于是整页
    // 内容被 CPU 重新光栅化两遍——实测两帧 98.7ms + 89.1ms，而同期 GPU 活跃度
    // 只有 6%，是纯 CPU 打满。那 170ms 是整次进会话卡顿的绝对大头。
    //
    // 模糊本身很便宜（那 79.6ms 里 DrawFilter 只占 0.57ms），**贵的是它触发的
    // 整页离屏缓存重建**。首屏揭幕之后再绑，那时页面已经静止，绑上不再有
    // 转场动画去反复作废缓存。
    .bindToScrollable(this.initialMessageTransitionSettled ? [this.scroller] : [])
    // HdsNavDestination 没有 fullScreenOverlay。只在分栏中把查看器提升为应用内
    // 顶层全模态，手机仍保留原来的页面内共享元素过渡。
    .bindContentCover(viewerFullScreenWanted(
      isSplitLayout(this.screenW, this.screenH), this.viewerMsgId !== 0), this.mediaViewer(), {
      modalTransition: ModalTransition.NONE,
      backgroundColor: Color.Black,
      enableSafeArea: false,
      onWillDismiss: (): void => { this.closeViewer(); }
    })
    // 入参：router 时代是 aboutToAppear 里 router.getParams() 现取，现在从
    // NavDestinationContext 的 pathInfo 里取——而 onReady 实测晚于 aboutToAppear，
    // 所以吃参数的初始化也在这里触发，不能留在 aboutToAppear。
    .onReady((ctx: NavDestinationContext): void => {
      this.navigationCoordinator.setStack(ctx.pathStack);
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
