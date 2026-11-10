import { closeContextMenu } from '../../util/uiContext';
import { showToast, showToastOptions } from '../../util/toast';
import { shareableMessageLink, ShareableMessageLink } from '../../util/deepLink';
import { ChatTimelineBindings, ChatTimelineSession } from './ChatTimelineSession';
import { subscribeVideoPreload } from '../../util/videoPreloadSetting';
import { initVideoPosterStore } from '../../util/videoPosterStore';
import { collapseFloatingVideo } from '../../util/floatingVideoRuntime';
import { ChatDropReceiver } from './ChatDropReceiver';
import { CHAT_DROP_TYPES } from '../../services/DropData';
import { EmojiDrawerState, drawerTopOverlap } from './EmojiDrawerState';
import { ComposerInputSwitch } from './ComposerInputSwitch';
import { StickerItem } from './StickerPicker';
import { GifItem } from './GifPicker';
import { ChatSendAccess } from './ChatSendAccess';
import { GroupPermissions } from '../../util/chatPermissions';
import { sendPermissionForType } from '../../util/sendPermissions';
import { SendPermissionError } from '../../store/SendPermissionApi';
import {
  HEIGHT_BP_LG, WIDTH_BP_SM, isSplitByBreakpoint
} from '../../util/layoutBreakpoint';
import { bumpDraftEpoch, localDraft, rememberLocalDraft } from '../../store/DraftStore';
import { initialAvatarPaths, warmSenderAvatars } from '../../util/avatarWarm';
import { dismissTopSheet, pushSheetDismiss } from '../../util/sheetDismissStack';
import { StickerSetSheet } from './StickerSetSheet';
import { StickerSetItem } from '../../util/stickerSetItems';
import {
  stickerSetIdForMessage, toggleFavoriteForMessage
} from './StickerMessageActions';
import { primeFavoriteStickers } from '../../store/FavoriteStickers';
import { deviceInfo } from '@kit.BasicServicesKit';
import { PROFILE_TAB_MEDIA } from '../../store/ChatProfileStore';
import { RowLeaveChannel, wholeDeleteRowIds } from '../../util/rowLeaveChannel';
import { saveableEntries, SaveablePlan } from '../../util/selectionSave';
import { ActionBarContext, dismissActionBar, handleActionBar } from './ChatActionBarActions';
import { actionBarButtons } from '../../util/chatActionBar';
import { ReportTarget, runReportFlow } from '../../util/reportFlow';
import { reportFlowUiFor } from '../common/ReportPrompts';
import { promptAction, UIContext } from '@kit.ArkUI';
import { MessageDeleteSession } from './MessageDeleteSession';
import { pasteboard } from '@kit.BasicServicesKit';
import { setScrollActive } from '../../util/scrollEffects';
import { rememberRecentSticker } from '../../store/StickerApi';
import { openMiniAppPage, openMessageMiniApp } from '../../util/miniAppNav';
import { InlineResultRow, sendInlineResult } from '../../store/BotApi';
import { clearEditableCache } from '../../util/messageEditable';
import { clearDeletableCache } from '../../util/messageDeletable';
import { common } from '@kit.AbilityKit';
import { PickedContact } from './ContactPickerSheet';
import { fileIo as fs } from '@kit.CoreFileKit';
import { holdPlayerJobs } from './WebmStickerView';
import { setChatAnimationSuspended } from '../../util/chatAnimationGate';
import { chatMotionAllowed, chatTimelineSuspended } from '../../util/chatMotionPolicy';
import { parkSenderAnimations } from '../../util/senderAnimationPark';
import { AudioSource, getVoicePlayback, streamAudioSource } from '../../services/VoicePlayback';
import { openLocalFile } from '../../util/openLocalFile';
import { getTdClient, getUserStore, getChatStore, getChatThemeStore } from '../../tdkit/Globals';
import { TdClient } from '../../tdkit/TdClient';
import { MessageStore, MediaSendItem, MESSAGE_WINDOW_CAP
} from '../../store/MessageStore';
import { MessageEntry, buildMessageEntry } from '../../store/MessageEntry';
import { allocateChatPageReuseScope } from '../../util/rowReuseId';
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
import { cacheMessagesInBackground } from '../../services/chatBackgroundCache';
import { selectionHasCacheableVideo } from '../../util/backgroundCacheEligibility';
import { PlaySlotDriver } from './PlaySlotDriver';
import { VideoHeadPrefetcher, VideoRef } from '../../services/VideoHeadPrefetcher';
import { subscribeNetworkType } from '../../services/NetworkStateService';
import { autoplaySizeAllowed, shouldCompete, slotKey } from './playSlot';
import { MediaViewerOverlay } from './MediaViewerOverlay';
import { openSelectTextOverlay, selectTextPayload } from './SelectTextOverlay';
import { ChatOverlayHost } from './ChatOverlayHost';
import { AudioFavoriteFlow } from './AudioFavoriteFlow';
import { ChatOverlayState, ChatOverlaySheetKind } from './ChatOverlayState';
import { ChatTimelineHost } from './ChatTimelineHost';
import { AttachActions } from './AttachActions';
import {
  ChatBackgroundState, ChatBackgroundStore, defaultChatBackgroundSnapshot, emptyChatBackground, parseSnapshot
} from '../../store/ChatBackgroundStore';
import { MusicQueue } from '../../services/MusicQueue';
import { VoiceState } from '../../services/VoicePlayback';
import { setMediaViewerOrientation } from './LiveViewerUi';
import {
  AlbumGroupDataSource, appendBreaksAnchor, prependBreaksAnchor, clampPrefetchRange, PrefetchRange, rowIdentity,
  repeatRowKey, reuseUnchangedRows, sameRowArray
} from './AlbumGroupDataSource';
import { IReusePool, LengthMetrics, UIUtils } from '@kit.ArkUI';
import { ChatPageSurface } from './ChatPageSurface';
import { ChatHeader } from './ChatHeader';
import { HeaderIdentitySession, ResolvedChatKind } from './HeaderIdentitySession';
import {
  ChatHeaderMenuController, ChatHeaderMenuParams, PANEL_MAIN, createChatHeaderMenuId
} from './ChatHeaderMenu';
import { TopBanners } from './TopBanners';
import { SelectionHeader } from './SelectionHeader';
import { SearchBottomBar, SearchHeader } from './ChatSearchBars';
import { SearchSenderPanel } from './SearchSenderPanel';
import {
  PendingMediaAppend, PendingMediaItem, appendPendingMedia,
  clearPendingMedia, hasPendingMedia, movePendingMedia, pendingMediaCanSend, toMediaSendItems,
  removePendingMedia
} from '../../util/pendingMedia';
import { sendDirectShareWithRecovery, stageShareWithPermissions } from '../../services/DirectShareSend';
import { ShareArrivalHost, applyShareArrival } from '../../util/shareArrival';
import {
  ShareMediaGeometry, UpgradedShare, upgradeLivePhotos
} from '../../util/shareLivePhoto';
import { SharedPayload } from '../../util/sharedContent';
import { onShareTargeted, takePendingShare } from '../../services/ShareInbox';
import { ChatComposerHost, ChatBottomDrawerHost } from './ChatComposerHost';
import { BOTTOM_DRAWER_HEIGHT, drawerBottomInset } from '../../util/drawerMetrics';
import { ChatSessionLifecycle } from './ChatSessionLifecycle';
import { ChatViewerSession } from './ChatViewerSession';
import { ChatMessageActionCoordinator } from './ChatMessageActionCoordinator';
import { UnreadMentionSession } from './UnreadMentionSession';
import { MembershipBar } from './MembershipBar';
import { SecretChatInfo } from '../../util/secretChat';
import { watchSecretChat } from '../../store/SecretChatWatch';
import { AT_BOTTOM_KEEP, AT_BOTTOM_YES, atBottomVerdict } from '../../util/atBottom';
import { membershipLosesComposer } from '../../util/membershipState';
import {
  TRANSLATION_ANCHOR_SETTLE_MS, clearTranslationInstant, shouldHoldTranslationAnchor
} from '../../util/translationAnchor';
import { registerTranslationGrowthPin, translationGrowthPinWanted } from '../../util/translationGrowthPin';
import {
  APPEND_ANCHOR_RESTORE_BYPASSED,
  newerPageIsUserDriven, shouldHoldAppendAnchor, useUserDrivenAppendMark
} from '../../util/appendAnchor';
import { PREPEND_ANCHOR_ENABLED, shouldCapturePrependAnchor, shouldPrimePrependAnchor } from '../../util/anchorRestore';
import {
  composerBottomGap as bottomGapOf, composerPlaceholder as placeholderOf,
  replyKeyboardVisible
} from '../../util/composerChrome';
import {
  TL_NEWER_ERROR, TL_OLDER_ERROR, TL_SYNC_ERROR
} from '../../util/timelineState';
import {
  MESSAGE_SELECTION_GUTTER_VP, messageSelectionContentWidth, rowMembersContaining,
  rowSelectable
} from '../../util/messageSelection';
import { commandLabel } from './SuggestionPanel';
import { cancelEdit, draftToRestore } from '../../util/composerMode';
import {
  SLOT_ATTACH, SLOT_EMOJI, SLOT_NONE, SLOT_REPLY_KB, claimIfFree, closeAllSlots, closeSlot,
  openSlot, slotIsDrawer, toggleSlot
} from '../../util/bottomSlot';
import {
  collapseAlbums, groupIndexOf, AlbumGroup, RunHeadHints
} from '../../util/collapseAlbums';
import {
  planEdgeSpliceRows, EdgeSplicePlan, patchIndicesAfterPrepend, SPLICE_PUBLISH_ENABLED,
  SPLICE_PATCH_PUBLISH_ENABLED, PUBLISH_DUPLICATE_SCAN, DuplicateRowReport,
  findDuplicateIdentities
} from '../../util/splicePublish';
import { publishMessageRowPresentations } from '../../util/messageRowPresentationChannel';
import { shouldFillViewport } from '../../util/viewportFill';
import {
  KEY_AUTOPLAY_MAX_MB,
  KEY_POWER_EFFECT_MENU,
  KEY_POWER_EFFECT_REPLY,
  KEY_CURRENT_NETWORK_TYPE,
  KEY_POWER_SMOOTH_TRANSITIONS,
  powerAnimationDuration,
  powerSavingActive
} from '../../store/AppSettings';
import {
  COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY, darkResourceMode
} from '../../util/theme';
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
import { VoiceRecorder } from '../../services/VoiceRecorder';
import { MediaSaveState } from './MediaSaveState';
import { MembershipSession } from './MembershipSession';
import { ScrollAnchorController } from './ScrollAnchorController';
import { leaveChatFully, setInFolder, showChatFolderPicker } from '../../store/ChatActions';
import { openJoinFolderMenu } from './JoinFolderMenu';
import { openReactorsMenu } from './ReactorsMenu';
import { liveLocation, LiveLocationState } from '../../services/LiveLocationService';
import { plural, str } from '../../util/strings';
import {
  ReturnState, ReturnTarget, RETURN_JUMP, RETURN_NONE, RETURN_READ,
  advanceRead, dropReachedJumps, emptyReturnState, nextReturnTarget, popJump, pushJump,
  reachedLatest
} from '../../util/readingReturn';
import {
  glassTintHex, containerBlur, overlayMaterial, overlayGlassFill
} from '../../util/overlayMaterial';
import { BOT_START_COMMAND, composerSlotState } from '../../util/botStart';
import { getAdministrators, AdminRow } from '../../store/ChatAdminApi';
import { adminLabelOf } from '../../util/adminLabel';
import { clearSenderRoles, publishSenderRole, senderRoleKey } from '../../util/senderRoleChannel';
import { logChatNavFailure, navigateToChat } from '../../util/chatNav';
import { hasPrefetchedPage } from '../../util/chatPrefetch';
import { subscribeChatJump } from '../../util/chatJumpChannel';
import { clearNowPlaying, NowPlaying, publishNowPlaying } from '../../util/nowPlayingChannel';
import { viewerFullScreenWanted, viewerHidesTitleBar } from '../../util/navFullScreen';
import { allocChatDestToken, markChatDestHidden, markChatDestShown } from '../../util/chatDestTracker';
import { isSystemTopBarReady, restoreViewerSystemBars } from '../../util/systemBarsWindow';
import { publishViewerCoversWindow } from '../../util/viewerWindowCover';
import {
  HdsNavDestination, HdsNavDestinationTitleMode, TitleBarContentOptions,
  HdsNavigationTitleBarOptions
} from '@kit.UIDesignKit';
import { titleBarStyle } from '../../util/hdsTitleBar';
import { navigateToChatProfile, navigateToProfile } from '../../util/profileNav';
import { endLinkNav } from '../../util/linkTapGuard';
import { copyPlainText } from '../../util/clipboard';
import {
  clientJoinNoticeRaw, hasRealClientJoinNotice, tagClientJoinNoticeGroup
} from '../../util/joinNotice';
import {
  ANCHOR_UNREAD, InitialAnchor, anchorLatchesBottom, initialAnchorOf
} from '../../util/initialAnchor';
import { isAtLiveTail, newestVisibleMessageId, visibleMessageIds } from '../../util/readMarking';
import { openForwardOrigin } from '../../util/chatNavigation';
import {
  confirmStopLiveLocation, normalizePhoneForDial, SharedLocationUris, sharedLocationUris
} from '../../util/locationActions';
import { utilityActionAllowedAt } from '../../util/utilityActionGuard';
import { buildRowPageInputs, RowPageInputs } from '../../util/rowPageInputs';
import { logE, logI, logW } from '../../util/log';
import {
  chromeDarkMaskOf, chromeIconColorOf, chromeOnDarkBgOf, chromeOnLightBgOf, chromeTextColorOf
} from '../../util/chatChrome';
import { wallpaperTakesUserDim } from '../../util/chatBackgroundRaster';
import {
  armedPageGate, canFirePageGate, draggedPageGate, firedPageGate,
  PAGE_GATE_REARM_DRAG_VP, PageGate, pageGateShotIsUserDriven, reachedNewerPageTrigger
} from '../../util/pageGate';
import {
  RememberedChatViewport, isResumeFragment, rememberChatPosition, rememberedChatViewport
} from '../../util/chatResume';
import { conversationScopeId } from '../../util/messageTopicScope';
import { navigateToSearch } from '../../util/searchNav';
import { navigateToSetting } from '../../util/settingsNav';
import { getActiveTdUserId } from '../../tdkit/Globals';
import {
  chatChromeHeight, ChatChromeGeometryInput, chatTopBannerHeight, chatTopicBarHeight
} from '../../util/ChatChromeGeometry';
import { KeyedListDataSource } from '../common/KeyedListDataSource';
import { ForumTopicsStore } from '../../store/ForumTopicsStore';
import { ForumTopicRow, topicAfterDelete, topicBarShown } from '../../util/forumTopicModel';
import { ChatTopicBar } from './ChatTopicBar';
import { CreatedTopic, createTopicFlow, deleteTopicFlow } from './TopicManageFlow';
import {
  initialMessageViewportRows, nextInitialMessageRevealCount, stageInitialMessageGroups,
  initialTailRevealTarget
} from '../../util/initialMessageStage';
import {
  LIST_CACHED_COUNT_DEFAULT
} from '../../util/debugListPerf';
import {
  ChatPageHiddenHooks, ChatPageShownHooks, ChatPageShownState, ChatPageWillHideHooks,
  coordinateChatPageHidden, coordinateChatPageShown, coordinateChatPageWillHide,
} from '../../util/chatPageLifecycle';
import {
  ChatPageNavigationCoordinator, parseChatRouteParams
} from '../../util/ChatPageNavigationCoordinator';
import { ChatPageSubscriptionRegistry } from '../../util/ChatPageSubscriptionRegistry';
import { chatEffectDurationOf } from '../../util/chatEffects';
import {
  INITIAL_BOTTOM_PRESENT_MIN_MS,
  INITIAL_MESSAGE_RELEASE_DELAY_MS, INITIAL_MESSAGE_TRANSITION_SETTLE_MS,
  INITIAL_TIMELINE_PRESENT_MIN_MS, INITIAL_TIMELINE_REVEAL_ROW_LIMIT,
  INITIAL_TIMELINE_ROW_FADE_MS, INITIAL_TIMELINE_ROW_STAGGER_MS,
  JUMP_LANDING_GRACE_MS, JUMP_RELOAD_THRESHOLD, KEYBOARD_SETTLE_MS,
  MENU_DISMISS_MS, NOW_SEC_TICK_MS, PREPARED_MESSAGE_CACHE_LIMIT,
  REUSE_CAP_MIN_INTERVAL_MS
} from '../../util/chatPageTuning';
import { DICE_CHOICES, DiceChoice } from '../../util/diceChoices';
import { mediaEntryIsPhoto, mediaEntryIsVideo } from '../../util/mediaEntryKind';
import { OneShotFrameCallback as ChatPageFrameCallback } from '../../util/oneShotFrameCallback';
import { bottomFollowShouldApply, bottomFollowShouldSchedule } from '../../util/bottomFollow';
import {
  NO_JUMP_LANDING, chunkPrependAllowed, jumpLandingDeadline, jumpLandingHolds
} from '../../util/jumpLandingOwner';
import { isResumeLanding } from '../../util/jumpAlign';
import { entryInlineSize, entryOwnsVideoFile, entryPrefetchFile } from '../../util/entryVideoVariant';

// B14 的四个建议控制器经宿主取值器拿 TDLib 客户端（缝的理由见
// ComposerSuggestionState.ets 文件里 client 取值器上方那段），这里只需要类型。
// UIUtils 本身从 API 12 起就有；这里用到的 getCustomComponentContext 是 26 起，
// 调用点在 capMessageReuseBuckets 的版本闸门之后。IReusePool 只是类型。
// cancelEdit/draftToRestore：commitEdit（留页面）用来把编辑态摊回 idle。
// ComposerMode/clearReply/enterEdit/enterReply/idleComposer 随 composerMode
// 七字段状态机整体搬进了 ComposerSession（B9 批），页面不再需要。
// setTranslateOptedIn/translateOptedIn/translateOptedOut/setTranslateOptedOut
// 与 getTranslationService/looksLikeTargetLanguage/resolveTranslateTarget 随
// 整簇翻译判定/驱动搬进了 TranslationDriver（B10 批），页面不再直接引用。
// bind 里 newRecorder 取值器的返回类型（等价于搬之前那句 new VoiceRecorder()）。
// applyTypingUpdate/pruneExpiredTyping/typingLabelOf 随 typingSenders/
// typingTimer/typingLabel 整套搬进了 TypingIndicatorState（B10 批），页面不再
// 直接引用。
// ⚠️ 临时（P6 标定）：cachedCount 档位调试项。标定结束后按
// util/debugListPerf.ets 末尾的清单删除。
// 以下五组是 B1 从本文件顶部搬走的模块级声明，现在从 util 导入。
// 别名保持原类名，4 处 new ChatPageFrameCallback(...) 调用点一字未动。

// applyRouteParams 的阶段间上下文：只在 A->C 之间传递的路由派生量。
interface RouteApplyContext {
  jumpTo: number | undefined;
  // 系统分享送进来的内容等着落到这个会话。**必须等 store 建好之后再消费**
  // （见 applyRouteParams 里那句调用的说明）。
  sharePending: boolean;
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

// Emoji offered in the full reaction picker (opened from the long-press menu's
// chevron). Ordered roughly like the official client's reaction sheet.
// 删除时那几行淡出的时长（issue #149）。比 publishGroupsNow 里塌陷动画的 200ms
// 略短，好让"先淡出、后收拢"读起来是一个连续动作。

let clearDetailHidingTimer: number = -1;

function cancelClearChatDetailHiding(hiding: boolean): void {
  if (clearDetailHidingTimer !== -1) {
    clearTimeout(clearDetailHidingTimer);
    clearDetailHidingTimer = -1;
  }
  AppStorage.setOrCreate<boolean>('chatDetailHiding', hiding);
}

function scheduleClearChatDetailHiding(): void {
  if (!(AppStorage.get<boolean>('chatDetailHiding') ?? false)) {
    return;
  }
  if (clearDetailHidingTimer !== -1) {
    return;
  }
  clearDetailHidingTimer = setTimeout((): void => {
    clearDetailHidingTimer = -1;
    AppStorage.setOrCreate<boolean>('chatDetailHiding', false);
  }, 36);
}

@ComponentV2
export struct ChatPage {
  private timeline: ChatTimelineSession = new ChatTimelineSession();
  private sessionLifecycle: ChatSessionLifecycle = new ChatSessionLifecycle();
  private viewer: ChatViewerSession = new ChatViewerSession();
  private messageActionsState: ChatMessageActionCoordinator = new ChatMessageActionCoordinator();
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
  private readonly chatDestToken: number = allocChatDestToken();
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
  @Param unifiedBackground: boolean = false;
  @Param appBackgroundRaw: string = '';
  @Param appBackgroundDim: number = 0;
  @Require @Param topSafe: number = 0;
  @Require @Param bottomSafe: number = 0;  // ✅ 新增
  @Require @Param keyboardH: number = 0;
  @Require @Param appIsForeground: boolean = true;
  // ⚠️ 临时（P6 标定）：List 的 cachedCount 档位，由 ChatPageChrome 透传。
  // 不是 @Require —— 少数直接 new ChatPage 的调用点（预览）没有它时用默认档。
  @Param listCachedCount: number = LIST_CACHED_COUNT_DEFAULT;

  // composerSlot() 的两个入参——messageLoadState 与 visibleGroupCount——都是**普通
  // 字段**，V2 里改了不触发任何重绘。于是机器人会话发出 /start、历史不再为空之后，
  // 输入区不会重新求值，「开始」按钮一直留着换不回输入框（用户 2026-09-07 报）。
  //
  // 进会话时按钮能正常出现，只是因为那一刻 membershipState 这类 @Local 恰好也在变、
  // 顺带把输入区重绘了一次——纯属搭便车，不是机制。
  //
  // 这里放一个可观测的镜像，只装**归属可能改变**的那两位（加载态 + 空不空），
  // 而不是把 visibleGroupCount 本身变成 @Local：后者每次发布都会变，等于每翻一页
  // 就重绘一次输入区。
  @Local private composerSlotKey: string = '';

  private syncComposerSlot(): void {
    const key: string = `${this.timeline.messageLoadState}|${this.timeline.visibleGroupCount > 0 ? 1 : 0}`;
    if (this.composerSlotKey !== key) {
      this.composerSlotKey = key;
    }
  }

  @Local private contentAnimationsAllowed: boolean = false;
  private hiddenSinceMs: number = 0;
  private scrollResumeCapturedOnHide: boolean = false;
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

  // ⚠️ 临时探针（2026-09-21，#140「动态头像要退出会话重进才动」）。定位完删。
  // 输入里到底是谁一直按着闸，静态看不出来——只在结果变化时打一行。
  private tgsGateLast: number = -1;

  private syncChatTgsGate(): void {
    this.viewer.underlay.setActive(this.timeline.pageVisible && this.appIsForeground && this.viewerOpen());
    // 查看器在同一个 Stack 内铺满聊天列；不影响分栏里仍可见的其他区域。
    this.contentAnimationsAllowed = chatMotionAllowed(this.timeline.pageVisible, this.appIsForeground, this.viewerOpen());
    this.typing.setActive(this.timeline.pageVisible && this.appIsForeground);
    const suspended: boolean = chatTimelineSuspended(this.contentAnimationsAllowed,
      this.timeline.initialMessageStageActive, this.timeline.chatTgsScrollActive, this.timeline.chatTgsStageSettling);
    const now: number = (suspended ? 1 : 0) | (this.timeline.pageVisible ? 2 : 0) |
      (this.timeline.initialMessageStageActive ? 4 : 0) | (this.timeline.chatTgsScrollActive ? 8 : 0) |
      (this.timeline.chatTgsStageSettling ? 16 : 0) | (this.appIsForeground ? 32 : 0) |
      (this.viewerOpen() ? 64 : 0);
    if (now !== this.tgsGateLast) {
      this.tgsGateLast = now;
      logW(`[TgsGate2] suspended=${suspended} visible=${this.timeline.pageVisible}`
        + ` stage=${this.timeline.initialMessageStageActive} scroll=${this.timeline.chatTgsScrollActive}`
        + ` settling=${this.timeline.chatTgsStageSettling} foreground=${this.appIsForeground} viewer=${this.viewerOpen()}`);
    }
    setChatAnimationSuspended(suspended);
  }

  // 诊断：把视口附近这一段数据集原样打出来，供和屏幕逐行对照。
  //

  // 官方预取算法：按可见区域变化决定预取/取消哪些行的图片解码。

  private messageActionsCache: MessageBubbleActions | null = null;

  private messageActions(): MessageBubbleActions {
    if (this.messageActionsCache === null) {
      this.messageActionsCache = {
        bubbleFocus: this.flash.focus,
        rowLeave: this.rowLeave,
        onStopLiveLocation: (): void => { confirmStopLiveLocation(); },
        // 形参 x/y 保留但不再存：几何过渡已全交给 geometryTransition，查看器
        // 那两个 @Param 从来没被读过（S1 已删）。**签名不改**——MessageBubble
        // 的三处调用点（:2068/:2099/:2761）传的是 e.windowX/windowY，改签名
        // 就要动跨组件契约，而将来若要回退到"从点击点缩放"那套转场，这两个值
        // 还得从这里取。
        onMediaTap: (messageId: number, _x: number, _y: number): void => {
          this.openViewer(messageId);
        },
        onAvatarTap: (userId: number): void => {
          const params: Record<string, Object> = { 'userId': userId };
          navigateToProfile(params);
        },
        onAvatarLongPress: (userId: number, name: string): void => {
          this.mentionSender(userId, name);
        },
        onLinkTap: (url: string, askFirst: boolean): void => { this.messageActionsState.onLinkTap(url, askFirst); },
        onCommentTap: (messageId: number): void => { this.onCommentTap(messageId); },
        onMiniApp: (messageId: number, url: string): void => {
          openMessageMiniApp(this.chatId, this.entryById(messageId), url);
        },
        onBotCallback: (messageId: number, data: string): void => {
          this.messageActionsState.onBotCallback(messageId, data);
        },
        onReplyTap: (messageId: number, fromId: number): void => {
          this.onReplyTap(messageId, fromId);
        },
        onFileTap: (messageId: number): void => { this.mediaSave.onFileTap(messageId); },
        onFileSave: (messageId: number): void => { this.mediaSave.onFileSave(messageId); },
        onFilePause: (messageId: number): void => { this.store?.pauseFileDownload(messageId); },
        onBackgroundCache: (messageIds: number[]): void => {
          cacheMessagesInBackground(this.getUIContext().getHostContext() as common.UIAbilityContext, this.timeline.messages, messageIds, this.chatId);
        },
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
          this.messageActionsState.onPollVote(messageId, optionIds);
        },
        onGameOpen: (messageId: number): void => { this.messageActionsState.onGameOpen(messageId); },
        onGamePhotoRetry: (messageId: number): void => { this.store?.retryPhoto(messageId); },
        onPaidMediaUnlock: (messageId: number): void => { this.messageActionsState.onPaidMediaUnlock(messageId); },
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
          this.musicQueue.play(this.timeline.messages, messageId, false);
        },
        onAudioPrevious: (messageId: number): void => {
          this.musicQueue.previous(this.timeline.messages, messageId);
        },
        onAudioNext: (messageId: number): void => {
          this.musicQueue.next(this.timeline.messages, messageId);
        },
        onAudioSave: (messageId: number): void => { this.mediaSave.onFileSave(messageId); },
        // 收藏面板整个在 pages/chat/AudioFavoriteFlow 里，本页只记下"给哪条消息开"。
        onAudioFavorite: (messageId: number): void => { this.favoriteAudioId = messageId; },
        onAudioSeek: (messageId: number, fraction: number): void => {
          this.musicQueue.seek(messageId, fraction);
        },
        onAutoplayVideoNeedDownload: (messageId: number): void => {
          this.store?.requestVideoDownload(messageId);
        },
        onMediaRatio: (messageId: number, albumIndex: number, ratio: number,
          centerY: number): void => {
          this.playSlot.reportMedia(messageId, albumIndex, ratio, centerY);
          this.videoPrefetch.reportMedia(messageId, albumIndex, ratio);
        },
        onMediaGone: (messageId: number, albumIndex: number): void => {
          this.playSlot.dropMedia(messageId, albumIndex);
          this.videoPrefetch.dropMedia(messageId, albumIndex);
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
        onAddToGifs: (messageId: number): void => { this.onAddToGifs(messageId); },
        onViewStickerSet: (messageId: number): void => { this.openStickerSet(messageId); },
        onToggleFavoriteSticker: (messageId: number): void => {
          this.toggleFavoriteSticker(messageId);
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
        onShowReactorsList: (messageId: number, anchorId: string): void => {
          openReactorsMenu(this.getUIContext(), this.chatId, messageId, anchorId,
            this.findMsg(messageId)?.reactions ?? []);
        },
        onTranslateMsg: (messageId: number): void => {
          this.messageActionsState.translateMessage(messageId);
        },
        onToggleTranslation: (messageId: number, hidden: boolean): void => {
          this.translation.toggleHidden(messageId, hidden);
        },
        onRetryTranslation: (messageId: number): void => {
          this.translation.translateInline(messageId);
        },
        onPinMsg: (messageId: number, unpin: boolean): void => {
          this.messageActionsState.togglePinMessage(messageId, unpin);
        },
        onStopPoll: (messageId: number): void => { this.messageActionsState.stopPoll(messageId); },
        onReplaceMedia: (messageId: number): void => { this.attach.replaceMedia(messageId); },
        onPollVoters: (messageId: number): void => { this.messageActionsState.showPollVoters(messageId); },
        onSetDefaultReaction: (emoji: string): void => { setDefaultReaction(emoji); },
        onSetReaction: (messageId: number, emoji: string, chosen: boolean): void => {
          this.overlayState.toggleReaction(messageId, emoji, chosen);
        },
        onReplyTo: (messageId: number): void => {
          // 兜底：输入框都不在的时候不接受回复。手势那边已经按 data.canReply
          // 拦过一道，这里是唯一的漏斗，再拦一次，免得将来新增入口漏掉。
          if (membershipLosesComposer(this.membershipState)) {
            return;
          }
          this.composer.startReply(messageId);
        },
        onCopyText: (messageId: number): void => { this.copyMessageText(messageId); },
        onSelectText: (messageId: number): void => { this.openSelectText(messageId); },
        onCopyLink: (messageId: number): void => { this.copyMessageLink(messageId); },
        onForwardMessages: (messageIds: number[]): void => { this.messageActionsState.openForwardPicker(messageIds); },
        onSaveMessages: (messageIds: number[]): void => { this.messageActionsState.saveToSavedMessages(messageIds); },
        onRepeatMessages: (messageIds: number[]): void => { this.messageActionsState.repeatMessages(messageIds); },
        onSendDice: (emoji: string): void => { this.attach.sendDiceEmoji(emoji); },
        onViewSenderHistory: (senderId: number): void => { this.search.enterForSender(senderId); },
        onReportMsg: (messageId: number): void => {
          // 与会话页共用 util/reportFlow；UI 三件套见 pages/common/ReportPrompts。
          runReportFlow((req: TdRequest): Promise<TdObject> => getTdClient().send(req, 15000),
            { chatId: this.chatId, messageIds: [messageId] } as ReportTarget,
            reportFlowUiFor(this.getUIContext()));
        },
        onSelectMessages: (messageIds: number[]): void => { this.selection.selectRow(messageIds); },
        // 相册逐格勾选：只切这一条。已经在多选态才有意义，非多选态由长按进入。
        onToggleSelectedMessage: (messageId: number): void => {
          this.selection.toggleMember(messageId);
        },
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

  // "×× 正在输入…" 提示的状态与到期定时器由 TypingIndicatorState 管理
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
  // 设置里的「强制单栏」。V2 读不了 AppStorage，由 ChatPageEntry 透传。
  @Require @Param forceSingleColumn: boolean = false;
  @Require @Param chatContentWidth: number = 360;
  private lastScreenW: number = 0;
  @Require @Param screenH: number = 780;
  // 系统断点（util/layoutBreakpoint），由 ChatPageEntry 从 AppStorage 读了传进来。
  @Param widthBp: number = WIDTH_BP_SM;
  @Param heightBp: number = HEIGHT_BP_LG;
  @Param windowPortrait: boolean = true;
  @Require @Param powerSaving: boolean = false;
  @Require @Param powerChatEffects: boolean = true;
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

  // 图标对比度跟实际露出的整窗背景走，不能再参考被隐藏的会话壁纸。
  private chromeBackground(): ChatBackgroundState {
    return this.unifiedBackground
      ? (parseSnapshot(this.appBackgroundRaw) ?? emptyChatBackground()) : this.chatBg;
  }

  // ── chrome 的前景要跟着**壁纸**翻，不是跟着深浅色模式 ───────────────────
  //
  // 判据、叠加公式与真机对比度数字全部住在 util/chatChrome.ets，由
  // entry/src/test/ChatChrome.test.ets 钉住；这里只剩「读字段 → 调纯函数」的
  // 薄包装。glassTintHex(true) 留在页面侧：玻璃厚度是设备态（依赖
  // immersiveMaterialAvailable()），不能进纯函数。
  private chromeOnLightBg(): boolean {
    return chromeOnLightBgOf(this.appDark, this.chromeBackground().colors, glassTintHex(true),
      this.chromeDarkMask());
  }

  private chromeDarkMask(): number {
    // 与 ChatBackdrop.darkMaskOpacity 同一判据：纯色 / 跟随系统不吃用户遮罩。
    const bg: ChatBackgroundState = this.chromeBackground();
    return chromeDarkMaskOf(bg.dimming,
      wallpaperTakesUserDim(bg.colors, bg.path)
        ? (this.unifiedBackground ? this.appBackgroundDim : this.chatBgDim) : 0);
  }

  // 浅色模式 + 暗壁纸的那一半（用户 2026-09-18：黑壁纸上按钮图标还是黑的）。
  // tint 要传**浅色**那档的玻璃色——合成的是浅色模式下那层玻璃。
  private chromeOnDarkBg(): boolean {
    return chromeOnDarkBgOf(this.appDark, this.chromeBackground().colors, glassTintHex(false),
      this.chromeDarkMask());
  }

  private chromeIcon(): ResourceColor {
    return chromeIconColorOf(this.chromeOnLightBg(), this.appDark, this.chromeOnDarkBg());
  }

  private chromeText(): ResourceColor {
    return chromeTextColorOf(this.chromeOnLightBg(), this.chromeOnDarkBg());
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
  // this.overlayState.xxx 读写。`paidMediaPendingIds` 由消息操作协调器持有。
  //
  // 字段初始化器 new：首帧前就已存在、引用全生命周期稳定、类型非空。禁止做成
  // 模块级单例：平板分栏/导航栈多层时同时活着多个 ChatPage，各自会话的弹层
  // 状态互不相干。
  private overlayState: ChatOverlayState = new ChatOverlayState();
  // 本页是否真的在屏上（NavDestination.onShown/onHidden）。给 ChatBackdrop 决定
  // 整屏光栅的 pin 生命周期：隐藏即还引用（2 秒宽限期），显示即重新 retain。
  @Local private surfaceActive: boolean = true;
  @Local nowSec: number = 0;
  private nowSecTimer: number = -1;
  // 查看器的目标、控制层、横屏和播放交接状态集中在 ChatViewerSession；页面只
  // 负责把它接到消息列表、播放位和系统方向 API。
  @Local swipeDir: number = 1; // 1 = advancing forward (next), -1 = going back — drives the slide direction
  // 顶栏下挂那张浮卡（置顶消息条 + 直播/群通话条）的整套状态机（B5 批）。原来
  // 摊在这里的 14 个 @Local（pinnedPreview/pinnedCount/pinnedLoadState/
  // pinnedJumpBusy/pinnedCycle/liveGroupCallId/liveCallIsActive/liveCallIsRtmp/
  // liveParticipantCount/livePulseExpanded/liveLoadState/liveDialogOpening/
  // liveNavigationBusy/topCardLoadingVisible——后者 2026-09-17 已删）与 9 个内部机件字段（4 个定时器
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
  // Message operation concurrency lives in ChatMessageActionCoordinator.
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
  @Local membershipRestrictedUntil: number = 0;
  @Local joiningChat: boolean = false;
  @Local joinByRequest: boolean = false;
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
  private sendAccess: ChatSendAccess = new ChatSendAccess();
  private membership: MembershipSession = new MembershipSession();
  private messageDelete: MessageDeleteSession = new MessageDeleteSession();
  private store: MessageStore | null = null;

  // 顶栏话题横条（2026-09-16）。三个都在字段初始化器里 new：titleBar 的 builder
  // **绝不能现场 new 对象**（见 chatTitleBarBottom 的注释），引用必须全生命周期不变。
  private topicsStore: ForumTopicsStore = new ForumTopicsStore(getTdClient());
  private topicRowsData: KeyedListDataSource<ForumTopicRow> =
    new KeyedListDataSource<ForumTopicRow>('chat-topics');
  private topicBarScroller: Scroller = new Scroller();
  // 横条有没有内容 —— 顶栏高度与下挂槽的结构缓存都看它，所以必须可观测。
  @Local private topicBarCount: number = 0;
  // 横条上给不给「新建话题」/长按删除（Bot 私聊话题模式，issue #206）。
  @Local private topicCreateAllowed: boolean = false;

  // 播放位竞选簇整簇搬进了 PlaySlotDriver（第二轮 R2-C）：候选表、定时器闭环、
  // 气泡进度表与两处查看器交接都在那边，页面只留下面两个 @Local（它们的读点在
  // prepareMessageBubble 的热路径上，搬走没有半径收益、只有一跳开销）。
  private playSlot: PlaySlotDriver = new PlaySlotDriver();
  // 视频气泡出现即预取第一块、划走即暂停（见 services/VideoHeadPrefetcher）。
  // 信号与播放位共用 onMediaRatio / onMediaGone，各取所需。
  private videoPrefetch: VideoHeadPrefetcher = new VideoHeadPrefetcher();
  @Local playSlotKey: string = '';
  // 新上位的播放位从哪一毫秒起播。换届时从 bubblePositionMs 查一次（见
  // subscribe 回调），随 playSlotKey 一起下发给气泡——查看器交还的进度就是
  // 靠这条路真正接到 VideoBubbleSurface.startPositionMs 上的。
  @Local playSlotStartMs: number = 0;
  // 缓存设置 → 自动播放静音开关，唯一消费点：下发给气泡播放器的 muted。
  @Require @Param autoplayMuted: boolean = true;
  private lastMaxId: number = 0;

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
  // 删除动画的旁路通道（issue #149）。不做模块级单例：平板分栏时多个 ChatPage
  // 同时活着，各自的淡出不能互相影响。
  private rowLeave: RowLeaveChannel = new RowLeaveChannel();
  // 会话操作条（issue #201 第 8 条），从 ChatEntry 镜像过来，空串 = 没有。
  // 音频卡片上「收藏」胶囊的目标消息；0 = 面板不显示。面板本体在
  // pages/chat/AudioFavoriteFlow（本页只留接线，见 [[no-new-code-in-chatpage]]）。
  @Local favoriteAudioId: number = 0;
  @Local actionBarKind: string = '';
  @Local actionBarCanUnarchive: boolean = false;
  @Local liveLocationMessageId: number = 0;
  // 贴纸"飞出"残影（stickerGhostPath/X/Y/Fly）与其收尾定时器句柄
  // （stickerGhostTimer）搬进了 ChatOverlayState（B11 批），原注释随字段一并
  // 搬走，页面侧改经 this.overlayState.stickerGhostXxx / this.overlayState.flyStickerGhost()。
  @Local unreadBadge: number = 0;

  // 右下角「↓」的去向状态。它不是"回到底部"，而是"回到该继续看的地方"：
  // 引用返回 > 阅读进度 > 最新消息。规则在 util/readingReturn（有单测），
  // 这里只负责喂状态和执行结果。
  @Local returnState: ReturnState = emptyReturnState();

  // 跳转落地的宽限期。跳到贴近尾部的引用时视口会短暂判为"在最新"，若不设防
  // 就会把返回栈当成"用户自己滚回来了"清掉，一步都退不回去。
  private jumpLandingUntil: number = 0;
  // 落地所有权窗口：跳转刚落地的这几百毫秒里，位置归这次跳转所有——贴底跟随、
  // 追加侧补位、再取一页历史、窗口裁剪四位都得让路。判据与四个嫌疑的来龙去脉
  // 见 util/jumpLandingOwner（与上面那条 900ms 各管一件事：那条管返回栈）。
  private jumpLandingSettleUntil: number = NO_JUMP_LANDING;
  private pendingScrollBottom: boolean = false; // snap to the end once jumpToLatest's page arrives
  // ⚠️ 临时探针 [JumpLatest] 用：↓ 的点击序号，把同一次点击的日志串起来。
  private jumpLatestSeq: number = 0;
  @Local scrollToBottomBusy: boolean = false;

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

  private jumpLayoutSeq: number = 0;

  // 内容铺不满一屏时主动补页的上限。到这个行数还说"整份都可见"，说明判据
  // 本身出了问题，停手比无限拉更安全。

  // 跳转落点通过行级通道驱动气泡呼吸，不再覆盖整行蓝色色带。
  //
  // 字段初始化器 new：首帧前就已存在、引用全生命周期稳定、类型非空。禁止做成
  // 模块级单例：平板分栏/导航栈多层时同时活着多个 ChatPage，各自的跳转高亮
  // 互不相干。
  private flash: JumpFlashState = new JumpFlashState();

  // RESIZE shortens the List while the IME animates in. Preserve the live-tail
  // anchor captured before that resize; otherwise onDidScroll observes the
  // temporary clipped viewport, flips atBottom to false and leaves the last
  // messages behind the newly raised composer.
  private imeTailPinned: boolean = false;
  private imeLayoutSeq: number = 0;
  private lastKeyboardH: number = 0;
  private fullViewportH: number = 0;
  private curViewportH: number = 0;
  private knownImeH: number = 0;
  private imeClosingToDrawer: boolean = false;
  private imeBridgeTimer: number = -1;
  private pendingImeBridgeFromEmoji: boolean = false;
  private drawerAnimSeq: number = 0;
  private drawerClosingToIme: boolean = false;
  private viewportResizeSettleTimer: number = -1;
  private lastComposerBottomGap: number = -1;
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
    // 边下边放：没有本地路径也能出声。迷你条要的曲目信息照发，path 留空——
    // 它只用来做暂停/继续，而流那一路的暂停继续由播放器自己管。
    playStream: (id: number, fileId: number, sizeBytes: number, mimeType: string,
      dur: number, forceStart: boolean): void => {
      const source: AudioSource = streamAudioSource(fileId, sizeBytes, mimeType);
      if (forceStart) {
        getVoicePlayback().startMusicSource(id, source, dur);
      } else {
        getVoicePlayback().toggleMusicSource(id, source, dur);
      }
      this.publishNowPlayingFor(id, '', dur);
    },
    seek: (id: number, fraction: number): void => { getVoicePlayback().seek(id, fraction); },
    requestDownload: (id: number, failed: boolean): void => {
      this.store?.requestVideoDownload(id, false, failed);
    },
    toast: (message: string, durationMs: number): void => {
      showToast(message, durationMs);
    }
  });
  // Messages with id above this slide in from the bottom (live arrivals only —
  // 0 disables, so rows created while scrolling history never animate).
  @Local freshSinceId: number = 0;
  private freshClearSeq: number = 0;

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
  // 骰子面板在「返回键该关谁」那张表里的注销函数（见 dock 上的 bindSheet）。
  private diceSheetOff: (() => void) | null = null;
  // 贴纸合集面板（点消息里的贴纸弹出来的那张）。
  @Local stickerSetSheetOpen: boolean = false;
  @Local stickerSetSheetId: string = '';
  // 面板内容的挂载态，和"抽屉是否可见"分开。
  //
  // 【为什么要分开】点格子会先发贴纸、再把 stickerSetSheetOpen 置 false 收起
  // 抽屉。原来 builder 里的 if 读的是同一个标志，于是内容在收起动画之前就被摘掉
  // ——用户看到的就是一个空白白抽屉（2026-11-05 实报）。现在收起期间内容继续
  // 挂着，等 onDisappear 真正消失后再卸载。
  @Local stickerSetSheetMounted: boolean = false;

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
  private composerEditorArea: Area | undefined = undefined;
  // 首帧直接挂载真实 TextArea，避免进场后从 Text 替身切换到 TextArea 导致占位文字基线/颜色跳动与主线程二次重排。
  @Local composerEditorReady: boolean = true;
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
  private unreadMentions: UnreadMentionSession = new UnreadMentionSession();
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

  // 每行 prepare 都要读的页面级状态，收成一个计算属性（逻辑在 util/rowPageInputs）。
  // 每行只读这一个，依赖不再逐行逐个登记；四个 id 数组也在这里转成普通 Set，每行不再
  // 在代理数组上跑 indexOf。只在其中某个状态变了时重算。
  // 【只收"状态 + 每行无条件读"的】普通字段（firstUnreadId / chatId / messageListRevision
  // …）变了不会让它重算；只有部分行才读的（nowSec、playSlotStartMs）放进来会把所有行
  // 一起拖着重跑。两类都留在 prepareMessageBubble 里逐行读。
  // 【声明在它用到的状态与控制器之后】@Computed 在组件创建时就计算一次。
  @Computed
  get rowPageInputs(): RowPageInputs {
    return buildRowPageInputs({
      isGroup: this.isGroup,
      isChannel: this.isChannel,
      translationActive: this.translation.active(this.translateChatsEnabled),
      editingActive: this.composer.isEditing(),
      liveCallActive: this.topCard.liveCallIsActive,
      liveGroupCallId: this.topCard.liveCallIsActive ? this.topCard.liveGroupCallId : 0,
      liveLocationMessageId: this.liveLocationMessageId,
      autoplayMuted: this.autoplayMuted,
      appearanceEpoch: this.appearanceEpoch,
      materialEpoch: this.materialEpoch,
      appDark: this.appDark,
      selectionActive: this.selection.active,
      chatContentWidth: this.chatContentWidth,
      canReply: !membershipLosesComposer(this.membershipState),
      playSlotKey: this.playSlotKey,
      freshSinceId: this.freshSinceId,
      pausedAnimationIds: this.viewer.pausedAnimationIds,
      forcedAnimationIds: this.viewer.forcedAnimationIds,
      failedAnimationIds: this.viewer.failedAnimationIds,
      paidMediaPendingIds: this.messageActionsState.paidMediaPendingIds
    });
  }

  private resetScrollSession(): void {
    this.timeline.invalidateScrollWork();
    this.timeline.scrollActionSeq++;
    this.jumpLayoutSeq++;
    this.timeline.anchor.invalidate();
    this.bottomChromeLayoutSeq++;
    this.timeline.initialUnreadLayoutSeq++;
    this.timeline.initialTimelinePresentationSeq++;
    this.timeline.initialTimelinePresentationScheduledSeq = 0;
    this.timeline.initialTimelineMasked = false;
    this.timeline.initialTimelineReadyToPresent = false;
    this.timeline.initialTailTarget = 0;
    this.timeline.initialTimelineEarliestAt = 0;
    this.timeline.initialMessageTransitionSettled = false;
    this.timeline.cancelInitialMessageTransitionSettle();
    this.timeline.didInitialScroll = false;
    this.lastMaxId = 0;
    this.timeline.atBottom = true;
    this.timeline.firstUnreadId = 0;
    this.timeline.stayAtUnread = false;
    this.timeline.curStartIdx = -1;
    // curEndIdx 和 indexGroupsLen 也要一起清。它们是上一个会话的可见行号，
    // 换会话后 groups 从 0 重新长起来，长度一旦碰巧和旧值相等，refreshAtBottom
    // 的新鲜度检查就会认下这批陈旧行号，据此否决"在底部"，于是刚进会话就
    // 挂出「↓」。清成 -1 后 indexFresh 恒为假，判定退回宽松侧，等第一次
    // onScrollIndex 落地再收紧。
    this.timeline.curEndIdx = -1;
    this.timeline.indexGroupsLen = -1;
    this.timeline.userScrollOffsetTotal = 0;
    // 与 userScrollOffsetTotal 同源，必须一起清：不清的话新会话第一帧的差值
    // 是个大数，白多算一次 chrome 跳过（不算错，但没必要留这种不一致）。
    this.timeline.floatDateScrollAt = 0;
    this.timeline.nextDidScrollIsUserDriven = false;
    this.timeline.timelineScrollActive = false;
    // 「↓」的返回关系和"底部看到的是哪条"同样是会话级的。消息 id 在每个会话
    // 里独立编号，把上一个会话的跳转栈带过来，↓ 就会指向本会话里一条恰好同号
    // 的无关消息——或者一条根本不存在的 id，点下去只是空转。
    this.returnState = emptyReturnState();
    this.timeline.curBottomId = 0;
    this.jumpLandingUntil = 0;
    this.jumpLandingSettleUntil = NO_JUMP_LANDING;
    this.clearPendingScrollBottom('resetScrollSession');
    this.scrollToBottomBusy = false;
    this.pendingJumpId = 0;
    this.pendingResumeId = 0;
    this.pendingResumeItemY = 0;
    this.timeline.resumeDividerId = 0;
    this.timeline.resumeDividerItemY = 0;
    // 原 `this.pendingFileOpenId = 0; this.fileOpenInFlightId = 0;` 两行（B15）。
    // 这是本簇六个字段里**只有这一对**会在换会话时单独清空的地方，另外四个在这
    // 条路径上从来不动——所以 MediaSaveState 单开了 resetFileOpenIntent()，
    // 不能用 dispose() 顶替（理由写在那个方法上方）。
    this.mediaSave.resetFileOpenIntent();
    this.musicQueue.reset();
    this.timeline.olderArmed = true;
    this.timeline.olderLoadQueued = false;
    this.timeline.initialViewportFillEnabled = true;
    this.timeline.newerGate = armedPageGate();
    this.freshSinceId = 0;
    this.freshClearSeq++;
    this.imeTailPinned = false;
    this.bottomChromeMeasured = false;
    this.lastComposerBottomGap = -1;
    this.imeLayoutSeq++;
    this.lastKeyboardH = this.keyboardH;
    this.flash.cancelFlash();
    this.timeline.clearFloatingDate();
    this.timeline.messages = [];
    this.timeline.messageListRevision++;
    this.timeline.preparedMessageCache.clear();
    // 「能不能编辑」的答案按 messageId 缓存，而 messageId 在别的会话里是另一条
    // 消息——换会话必须清，否则会把上一个会话的判断带过来（issue #179）。
    clearEditableCache();
    // 同一份 messageId 在别的会话里是另一条消息，「能不能删」也必须一起清。
    clearDeletableCache();
    this.timeline.messageLoadError = '';
    this.timeline.olderLoadState = 'idle';
    this.timeline.newerLoadState = 'idle';
    this.timeline.visibleGroupCount = 0;
    this.syncComposerSlot();
    this.timeline.publishGroups([]);
    this.viewer.resetAnimationState();
  }

  private resetComposerSession(): void {
    this.dropReceiver.cancel();
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
    this.inputSwitch.cancel();
    this.clearViewportResizeSettleTimer();
    this.clearImeBridge(false);
    this.drawerAnimSeq++;
    this.drawerClosingToIme = false;
    this.emojiDrawer.closingToIme = false;
    this.emojiDrawer.shellHeight = 0;
    this.emojiDrawer.activeSlot = '';
    this.emojiDrawer.cardOffsetY = 0;
    this.emojiDrawer.cardOpacity = 1;
    this.emojiDrawer.closingImeToDrawer = false;
    this.emojiDrawer.closingExpanded = false;
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
    this.composerEditorReady = true;
    this.imeTailPinned = false;
    this.bottomChromeMeasured = false;
    this.lastComposerBottomGap = -1;
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
    this.messageActionsState.reset();
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
      return this.timeline.noteRunHead(collapseAlbums(list, this.timeline.runHeadHints()));
    }
    const displayList: MessageEntry[] = list.slice();
    displayList.push(this.clientJoinNoticeEntry());
    const groups: AlbumGroup[] = this.timeline.noteRunHead(collapseAlbums(displayList, this.timeline.runHeadHints()));
    tagClientJoinNoticeGroup(groups, this.chatId, this.clientJoinNoticeDate);
    return groups;
  }

  private showClientJoinNotice(isChannel: boolean): void {
    this.clientJoinNoticeVisible = true;
    this.clientJoinNoticeIsChannel = isChannel;
    this.clientJoinNoticeDate = Math.floor(Date.now() / 1000);
    this.clientJoinNoticeEntryCache = null;
    const groups: AlbumGroup[] = this.groupsWithClientJoinNotice(this.timeline.messages);
    this.timeline.visibleGroupCount = groups.length;
    this.syncComposerSlot();
    this.timeline.publishGroups(groups);
    if (this.timeline.didInitialScroll && this.timeline.atBottom) {
      const actionSeq: number = ++this.timeline.scrollActionSeq;
      setTimeout((): void => {
        if (actionSeq === this.timeline.scrollActionSeq) {
          this.timeline.glueBottom('L846');
          this.timeline.refreshAtBottom();
        }
      }, 0);
    }
  }

  private captureScrollResume(): void {
    this.resumeScrollPending = false;
    if (!this.timeline.didInitialScroll || this.timeline.groups.length === 0 ||
      this.timeline.curStartIdx < 0 || this.timeline.curStartIdx >= this.timeline.groups.length) {
      return;
    }
    this.resumeScrollChatId = this.chatId;
    this.resumeScrollThreadId = conversationScopeId(
      this.threadRootId, this.forumTopicId, this.directMessagesTopicId);
    this.resumeScrollMessageId = this.timeline.groups[this.timeline.curStartIdx].head.id;
    const itemY: number = this.timeline.anchorItemY(this.timeline.curStartIdx);
    this.resumeScrollItemY = Number.isNaN(itemY) ? 0 : itemY;
    this.resumeScrollAtBottom = this.timeline.atBottom;
    // 同一份位置也记到模块级表里：页面销毁后（退出会话再进来）还能落回去，
    // issue #98。在底部的不记——那种情况下次该跟到最新。
    rememberChatPosition(this.chatId, this.resumeScrollThreadId,
      this.resumeScrollMessageId, this.timeline.atBottom, this.resumeScrollItemY);
    this.resumeScrollPending = true;
  }

  // 路由参数。router 时代靠 this.getUIContext().getRouter().getParams() 现取，NavDestination 要在
  // onReady 里从 NavDestinationContext 拿。
  //
  // 实测（平板 API 26，commit 8046f73 上机）：**onReady 晚于 aboutToAppear**。
  // 官方文档写 onReady 在「即将构建子组件之前」触发，但 aboutToAppear 比它更早，
  // 所以 aboutToAppear 里读不到 navParams。用参数的那一段因此整体挪进了
  // applyRouteParams()，由 onReady 存完 navParams 之后立即调用。
  // 译文到货的锚点保持。-1 = 这一轮还没记过位置。
  private translationAnchorIdx: number = -1;
  private translationAnchorY: number = 0;
  private translationAnchorTimer: number = -1;
  // 译文让行变高时的钉底分发（util/translationGrowthPin）；aboutToDisappear 摘掉。
  private unregisterTranslationGrowthPin: (() => void) | null = null;

  private navParams: Record<string, Object> | undefined = undefined;
  private navigationCoordinator: ChatPageNavigationCoordinator =
    new ChatPageNavigationCoordinator();

  // 返回上一层。**不能用 this.getUIContext().getRouter().back()**：本页是 NavDestination（导航页，不是 router 页），router 页栈里
  // 只剩 Index 一层，this.getUIContext().getRouter().back() 弹掉的是 Index——平板模拟器实测（Task 7 修复轮 1）
  // 的现象是「点返回箭头直接退到桌面」。要出的是 Navigation 栈。
  //
  // Task 6 迁移本页时 leaveChat 成功回调原样留了 this.getUIContext().getRouter().back()，是漏改，
  // 不是有意为之。标题栏返回键现在由 HDS 自己弹出同一条 Navigation 栈。
  // 会话操作条：从 ChatEntry 镜像两个标量；同值不写，免得惊动 TopBanners。
  // 收藏面板的副标题用。找不到就给空串——面板照样能开，只是标题少一行。
  private audioTitleOf(messageId: number): string {
    const found = this.timeline.messages.find((m: MessageEntry): boolean => m.id === messageId);
    return found !== undefined ? found.audioTitle : '';
  }

  private audioPerformerOf(messageId: number): string {
    const found = this.timeline.messages.find((m: MessageEntry): boolean => m.id === messageId);
    return found !== undefined ? found.audioPerformer : '';
  }

  private syncActionBar(): void {
    const e: ChatEntry | undefined = getChatStore().entryOf(this.chatId);
    const canUnarchive: boolean = e !== undefined ? e.actionBarCanUnarchive : false;
    const rawKind: string = e !== undefined ? e.actionBar : '';
    // 未实现按钮的类型不生成空操作行；渲染和顶部占位共用这个显示态。
    const kind: string = actionBarButtons(rawKind, canUnarchive).length > 0 ? rawKind : '';
    if (kind !== this.actionBarKind) { this.actionBarKind = kind; }
    if (canUnarchive !== this.actionBarCanUnarchive) { this.actionBarCanUnarchive = canUnarchive; }
  }

  private onActionBar(id: string): void {
    handleActionBar(id, {
      chatId: this.chatId,
      peerUserId: this.header.currentPeerUserId(),
      peerTitle: this.header.titleTextOf(),
      ui: this.getUIContext(),
      onChatRemoved: (): void => { this.goBack(); }
    } as ActionBarContext);
  }

  private goBack(): void {
    if (!this.navigationCoordinator.pop()) {
      // navStack 由 onReady(ctx.pathStack) 填，而 onReady 必先于本页可见，所以
      // 这一支不该发生。这里**故意不回退到 this.getUIContext().getRouter().back()**：那正是会退出应用的
      // 那条路，把返回键做成"什么都不做 + 一条日志"远比把应用关掉好。
      logE('ChatPage.goBack: navStack missing, back ignored');
      return;
    }
  }

  // 分享目标广播的退订钩子。会话已经开着时路由参数不会重跑，靠它认领
  // （见 services/ShareInbox 的那条旁路）。
  private offShareTargeted: (() => void) | null = null;
  // 这次分享要不要"进来就发"。由路由参数带进来，见 util/shareSendMode。
  private shareAutoSend: boolean = false;

  aboutToAppear(): void {
    this.messageActionsState.bind({
      client: (): TdClient => getTdClient(),
      chatId: (): number => this.chatId,
      store: (): MessageStore | null => this.store,
      entryById: (id: number): MessageEntry | null => this.entryById(id),
      pollVotersEntry: (id: number): MessageEntry | null => this.findMsg(id),
      displayUserName: (id: number): string => getUserStore().displayName(id),
      ensureUser: (id: number): void => { getUserStore().ensure(id); },
      currentUserId: (): number => getActiveTdUserId(),
      threadRootId: (): number => this.threadRootId,
      forwardIds: (ids: number[]): number[] => this.selection.forwardIds(ids),
      openForwardPicker: (ids: number[]): void => { this.overlayState.openForwardPicker(ids); },
      closeContextMenu: (): void => { closeContextMenu(); },
      translateInline: (id: number): void => { this.translation.translateInline(id); },
      context: (): common.UIAbilityContext => this.getUIContext().getHostContext() as common.UIAbilityContext,
      sendBotCommand: (command: string): void => { this.sendBotCommand(command); },
      searchForQuery: (query: string): void => { this.search.enterForQuery(query); },
      jumpToLinkedMessage: (id: number): void => { this.jumpToLinkedMessageInThisChat(id); },
      actionMenu: (options: promptAction.ActionMenuOptions): Promise<promptAction.ActionMenuSuccessResponse> =>
        this.getUIContext().getPromptAction().showActionMenu(options),
      toast: (options: promptAction.ShowToastOptions): void => { showToastOptions(options); },
      dialog: (options: promptAction.ShowDialogOptions): Promise<promptAction.ShowDialogSuccessResponse> =>
        this.getUIContext().getPromptAction().showDialog(options),
      confirmMenu: (options: promptAction.ShowDialogOptions, what: string) => new Promise((resolve, reject) => {
        const prompt = this.getUIContext().getPromptAction();
        setTimeout((): void => {
          prompt.showDialog(options).then(resolve).catch((e: Object): void => {
            logI(`ChatPage.${what} dialog dismissed: ${JSON.stringify(e)}`);
            reject(e);
          });
        }, MENU_DISMISS_MS);
      }),
      openPaymentUrl: (url: string): void => {
        openWebUrl(this.getUIContext().getHostContext() as common.UIAbilityContext, url, (): void => {
          showToast($r('app.string.cp_cannot_open_payment'), 1800);
        });
      },
      logError: (message: string): void => { logE(message); }
    });
    this.viewer.bind({
      onTargetChanged: (): void => { this.onViewerTargetChanged(); },
      store: (): MessageStore | null => this.store,
      entryById: (id: number): MessageEntry | null => this.entryById(id),
      messages: (): MessageEntry[] => this.timeline.messages,
      groups: (): AlbumGroup[] => this.timeline.groups,
      effectDuration: (key: string, duration: number): number => this.chatEffectDuration(key, duration),
      logOpen: (): void => {
        const split = isSplitByBreakpoint(this.widthBp, this.heightBp, this.forceSingleColumn, this.windowPortrait);
        logW(`[ViewerPath] split=${split} path=inline coversWindow=${split}` +
          ` api=${deviceInfo.sdkApiVersion} win=${Math.round(this.screenW)}x${Math.round(this.screenH)}`);
      },
      unlockPaidMedia: (id: number): void => { this.messageActionsState.onPaidMediaUnlock(id); },
      handoffToViewer: (id: number): number => this.playSlot.handoffToViewer(id),
      handoffFromViewer: (id: number, index: number, position: number): void => {
        this.playSlot.handoffFromViewer(id, index, position);
      },
      resumePrefetch: (): void => { this.videoPrefetch.resume(); },
      armPlaySlotSettle: (): void => { this.playSlot.armSettle(); },
      exitLandscape: (): void => { setMediaViewerOrientation(this.getUIContext().getHostContext() as common.UIAbilityContext, false); },
      restoreSystemBars: (): Promise<void> => restoreViewerSystemBars(this.getUIContext().getHostContext() as common.UIAbilityContext),
      isSystemTopBarReady: (): boolean => isSystemTopBarReady()
    });
    this.sessionLifecycle.bind({
      invalidateScrollWork: (): void => { this.timeline.invalidateScrollWork(); },
      cancelDropReceiver: (): void => { this.dropReceiver.cancel(); },
      publishViewerCovered: (): void => { publishViewerCoversWindow(false); },
      disposeShareTargeted: (): void => {
        if (this.offShareTargeted !== null) {
          this.offShareTargeted();
          this.offShareTargeted = null;
        }
      },
      disposeInitialStageAndTgs: (): void => { this.disposeInitialStageAndTgs(); },
      disposePlaybackAndSlots: (): void => { this.disposePlaybackAndSlots(); },
      persistDraftAndViewport: (): void => { this.persistDraftAndViewport(); },
      disposeTimersAndSeqGuards: (): void => { this.disposeTimersAndSeqGuards(); },
      stopVoicePlaybackKeepingMusic: (): void => { this.stopVoicePlaybackKeepingMusic(); },
      disposeSubscriptionsInOrder: (): void => { this.disposeSubscriptionsInOrder(); },
      closeStores: (): void => { this.closeStores(); }
    });
    const timelineBindings: ChatTimelineBindings = {
      scheduleComposerEditorMount: (): void => { this.scheduleComposerEditorMount(); },
      syncChatTgsGate: (): void => { this.syncChatTgsGate(); },
      getUIContext: (): UIContext => this.getUIContext(),
      screenH: (): number => this.screenH,
      bottomChromeH: (): number => this.bottomChromeH,
      store: (): MessageStore | null => this.store,
      isGroup: (): boolean => this.isGroup,
      isChannel: (): boolean => this.isChannel,
      chatId: (): number => this.chatId,
      threadRootId: (): number => this.threadRootId,
      forumTopicId: (): number => this.forumTopicId,
      directMessagesTopicId: (): number => this.directMessagesTopicId,
      screenW: (): number => this.screenW,
      langEpoch: (): number => this.langEpoch,
      pendingJumpId: (): number => this.pendingJumpId,
      playSlotKey: (): string => this.playSlotKey,
      playSlotStartMs: (): number => this.playSlotStartMs,
      nowSec: (): number => this.nowSec,
      chatBg: (): ChatBackgroundState => this.chatBg,
      header: (): HeaderIdentitySession => this.header,
      translateChatsEnabled: (): boolean => this.translateChatsEnabled,
      listCachedCount: (): number => this.listCachedCount,
      imeTailPinned: (): boolean => this.imeTailPinned,
      selection: this.selection,
      musicQueue: this.musicQueue,
      playSlot: this.playSlot,
      translation: this.translation,
      topCard: this.topCard,
      flash: this.flash,
      headerChromeHeight: (): number => this.headerChromeHeight(),
      viewerOpen: (): boolean => this.viewerOpen(),
      jumpLandingHolding: (): boolean => this.jumpLandingHolding(),
      syncReturnState: (): void => { this.syncReturnState(); },
      markVisibleRead: (end: number): void => { this.markVisibleRead(end); },
      closeBottomPanels: (): void => { this.closeBottomPanels(); },
      dismissKeyboardOnUserScroll: (): void => { this.dismissKeyboardOnUserScroll(); },
      keyboardVisible: (): boolean => this.keyboardH > 0,
      capMessageReuseBuckets: (): void => { this.capMessageReuseBuckets(); },
      cancelImeFollow: (): void => {
        this.imeTailPinned = false;
        this.imeLayoutSeq++;
      }
    };
    this.timeline.bind(timelineBindings);

    // 目标会话正是自己时把分享取走。放在最前：它只是登记一个回调，
    // 不依赖下面任何初始化。
    this.offShareTargeted = onShareTargeted((chatId: number): void => {
      if (chatId === this.chatId) {
        this.consumeSharedContent();
      }
    });
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
      groups: (): AlbumGroup[] => this.timeline.groups,
      curStartIdx: (): number => this.timeline.curStartIdx,
      prepareUserJump: (): void => { this.prepareUserJump(); },
      scrollToLatest: (): void => { this.scrollToLatest(); },
      // scroller 是页面独有的（不变量 10），所以这条动作回调把
      // 「怎么滚到那一行」（现在是居中，见 scrollToJumpTarget）这个细节挡在控制器之外，
      // 顺带让 ArkUI 的滚动类型不必进那个文件。
      scrollToIndex: (index: number): void => { this.timeline.scrollToJumpTarget(index); },
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
        this.typing.refresh();
      },
      // header.refresh()（原 refreshHeader）对未读徽标的写入单独一条通道，不
      // 经 onChatKindResolved——它由消息/会话列表更新驱动，触发频率远高于一次
      // 身份解析，见 HeaderIdentitySession.ets 的说明。
      onUnreadCount: (count: number): void => { this.unreadBadge = count; },
      onLiveEntry: (entry: ChatEntry): void => { this.topCard.syncLiveFromChatEntry(entry); },
      onKnownBackground: (background: TdObject): void => {
        this.bgStore?.applyKnownBackground(background);
      },
      commitTimelineSnapshot: (): void => { this.timeline.commitTimelineSnapshot(); },
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
    this.messageDelete.bind({
      ui: (): UIContext => this.getUIContext(), client: (): TdClient => getTdClient(),
      chatId: (): number => this.chatId, selfId: (): number => getActiveTdUserId(),
      markLeaving: (ids: number[]): Promise<void> => this.markRowsLeaving(ids),
      clearLeaving: (): void => { this.rowLeave.clear(); },
      onDeleted: (): void => { this.selection.exit(); }
    });
    // 会话内搜索控制器接上宿主（B6）。jumpToMessage 命中后交回页面走
    // onReplyTap；cancelFlash 是与搜索簇本身无关的高亮闪烁子系统。
    this.search.bind({
      client: (): TdClient => getTdClient(),
      canSuggestSenders: (): boolean => this.isGroup && !this.isChannel,
      chatId: (): number => this.chatId,
      threadRootId: (): number => this.threadRootId,
      forumTopicId: (): number => this.forumTopicId,
      directMessagesTopicId: (): number => this.directMessagesTopicId,
      jumpToMessage: (messageId: number): void => { this.onReplyTap(messageId); },
      // 多选开着时，手动翻到的搜索结果加进已选（相册按整组，同长按选择的粒度）。
      onNavigatedResult: (messageId: number): void => {
        if (this.selection.active) {
          this.selection.selectRow(rowMembersContaining(
            this.timeline.groups.map((g: AlbumGroup): number[] => g.memberIds), messageId));
        }
      },
      cancelFlash: (): void => { this.flash.cancelFlash(); }
    });
    // 多选控制器接上宿主（B7）。chatTgsScrollActive 是取值器；
    // closeReactionSheet/setEmojiPanel 是伸到多选簇之外的页面子系统，仅由
    // enter() 触达。
    this.selection.bind({
      messages: (): MessageEntry[] => this.timeline.messages,
      chatTgsScrollActive: (): boolean => this.timeline.chatTgsScrollActive,
      closeReactionSheet: (): void => { this.overlayState.closeReactionSheet(); },
      setEmojiPanel: (show: boolean): void => { this.setEmojiPanel(show); },
      onActiveChange: (active: boolean): void => {
        this.timeline.groupsData.setLayoutContext(this.chatContentWidth, active, this.isGroup);
      }
    });
    this.timeline.groupsData.setLayoutContext(this.chatContentWidth, this.selection.active, this.isGroup);
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
      groups: (): AlbumGroup[] => this.timeline.groups,
      isTranslatable: (): boolean => this.isTranslatable,
      setIsTranslatable: (value: boolean): void => { this.isTranslatable = value; },
      driveVisibleWork: (): void => { this.timeline.driveVisibleWork(); },
      holdAnchor: (): void => { this.holdAnchorForTranslation(); },
      // 手指按着、或列表还在惯性里都算"在动"。listUserScrollActive 在列表停稳后
      // 还会保持 820ms（见 onFloatDateHidden 的说明）——对"等停下来再改布局"
      // 这个用途，滞后反而是优点：宁可晚一点落，也不要在惯性期改布局。
      listMoving: (): boolean => this.timeline.listTouchActive || this.timeline.listUserScrollActive,
      // 首个可见行的行号。驱动据此点名"在视口上方"的那几条——它们变高会把
      // 用户正在看的内容往下推，得直接落 + 靠补偿吃掉位移（见 util/translationAnchor）。
      visibleStartIndex: (): number => this.timeline.curStartIdx
    });
    this.timeline.prependChunker.bind({
      chunkRows: (): number => this.listCachedCount,
      // 跳转落地期间整份发布，不扣头部：目标行被扣着时 landPendingJump 按完整
      // 快照算出的下标指向的是另一条消息（真机 [JumpLand] 实测，判据见
      // util/jumpLandingOwner.chunkPrependAllowed）。
      allowed: (): boolean => chunkPrependAllowed(
        this.timeline.pageVisible && !this.timeline.initialMessageStageActive,
        this.pendingJumpId !== 0, this.jumpLandingHolding()),
      republish: (): void => {
        const target: AlbumGroup[] | null = this.timeline.prependChunker.latestTarget();
        if (target !== null && this.store !== null) {
          this.timeline.publishGroupsNow(target);
        }
      }
    });
    // 上一批点名（"这几条直接落、不做动画"）不该跨会话留着。
    clearTranslationInstant();
    // 停在最底下时译文/「翻译中」让行变高：行在变高的那一次刷新里叫这里钉底，
    // 气泡向上长（为什么现有的贴底跟随接不住，见 util/translationGrowthPin）。
    if (this.unregisterTranslationGrowthPin === null) {
      this.unregisterTranslationGrowthPin = registerTranslationGrowthPin((chatId: number): void => {
        this.pinBottomForTranslationGrowth(chatId);
      });
    }
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
    // 的唯一例外：这里把 this.getUIContext().getHostContext() 求值一次、闭包成常量传进去——
    // UIAbilityContext 在同一个 Ability 生命周期内本来就是稳定值，且任何会
    // 触发 picker 的用户操作都严格晚于这里（组件树先要 build 完，用户还要先
    // 手动点开附件抽屉）。uiContext 不具备这条"同生命周期内稳定"的依据，
    // 所以是逐次现取。pendingMedia/atBottom/diceSheetOpen/composerFocused/
    // draft/composerSending 等留页面的字段只经这里的取值器/回调读写，本类不
    // 存影子拷贝；overlayState 的四个 sheet 开关经 setSheet 转发，控制器之间
    // 不互相持有引用（B8 起立的规矩）。
    const attachContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
    this.attach.bind({
      sendAccess: this.sendAccess,
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
      setAtBottom: (value: boolean): void => { this.timeline.atBottom = value; },
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
      scroller: (): Scroller => this.timeline.scroller,
      groups: (): AlbumGroup[] => this.timeline.groups,
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
    const inputClient = getTdClient();
    this.inputSwitch.bind({
      active: (): boolean => this.timeline.pageVisible && this.appIsForeground && !this.viewerOpen() &&
        !this.recording.isRecording && !membershipLosesComposer(this.membershipState) &&
        this.chatId !== 0 && getTdClient() === inputClient,
      contextKey: (): number => this.chatId,
      emojiOpen: (): boolean => this.showEmojiPanel && !this.emojiPanelClosing,
      setEmoji: (show: boolean): void => {
        if (!show) {
          if (this.showEmojiPanel) {
            this.pendingImeBridgeFromEmoji = true;
          } else if (this.attachPanelOpen) {
            this.applyBottomSlot(closeSlot(this.bottomSlot, SLOT_ATTACH));
            this.startDrawerToImeBridge(SLOT_ATTACH);
          }
        }
        this.setEmojiPanel(show);
        this.pendingImeBridgeFromEmoji = false;
      },
      prepareEditor: (): void => { this.prepareComposerEditor(); },
      focusEditor: (): void => { focusControl.requestFocus('chat_composer'); }
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
    // this.getUIContext().getHostContext() 求值一次、闭包成常量传进去。beforeStart 打包
    // start()（原 startRecording）开头五条真连续的跨簇语句——
    // setEmojiPanel(false)/applyBottomSlot(closeSlot(...))/mention.clear()/
    // command.closePanel()/composerController.stopEditing()（原
    // 6218-6222 行，侦察报告 (B) 核实过真的连续）；紧接着的
    // `this.composerFocused = false;`（原 6223 行，页面自留字段，方案 6.9
    // 节裁决不进任何控制器）单独经 setComposerFocused 转发，不并入
    // beforeStart；afterSent 对应 finish()（原 finishRecording）发送成功后
    // 的 `this.timeline.atBottom = true;`（页面自留字段，跨簇写）。
    const recordingContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
    this.recording.bind({
      canSend: (): boolean => this.sendAccess.check('sendVoiceNotes'),
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
      afterSent: (): void => { this.timeline.atBottom = true; },
      // 与搬之前 start() 里那句 `new VoiceRecorder()` 逐字等价；开成宿主取值器
      // 只是为了让单测能注入一个可手动兑现的假录音器，把 recordingSeq 那道
      // 守卫钉住（理由写在 VoiceRecordingState 的接口上方）。
      newRecorder: (): VoiceRecorder => new VoiceRecorder()
    });
    // 媒体保存/下载簇接上宿主（B15）。context 同上一条的一次性求值例外。
    // findMsg/latestMessages 对应原文两种不同的"查消息"方式——
    // `this.timeline.messages.find(...)`/`this.timeline.messages` 本身，返回类型（null 还是
    // undefined）逐字保留，不合并成一个万能取值器（理由见 MediaSaveState.ets
    // 文件头）。
    //
    // 原来还有第三个 viewerEntry（= `this.entryById(this.viewer.viewerMsgId)`），
    // S2 删掉了：它是整簇唯一一条跨域读，改由调用方把 entry 传进
    // saveMediaEntry()。**这是删掉三种之一，不是把三种合并**，上面那条纪律
    // 仍然成立。
    const mediaSaveContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
    this.mediaSave.bind({
      context: (): common.UIAbilityContext => mediaSaveContext,
      store: (): MessageStore | null => this.store,
      chatId: (): number => this.chatId,
      findMsg: (messageId: number): MessageEntry | undefined =>
        this.timeline.messages.find((x: MessageEntry): boolean => x.id === messageId),
      latestMessages: (): MessageEntry[] => this.timeline.messages
    });
    // 成员资格状态机接上宿主（第二轮 R2-A 批）。isChannel 是双重用途取值器
    // （refresh() 的 supergroup 分支拿它当 is_channel 缺省回退值，
    // applyStatus() 拼 membershipStateOf 入参再读一次），两处都现取不缓存。
    // membershipState 按 B8 裁决留在页面，控制器只经 setMembershipState 写它。
    // client() 恒为 () => getTdClient()，是本批的注入缝（见
    // MembershipSession.ets 文件头【client() 注入缝】节）。本批一共两处刻意
    // 偏离逐字搬迁：这条缝，以及三条 logE 的前缀改名（见那边文件头）。
    this.membership.bind({
      setSendPermissions: (value: GroupPermissions): void => { this.sendAccess.update(value); },
      chatId: (): number => this.chatId,
      isChannel: (): boolean => this.isChannel,
      setMembershipState: (next: string): void => { this.membershipState = next; },
      setRestrictedUntil: (value: number): void => { this.membershipRestrictedUntil = value; },
      setIsGroup: (value: boolean): void => { this.isGroup = value; },
      setIsChannel: (value: boolean): void => { this.isChannel = value; },
      commitTimelineSnapshot: (): void => { this.timeline.commitTimelineSnapshot(); },
      setJoiningChat: (value: boolean): void => { this.joiningChat = value; },
      setJoinByRequest: (value: boolean): void => { this.joinByRequest = value; },
      onJoined: (folderId?: number): void => {
        this.showClientJoinNotice(this.isChannel);
        if (folderId !== undefined) { setInFolder(folderId, this.chatId, true); }
      },
      onJoinRequested: (): void => {
        showToast($r('app.string.cpp_join_requested'), 2000);
      },
      onJoinFailed: (): void => {
        showToast($r('app.string.cp_join_failed'), 2000);
      },
      closeComposerSurfaces: (): void => {
        this.setEmojiPanel(false);
        this.closeAttachPanel();
        this.applyBottomSlot(closeSlot(this.bottomSlot, SLOT_REPLY_KB));
        this.composerController.stopEditing();
        this.composerFocused = false;
        this.inline.clear();
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
    this.timeline.anchor.bind({
      scroller: (): Scroller => this.timeline.scroller,
      userScrollOffsetTotal: (): number => this.timeline.userScrollOffsetTotal,
      timelineScrollActive: (): boolean => this.timeline.timelineScrollActive,
      touchActive: (): boolean => this.timeline.listTouchActive,
      pendingJumpId: (): number => this.pendingJumpId,
      pendingScrollBottom: (): boolean => this.pendingScrollBottom,
      headerChromeHeight: (): number => this.headerChromeHeight(),
      // 整屏高度而不是 List 的实测高度——和 :1384 那处同一个取舍，
      // 这里只用来给"滑动中允许多大的修正"定一个数量级的尺。
      viewportHeight: (): number => this.screenH,
      appendGateProbe: (groups: AlbumGroup[]): string => this.appendAnchorGateProbe(groups)
    });
    // The navigation/build frame owns the main thread; chat stickers can start
    // only after the initial row gate has settled.
    this.timeline.chatTgsStageSettling = true;
    this.syncChatTgsGate();
    this.videoPrefetch.bind({
      client: (): TdClient => getTdClient(),
      videoAt: (messageId: number, _albumIndex: number): VideoRef | null => {
        const m = this.timeline.messages.find((e: MessageEntry): boolean => e.id === messageId);
        // GIF/动图走自己的自动播放路径，整份都会下，不归预取管。
        if (m === undefined || m.videoFileId === 0 || m.isAnimation) {
          return null;
        }
        // 预取查看器「自动」点开要播的那一档（多清晰度，见 util/entryVideoVariant）。
        const f = entryPrefetchFile(m, AppStorage.get<string>(KEY_CURRENT_NETWORK_TYPE) ?? 'other');
        return f !== null ? { fileId: f.fileId, fileSize: f.fileSize, local: f.local } : null;
      },
      // store 还没就绪就当作已被认领：宁可不预取，也别夹了别人的下载。
      // 查看器当前那条的视频也算已认领：它的流式下载走 VideoStreamSession 自己的
      // downloadFile，不经过 MessageStore 的归属集合，光靠 store 判不出来。
      fileClaimed: (fileId: number): boolean =>
        (this.store?.isVideoFileClaimed(fileId) ?? true) ||
        this.timeline.messages.some((e: MessageEntry): boolean =>
          e.id === this.viewer.viewerMsgId && entryOwnsVideoFile(e, fileId)),
      subscribeEnabled: subscribeVideoPreload,
      subscribeNetwork: subscribeNetworkType,
      network: (): string => AppStorage.get<string>(KEY_CURRENT_NETWORK_TYPE) ?? 'other',
      powerSaving: (): boolean => powerSavingActive()
    });
    this.playSlot.bind({
      // 按小窗实际要下的那一档算（多清晰度：有低清档的大视频不该被原片大小挡掉）。
      sizeAllowed: (messageId: number): boolean => autoplaySizeAllowed(
        entryInlineSize(this.findMsg(messageId)), AppStorage.get<number>(KEY_AUTOPLAY_MAX_MB) ?? 0),
      viewerMsgId: (): number => this.viewer.viewerMsgId,
      pageVisible: (): boolean => this.timeline.pageVisible,
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
    initVideoPosterStore((this.getUIContext().getHostContext() as common.UIAbilityContext).cacheDir);
    this.nowSec = Math.floor(Date.now() / 1000);
    // 首帧 build 前即同步填入账号默认壁纸快照，避免 aboutToAppear → onReady 之间发生二次壁纸切换。
    this.chatBg = defaultChatBackgroundSnapshot(
      darkResourceMode(this.getUIContext().getHostContext() as common.UIAbilityContext)
    );
    // 日期条隐藏的那一刻 listUserScrollActive 必须跟着翻假——原来它和显隐写在
    // 同一个定时器体里，定时器下沉之后靠这个回调保住同一时刻。
    this.timeline.floatDateState.setOnHidden((): void => { this.timeline.onFloatDateHidden(); });
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
    // 系统分享送进来的内容。**必须放在这里，不能放进 resolveRouteAndResetSession**
    // ——那一步跑在 createMessageStore 之前，那时 this.store 还是 null（或上一个
    // 会话的），载荷会被取走又丢掉，现象就是"点了分享只进会话、什么都没有"。
    if (ctx.sharePending) {
      this.consumeSharedContent();
    }
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
    this.openTopicBar();
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
      this.musicQueue.onCompleted(this.timeline.messages, messageId);
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
      // 本地那份先顶上（同步、无往返），服务端的再回来补（restoreServerDraft
      // 里本来就有"本地非空就不覆盖"的判断）。
      const local: string = localDraft(this.chatId);
      if (local !== '') {
        this.draft = local;
      }
      this.restoreServerDraft();
    }

    this.search.seedFromRoute(route.searchQuery, route.startSearch, jumpTo !== undefined ? jumpTo : 0);
    this.shareAutoSend = route.shareAutoSend;
    const ctx: RouteApplyContext = { jumpTo: jumpTo, sharePending: route.sharePending };
    return ctx;
  }

  // 系统分享送进来的内容落到本会话。**取走式**：ShareInbox 里那份是一次性的，
  // 取过就没了——否则回退再进同一个会话会把同一批图再放一遍。
  private consumeSharedContent(): void {
    const store: MessageStore | null = this.store;
    if (store === null) {
      // **不能在这之前 takePendingShare()**：取走是破坏性的，store 还没建好时
      // 取了就等于把这次分享丢了（真机复现过）。
      logW('[Share] chat page not ready, leaving payload for the next attempt');
      return;
    }
    const payload: SharedPayload | null = takePendingShare();
    if (payload === null) {
      return;
    }
    logI(`[Share] staging into chat ${this.chatId}: ` +
      `${payload.media.length} media, caption ${payload.caption.length}ch`);
    // 实况照片的动态部分要现去媒体库取（秒级），所以整条落地是异步的。
    // 取不到就原样按静图发，见 util/shareLivePhoto。
    upgradeLivePhotos(this.getUIContext().getHostContext() as common.Context, payload)
      .then((upgraded: UpgradedShare): void => {
        this.stageSharedPayload(upgraded, store);
      }).catch((e: Object): void => {
        logE(`[Share] live photo upgrade failed: ${e}`);
        this.stageSharedPayload(
          { payload: payload, geometry: new Map<string, ShareMediaGeometry>() }, store);
      });
  }

  // 真正把分享落到输入框/发送链上。决策在 util/shareStaging（纯函数、有单测），
  // 这里只是把页面的几个落点接上去。
  private stageSharedPayload(upgraded: UpgradedShare, store: MessageStore): void {
    if (this.shareAutoSend) {
      this.sendSharedDirectly(upgraded, store);
      return;
    }
    this.stageSharedPayloadInComposer(upgraded, store);
  }

  // 分享落地要用到的页面能力。两档共用一份。
  private shareHost(store: MessageStore): ShareArrivalHost {
    return {
      checkPermissions: (payload: SharedPayload): Promise<void> => store.checkSharePermissions(payload),
      appendMedia: (items: MediaSendItem[]): number => {
        const merged: PendingMediaAppend = appendPendingMedia(this.pendingMedia, items);
        this.pendingMedia = merged.items;
        return merged.dropped;
      },
      setDraft: (text: string): void => { this.draft = text; },
      draftText: (): string => this.draft,
      sendDocument: (path: string, caption: string): Promise<void> => store.sendDocumentAsync(path, caption),
      sendAudio: (path: string, caption: string): Promise<void> => store.sendAudioAsync(path, caption),
      sendMedia: (items: MediaSendItem[], caption: string): Promise<void> =>
        store.sendMedia(items, caption),
      sendText: (text: string): Promise<void> => store.sendAsync(text),
      scrollToBottom: (): void => { this.timeline.atBottom = true; }
    };
  }

  // 「直接发送」那一档（分享面板上选的，见 util/shareSendMode）：不落输入框，
  // 当场发出去，然后把应用退回后台——用户人还在图库里，看到的是"闪了一下"。
  //
  // 失败留在前台，由服务只把未确认发送的内容交回选择器，避免自动重发文件。
  private sendSharedDirectly(upgraded: UpgradedShare, store: MessageStore): void {
    const host: ShareArrivalHost = this.shareHost(store);
    sendDirectShareWithRecovery(upgraded, host, (): boolean => this.store === store).then((sent: boolean): void => {
      if (!sent) { return; }
      showToast(str('share_sent_to', this.header.titleTextOf()), 1600);
      // 请求已被 TDLib 收下，上传在后台继续（dataTransfer 长时任务）。
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      ctx.moveAbilityToBackground().catch((e: Object): void => {
        // 退不回去不算失败，消息已经发出去了，用户留在会话里也说得通。
        logW(`[Share] moveAbilityToBackground failed: ${e}`);
      });
    });
  }

  private stageSharedPayloadInComposer(upgraded: UpgradedShare, store: MessageStore): void {
    stageShareWithPermissions(upgraded, this.shareHost(store), this.pendingMedia.length,
      (): boolean => this.store === store);
  }

  // 会话重置决策。结果留在 routeResumeWaiting 字段上——拆分前它是 applyRouteParams
  // 的局部量 scrollResumeWaiting，既被消息回调读写，也被 store.open 的分支读。
  private resetOrPreserveScrollSession(): void {
    this.routeResumeWaiting = this.resumeScrollPending &&
      this.resumeScrollChatId === this.chatId &&
      this.resumeScrollThreadId === conversationScopeId(
        this.threadRootId, this.forumTopicId, this.directMessagesTopicId) &&
      this.timeline.groups.length > 0;
    if (!this.routeResumeWaiting) {
      this.resumeScrollPending = false;
      this.resetScrollSession();
      this.resetComposerSession();
      this.resetMessageActionSession();
    } else {
      // Old rows remain visible until the replacement page has arrived. Clear
      // transient overlays/actions, but preserve the captured viewport.
      this.timeline.scrollActionSeq++;
      this.jumpLayoutSeq++;
      this.pendingJumpId = 0;
      this.clearPendingScrollBottom('pageShowResume');
      this.scrollToBottomBusy = false;
      this.timeline.didInitialScroll = true;
      this.timeline.clearFloatingDate();
    }
  }

  // 阶段 A（后半）：聊天级订阅与两个 setInterval。四个子阶段的相对顺序即原文顺序。
  private registerChatLevelSubscriptions(): void {
    this.subscribeChatLevelUpdates();
    this.subscriptions.set('selectionDeleted', getTdClient().onUpdate('updateDeleteMessages',
      (update: TdObject): void => { this.selection.applyDeletion(this.chatId, update); }));
    this.startChatBackgroundStore();
    this.subscribeMembershipUpdates();
    this.subscribeLiveCallUpdatesAndTimers();
  }

  private subscribeChatLevelUpdates(): void {
    this.unreadMentions.open({ chatId: this.chatId, threadRootId: this.threadRootId,
      forumTopicId: this.forumTopicId, directMessagesTopicId: this.directMessagesTopicId }, {
      send: (request: TdRequest): Promise<TdObject> => getTdClient().send(request, 12000),
      subscribeCount: (listener: (count: number) => void): (() => void) =>
        getChatStore().subscribeChat(this.chatId, (): void => {
          listener(getChatStore().entryOf(this.chatId)?.unreadMentionCount ?? 0);
        }),
      onUpdate: (type: string, listener: (update: TdObject) => void): (() => void) =>
        getTdClient().onUpdate(type, listener),
      active: (): boolean => this.timeline.pageVisible && this.appIsForeground && !this.viewerOpen() &&
        this.pendingJumpId === 0 && !this.scrollToBottomBusy && !this.search.mode && !this.showEmojiPanel,
      jump: (messageId: number): void => this.onReplyTap(messageId),
      failed: (): void => { showToast($r('app.string.cp_cannot_jump'), 1500); }
    });
    this.header.refresh();
    this.subscriptions.set('chatAction', getTdClient().onUpdate('updateChatAction',
      (u: TdObject): void => this.typing.onChatAction(u)));
    this.subscriptions.set('chatActionUser', getTdClient().onUpdate('updateUser',
      (u: TdObject): void => this.typing.onUserUpdate(u)));
    this.subscriptions.set('chatActionNewMsg', getTdClient().onUpdate('updateNewMessage',
      (u: TdObject): void => this.typing.onNewMessage(u)));
    this.subscriptions.set('chatAutoDelete', getTdClient().onUpdate('updateChatMessageAutoDeleteTime',
      (u: TdObject): void => this.header.onAutoDeleteUpdate(u)));
    // 会话已经开着时，navigateToChat 只出栈不传参，跳转目标走旁路送进来
    // （issue #80、#102，见 util/chatJumpChannel 的说明）。
    this.subscriptions.set('jump', subscribeChatJump(this.chatId,
      (messageId: number): void => { this.jumpToMessageId(messageId); }));
    // ForwardSheet subscribes to the chat list itself while it is open, so this
    // no longer has to push updates into it.
    // 主列表订阅**不能删**：返回键上的未读徽标是「其他会话的未读总数」，要靠主列表
    // 里任何一个会话的变化来刷新。
    this.subscriptions.set('chat', getChatStore().subscribe(() => {
      this.header.refresh();
      this.syncActionBar();
    }, 'main'));
    // 另外盯本会话：归档里、或还不在任何列表里的会话，上面那条收不到它自己的更新
    // ——陌生人私聊的操作条（updateChatActionBar 在进会话之后才补发）因此出不来，
    // 标题栏也不刷新。见 ChatStore.subscribeChat。
    this.subscriptions.set('chatSelf', getChatStore().subscribeChat(this.chatId, () => {
      this.header.refresh();
      this.syncActionBar();
    }));
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
      (): boolean => darkResourceMode(this.getUIContext().getHostContext() as common.UIAbilityContext)
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
      this.timeline.chatBackgroundRevision++;
    }));
    this.bgStore.open(this.chatId);
  }

  private subscribeMembershipUpdates(): void {
    const client: TdClient = getTdClient();
    this.subscriptions.set('membershipPermissions', client.onUpdate('updateChatPermissions', (u: TdObject): void => {
      if (client === getTdClient()) { this.membership.applyChatPermissions(u); }
    }));
    this.subscriptions.set('membershipSupergroup', client.onUpdate('updateSupergroup', (u: TdObject) => {
      if (client !== getTdClient()) { return; }
      const supergroup = u['supergroup'] as TdObject | undefined;
      if (supergroup !== undefined &&
        ((supergroup['id'] as number | undefined) ?? 0) === this.membership.supergroupId()) {
        this.membership.applySupergroup(supergroup);
      }
    }));
    this.subscriptions.set('membershipBasicGroup', client.onUpdate('updateBasicGroup', (u: TdObject) => {
      if (client !== getTdClient()) { return; }
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
      (isSplitByBreakpoint(this.widthBp, this.heightBp, this.forceSingleColumn, this.windowPortrait) || hasPrefetchedPage(this.chatId))
        ? 0 : INITIAL_MESSAGE_TRANSITION_SETTLE_MS);
    this.store = store;
    if (!this.routeResumeWaiting || this.timeline.groups.length === 0) {
      this.timeline.messageLoadState = 'loading';
      this.syncComposerSlot();
    }
    return store;
  }

  // 阶段 B：messages 订阅的回调体。store 逐层按参数传递（而不是读 this.store），
  // scheduleNewerTailRefresh 里的 this.store === store 身份判定要靠它。
  private onMessagesSnapshot(store: MessageStore, list: MessageEntry[]): void {
    const historyState: string = store.getInitialHistoryState();
    this.timeline.olderLoadState = store.getOlderLoadState();
    this.timeline.newerLoadState = store.getNewerLoadState();
    if (!(this.routeResumeWaiting && this.timeline.groups.length > 0 && historyState === 'loading')) {
      this.timeline.messageLoadState = historyState;
      this.syncComposerSlot();
      this.timeline.messageLoadError = store.getInitialHistoryError();
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
    const fragment: boolean = isResumeFragment(this.timeline.groups.length, list.length);
    if (this.routeResumeWaiting && (list.length === 0 || fragment)) {
      return;
    }
    const notifyKind: string = store.getCurrentNotifyKind();
    const maxId: number = list.length > 0 ? list[list.length - 1].id : 0;
    const groups: AlbumGroup[] = this.groupsWithClientJoinNotice(list);
    const resumeLandingPrepared: boolean = this.resolveResumeLandingChoice(store, groups);
    const firstMessageStage: boolean = !this.routeResumeWaiting && this.timeline.groups.length === 0 &&
      (resumeLandingPrepared || !this.timeline.didInitialScroll);
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
    if (this.timeline.didInitialScroll && list.length > 0) {
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
    if (!this.routeResumeWaiting && !this.timeline.didInitialScroll && this.pendingResumeId > 0) {
      const rememberedId: number = this.pendingResumeId;
      const rememberedIndex: number = groupIndexOf(groups, rememberedId);
      if (store.isResumeLandingSelected() && rememberedIndex >= 0) {
        this.timeline.didInitialScroll = true;
        this.timeline.atBottom = false;
        this.pendingJumpId = rememberedId;
        this.timeline.resumeDividerId = groups[rememberedIndex].head.id;
        this.timeline.resumeDividerItemY = this.pendingResumeItemY;
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
    const olderPageGrowth: boolean = notifyKind === 'older' && list.length > this.timeline.messages.length;
    // 前插锚点（prime / retry / reposition）**默认整个不做**：位置由 splice 发布 +
    // maintainVisibleContentPosition 保住（util/splicePublish 文件头有真机对照）。
    // 两个常量必须同向：splice 关掉时锚点必须回来，否则重演"翻页自激灌到最老"。
    const anchorSuppressed: boolean = !PREPEND_ANCHOR_ENABLED && SPLICE_PUBLISH_ENABLED;
    if (!anchorSuppressed && shouldCapturePrependAnchor({
      didInitialScroll: this.timeline.didInitialScroll,
      anchorIndexFresh: this.timeline.anchorIndexFresh(),
      olderPageGrowth: olderPageGrowth
    })) {
      const visibleIndex: number = this.timeline.curStartIdx;
      if (visibleIndex >= 0 && visibleIndex < this.timeline.groups.length) {
        const y: number = this.timeline.anchorItemY(visibleIndex);
        // 量不到就整个不记锚点：宁可不补，也不要拿一个假 0 去算 dy
        // （见 anchorItemY 的说明）。
        if (!Number.isNaN(y)) {
          prependAnchorId = this.timeline.groups[visibleIndex].head.id;
          prependAnchorY = y;
          prependAnchorUserOffset = this.timeline.userScrollOffsetTotal;
          primePrependAnchor = shouldPrimePrependAnchor(
            visibleIndex, y, this.headerChromeHeight(), this.timeline.listTouchActive,
            this.timeline.timelineScrollActive);
          this.timeline.anchor.captureAnchorOffset();
        } else {
        }
      } else {
      }
    } else if (olderPageGrowth && this.timeline.didInitialScroll) {
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
    // 它原来是 `!this.timeline.atBottom`——那问的是另一件事（"用户此刻在不在会话实时
    // 尾部"），而 atBottomVerdict 里带着 !hasMoreNewer，于是向下翻页的整个
    // 过程中恒为真、闸恒开，每一次追加都把视口按回锚点。那正是真机上"进会话
    // 落在中间之后持续闪、滑不动、↓ 按不下去"的动力来源。
    let appendAnchorId: number = 0;
    let appendAnchorY: number = 0;
    let appendAnchorUserOffset: number = 0;
    const appendsRows: boolean = appendBreaksAnchor(this.timeline.groups, groups);
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
      didInitialScroll: this.timeline.didInitialScroll,
      prependAnchorHeld: prependAnchor.id !== 0,
      appendBreaksAnchor: appendsRows,
      atLiveTail: this.timeline.atBottom,
      scrollIntentPending: this.pendingJumpId !== 0 || this.pendingScrollBottom ||
        this.jumpLandingHolding()
    });
    if (holdAppendAnchor && this.timeline.anchorIndexFresh()) {
      const visibleIndex: number = this.timeline.curStartIdx;
      const y: number = visibleIndex >= 0 && visibleIndex < this.timeline.groups.length
        ? this.timeline.anchorItemY(visibleIndex) : Number.NaN;
      if (!Number.isNaN(y)) {
        appendAnchorId = this.timeline.groups[visibleIndex].head.id;
        appendAnchorY = y;
        appendAnchorUserOffset = this.timeline.userScrollOffsetTotal;
        this.timeline.anchor.captureAnchorOffset();
      }
    } else if (appendsRows && prependAnchor.id === 0 && this.timeline.didInitialScroll) {
      // 闸关上时也留一条：判读时要能看见「这一次追加本来会不会复位」。与 hold
      // 那条同格式，随探针一起删。
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
    this.timeline.messages = list;
    this.timeline.messageListRevision++;
    this.reconcileMessageActionTargets(list);
    this.timeline.visibleGroupCount = groups.length;
    this.syncComposerSlot();
    if (this.viewer.viewerMsgId !== 0 &&
      list.findIndex((m: MessageEntry): boolean => m.id === this.viewer.viewerMsgId) < 0) {
      this.closeViewer();
    }
    if (firstMessageStage) {
      this.timeline.publishInitialMessageGroups(groups);
    } else {
      this.timeline.publishMessageGroups(groups);
    }
    if (firstMessageStage && groups.length === 0) {
      // There is no bubble that can drive the coordinated presentation.
      // Reveal the resolved empty/error surface now. Non-empty histories are
      // released only by scheduleInitialTimelinePresentation(), keeping the
      // header, composer, and first real bubble in the same render frame.
      this.timeline.cancelInitialMessageTransitionSettle();
      this.timeline.initialMessageTransitionSettled = true;
    } else if (!firstMessageStage && !this.timeline.initialMessageTransitionSettled &&
      !this.timeline.initialMessageStageActive) {
      // Message-link/search/thread entries set didInitialScroll before their
      // around-target history arrives because pendingJumpId owns positioning.
      // They intentionally bypass bottom/unread staging, so they also need a
      // direct presentation completion path. Release chrome in the same
      // state publication as the resolved timeline (including an empty/error
      // result) without issuing another scroll that could override the jump.
      this.timeline.cancelInitialMessageTransitionSettle();
      this.timeline.initialMessageTransitionSettled = true;
    }
    // 翻译和媒体窗口原来只挂在 onScrollIndex 上 —— 进页面不滑动就永远不
    // 触发（用户报的"这个页面不会自动翻译"），新消息到达也一样。数据一变
    // 就按当前视口驱动一次；curStartIdx/curEndIdx 在首帧前是 -1，此时用
    // 首屏兜底，滑动事件来了会立刻纠正。
    // 首屏逐行放行时不要每一行都驱动翻译、媒体窗口和播放位；这些旁路
    // 状态会回流到 ChatPage，抵消分帧首屏的收益。首屏稳定后由最终发布或
    // presentation callback 统一驱动一次。
    if (!firstMessageStage || !this.timeline.initialMessageStageActive) {
      this.timeline.driveVisibleWork();
    }
    this.timeline.fillViewportIfNeeded();
    this.musicQueue.settlePending(list);
  }

  private restoreCapturedAnchors(prependAnchor: PrependAnchorSample,
    appendAnchor: AppendAnchorSample): void {
    // 复位跑在发布之后：this.timeline.groups 此刻已经是新快照，按消息 id 找得到锚点行
    // 的新下标。restorePrependAnchor 内部是一个 setTimeout(0) + 代次守卫，
    // 跳转/贴底这些更强的定位意图会把它作废。
    if (prependAnchor.id > 0) {
      this.timeline.anchor.restorePrependAnchor(
        this.timeline.groups, prependAnchor.id, prependAnchor.y, prependAnchor.userOffset,
        prependAnchor.prime);
    } else if (appendAnchor.id > 0) {
      // 复位走的是和向上那侧同一个 restoreScrollAnchor：setTimeout(0) + 代次
      // 守卫，跳转/贴底这些更强的定位意图会把它作废。
      this.timeline.anchor.restoreAppendAnchor(
        this.timeline.groups, appendAnchor.id, appendAnchor.y, appendAnchor.userOffset);
    }
  }

  private applyResumeLanding(list: MessageEntry[], groups: AlbumGroup[],
    maxId: number): boolean {
    let positionHandled: boolean = false;
    if (this.routeResumeWaiting && list.length > 0) {
      this.routeResumeWaiting = false;
      this.resumeScrollPending = false;
      this.timeline.didInitialScroll = true;
      this.lastMaxId = maxId;
      this.timeline.firstUnreadId = 0;
      this.timeline.stayAtUnread = false;
      positionHandled = true;
      if (this.resumeScrollAtBottom) {
        this.timeline.atBottom = false;
        const actionSeq: number = ++this.timeline.scrollActionSeq;
        this.timeline.glueBottom('L1153');
        setTimeout((): void => {
          if (actionSeq === this.timeline.scrollActionSeq) {
            this.timeline.glueBottom('L1156');
            this.timeline.refreshAtBottom();
          }
        }, 60);
      } else {
        const resumeIndex: number = groupIndexOf(groups, this.resumeScrollMessageId);
        this.timeline.atBottom = false;
        if (resumeIndex >= 0) {
          this.timeline.anchor.restoreScrollAnchor(resumeIndex, this.resumeScrollItemY);
        } else {
          this.timeline.glueBottom('L1166');
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
    // 机器人 '/' 指令按钮已不在输入框内常驻展示，命令目录改为用户输入 '/' 触发 refreshCommands() 时按需加载。
  }

  // 四条落点分支的互斥链：resume 已定位 / 首屏落点 / 新消息跟随 / 原地增高贴底。
  // if / else-if 结构原样保留，只把两条长分支的方法体搬进各自的方法。
  private applyInitialOrFollowLanding(list: MessageEntry[], groups: AlbumGroup[],
    maxId: number, notifyKind: string, positionHandled: boolean, fillPending: boolean): void {
    if (!positionHandled && !this.timeline.didInitialScroll && list.length > 0) {
      this.applyFirstScreenLanding(list, groups, maxId, fillPending);
    } else if (!positionHandled && this.timeline.didInitialScroll && maxId > this.lastMaxId) {
      this.followNewTailIfAtBottom(maxId, notifyKind);
    } else if (this.timeline.didInitialScroll && (this.timeline.atBottom || this.timeline.bottomFollowPending) &&
      !this.timeline.stayAtUnread && !this.viewerOpen()
      && (this.store === null || !this.store.getHasMoreNewer())) {
      // In-place content growth (thumbnails, reply quotes, forward headers
      // filling in async) changes row heights; when the user is at the
      // bottom, stay glued there instead of letting the tail drift. Never
      // glue while unloaded newer pages exist — being at the window's edge
      // there is NOT the live tail, and gluing chain-loads every page.
      // Also never move the underlying list while the media viewer is open.
      this.scheduleBottomAfterLayout('L1252');
    }
  }

  private applyFirstScreenLanding(list: MessageEntry[], groups: AlbumGroup[],
    maxId: number, fillPending: boolean): void {
    // First real page: jump to the first unread message (Android-style);
    // fully-read chats land at the bottom. (Never anchor on
    // last_read_inbox_message_id here — it only tracks incoming messages,
    // so with an outgoing tail it points at a stale mid-history position.)
    this.timeline.didInitialScroll = true;
    this.lastMaxId = maxId;
    const fu: number = this.store !== null ? this.store.getFirstUnreadId() : 0;
    // 落点判定在 util/initialAnchor（6 条测），两个分支各自的理由写在那里。
    const anchor: InitialAnchor = initialAnchorOf(
      fu, fu > 0 ? groupIndexOf(groups, fu) : -1,
      (index: number): number => groups[index].head.id);
    this.timeline.firstUnreadId = anchor.dividerId;
    // 首屏定位的落点诊断。**未读分支原来一条日志都没有**，只有底部分支
    // 打 glueBottom，于是"没跳到未读"和"压根没落定"在日志上长得一模一样，
    // 排查时分不开——正是这次浪费掉一轮的原因。
    // 方向一（进会话落在中间）的落点侧证据：这里说的是"选了哪条落点路径"，
    // 而 hasMoreNewer 说的是"贴的是已加载窗口的底还是真尾部"——两者要一起
    // 看才分得清"没跳到未读"和"跳到了但窗口本身没够到尾部"。
    const anchorHasMoreNewer: boolean =
      this.store !== null && this.store.getHasMoreNewer();
    const landSeq: number = this.timeline.scrollActionSeq;
    setTimeout((): void => {
      if (landSeq !== this.timeline.scrollActionSeq) {
        return;
      }
    }, 400);
    if (anchor.kind === ANCHOR_UNREAD) {
      // 两个标志必须一起动，各自挡一个已经发生过的问题，见 util 里的说明。
      this.timeline.atBottom = false;
      this.timeline.stayAtUnread = anchorLatchesBottom(anchor);
      // The initial-message performance path has only just published
      // placeholder rows here. An immediate scroll alone can be swallowed
      // before List layout; beginInitialUnreadLanding reissues it after the
      // real anchor row is laid out and recomputes the index after backfill.
      this.timeline.beginInitialUnreadLanding();
    } else {
      this.timeline.glueBottom('L1220');
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
    }
    // 新消息到达且最后一条已在底部可见：跟随，并解除未读闩。闩防的是缩略图
    // 这类原地通知把分界线贴底滑走（下面那一支仍受它约束）；新消息把内容往上
    // 顶是官方行为，不该被它挡住——真机日志：atBottom=true stayAtUnread=true 不跟随。
    if (notifyKind === 'update' &&
      bottomFollowShouldSchedule(this.timeline.atBottom, this.timeline.bottomFollowPending, this.viewerOpen())) {
      this.timeline.stayAtUnread = false;
      this.scheduleBottomAfterLayout('L1242');
    }
  }

  private scheduleBottomAfterLayout(tag: string): void {
    const seq: number = ++this.timeline.bottomLayoutFollowSeq;
    this.timeline.bottomFollowPending = true;
    setTimeout((): void => {
      const superseded: boolean = seq !== this.timeline.bottomLayoutFollowSeq;
      if (!superseded) {
        // 被取代的那次不清标志：标志归最新的那次排期管。
        this.timeline.bottomFollowPending = false;
      }
      // **点火时不问 atBottom**：它翻假正是这次追加造成的——新行落在视口下方，
      // isAtEnd() 立刻变假——恰恰是要跟随的那件事。原来这里多一个
      // `!this.timeline.atBottom`，真机上全程没有一条 apply tag=L1242，视口卡在 31 行、
      // 行数涨到 42（用户："消息在最底下，但是不会往上顶消息列表了"）。
      if (!bottomFollowShouldApply({
        superseded: superseded,
        touchActive: this.timeline.listTouchActive,
        scrollActive: this.timeline.timelineScrollActive,
        viewerOpen: this.viewerOpen(),
        hasMoreNewer: this.store !== null && this.store.getHasMoreNewer(),
        jumpLanding: this.jumpLandingHolding()
      })) {
        if (!superseded) {
        }
        return;
      }
      this.timeline.glueBottom(tag);
      setTimeout((): void => {
        if (seq === this.timeline.bottomLayoutFollowSeq) {
          this.timeline.refreshAtBottom();
        }
      }, 60);
    }, 32);
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
      this.timeline.atBottom = true;
      const actionSeq: number = this.timeline.scrollActionSeq;
      const probeSeq: number = this.jumpLatestSeq;
      logW(`[JumpLatest] #${probeSeq} publish consume call=scrollEdge` +
        ` rows=${groups.length} list=${list.length} ${this.scrollStateProbe()}`);
      this.timeline.glueBottom('L1263');
      setTimeout(() => {
        if (actionSeq !== this.timeline.scrollActionSeq) {
          logW(`[JumpLatest] #${probeSeq} publish settle stale actionSeq=${actionSeq}` +
            ` cur=${this.timeline.scrollActionSeq}`);
          return;
        }
        this.timeline.glueBottom('L1266');
        this.timeline.refreshAtBottom();
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
          this.timeline.refreshAtBottom();
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
        const itemY: number = jumpTargetId === this.timeline.resumeDividerId
          ? this.timeline.resumeDividerItemY : 0;
        // 回到上次阅读位置按记下的行内偏移原样恢复；其余（@提及、引用、置顶、
        // 搜索结果、消息链接……）一律居中。按行比，见 util/jumpAlign。
        const resumeRow: number = this.timeline.resumeDividerId > 0
          ? groupIndexOf(groups, this.timeline.resumeDividerId) : -1;
        const resume: boolean = isResumeLanding(jg, resumeRow);
        this.pendingJumpId = 0;
        // 落地宽限从**此刻**起算（issue #51）：原来只在点击时上了 900ms，目标不在
        // 窗口里要先 loadAround，慢链路上一超时，刚压进返回栈的那层就被
        // syncReturnState 当成"手动滑过"弹掉了。
        this.jumpLandingUntil = Date.now() + JUMP_LANDING_GRACE_MS;
        // 异步落地这条路才是被抢的那条：pendingJumpId 上一行刚清零，所有
        // 「让路给跳转」的判据同时失效（util/jumpLandingOwner 文件头）。
        this.beginJumpLanding();
        this.topCard.finishPinnedJump();
        if (resume) {
          this.timeline.scrollToTimelineIndexAtY(jg, itemY);
        } else {
          this.timeline.scrollToJumpTarget(jg);
        }
        // loadAround 可能整片换掉窗口（list RELOAD）——立刻发出的那次滚动会在
        // 新行布局之前被吞掉。
        // 【2026-09-22 更正】原文写的是 "replaces the window wholesale"，**不对**：
        // around 页默认是**合进**现有窗口的，只有它和窗口断开时才换窗口
        // （issue #213，判据见 util/historyWindowJoin）。这句错注释很可能就是
        // 当初没给 around 补那道连续性检查的原因。
        // Re-issue once layout settles (index recomputed: prepends may have
        // shifted it) and flash after that.
        const jumpSeq: number = ++this.jumpLayoutSeq;
        setTimeout(() => {
          if (jumpSeq !== this.jumpLayoutSeq) {
            return;
          }
          const jg2: number = groupIndexOf(this.timeline.groups, jumpTargetId);
          if (jg2 >= 0) {
            if (resume) {
              this.timeline.scrollToTimelineIndexAtY(jg2, itemY);
            } else {
              this.timeline.scrollToJumpTarget(jg2);
            }
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
      this.timeline.didInitialScroll = true;
      this.pendingJumpId = jumpTo;
      store.open(jumpTo);
    } else if (this.threadRootId > 0) {
      // Comment thread: start at the TOP — the root post — not the newest reply.
      this.timeline.didInitialScroll = true;
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

  private interceptKeyboardDismiss(event: TouchEvent): HitTestMode {
    if (event.type !== TouchType.Down || this.keyboardH <= 0 || !this.composerFocused) {
      return HitTestMode.Default;
    }
    const area: Area | undefined = this.composerEditorArea;
    const touches: TouchObject[] = event.changedTouches.length > 0 ? event.changedTouches : event.touches;
    if (area === undefined || touches.length === 0) { return HitTestMode.Default; }
    // Area.globalPosition 与 windowX/windowY 都是窗口内 vp 坐标，适用于分栏与自由窗口。
    const top: number = Number(area.globalPosition.y);
    const height: number = Number(area.height);
    if (!Number.isFinite(top) || !Number.isFinite(height) || height <= 0) {
      return HitTestMode.Default;
    }
    const touch: TouchObject = touches[0];
    // 【判据按 y 轴，不再按编辑框矩形】底栏上除了输入框还有附件、表情、发送这些
    // 按钮：它们的中心和编辑框同一条水平带，可横向就在编辑框之外。原来只认编辑框
    // 矩形，于是键盘立着时点发送是"第一下收键盘、第二下才发"，点表情/附件同理。
    // 现在：编辑行上沿往上留一条容差，容差以下整条底栏都放行；容差以上（消息
    // 列表、顶栏）才收键盘并拦截。容差 16vp 盖住比编辑框更高的圆钮（46vp）。
    if (touch.windowY >= top - COMPOSER_TAP_BAND_TOLERANCE) {
      return HitTestMode.Default;
    }
    this.composerController.stopEditing();
    this.composerFocused = false;
    // 在 DOWN 的命中测试阶段阻断子树；这整次触摸都不会交给菜单、媒体或按钮。
    // 不在冒泡 onTouch/onClick 中收键盘，避免子节点已经响应或收起后 UP 穿透。
    return HitTestMode.Block;
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
    // 只有"按下时键盘已经立着"的手势才允许滑动收键盘。长按头像 @ 会在按住
    // 期间 requestFocus，键盘刚升起就撞上 IME 贴底滚动产生的 onScrollStart，
    // 这里若只看 listTouchActive 就会把刚升起的键盘收掉（闪烁）。
    if (!this.timeline.listTouchActive || this.keyboardH <= 0 ||
      !this.timeline.keyboardWasUpAtTouchDown()) {
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
    if (this.timeline.initialMessageStageActive || store === null ||
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
      if (this.timeline.initialMessageStageActive || currentStore === null ||
        currentStore.getInitialHistoryState() === 'loading' || currentStore.isInitialFillPending()) {
        return;
      }
      this.composerEditorReady = true;
    }), INITIAL_MESSAGE_RELEASE_DELAY_MS);
  }

  private clearViewportResizeSettleTimer(): void {
    if (this.viewportResizeSettleTimer !== -1) {
      clearTimeout(this.viewportResizeSettleTimer);
      this.viewportResizeSettleTimer = -1;
    }
  }

  private onViewportResizeFrame(): void {
    this.timeline.pauseForViewportResize();
    if (this.viewportResizeSettleTimer !== -1) {
      clearTimeout(this.viewportResizeSettleTimer);
    }
    this.viewportResizeSettleTimer = setTimeout((): void => {
      this.viewportResizeSettleTimer = -1;
      this.timeline.resumeAfterViewportResize();
      if (this.keyboardH <= 0 && this.emojiDrawer.shellHeight <= 0 &&
        !this.drawerClosingToIme && !this.emojiDrawer.closingImeToDrawer) {
        if (this.imeTailPinned) {
          this.imeTailPinned = false;
          this.timeline.driveVisibleWork();
        }
      }
    }, 150);
  }

  private prepareComposerEditor(): void {
    // Automatic mounting remains outside the transition-critical path, but a
    // user tap always wins over that scheduler. Replace the text shell now and
    // focus the real TextArea on the next task, after its keyed node exists.
    if (!this.composerEditorReady) {
      this.composerMountSeq++;
      this.composerMountScheduled = false;
      this.composerEditorReady = true;
    }
    // An early user tap must never wait for the coordinated visual reveal.
    this.timeline.cancelInitialMessageTransitionSettle();
    this.timeline.initialMessageTransitionSettled = true;
  }

  private activateInitialChrome(action: () => void): void {
    // Lightweight header controls are not decorative: the first tap promotes
    // the full header and then performs the requested action against it.
    this.timeline.cancelInitialMessageTransitionSettle();
    this.timeline.initialMessageTransitionSettled = true;
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
    scheduleClearChatDetailHiding();
    markChatDestHidden(this.chatDestToken);
    this.surfaceActive = false;

    this.inputSwitch.cancel();
    coordinateChatPageHidden({
      stopScrollActivity: (): void => { setScrollActive(false); },
      endLinkNavigation: (): void => { endLinkNav(); },
      cancelInitialTransition: (): void => { this.timeline.cancelInitialMessageTransitionSettle(); },
      setPageVisible: (visible: boolean): void => { if (!visible) { this.dropReceiver.cancel(); } this.timeline.pageVisible = visible; },
      syncChatTgsGate: (): void => { this.syncChatTgsGate(); },
      captureHiddenAnchor: (): void => {
        this.hiddenSinceMs = Date.now();
        if (!this.scrollResumeCapturedOnHide) {
          this.timeline.captureHiddenAnchor();
        }
      },
      clearNowSecTimer: (): void => { this.clearNowSecTimer(); },
      clearSlotTick: (): void => { this.playSlot.clearTick(); },
      suspendPlaySlots: (): void => { this.playSlot.suspend(); this.videoPrefetch.suspend(); }
    });
  }

  private handleWillHide(): void {
    cancelClearChatDetailHiding(true);
    this.inputSwitch.cancel();
    this.hiddenSinceMs = Date.now();
    this.timeline.captureHiddenAnchor();
    this.captureScrollResume();
    this.scrollResumeCapturedOnHide = true;
    // 退场一开始就把群聊动态头像卸下来：播放器于是在转场那 600ms 里逐个释放，
    // 而不是全挤在转场结束那一帧（真机 trace：那一帧 47–57ms，
    // SenderAnimatedLayer 是单节点销毁成本的冠军，1.02ms/个 × 17）。
    parkSenderAnimations(true);
    coordinateChatPageWillHide({
      stopScrollActivity: (): void => { setScrollActive(false); },
      cancelInitialTransition: (): void => { this.timeline.cancelInitialMessageTransitionSettle(); },
      setPageVisible: (visible: boolean): void => { if (!visible) { this.dropReceiver.cancel(); } this.timeline.pageVisible = visible; },
      syncChatTgsGate: (): void => { this.syncChatTgsGate(); },
      clearNowSecTimer: (): void => { this.clearNowSecTimer(); },
      clearSlotTick: (): void => { this.playSlot.clearTick(); },
      suspendPlaySlots: (): void => { this.playSlot.suspend(); this.videoPrefetch.suspend(); }
    });
  }

  private handleShown(): void {
    cancelClearChatDetailHiding(false);
    this.scrollResumeCapturedOnHide = false;
    markChatDestShown(this.chatDestToken);
    this.surfaceActive = true;

    // 回到这一页（或者退场被取消了）：放开停车闸，头像该动的继续动。
    parkSenderAnimations(false);
    this.videoPrefetch.resume();
    // 收藏贴纸表：长按菜单要在构建那一刻就知道该写"收藏"还是"取消收藏"，
    // 等不了一次往返。拉一次，之后走本地那份（见 store/FavoriteStickers）。
    primeFavoriteStickers();
    const state: ChatPageShownState = {
      hiddenSinceMs: this.hiddenSinceMs,
      appWentBackground: this.appWentBackground,
      hiddenListDirty: this.timeline.hiddenListDirty
    };
    coordinateChatPageShown(state, {
      setPageVisible: (visible: boolean): void => { if (!visible) { this.dropReceiver.cancel(); } this.timeline.pageVisible = visible; },
      armInitialTransitionSettle: (): void => { this.timeline.armInitialMessageTransitionSettle(); },
      scheduleInitialTimelinePresentation: (): void => { this.timeline.scheduleInitialTimelinePresentation(); },
      scheduleChatTgsResume: (): void => { this.timeline.scheduleInitialChatTgsResume(); },
      endLinkNavigation: (): void => { endLinkNav(); },
      armPlaySlotSettle: (): void => { this.playSlot.armSettle(); },
      resyncListAfterHidden: (): void => { this.timeline.resyncListAfterHidden(); },
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
    this.timeline.hiddenListDirty = state.hiddenListDirty;
  }

  aboutToDisappear(): void {
    scheduleClearChatDetailHiding();
    markChatDestHidden(this.chatDestToken, true);
    this.messageActionsState.reset();
    this.sessionLifecycle.dispose();
  }

  private disposeInitialStageAndTgs(): void {
    // Invalidate the staged-row and composer frame callbacks. The page may be
    // popped while either delayed task is queued.
    this.timeline.initialMessageStageSeq++;
    this.timeline.initialMessageStageActive = false;
    this.timeline.initialMessagePendingGroups = null;
    this.timeline.initialMessageRevealCount = 0;
    this.timeline.initialMessageStageScheduledSeq = 0;
    this.timeline.initialTimelinePresentationSeq++;
    this.timeline.initialTimelinePresentationScheduledSeq = 0;
    this.timeline.cancelInitialMessageTransitionSettle();
    if (this.timeline.chatTgsResumeTimer !== -1) {
      clearTimeout(this.timeline.chatTgsResumeTimer);
      this.timeline.chatTgsResumeTimer = -1;
    }
    this.timeline.pageVisible = false;
    this.timeline.chatTgsScrollActive = false;
    this.timeline.chatTgsStageSettling = true;
    this.syncChatTgsGate();
    this.composerMountSeq++;
    this.composerMountScheduled = false;
  }

  private disposePlaybackAndSlots(): void {
    // 退出会话时播放器可能还开着（返回手势不走 closeViewer），为播放拉起的
    // 下载得在这里也停掉，否则回到列表页它还在后台跑。
    this.viewer.releasePlaybackRequests(this.store);
    this.playSlot.dispose();
    this.videoPrefetch.dispose();
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
    const draftText: string = this.composer.draftToPersist(this.draft);
    // 本地先落一份：服务端那条是 fire-and-forget，"返回再进来"这条最快的往返会
    // 抢在草稿落地之前（真机日志 1.4.7.2：save len=3 → 同一会话 restore serverLen=0）。
    // 仅当草稿文本真发生改变时才递增 DRAFT_EPOCH，避免退出会话（aboutToDisappear）
    // 最后一帧无条件唤醒会话列表全部 ChatRow 同步重绘导致退场尾帧掉帧。
    const draftChanged: boolean = rememberLocalDraft(this.chatId, draftText);
    if (draftChanged) {
      bumpDraftEpoch();
    }
    if (draftChanged || draftText.trim() !== '' || this.composer.replyToId !== 0) {
      this.store?.saveDraft(draftText, this.composer.replyToId);
    }
    this.exitViewerLandscape();
    if (!this.scrollResumeCapturedOnHide) {
      this.captureScrollResume();
    }
  }

  private disposeTimersAndSeqGuards(): void {
    this.inputSwitch.dispose();
    this.clearViewportResizeSettleTimer();
    this.clearImeBridge(false);
    this.drawerAnimSeq++;
    this.drawerClosingToIme = false;
    this.emojiDrawer.closingToIme = false;
    this.bottomChromeLayoutSeq++;
    this.imeTailPinned = false;
    this.bottomChromeMeasured = false;
    this.lastComposerBottomGap = -1;
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
    // 一字未动；clearTimeout（topCardActionTimer，加载占位的定时器 09-17 已删）原本
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
    this.messageDelete.dispose();
    this.unreadMentions.dispose();
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
    if (this.unregisterTranslationGrowthPin !== null) {
      this.unregisterTranslationGrowthPin();
      this.unregisterTranslationGrowthPin = null;
    }
    // 头插分批的续发定时器（util/prependChunker）。
    this.timeline.prependChunker.dispose();
    // 附件面板分发簇的退场（B12）。逐行核对过原 aboutToDisappear 全链路七个
    // 子方法，对 mediaPickerOpen/mediaCopySeq 从来没有任何清理——两个字段随
    // 页面实例一起被丢弃，不产生可观察副作用。dispose() 是空实现，仅为与
    // 其余控制器统一 bind/dispose 生命周期而保留、调用，不替原代码编造一份
    // 清理逻辑。
    this.attach.dispose();
    // 退场时取消气泡呼吸和延迟落点，避免旧页面回调继续写消息行。
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
    this.timeline.scrollActionSeq++;
    this.jumpLayoutSeq++;
    this.timeline.anchor.invalidate();
    this.scrollToBottomBusy = false;
    this.clearPendingScrollBottom('pageHide');
    this.timeline.clearFloatingDate();
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
    this.disposeConversationSubscriptions();
    // 话题横条跨话题存活，只在**页面真正退场**时才拆。
    this.subscriptions.clear('topics');
  }

  // 一个会话（话题）的订阅退场。切话题与页面退场共用这**唯一一份**——复制成两份
  // 必然漂移（日后有人加一个键，另一份不会跟着改），而漏拆一个就是订阅泄漏。
  //
  // 三段 clearInOrder 之间夹着 bgStore.close() 与 membership.dispose()，这个**交错
  // 顺序是原有的、有意为之**（见下面那段注释），合并时一并保留，没有拉平成一段。
  private disposeConversationSubscriptions(): void {
    this.subscriptions.clearInOrder([
      'messages', 'subtitle', 'chat', 'chatSelf', 'liveLocation', 'translatable', 'background'
    ]);
    if (this.bgStore !== null) {
      this.bgStore.close();
      this.bgStore = null;
    }
    this.subscriptions.clearInOrder([
      'pinned', 'headerAvatar', 'headerTitle', 'replyKeyboard'
    ]);
    // 先作废成员资格请求和权限缓存，再统一退订身份、默认权限推送。
    this.membership.dispose();
    this.subscriptions.clearInOrder([
      'membershipSupergroup', 'membershipBasicGroup', 'membershipPermissions', 'videoChat', 'groupCall'
    ]);
  }

  private closeStores(): void {
    // 两个直播定时器（脉冲/轮询）的 clearInterval 随整簇进了 topCard.dispose()，
    // 在本方法之前的 disposeTimersAndSeqGuards 里执行（B5）。
    this.closeMessageStore();
    this.topicsStore.close();
  }

  private closeMessageStore(): void {
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
    this.timeline.replaceTimelineGroups(this.timeline.groups);
  }

  @Monitor('chatContentWidth', 'isGroup')
  private onChatContentWidthChanged(): void {
    this.timeline.groupsData.setLayoutContext(this.chatContentWidth, this.selection.active, this.isGroup);
  }

  private syncTailAfterImeResize(releaseAfter: boolean = false): void {
    if (!this.imeTailPinned || this.viewerOpen()) {
      return;
    }
    const seq: number = ++this.imeLayoutSeq;
    this.timeline.atBottom = true;
    this.timeline.stayAtUnread = false;
    // First pass follows the current resize frame; the second pass catches the
    // final List measurement after the system IME animation has settled.
    setTimeout((): void => {
      if (seq === this.imeLayoutSeq && this.imeTailPinned) {
        this.timeline.glueBottom('L2057');
      }
    }, 0);
    setTimeout((): void => {
      if (seq !== this.imeLayoutSeq || !this.imeTailPinned) {
        return;
      }
      this.timeline.glueBottom('L2064');
      this.timeline.atBottom = true;
      if (releaseAfter) {
        this.imeTailPinned = false;
        this.timeline.driveVisibleWork();
      }
    }, releaseAfter ? 180 : 80);
  }

  private syncTailOnImeFrame(): void {
    if (!this.imeTailPinned || this.viewerOpen()) {
      return;
    }
    this.timeline.atBottom = true;
    this.timeline.stayAtUnread = false;
    this.timeline.glueBottom('L2078');
  }

  private currentImeOverlap(): number {
    if (this.fullViewportH > 0 && this.curViewportH > 0) {
      return Math.max(0, this.fullViewportH - this.curViewportH);
    }
    return this.keyboardH > 0 ? this.keyboardH : 0;
  }

  private refImeHeight(): number {
    if (this.knownImeH > 0) {
      return this.knownImeH;
    }
    if (this.keyboardH > 0) {
      return this.keyboardH;
    }
    return this.emojiDrawer.totalHeight(this.headerChromeHeight(), this.bottomSafe);
  }

  private targetDrawerTotalHeight(slot: string): number {
    if (slot === SLOT_EMOJI) {
      return this.emojiDrawer.totalHeight(this.headerChromeHeight(), this.bottomSafe);
    }
    if (slot === SLOT_ATTACH) {
      return BOTTOM_DRAWER_HEIGHT + drawerBottomInset(this.bottomSafe);
    }
    return 0;
  }

  private targetDrawerLiftHeight(slot: string): number {
    const total: number = this.targetDrawerTotalHeight(slot);
    if (total <= 0) {
      return 0;
    }
    return Math.max(0, total - drawerTopOverlap(this.bottomSafe, false));
  }

  private finishDrawerToImeBridge(): void {
    if (this.imeBridgeTimer !== -1) {
      clearTimeout(this.imeBridgeTimer);
      this.imeBridgeTimer = -1;
    }
    this.drawerAnimSeq++;
    this.drawerClosingToIme = false;
    this.emojiDrawer.closingToIme = false;
    this.imeClosingToDrawer = false;
    this.emojiDrawer.closingImeToDrawer = false;
    this.emojiDrawer.closingExpanded = false;
    this.emojiDrawer.shellHeight = 0;
    this.emojiDrawer.activeSlot = '';
    this.emojiDrawer.cardOffsetY = 0;
    this.emojiDrawer.cardOpacity = 1;
    this.emojiDrawer.imeBridgeSlot = '';
    this.emojiDrawer.setImeOverlapRatio(0);
    this.syncComposerBottomGap();
  }

  private armImeBridgeTimer(ms: number): void {
    if (this.imeBridgeTimer !== -1) {
      clearTimeout(this.imeBridgeTimer);
    }
    this.imeBridgeTimer = setTimeout((): void => {
      this.imeBridgeTimer = -1;
      this.imeClosingToDrawer = false;
      this.emojiDrawer.closingImeToDrawer = false;
      if (this.drawerClosingToIme) {
        this.finishDrawerToImeBridge();
      }
    }, ms);
  }

  private startDrawerToImeBridge(slot: string): void {
    if (this.currentImeOverlap() > 10 && this.emojiDrawer.shellHeight <= 0) {
      return;
    }
    const prevTopOverlap: number = drawerTopOverlap(this.bottomSafe, this.drawerClosingToIme);
    this.imeClosingToDrawer = false;
    this.emojiDrawer.closingImeToDrawer = false;
    this.drawerClosingToIme = true;
    this.emojiDrawer.closingToIme = true;
    const settle: number = this.chatEffectDuration(KEY_POWER_EFFECT_MENU, 190);
    const startH: number = this.emojiDrawer.shellHeight > 0
      ? this.emojiDrawer.shellHeight + prevTopOverlap
      : this.targetDrawerTotalHeight(slot);
    const targetH: number = this.refImeHeight();
    this.armImeBridgeTimer(Math.max(340, settle + 140));
    this.animateDrawerTo(slot, targetH, settle, startH, 0, 14, 1, 0, true);
  }

  private clearImeBridge(keepContentReady: boolean): void {
    if (this.imeBridgeTimer !== -1) {
      clearTimeout(this.imeBridgeTimer);
      this.imeBridgeTimer = -1;
    }
    this.imeClosingToDrawer = false;
    this.drawerClosingToIme = false;
    this.emojiDrawer.closingToIme = false;
    this.emojiDrawer.closingImeToDrawer = false;
    if (this.emojiDrawer.imeBridgeSlot !== '') {
      this.emojiDrawer.imeBridgeSlot = '';
    }
    this.emojiDrawer.setImeOverlapRatio(0);
    if (!keepContentReady && !this.showEmojiPanel) {
      this.panelContentReady = false;
    }
  }

  private animateDrawerTo(
    slot: string,
    targetH: number,
    durationMs: number,
    startH: number,
    fromOffsetY: number,
    toOffsetY: number,
    fromOpacity: number,
    toOpacity: number,
    closingToIme: boolean = false,
    onDone?: () => void
  ): void {
    const seq: number = ++this.drawerAnimSeq;
    this.drawerClosingToIme = closingToIme;
    this.emojiDrawer.closingToIme = closingToIme;
    if (slot !== '') {
      this.emojiDrawer.activeSlot = slot;
    }
    if (this.fullViewportH <= 0 && this.emojiDrawer.viewport > 0) {
      this.fullViewportH = this.emojiDrawer.viewport;
      this.emojiDrawer.fullViewportH = this.fullViewportH;
    }
    if (this.timeline.atBottom && !this.viewerOpen()) {
      this.imeTailPinned = true;
    }
    holdPlayerJobs(Math.max(KEYBOARD_SETTLE_MS, durationMs + 80));
    if (durationMs <= 0 || (Math.abs(targetH - startH) < 0.5 &&
      Math.abs(toOffsetY - fromOffsetY) < 0.5 && Math.abs(toOpacity - fromOpacity) < 0.01)) {
      this.emojiDrawer.shellHeight = Math.max(0, targetH);
      this.emojiDrawer.cardOffsetY = toOffsetY;
      this.emojiDrawer.cardOpacity = toOpacity;
      this.emojiDrawer.closingExpanded = false;
      if (!closingToIme && targetH <= 0) {
        this.emojiDrawer.activeSlot = '';
      }
      if (onDone !== undefined) {
        onDone();
      }
      if (!closingToIme) {
        this.imeTailPinned = false;
        this.timeline.driveVisibleWork();
      }
      return;
    }
    this.emojiDrawer.shellHeight = Math.max(0, startH);
    this.emojiDrawer.cardOffsetY = fromOffsetY;
    this.emojiDrawer.cardOpacity = fromOpacity;
    const startMs: number = Date.now();
    const step = (): void => {
      if (seq !== this.drawerAnimSeq) {
        return;
      }
      const elapsed: number = Date.now() - startMs;
      const u: number = Math.min(1, Math.max(0, elapsed / durationMs));
      const eased: number = 1 - Math.pow(1 - u, 3.2);
      this.emojiDrawer.shellHeight = Math.max(0, startH + (targetH - startH) * eased);
      this.emojiDrawer.cardOffsetY = fromOffsetY + (toOffsetY - fromOffsetY) * eased;
      this.emojiDrawer.cardOpacity = fromOpacity + (toOpacity - fromOpacity) * eased;
      if (u < 1) {
        this.getUIContext().postFrameCallback(new ChatPageFrameCallback(step));
        return;
      }
      this.emojiDrawer.closingExpanded = false;
      if (!closingToIme) {
        if (targetH <= 0) {
          this.emojiDrawer.shellHeight = 0;
          this.emojiDrawer.activeSlot = '';
          this.emojiDrawer.cardOffsetY = 0;
          this.emojiDrawer.cardOpacity = 1;
          this.syncComposerBottomGap();
        }
        if (onDone !== undefined) {
          onDone();
        }
        this.getUIContext().postFrameCallback(new ChatPageFrameCallback((): void => {
          if (seq !== this.drawerAnimSeq) {
            return;
          }
          if (this.keyboardH <= 0 && this.viewportResizeSettleTimer === -1) {
            this.imeTailPinned = false;
            this.timeline.driveVisibleWork();
          }
        }));
      } else {
        if (onDone !== undefined) {
          onDone();
        }
        const overlap: number = this.currentImeOverlap();
        if (overlap >= Math.max(10, targetH - 4)) {
          this.finishDrawerToImeBridge();
        }
      }
    };
    this.getUIContext().postFrameCallback(new ChatPageFrameCallback(step));
  }

  private handleResizeAreaChange(_oldH: number, newH: number): void {
    if (newH <= 0) {
      return;
    }
    this.curViewportH = newH;
    this.emojiDrawer.curResizeH = newH;
    if (newH > this.fullViewportH ||
      (this.keyboardH <= 0 && !this.imeTailPinned && !this.emojiDrawer.closingImeToDrawer &&
        !this.drawerClosingToIme && this.emojiDrawer.shellHeight <= 0)) {
      this.fullViewportH = Math.max(this.fullViewportH, newH);
    }
    if (this.fullViewportH > 0) {
      this.emojiDrawer.fullViewportH = this.fullViewportH;
    }
    const overlap: number = Math.max(0, this.fullViewportH - newH);
    if (overlap > this.knownImeH) {
      this.knownImeH = overlap;
    }
    if (this.emojiDrawer.closingImeToDrawer && overlap <= 1 && this.keyboardH <= 0) {
      this.imeClosingToDrawer = false;
      this.emojiDrawer.closingImeToDrawer = false;
      if (this.imeBridgeTimer !== -1) {
        clearTimeout(this.imeBridgeTimer);
        this.imeBridgeTimer = -1;
      }
    } else if (this.drawerClosingToIme && this.emojiDrawer.shellHeight > 0 &&
      overlap >= Math.max(10, this.emojiDrawer.shellHeight - 4)) {
      this.finishDrawerToImeBridge();
    }
  }

  private handleViewportHeightChange(oldH: number, newH: number): void {
    if (newH > 0 && this.fullViewportH <= 0) {
      this.fullViewportH = newH;
      this.emojiDrawer.fullViewportH = newH;
    }
    if (oldH <= 0 || newH <= 0 || this.viewerOpen()) {
      return;
    }
    const deltaH: number = oldH - newH;
    if (Math.abs(deltaH) < 0.5) {
      return;
    }
    if (!this.timeline.didInitialScroll || this.timeline.initialTimelineMasked ||
      this.timeline.groups.length === 0) {
      return;
    }
    this.onViewportResizeFrame();
    if (deltaH > 0) {
      // 软键盘或底部抽屉升起、视口高度收缩：把当前可见的聊天记录按相同位移往上顶，避免被直接遮挡。
      if (this.imeTailPinned || this.timeline.atBottom) {
        this.imeTailPinned = true;
        this.timeline.atBottom = true;
        this.timeline.stayAtUnread = false;
        this.timeline.glueBottom('imeResizeOpen');
      } else {
        this.timeline.scroller.scrollBy(0, deltaH);
      }
    } else {
      // 软键盘或底部抽屉收起、视口高度恢复：聊天记录随视口平滑下移复位。
      if (this.imeTailPinned || this.timeline.atBottom) {
        this.imeTailPinned = true;
        this.timeline.atBottom = true;
        if (!this.timeline.scroller.isAtEnd()) {
          this.timeline.glueBottom('imeResizeClose');
        }
      } else if (!this.timeline.scroller.isAtEnd()) {
        this.timeline.scroller.scrollBy(0, deltaH);
      }
    }
  }

  @Monitor('keyboardH')
  private onKeyboardHeightChanged(): void {
    const wasVisible: boolean = this.lastKeyboardH > 0;
    const visible: boolean = this.keyboardH > 0;
    if (this.keyboardH > this.knownImeH) {
      this.knownImeH = this.keyboardH;
    }
    if (wasVisible !== visible) {
      holdPlayerJobs(KEYBOARD_SETTLE_MS);
    }
    if (!this.imeTailPinned && this.timeline.atBottom && !this.viewerOpen()) {
      if ((!wasVisible && visible && this.composerFocused) || (wasVisible && !visible)) {
        this.imeTailPinned = true;
      }
    }
    this.lastKeyboardH = this.keyboardH;
    this.syncComposerBottomGap();
    if (this.imeTailPinned) {
      if (visible) {
        // keyboardHeightChange follows the system IME animation. Keep the
        // message tail on the same layout frame instead of adding a separate
        // delayed scroll animation with a visibly different velocity.
        this.syncTailOnImeFrame();
      } else if (this.emojiDrawer.shellHeight <= 0 && !this.emojiDrawer.closingImeToDrawer) {
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

  // 菜单里的「添加到 GIF」。存的是这条消息的动图文件 id，之后从输入栏的
  // GIF 面板取用。失败不静默：TDLib 会因为文件已过期/不可引用而拒。
  private onAddToGifs(messageId: number): void {
    const entry = this.entryById(messageId);
    if (entry === null || !entry.isAnimation || entry.videoFileId === 0 || this.store === null) {
      showToast($r('app.string.cp_gif_unavailable'), 1500);
      return;
    }
    this.store.addSavedAnimation(entry.videoFileId).then((): void => {
      showToast($r('app.string.mb_added_to_gifs'), 1500);
    }).catch((): void => {
      showToast($r('app.string.cp_gif_unavailable'), 1500);
    });
  }

  // ① 点贴纸/长按「查看贴纸合集」：弹合集面板。逻辑在 StickerMessageActions，
  // 这里只负责把面板打开。
  private openStickerSet(messageId: number): void {
    const setId: string = stickerSetIdForMessage(this.entryById(messageId));
    if (setId === '') {
      return;
    }
    this.stickerSetSheetId = setId;
    this.stickerSetSheetMounted = true;
    this.stickerSetSheetOpen = true;
    // 登记给返回键（见 util/sheetDismissStack）。onDisappear 里注销。
    this.stickerSheetOff = pushSheetDismiss((): void => {
      this.stickerSetSheetOpen = false;
    });
  }

  private stickerSheetOff: (() => void) | null = null;

  // ② 收藏/取消收藏这张贴纸。
  private toggleFavoriteSticker(messageId: number): void {
    toggleFavoriteForMessage(this.entryById(messageId)).then((favorite: boolean): void => {
      showToast(favorite ? $r('app.string.mb_favorite_added') : $r('app.string.mb_favorite_removed'), 1500);
    }).catch((e: Error): void => {
      logW(`toggleFavoriteSticker failed: ${e.message}`);
      showToast($r('app.string.mb_favorite_failed'), 1800);
    });
  }

  @Builder
  private stickerSetSheet() {
    // 每次打开都重建：合集内容与"已添加"状态都得重新问一遍服务端。
    // 判据用 mounted 而不是 open：收起动画期间内容要保持，否则是白抽屉。
    if (this.stickerSetSheetMounted) {
      StickerSetSheet({
        setId: this.stickerSetSheetId,
        onPick: (item: StickerSetItem): void => {
          if (!this.sendAccess.check('sendOtherMessages')) { return; }
          this.timeline.atBottom = true;
          this.store?.sendSticker(item.fileId, item.width, item.height);
          this.stickerSetSheetOpen = false;
        }
      });
    }
  }

  private onAnimationTap(messageId: number, isPlaying: boolean): void {
    const entry = this.entryById(messageId);
    if (entry === null || !entry.isAnimation) {
      return;
    }
    if (entry.videoFileId === 0 && entry.videoPath === '') {
      showToast($r('app.string.cp_gif_unavailable'), 1500);
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
    this.viewer.requestAnimationPlayback(messageId);
    if (entry.videoPath === '') {
      // 内联播放的 GIF 按定义就在可见窗口里，划走了本来就该停 —— 不需要豁免，
      // 更不该进下载管理器（那是"保存"才有的待遇）。
      this.store?.requestVideoDownload(messageId, false, entry.videoFailed);
    }
  }

  private onAnimationPlaybackFailed(messageId: number): void {
    this.viewer.markAnimationPlaybackFailed(messageId);
  }

  // Open/close wrapped in animateTo so the viewer's own transition remains
  // smooth without moving/re-parenting the chat thumbnail Image node.
  private openViewer(messageId: number): void {
    this.viewer.open(messageId);
  }

  // 查看器显式通知目标切换，页面协调动画闸门和窗口覆盖。
  private onViewerTargetChanged(): void {
    this.syncChatTgsGate();
    // 分栏下查看器开着：收左栏和侧边页签，让页面内的查看器盖满窗口（见 util/viewerWindowCover）。
    publishViewerCoversWindow(viewerFullScreenWanted(
      isSplitByBreakpoint(this.widthBp, this.heightBp, this.forceSingleColumn, this.windowPortrait), this.viewerOpen()));
  }

  // 查看器上点"保存"：entry 在这里取，取不到就不调。
  //
  // 原来是 MediaSaveState 经宿主取值器 viewerEntry() 自己现读 viewerMsgId
  // （整簇唯一一条跨域读）。S2 把取值这一步收回页面，MediaSaveState 从此不需要
  // 知道 viewerMsgId 或 entryById 的存在——理由见该文件 saveMediaEntry 上方。
  // 查看器右上角「在聊天中查看」（issue #166）：关掉查看器、跳到那条消息。
  private showViewerMediaInChat(): void {
    const messageId: number = this.viewer.viewerMsgId;
    this.closeViewer();
    if (messageId > 0) {
      this.jumpToMessageId(messageId);
    }
  }

  // 「显示所有图片」：打开资料页并直接落到「媒体」页签。私聊开个人资料页，
  // 群/频道开群资料页，两边都收 tab 参数。
  private showAllChatMedia(): void {
    this.closeViewer();
    const userId: number = this.header.currentPeerUserId();
    if (!this.isGroup && !this.isChannel && userId > 0) {
      const params: Record<string, Object> = { 'userId': userId, 'tab': PROFILE_TAB_MEDIA };
      navigateToProfile(params);
      return;
    }
    const params: Record<string, Object> = { 'chatId': this.chatId, 'tab': PROFILE_TAB_MEDIA };
    navigateToChatProfile(params);
  }

  private saveCurrentViewerMedia(toFiles: boolean): void {
    const e: MessageEntry | null = this.entryById(this.viewer.viewerMsgId);
    if (e === null) {
      return;
    }
    this.mediaSave.saveMediaEntry(e, toFiles);
  }

  private viewerOpen(): boolean {
    return this.viewer.viewerOpen();
  }

  private closeViewer(): void {
    this.viewer.close();
  }

  // Leaving the viewer in landscape would strand the chat page sideways.
  private exitViewerLandscape(): void {
    this.viewer.exitLandscape();
  }

  // System back (gesture/hardware button): close the fullscreen viewer first
  // if it's open, rather than popping all the way back to the chat list.
  private handleBackPressed(): boolean {
    // 别人用 bindSheet 弹的面板（贴纸合集、输入框全屏编辑…）自己登记在这里。
    // 必须排在最前：面板盖在所有浮层之上，返回键该先收它。
    if (dismissTopSheet()) {
      return true;
    }
    // 录制浮层盖住整页，返回键必须先关它（组件退场时会取消录制并删掉临时文件）。
    if (this.overlayState.showVideoNoteRecorder) {
      this.overlayState.showVideoNoteRecorder = false;
      return true;
    }
    if (this.viewerOpen() || this.viewer.viewerClosing) {
      if (this.viewer.viewerVideoLandscape) {
        this.exitViewerLandscape();
        return true;
      }
      if (this.viewerOpen()) {
        this.closeViewer();
      }
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
    // 表情/贴纸抽屉、附件抽屉开着：返回先收抽屉，不直接退出会话——和系统键盘弹着时
    // 返回先收键盘是同一个手感。排在查看器之后：查看器盖在抽屉上面，要先收它。
    if (this.showEmojiPanel && this.emojiDrawer.expanded) {
      this.setEmojiExpanded(false);
      return true;
    }
    if (slotIsDrawer(this.bottomSlot)) {
      this.closeBottomPanels();
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

  // 锚点采样：第 index 行相对 List 顶的 y。**量不到时返回 NaN，绝不返回 0**。
  //
  // 官方（faqs-arkui-572）：getItemRect 的下标必须是当前显示区域内的子组件，
  // 否则视为非法值，**非法值返回的大小和位置均为 0**。原来两处采样都是
  // `try { y = getItemRect(i).y } catch { y = 0 }` —— 非法下标和"行正好贴在
  // 视口顶端(y=0)"取到的是同一个 0，分不开。而 anchorRestore 的
  // dy = rect.y - itemY 会把这个假 0 当成真位置，补出整行级别的位移。
  // 译文到货前先记下当前首个可见行的位置，落定后把它按回去。
  //
  // 顶部锚定时行变高会把下面的内容往下推，用户正在看的那条跟着漂
  // （用户 2026-09-09：「顶部确实定不住」）。maintainVisibleContentPosition
  // 管的是插入/删除，不管行变高——判据与取舍见 util/translationAnchor。
  //
  // 一次可见范围里可能连着落好几条译文，所以**合并**：只记第一次的位置，
  // 后面每次都把落定的时刻往后推，最后统一补一次。
  private holdAnchorForTranslation(): void {
    if (!shouldHoldTranslationAnchor(this.timeline.atBottom, this.timeline.anchorIndexFresh())) {
      return;
    }
    if (this.translationAnchorIdx < 0) {
      const y: number = this.timeline.anchorItemY(this.timeline.curStartIdx);
      if (Number.isNaN(y)) {
        return;
      }
      this.translationAnchorIdx = this.timeline.curStartIdx;
      this.translationAnchorY = y;
    }
    if (this.translationAnchorTimer !== -1) {
      clearTimeout(this.translationAnchorTimer);
    }
    this.translationAnchorTimer = setTimeout((): void => {
      this.translationAnchorTimer = -1;
      this.applyTranslationAnchor();
    }, TRANSLATION_ANCHOR_SETTLE_MS);
  }

  private applyTranslationAnchor(): void {
    const idx: number = this.translationAnchorIdx;
    const y0: number = this.translationAnchorY;
    this.translationAnchorIdx = -1;
    if (idx < 0 || this.timeline.atBottom) {
      return;
    }
    const y1: number = this.timeline.anchorItemY(idx);
    if (Number.isNaN(y1)) {
      return;
    }
    const dy: number = y1 - y0;
    if (Math.abs(dy) < 0.5) {
      return;
    }
    // 诊断：这条补偿到底有没有活干。上一轮同类补偿在**插入/删除**场景下 90 次
    // 里 83 次 dy=0（mVCP 已经管了），而行变高是 mVCP 不管的那一类，这里应当
    // 是非零的。真机上验完就删。
    logW(`[TransAnchor] idx=${idx} dy=${dy.toFixed(1)}`);
    this.timeline.scroller.scrollBy(0, dy);
  }

  // 贴底时行因翻译变高：同一次刷新里钉住底部（判据在 util/translationGrowthPin）。
  private pinBottomForTranslationGrowth(chatId: number): void {
    if (chatId !== this.chatId || !translationGrowthPinWanted({
      pageVisible: this.timeline.pageVisible,
      didInitialScroll: this.timeline.didInitialScroll,
      atBottom: this.timeline.atBottom,
      followPending: this.timeline.bottomFollowPending,
      stayAtUnread: this.timeline.stayAtUnread,
      touchActive: this.timeline.listTouchActive,
      scrollActive: this.timeline.timelineScrollActive,
      viewerOpen: this.viewerOpen(),
      hasMoreNewer: this.store !== null && this.store.getHasMoreNewer(),
      jumpLanding: this.jumpLandingHolding()
    })) {
      return;
    }
    this.timeline.glueBottom('translationGrowth');
  }

  private prepareUserJump(): void {
    this.timeline.clearFloatingDate();
    this.timeline.stayAtUnread = false;
    this.jumpLayoutSeq++;
    this.flash.cancelFlash();
  }

  // 跳转落地的所有权窗口：开窗与问询各一行，判据全在 util/jumpLandingOwner。
  private beginJumpLanding(): void {
    this.jumpLandingSettleUntil = jumpLandingDeadline(Date.now());
  }

  private jumpLandingHolding(): boolean {
    return jumpLandingHolds(this.jumpLandingSettleUntil, Date.now());
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
        showToast($r('app.string.cp_pinned_unavailable'), 1500);
      }
    });
  }

  // [NewerFire] 用：还剩多少行是首屏占位。用循环而不是 filter，这行日志在
  // 底部区里会反复打，不该每次都拷一份数组出来。
  private countDeferredRows(): number {
    let count: number = 0;
    for (const row of this.timeline.groups) {
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
  // 刻意不调 refreshAtBottom：那个会写 this.timeline.atBottom。这里只读，绝不改状态。
  // groupsLen 用**新快照**的长度，因为闸是在发布这份快照时判的。
  private appendAnchorGateProbe(groups: AlbumGroup[]): string {
    const hasMoreNewer: boolean = this.store !== null && this.store.getHasMoreNewer();
    let scrollerAtEnd: boolean = false;
    try {
      scrollerAtEnd = this.viewerOpen() ? false : this.timeline.scroller.isAtEnd();
    } catch (e) {
      scrollerAtEnd = false;
    }
    const verdict: string = atBottomVerdict({
      viewerOpen: this.viewerOpen(),
      imeTailPinned: this.imeTailPinned,
      scrollerAtEnd: scrollerAtEnd,
      visibleEndIdx: this.timeline.curEndIdx,
      indexGroupsLen: this.timeline.indexGroupsLen,
      groupsLen: groups.length,
      hasMoreNewer: hasMoreNewer
    });
    return `hasMoreNewer=${hasMoreNewer} atBottom=${this.timeline.atBottom} verdict=${verdict}` +
      ` scrollerAtEnd=${scrollerAtEnd} startIdx=${this.timeline.curStartIdx} endIdx=${this.timeline.curEndIdx}` +
      ` idxLen=${this.timeline.indexGroupsLen} userScroll=${this.timeline.listUserScrollActive}` +
      ` touch=${this.timeline.listTouchActive} newerArmed=${this.timeline.newerGate.armed}` +
      ` gateByUser=${this.timeline.newerGate.armedByUser}` +
      ` reqUserDriven=${newerPageIsUserDriven(pageGateShotIsUserDriven(this.timeline.newerGate))}`;
  }

  // ⚠️ 临时探针（[InitialPage] / [Anchor] / [JumpLatest] 共用，判读完一起删）：
  // 当前视口与分页状态的一行快照。首屏落点和 ↓ 的走向都要靠这几个值判读，
  // 尤其是"贴的是已加载窗口的底（hasMoreNewer=true）还是真尾部"。
  private scrollStateProbe(): string {
    const hasMoreNewer: boolean = this.store !== null && this.store.getHasMoreNewer();
    let scrollerAtEnd: boolean = false;
    try {
      scrollerAtEnd = this.viewerOpen() ? false : this.timeline.scroller.isAtEnd();
    } catch (e) {
      scrollerAtEnd = false;
    }
    const verdict: string = atBottomVerdict({
      viewerOpen: this.viewerOpen(),
      imeTailPinned: this.imeTailPinned,
      scrollerAtEnd: scrollerAtEnd,
      visibleEndIdx: this.timeline.curEndIdx,
      indexGroupsLen: this.timeline.indexGroupsLen,
      groupsLen: this.timeline.groups.length,
      hasMoreNewer: hasMoreNewer
    });
    return `hasMoreNewer=${hasMoreNewer} atBottom=${this.timeline.atBottom} verdict=${verdict}` +
      ` scrollerAtEnd=${scrollerAtEnd} startIdx=${this.timeline.curStartIdx} endIdx=${this.timeline.curEndIdx}` +
      ` rows=${this.timeline.groups.length} pendingBottom=${this.pendingScrollBottom}` +
      ` pendingJumpId=${this.pendingJumpId} busy=${this.scrollToBottomBusy}`;
  }

  // Submission and approval state live in MembershipSession.
  private joinCurrentChat(folderId?: number): void {
    this.membership.join(this.membershipState, folderId);
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
      this.returnState = dropReachedJumps(this.returnState, this.timeline.curBottomId);
    }
    if (this.timeline.atBottom) {
      if (Date.now() >= this.jumpLandingUntil) {
        this.returnState = reachedLatest();
      }
      return;
    }
    this.returnState = advanceRead(this.returnState, this.timeline.curBottomId);
  }

  // 「↓」这一下该去哪。显隐也读它：没有可返回的位置就不该出现。
  private returnTarget(): ReturnTarget {
    return nextReturnTarget(this.returnState, this.timeline.curBottomId, this.timeline.atBottom);
  }

  private onScrollFabTap(): void {
    const target: ReturnTarget = this.returnTarget();
    // ⚠️ 临时探针 [JumpLatest]：↓ 不是"回到底部"而是三级返回（引用栈 > 阅读
    // 进度 > 最新，见 util/readingReturn）。用户说"要点好几次"时，第一件要分
    // 清的就是前几下究竟去了返回点还是真的走了 scrollToLatest——这行日志把
    // 每一次点击各自选的分支和当时的返回栈都记下来。
    this.jumpLatestSeq++;
    logW(`[JumpLatest] #${this.jumpLatestSeq} tap route=${target.kind}` +
      ` targetId=${target.messageId} curBottomId=${this.timeline.curBottomId}` +
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

  private markVisibleRead(end: number): void {
    if (this.store === null || end < 0 || end >= this.timeline.groups.length) {
      return;
    }
    if (this.timeline.pageVisible && this.appIsForeground && !this.viewerOpen()) {
      this.store.markVisibleMentions(visibleMessageIds(this.timeline.groups.length,
        (index: number): number[] => this.timeline.groups[index].memberIds, this.timeline.curStartIdx, end));
    }
    // 往回找第一条"真实"消息行、以及"是不是实时尾部"，两个判定都在
    // util/readMarking（8 条测）——已读是高水位，报高了就吞掉没看过的消息。
    const maxId: number = newestVisibleMessageId(
      this.timeline.groups.length, (index: number): number[] => this.timeline.groups[index].memberIds, end);
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
      if (isAtLiveTail(end, this.timeline.groups.length, this.store.getHasMoreNewer())) {
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
    this.timeline.atBottom = true;
    this.timeline.stayAtUnread = false;
    this.withSendLock((): Promise<void> => store.sendAsync(command, replyId).then((): void => {
      if (this.composer.replyToId === replyId) {
        this.composer.clearReply();
      }
    }).catch((e: TdError): void => {
      logE(`ChatPage.botCommand failed: ${e.message}`);
      showToast($r('app.string.cp_command_failed'), 1600);
    }));
  }

  private jumpToLinkedMessageInThisChat(messageId: number): void {
    this.prepareUserJump();
    this.beginJumpLanding();
    const gidx = groupIndexOf(this.timeline.groups, messageId);
    if (gidx >= 0) {
      this.timeline.scrollToJumpTarget(gidx);
      this.flash.flashAtIndex(gidx, messageId);
    } else {
      this.pendingJumpId = messageId;
      if (this.store !== null) {
        const targetId: number = messageId;
        this.store.loadAround(targetId, (found: boolean): void => {
          if (!found && this.pendingJumpId === targetId) {
            this.pendingJumpId = 0;
            showToast($r('app.string.cp_cannot_locate'), 1500);
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
    this.returnState = pushJump(this.returnState, fromId > 0 ? fromId : this.timeline.curBottomId);
    this.jumpLandingUntil = Date.now() + JUMP_LANDING_GRACE_MS;
    this.prepareUserJump();
    this.beginJumpLanding();
    const gidx = groupIndexOf(this.timeline.groups, messageId);
    if (gidx >= 0) {
      this.timeline.scrollToJumpTarget(gidx);
      this.flash.flashAtIndex(gidx, messageId);
    } else if (this.store !== null) {
      this.pendingJumpId = messageId;
      this.store.loadAround(messageId, (found: boolean): void => {
        if (!found && this.pendingJumpId === messageId) {
          this.pendingJumpId = 0;
          showToast($r('app.string.cp_original_unavailable'), 1500);
        }
      });
    }
  }

  // 跳转反馈的落点校验、动画时序和取消由 JumpFlashState 统一管理。

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
    if (!this.timeline.pageVisible) {
      this.timeline.hiddenListDirty = true;
      return;
    }
    this.timeline.rebuildAllRows();
  }

  @Monitor('appIsForeground')
  private onAppForegroundChanged(): void {
    if (!this.appIsForeground) { this.dropReceiver.cancel(); }
    // 栈内隐藏页也会收到前后台通知，不能由它覆盖当前可见会话的动画总闸。
    if (this.timeline.pageVisible) {
      this.syncChatTgsGate();
    }
    // 停留在会话页切后台时必须 closeChat，否则 TDLib 认为用户正在看这个
    // 会话，不会为它生成任何通知。
    if (this.appIsForeground) {
      this.store?.resumeOpenChat();
    } else {
      this.inputSwitch.cancel();
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
    const idx = this.timeline.messages.findIndex((m: MessageEntry) => m.id === id);
    return idx >= 0 ? this.timeline.messages[idx] : null;
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
      showToast($r('app.string.cp_code_unavailable'), 1500);
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

  private openBotMiniApp(): void {
    openMiniAppPage({ kind: 'web', chatId: this.chatId,
      botUserId: this.header.currentPeerUserId(), title: '', url: this.header.botMiniAppUrl });
  }

  // pickInlineResult（涉及 sendInlineResult 与 composer.clearReply，方案点名
  // 留页面）：refreshInlineQuery/downloadInlineThumb 整簇搬进了
  // InlineQueryState（B14 批），this.inlineQueryId 换成只读取值器
  // this.inline.queryId()，两处清空换成 this.inline.clear()（原样两行
  // `this.inlineResults = []; this.inlineQueryId = '';`，见该方法注释）。
  private pickInlineResult(row: InlineResultRow): void {
    if (this.inline.queryId() === '' || !this.sendAccess.check(sendPermissionForType(row.kind))) { return; }
    const replyId = this.composer.replyToId;
    sendInlineResult(this.chatId, this.inline.queryId(), row.resultId, replyId, false, sendPermissionForType(row.kind)).then((): void => {
      this.draft = '';
      this.inline.clear();
      this.composer.clearReply();
      this.timeline.atBottom = true;
    }).catch((e: TdError): void => {
      logE(`ChatPage.sendInlineResult failed: ${e.message}`);
      showToast(e instanceof SendPermissionError ? e.message : $r('app.string.cp_inline_send_failed'), 1600);
    });
  }

  // sendSuggestedSticker（调用 this.store?.sendSticker(...)，方案点名留
  // 页面）：refreshStickerSuggestions/downloadSuggestionThumb 整簇搬进了
  // StickerSuggestionState（B14 批）。原样两行
  // `this.stickerSuggestions = []; this.stickerSuggestSeq++;` 换成
  // this.sticker.clearAfterSend()——两个字段现在都是私有的，打包成这一个方法。
  private sendSuggestedSticker(fileId: number): void {
    if (!this.sendAccess.check('sendOtherMessages')) { return; }
    const draft: string = this.draft;
    const store: MessageStore | null = this.store;
    store?.sendSticker(fileId, 512, 512).then((sent: boolean): void => {
      if (!sent || this.store !== store) { return; }
      rememberRecentSticker(fileId);
      if (this.draft === draft) { this.draft = ''; }
      this.sticker.clearAfterSend();
    });
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

  // 面板右侧那颗按钮：只填进输入框，末尾补一个空格好接着打参数（issue #183）。
  private fillCommand(item: CommandItem): void {
    this.draft = `${commandLabel(item)} `;
    this.command.closePanel();
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
      // 迁移前是 this.getUIContext().getRouter().pushUrl(...).catch(弹「打不开联系人」)。漏斗是同步 void，
      // 推进已注册的栈不会失败，那个 toast 分支不再可达；成功路径完全一致。
      navigateToProfile(params);
      return;
    }
    if (vcard.trim() !== '') {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
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
      showToast($r('app.string.cp_contact_no_phone'), 1500);
      return;
    }
    openUrl(this.getUIContext().getHostContext() as common.UIAbilityContext, `tel:${normalized}`, (): void => {
      showToast($r('app.string.cp_no_dialer'), 1600);
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
      showToast($r('app.string.cp_no_location'), 1500);
      return;
    }
    openUrl(this.getUIContext().getHostContext() as common.UIAbilityContext, uris.geoUri, (): void => {
      openUrl(this.getUIContext().getHostContext() as common.UIAbilityContext, uris.webFallback, (): void => {
        showToast($r('app.string.cp_no_map_app'), 1700);
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
    this.getUIContext().showAlertDialog({
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
            showToast($r('app.string.cp_history_cleared'), 2000);
          }).catch((e: TdError) => {
            logE(`ChatPage.deleteChatHistory failed: ${e.message}`);
            showToast($r('app.string.cp_clear_failed'), 2000);
          });
        }
      }
    });
  }

  private confirmLeaveChat(): void {
    this.getUIContext().showAlertDialog({
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
          leaveChatFully(this.chatId).then(() => {
            this.goBack();
          }).catch((e: TdError) => {
            logE(`ChatPage.leaveChat failed: ${e.message}`);
            showToast($r('app.string.cp_leave_failed'), 2000);
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
      pinnedHidden: this.topCard.pinnedVisibility.hidden,
      onTogglePinned: (): void => { this.topCard.togglePinnedVisibility(); },
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
  private bottomChromeMeasured: boolean = false;
  private bottomChromeLayoutSeq: number = 0;
  // Measured bot-keyboard height; with the input bar it makes up the bottom
  // chrome the scroll-to-bottom FAB has to clear.
  // "Fake" animation: the open/close transition flies an empty white shell;
  // the real panel content (hundreds of emoji + sticker players) mounts only
  // after the animation lands, so frames stay cheap.
  @Local panelContentReady: boolean = false;
  private emojiDrawer: EmojiDrawerState = new EmojiDrawerState();
  private dropReceiver: ChatDropReceiver = new ChatDropReceiver();
  private inputSwitch: ComposerInputSwitch = new ComposerInputSwitch();
  private panelReadySeq: number = 0;

  // 话题横条：论坛超级群已在会话列表通过双栏话题列表选定具体话题进入，不再挂顶栏话题横条；
  // 仅开了话题模式的 Bot 私聊（或未带 forumTopicId 直入论坛超级群需要兜底落到首话题时）拉取话题。
  private openTopicBar(): void {
    const store = getChatStore();
    const isSupergroupForum: boolean = store.isForumSupergroup(this.chatId);
    this.topicCreateAllowed = isSupergroupForum ? false : store.canUserCreateTopics(this.chatId);
    if (!store.isForum(this.chatId) || (isSupergroupForum && this.forumTopicId > 0)) {
      this.topicsStore.close();
      this.topicBarCount = 0;
      return;
    }
    // 切话题会重跑整条路由流水线，于是这里也会被再调一次。同一个会话、横条已经
    // 有内容时直接返回：否则每切一次话题就白发一次 getForumTopics。
    if (this.topicsStore.getChatId() === this.chatId && this.topicBarCount > 0) {
      return;
    }
    // set 会先拆同名订阅，所以换会话时不会叠两份；'topics' 在页面退场时单独拆。
    this.subscriptions.set('topics', this.topicsStore.subscribe((): void => {
      this.syncTopicBar();
    }));
    this.topicsStore.open(this.chatId);
  }

  private syncTopicBar(): void {
    const store = getChatStore();
    const isSupergroupForum: boolean = store.isForumSupergroup(this.chatId);
    const rows: ForumTopicRow[] = this.topicsStore.getRows();
    if (isSupergroupForum) {
      if (this.topicBarCount !== 0) {
        this.topicBarCount = 0;
      }
      if (this.forumTopicId === 0 && rows.length > 0) {
        this.switchTopic(rows[0].threadId, rows[0].name);
      }
      return;
    }
    this.topicRowsData.update(rows,
      rows.map((row: ForumTopicRow): string => `${row.threadId}`),
      rows.map((row: ForumTopicRow): string =>
        `${row.threadId}|${row.name}|${row.unreadCount}|${row.isPinned}`));
    if (this.topicBarCount !== rows.length) {
      this.topicBarCount = rows.length;
    }
    if (this.forumTopicId === 0 && rows.length > 0 && store.isForum(this.chatId)) {
      this.switchTopic(rows[0].threadId, rows[0].name);
    }
  }

  // 原地切话题：不 push 新页面，改写路由参数后重跑同一条 applyRouteParams。
  //
  // 【为什么能整条复用】resolveRouteAndResetSession 会按 conversationScopeId 判定
  // 会话是否变了，话题一换它就走 resetScrollSession()，滚动/输入/选择态全部重置；
  // 订阅侧 subscriptions.set 自带同名先拆。所以这里只需要把**上一个话题**的东西
  // 收干净：草稿与浏览位置先落盘，会话级订阅与消息 store 拆掉，横条留着。
  private switchTopic(threadId: number, name: string): void {
    const params: Record<string, Object> | undefined = this.navParams;
    if (params === undefined || threadId === this.forumTopicId) {
      return;
    }
    this.persistDraftAndViewport();
    // 会话级退场走**同一份**清单（含 bgStore 与成员状态机），不在这里另抄一遍。
    this.disposeConversationSubscriptions();
    this.closeMessageStore();
    params['forumTopicId'] = threadId;
    params['topicName'] = name;
    this.navigationCoordinator.resetRouteApply();
    this.applyRouteParams();
  }

  // 点横条切话题：原地切，不 push 新页面。
  private onTopicBarSelect(threadId: number): void {
    const rows: ForumTopicRow[] = this.topicsStore.getRows();
    const hit: ForumTopicRow | undefined =
      rows.find((row: ForumTopicRow): boolean => row.threadId === threadId);
    this.switchTopic(threadId, hit !== undefined ? hit.name : '');
  }

  // 横条「+」：流程在 TopicManageFlow，建好后刷新横条并切过去。
  private onTopicCreate(): void {
    const chatId: number = this.chatId;
    createTopicFlow(this.getUIContext(), chatId).then((created: CreatedTopic | null): void => {
      if (created === null || chatId !== this.chatId) {
        return;
      }
      this.topicsStore.reload();
      this.switchTopic(created.threadId, created.name);
    });
  }

  // 长按话题删除；删的是正在看的就落到剩下的第一个（topicAfterDelete）。
  private onTopicLongPress(threadId: number): void {
    const rows: ForumTopicRow[] = this.topicsStore.getRows();
    const row: ForumTopicRow | undefined = rows.find((r: ForumTopicRow): boolean => r.threadId === threadId);
    if (row === undefined) {
      return;
    }
    const chatId: number = this.chatId;
    deleteTopicFlow(chatId, row).then((deleted: boolean): void => {
      if (!deleted || chatId !== this.chatId) {
        return;
      }
      const next: number = topicAfterDelete(rows, threadId, this.forumTopicId);
      this.topicsStore.reload();
      if (next !== this.forumTopicId) {
        const hit: ForumTopicRow | undefined = rows.find((r: ForumTopicRow): boolean => r.threadId === next);
        this.switchTopic(next, hit !== undefined ? hit.name : '');
      }
    });
  }

  private chromeGeometryInput(): ChatChromeGeometryInput {
    return {
      topSafe: this.topSafe,
      searchMode: this.search.mode,
      pinnedVisible: this.topCard.pinnedVisible(),
      musicVisible: this.topCard.musicVisible(),
      liveVisible: this.topCard.liveGroupCallId > 0 && this.topCard.liveCallIsActive,
      actionBarVisible: this.actionBarKind !== '',
      topicBarVisible: topicBarShown(this.topicBarCount, this.topicCreateAllowed)
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
    // **加载态与空态从镜像里取**，不直接读 messageLoadState / visibleGroupCount：
    // 那两个是普通字段，V2 不会因为它们变化而重算这一支（见镜像的声明处）。
    // 镜像还没初始化时退回直读，行为与以前一致。
    const parts: string[] = this.composerSlotKey.split('|');
    const loadState: string = parts.length > 1 ? parts[0] : this.timeline.messageLoadState;
    const hasRows: boolean = parts.length > 1
      ? parts[1] === '1' : this.timeline.visibleGroupCount > 0;
    return composerSlotState({
      isBot: this.isBotChat,
      membershipState: this.membershipState,
      loadState: loadState,
      visibleGroupCount: hasRows ? 1 : 0,
      threadRootId: this.threadRootId
    });
  }

  private composerBottomGap(): number {
    const tightForIme: boolean = (this.keyboardH > 0 && this.emojiDrawer.activeSlot === '') ||
      this.drawerClosingToIme;
    return bottomGapOf(
      tightForIme ? Math.max(1, this.keyboardH) : 0,
      tightForIme,
      this.bottomSafe
    );
  }

  private syncComposerBottomGap(): void {
    const nextGap: number = this.composerBottomGap();
    if (this.lastComposerBottomGap < 0) {
      this.lastComposerBottomGap = nextGap;
      return;
    }
    const deltaGap: number = nextGap - this.lastComposerBottomGap;
    this.lastComposerBottomGap = nextGap;
    if (!this.bottomChromeMeasured || Math.abs(deltaGap) < 0.5) {
      return;
    }
    this.bottomChromeH = Math.max(0, this.bottomChromeH + deltaGap);
  }

  // 输入框高度的测量整段下沉到了 ChatComposerInput（第二轮第 9 项）：三个几何
  // 常量本来就定义在那个文件里，宽度也是它自己 onAreaChange 量的，绕经页面
  // 存一个 @Local composerEditorW 再把结果作为 @Param 传回去，是一圈无谓的往返。
  // 随之删掉的还有 @Event onEditorWidthChange 与 @Param composerEditorHeight。

  private updateBottomChromeHeight(height: number): void {
    if (height <= 0) {
      return;
    }
    this.lastComposerBottomGap = this.composerBottomGap();
    const wasMeasured: boolean = this.bottomChromeMeasured;
    this.bottomChromeMeasured = true;
    if (Math.abs(height - this.bottomChromeH) < 0.5) {
      return;
    }
    const prevChromeH: number = this.bottomChromeH;
    const deltaChrome: number = height - prevChromeH;
    const keepTailVisible: boolean = (this.timeline.atBottom || this.imeTailPinned) && !this.viewerOpen();
    const drawerActive: boolean = this.emojiDrawer.shellHeight > 0 ||
      this.emojiDrawer.closingImeToDrawer || this.drawerClosingToIme;
    this.bottomChromeH = height;
    if (keepTailVisible) {
      this.timeline.atBottom = true;
      if (drawerActive) {
        this.timeline.glueBottom('L4617_sync');
      } else {
        const seq: number = ++this.bottomChromeLayoutSeq;
        setTimeout((): void => {
          if (seq === this.bottomChromeLayoutSeq && !this.timeline.listTouchActive && !this.viewerOpen()) {
            this.timeline.atBottom = true;
            this.timeline.glueBottom('L4617');
          }
        }, 0);
      }
    } else if (wasMeasured && this.timeline.didInitialScroll &&
      !this.timeline.initialTimelineMasked && this.timeline.groups.length > 0 &&
      !this.viewerOpen() && Math.abs(deltaChrome) >= 0.5) {
      if (drawerActive) {
        this.timeline.scroller.scrollBy(0, deltaChrome);
      } else {
        const seq: number = ++this.bottomChromeLayoutSeq;
        setTimeout((): void => {
          if (seq === this.bottomChromeLayoutSeq && !this.timeline.listTouchActive && !this.viewerOpen()) {
            this.timeline.scroller.scrollBy(0, deltaChrome);
          }
        }, 0);
      }
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

  private setEmojiExpanded(expanded: boolean): void {
    if (this.emojiDrawer.expanded === expanded) {
      return;
    }
    const startH: number = this.emojiDrawer.shellHeight > 0
      ? this.emojiDrawer.shellHeight
      : this.emojiDrawer.liftHeight(this.headerChromeHeight(), this.bottomSafe);
    this.emojiDrawer.closingExpanded = !expanded;
    this.emojiDrawer.expanded = expanded;
    const targetH: number = this.emojiDrawer.liftHeight(this.headerChromeHeight(), this.bottomSafe);
    const settle: number = this.chatEffectDuration(KEY_POWER_EFFECT_MENU, 210);
    this.animateDrawerTo(SLOT_EMOJI, targetH, settle, startH, 0, 0, 1, 1, false);
  }

  private setEmojiPanel(show: boolean): void {
    if (!show) { this.emojiDrawer.collapse(); }
    this.inputSwitch.cancel();
    if (this.showEmojiPanel === show && !this.emojiPanelClosing &&
      (show ? this.emojiDrawer.activeSlot === SLOT_EMOJI : this.emojiDrawer.activeSlot !== SLOT_EMOJI)) {
      return;
    }
    const seq = ++this.panelReadySeq;
    const settle: number = this.chatEffectDuration(KEY_POWER_EFFECT_MENU, 210);
    if (show) {
      this.emojiPanelClosing = false;
      this.composerFocused = false;
      this.drawerClosingToIme = false;
      this.emojiDrawer.closingToIme = false;
      const overlap: number = this.currentImeOverlap();
      const fromIme: boolean = overlap > 1 || this.keyboardH > 0;
      const wasDrawerOpen: boolean = this.emojiDrawer.shellHeight > 0;
      if (fromIme) {
        if (overlap > this.knownImeH) {
          this.knownImeH = overlap;
        } else if (this.keyboardH > this.knownImeH) {
          this.knownImeH = this.keyboardH;
        }
        this.emojiDrawer.closingImeToDrawer = true;
        this.armImeBridgeTimer(Math.max(320, settle + 120));
      } else {
        this.emojiDrawer.closingImeToDrawer = false;
      }
      const topOverlap: number = drawerTopOverlap(this.bottomSafe, false);
      const rawImeH: number = overlap > 1 ? overlap : this.keyboardH;
      const startH: number = wasDrawerOpen
        ? this.emojiDrawer.shellHeight
        : (fromIme ? Math.max(0, rawImeH - topOverlap) : 0);
      const fromOffsetY: number = wasDrawerOpen ? 8 : (fromIme ? 14 : Math.max(18, topOverlap + 4));
      const fromOpacity: number = wasDrawerOpen ? 0.92 : (fromIme ? 0.86 : 0.88);
      this.applyBottomSlot(openSlot(this.bottomSlot, SLOT_EMOJI));
      this.showEmojiPanel = true;
      this.emojiDrawer.activeSlot = SLOT_EMOJI;
      this.syncComposerBottomGap();
      // 收起系统键盘，把这块高度让给抽屉。
      this.composerController.stopEditing();
      const targetH: number = this.targetDrawerLiftHeight(SLOT_EMOJI);
      this.animateDrawerTo(SLOT_EMOJI, targetH, settle, startH, fromOffsetY, 0, fromOpacity, 1, false);
      if (!this.panelContentReady) {
        this.getUIContext().postFrameCallback(new ChatPageFrameCallback((): void => {
          if (seq === this.panelReadySeq && this.showEmojiPanel) {
            this.panelContentReady = true;
          }
        }));
      }
    } else if (this.pendingImeBridgeFromEmoji) {
      this.emojiPanelClosing = false;
      this.showEmojiPanel = false;
      this.applyBottomSlot(closeSlot(this.bottomSlot, SLOT_EMOJI));
      this.startDrawerToImeBridge(SLOT_EMOJI);
      this.syncComposerBottomGap();
    } else {
      this.clearImeBridge(true);
      this.showEmojiPanel = false;
      this.applyBottomSlot(closeSlot(this.bottomSlot, SLOT_EMOJI));
      if (this.emojiDrawer.activeSlot !== SLOT_EMOJI || this.emojiDrawer.shellHeight <= 0) {
        this.emojiPanelClosing = false;
        this.syncComposerBottomGap();
        return;
      }
      this.emojiPanelClosing = true;
      const closeDur: number = this.chatEffectDuration(KEY_POWER_EFFECT_MENU, 190);
      const startH: number = this.emojiDrawer.shellHeight;
      const topOverlap: number = drawerTopOverlap(this.bottomSafe, false);
      this.animateDrawerTo(
        SLOT_EMOJI,
        0,
        closeDur,
        startH,
        this.emojiDrawer.cardOffsetY,
        Math.max(18, topOverlap + 6),
        this.emojiDrawer.cardOpacity,
        0.82,
        false,
        (): void => {
          if (seq !== this.panelReadySeq) {
            return;
          }
          this.emojiDrawer.shellHeight = 0;
          this.emojiDrawer.activeSlot = '';
          this.emojiDrawer.cardOffsetY = 0;
          this.emojiDrawer.cardOpacity = 1;
          this.emojiPanelClosing = false;
          this.syncComposerBottomGap();
        }
      );
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
      showToast($r('app.string.cp_voice_unavailable'), 1600);
      return;
    }
    if (this.store !== null) {
      this.store.requestVideoDownload(messageId, false, entry.videoFailed);
    }
    showToast(entry.videoFailed ? $r('app.string.cp_redownloading_voice') : $r('app.string.cp_voice_loading'), 1400);
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
      showToast($r('app.string.sending'), 1200);
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
    if (!this.sendAccess.checkMedia(items)) { return; }
    const captionSnapshot: string = this.draft;
    const caption: string = captionSnapshot.trim();
    const replyId: number = this.composer.replyToId;
    this.command.closeMenu();
    // When the initial view is parked at an unread boundary, the loaded tail
    // is only the tail of the current window.  Do not treat it as the live
    // tail: the sent message would otherwise be appended after the gap and
    // become the apparent newest row before the missing pages are loaded.
    const needsLatestWindow: boolean = store.getHasMoreNewer();
    if (needsLatestWindow) {
      store.deferOutgoingForLatest();
    }
    if (!needsLatestWindow) {
      this.timeline.atBottom = true;
      this.timeline.stayAtUnread = false;
    }
    this.withSendLock((): Promise<void> => store.sendMedia(items, caption, replyId).then((): void => {
      this.pendingMedia = clearPendingMedia();
      if (this.draft === captionSnapshot) {
        this.draft = '';
        this.mention.clearPendingNameMentions();
      }
      if (this.composer.replyToId === replyId) {
        this.composer.clearReply();
      }
      if (needsLatestWindow && store.getHasMoreNewer()) {
        this.scrollToLatest();
      }
    }).catch((e: TdError): void => {
      logE(`ChatPage.sendMedia failed: ${e.message}`);
      showToast(e instanceof SendPermissionError ? e.message : $r('app.string.cp_photo_send_failed'), 2000);
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
    const needsLatestWindow: boolean = store.getHasMoreNewer();
    if (needsLatestWindow) {
      store.deferOutgoingForLatest();
    }
    if (!needsLatestWindow) {
      this.timeline.atBottom = true;
      this.timeline.stayAtUnread = false;
    }
    // 按名字提及的实体在这里生成：偏移必须相对**实际发出去的那串文本**，
    // 所以用 trim 之后的 text，不是原始草稿。
    const entities: TdObject[] = buildMentionEntities(text, this.mention.readPendingNameMentions());
    // 清空放在**发送之前**，不等应答。消息本身不用我们伪造回显：TDLib 会先
    // 发 updateNewMessage（自己发的消息在 onNewMessage 里是放行的），列表那边
    // 立刻就有一条 pending 的气泡。
    this.draft = '';
    store.resetTypingThrottle();
    this.mention.clearPendingNameMentions();
    if (this.composer.replyToId === replyId) {
      this.composer.clearReply();
    }
    this.mention.clear();
    this.command.clearItems();
    store.sendAsync(text, replyId, entities).then((): void => {
      // The local outgoing row is now present. Replace the around-unread
      // window with the real latest page so the gap below it becomes ordinary
      // older history that can be loaded while scrolling upward.
      if (needsLatestWindow && store.getHasMoreNewer()) {
        this.scrollToLatest();
      }
    }).catch((e: TdError): void => {
      logE(`ChatPage.doSend failed: ${e.message}`);
      // 提示语说的是"草稿已保留"，那就真的还回去。但用户可能已经开始写下
      // 一条了——那种情况不覆盖他的输入，只报错。
      if (this.draft === '') {
        this.draft = draftSnapshot;
        this.mention.restorePendingNameMentions(mentionsSnapshot);
      }
      showToast($r('app.string.cp_send_failed_kept'), 1800);
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
      showToast($r('app.string.cp_button_unsupported'), 1500);
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
    this.timeline.atBottom = true;
    this.timeline.stayAtUnread = false;
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
      showToast($r('app.string.send_failed_retry_short'), 1600);
    });
  }

  private findMsg(messageId: number): MessageEntry | null {
    for (const m of this.timeline.messages) {
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

  // 多选保存（issue #199）。挑选与分类是纯函数，下载与落盘在 MediaSaveState。
  private saveSelected(): void {
    const plan: SaveablePlan = saveableEntries(this.selection.entries(), this.selection.ids);
    if (plan.entries.length === 0) {
      showToast($r('app.string.cp_nothing_to_save'), 1600);
      return;
    }
    this.mediaSave.saveEntries(plan.entries);
    showToast(str('cp_save_selected_started', plan.entries.length), 1800);
    this.selection.exit();
  }

  private copySelected(): void {
    const sorted = [...this.selection.ids].sort((a: number, b: number) => a - b);
    const parts: string[] = [];
    const entries: MessageEntry[] = this.selection.entries();
    for (const id of sorted) {
      const m: MessageEntry | null = entries.find((entry: MessageEntry): boolean => entry.id === id) ?? null;
      if (m !== null && m.text !== '') {
        parts.push(m.text);
      }
    }
    if (parts.length === 0) {
      showToast($r('app.string.cp_nothing_to_copy'), 1500);
      return;
    }
    const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, parts.join('\n\n'));
    pasteboard.getSystemPasteboard().setData(data).then(() => {
      showToast(plural('cp_copied_n', parts.length, parts.length), 1200);
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
  // 单条删除成功后退出未开启的多选模式是无害的空操作。
  private deleteMessage(messageId: number): void {
    this.openDeleteConfirm([messageId]);
  }

  // 弹窗走 ComponentContent + UIContext.openCustomDialog，不再走
  // CustomDialogController：后者官方明写只在状态管理 V1 中使用，而本页要迁 V2。
  private openDeleteConfirm(ids: number[]): void {
    this.messageDelete.open(ids, this.timeline.messages.concat(this.selection.entries()),
      this.isGroup || this.isChannel ? '' : this.header.titleTextOf(), this.isGroup && !this.isChannel)
      .catch((e: Object): void => { logE(`ChatPage.openDeleteConfirm failed: ${e}`); });
  }

  // 消息 id → 行 id（相册整组共用一个 rowId），退场和完成等待交给独立通道。
  private markRowsLeaving(ids: number[]): Promise<void> {
    const rowIds = wholeDeleteRowIds(this.timeline.groups, ids);
    return this.rowLeave.play(rowIds, powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 550) > 0);
  }

  private copyMessageText(messageId: number): void {
    const m = this.findMsg(messageId);
    if (m === null || m.text === '') {
      showToast($r('app.string.cp_nothing_to_copy'), 1500);
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
      showToast($r('app.string.cp_nothing_to_copy'), 1500);
      return;
    }
    openSelectTextOverlay(this.getUIContext(), selectTextPayload(m), this.topSafe);
  }

  private copyMessageLink(messageId: number): void {
    if (this.store === null) {
      return;
    }
    this.store.messageLink(messageId, (url: string) => {
      // 私有会话的 t.me/c/… 只有本客户端能解析，换成本应用的 tg:// 形式后再复制，
      // 并在提示里说明适用范围（公开频道/群仍复制 https 链接）。
      const share: ShareableMessageLink = shareableMessageLink(this.chatId, messageId, url);
      if (share.link === '') {
        showToast($r('app.string.cp_no_link'), 1800);
        return;
      }
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, share.link);
      pasteboard.getSystemPasteboard().setData(data).then(() => {
        showToast(share.internal
            ? $r('app.string.link_copied_internal') : $r('app.string.link_copied'), share.internal ? 1800 : 1200);
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
        showToast($r('app.string.cp_no_messages_that_day'), 1600);
        return;
      }
      this.jumpToMessageId(id);
    }).catch((e: TdError): void => {
      // 404 是合法结果：该日期之前没有任何消息。
      const code: number = e.code !== undefined ? e.code : 0;
      showToast(code === 404 ? $r('app.string.cp_no_messages_before') : str('cp_jump_failed_msg', e.message), 1600);
    });
  }

  // 跳到指定消息：已在当前页就直接滚动并高亮，否则围绕它重新拉一页。
  // 定位后让目标气泡轻轻呼吸一次；「↓」返回与引用跳转共用这个反馈。
  private jumpToMessageId(targetId: number): void {
    this.jumpLandingUntil = Date.now() + JUMP_LANDING_GRACE_MS;
    this.beginJumpLanding();
    const gidx: number = groupIndexOf(this.timeline.groups, targetId);
    logW(`[Jump80] jumpToMessageId target=${targetId} idxInLoaded=${gidx} rows=${this.timeline.groups.length}`);
    if (gidx >= 0) {
      this.timeline.scrollToJumpTarget(gidx);
      this.flash.flashAtIndex(gidx, targetId);
      return;
    }
    this.pendingJumpId = targetId;
    this.store?.loadAround(targetId, (found: boolean): void => {
      if (!found && this.pendingJumpId === targetId) {
        this.pendingJumpId = 0;
        showToast($r('app.string.cp_cannot_jump'), 1500);
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

  private recognizeSpeech(messageId: number): void {
    this.store?.recognizeSpeech(messageId).catch((e: TdError): void => {
      const message: string = e.message !== undefined ? e.message : '';
      showToast(message.indexOf('PREMIUM') >= 0 || message.indexOf('premium') >= 0
          ? $r('app.string.cp_transcribe_premium') : str('cp_transcribe_failed_msg', message), 2200);
    });
  }

  // openReactionSheet 整体搬进了 ChatOverlayState（B11 批），经
  // host.findMsg 转发；调用点改为 this.overlayState.openReactionSheet(messageId)。

  // Chat-level auto-delete timer (阅后即焚).
  private chooseAutoDelete(): void {
    const labels: string[] = [str('close'), str('ps_1_day'), str('ps_1_week'), str('ps_1_month')];
    const seconds: number[] = [0, 86400, 604800, 2678400];
    this.getUIContext().getPromptAction().showActionMenu({
      title: $r('app.string.cp_auto_delete_title'),
      buttons: labels.map((text: string): promptAction.Button =>
        ({ text, color: '#3390EC' } as promptAction.Button)) as
        [promptAction.Button, promptAction.Button?, promptAction.Button?,
          promptAction.Button?, promptAction.Button?, promptAction.Button?]
    }).then((chosen): void => {
      const value = seconds[chosen.index];
      if (value === undefined) { return; }
      this.store?.setAutoDeleteAsync(value).then((): void => {
        this.header.autoDeleteTime = value;
        showToast(value === 0 ? $r('app.string.cp_auto_delete_off') : str('cp_auto_delete_after', labels[chosen.index]), 1800);
      }).catch((e: TdError): void => {
        logE(`ChatPage.autoDelete failed: ${e.message}`);
        showToast($r('app.string.cp_setting_failed_permission'), 1700);
      });
    }).catch((): void => {});
  }

  // Long-press the send button: schedule or send silently.
  private showSendOptions(): void {
    if (this.draft.trim() === '' || this.composer.editingId !== 0) { return; }
    const labels: string[] = [str('cp_send_silently'), str('cp_send_in_1h'), str('cp_send_tomorrow_9')];
    this.getUIContext().getPromptAction().showActionMenu({
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
        showToast(sendDate > 0 ? $r('app.string.cp_scheduled') : $r('app.string.cp_sent_silently'), 1600);
      }).catch((e: TdError): void => {
        logE(`ChatPage.sendScheduled failed: ${e.message}`);
        showToast($r('app.string.send_failed'), 1600);
      });
    }).catch((): void => {});
  }

  // "正在输入…" 提示的状态与到期定时器由 TypingIndicatorState 管理
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
      if (text !== '') {
        this.draft = text;
        // 服务端那份（别的端写的）也进本地缓存，列表跟着显示。
        rememberLocalDraft(this.chatId, text);
        bumpDraftEpoch();
      }
    }).catch((e: TdError): void => {
      logW(`[Draft] restore chat=${this.chatId} failed: ${e.message}`);
    });
  }

  // showReactors、closeReactionSheet 整体搬进了 ChatOverlayState（B11 批），
  // 经 host.chatId 转发；调用点分别改为 this.overlayState.showReactors(...)、
  // this.overlayState.closeReactionSheet()。

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
      showToast(e.message.indexOf('MESSAGE_NOT_MODIFIED') >= 0
          ? $r('app.string.cp_no_change') : $r('app.string.cp_edit_failed'), 1800);
    }));
  }

  private replyKbVisible(): boolean {
    return replyKeyboardVisible(
      this.membershipState, this.replyKeyboard !== null, this.replyKbCollapsed);
  }

  private composerPlaceholder(): string {
    return placeholderOf('', this.replyKbVisible(),
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
    this.clearImeBridge(true);
    this.closeAttachPanel(true);
    this.setEmojiPanel(false);
  }

  private toggleAttachPanel(): void {
    const next: string = toggleSlot(this.bottomSlot, SLOT_ATTACH);
    if (next !== SLOT_ATTACH) {
      this.clearImeBridge(true);
      this.closeAttachPanel(true);
      return;
    }
    this.inputSwitch.cancel();
    this.emojiDrawer.collapse();
    this.showEmojiPanel = false;
    this.emojiPanelClosing = false;
    this.composerFocused = false;
    this.drawerClosingToIme = false;
    this.emojiDrawer.closingToIme = false;
    const settle: number = this.chatEffectDuration(KEY_POWER_EFFECT_MENU, 210);
    const overlap: number = this.currentImeOverlap();
    const fromIme: boolean = overlap > 1 || this.keyboardH > 0;
    const wasDrawerOpen: boolean = this.emojiDrawer.shellHeight > 0;
    if (fromIme) {
      if (overlap > this.knownImeH) {
        this.knownImeH = overlap;
      } else if (this.keyboardH > this.knownImeH) {
        this.knownImeH = this.keyboardH;
      }
      this.emojiDrawer.closingImeToDrawer = true;
      this.armImeBridgeTimer(Math.max(320, settle + 120));
    } else {
      this.emojiDrawer.closingImeToDrawer = false;
    }
    const topOverlap: number = drawerTopOverlap(this.bottomSafe, false);
    const rawImeH: number = overlap > 1 ? overlap : this.keyboardH;
    const startH: number = wasDrawerOpen
      ? this.emojiDrawer.shellHeight
      : (fromIme ? Math.max(0, rawImeH - topOverlap) : 0);
    const fromOffsetY: number = wasDrawerOpen ? 8 : (fromIme ? 14 : Math.max(18, topOverlap + 4));
    const fromOpacity: number = wasDrawerOpen ? 0.92 : (fromIme ? 0.86 : 0.88);
    this.composerController.stopEditing();
    this.applyBottomSlot(next);
    this.emojiDrawer.activeSlot = SLOT_ATTACH;
    this.syncComposerBottomGap();
    const targetH: number = this.targetDrawerLiftHeight(SLOT_ATTACH);
    this.animateDrawerTo(SLOT_ATTACH, targetH, settle, startH, fromOffsetY, 0, fromOpacity, 1, false);
  }

  private closeAttachPanel(animate: boolean = false): void {
    if (!animate || this.emojiDrawer.activeSlot !== SLOT_ATTACH || this.emojiDrawer.shellHeight <= 0) {
      this.applyBottomSlot(closeSlot(this.bottomSlot, SLOT_ATTACH));
      if (this.emojiDrawer.activeSlot === SLOT_ATTACH) {
        this.emojiDrawer.shellHeight = 0;
        this.emojiDrawer.activeSlot = '';
        this.emojiDrawer.cardOffsetY = 0;
        this.emojiDrawer.cardOpacity = 1;
      }
      this.syncComposerBottomGap();
      return;
    }
    const seq: number = ++this.panelReadySeq;
    this.applyBottomSlot(closeSlot(this.bottomSlot, SLOT_ATTACH));
    const closeDur: number = this.chatEffectDuration(KEY_POWER_EFFECT_MENU, 190);
    const startH: number = this.emojiDrawer.shellHeight;
    const topOverlap: number = drawerTopOverlap(this.bottomSafe, false);
    this.animateDrawerTo(
      SLOT_ATTACH,
      0,
      closeDur,
      startH,
      this.emojiDrawer.cardOffsetY,
      Math.max(18, topOverlap + 6),
      this.emojiDrawer.cardOpacity,
      0.82,
      false,
      (): void => {
        if (seq !== this.panelReadySeq) {
          return;
        }
        this.emojiDrawer.shellHeight = 0;
        this.emojiDrawer.activeSlot = '';
        this.emojiDrawer.cardOffsetY = 0;
        this.emojiDrawer.cardOpacity = 1;
        this.syncComposerBottomGap();
      }
    );
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
      if (this.search.mode) {
        // 搜索与多选同开：多选的操作叠在搜索条上面（顶栏归搜索框）。
        if (this.selection.active) {
          this.selectionBar(false);
        }
        SearchSenderPanel({ search: this.search });
        this.searchDock();
      } else if (this.selection.active) {
        // Selection owns the header actions; removing the composer also drops
        // its reserved list inset so messages expand naturally into the space.
        Column().width('100%').height(0);
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
    //
    // 它和贴纸合集一样是 bindSheet，同样要登记：不登记的话分享进来的那一刻
    // dismissAllSheets() 收不掉它，Index 那层「分享到…」继续被它盖住，返回键也
    // 关不掉（登记了 handleBackPressed 的第一句就会先收它）。
    .bindSheet($$this.diceSheetOpen, this.diceSheet(), {
      height: 320,
      // **不能写 Color.Transparent。** 那张表的前提是「材质/模糊一定在」：
      // 材质全关（设置里把厚度调到关闭）时 blurStyle 和 systemMaterial 都退化，
      // 底色又透明 → 整个抽屉没有背景，聊天内容直接透上来
      // （2026-11-03 用户报的「材质全关时贴纸添加抽屉背景消失」）。
      // overlayGlassFill 在材质关时原样返回石头色，材质在时才交给材质。
      backgroundColor: overlayGlassFill('dialog', $r('app.color.surface')),
      dragBar: false,
      blurStyle: containerBlur('dialog'), systemMaterial: overlayMaterial('dialog'),
      onAppear: (): void => {
        if (this.diceSheetOff === null) {
          this.diceSheetOff = pushSheetDismiss((): void => { this.diceSheetOpen = false; });
        }
      },
      // 拖动下拉 / 点遮罩关的那一刻不会经过 setDiceSheetOpen，注销只能挂在这里。
      // 返回键关的那一次登记项已经被弹掉了，这里再注销是幂等的空操作。
      onDisappear: (): void => {
        if (this.diceSheetOff !== null) {
          this.diceSheetOff();
          this.diceSheetOff = null;
        }
      }
    });
  }

  // 搜索态底栏：结果计数 + 上一条/下一条导航。
  @Builder
  private searchDock() {
    SearchBottomBar({
      search: this.search,
      bottomGap: this.composerBottomGap(),
      onOlder: (): void => { this.search.older(); },
      onNewer: (): void => { this.search.newer(); },
      onPublicPosts: (tag: string): void => {
        navigateToSearch({ 'query': tag } as Record<string, Object>);
      }
    });
  }

  // 不可写态底栏：入群 / 静音开关 / 启动 bot 的成员资格条。
  @Builder
  private membershipDock() {
    MembershipBar({
      materialEpoch: this.materialEpoch,
      state: this.composerSlot(),
      restrictedUntil: this.membershipRestrictedUntil,
      isMuted: this.header.isMuted,
      joining: this.joiningChat,
      joinByRequest: this.joinByRequest,
      secretOutbound: this.header.secretOutbound,
      bottomGap: this.composerBottomGap(),
      onJoin: (): void => { this.joinCurrentChat(); },
      onJoinToFolder: (anchorId: string): void => {
        openJoinFolderMenu(this.getUIContext(), anchorId, (folderId: number): void => {
          this.joinCurrentChat(folderId);
        });
      },
      onToggleMute: (): void => { this.header.toggleMute(); },
      onStartBot: (): void => { this.sendBotCommand(BOT_START_COMMAND); }
    });
  }

  // 可写态底栏的完整输入树由 ChatComposerHost 持有；页面只接会话状态、
  // 发送动作和几何回调。搜索态与成员资格态仍由 bottomDock 留在页面。
  @Builder
  private composerDock() {
    ChatComposerHost({
      composer: this.composer,
      commandSuggestion: this.command,
      recording: this.recording,
      emojiDrawer: this.emojiDrawer,
      sendAccess: this.sendAccess,
      appDark: this.appDark,
      attachPanelOpen: this.attachPanelOpen,
      pendingMedia: this.pendingMedia,
      showEmojiPanel: this.showEmojiPanel && !this.emojiPanelClosing,
      composerEditorReady: this.composerEditorReady,
      editorFocused: this.composerFocused,
      keyboardVisible: this.keyboardH > 0,
      draft: this.draft,
      composerPlaceholder: this.composerPlaceholder(),
      composerController: this.composerController,
      sendByEnter: this.sendByEnter,
      replyKeyboard: this.replyKeyboard,
      replyKbCollapsed: this.replyKbCollapsed,
      botMiniAppUrlValue: this.header.botMiniAppUrl,
      composerSending: this.composerSending,
      replyKeyboardVisible: this.replyKbVisible(),
      replyKeyboardSendingKey: this.replyKeyboardSendingKey,
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
        this.inputSwitch.toggleEmoji();
        this.mention.clear();
        this.command.closePanel();
      },
      onDraftChange: (value: string): void => {
        const prev = this.draft;
        this.draft = value;
        this.updateSuggestions(value);
        if (!this.composerFocused || value === prev || this.composer.editingId !== 0) {
          return;
        }
        if (value.trim() !== '') {
          this.store?.notifyTyping();
        } else {
          this.store?.cancelTyping();
        }
      },
      onSubmit: (): void => {
        if (this.sendByEnter) { this.doSend(); }
      },
      onEditorFocus: (): void => {
        this.imeTailPinned = this.timeline.atBottom && !this.viewerOpen();
        this.composerFocused = true;
        holdPlayerJobs(KEYBOARD_SETTLE_MS);
        if (this.showEmojiPanel) {
          this.pendingImeBridgeFromEmoji = true;
          this.setEmojiPanel(false);
          this.pendingImeBridgeFromEmoji = false;
        } else if (this.attachPanelOpen) {
          this.applyBottomSlot(closeAllSlots());
          this.startDrawerToImeBridge(SLOT_ATTACH);
        }
        this.applyBottomSlot(closeAllSlots());
        this.command.closeMenu();
        if (this.keyboardH > 0) { this.syncTailOnImeFrame(); }
      },
      onEditorBlur: (): void => {
        this.composerFocused = false;
      },
      onEditorAreaChange: (area: Area | undefined): void => { this.composerEditorArea = area; },
      onActivateEditor: (): void => { this.inputSwitch.showKeyboard(); },
      onScheduleEditorMount: (): void => { this.scheduleComposerEditorMount(); },
      onToggleReplyKeyboard: (): void => { this.toggleReplyKeyboard(); },
      onOpenMiniApp: (): void => { this.openBotMiniApp(); },
      onRecord: (): void => { this.recording.start(); },
      onSend: (): void => { this.doSend(); },
      onSendOptions: (): void => { this.showSendOptions(); },
      onReplyKeyboardButton: (button: KeyboardBtn, key: string): void => {
        this.onReplyKeyboardTap(button, key);
      },
      onHeightChange: (height: number): void => { this.updateBottomChromeHeight(height); },
      menuEffectDuration: (duration: number): number =>
        this.chatEffectDuration(KEY_POWER_EFFECT_MENU, duration),
      replyEffectDuration: (duration: number): number =>
        this.chatEffectDuration(KEY_POWER_EFFECT_REPLY, duration),
      smoothEffectDuration: (duration: number): number =>
        powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, duration)
    });
  }

  @Builder
  private bottomDrawerDock() {
    if (!this.search.mode && !this.selection.active && this.composerSlot() === 'writable') {
      ChatBottomDrawerHost({
        emojiDrawer: this.emojiDrawer,
        sendAccess: this.sendAccess,
        attachPanelOpen: this.attachPanelOpen,
        showEmojiPanel: this.showEmojiPanel && !this.emojiPanelClosing,
        panelContentReady: this.panelContentReady,
        emojiPanelClosing: this.emojiPanelClosing,
        emojiPanelTab: this.emojiPanelTab,
        bottomSafe: this.bottomSafe,
        drawerHeight: this.emojiDrawer.cardHeight(this.headerChromeHeight(), this.bottomSafe),
        accentColor: this.accent(),
        chatId: this.chatId,
        isGroup: this.isGroup,
        isChannel: this.isChannel,
        onAttachPick: (key: string): void => { this.attach.runAttachAction(key); },
        onEmojiPick: (emoji: string): void => { this.insertEmoji(emoji); },
        onCustomEmojiPick: (emoji: string, customEmojiId: string): void => {
          if (this.store === null || !this.sendAccess.check('sendMessages')) { return; }
          this.timeline.atBottom = true;
          this.store.sendCustomEmoji(emoji, customEmojiId);
          this.overlayState.flyStickerGhost('', 0, 0);
        },
        onStickerPick: (sticker: StickerItem, x: number, y: number): void => {
          if (!this.sendAccess.check('sendOtherMessages') || this.store === null) { return; }
          this.timeline.atBottom = true;
          this.store.sendSticker(sticker.fileId, sticker.width, sticker.height);
          this.overlayState.flyStickerGhost(sticker.thumbPath, x, y);
        },
        onGifPick: (gif: GifItem): void => {
          if (!this.sendAccess.check('sendOtherMessages') || this.store === null) { return; }
          this.timeline.atBottom = true;
          if (gif.resultId !== '') {
            sendInlineResult(this.chatId, gif.queryId, gif.resultId, 0, true)
              .catch((e: TdError): void => { logE(`ChatPage.sendInlineGif failed: ${e.message}`); });
          } else {
            this.store.sendAnimation(gif.fileId, gif.width, gif.height, gif.duration);
          }
          this.overlayState.flyStickerGhost('', 0, 0);
        },
        onEmojiTabChange: (tab: number): void => { this.emojiPanelTab = tab; },
        onEmojiExpanded: (expanded: boolean): void => { this.setEmojiExpanded(expanded); },
        menuEffectDuration: (duration: number): number =>
          this.chatEffectDuration(KEY_POWER_EFFECT_MENU, duration)
      });
    }
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
    const farFromEnd: boolean = this.timeline.groups.length - this.timeline.curStartIdx > JUMP_RELOAD_THRESHOLD;
    const probeSeq: number = this.jumpLatestSeq;
    if (this.store.getHasMoreNewer() || farFromEnd) {
      const actionSeq: number = ++this.timeline.scrollActionSeq;
      this.scrollToBottomBusy = true;
      this.pendingScrollBottom = true;
      logW(`[JumpLatest] #${probeSeq} path=reload farFromEnd=${farFromEnd}` +
        ` actionSeq=${actionSeq} ${this.scrollStateProbe()}`);
      this.store.jumpToLatest((success: boolean): void => {
        if (actionSeq !== this.timeline.scrollActionSeq) {
          // 早退：这次点击的意图已经被更强的定位动作作废。不打这一行的话，
          // scrollToBottomBusy 卡住导致后续点击全被吞掉就查不出来。
          logW(`[JumpLatest] #${probeSeq} reload stale actionSeq=${actionSeq}` +
            ` cur=${this.timeline.scrollActionSeq} busyStuck=${this.scrollToBottomBusy}`);
          return;
        }
        this.scrollToBottomBusy = false;
        logW(`[JumpLatest] #${probeSeq} reload done success=${success}` +
          ` ${this.scrollStateProbe()}`);
        if (!success) {
          this.clearPendingScrollBottom('reloadFailed');
          this.timeline.atBottom = false;
          showToast($r('app.string.cp_latest_failed'), 1600);
        } else if (this.timeline.groups.length === 0) {
          this.clearPendingScrollBottom('emptyGroups');
          this.timeline.atBottom = true;
        }
      }, probeSeq);
      return;
    }
    // Close to the end and fully loaded — snap instantly, no animated crawl.
    const actionSeq: number = ++this.timeline.scrollActionSeq;
    const snapIndex: number = Math.max(0, this.timeline.groups.length - 1);
    logW(`[JumpLatest] #${probeSeq} path=snap call=scrollToIndex index=${snapIndex}` +
      ` actionSeq=${actionSeq} ${this.scrollStateProbe()}`);
    this.timeline.scroller.scrollToIndex(snapIndex, false, ScrollAlign.END);
    setTimeout((): void => {
      if (actionSeq !== this.timeline.scrollActionSeq) {
        logW(`[JumpLatest] #${probeSeq} snap settle stale actionSeq=${actionSeq}` +
          ` cur=${this.timeline.scrollActionSeq}`);
        return;
      }
      this.timeline.glueBottom('L7961');
      this.timeline.refreshAtBottom();
      logW(`[JumpLatest] #${probeSeq} snap landed call=scrollEdge ${this.scrollStateProbe()}`);
    }, 60);
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
      this.timeline.olderArmed = false;
      this.store.retryOlder();
    } else if (mode === TL_NEWER_ERROR) {
      this.store.retryNewer();
    }
  }

  // 多选操作栏：单独多选时在顶栏（带🔍，可以接着进搜索），与搜索同开时在底栏
  // （不带🔍，已经在搜了）。参数两处一模一样，只写这一份。
  @Builder
  selectionBar(showSearch: boolean) {
    SelectionHeader({
      materialEpoch: this.materialEpoch,
      selection: this.selection,
      topSafe: 0,
      showSearch: showSearch,
      onSearch: (): void => { this.search.enter(); },
      onExit: (): void => { this.selection.exit(); },
      onForward: (): void => { this.messageActionsState.openForwardPicker(this.selection.ids); },
      onSave: (): void => { this.saveSelected(); },
      canBackgroundCache: selectionHasCacheableVideo(this.selection.entries(), this.selection.ids),
      onBackgroundCache: (): void => {
        cacheMessagesInBackground(this.getUIContext().getHostContext() as common.UIAbilityContext, this.selection.entries(), this.selection.ids,
          this.chatId);
        this.selection.exit();
      },
      onCopy: (): void => { this.copySelected(); },
      onDelete: (): void => { this.deleteSelected(); }
    });
  }

  @Builder
  chatTitleBar() {
    Column() {
      // 搜索优先：多选与搜索可以同时开着（用户要求），这时顶栏留给搜索框（还能改
      // 关键词），多选的操作挪到底栏、叠在搜索条上面（见 bottomDock）。
      if (this.search.mode) {
        SearchHeader({
          search: this.search,
          topSafe: 0,
          onExit: (): void => { this.search.exit(); },
          onQueryChange: (v: string): void => { this.search.updateQuery(v); },
          onSubmit: (): void => { this.search.run(0, 0); }
        });
      } else if (this.selection.active) {
        this.selectionBar(true);
      } else {
        ChatHeader({
          animationsAllowed: this.contentAnimationsAllowed,
          appearanceEpoch: this.appearanceEpoch,
          materialEpoch: this.materialEpoch,
          onLightBg: this.chromeOnLightBg(),
          onDarkBg: this.chromeOnDarkBg(),
          appDark: this.appDark,
          // B8：上面那 12 个标量 @Param 换成一个控制器引用——ChatHeader 直接
          // 持有 header、在自己的 build()/@Builder 里读 @Trace，本页不再算
          // titleText/subtitleText 等经 @Param 转手。
          header: this.header,
          typing: this.typing,
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
    .width('100%');
  }

  @Builder
  chatTitleBarBottom() {
    // 13 个标量 @Param 换成一个控制器引用（B5）。this.topCard 是字段初始化器
    // new 出来的，引用全生命周期不变——@Param 那层的 `!==` 永不成立，本页重建
    // 不会让浮卡整体白刷；显示态由 TopBanners 自己在 build() 里读 @Trace。
    // 千万不要在这里现场 new 任何对象传下去，那会破坏引用稳定、让子组件每帧白刷。
    Column() {
      if (topicBarShown(this.topicBarCount, this.topicCreateAllowed)) {
        ChatTopicBar({
          source: this.topicRowsData,
          selectedThreadId: this.forumTopicId,
          rowCount: this.topicBarCount,
          scroller: this.topicBarScroller,
          canCreate: this.topicCreateAllowed,
          onSelect: (threadId: number): void => { this.onTopicBarSelect(threadId); },
          onCreate: (): void => { this.onTopicCreate(); },
          onLongPressTopic: (threadId: number): void => { this.onTopicLongPress(threadId); }
        });
      }
      TopBanners({
      appDark: this.appDark,
      materialEpoch: this.materialEpoch,
      topCard: this.topCard,
      onPinnedTap: (): void => { this.topCard.onPinnedTap(); },
      onOpenPinnedList: (): void => { this.overlayState.setSheet('pinnedList', true); },
      onLiveStreamTap: (): void => { this.topCard.onLiveStreamTap(); },
      onMusicTap: (): void => { navigateToSetting('MusicCenterPage'); },
      actionBarKind: this.actionBarKind,
      actionBarCanUnarchive: this.actionBarCanUnarchive,
      onActionBarAction: (id: string): void => { this.onActionBar(id); },
      onActionBarDismiss: (): void => { dismissActionBar(this.chatId); }
      });
    }
    .width('100%');
  }

  // 传给 HdsNavDestination 的 .titleBar()。**引用必须稳定。**
  //
  // 【为什么】(2026-09-11 帧 trace) 原来这里每次 ChatPage.build() 都现 new 一个
  // options、外带一个新的 stackBuilder 闭包交给 HDS，于是整条标题栏跟着销毁重建：
  // ChatHeader 4.05ms + TopBanners 2.15ms + AvatarView + CachedImage，一次录制里
  // **22 次，其中 17 次落在卡顿帧上**。chatTitleBarBottom 上面那句「千万不要在这里
  // 现场 new 任何对象传下去」说的就是这件事，只是漏了它自己这一层。
  //
  // 栏里的内容照样会更新：两个 builder 的**函数体**在各自的渲染上下文里读
  // selection/search/topCard 这些 @Trace，值变了由它们自己刷新，与外面这个 options
  // 对象的身份无关。这里只在**结构**真的变了（横幅出现/消失/改高）时才换新对象。
  private titleBarContentCache: TitleBarContentOptions | null = null;
  private titleBarBannerHeight: number = -1;

  // 整份 titleBar 选项也缓存：style 里那三个字面量是常量，而 $r() 每调一次都
  // 是一个新 Resource 对象，光稳住 content 还不够。结构变了（content 换新）
  // 才重建。
  private titleBarOptionsCache: HdsNavigationTitleBarOptions | null = null;

  private chatTitleBarOptions(): HdsNavigationTitleBarOptions {
    const content: TitleBarContentOptions = this.chatTitleBarContent();
    const cached: HdsNavigationTitleBarOptions | null = this.titleBarOptionsCache;
    if (cached !== null && cached.content === content) {
      return cached;
    }
    const options: HdsNavigationTitleBarOptions = {
      avoidLayoutSafeArea: true,
      // 消息 List 自己用 contentStartOffset 保留稳定锚点；这里不重复挤内容区。
      enableComponentSafeArea: false,
      // 第三个参数 false = 静态栏：滑动时不变；第四个参数 false = 不挂 HDS 整条栏系统材质与
      // BlurStrategy.ENABLE（顶栏三颗胶囊已在 ChatHeader 里自绘毛玻璃，避免再挂整页滤镜节点）。
      style: titleBarStyle(Color.Transparent, $r('app.color.text_primary'), false, false),
      content: content
    };
    this.titleBarOptionsCache = options;
    return options;
  }

  private chatTitleBarContent(): TitleBarContentOptions {
    // 操作条要单独算进来：topCard.shouldShow() 只看置顶和直播（它是那两样的控制器），
    // 陌生人私聊恰好两样都没有，槽高被算成 0，操作条的数据到了也没地方画
    // （2026-09-29 实测：页面拿到 chatActionBarReportAddBlock，顶上什么都没有）。
    const bannerHeight: number =
      this.timeline.initialMessageTransitionSettled && (this.topCard.shouldShow() || this.actionBarKind !== '')
        ? this.topBannerHeight() : 0;
    // 槽里现在装两样：话题横条（在上）+ 置顶/直播/操作条（在下）。缓存键必须用
    // **两者之和**，否则话题出现或消失时槽不会重新量高，横条会被裁掉或留下空白。
    const slotHeight: number = chatTopicBarHeight(this.chromeGeometryInput()) + bannerHeight;
    const cached: TitleBarContentOptions | null = this.titleBarContentCache;
    if (cached !== null && this.titleBarBannerHeight === slotHeight) {
      return cached;
    }
    const content: TitleBarContentOptions = {
      stackBuilder: (): void => { this.chatTitleBar(); }
    };
    if (slotHeight > 0) {
      content.bottomBuilder = {
        builder: (): void => { this.chatTitleBarBottom(); },
        height: slotHeight
      };
    }
    this.titleBarContentCache = content;
    this.titleBarBannerHeight = slotHeight;
    return content;
  }

  @Builder
  mediaViewer() {
    MediaViewerOverlay({
      underlay: this.viewer.underlay,
      closing: this.viewer.viewerClosing,
      topSafe: this.topSafe,
      viewerMsgId: this.viewer.viewerMsgId,
      onViewerMsgIdChange: (msgId: number): void => { this.viewer.updateTarget(msgId); },
      chromeVisible: this.viewer.chromeVisible,
      onChromeVisibleChange: (visible: boolean): void => { this.viewer.setChromeVisible(visible); },
      videoLandscape: this.viewer.viewerVideoLandscape,
      onVideoLandscapeChange: (landscape: boolean): void => { this.viewer.setVideoLandscape(landscape); },
      messages: this.timeline.messages,
      groups: this.timeline.timelineRows,
      onNeedHistory: (dir: number): void => {
        if (dir < 0) {
          this.store?.loadOlder();
        } else if (dir > 0) {
          this.store?.loadNewer();
        }
      },
      initIdx: this.viewer.viewerInitIdx,
      initStartPositionMs: this.viewer.viewerStartPositionMs,
      store: this.store,
      chatId: this.chatId,
      chatTitle: this.header.title,
      nowSec: this.nowSec,
      onRequestClose: (): void => { this.closeViewer(); },
      // S2：entry 由页面在这里取好传进去，MediaSaveState 不再经宿主取值器
      // 现读 viewerMsgId（见该文件 saveMediaEntry 上方的说明）。
      onSaveMedia: (): void => { this.saveCurrentViewerMedia(false); },
      // 实况打开即下全片：存回图库要真实文件，而流式播放不会产生它。
      // 理由见 MediaViewerOverlay.onEnsureLiveDownload 的注释。
      onEnsureLiveDownload: (messageId: number): void => {
        const entry = this.entryById(messageId);
        if (entry !== null && this.store !== null) {
          this.store.requestVideoDownload(messageId, true, entry.videoFailed);
        }
      },
      onSaveMediaToFiles: (): void => { this.saveCurrentViewerMedia(true); },
      onShowInChat: (): void => { this.showViewerMediaInChat(); },
      onShowAllMedia: (): void => { this.showAllChatMedia(); },
      onPositionChanged: (positionMs: number): void => { this.viewer.viewerPositionMs = positionMs; }
    });
  }

  @Builder
  surfaceTimeline() {
    ChatTimelineHost({
      session: this.timeline,
      selection: this.selection,
      rowPageInputs: this.rowPageInputs,
      actions: this.messageActions(),
      reusePageScope: this.reusePageScope,
      nowSec: this.nowSec,
      listCachedCount: this.listCachedCount,
      appearanceEpoch: this.appearanceEpoch,
      headerStartOffset: this.headerChromeHeight(),
      bottomChromeH: this.bottomChromeH,
      threadRootId: this.threadRootId,
      membershipState: this.membershipState,
      screenW: this.screenW,
      langEpoch: this.langEpoch,
      materialEpoch: this.materialEpoch,
      timelineTopMargin: this.headerChromeHeight() + 8,
      onEmptyRetry: (): void => { this.store?.retryInitialHistory(); },
      // mode 由宿主传上来——它是**用户实际看到的那枚 pill** 算出来的。
      // 页面自己重算过一版，读的是活字段而不是发布出去的快照，两者会分叉
      // （见 timelineStateRetry 上方的说明），分叉时这个按钮点了没反应。
      onTimelinePillRetry: (mode: string): void => {
        this.timelineStateRetry(mode);
      }
    });
  }

  @Builder
  surfaceOverlays() {
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
    AudioFavoriteFlow({
      targetMessageId: this.favoriteAudioId,
      chatId: this.chatId,
      trackTitle: this.audioTitleOf(this.favoriteAudioId),
      trackArtist: this.audioPerformerOf(this.favoriteAudioId),
      bottomSafe: this.bottomSafe,
      onClose: (): void => { this.favoriteAudioId = 0; }
    });
    ChatOverlayHost({
      selection: this.selection,
      overlayState: this.overlayState,
      messages: this.timeline.messages,
      chatId: this.chatId,
      threadRootId: this.threadRootId,
      store: this.store,
      bottomSafe: this.bottomSafe,
      keyboardH: this.keyboardH,
      topInset: this.headerChromeHeight(),
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
        quizMode: boolean, correctOptionId: number): void => {
        if (!this.sendAccess.check('sendPolls')) { return; }
        this.overlayState.showPollSheet = false;
        if (this.store !== null) {
          this.timeline.atBottom = true;
          this.store.sendPoll(question, options, isAnonymous, quizMode, correctOptionId);
        }
      },
      onPollClose: (): void => {
        this.overlayState.showPollSheet = false;
      },
      onContactPick: (contact: PickedContact): void => {
        if (!this.sendAccess.check('sendMessages')) { return; }
        this.overlayState.showContactSheet = false;
        if (this.store !== null) {
          this.timeline.atBottom = true;
          this.store.sendContact(
            contact.phone, contact.firstName, contact.lastName, contact.userId);
        }
      },
      onContactClose: (): void => {
        this.overlayState.showContactSheet = false;
      },
      onVideoCaptured: (path: string, durationSec: number, length: number): void => {
        if (!this.sendAccess.check('sendVideoNotes')) { return; }
        if (this.store !== null) {
          this.timeline.atBottom = true;
          this.store.sendVideoNote(path, durationSec, length);
        }
      },
      onVideoClose: (): void => {
        this.overlayState.showVideoNoteRecorder = false;
      },
      onPinnedJump: (messageId: number): void => { this.onReplyTap(messageId); },
      effectDuration: (key: string, ms: number): number => this.chatEffectDuration(key, ms)
    });
  }

  // Keep navigation, the fullscreen viewer and root events at the page boundary.
  build() {
    HdsNavDestination() {
    Stack() {
      ChatPageSurface({
        timeline: this.timeline,
        viewer: this.viewer,
        overlayState: this.overlayState,
        emojiDrawer: this.emojiDrawer,
        chatBg: this.chatBg,
        screenW: this.screenW,
        screenH: this.screenH,
        surfaceActive: this.surfaceActive,
        chatBgBlur: this.chatBgBlur,
        chatBgPattern: this.chatBgPattern,
        chatBgDim: this.chatBgDim,
        timelineContent: (): void => { this.surfaceTimeline(); },
        bottomContent: (): void => { this.bottomDock(); },
        drawerContent: (): void => { this.bottomDrawerDock(); },
        overlayContent: (): void => { this.surfaceOverlays(); },
        mention: this.mention,
        command: this.command,
        inline: this.inline,
        sticker: this.sticker,
        unreadMentions: this.unreadMentions,
        search: this.search,
        membershipState: this.membershipState,
        showEmojiPanel: this.showEmojiPanel,
        replyKeyboardVisible: this.replyKbVisible(),
        hasReturnTarget: this.returnTarget().kind !== RETURN_NONE,
        pendingJumpId: this.pendingJumpId,
        unreadBadge: this.unreadBadge,
        scrollToBottomBusy: this.scrollToBottomBusy,
        bottomChromeH: this.bottomChromeH,
        chromeIconColor: this.chromeIcon(),
        onPickCommand: (item: CommandItem): void => { this.pickCommand(item); },
        onFillCommand: (item: CommandItem): void => { this.fillCommand(item); },
        onPickMention: (item: MentionItem): void => { this.pickMention(item); },
        onPickInline: (row: InlineResultRow): void => { this.pickInlineResult(row); },
        onPickSticker: (fileId: number): void => { this.sendSuggestedSticker(fileId); },
        onReturnTap: (): void => { this.onScrollFabTap(); },
        onViewportAreaChange: (oldH: number, newH: number): void => {
          this.handleViewportHeightChange(oldH, newH);
        },
        onResizeAreaChange: (oldH: number, newH: number): void => {
          this.handleResizeAreaChange(oldH, newH);
        }
      });

      // Fullscreen media viewer. The page owns which message is open and the
      // hero transition anchored to the tapped thumbnail; the overlay owns
      // zoom/pan, paging, the filmstrip and the chrome layer.
      if (this.viewerOpen()) {
        this.mediaViewer();
      }
    }
    .width('100%').height('100%')
    .onSizeChange((_old: SizeOptions, size: SizeOptions): void => {
      if (typeof size.height === 'number' &&
        (this.keyboardH <= 0 || this.emojiDrawer.viewport <= 0 || size.height > this.emojiDrawer.viewport)) {
        this.emojiDrawer.measureViewport(size.height);
      }
    })
    .allowDrop(CHAT_DROP_TYPES)
    .onDrop((event: DragEvent, extraParams?: string): void => {
      const store = this.store;
      if (store === null) { event.setResult(DragResult.DRAG_FAILED); return; }
      const client = getTdClient();
      const chatId = this.chatId;
      const threadId = this.threadRootId;
      this.dropReceiver.receive(event, this.getUIContext().getHostContext() as common.Context, this.getUIContext(), this.shareHost(store),
        (): boolean => this.store === store && getTdClient() === client && this.chatId === chatId && this.threadRootId === threadId &&
          this.timeline.pageVisible && this.appIsForeground && !this.viewerOpen() && !this.search.mode && !this.selection.active &&
          this.composer.editingId === 0 && !this.recording.isRecording && this.membershipState === 'writable',
        this.header.titleTextOf(), chatId, extraParams);
    })
    // 贴纸合集面板挂在页面根 Stack 上：这个节点还没有别的 bindSheet（骰子那张
    // 挂 dock），同一节点上串两个只有最后一个生效。
    .bindSheet($$this.stickerSetSheetOpen, this.stickerSetSheet(), {
      height: 420,
      // **不能写 Color.Transparent。** 那张表的前提是「材质/模糊一定在」：
      // 材质全关（设置里把厚度调到关闭）时 blurStyle 和 systemMaterial 都退化，
      // 底色又透明 → 整个抽屉没有背景，聊天内容直接透上来
      // （2026-11-03 用户报的「材质全关时贴纸添加抽屉背景消失」）。
      // overlayGlassFill 在材质关时原样返回石头色，材质在时才交给材质。
      backgroundColor: overlayGlassFill('dialog', $r('app.color.surface')),
      dragBar: false,
      blurStyle: containerBlur('dialog'), systemMaterial: overlayMaterial('dialog'),
      onDisappear: (): void => {
        this.stickerSetSheetMounted = false;
        this.stickerSetSheetId = '';
        if (this.stickerSheetOff !== null) {
          this.stickerSheetOff();
          this.stickerSheetOff = null;
        }
      }
    });
    }
    .titleBar(this.chatTitleBarOptions())
    .titleMode(HdsNavDestinationTitleMode.MINI)
    // **HDS 自己的返回键和菜单一颗都不用**，三个胶囊全部由 stackBuilder 自绘
    // ——理由见 ChatHeader 文件头（玻璃/按压/动画 HDS 那三个字段都给不了，
    // 且把展开态接进 TitleBarContentOptions 会让整条栏按点击重建）。
    // 首页 ChatListPage 早就是这个结构。
    .hideBackButton(true)
    // 统一背景在 MainScreen 底下；框架默认的目的页底色也必须让位。
    .backgroundColor(Color.Transparent)
    .onTouchIntercept((event: TouchEvent): HitTestMode => { return this.interceptKeyboardDismiss(event); })
    // 查看器在内容区里，盖不住框架标题栏：开着就收（见 navFullScreen.viewerHidesTitleBar）。
    // animated 取 true：查看器根节点是 300ms 的黑底渐入，第 0 帧直接摘掉顶栏会
    // 在还透着的黑底上闪一下。退出查看器时若状态栏安全区还在恢复，先保持收起直到
    // TYPE_SYSTEM 恢复，避免 HDS 标题栏在 TYPE_SYSTEM=0 期间先画在 y=0 再跳回状态栏下方。
    .hideTitleBar(viewerHidesTitleBar(this.viewerOpen() || this.viewer.titleBarRestoring), true)
    // **不绑定 Scroller 到 HdsNavDestination**：
    // 聊天页顶栏是 scrollEffect=false 且 glass=false 的静态自绘三胶囊（ChatHeader），不需要
    // HDS 根据滚动位置驱动标题栏收缩或渐变模糊。若把 Scroller 传给 bindToScrollable，
    // HdsNavDestination 会为整页挂一个 1378×2832 的离屏滤镜节点；一旦会话内有动态头像
    // 或动态贴纸/表情按 30~60fps 刷新，该整页滤镜缓存就会每帧失效（`forceClearCache_:1, hashChange`），
    // 导致整页离屏重绘并把 GPU 负载推高到 90%~100%。
    .bindToScrollable([])
    // 查看器**不走 bindContentCover**：全模态里视频画面显示不出来（#201，平板分栏黑屏）。
    // 分栏下盖满窗口改由收左栏 + 侧边页签实现，见 util/viewerWindowCover。
    // 入参：router 时代是 aboutToAppear 里 this.getUIContext().getRouter().getParams() 现取，现在从
    // NavDestinationContext 的 pathInfo 里取——而 onReady 实测晚于 aboutToAppear，
    // 所以吃参数的初始化也在这里触发，不能留在 aboutToAppear。
    .onReady((ctx: NavDestinationContext): void => {
      this.navigationCoordinator.setStack(ctx.pathStack);
      this.navParams = ctx.pathInfo.param as Record<string, Object> | undefined;
      // 必须在这里调而不是等 aboutToAppear：实测 onReady 晚于 aboutToAppear。
      this.applyRouteParams();
    })

    .onWillShow((): void => {
      cancelClearChatDetailHiding(false);
      markChatDestShown(this.chatDestToken);
    })
    .onShown((): void => { this.handleShown(); })
    .onWillHide((): void => { this.handleWillHide(); })
    .onHidden((): void => { this.handleHidden(); })
    .onBackPressed((): boolean => { return collapseFloatingVideo() || this.handleBackPressed(); })
    .width('100%').height('100%');
  }
}// 底栏放行带：编辑行上沿往上留这么多 vp，仍算「点在底栏上」（不拦、不收起键盘）。
const COMPOSER_TAP_BAND_TOLERANCE: number = 16;

