import { ShatterDeleteOverlay } from '../common/ShatterDeleteOverlay';
import { SearchChannelPicker } from './SearchChannelPicker';
import { messageScopeRequest, channelSearchCursor, messageMatch, MessageMatch, SEARCH_TAB_RECENT, searchTabForQuery } from '../../util/searchPresentation';
import { emptySearchPageAction, SEARCH_PAGE_EMPTY, SEARCH_PAGE_FETCH, SEARCH_PAGE_MORE } from '../../util/searchPresentation';
import { collapseFloatingVideo } from '../../util/floatingVideoRuntime';
import {
  HEIGHT_BP_LG, KEY_HEIGHT_BREAKPOINT, KEY_WINDOW_PORTRAIT, KEY_WIDTH_BREAKPOINT, WIDTH_BP_SM, isSplitByBreakpoint
} from '../../util/layoutBreakpoint';
import { promptAction, router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { getTdClient } from '../../tdkit/Globals';
import { TdObject, TdRequest, TdError } from '../../tdkit/TdTypes';
import { GlobalSearchStore, SearchRow } from '../../store/GlobalSearchStore';
import { AvatarView } from '../chatlist/AvatarView';
import { KeyedListDataSource } from '../common/KeyedListDataSource';
import { guardKey } from '../../util/keyGuard';
import {
  SearchAppRow, SearchChatRow, SearchFrequentCell, SearchMediaCell, SearchMessageRow
} from './SearchResultRows';
import { formatPreview } from '../../util/formatPreview';
import { formatTime } from '../../util/formatTime';
import {
  COLOR_PRIMARY,
  COLOR_TEXT_PRIMARY,
  COLOR_ICON_SECONDARY, COLOR_TEXT_SECONDARY,
  mainCardFill, mainPageFill, COLOR_ON_PRIMARY
} from '../../util/theme';
import {
  KEY_APP_BG_ON, KEY_POWER_SMOOTH_TRANSITIONS, powerAnimationDuration, KEY_FORCE_SINGLE_COLUMN
} from '../../store/AppSettings';
import { plural, str } from '../../util/strings';
import { LANGUAGE_EPOCH } from '../../util/appLanguage';
import { MATERIAL_EPOCH, plainBackdropBlur, plainGlassFill } from '../../util/overlayMaterial';
import { BLUR_MAX_VP, edgeBlurStops } from '../../util/scrollEdgeBlur';
import { logChatNavFailure, navigateToChat } from '../../util/chatNav';
import {
  SearchSession, forgetSearchSession, rememberSearchSession, takeSearchSession
} from '../../util/searchSession';
import { SEARCH_DEST_NAME } from '../../util/searchNav';
import { NavStackLike, lastParamOfDest, stackOf } from '../../util/navStacks';
import { logE, logI } from '../../util/log';
import { readableContentWidth } from '../../util/contentWidth';
import { AppBackdrop } from '../common/AppBackdrop';

interface FoundItem {
  match?: MessageMatch;
  chatId: number;
  messageId: number;
  chatTitle: string;
  preview: string;
  date: number;
  // 媒体 tab extras (unused elsewhere).
  thumbPath: string;
  isVideo: boolean;
  duration: string;
  // chat avatar for list rows
  avatarPath: string;
  initials: string;
  isChannelChat: boolean; // resolved chat type — 频道 tab filters messages by it
}

// Telegram global-search categories. Public post search belongs to 帖子;
// hashtag search is a mode of that tab, not a second visible category.
const TABS: string[] = [str('gs_objects'), str('cps_messages'), str('gs_apps'), str('gs_public_posts'), str('cpp_media'), str('cpp_links'), str('storage_file'), str('storage_audio'), str('storage_voice'), str('gs_downloads')];
const TAB_CHATS: number = 0;
const TAB_MESSAGES: number = 1;
const TAB_DOWNLOADS: number = 9;
const TAB_APPS: number = 2;
const TAB_POSTS: number = 3;
const TAB_MEDIA: number = 4;
// 原来的「下载」页签（下标 5）搬去了「设置 › 下载中心」（2026-09-15），后面几个依次前移。
const TAB_LINKS: number = 5;
const TAB_FILES: number = 6;
const TAB_AUDIO: number = 7;
const TAB_VOICE: number = 8;
const SEARCH_PAGE_INSET: number = 12;
const SEARCH_RESULT_DIVIDER_INSET: number = 72;

// TDLib message filter for the typed-message tabs ('' = no filter).
function filterTypeForTab(tab: number): string {
  if (tab === TAB_MEDIA) {
    return 'searchMessagesFilterPhotoAndVideo';
  } else if (tab === TAB_LINKS) {
    return 'searchMessagesFilterUrl';
  } else if (tab === TAB_FILES) {
    return 'searchMessagesFilterDocument';
  } else if (tab === TAB_AUDIO) {
    return 'searchMessagesFilterAudio';
  } else if (tab === TAB_VOICE) {
    return 'searchMessagesFilterVoiceNote';
  }
  return '';
}

// mm:ss badge for video thumbnails.
function durationLabel(totalSeconds: number): string {
  const m = Math.floor(totalSeconds / 60);
  const s = totalSeconds % 60;
  return `${m}:${`${s}`.padStart(2, '0')}`;
}
const SEARCH_DEBOUNCE_MS: number = 300;
// Cap on pages fetched automatically when a tab's filter hides every hit.
const MAX_AUTO_PAGES: number = 5;

// 结果列表 LazyForEach 的身份与内容签名（见 KeyedListDataSource）。内容签名沿用原来 ForEach
// key 的字段，去掉了各容器自己的前缀——现在每个容器各有各的数据源，不会串。
function searchRowId(r: SearchRow): string {
  return `${r.chatId}`;
}

function searchRowKey(r: SearchRow): string {
  return `${r.chatId}_${r.title}_${r.subtitle}_${r.avatarPath}`;
}

// 应用行按机器人 userId 认。
function appRowId(r: SearchRow): string {
  return `${r.userId}`;
}

function appRowKey(r: SearchRow): string {
  return `${r.userId}_${r.title}_${r.subtitle}_${r.avatarPath}`;
}

function frequentCellKey(r: SearchRow): string {
  return `${r.chatId}_${r.title}_${r.avatarPath}`;
}

function foundItemId(it: FoundItem): string {
  return `${it.chatId}_${it.messageId}`;
}

function foundItemKey(it: FoundItem): string {
  return `${it.chatId}_${it.messageId}_${it.chatTitle}_${it.avatarPath}`;
}

function mediaItemKey(it: FoundItem): string {
  return `${it.chatId}_${it.messageId}_${it.chatTitle}_${it.thumbPath}`;
}

// Global search (Telegram-style): an empty query shows frequent contacts and
// recently opened chats; a typed query searches chats/channels by name or
// message content separately from public posts.
// 路由表（router_map.json）的 buildFunction 指向这里：搜索页现在是**聊天页签栈
// 里的一层**（issue #129），栈是 聊天列表 → 搜索 → 会话，从会话返回天然回到
// 还活着的搜索结果页。原来它是整页 router 页、点结果必须自己弹掉，返回也就
// 回不来了。
@Builder
export function GlobalSearchPageBuilder(): void {
  GlobalSearchPage();
}

@Component
export struct GlobalSearchPage {
  // 本页在栈里的位置由外壳给（NavDestination 的 onReady），关闭 = 弹自己。
  private navStack: NavPathStack | null = null;
  // 材质档位（厚度/光感）改变时重绘。overlayMaterial 是 util，订阅不了
  // AppStorage，只能由调用方订阅，同 LANGUAGE_EPOCH 的做法。
  @StorageProp(MATERIAL_EPOCH) private materialEpoch: number = 0;
  @StorageProp(LANGUAGE_EPOCH) langEpoch: number = 0;
  @StorageProp(KEY_APP_BG_ON) private appWallpaperOn: boolean = false;
  @StorageProp('topSafeHeight') topSafe: number = 0;
  // 窗口宽（不是屏幕宽），限宽用。平板上把结果列拉满 2880px，头像贴最左、时间
  // 贴最右，眼睛要横扫整屏才读得完一行（设备截图实测）。
  @StorageProp('screenWidthVp') screenW: number = 360;
  // 设置里的「强制单栏」（宽屏也当手机用）。
  @StorageProp(KEY_FORCE_SINGLE_COLUMN) forceSingleColumn: boolean = false;
  @StorageProp('screenHeightVp') screenH: number = 780;
  // 系统断点（util/layoutBreakpoint）：分栏判据读它，不再按窗口宽高自己算。
  @StorageProp(KEY_WIDTH_BREAKPOINT) widthBp: number = WIDTH_BP_SM;
  @StorageProp(KEY_HEIGHT_BREAKPOINT) heightBp: number = HEIGHT_BP_LG;
  @StorageProp(KEY_WINDOW_PORTRAIT) windowPortrait: boolean = true;
  // 下载列表和应用榜按 query 过滤，query 变了要同步它们的数据源（见 syncQueryFilteredData）。
  @State @Watch('syncQueryFilteredData') query: string = '';
  @State @Watch('syncTabFilteredData') tab: number = SEARCH_TAB_RECENT;
  // 「最近」页列表滚到悬浮栏底下时雾化，需要列表自身高度。
  @State private listViewH: number = 0;
  @State objectScope: string = 'all';
  @State messageScope: string = 'all';
  @State channelId: number = 0;
  @State channelTitle: string = '';
  @State channelPickerOpen: boolean = false;
  @State searchFocused: boolean = false;
  @State searchPending: boolean = false;
  @State clearPressed: boolean = false;
  @State cancelPressed: boolean = false;
  @State closingSearch: boolean = false;
  @State searchHeaderVisible: boolean = false;
  @State resultOpeningKey: string = '';
  @State @Watch('syncTopUsersData') topUsers: SearchRow[] = [];
  // 「最近打开」要剔掉已在「最近搜索」里的会话，所以 recent 变了两块都要同步（见 syncRecentData）。
  @State @Watch('syncRecentData') recent: SearchRow[] = [];
  @State @Watch('syncRecentlyOpenedData') recentlyOpened: SearchRow[] = [];
  @State topLoaded: boolean = false;
  @State recentLoaded: boolean = false;
  @State openedLoaded: boolean = false;
  @State topFailed: boolean = false;
  @State recentFailed: boolean = false;
  @State openedFailed: boolean = false;
  @State clearingRecent: boolean = false;
  @State @Watch('syncChatResultsData') chatResults: SearchRow[] = [];
  @State chatSearching: boolean = false;
  @State chatSearchFailed: boolean = false;
  @State @Watch('syncJoinedChannelsData') joinedChannels: SearchRow[] = [];
  @State @Watch('syncSimilarChannelsData') similarChannels: SearchRow[] = [];
  @State @Watch('syncAppsData') apps: SearchRow[] = [];
  @State joinedLoaded: boolean = false;
  @State similarLoaded: boolean = false;
  @State appsLoaded: boolean = false;
  @State joinedFailed: boolean = false;
  @State similarFailed: boolean = false;
  @State appsFailed: boolean = false;
  // 帖子 (message) search state.
  @State @Watch('syncFoundItemsData') items: FoundItem[] = [];
  @State loading: boolean = false;
  @State pagingBusy: boolean = false;
  @State messageError: string = '';
  @State pagingError: boolean = false;
  @State loadedPageCount: number = 0;
  @State nextOffset: string = '';
  @State searchedOnce: boolean = false;
  private nowSec: number = Math.floor(Date.now() / 1000);
  private seq: number = 0;
  private searchTraceId: string = String(Date.now());
  private lastSearchTraceState: string = '';
  private failedPagingOffset: string = '';
  private autoPages: number = 0; // consecutive auto-fetched pages that rendered nothing
  private debounceTimer: number = -1;
  private searchHeaderTimer: number = -1;
  private closeSearchTimer: number = -1;
  private hashtagSearchSeq: number = 0;
  private postsQuotaSeq: number = 0;
  private resultOpeningTimer: number = -1;
  @State private deletingRecentKey: string = '';
  @State private deleteEffectVisible: boolean = false;
  @State private deleteSnapshotReady: boolean = false;
  private pendingRecentDelete: (() => void) | null = null;
  private landingScroller: ListScroller = new ListScroller();
  private clearRecentDialogOpen: boolean = false;
  private clearOpenedDialogOpen: boolean = false;
  private store: GlobalSearchStore | null = null;
  private unsub: (() => void) | null = null;
  // 各结果分组使用独立数据源，避免列表身份互相覆盖。
  private joinedChannelsData: KeyedListDataSource<SearchRow> = new KeyedListDataSource<SearchRow>('gs-joined');
  private similarChannelsData: KeyedListDataSource<SearchRow> = new KeyedListDataSource<SearchRow>('gs-similar');
  private combinedChatsData: KeyedListDataSource<SearchRow> = new KeyedListDataSource<SearchRow>('gs-chats');
  private messageItemsData: KeyedListDataSource<FoundItem> = new KeyedListDataSource<FoundItem>('gs-messages');
  private combinedMessagesData: KeyedListDataSource<FoundItem> = new KeyedListDataSource<FoundItem>('gs-combined-messages');
  private mediaItemsData: KeyedListDataSource<FoundItem> = new KeyedListDataSource<FoundItem>('gs-media');
  private topUsersData: KeyedListDataSource<SearchRow> = new KeyedListDataSource<SearchRow>('gs-top');
  private localNamesData: KeyedListDataSource<SearchRow> = new KeyedListDataSource<SearchRow>('gs-local-names');
  private publicNamesData: KeyedListDataSource<SearchRow> = new KeyedListDataSource<SearchRow>('gs-public-names');
  private recentData: KeyedListDataSource<SearchRow> = new KeyedListDataSource<SearchRow>('gs-recent');
  private recentlyOpenedData: KeyedListDataSource<SearchRow> = new KeyedListDataSource<SearchRow>('gs-opened');
  private appsData: KeyedListDataSource<SearchRow> = new KeyedListDataSource<SearchRow>('gs-apps');
  private combinedAppsData: KeyedListDataSource<SearchRow> = new KeyedListDataSource<SearchRow>('gs-combined-apps');

  @Styles
  resultRowNormalStyle() {
    .backgroundColor(mainCardFill(this.appWallpaperOn, false))
  }

  @Styles
  resultRowPressedStyle() {
    .backgroundColor(mainCardFill(this.appWallpaperOn, true))
  }

  @Styles
  mediaResultNormalStyle() {
    .opacity(1)
  }

  @Styles
  mediaResultPressedStyle() {
    .opacity(0.82)
  }

  @Styles
  landingActionNormalStyle() {
    .backgroundColor(Color.Transparent)
  }

  @Styles
  landingActionPressedStyle() {
    .backgroundColor(mainCardFill(this.appWallpaperOn, true))
  }

  @Styles
  retryActionNormalStyle() {
    .backgroundColor(mainCardFill(this.appWallpaperOn, true))
    .opacity(1)
  }

  @Styles
  retryActionPressedStyle() {
    .backgroundColor('#18229ED9')
    .opacity(0.72)
  }

  private traceMessageSearch(event: string, detail: string = ''): void {
    logI(`[MessageSearch] trace=v2-${this.searchTraceId} seq=${this.seq} event=${event} ` + detail);
  }

  private traceMessageState(event: string): void {
    const state = `tab=${this.tab} scope=${this.messageScope} fixedChat=${this.channelId !== 0} ` +
      `rows=${this.items.length} visible=${this.visibleItems().length} ` +
      `unresolved=${this.items.filter((it: FoundItem): boolean => it.chatTitle === '').length} ` +
      `published=${this.messageItemsData.totalCount()} busy=${this.loading || this.pagingBusy} ` +
      `failed=${this.messageError !== '' || this.pagingError} searched=${this.searchedOnce} ` +
      `more=${this.nextOffset !== ''} autoPages=${this.autoPages} action=${this.emptyPageAction()}`;
    const signature = `${this.seq}:${state}`;
    if (signature === this.lastSearchTraceState) { return; }
    this.lastSearchTraceState = signature;
    this.traceMessageSearch(event, state);
  }

  private onTabSelected(index: number): void {
    if (this.debounceTimer !== -1) {
      clearTimeout(this.debounceTimer);
      this.debounceTimer = -1;
    }
    this.searchPending = false;
    this.tab = index;
    this.traceMessageSearch('select-tab', `tab=${index}`);
    this.hashtagSearchSeq++;
    this.postsQuotaSeq++;
    this.runSearch();
  }

  aboutToAppear(): void {
    this.traceMessageSearch('open', 'diagnostics=message-search-v2');
    if (this.closeSearchTimer !== -1) {
      clearTimeout(this.closeSearchTimer);
      this.closeSearchTimer = -1;
    }
    this.closingSearch = false;
    this.resetResultOpening();
    this.searchHeaderVisible = false;
    this.searchHeaderTimer = setTimeout((): void => {
      this.searchHeaderTimer = -1;
      this.searchHeaderVisible = true;
    }, powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 30));
    const store = new GlobalSearchStore(getTdClient());
    this.store = store;
    this.unsub = store.subscribe(() => {
      const removedRecent = store.recent.length < this.recent.length ||
        store.recentlyOpened.length < this.recentlyOpened.length;
      this.topUsers = store.topUsers;
      if (removedRecent && this.query.trim() === '' && !this.closingSearch) {
        // DELETE 通知与行退出在同一动画事务内发布，交给 List 保持存活行的位置。
        // 不再布局后 scrollTo 旧绝对偏移，避免先补位、再被拉回。
        this.getUIContext().animateTo({
          duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 180),
          curve: Curve.EaseOut
        }, (): void => {
          this.recent = store.recent;
          this.recentlyOpened = store.recentlyOpened;
        });
      } else {
        this.recent = store.recent;
        this.recentlyOpened = store.recentlyOpened;
      }
      this.topLoaded = store.topLoaded;
      this.recentLoaded = store.recentLoaded;
      this.openedLoaded = store.openedLoaded;
      this.topFailed = store.topFailed;
      this.recentFailed = store.recentFailed;
      this.openedFailed = store.openedFailed;
      this.chatResults = store.results;
      this.chatSearching = store.searching;
      this.chatSearchFailed = store.searchFailed;
      this.joinedChannels = store.joinedChannels;
      this.similarChannels = store.similarChannels;
      this.apps = store.apps;
      this.joinedLoaded = store.joinedLoaded;
      this.similarLoaded = store.similarLoaded;
      this.appsLoaded = store.appsLoaded;
      this.joinedFailed = store.joinedFailed;
      this.similarFailed = store.similarFailed;
      this.appsFailed = store.appsFailed;
    });
    store.open();
    const params: Record<string, Object> | undefined = this.entryParams();
    const q = params !== undefined ? (params['query'] as string | undefined) : undefined;
    if (q !== undefined && q !== '') {
      // Hashtag entry — straight into the 帖子 (global posts) tab.
      this.query = q;
      this.tab = TAB_POSTS;
      this.searchMessages('');
      forgetSearchSession(); // 带关键词进来的（话题跳转等），别被上次的覆盖
      return;
    }
    // 上次点开结果时记下的关键词与分页，时效内自动填回并重跑一次（issue #129）。
    // 结果本身不存快照——那些条目挂着实时订阅，存下来只会显示过期数据。
    const restored: SearchSession | null = takeSearchSession(Date.now());
    if (restored !== null) {
      this.query = restored.query;
      this.tab = searchTabForQuery(restored.query, restored.tab);
      this.objectScope = restored.objectScope ?? 'all'; this.messageScope = restored.messageScope ?? 'all';
      this.channelId = restored.channelId ?? 0; this.channelTitle = restored.channelTitle ?? '';
      this.runSearch();
    }
  }

  aboutToDisappear(): void {
    this.traceMessageState('leave');
    // 离页不丢掉已经确认的删除操作，也不把旧动画带到下一次打开。
    this.finishRecentDeleteEffect();
    this.deletingRecentKey = '';

    this.channelPickerOpen = false;
    if (this.debounceTimer !== -1) { clearTimeout(this.debounceTimer); this.debounceTimer = -1; }
    if (this.searchHeaderTimer !== -1) {
      clearTimeout(this.searchHeaderTimer);
      this.searchHeaderTimer = -1;
    }
    if (this.closeSearchTimer !== -1) {
      clearTimeout(this.closeSearchTimer);
      this.closeSearchTimer = -1;
    }
    this.resetResultOpening();
    this.hashtagSearchSeq++;
    this.postsQuotaSeq++;
    this.searchPending = false;
    this.searchFocused = false;
    this.clearPressed = false;
    this.cancelPressed = false;
    this.clearingRecent = false;
    this.clearRecentDialogOpen = false;
    this.clearOpenedDialogOpen = false;
    this.closingSearch = false;
    this.searchHeaderVisible = false;
    if (this.unsub !== null) { this.unsub(); this.unsub = null; }
    if (this.store !== null) { this.store.close(); this.store = null; }
  }

  private onQueryChanged(v: string): void {
    this.tab = searchTabForQuery(v, this.tab);
    this.query = v;
    this.traceMessageSearch('query-change', `length=${v.trim().length} tab=${this.tab}`);
    if (this.debounceTimer !== -1) {
      clearTimeout(this.debounceTimer);
      this.debounceTimer = -1;
    }
    this.hashtagSearchSeq++;
    this.postsQuotaSeq++;
    this.cancelInFlight();
    this.items = [];
    this.hashtagPosts = [];
    this.searchedOnce = false;
    this.autoPages = 0;
    this.postsQuota = '';
    if (this.store !== null) {
      this.store.searchChats('');
    }
    if (v.trim() === '') {
      this.searchPending = false;
      this.runSearch();
      return;
    }
    this.searchPending = true;
    this.debounceTimer = setTimeout(() => {
      this.debounceTimer = -1;
      this.searchPending = false;
      this.runSearch();
    }, SEARCH_DEBOUNCE_MS);
  }

  private submitSearch(): void {
    if (this.debounceTimer !== -1) {
      clearTimeout(this.debounceTimer);
      this.debounceTimer = -1;
    }
    this.searchPending = false;
    if (this.tab === TAB_POSTS && this.query.trim() !== '') {
      this.searchMessages('');
    } else {
      this.runSearch();
    }
  }

  private clearSearch(): void {
    if (this.query === '') {
      return;
    }
    if (this.debounceTimer !== -1) {
      clearTimeout(this.debounceTimer);
      this.debounceTimer = -1;
    }
    this.searchPending = false;
    this.hashtagSearchSeq++;
    this.postsQuotaSeq++;
    this.tab = SEARCH_TAB_RECENT;
    this.query = '';
    this.chatResults = [];
    this.items = [];
    this.hashtagPosts = [];
    this.searchedOnce = false;
    this.autoPages = 0;
    this.postsQuota = '';
    if (this.store !== null) {
      this.store.searchChats('');
    }
    this.runSearch();
  }

  private closeSearch(): void {
    if (this.closingSearch) {
      return;
    }
    if (this.debounceTimer !== -1) {
      clearTimeout(this.debounceTimer);
      this.debounceTimer = -1;
    }
    this.searchPending = false;
    this.hashtagSearchSeq++;
    this.postsQuotaSeq++;
    this.cancelInFlight();
    if (this.store !== null) {
      this.store.searchChats('');
    }
    // 点「取消」是明确要离开搜索，别在下次打开时把上次的关键词又端上来。
    forgetSearchSession();
    this.closingSearch = true;
    this.cancelPressed = false;
    this.closeSearchTimer = setTimeout((): void => {
      this.closeSearchTimer = -1;
      this.closingSearch = false;
    }, 650);
    try {
      this.closeSelf();
    } catch (caught) {
      if (this.closeSearchTimer !== -1) {
        clearTimeout(this.closeSearchTimer);
        this.closeSearchTimer = -1;
      }
      this.closingSearch = false;
      logE(`GlobalSearchPage.closeSearch failed: ${caught}`);
    }
  }

  private searchPlaceholder(): string {
    if (this.tab === SEARCH_TAB_RECENT) { return str('fe_search_hint'); }
    if (this.tab === TAB_MEDIA) {
      return str('gs_search_media');
    }
    if (this.tab === TAB_LINKS) {
      return str('gs_search_links');
    }
    if (this.tab === TAB_FILES) {
      return str('gs_search_files');
    }
    if (this.tab === TAB_AUDIO || this.tab === TAB_VOICE) {
      return str('gs_search_audio');
    }
    if (this.tab === TAB_POSTS) {
      return str('gs_search_posts');
    }
    if (this.tab === TAB_MESSAGES) { return str('gs_search_message_content'); }
    if (this.tab === TAB_APPS) { return str('gs_search_app_names'); }
    return str('gs_search_names');
  }

  private searchBusy(): boolean {
    if (this.searchPending) {
      return true;
    }
    if (this.tab === TAB_CHATS || this.tab === TAB_MESSAGES) {
      return this.chatSearching || this.loading;
    }
    return this.loading;
  }

  // Rows the current tab actually shows: the 频道 tab keeps only messages from
  // channels, so a page of hits can render as nothing at all.
  private visibleItems(): FoundItem[] {
    const resolved = this.items.filter((it: FoundItem) => it.chatTitle !== '');
    return resolved;
  }

  private visibleHashtagPosts(): FoundItem[] {
    return this.hashtagPosts.filter((it: FoundItem) => it.chatTitle !== '');
  }

  private resolvingMessageRows(): boolean {
    return this.items.some((it: FoundItem) => it.chatTitle === '');
  }

  private emptyPageAction(): string {
    return emptySearchPageAction({
      searched: this.searchedOnce, busy: this.loading || this.pagingBusy,
      failed: this.pagingError || this.messageError !== '', resolving: this.resolvingMessageRows(),
      visibleCount: this.visibleItems().length, nextOffset: this.nextOffset, automaticPages: this.autoPages
    }, MAX_AUTO_PAGES);
  }

  // Empty pages need continuation in every message scope, including All.
  private maybeAutoPage(): void {
    if (this.tab !== TAB_MESSAGES && !this.isFilterTab()) { return; }
    if (this.emptyPageAction() !== SEARCH_PAGE_FETCH) { return; }
    this.traceMessageState('auto-page');
    this.autoPages += 1;
    this.searchMessages(this.nextOffset);
  }

  private searchExhausted(): boolean {
    return this.emptyPageAction() === SEARCH_PAGE_EMPTY;
  }

  private continueEmptySearch(): void {
    const action = this.emptyPageAction();
    if (action !== SEARCH_PAGE_FETCH && action !== SEARCH_PAGE_MORE) { return; }
    this.traceMessageState('manual-page');
    this.autoPages = 0;
    this.searchMessages(this.nextOffset);
  }

  private isFilterTab(): boolean {
    return filterTypeForTab(this.tab) !== '';
  }

  private mergeFoundItems(current: FoundItem[], fresh: FoundItem[], replace: boolean): FoundItem[] {
    const merged: FoundItem[] = replace ? [] : [...current];
    const seen: Set<string> = new Set<string>();
    for (const item of merged) {
      seen.add(`${item.chatId}:${item.messageId}`);
    }
    for (const item of fresh) {
      const key = `${item.chatId}:${item.messageId}`;
      if (!seen.has(key)) {
        seen.add(key);
        merged.push(item);
      }
    }
    return merged;
  }


  // Abandon whatever is in flight: the response of a superseded request must
  // neither land in the list nor leave the spinner running. Every path that
  // returns without starting a new request has to call this — a stale `loading`
  // is what makes a tab spin forever.
  private cancelInFlight(): void {
    this.traceMessageSearch('cancel', `busy=${this.loading || this.pagingBusy}`);
    this.seq++;
    this.pagingBusy = false;
    this.loading = false;
    this.messageError = '';
    this.pagingError = false;
    this.failedPagingOffset = '';
    this.loadedPageCount = 0;
    this.nextOffset = '';
  }

  private retryMessageSearch(): void {
    if (!this.loading) {
      this.searchMessages('');
    }
  }

  private retryPaging(): void {
    if (!this.loading && !this.pagingBusy && this.failedPagingOffset !== '') {
      this.searchMessages(this.failedPagingOffset);
    }
  }

  private retryChatSearch(): void {
    if (this.store !== null && this.query.trim() !== '') {
      this.store.searchChats(this.query, this.tab === TAB_APPS ? 'bot' : this.objectScope);
    }
  }

  private runSearch(): void {
    this.traceMessageSearch('dispatch', `tab=${this.tab} scope=${this.messageScope} length=${this.query.trim().length}`);
    if (this.query.trim() === '') {
      this.cancelInFlight();
      this.items = [];
      this.hashtagPosts = [];
      this.searchedOnce = false;
      this.store?.searchChats('');
      return;
    }
    if (this.tab === TAB_POSTS) {
      if (this.query.trim().startsWith('#') && this.query.trim().length > 1) {
        // A hashtag is another mode of the official 帖子 tab. It uses TDLib's
        // tag endpoint immediately and does not consume keyword-search quota.
        this.searchMessages('');
      } else {
        // Keyword post search burns server quota — never auto-fire; typing
        // resets back to the prompt with its explicit 搜索 button.
        this.cancelInFlight();
        this.searchedOnce = false;
        this.items = [];
        this.loadPostsQuota();
      }
    } else if (this.tab === TAB_MESSAGES || this.isFilterTab()) {
      this.searchMessages('');
    } else {
      this.cancelInFlight(); this.items = []; this.hashtagPosts = []; this.searchedOnce = false;
      if (this.tab === TAB_CHATS || this.tab === TAB_APPS) { this.store?.searchChats(this.query, this.tab === TAB_APPS ? 'bot' : this.objectScope); }
    }
  }

  @State postsQuota: string = '';

  // Remaining free public-post searches today (field names probed defensively —
  // the raw object is logged for calibration).
  private loadPostsQuota(): void {
    const requestSeq = ++this.postsQuotaSeq;
    const requestQuery = this.query.trim();
    const req: TdRequest = { '@type': 'getPublicPostSearchLimits' };
    req['query'] = requestQuery;
    getTdClient().send(req).then((res: TdObject) => {
      if (requestSeq !== this.postsQuotaSeq || this.query.trim() !== requestQuery) {
        return;
      }
      logI(`GlobalSearchPage.postSearchLimits: ${JSON.stringify(res)}`);
      const remaining = (res['remaining_free_query_count'] as number | undefined)
        ?? ((res['remaining_count'] as number | undefined)
          ?? ((res['free_query_count'] as number | undefined) ?? -1));
      this.postsQuota = remaining >= 0 ? plural('gs_free_left', remaining, remaining) : '';
    }).catch((e: TdError) => {
      logE(`GlobalSearchPage.getPublicPostSearchLimits failed: ${e.message}`);
    });
  }

  private searchMessages(offset: string): void {
    const q = this.query.trim();
    const filterType = filterTypeForTab(this.tab);
    // posts: quota-limited keyword post search; tagposts: hashtag mode of the
    // same 帖子 tab; filter: typed tabs (query optional); all: the 消息
    // section under 聊天/频道/应用.
    const mode: string = this.tab === TAB_POSTS
      ? (q.startsWith('#') ? 'tagposts' : 'posts')
      : (filterType !== '' ? 'filter' : 'all');
    if (q === '' && mode !== 'filter') {
      this.cancelInFlight();
      this.items = [];
      this.searchedOnce = false;
      return;
    }
    if (offset !== '') {
      // Scroll-driven pagination: one in-flight page at a time.
      if (this.loading || this.pagingBusy) {
        return;
      }
      this.pagingBusy = true;
      this.pagingError = false;
      this.failedPagingOffset = '';
    } else {
      // A category/query change is a new result set. Never expose rows from
      // the previous category if this first page subsequently fails.
      this.pagingBusy = false;
      this.pagingError = false;
      this.failedPagingOffset = '';
      this.messageError = '';
      this.items = [];
      this.nextOffset = '';
      this.searchedOnce = false;
      this.loadedPageCount = 0;
      this.autoPages = 0;
    }
    const seq = ++this.seq;
    this.loading = offset === '';
    const scoped = this.tab === TAB_MESSAGES && this.channelId !== 0;
    const req: TdRequest = mode === 'posts' ? { '@type': 'searchPublicPosts' }
      : (mode === 'tagposts' ? { '@type': 'searchPublicMessagesByTag' } :
        messageScopeRequest(q, this.tab === TAB_MESSAGES ? this.messageScope : 'all', scoped ? this.channelId : 0, offset));
    if (mode === 'filter' || mode === 'all') {
      // **不设 chat_list**（issue #139）：TDLib 省略这一项时搜的是**所有**会话
      // 列表，归档里的消息才搜得到。原来固定 chatListMain，归档会话的内容一条
      // 都出不来，而官方客户端的全局搜索是含归档的。
      if (filterType !== '') {
        req['filter'] = { '@type': filterType } as TdObject;
      }
    }
    if (mode === 'tagposts') {
      // The hashtag API wants a tag — prefix bare keywords with '#'.
      req['tag'] = q.startsWith('#') ? q : `#${q}`;
    } else {
      req['query'] = q;
    }
    if (!scoped) { req['offset'] = offset; }
    req['limit'] = 30;
    const startedAt = Date.now();
    this.traceMessageSearch('request', `type=${req['@type']} tab=${this.tab} scope=${this.messageScope} ` +
      `fixedChat=${scoped} first=${offset === ''} length=${q.length} filter=${filterType || 'none'}`);
    getTdClient().send(req).then((res: TdObject) => {
      if (seq !== this.seq) {
        this.traceMessageSearch('stale-response', `requestSeq=${seq} elapsedMs=${Date.now() - startedAt}`);
        return;
      }
      this.pagingBusy = false;
      this.loading = false;
      this.messageError = '';
      this.pagingError = false;
      this.failedPagingOffset = '';
      this.searchedOnce = true;
      const responseOffset = scoped ? channelSearchCursor(res, offset) : (res['next_offset'] as string | undefined) ?? '';
      // A non-advancing cursor would otherwise retrigger forever at the same
      // scroll position.
      this.nextOffset = responseOffset === offset ? '' : responseOffset;
      this.loadedPageCount = offset === '' ? 1 : this.loadedPageCount + 1;
      const msgs = (res['messages'] as TdObject[] | undefined) ?? [];
      const fresh: FoundItem[] = [];
      for (const m of msgs) {
        const item = this.parseFoundMessage(m);
        if (item === null) {
          continue;
        }
        if (this.tab === TAB_MEDIA) {
          this.parseMediaThumb(m, item);
        }
        fresh.push(item);
      }
      this.traceMessageSearch('response', `requestSeq=${seq} elapsedMs=${Date.now() - startedAt} ` +
        `type=${res['@type']} page=${this.loadedPageCount} returned=${msgs.length} accepted=${fresh.length} ` +
        `discarded=${msgs.length - fresh.length} total=${res['total_count']} ` +
        `rawMore=${responseOffset !== ''} repeatedCursor=${responseOffset !== '' && responseOffset === offset}`);
      this.items = this.mergeFoundItems(this.items, fresh, offset === '');
      if (mode === 'posts') {
        this.loadPostsQuota(); // a search just burned one — refresh the count
      }
      // getChat still resolves the title/avatar and defensively verifies the
      // type, while TDLib already limits the 频道 tab to channel messages.
      if (offset === '') {
        this.autoPages = 0;
      }
      this.traceMessageState('settled');
      this.maybeAutoPage();
    }).catch((e: TdError) => {
      if (seq !== this.seq) {
        this.traceMessageSearch('stale-error', `requestSeq=${seq} code=${e.code}`);
        return;
      }
      this.pagingBusy = false;
      this.loading = false;
      this.searchedOnce = true;
      if (offset === '') {
        this.messageError = str('gs_search_failed_network');
        this.nextOffset = '';
      } else {
        this.pagingError = true;
        this.failedPagingOffset = offset;
      }
      this.traceMessageSearch('request-error', `requestSeq=${seq} code=${e.code} elapsedMs=${Date.now() - startedAt}`);
      this.traceMessageState('failed');
      logE(`GlobalSearchPage.searchMessages failed: ${e.message}`);
    });
  }

  private parseFoundMessage(m: TdObject): FoundItem | null {
    const chatId = (m['chat_id'] as number | undefined) ?? 0;
    const messageId = (m['id'] as number | undefined) ?? 0;
    if (chatId === 0 || messageId === 0) {
      return null;
    }
    this.resolveTitle(chatId);
    const cachedTitle = this.titles.get(chatId) ?? '';
    return {
      chatId, messageId, chatTitle: cachedTitle,
      preview: formatPreview(m), match: messageMatch(m),
      date: (m['date'] as number | undefined) ?? 0,
      thumbPath: '', isVideo: false, duration: '',
      avatarPath: this.avatarCache.get(chatId) ?? '',
      initials: cachedTitle.length > 0 ? cachedTitle.substring(0, 1).toUpperCase() : '?',
      isChannelChat: this.channelFlags.get(chatId) ?? false
    };
  }

  // #tag queries: public posts carrying the hashtag, previewed above the
  // regular results ("公开贴文") with a 显示更多 expander.
  @State hashtagPosts: FoundItem[] = [];

  private loadHashtagPosts(offset: string): void {
    const tag = this.query.trim();
    const requestSeq = ++this.hashtagSearchSeq;
    const req: TdRequest = { '@type': 'searchPublicMessagesByTag' };
    req['tag'] = tag;
    req['offset'] = offset;
    req['limit'] = 5;
    getTdClient().send(req).then((res: TdObject) => {
      if (requestSeq !== this.hashtagSearchSeq || this.query.trim() !== tag) {
        return;
      }
      const msgs = (res['messages'] as TdObject[] | undefined) ?? [];
      const fresh: FoundItem[] = [];
      for (const m of msgs) {
        const item = this.parseFoundMessage(m);
        if (item !== null) {
          fresh.push(item);
        }
      }
      this.hashtagPosts = this.mergeFoundItems(this.hashtagPosts, fresh, offset === '');
    }).catch((e: TdError) => {
      logE(`GlobalSearchPage.searchPublicMessagesByTag failed: ${e.message}`);
    });
  }

  // 媒体 grid: extract the thumbnail file (photo 'm' size / video thumbnail)
  // and kick its download; the cell fills in when the file lands.
  private parseMediaThumb(m: TdObject, item: FoundItem): void {
    const content = m['content'] as TdObject | undefined;
    if (content === undefined) {
      return;
    }
    let thumbId = 0;
    const photo = content['photo'] as TdObject | undefined;
    if (photo !== undefined) {
      const sizes = (photo['sizes'] as TdObject[] | undefined) ?? [];
      let pick: TdObject | undefined = undefined;
      for (const s of sizes) {
        if ((s['type'] as string | undefined) === 'm') {
          pick = s;
        }
      }
      if (pick === undefined && sizes.length > 0) {
        pick = sizes[0];
      }
      const f = pick !== undefined ? (pick['photo'] as TdObject | undefined) : undefined;
      thumbId = f !== undefined ? ((f['id'] as number | undefined) ?? 0) : 0;
    }
    const video = content['video'] as TdObject | undefined;
    if (video !== undefined) {
      item.isVideo = true;
      item.duration = durationLabel((video['duration'] as number | undefined) ?? 0);
      const thumb = video['thumbnail'] as TdObject | undefined;
      const f = thumb !== undefined ? (thumb['file'] as TdObject | undefined) : undefined;
      thumbId = f !== undefined ? ((f['id'] as number | undefined) ?? 0) : 0;
    }
    if (thumbId === 0) {
      return;
    }
    const req: TdRequest = { '@type': 'downloadFile' };
    req['file_id'] = thumbId;
    req['priority'] = 1;
    req['synchronous'] = true;
    getTdClient().send(req).then((f: TdObject) => {
      const local = f['local'] as TdObject | undefined;
      const path = local !== undefined ? ((local['path'] as string | undefined) ?? '') : '';
      if (path === '') {
        return;
      }
      this.items = this.items.map((it: FoundItem): FoundItem =>
        it.chatId === item.chatId && it.messageId === item.messageId
        ? {
          chatId: it.chatId, messageId: it.messageId, chatTitle: it.chatTitle,
          preview: it.preview, match: it.match, date: it.date,
          thumbPath: path, isVideo: it.isVideo, duration: it.duration,
          avatarPath: it.avatarPath, initials: it.initials, isChannelChat: it.isChannelChat
        } : it);
    }).catch((e: TdError) => {
      logE(`GlobalSearchPage.mediaThumb failed: ${e.message}`);
    });
  }

  // Resolved-chat caches. All three must be cached together: resolveTitle()
  // short-circuits on a title cache hit, so anything it resolves but does not
  // cache (the channel flag, once) would stay at its default on every later
  // search — which silently emptied the 频道 tab, whose message section filters
  // on exactly that flag.
  private titles: Map<number, string> = new Map();
  private avatarCache: Map<number, string> = new Map();
  private channelFlags: Map<number, boolean> = new Map();

  private resolveTitle(chatId: number): void {
    if (this.titles.has(chatId)) {
      return;
    }
    this.titles.set(chatId, '');
    const req: TdRequest = { '@type': 'getChat' };
    req['chat_id'] = chatId;
    getTdClient().send(req).then((chat: TdObject) => {
      const title = (chat['title'] as string | undefined) ?? '';
      this.titles.set(chatId, title);
      this.traceMessageSearch('chat-resolved', `hasTitle=${title !== ''} ` +
        `affected=${this.items.filter((it: FoundItem): boolean => it.chatId === chatId).length}`);
      const type = chat['type'] as TdObject | undefined;
      const isChannel = type !== undefined
        && ((type['@type'] as string | undefined) ?? '') === 'chatTypeSupergroup'
        && (((type as TdObject)['is_channel'] as boolean | undefined) ?? false);
      this.channelFlags.set(chatId, isChannel);
      this.patchItems(chatId, (it: FoundItem): FoundItem => ({
        chatId: it.chatId, messageId: it.messageId, chatTitle: title,
        preview: it.preview, match: it.match, date: it.date,
        thumbPath: it.thumbPath, isVideo: it.isVideo, duration: it.duration,
        avatarPath: it.avatarPath,
        initials: title.length > 0 ? title.substring(0, 1).toUpperCase() : '?',
        isChannelChat: isChannel
      }));
      this.maybeAutoPage();
      const photo = chat['photo'] as TdObject | undefined;
      const small = photo !== undefined ? (photo['small'] as TdObject | undefined) : undefined;
      const fileId = small !== undefined ? ((small['id'] as number | undefined) ?? 0) : 0;
      if (fileId > 0) {
        const dl: TdRequest = { '@type': 'downloadFile' };
        dl['file_id'] = fileId;
        dl['priority'] = 1;
        dl['synchronous'] = true;
        getTdClient().send(dl).then((f: TdObject) => {
          const local = f['local'] as TdObject | undefined;
          const path = local !== undefined ? ((local['path'] as string | undefined) ?? '') : '';
          if (path !== '') {
            this.avatarCache.set(chatId, path);
            this.patchItems(chatId, (it: FoundItem): FoundItem => ({
              chatId: it.chatId, messageId: it.messageId, chatTitle: it.chatTitle,
              preview: it.preview, match: it.match, date: it.date,
              thumbPath: it.thumbPath, isVideo: it.isVideo, duration: it.duration,
              avatarPath: path, initials: it.initials, isChannelChat: it.isChannelChat
            }));
          }
        }).catch((e: TdError) => {
          logE(`GlobalSearchPage.avatar download failed: ${e.message}`);
        });
      }
    }).catch((e: TdError) => {
      // A permanently unresolved row keeps the whole result screen in its
      // loading branch. Drop only that chat's unusable hits and allow paging or
      // the empty/error state to settle; a later search may resolve it again.
      this.traceMessageSearch('chat-error', `code=${e.code} ` +
        `dropped=${this.items.filter((it: FoundItem): boolean => it.chatId === chatId).length}`);
      this.titles.delete(chatId);
      this.channelFlags.delete(chatId);
      this.items = this.items.filter((it: FoundItem) => it.chatId !== chatId);
      this.hashtagPosts = this.hashtagPosts.filter((it: FoundItem) => it.chatId !== chatId);
      this.maybeAutoPage();
      logE(`GlobalSearchPage.getChat failed: ${e.message}`);
    });
  }

  private patchItems(chatId: number, fn: (it: FoundItem) => FoundItem): void {
    this.items = this.items.map((it: FoundItem): FoundItem => it.chatId === chatId ? fn(it) : it);
    this.hashtagPosts = this.hashtagPosts.map((it: FoundItem): FoundItem => it.chatId === chatId ? fn(it) : it);
  }

  // 点搜索结果打开会话。**本页留在栈上，返回就回到搜索结果。**
  //
  // 【origin='search' 而不是默认的 navbar】navbar 的语义是"换一个会话看"，它既
  // 清栈、又对已在栈里的会话做去重出栈——两条都会把压在下面的本页一起弹掉，
  // 于是返回落到文件夹 tab。而"之前开没开过那个会话"决定走清栈还是出栈，两条
  // 又恰好一条能保住本页一条不能，用户看到的就是「有些可以回到搜索结果，有些
  // 会退回到文件夹」（2026-09-08 反馈）。判据与取舍见 util/splitRouting。
  //
  // 【不再自己弹本页】原来这里跟着一句 closingSearch = true，那是本页还是 router
  // 页、盖在聊天栈之上时的做法（弹掉自己才能露出会话）。改进 tab 栈之后它只剩
  // 副作用：这个标记没人复位，返回搜索页后「取消」按钮会被它挡住恒不生效。
  // 防连点由 beginResultOpening 的 900ms 定时器负责，不需要它。
  //
  // rememberSearchSession 保留：它管的是**另一条路**——用户按取消离开搜索、
  // 稍后再点搜索时把上次的关键词端回来（issue #129），和返回栈无关。
  private openChatAndClose(params: Record<string, Object>): void {
    navigateToChat(params, 'search').then((): void => {
      rememberSearchSession(this.query, this.tab, Date.now(), this.objectScope, this.messageScope, this.channelId, this.channelTitle);
    }).catch(logChatNavFailure);
  }

  // 进来时带的参数（话题标签跳转会带 query）。
  //
  // 【三条路的顺序不能变】唯一的调用点在 aboutToAppear 里，而**那时 this.navStack
  // 还是 null**：官方生命周期写明「aboutToAppear 在 build() 执行之前调用」，
  // 而 navStack 是 build 里 NavDestination.onReady() 才交过来的。
  // 78026c9 把搜索页从 router.pushUrl 改成 tab 栈的 pushPath 之后，这里就只剩
  // router.getParams() 那条兜底——它读的是 router 的参数，pushPath 根本不往那儿
  // 放，于是 `#话题标签` 跳进来关键词丢了、进页面不自动搜（1.4.3 起，用户报
  // 「点击搜索标签，跳转到搜索页面不会自动搜索了」）。
  // 中间这条从全局注册表取同一个栈：它在 pushPath 之前就注册好了，拿得到。
  private entryParams(): Record<string, Object> | undefined {
    const stack: NavPathStack | null = this.navStack;
    if (stack !== null) {
      const param: Object[] = stack.getParamByName(SEARCH_DEST_NAME) as Object[];
      return param.length === 0
        ? undefined : param[param.length - 1] as Record<string, Object>;
    }
    const registered: NavStackLike | undefined = stackOf('chat');
    if (registered !== undefined) {
      const fromStack: Object | undefined = lastParamOfDest(registered, SEARCH_DEST_NAME);
      if (fromStack !== undefined) {
        return fromStack as Record<string, Object>;
      }
    }
    // 整页路由那条路（stackOf('chat') 还没注册时 searchNav 会退回 pushUrl）。
    return router.getParams() as Record<string, Object> | undefined;
  }

  // 关闭自己：栈里就弹一层，退回整页路由的那种情况才用 router.back()。
  private closeSelf(): void {
    const stack: NavPathStack | null = this.navStack;
    if (stack !== null) {
      stack.pop(true);
      return;
    }
    router.back();
  }

  private resetResultOpening(): void {
    if (this.resultOpeningTimer !== -1) {
      clearTimeout(this.resultOpeningTimer);
      this.resultOpeningTimer = -1;
    }
    this.resultOpeningKey = '';
  }

  private beginResultOpening(key: string): boolean {
    if (this.resultOpeningKey !== '') {
      return false;
    }
    this.resultOpeningKey = key;
    // Route requests normally make this page disappear and reset the guard.
    // Keep a fallback in case the router accepts no navigation.
    this.resultOpeningTimer = setTimeout((): void => {
      this.resultOpeningTimer = -1;
      this.resultOpeningKey = '';
    }, 900);
    return true;
  }

  // A chat-name result opens the conversation normally. Only message results
  // should enter in-chat search and jump to a concrete hit.
  private openChat(chatId: number): void {
    const openingKey = `chat:${chatId}`;
    if (!this.beginResultOpening(openingKey)) {
      return;
    }
    if (this.query.trim() !== '' && this.store !== null) {
      this.store.rememberFoundChat(chatId);
    }
    const params: Record<string, Object> = { 'chatId': chatId };
    this.openChatAndClose(params);
  }

  // App (mini-app bot) rows open the bot's chat — running the web app itself
  // needs a WebView container we don't have yet.
  private openApp(userId: number): void {
    const openingKey = `app:${userId}`;
    if (!this.beginResultOpening(openingKey)) {
      return;
    }
    const req: TdRequest = { '@type': 'createPrivateChat' };
    req['user_id'] = userId;
    req['force'] = false;
    getTdClient().send(req).then((chat: TdObject) => {
      const id = (chat['id'] as number | undefined) ?? 0;
      if (id !== 0) {
        const params: Record<string, Object> = { 'chatId': id };
        this.openChatAndClose(params);
      } else {
        this.resetResultOpening();
      }
    }).catch((e: TdError) => {
      this.resetResultOpening();
      logE(`GlobalSearchPage.openApp failed: ${e.message}`);
    });
  }

  // A message hit lands on that message AND carries the query, so the chat opens
  // in its in-chat search with the tapped message as the current hit — ∧/∨ then
  // walk this chat's other hits for the same words.
  private openResult(it: FoundItem): void {
    const openingKey = `message:${it.chatId}:${it.messageId}`;
    if (!this.beginResultOpening(openingKey)) {
      return;
    }
    const params: Record<string, Object> = { 'chatId': it.chatId, 'jumpTo': it.messageId };
    const q = this.query.trim();
    if (q !== '') {
      params['searchQuery'] = q;
    }
    this.openChatAndClose(params);
  }

  private resolvedTopUsers(): SearchRow[] {
    return this.topUsers.filter((row: SearchRow) => row.title !== '');
  }

  private resolvedRecent(): SearchRow[] {
    return this.recent.filter((row: SearchRow) => row.title !== '');
  }

  private resolvedRecentlyOpened(): SearchRow[] {
    const foundIds = new Set<number>();
    for (const row of this.recent) {
      foundIds.add(row.chatId);
    }
    return this.recentlyOpened.filter((row: SearchRow) =>
      row.title !== '' && !foundIds.has(row.chatId));
  }

  private landingResolving(): boolean {
    return !this.topLoaded || !this.recentLoaded || !this.openedLoaded
      || this.topUsers.some((row: SearchRow) => row.title === '')
      || this.recent.some((row: SearchRow) => row.title === '')
      || this.recentlyOpened.some((row: SearchRow) => row.title === '');
  }

  private landingFailed(): boolean {
    return this.topFailed || this.recentFailed || this.openedFailed;
  }

  private retryLanding(): void {
    if (this.store !== null) {
      this.store.retryLanding();
    }
  }

  private retryChannels(): void {
    if (this.store !== null) {
      this.store.retryChannels();
    }
  }

  private retryApps(): void {
    if (this.store !== null) {
      this.store.retryApps();
    }
  }

  private confirmClearRecent(): void {
    if (this.clearRecentDialogOpen || this.clearingRecent || this.resolvedRecent().length === 0) {
      return;
    }
    this.clearRecentDialogOpen = true;
    promptAction.showDialog({
      title: $r('app.string.gs_clear_recent'),
      message: $r('app.string.gs_clear_recent_confirm'),
      buttons: [
        { text: $r('app.string.cancel'), color: COLOR_TEXT_SECONDARY as string },
        { text: $r('app.string.clear_all'), color: '#E64646' }
      ]
    }).then((result: promptAction.ShowDialogSuccessResponse): void => {
      this.clearRecentDialogOpen = false;
      if (result.index === 1) {
        this.performClearRecent();
      }
    }).catch((): void => {
      this.clearRecentDialogOpen = false;
    });
  }

  private confirmClearOpened(): void {
    const store = this.store;
    if (store === null || this.clearOpenedDialogOpen || this.resolvedRecentlyOpened().length === 0) { return; }
    this.clearOpenedDialogOpen = true;
    promptAction.showDialog({
      title: $r('app.string.gs_clear_opened'),
      message: $r('app.string.gs_clear_opened_confirm'),
      buttons: [
        { text: $r('app.string.cancel'), color: COLOR_TEXT_SECONDARY as string },
        { text: $r('app.string.clear_all'), color: '#E64646' }
      ]
    }).then((result: promptAction.ShowDialogSuccessResponse): void => {
      if (this.store !== store) { return; }
      this.clearOpenedDialogOpen = false;
      if (result.index === 1) {
        try { store.clearOpened(); }
        catch (_error) { promptAction.showToast({ message: $r('app.string.gs_clear_failed'), duration: 1800 }); }
      }
    }).catch((): void => {
      if (this.store === store) { this.clearOpenedDialogOpen = false; }
    });
  }

  private finishRecentDeleteEffect(): void {
    const action = this.pendingRecentDelete;
    this.pendingRecentDelete = null;
    this.deleteEffectVisible = false;
    if (action !== null) { action(); }
  }

  private playRecentDeleteEffect(key: string, action: () => void): void {
    if (this.deletingRecentKey !== '') { return; }
    const duration = powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 820);
    if (duration === 0 || this.query.trim() !== '') { action(); return; }
    this.pendingRecentDelete = action;
    this.deletingRecentKey = key;
    this.deleteSnapshotReady = false;
    this.deleteEffectVisible = true;
  }

  private removeRecent(chatId: number): void {
    const store = this.store;
    if (store === null) { return; }
    this.playRecentDeleteEffect('recent:' + chatId, (): void => {
      store.removeRecent(chatId).then((): void => {
        if (this.store === store) { this.deletingRecentKey = ''; }
      }).catch((): void => {
        if (this.store === store) {
          this.deletingRecentKey = '';
          promptAction.showToast({ message: $r('app.string.gs_clear_failed'), duration: 1800 });
        }
      });
    });
  }

  private removeOpened(chatId: number): void {
    const store = this.store;
    if (store === null) { return; }
    this.playRecentDeleteEffect('opened:' + chatId, (): void => {
      try { store.removeOpened(chatId); }
      catch (_error) {
        if (this.store === store) {
          promptAction.showToast({ message: $r('app.string.gs_clear_failed'), duration: 1800 });
        }
      } finally {
        if (this.store === store) { this.deletingRecentKey = ''; }
      }
    });
  }

  private performClearRecent(): void {
    if (this.store === null || this.clearingRecent) {
      return;
    }
    this.clearingRecent = true;
    this.store.clearRecent().then((): void => {
      this.clearingRecent = false;
    }).catch((): void => {
      this.clearingRecent = false;
      promptAction.showToast({ message: $r('app.string.gs_clear_failed'), duration: 1800 });
    });
  }

  @Builder
  searchBar() {
    Row({ space: 10 }) {
      Row({ space: 8 }) {
        Stack({ alignContent: Alignment.Center }) {
          if (this.searchBusy()) {
            LoadingProgress()
              .width(18)
              .height(18)
              .color(COLOR_PRIMARY)
              .transition(TransitionEffect.OPACITY
                .combine(TransitionEffect.scale({ x: 0.72, y: 0.72 }))
                .animation({
                  duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 150),
                  curve: Curve.EaseOut
                }));
          } else {
            SymbolGlyph($r('sys.symbol.magnifyingglass'))
              .fontSize(18)
              .fontColor([this.searchFocused ? COLOR_PRIMARY : COLOR_ICON_SECONDARY])
              .transition(TransitionEffect.OPACITY
                .combine(TransitionEffect.scale({ x: 0.84, y: 0.84 }))
                .animation({
                  duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 150),
                  curve: Curve.EaseOut
                }));
          }
        }
        .width(22)
        .height(22);

        TextInput({ text: this.query, placeholder: this.searchPlaceholder() })
          .layoutWeight(1)
          .height(44)
          .fontSize(16)
          .backgroundColor(Color.Transparent)
          .padding(0)
          .borderRadius(0)
          .placeholderColor(COLOR_TEXT_SECONDARY)
          .caretColor(COLOR_PRIMARY)
          .enterKeyType(EnterKeyType.Search)
          .defaultFocus(true)
          .enabled(!this.closingSearch)
          .onFocus((): void => { this.searchFocused = true; })
          .onBlur((): void => { this.searchFocused = false; })
          .onChange((value: string): void => { this.onQueryChanged(value); })
          .onSubmit((): void => { this.submitSearch(); });

        if (this.query !== '') {
          Row() {
            SymbolGlyph($r('sys.symbol.xmark_circle'))
              .fontSize(19)
              .fontColor([COLOR_ICON_SECONDARY]);
          }
          .width(32)
          .height(32)
          .borderRadius(16)
          .justifyContent(FlexAlign.Center)
          .backgroundColor(this.clearPressed
            ? $r('app.color.selected_pill') : Color.Transparent)
          .scale({
            x: this.clearPressed ? 0.9 : 1,
            y: this.clearPressed ? 0.9 : 1
          })
          .animation({
            duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 110),
            curve: Curve.EaseOut
          })
          .accessibilityText($r('app.string.clear_search'))
          .onTouch((event: TouchEvent): void => {
            if (event.type === TouchType.Down) {
              this.clearPressed = true;
            } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
              this.clearPressed = false;
            }
          })
          .onClick((): void => {
            this.clearPressed = false;
            this.clearSearch();
          })
          .transition(TransitionEffect.OPACITY
            .combine(TransitionEffect.scale({ x: 0.72, y: 0.72 }))
            .animation({
              duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 150),
              curve: Curve.EaseOut
            }));
        }
      }
      .layoutWeight(1)
      .height(48)
      .padding({ left: 13, right: 8 })
    .backgroundColor(mainCardFill(this.appWallpaperOn, false))
      .borderRadius(24)
      .border({
        width: this.searchFocused ? 1.5 : 0.5,
        color: this.searchFocused ? COLOR_PRIMARY : $r('app.color.divider')
      })
      .shadow({
        radius: this.searchFocused ? 6 : 0,
        color: this.searchFocused ? '#18000000' : '#00000000',
        offsetX: 0,
        offsetY: 2
      })
      .alignItems(VerticalAlign.Center)
      .animation({
        duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 160),
        curve: Curve.EaseOut
      });

      Text(this.closingSearch ? $r('app.string.gs_closing') : $r('app.string.cancel'))
        .width(50)
        .height(44)
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.closingSearch ? COLOR_TEXT_SECONDARY : COLOR_PRIMARY)
        .textAlign(TextAlign.Center)
        .opacity(this.cancelPressed ? 0.55 : 1)
        .scale({
          x: this.cancelPressed ? 0.94 : 1,
          y: this.cancelPressed ? 0.94 : 1
        })
        .animation({
          duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 110),
          curve: Curve.EaseOut
        })
        .enabled(!this.closingSearch)
        .accessibilityText($r('app.string.gs_close_search'))
        .onTouch((event: TouchEvent): void => {
          if (event.type === TouchType.Down && !this.closingSearch) {
            this.cancelPressed = true;
          } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
            this.cancelPressed = false;
          }
        })
        .onClick((): void => {
          this.closeSearch();
        });
    }
    .width('100%')
    .height(52)
    .alignItems(VerticalAlign.Center)
    .opacity(this.searchHeaderVisible ? 1 : 0)
    .translate({ y: this.searchHeaderVisible ? 0 : -8 })
    .animation({
      duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 200),
      curve: Curve.EaseOut
    });
  }

  private categoryIds(showRecent: boolean): number[] {
    const ids: number[] = showRecent ? [SEARCH_TAB_RECENT] : [];
    for (let i = 0; i < TABS.length; i++) { ids.push(i); }
    return ids;
  }

  @Builder
  searchCategoryTabs(showRecent: boolean) {
    List({ space: 8, initialIndex: Math.max(0, this.tab + (showRecent ? 1 : 0)) }) {
      ForEach(this.categoryIds(showRecent), (index: number) => {
        ListItem() {
          Text(index === SEARCH_TAB_RECENT ? str('gs_tab_recent') : TABS[index])
            .fontSize(14)
            .fontWeight(this.tab === index ? FontWeight.Medium : FontWeight.Normal)
            .fontColor(this.tab === index ? COLOR_PRIMARY : COLOR_TEXT_SECONDARY)
            .maxLines(1)
            .height(36)
            .padding({ left: 12, right: 12 })
            .borderRadius(18)
            .backgroundColor(this.tab === index ? $r('app.color.selected_pill') : Color.Transparent);
        }
        .accessibilitySelected(this.tab === index)
        .onClick((): void => { if (index !== this.tab) { this.onTabSelected(index); } });
      }, (index: number): string => String(index));
    }
    .listDirection(Axis.Horizontal)
    .scrollBar(BarState.Off)
    .width('100%').height(40)
    .margin({ top: 8 });
  }

  @Builder
  chatRow(r: SearchRow, showDivider: boolean) {
    Column() {
      if (showDivider) {
        Divider().color($r('app.color.divider')).strokeWidth(0.7)
          .margin({ left: SEARCH_RESULT_DIVIDER_INSET });
      }
      Row({ space: 12 }) {
        AvatarView({
          avatarPath: r.avatarPath, initials: r.initials, colorSeed: r.chatId, avatarSize: 48,
          savedMessages: this.store !== null && r.chatId === this.store.selfChatId()
        });
        Column({ space: 3 }) {
          Text(r.title !== '' ? r.title : '…')
            .fontSize(16).fontWeight(FontWeight.Medium).fontColor(COLOR_TEXT_PRIMARY)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
          if (r.subtitle !== '') {
            Text(r.subtitle).fontSize(13).fontColor(COLOR_TEXT_SECONDARY)
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
          }
        }.alignItems(HorizontalAlign.Start).layoutWeight(1);
        if (this.resultOpeningKey === `chat:${r.chatId}`) {
          LoadingProgress().width(18).height(18).color(COLOR_PRIMARY);
        }
      }
      .width('100%')
      .constraintSize({ minHeight: 64 })
      .padding({ left: 14, right: 14, top: 8, bottom: 8 })
      .alignItems(VerticalAlign.Center)
      .stateStyles({
        normal: this.resultRowNormalStyle,
        pressed: this.resultRowPressedStyle
      })
      .accessibilityText(`${r.title}${r.subtitle !== '' ? '，' + r.subtitle : ''}`)
      .onClick(() => { this.openChat(r.chatId); });
    }
  }

  @Builder
  frequentSection() {
    Column() {
      Row() {
        Text($r('app.string.gs_frequent_contacts'))
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(COLOR_TEXT_PRIMARY);
      }
      .width('100%')
      .padding({ left: 14, right: 14, top: 12, bottom: 4 });

      // 横向 List + LazyForEach + 复用格（SearchFrequentCell）；点击和按压态挂在 ListItem 上。
      List({ space: 4 }) {
        LazyForEach(this.topUsersData, (row: SearchRow) => {
          ListItem() {
            SearchFrequentCell({
              chatId: row.chatId, title: row.title, avatarPath: row.avatarPath, initials: row.initials,
              savedMessages: this.isSavedMessagesChat(row.chatId),
              opening: this.resultOpeningKey === `chat:${row.chatId}`
            });
          }
          .borderRadius(14)
          .stateStyles({
            normal: this.landingActionNormalStyle,
            pressed: this.landingActionPressedStyle
          })
          .accessibilityText(str('gs_frequent_a11y', row.title))
          .onClick((): void => { this.openChat(row.chatId); });
        }, (row: SearchRow, index: number): string =>
          guardKey(this.topUsersData.keyTableId, index, frequentCellKey(row)));
      }
      .listDirection(Axis.Horizontal)
      // 高 100 = 格高 92 + 原来横排下边距 8；左右 8 原来是横排的内边距，现在是内容偏移。
      .width('100%').height(100)
      .contentStartOffset(8).contentEndOffset(8)
      .scrollBar(BarState.Off)
      .cachedCount(4);
    }
    .width('100%')
    .margin({ top: 8 })
    .backgroundColor(mainCardFill(this.appWallpaperOn, false))
    .borderRadius(18)
    .clip(true)
    .transition(TransitionEffect.OPACITY
      .combine(TransitionEffect.translate({ y: 5 }))
      .animation({
        duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 180),
        curve: Curve.EaseOut
      }));
  }

  // 卡片标题（含下面那条分隔线）放在 ListItemGroup 的 header 里；组的 divider 只画在行与行之间。
  @Builder
  recentHeader() {
    Column() {
      Row() {
        Row({ space: 6 }) {
          SymbolGlyph($r('sys.symbol.clock'))
            .fontSize(16)
            .fontColor([COLOR_ICON_SECONDARY]);
          Text($r('app.string.gs_recent'))
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor(COLOR_TEXT_PRIMARY);
        }
        .layoutWeight(1);

        Row() {
          if (this.clearingRecent) {
            LoadingProgress().width(16).height(16).color(COLOR_PRIMARY);
          } else {
            Text($r('app.string.clear_all'))
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor(COLOR_PRIMARY);
          }
        }
        .width(58)
        .height(32)
        .borderRadius(16)
        .justifyContent(FlexAlign.Center)
        .stateStyles({
          normal: this.landingActionNormalStyle,
          pressed: this.landingActionPressedStyle
        })
        .enabled(!this.clearingRecent)
        .accessibilityText($r('app.string.gs_clear_recent'))
        .onClick((): void => { this.confirmClearRecent(); });
      }
      .width('100%')
      .height(46)
      .padding({ left: 14, right: 8 });

      Divider()
        .color($r('app.color.divider'))
        .strokeWidth(0.7)
        .margin({ left: 14 });
    }
    .width('100%');
  }

  @Builder
  recentSection() {
    ListItemGroup({ header: this.recentHeader() }) {
      LazyForEach(this.recentData, (r: SearchRow) => {
        ListItem() {
          Stack({ alignContent: Alignment.TopStart }) {
          Row() {
            SearchChatRow({
              query: this.query,
              chatId: r.chatId, title: r.title, subtitle: r.subtitle, avatarPath: r.avatarPath,
              initials: r.initials, savedMessages: this.isSavedMessagesChat(r.chatId),
              opening: this.resultOpeningKey === `chat:${r.chatId}`, wallpaperOn: this.appWallpaperOn
            })
              .layoutWeight(1)
              .onClick((): void => { this.openChat(r.chatId); });
            Button({ type: ButtonType.Circle }) {
              SymbolGlyph($r('sys.symbol.xmark'))
                .fontSize(16)
                .fontColor([COLOR_ICON_SECONDARY]);
            }
            .width(40).height(40)
            .margin({ right: 6 })
            .backgroundColor(Color.Transparent)
            .enabled(!this.clearingRecent)
            .accessibilityText(str('delete') + ' ' + str('gs_recent') + ' ' + r.title)
            .onClick((): void => { this.removeRecent(r.chatId); });
          }.width('100%')
          .backgroundColor(mainCardFill(this.appWallpaperOn, false))
          .id('search-delete-recent-' + r.chatId)
          .opacity(this.deleteSnapshotReady && this.deletingRecentKey === 'recent:' + r.chatId ? 0 : 1);
          if (this.deleteEffectVisible && this.deletingRecentKey === 'recent:' + r.chatId) {
            ShatterDeleteOverlay({
              nodeId: 'search-delete-recent-' + r.chatId,
              onCaptured: (): void => { this.deleteSnapshotReady = true; },
              onFinish: (): void => { this.finishRecentDeleteEffect(); }
            }).position({ x: 0, y: 0 });
          }
          }.width('100%')
            .enabled(this.deletingRecentKey === '');
        }
        .transition(TransitionEffect.asymmetric(
          TransitionEffect.IDENTITY,
          TransitionEffect.OPACITY
        ))
        .accessibilityText(`${r.title}${r.subtitle !== '' ? '，' + r.subtitle : ''}`);
      }, (r: SearchRow, index: number): string =>
        guardKey(this.recentData.keyTableId, index, searchRowKey(r)));
    }
    .divider({ strokeWidth: 0.7, color: $r('app.color.divider'), startMargin: SEARCH_RESULT_DIVIDER_INSET })
    .width('100%')
    .margin({ top: 10, bottom: 10 })
    .backgroundColor(mainCardFill(this.appWallpaperOn, false))
    .borderRadius(18)
    .clip(!this.deleteEffectVisible)
    .transition(TransitionEffect.asymmetric(
      TransitionEffect.IDENTITY,
      TransitionEffect.OPACITY
    ));
  }

  @Builder
  recentlyOpenedHeader() {
    Column() {
      Row() {
        Row({ space: 6 }) {
          SymbolGlyph($r('sys.symbol.clock'))
            .fontSize(16)
            .fontColor([COLOR_ICON_SECONDARY]);
          Text($r('app.string.gs_recent_chats'))
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor(COLOR_TEXT_PRIMARY);
        }
        .layoutWeight(1);
        Button($r('app.string.clear_all'))
          .fontSize(14)
          .fontColor(COLOR_PRIMARY)
          .backgroundColor(Color.Transparent)
          .height(32)
          .accessibilityText($r('app.string.gs_clear_opened'))
          .onClick((): void => { this.confirmClearOpened(); });
      }
      .width('100%')
      .height(46)
      .padding({ left: 14, right: 14 });

      Divider()
        .color($r('app.color.divider'))
        .strokeWidth(0.7)
        .margin({ left: 14 });
    }
    .width('100%');
  }

  @Builder
  recentlyOpenedSection() {
    ListItemGroup({ header: this.recentlyOpenedHeader() }) {
      LazyForEach(this.recentlyOpenedData, (r: SearchRow) => {
        ListItem() {
          Stack({ alignContent: Alignment.TopStart }) {
          Row() {
            SearchChatRow({
              query: this.query,
              chatId: r.chatId, title: r.title, subtitle: r.subtitle, avatarPath: r.avatarPath,
              initials: r.initials, savedMessages: this.isSavedMessagesChat(r.chatId),
              opening: this.resultOpeningKey === `chat:${r.chatId}`, wallpaperOn: this.appWallpaperOn
            })
              .layoutWeight(1)
              .onClick((): void => { this.openChat(r.chatId); });
            Button({ type: ButtonType.Circle }) {
              SymbolGlyph($r('sys.symbol.xmark'))
                .fontSize(16)
                .fontColor([COLOR_ICON_SECONDARY]);
            }
            .width(40).height(40)
            .margin({ right: 6 })
            .backgroundColor(Color.Transparent)
            .accessibilityText(str('gs_remove_opened') + ' ' + r.title)
            .onClick((): void => { this.removeOpened(r.chatId); });
          }
          .width('100%')
          .backgroundColor(mainCardFill(this.appWallpaperOn, false))
          .id('search-delete-opened-' + r.chatId)
          .opacity(this.deleteSnapshotReady && this.deletingRecentKey === 'opened:' + r.chatId ? 0 : 1);
          if (this.deleteEffectVisible && this.deletingRecentKey === 'opened:' + r.chatId) {
            ShatterDeleteOverlay({
              nodeId: 'search-delete-opened-' + r.chatId,
              onCaptured: (): void => { this.deleteSnapshotReady = true; },
              onFinish: (): void => { this.finishRecentDeleteEffect(); }
            }).position({ x: 0, y: 0 });
          }
          }.width('100%')
            .enabled(this.deletingRecentKey === '');
        }
        .transition(TransitionEffect.asymmetric(
          TransitionEffect.IDENTITY,
          TransitionEffect.OPACITY
        ))
        .accessibilityText(`${r.title}${r.subtitle !== '' ? '，' + r.subtitle : ''}`);
      }, (r: SearchRow, index: number): string =>
        guardKey(this.recentlyOpenedData.keyTableId, index, searchRowKey(r)));
    }
    .divider({ strokeWidth: 0.7, color: $r('app.color.divider'), startMargin: SEARCH_RESULT_DIVIDER_INSET })
    .width('100%')
    .margin({ top: 10, bottom: 10 })
    .backgroundColor(mainCardFill(this.appWallpaperOn, false))
    .borderRadius(18)
    .clip(!this.deleteEffectVisible)
    .transition(TransitionEffect.asymmetric(
      TransitionEffect.IDENTITY,
      TransitionEffect.OPACITY
    ));
  }

  @Builder
  landingLoadingState() {
    Row({ space: 10 }) {
      LoadingProgress().width(22).height(22).color(COLOR_PRIMARY);
      Text($r('app.string.gs_loading_recent'))
        .fontSize(14)
        .fontColor(COLOR_TEXT_SECONDARY);
    }
    .width('100%')
    .height(116)
    .justifyContent(FlexAlign.Center);
  }

  @Builder
  landingEmptyState() {
    Column({ space: 9 }) {
      Stack({ alignContent: Alignment.Center }) {
        Circle({ width: 62, height: 62 }).fill($r('app.color.surface_alt'));
        SymbolGlyph($r('sys.symbol.magnifyingglass'))
          .fontSize(28)
          .fontColor([COLOR_ICON_SECONDARY]);
      }
      Text($r('app.string.gs_search_chats'))
        .fontSize(17)
        .fontWeight(FontWeight.Medium)
        .fontColor(COLOR_TEXT_PRIMARY);
      Text($r('app.string.gs_empty_hint'))
        .fontSize(13)
        .lineHeight(19)
        .fontColor(COLOR_TEXT_SECONDARY)
        .textAlign(TextAlign.Center)
        .constraintSize({ maxWidth: 250 });
    }
    .width('100%')
    .height(214)
    .margin({ top: 12 })
    .justifyContent(FlexAlign.Center)
    .backgroundColor(mainCardFill(this.appWallpaperOn, false))
    .borderRadius(20)
    .transition(TransitionEffect.OPACITY
      .combine(TransitionEffect.scale({ x: 0.97, y: 0.97 }))
      .animation({
        duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 180),
        curve: Curve.EaseOut
      }));
  }

  @Builder
  landingErrorState() {
    Column({ space: 8 }) {
      Stack({ alignContent: Alignment.Center }) {
        Circle({ width: 58, height: 58 }).fill('#18E64646');
        SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
          .fontSize(28)
          .fontColor(['#E64646']);
      }
      Text($r('app.string.gs_recent_failed'))
        .fontSize(17)
        .fontWeight(FontWeight.Medium)
        .fontColor(COLOR_TEXT_PRIMARY);
      Text($r('app.string.ct_service_unavailable'))
        .fontSize(13)
        .fontColor(COLOR_TEXT_SECONDARY);
      Row({ space: 6 }) {
        SymbolGlyph($r('sys.symbol.arrow_clockwise'))
          .fontSize(15)
          .fontColor([COLOR_PRIMARY]);
        Text($r('app.string.settings_reload'))
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(COLOR_PRIMARY);
      }
      .height(38)
      .padding({ left: 16, right: 16 })
      .margin({ top: 4 })
      .borderRadius(19)
      .stateStyles({
        normal: this.retryActionNormalStyle,
        pressed: this.retryActionPressedStyle
      })
      .accessibilityText($r('app.string.gs_reload_recent'))
      .onClick((): void => { this.retryLanding(); });
    }
    .width('100%')
    .height(220)
    .margin({ top: 12 })
    .justifyContent(FlexAlign.Center)
    .backgroundColor(mainCardFill(this.appWallpaperOn, false))
    .borderRadius(20)
    .transition(TransitionEffect.OPACITY
      .combine(TransitionEffect.scale({ x: 0.97, y: 0.97 }))
      .animation({
        duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 180),
        curve: Curve.EaseOut
      }));
  }

  // Empty-query landing: frequent contacts, recently searched chats and a
  // useful first-run state once both sources have settled.
  // 整页一个 List：常用联系人一项、两张会话卡各一组，行走 LazyForEach + 复用行——原来是
  // Scroll 里的 ForEach，每次点开搜索都把几十行一次建完。
  @Builder
  landing() {
    List({ scroller: this.landingScroller }) {
      if (this.resolvedTopUsers().length > 0) {
        ListItem() {
          this.frequentSection();
        }
      }
      if (this.resolvedRecent().length > 0) {
        this.recentSection();
      }
      if (this.resolvedRecentlyOpened().length > 0) {
        this.recentlyOpenedSection();
      }
      if (this.resolvedTopUsers().length === 0 && this.resolvedRecent().length === 0 &&
        this.resolvedRecentlyOpened().length === 0) {
        ListItem() {
          if (this.landingResolving()) {
            this.landingLoadingState();
          } else if (this.landingFailed()) {
            this.landingErrorState();
          } else {
            this.landingEmptyState();
          }
        }
      }
    }
    .layoutWeight(1)
    .width('100%')
    .edgeEffect(EdgeEffect.Spring)
    .scrollBar(BarState.Off)
    .cachedCount(4)
    .maintainVisibleContentPosition(true)
    .contentStartOffset(this.headerHeight())
    .linearGradientBlur(BLUR_MAX_VP, {
      fractionStops: edgeBlurStops(this.listViewH),
      direction: GradientDirection.Bottom
    })
    .clip(false)
    .onAreaChange((_o: Area, n: Area): void => {
      const h: number = n.height as number;
      if (h > 0 && Math.abs(h - this.listViewH) > 0.5) { this.listViewH = h; }
    })
    // 底部留白原来是内容列的 padding（随内容滚动），在 List 上对应 contentEndOffset。
    .contentEndOffset(8);
  }

  @Builder
  sectionHeader(label: string) {
    Text(label).fontSize(14).fontWeight(FontWeight.Medium).fontColor(COLOR_TEXT_SECONDARY)
      .width('100%').padding({ left: 16, right: 16, top: 12, bottom: 6 });
  }

  @Builder
  catalogLoadingState(label: string) {
    Column({ space: 10 }) {
      LoadingProgress().width(32).height(32).color(COLOR_PRIMARY);
      Text(label)
        .fontSize(14)
        .fontColor(COLOR_TEXT_SECONDARY);
    }
    .width('100%')
    .height(170)
    .justifyContent(FlexAlign.Center)
    .transition(TransitionEffect.OPACITY.animation({
      duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 160),
      curve: Curve.EaseOut
    }));
  }

  @Builder
  catalogErrorState(title: string, tab: number) {
    Column({ space: 8 }) {
      Stack({ alignContent: Alignment.Center }) {
        Circle({ width: 56, height: 56 }).fill('#18E64646');
        SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
          .fontSize(27)
          .fontColor(['#E64646']);
      }
      Text(title)
        .fontSize(17)
        .fontWeight(FontWeight.Medium)
        .fontColor(COLOR_TEXT_PRIMARY);
      Text($r('app.string.ct_service_unavailable'))
        .fontSize(13)
        .fontColor(COLOR_TEXT_SECONDARY);
      Row({ space: 6 }) {
        SymbolGlyph($r('sys.symbol.arrow_clockwise'))
          .fontSize(15)
          .fontColor([COLOR_PRIMARY]);
        Text($r('app.string.settings_reload'))
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(COLOR_PRIMARY);
      }
      .height(38)
      .padding({ left: 16, right: 16 })
      .margin({ top: 4 })
      .borderRadius(19)
      .stateStyles({
        normal: this.retryActionNormalStyle,
        pressed: this.retryActionPressedStyle
      })
      .accessibilityText(title)
      .onClick((): void => {
        if (tab === TAB_MESSAGES) {
          this.retryChannels();
        } else {
          this.retryApps();
        }
      });
    }
    .width('100%')
    .height(214)
    .margin({ top: 12 })
    .justifyContent(FlexAlign.Center)
    .backgroundColor(mainCardFill(this.appWallpaperOn, false))
    .borderRadius(20)
    .transition(TransitionEffect.OPACITY
      .combine(TransitionEffect.scale({ x: 0.97, y: 0.97 }))
      .animation({
        duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 180),
        curve: Curve.EaseOut
      }));
  }

  @Builder
  catalogEmptyState(title: string, detail: string, symbol: Resource) {
    Column({ space: 8 }) {
      Stack({ alignContent: Alignment.Center }) {
        Circle({ width: 58, height: 58 }).fill($r('app.color.surface_alt'));
        SymbolGlyph(symbol)
          .fontSize(27)
          .fontColor([COLOR_ICON_SECONDARY]);
      }
      Text(title)
        .fontSize(17)
        .fontWeight(FontWeight.Medium)
        .fontColor(COLOR_TEXT_PRIMARY);
      Text(detail)
        .fontSize(13)
        .fontColor(COLOR_TEXT_SECONDARY)
        .textAlign(TextAlign.Center);
    }
    .width('100%')
    .height(194)
    .margin({ top: 12 })
    .justifyContent(FlexAlign.Center)
    .backgroundColor(mainCardFill(this.appWallpaperOn, false))
    .borderRadius(20)
    .transition(TransitionEffect.OPACITY
      .combine(TransitionEffect.scale({ x: 0.97, y: 0.97 }))
      .animation({
        duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 180),
        curve: Curve.EaseOut
      }));
  }

  // 频道 tab landing: joined channels + server-recommended channels.
  // 两组各是「标题项 + ListItemGroup」，行走 LazyForEach + 复用行（SearchChatRow）。分隔线交给
  // 组的 divider：原来按 idx > 0 在行内画，LazyForEach 下删掉首行后，新的首行沿用旧节点，
  // 顶上会多一条线。点击和无障碍文本挂在 ListItem 上，闭包随行 key 重建。
  @Builder
  channelsLanding() {
    List() {
      if (this.joinedChannels.length > 0) {
        ListItem() {
          this.sectionHeader(str('gs_joined_channels'));
        }
        ListItemGroup() {
          LazyForEach(this.joinedChannelsData, (r: SearchRow) => {
            ListItem() {
              SearchChatRow({
                query: this.query,
                chatId: r.chatId, title: r.title, subtitle: r.subtitle, avatarPath: r.avatarPath,
                initials: r.initials, savedMessages: this.isSavedMessagesChat(r.chatId),
                opening: this.resultOpeningKey === `chat:${r.chatId}`, wallpaperOn: this.appWallpaperOn
              });
            }
            .accessibilityText(`${r.title}${r.subtitle !== '' ? '，' + r.subtitle : ''}`)
            .onClick(() => { this.openChat(r.chatId); });
          }, (r: SearchRow, index: number): string =>
            guardKey(this.joinedChannelsData.keyTableId, index, searchRowKey(r)));
        }
        .divider({ strokeWidth: 0.7, color: $r('app.color.divider'), startMargin: SEARCH_RESULT_DIVIDER_INSET })
        .backgroundColor(mainCardFill(this.appWallpaperOn, false));
      }
      if (this.similarChannels.length > 0) {
        ListItem() {
          this.sectionHeader(str('gs_similar_channels'));
        }
        ListItemGroup() {
          LazyForEach(this.similarChannelsData, (r: SearchRow) => {
            ListItem() {
              SearchChatRow({
                query: this.query,
                chatId: r.chatId, title: r.title, subtitle: r.subtitle, avatarPath: r.avatarPath,
                initials: r.initials, savedMessages: this.isSavedMessagesChat(r.chatId),
                opening: this.resultOpeningKey === `chat:${r.chatId}`, wallpaperOn: this.appWallpaperOn
              });
            }
            .accessibilityText(`${r.title}${r.subtitle !== '' ? '，' + r.subtitle : ''}`)
            .onClick(() => { this.openChat(r.chatId); });
          }, (r: SearchRow, index: number): string =>
            guardKey(this.similarChannelsData.keyTableId, index, searchRowKey(r)));
        }
        .divider({ strokeWidth: 0.7, color: $r('app.color.divider'), startMargin: SEARCH_RESULT_DIVIDER_INSET })
        .backgroundColor(mainCardFill(this.appWallpaperOn, false));
      }
      if (this.joinedChannels.length === 0 && this.similarChannels.length === 0) {
        ListItem() {
          if (!this.joinedLoaded || !this.similarLoaded) {
            this.catalogLoadingState(str('gs_loading_channels'));
          } else if (this.joinedFailed || this.similarFailed) {
            this.catalogErrorState(str('gs_channels_failed'), TAB_MESSAGES);
          } else {
            this.catalogEmptyState(
              str('gs_no_suggested'),
              str('gs_join_to_see'),
              $r('sys.symbol.message')
            );
          }
        }
      }
    }
    .layoutWeight(1).width('100%')
    .edgeEffect(EdgeEffect.Spring)
    .scrollBar(BarState.Off)
    .cachedCount(4);
  }

  // 应用 tab: top-grossing mini apps; a typed query filters by name.
  // 标题一项、榜单一组（LazyForEach + 复用行 SearchAppRow），分隔线交给组的 divider。
  @Builder
  appsList() {
    List() {
      ListItem() {
        this.sectionHeader(str(this.query.trim() === '' ? 'gs_popular_apps' : 'gs_app_results'));
      }
      ListItemGroup() {
        LazyForEach(this.appsData, (r: SearchRow) => {
          ListItem() {
            SearchAppRow({
              query: this.query, identity: r.identity, userId: r.userId, title: r.title, subtitle: r.subtitle, avatarPath: r.avatarPath,
              initials: r.initials, opening: this.resultOpeningKey === `app:${r.userId}`,
              wallpaperOn: this.appWallpaperOn
            });
          }
          .accessibilityText(str('gs_open_a11y', r.title, r.subtitle !== '' ? str('gs_comma') + r.subtitle : ''))
          .onClick(() => { this.openApp(r.userId); });
        }, (r: SearchRow, index: number): string =>
          guardKey(this.appsData.keyTableId, index, appRowKey(r) + this.query + JSON.stringify(r.identity)));
      }
      .divider({ strokeWidth: 0.7, color: $r('app.color.divider'), startMargin: SEARCH_RESULT_DIVIDER_INSET })
      .backgroundColor(mainCardFill(this.appWallpaperOn, false));
      if (this.query.trim() !== '' && (this.chatSearching || this.chatSearchFailed)) {
        ListItem() { this.chatSearchInlineState(); }
      }
      if (this.filteredAppResults().length === 0) {
        ListItem() {
          if (!this.appsLoaded || this.apps.some((row: SearchRow) => row.title === '')) {
            this.catalogLoadingState(str('gs_loading_apps'));
          } else if (this.appsFailed) {
            this.catalogErrorState(str('gs_apps_failed'), TAB_APPS);
          } else {
            this.catalogEmptyState(
              str('gs_no_apps'),
              str('gs_check_back'),
              $r('sys.symbol.dot_grid_1x2')
            );
          }
        }
      }
    }
    .layoutWeight(1).width('100%')
    .edgeEffect(EdgeEffect.Spring)
    .scrollBar(BarState.Off)
    .cachedCount(4);
  }

  private filteredChatResults(): SearchRow[] {
    return this.chatResults.filter((row: SearchRow) =>
      row.title !== '' && (this.objectScope === 'all' || row.identity?.kind === this.objectScope));
  }

  private filteredAppResults(): SearchRow[] {
    const q = this.query.trim().toLowerCase();
    const rows = this.apps.filter((row: SearchRow): boolean => row.title !== '' &&
      (q === '' || row.title.toLowerCase().includes(q) ||
        row.identity?.usernames.some((name: string): boolean => ('@' + name).toLowerCase().includes(q)) === true));
    if (q !== '') {
      for (const row of this.chatResults) {
        if (row.title !== '' && row.identity?.isBot === true && row.userId > 0 &&
          !rows.some((item: SearchRow): boolean => item.userId === row.userId)) { rows.push(row); }
      }
    }
    return rows;
  }

  // —— 结果列表的 LazyForEach 数据源同步（@Watch 触发）——
  private syncJoinedChannelsData(): void {
    this.joinedChannelsData.update(this.joinedChannels,
      this.joinedChannels.map((r: SearchRow): string => searchRowId(r)),
      this.joinedChannels.map((r: SearchRow): string => searchRowKey(r)));
  }

  private syncSimilarChannelsData(): void {
    this.similarChannelsData.update(this.similarChannels,
      this.similarChannels.map((r: SearchRow): string => searchRowId(r)),
      this.similarChannels.map((r: SearchRow): string => searchRowKey(r)));
  }

  // 会话名结果按 tab 过滤（频道 tab 只留频道）：chatResults 和 tab 变了都走这里。
  private syncChatResultsData(): void {
    this.syncAppsData();
    const rows: SearchRow[] = this.filteredChatResults();
    const local = rows.filter((r: SearchRow): boolean => r.identity?.existing === true);
    const pub = rows.filter((r: SearchRow): boolean => r.identity?.existing !== true);
    this.localNamesData.update(local, local.map(searchRowId), local.map((r: SearchRow): string => searchRowKey(r) + this.query + JSON.stringify(r.identity)));
    this.publicNamesData.update(pub, pub.map(searchRowId), pub.map((r: SearchRow): string => searchRowKey(r) + this.query + JSON.stringify(r.identity)));
    this.combinedChatsData.update(rows,
      rows.map((r: SearchRow): string => searchRowId(r)),
      rows.map((r: SearchRow): string => searchRowKey(r)));
  }

  // 消息结果同样按 tab 过滤（频道 tab 只留频道消息）：items 和 tab 变了都走这里。
  private syncFoundItemsData(): void {
    const rows: FoundItem[] = this.visibleItems();
    const ids: string[] = rows.map((it: FoundItem): string => foundItemId(it));
    const keys: string[] = rows.map((it: FoundItem): string => foundItemKey(it) + this.query + JSON.stringify(it.match));
    this.messageItemsData.update(rows, ids, keys);
    this.combinedMessagesData.update(rows, ids, keys);
    this.mediaItemsData.update(rows, ids, rows.map((it: FoundItem): string => mediaItemKey(it)));
    this.traceMessageState('publish');
  }

  private syncTabFilteredData(): void {
    this.syncChatResultsData();
    this.syncFoundItemsData();
  }

  private syncQueryFilteredData(): void {
    this.syncChatResultsData();
    this.syncFoundItemsData();
  }

  // 应用榜按 query 过滤：应用 tab 和综合结果各一个容器。
  private syncAppsData(): void {
    const rows: SearchRow[] = this.filteredAppResults();
    const ids: string[] = rows.map((r: SearchRow): string => appRowId(r));
    const keys: string[] = rows.map((r: SearchRow): string => appRowKey(r) + this.query + JSON.stringify(r.identity));
    this.appsData.update(rows, ids, keys);
    this.combinedAppsData.update(rows, ids, keys);
  }

  // —— 搜索首页三块：常用联系人 / 最近搜索 / 最近打开 ——
  private syncTopUsersData(): void {
    const rows: SearchRow[] = this.resolvedTopUsers();
    this.topUsersData.update(rows,
      rows.map((r: SearchRow): string => searchRowId(r)),
      rows.map((r: SearchRow): string => frequentCellKey(r)));
  }

  private syncRecentData(): void {
    const rows: SearchRow[] = this.resolvedRecent();
    this.recentData.update(rows,
      rows.map((r: SearchRow): string => searchRowId(r)),
      rows.map((r: SearchRow): string => searchRowKey(r)));
    this.syncRecentlyOpenedData();
  }

  private syncRecentlyOpenedData(): void {
    const rows: SearchRow[] = this.resolvedRecentlyOpened();
    this.recentlyOpenedData.update(rows,
      rows.map((r: SearchRow): string => searchRowId(r)),
      rows.map((r: SearchRow): string => searchRowKey(r)));
  }

  private isSavedMessagesChat(chatId: number): boolean {
    return this.store !== null && chatId === this.store.selfChatId();
  }

  @Builder
  messageLoadingState(compact: boolean) {
    Column({ space: 10 }) {
      LoadingProgress()
        .width(compact ? 28 : 36)
        .height(compact ? 28 : 36)
        .color(COLOR_PRIMARY);
      Text($r('app.string.searching'))
        .fontSize(compact ? 13 : 15)
        .fontWeight(FontWeight.Medium)
        .fontColor(COLOR_TEXT_PRIMARY);
      if (!compact) {
        Text($r('app.string.gs_finding_messages'))
          .fontSize(13)
          .fontColor(COLOR_TEXT_SECONDARY);
      }
    }
    .layoutWeight(compact ? 0 : 1)
    .width('100%')
    .height(compact ? 106 : '100%')
    .margin({
      top: compact ? 0 : 12,
      bottom: compact ? 0 : 12
    })
    .justifyContent(FlexAlign.Center)
    .backgroundColor(mainCardFill(this.appWallpaperOn, false))
    .borderRadius(compact ? 0 : 20)
    .transition(TransitionEffect.OPACITY
      .combine(TransitionEffect.translate({ y: 3 }))
      .animation({
        duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 160),
        curve: Curve.EaseOut
      }));
  }

  @Builder
  messageErrorState(compact: boolean) {
    Column({ space: 8 }) {
      Stack({ alignContent: Alignment.Center }) {
        Circle({ width: compact ? 46 : 58, height: compact ? 46 : 58 }).fill('#18E64646');
        SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
          .fontSize(compact ? 23 : 28)
          .fontColor(['#E64646']);
      }
      Text(compact ? $r('app.string.gs_message_search_failed') : $r('app.string.search_failed'))
        .fontSize(compact ? 15 : 17)
        .fontWeight(FontWeight.Medium)
        .fontColor(COLOR_TEXT_PRIMARY);
      Text(this.messageError !== '' ? this.messageError : $r('app.string.ct_service_unavailable'))
        .fontSize(13)
        .fontColor(COLOR_TEXT_SECONDARY);
      Row({ space: 6 }) {
        SymbolGlyph($r('sys.symbol.arrow_clockwise'))
          .fontSize(15)
          .fontColor([COLOR_PRIMARY]);
        Text($r('app.string.gs_search_again'))
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(COLOR_PRIMARY);
      }
      .height(38)
      .padding({ left: 16, right: 16 })
      .margin({ top: 3 })
      .borderRadius(19)
      .stateStyles({
        normal: this.retryActionNormalStyle,
        pressed: this.retryActionPressedStyle
      })
      .accessibilityText($r('app.string.gs_search_again'))
      .onClick((): void => { this.retryMessageSearch(); });
    }
    .layoutWeight(compact ? 0 : 1)
    .width('100%')
    .height(compact ? 166 : '100%')
    .margin({
      top: compact ? 0 : 12,
      bottom: compact ? 0 : 12
    })
    .justifyContent(FlexAlign.Center)
    .backgroundColor(mainCardFill(this.appWallpaperOn, false))
    .borderRadius(compact ? 0 : 20)
    .transition(TransitionEffect.OPACITY
      .combine(TransitionEffect.translate({ y: 3 }))
      .animation({
        duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 180),
        curve: Curve.EaseOut
      }));
  }

  @Builder
  paginationFooter() {
    if (this.pagingBusy) {
      Row({ space: 8 }) {
        LoadingProgress().width(20).height(20).color(COLOR_PRIMARY);
        Text($r('app.string.cpp_loading_more'))
          .fontSize(13)
          .fontColor(COLOR_TEXT_SECONDARY);
      }
      .width('100%')
      .height(54)
      .justifyContent(FlexAlign.Center)
      .accessibilityText($r('app.string.gs_loading_more_results'))
      .transition(TransitionEffect.OPACITY
        .combine(TransitionEffect.translate({ y: 4 }))
        .animation({
          duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 150),
          curve: Curve.EaseOut
        }));
    } else if (this.pagingError) {
      Row({ space: 9 }) {
        SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
          .fontSize(17)
          .fontColor(['#E64646']);
        Text($r('app.string.gs_load_more_failed'))
          .fontSize(13)
          .fontColor(COLOR_TEXT_SECONDARY);
        Row({ space: 4 }) {
          SymbolGlyph($r('sys.symbol.arrow_clockwise'))
            .fontSize(13)
            .fontColor([COLOR_PRIMARY]);
          Text($r('app.string.settings_retry'))
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor(COLOR_PRIMARY);
        }
        .height(32)
        .padding({ left: 11, right: 11 })
        .borderRadius(16)
        .stateStyles({
          normal: this.retryActionNormalStyle,
          pressed: this.retryActionPressedStyle
        })
        .accessibilityText($r('app.string.gs_retry_more'))
        .onClick((): void => { this.retryPaging(); });
      }
      .width('100%')
      .height(58)
      .justifyContent(FlexAlign.Center)
      .transition(TransitionEffect.OPACITY
        .combine(TransitionEffect.translate({ y: 4 }))
        .animation({
          duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 160),
          curve: Curve.EaseOut
        }));
    } else if (this.loadedPageCount > 1 && this.nextOffset === '') {
      Text($r('app.string.gs_all_results'))
        .width('100%')
        .height(48)
        .fontSize(12)
        .fontColor(COLOR_TEXT_SECONDARY)
        .textAlign(TextAlign.Center)
        .transition(TransitionEffect.OPACITY.animation({
          duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 150),
          curve: Curve.EaseOut
        }));
    }
  }

  @Builder
  chatSearchInlineState() {
    if (this.chatSearching || this.searchPending || this.chatResults.some((r: SearchRow): boolean => r.title === '')) {
      Row({ space: 8 }) {
        LoadingProgress().width(19).height(19).color(COLOR_PRIMARY);
        Text(this.tab === TAB_MESSAGES ? $r('app.string.gs_searching_channels') : $r('app.string.gs_searching_chats'))
          .fontSize(13)
          .fontColor(COLOR_TEXT_SECONDARY);
      }
      .width('100%')
      .height(48)
      .justifyContent(FlexAlign.Center);
    } else if (this.chatSearchFailed) {
      Row({ space: 8 }) {
        SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
          .fontSize(17)
          .fontColor(['#E64646']);
        Text(this.tab === TAB_MESSAGES ? $r('app.string.gs_channel_search_failed') : $r('app.string.gs_chat_search_failed'))
          .fontSize(13)
          .fontColor(COLOR_TEXT_SECONDARY);
        Row() {
          Text($r('app.string.settings_retry'))
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor(COLOR_PRIMARY);
        }
        .height(32)
        .padding({ left: 12, right: 12 })
        .borderRadius(16)
        .stateStyles({
          normal: this.retryActionNormalStyle,
          pressed: this.retryActionPressedStyle
        })
        .onClick((): void => { this.retryChatSearch(); });
      }
      .width('100%')
      .height(52)
      .justifyContent(FlexAlign.Center);
    }
  }

  @Builder
  appSearchInlineState() {
    if (!this.appsLoaded || this.apps.some((row: SearchRow) => row.title === '')) {
      Row({ space: 8 }) {
        LoadingProgress().width(19).height(19).color(COLOR_PRIMARY);
        Text($r('app.string.gs_searching_apps'))
          .fontSize(13)
          .fontColor(COLOR_TEXT_SECONDARY);
      }
      .width('100%')
      .height(48)
      .justifyContent(FlexAlign.Center);
    } else if (this.appsFailed) {
      Row({ space: 8 }) {
        SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
          .fontSize(17)
          .fontColor(['#E64646']);
        Text($r('app.string.gs_apps_failed'))
          .fontSize(13)
          .fontColor(COLOR_TEXT_SECONDARY);
        Row() {
          Text($r('app.string.settings_retry'))
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor(COLOR_PRIMARY);
        }
        .height(32)
        .padding({ left: 12, right: 12 })
        .borderRadius(16)
        .stateStyles({
          normal: this.retryActionNormalStyle,
          pressed: this.retryActionPressedStyle
        })
        .onClick((): void => { this.retryApps(); });
      }
      .width('100%')
      .height(52)
      .justifyContent(FlexAlign.Center);
    }
  }

  // 聊天/频道 tabs: name-search results (频道 keeps only channels).
  @Builder
  chatResultsList() {
    if (this.chatSearching && this.chatResults.length === 0) {
      Column() {
        LoadingProgress().width(36).height(36).color(COLOR_ICON_SECONDARY);
      }.layoutWeight(1).width('100%').justifyContent(FlexAlign.Center);
    } else if (this.filteredChatResults().length === 0) {
      Column() {
        Text(this.tab === TAB_MESSAGES ? $r('app.string.gs_no_channels') : $r('app.string.gs_no_chats'))
          .fontSize(14).fontColor(COLOR_TEXT_SECONDARY);
      }.layoutWeight(1).width('100%').justifyContent(FlexAlign.Center);
    } else {
      List() {
        ForEach(this.filteredChatResults(),
          (r: SearchRow, idx: number) => {
            ListItem() {
              this.chatRow(r, idx > 0);
            }.backgroundColor(mainCardFill(this.appWallpaperOn, false));
          }, (r: SearchRow) => `res_${r.chatId}_${r.title}_${r.subtitle}_${r.avatarPath}`);
      }
      .layoutWeight(1)
      .width('100%')
      .margin({ top: 12, bottom: 12 })
    .backgroundColor(mainCardFill(this.appWallpaperOn, false))
      .borderRadius(20)
      .clip(true);
    }
  }

  // 媒体 tab: 3-column photo/video thumbnail grid.
  @Builder
  mediaGrid() {
    if (this.messageError !== '') {
      this.messageErrorState(false);
    } else if (this.loading || (this.resolvingMessageRows() && this.visibleItems().length === 0)) {
      this.messageLoadingState(false);
    } else if (this.visibleItems().length === 0 && this.searchedOnce && this.searchExhausted()) {
      Column() {
        Text($r('app.string.gs_no_media')).fontSize(14).fontColor(COLOR_TEXT_SECONDARY);
      }
      .layoutWeight(1)
      .width('100%')
      .margin({ top: 12, bottom: 12 })
      .justifyContent(FlexAlign.Center)
      .backgroundColor(mainCardFill(this.appWallpaperOn, false))
      .borderRadius(20);
    } else {
      Grid() {
        // LazyForEach + 复用格（SearchMediaCell）：翻页结果不设上限，原来 ForEach 一次全建。
        // 点击和无障碍文本挂在 GridItem 上，闭包随格 key 重建。
        LazyForEach(this.mediaItemsData, (it: FoundItem) => {
          GridItem() {
            SearchMediaCell({
              thumbPath: it.thumbPath, isVideo: it.isVideo, duration: it.duration,
              wallpaperOn: this.appWallpaperOn
            });
          }
          .accessibilityText(str('gs_media_a11y', it.isVideo ? str('storage_video') : str('storage_photo'), it.chatTitle))
          .onClick(() => { this.openResult(it); });
        }, (it: FoundItem, index: number): string =>
          guardKey(this.mediaItemsData.keyTableId, index, mediaItemKey(it)));
        if (this.pagingBusy || this.pagingError ||
          (this.loadedPageCount > 1 && this.nextOffset === '')) {
          GridItem() {
            this.paginationFooter();
          }
          .columnStart(0)
          .columnEnd(2);
        }
      }
      .columnsTemplate('1fr 1fr 1fr')
      .columnsGap(2).rowsGap(2)
      .cachedCount(2)
      .layoutWeight(1)
      .width('100%')
      .margin({ top: 12, bottom: 12 })
      .backgroundColor(mainCardFill(this.appWallpaperOn, false))
      .borderRadius(20)
      .clip(true)
      .onReachEnd(() => {
        if (this.nextOffset !== '' && !this.loading && !this.pagingError) {
          this.searchMessages(this.nextOffset);
        }
      });
    }
  }

  // 聊天/频道/应用 with a typed query: matched objects on top, hashtag public
  // posts (for #tags) above them, and a 消息 message-results section below —
  // Telegram's combined layout.
  // 整张卡是一个 List：标题、内联状态、翻页脚各占一项；会话名结果和消息结果各是
  // ListItemGroup + LazyForEach + 复用行，消息那段翻页不设上限，原来是 Scroll 里的
  // ForEach 一次全建。分隔线交给组的 divider（理由同 channelsLanding）。
  @Builder
  combinedResults() {
    List() {
      if (this.visibleHashtagPosts().length > 0) {
        ListItem() {
          Row() {
            Text($r('app.string.gs_public_posts')).fontSize(14).fontWeight(FontWeight.Medium).fontColor(COLOR_TEXT_SECONDARY)
              .layoutWeight(1);
            Text($r('app.string.gs_show_more')).fontSize(14).fontColor(COLOR_PRIMARY)
              .onClick(() => {
                // Hashtag results expand into the official 帖子 category.
                this.onTabSelected(TAB_POSTS);
              });
          }.width('100%').padding({ left: 16, right: 16, top: 10, bottom: 6 });
        }
        ListItemGroup() {
          // 最多三条，ForEach 就够了。
          ForEach(this.visibleHashtagPosts().slice(0, 3), (it: FoundItem) => {
            ListItem() {
              SearchMessageRow({
                chatId: it.chatId, chatTitle: it.chatTitle, avatarPath: it.avatarPath, initials: it.initials,
                match: it.match, query: this.query, preview: it.preview, timeLabel: formatTime(it.date, this.nowSec),
                opening: this.resultOpeningKey === `message:${it.chatId}:${it.messageId}`,
                wallpaperOn: this.appWallpaperOn
              });
            }
            .accessibilityText(`${it.chatTitle}，${it.preview}`)
            .onClick(() => { this.openResult(it); });
          }, (it: FoundItem) =>
            `ht_${it.chatId}_${it.messageId}_${it.chatTitle}_${it.avatarPath}`);
        }
        .divider({ strokeWidth: 0.7, color: $r('app.color.divider'), startMargin: SEARCH_RESULT_DIVIDER_INSET });
      }
      if (this.tab === TAB_APPS) {
        if (this.filteredAppResults().length > 0) {
          ListItem() {
            this.sectionHeader(str('gs_apps'));
          }
        }
        ListItemGroup() {
          LazyForEach(this.combinedAppsData, (r: SearchRow) => {
            ListItem() {
              SearchAppRow({
                query: this.query, identity: r.identity, userId: r.userId, title: r.title, subtitle: r.subtitle, avatarPath: r.avatarPath,
                initials: r.initials, opening: this.resultOpeningKey === `app:${r.userId}`,
                wallpaperOn: this.appWallpaperOn
              });
            }
            .accessibilityText(str('gs_open_a11y', r.title, r.subtitle !== '' ? str('gs_comma') + r.subtitle : ''))
            .onClick(() => { this.openApp(r.userId); });
          }, (r: SearchRow, index: number): string =>
            guardKey(this.combinedAppsData.keyTableId, index, appRowKey(r)));
        }
        .divider({ strokeWidth: 0.7, color: $r('app.color.divider'), startMargin: SEARCH_RESULT_DIVIDER_INSET })
        .backgroundColor(mainCardFill(this.appWallpaperOn, false));
        if (this.filteredAppResults().length === 0 &&
          (!this.appsLoaded || this.appsFailed ||
            this.apps.some((row: SearchRow) => row.title === ''))) {
          ListItem() {
            this.appSearchInlineState();
          }
        }
      } else {
        if (this.filteredChatResults().length > 0) {
          ListItem() {
            this.sectionHeader(this.tab === TAB_MESSAGES ? str('gn_channel') : str('gs_chats_and_contacts'));
          }
        }
        ListItemGroup() {
          LazyForEach(this.combinedChatsData, (r: SearchRow) => {
            ListItem() {
              SearchChatRow({
                query: this.query,
                chatId: r.chatId, title: r.title, subtitle: r.subtitle, avatarPath: r.avatarPath,
                initials: r.initials, savedMessages: this.isSavedMessagesChat(r.chatId),
                opening: this.resultOpeningKey === `chat:${r.chatId}`, wallpaperOn: this.appWallpaperOn
              });
            }
            .accessibilityText(`${r.title}${r.subtitle !== '' ? '，' + r.subtitle : ''}`)
            .onClick(() => { this.openChat(r.chatId); });
          }, (r: SearchRow, index: number): string =>
            guardKey(this.combinedChatsData.keyTableId, index, searchRowKey(r)));
        }
        .divider({ strokeWidth: 0.7, color: $r('app.color.divider'), startMargin: SEARCH_RESULT_DIVIDER_INSET })
        .backgroundColor(mainCardFill(this.appWallpaperOn, false));
        if (this.filteredChatResults().length === 0 &&
          (this.chatSearching || this.chatSearchFailed)) {
          ListItem() {
            this.chatSearchInlineState();
          }
        }
      }
      ListItem() {
        this.sectionHeader(str('cps_messages'));
      }
      if (this.messageError !== '') {
        ListItem() {
          this.messageErrorState(true);
        }
      } else if ((this.loading || this.resolvingMessageRows()) && this.visibleItems().length === 0) {
        ListItem() {
          this.messageLoadingState(true);
        }
      } else {
        ListItemGroup() {
          LazyForEach(this.combinedMessagesData, (it: FoundItem) => {
            ListItem() {
              SearchMessageRow({
                chatId: it.chatId, chatTitle: it.chatTitle, avatarPath: it.avatarPath, initials: it.initials,
                match: it.match, query: this.query, preview: it.preview, timeLabel: formatTime(it.date, this.nowSec),
                opening: this.resultOpeningKey === `message:${it.chatId}:${it.messageId}`,
                wallpaperOn: this.appWallpaperOn
              });
            }
            .accessibilityText(`${it.chatTitle}，${it.preview}`)
            .onClick(() => { this.openResult(it); });
          }, (it: FoundItem, index: number): string =>
            guardKey(this.combinedMessagesData.keyTableId, index, foundItemKey(it)));
        }
        .divider({ strokeWidth: 0.7, color: $r('app.color.divider'), startMargin: SEARCH_RESULT_DIVIDER_INSET });
        if (this.visibleItems().length === 0 && this.searchedOnce && this.searchExhausted()) {
          ListItem() {
            Text($r('app.string.cp_no_messages_found')).fontSize(14).fontColor(COLOR_TEXT_SECONDARY)
              .width('100%').textAlign(TextAlign.Center).padding(16);
          }
        }
        if (this.pagingBusy || this.pagingError ||
          (this.loadedPageCount > 1 && this.nextOffset === '')) {
          ListItem() {
            this.paginationFooter();
          }
        }
      }
    }
    .layoutWeight(1)
    .width('100%')
    .margin({ top: 12, bottom: 12 })
    .edgeEffect(EdgeEffect.Spring)
    .scrollBar(BarState.Off)
    .backgroundColor(mainCardFill(this.appWallpaperOn, false))
    .borderRadius(20)
    .clip(true)
    .cachedCount(4)
    .onReachEnd(() => {
      if (this.nextOffset !== '' && !this.loading && !this.pagingError) {
        this.searchMessages(this.nextOffset);
      }
    });
  }

  // 帖子 tab prompt: explicit search button (each run burns server quota).
  @Builder
  postsPrompt() {
    Column({ space: 10 }) {
      Text($r('app.string.cl_global_search')).fontSize(17).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT_PRIMARY);
      Text($r('app.string.gs_search_public_hint'))
        .fontSize(14).fontColor(COLOR_TEXT_SECONDARY);
      if (this.query.trim() !== '') {
        Row({ space: 6 }) {
          SymbolGlyph($r('sys.symbol.magnifyingglass')).fontSize(16).fontColor([COLOR_ON_PRIMARY]);
          Text(str('gs_search_for', this.query.trim()))
            .fontSize(16).fontWeight(FontWeight.Medium).fontColor(COLOR_ON_PRIMARY)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            .constraintSize({ maxWidth: 200 });
          SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(14).fontColor([COLOR_ON_PRIMARY]);
        }
        .backgroundColor(COLOR_PRIMARY).borderRadius(24)
        .padding({ left: 22, right: 22, top: 12, bottom: 12 })
        .margin({ top: 6 })
        .onClick(() => { this.searchMessages(''); });
      }
      if (this.postsQuota !== '') {
        Text(this.postsQuota).fontSize(13).fontColor(COLOR_TEXT_SECONDARY);
      }
    }
    .layoutWeight(1).width('100%').justifyContent(FlexAlign.Center);
  }

  @Builder
  messageResults() {
    if (this.messageError !== '') {
      this.messageErrorState(false);
    } else if (this.loading || (this.resolvingMessageRows() && this.visibleItems().length === 0)) {
      this.messageLoadingState(false);
    } else if (this.emptyPageAction() === SEARCH_PAGE_FETCH || this.emptyPageAction() === SEARCH_PAGE_MORE) {
      Column({ space: 12 }) {
        Text($r('app.string.gs_finding_messages')).fontSize(14).fontColor(COLOR_TEXT_SECONDARY);
        Button($r('app.string.gs_show_more')).onClick((): void => { this.continueEmptySearch(); });
      }.layoutWeight(1).width('100%').justifyContent(FlexAlign.Center).padding(24);
    } else if (this.visibleItems().length === 0 && this.searchedOnce && this.searchExhausted()) {
      Column() {
        Text(this.tab === TAB_LINKS ? $r('app.string.gs_no_links')
          : (this.tab === TAB_FILES ? $r('app.string.gs_no_files')
            : (this.tab === TAB_AUDIO ? $r('app.string.gs_no_music')
              : (this.tab === TAB_VOICE ? $r('app.string.gs_no_voice') : $r('app.string.cp_no_messages_found')))))
          .fontSize(14).fontColor(COLOR_TEXT_SECONDARY);
      }
      .layoutWeight(1)
      .width('100%')
      .margin({ top: 12, bottom: 12 })
      .justifyContent(FlexAlign.Center)
      .backgroundColor(mainCardFill(this.appWallpaperOn, false))
      .borderRadius(20);
    } else {
      List() {
        // LazyForEach + 复用行（SearchMessageRow）：翻页结果不设上限，原来 ForEach 一次全建。
        LazyForEach(this.messageItemsData, (it: FoundItem) => {
          ListItem() {
            SearchMessageRow({
              chatId: it.chatId, chatTitle: it.chatTitle, avatarPath: it.avatarPath, initials: it.initials,
              match: it.match, query: this.query, preview: it.preview, timeLabel: formatTime(it.date, this.nowSec),
              opening: this.resultOpeningKey === `message:${it.chatId}:${it.messageId}`,
              wallpaperOn: this.appWallpaperOn
            });
          }
          .accessibilityText(`${it.chatTitle}，${it.preview}`)
          .onClick(() => { this.openResult(it); });
        }, (it: FoundItem, index: number): string =>
          guardKey(this.messageItemsData.keyTableId, index, foundItemKey(it) + this.query + JSON.stringify(it.match)));
        if (this.pagingBusy || this.pagingError ||
          (this.loadedPageCount > 1 && this.nextOffset === '')) {
          ListItem() {
            this.paginationFooter();
          }
        }
      }
      .layoutWeight(1)
      .width('100%')
      .margin({ top: 12, bottom: 12 })
      .backgroundColor(mainCardFill(this.appWallpaperOn, false))
      .borderRadius(20)
      .clip(true)
      .cachedCount(4)
      .divider({
        strokeWidth: 0.7,
        color: $r('app.color.divider'),
        startMargin: SEARCH_RESULT_DIVIDER_INSET,
        endMargin: 0
      })
      // Prefetch the next page a few rows before the bottom (no tap needed).
      .onScrollIndex((_start: number, end: number) => {
        if (this.visibleItems().length > 0 && this.nextOffset !== '' && !this.loading && !this.pagingError &&
          end >= this.items.length - 5) {
          this.searchMessages(this.nextOffset);
        }
      });
    }
  }

  // Read reactive state here: a value parameter captures the tab from the first render.
  @Builder
  tabBody() {
    if (this.tab === SEARCH_TAB_RECENT) {
      this.landing();
    } else if (this.query.trim() === '' && this.tab !== TAB_APPS && this.tab !== TAB_DOWNLOADS && this.tab !== TAB_POSTS) {
      Column() {
        Text($r('app.string.gs_empty_hint')).fontSize(14).fontColor(COLOR_TEXT_SECONDARY);
      }.layoutWeight(1).width('100%').justifyContent(FlexAlign.Center).padding(24);
    } else if (this.tab === TAB_DOWNLOADS) {
      Column({ space: 14 }) {
        Text($r('app.string.gs_download_scope')).fontColor(COLOR_TEXT_SECONDARY).fontSize(14);
        Button($r('app.string.dc_title')).onClick((): void => {
          this.navStack?.pushPathByName('DownloadCenterPage', { 'query': this.query } as Record<string, Object>);
        });
      }.layoutWeight(1).justifyContent(FlexAlign.Center).padding(24);
    } else if (this.tab === TAB_APPS) {
      this.appsList();
    } else if (this.tab === TAB_MEDIA) {
      if (this.query.trim() === '') { this.mediaGrid(); } else { this.messageResults(); }
    } else if (filterTypeForTab(this.tab) !== '') {
      this.messageResults();
    } else if (this.tab === TAB_POSTS) {
      if (this.loading || this.searchedOnce) { this.messageResults(); } else { this.postsPrompt(); }
    } else if (this.tab === TAB_MESSAGES) {
      this.messageResults();
    } else {
      this.nameResults();
    }
  }

  @Builder
  nameGroup(publicResults: boolean) {
    ListItemGroup() {
      ListItem() { this.sectionHeader(str(publicResults ? 'gs_public_names' : 'gs_existing_chats')); }
      LazyForEach(publicResults ? this.publicNamesData : this.localNamesData, (row: SearchRow) => {
        ListItem() {
          SearchChatRow({ chatId: row.chatId, title: row.title, subtitle: row.subtitle,
            avatarPath: row.avatarPath, initials: row.initials, query: this.query, identity: row.identity,
            wallpaperOn: this.appWallpaperOn, savedMessages: this.isSavedMessagesChat(row.chatId) });
        }.onClick((): void => this.openChat(row.chatId));
      }, (row: SearchRow): string => searchRowKey(row) + this.query + JSON.stringify(row.identity));
    }
  }

  @Builder
  nameResults() {
    List() {
      if (this.filteredChatResults().some((r: SearchRow): boolean => r.identity?.existing === true)) { this.nameGroup(false); }
      if (this.filteredChatResults().some((r: SearchRow): boolean => r.identity?.existing !== true)) { this.nameGroup(true); }
      if (this.chatSearching || this.searchPending || this.chatSearchFailed || this.chatResults.some((r: SearchRow): boolean => r.title === '')) {
        ListItem() { this.chatSearchInlineState(); }
      }
      if (!this.chatSearching && !this.searchPending && !this.chatSearchFailed &&
        !this.chatResults.some((r: SearchRow): boolean => r.title === '') && this.filteredChatResults().length === 0) {
        ListItem() { Text($r('app.string.gs_no_chats')).padding(24).fontColor(COLOR_TEXT_SECONDARY); }
      }
      ListItem() { Text($r('app.string.gs_public_name_limit')).fontSize(12).fontColor(COLOR_TEXT_SECONDARY).padding(20); }
    }.layoutWeight(1).width('100%').cachedCount(4);
  }

  private chooseScope(scope: string): void {
    if (this.tab === TAB_CHATS) { this.objectScope = scope; this.syncChatResultsData(); this.runSearch(); }
    else {
      this.messageScope = scope;
      if (scope !== 'channel') { this.channelId = 0; this.channelTitle = ''; }
      this.runSearch();
    }
  }

  @Builder
  channelPicker() {
    SearchChannelPicker({ onPick: (id: number, title: string): void => {
      this.channelId = id; this.channelTitle = title; this.messageScope = 'channel';
      this.channelPickerOpen = false; this.runSearch();
    } });
  }

  @Builder
  scopeControls() {
    if (this.tab === TAB_CHATS || this.tab === TAB_MESSAGES) {
      Column({ space: 8 }) {
        Text(this.tab === TAB_CHATS ? str('gs_name_scope') :
          (this.channelId !== 0 ? str('gs_channel_scope', this.channelTitle) : str('gs_message_scope')))
          .fontSize(12).fontColor(COLOR_TEXT_SECONDARY).width('100%');
        Row({ space: 8 }) {
          ForEach(['all', 'user', 'group', 'channel'], (scope: string) => {
            Button(str(scope === 'all' ? 'gs_scope_all' : scope === 'user' ?
              (this.tab === TAB_MESSAGES ? 'gs_scope_private' : 'gs_scope_user') : scope === 'group' ? 'gn_group' : 'gn_channel'))
              .fontSize(12).height(30)
              .fontColor((this.tab === TAB_CHATS ? this.objectScope : this.messageScope) === scope ? COLOR_PRIMARY : COLOR_TEXT_SECONDARY)
              .backgroundColor((this.tab === TAB_CHATS ? this.objectScope : this.messageScope) === scope ? '#183D8BFF' : Color.Transparent)
              .onClick((): void => this.chooseScope(scope));
          });
        }.width('100%');
        if (this.tab === TAB_MESSAGES && this.messageScope === 'channel') {
          Row({ space: 8 }) {
            Button(this.channelId !== 0 ? this.channelTitle : str('gs_choose_channel'))
              .fontSize(12).height(32).constraintSize({ maxWidth: '80%' })
              .onClick((): void => { this.channelPickerOpen = true; });
            if (this.channelId !== 0) {
              Button('×').height(32).width(32).accessibilityText(str('gs_all_channels'))
                .onClick((): void => { this.channelId = 0; this.channelTitle = ''; this.runSearch(); });
            }
          }.width('100%');
        }
      }.padding({ top: 8 }).width('100%');
    }
  }

  build() {
    NavDestination() {
      this.body();
    }
    .hideTitleBar(true)
    .bindSheet($$this.channelPickerOpen, this.channelPicker(), { height: '80%', dragBar: true })
    .onBackPressed((): boolean => collapseFloatingVideo())
    .onReady((context: NavDestinationContext): void => {
      this.navStack = context.pathStack;
    })
    .width('100%').height('100%')
    .backgroundColor(mainPageFill(this.appWallpaperOn));
  }

  // 搜索框(48) + 页签条(40 + 上间距 8) + 顶部安全区与内边距(10)。
  private headerHeight(): number {
    return this.topSafe + 10 + 48 + 8 + 40;
  }

  @Builder
  body() {
    Stack({ alignContent: Alignment.TopStart }) {
    // NavDestination 自带的页面层会隔断 MainScreen 的壁纸，和资料详情页一样在
    // 当前目的页内重画一层；分栏时 AppBackdrop 会按统一规则自动停止绘制。
    AppBackdrop({ split: isSplitByBreakpoint(this.widthBp, this.heightBp, this.forceSingleColumn, this.windowPortrait) });
    // 内容层：铺满整页、从 y=0 起，「最近」页的列表会从悬浮搜索栏底下穿过。
    Column() {
      Column() {
        this.tabBody();
      }
      .width('100%')
      .layoutWeight(1)
      .constraintSize({ maxWidth: readableContentWidth(this.screenW) })
      // 「最近」页的 List 用 contentStartOffset 自己让位；其余页签的列表还没逐一套
      // 偏移，先整体下移，避免内容被悬浮栏压住。
      .padding({
        left: SEARCH_PAGE_INSET, right: SEARCH_PAGE_INSET,
        top: this.tab === SEARCH_TAB_RECENT ? 0 : this.headerHeight()
      });
    }
    .width('100%').height('100%')
    .alignItems(HorizontalAlign.Center)
    .backgroundColor(mainPageFill(this.appWallpaperOn))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM]);

    // 悬浮搜索栏 + 页签：玻璃底压最上层，滚上来的内容在它后面雾化。
    Column() {
      Column() {
        this.searchBar();
        // Rebuild the strip only when Recent enters/leaves, resetting its scroll to the selected tab.
        if (this.query.trim() === '') {
          this.searchCategoryTabs(true);
        } else {
          this.searchCategoryTabs(false);
          this.scopeControls();
        }
      }
      .width('100%')
      .constraintSize({ maxWidth: readableContentWidth(this.screenW) })
      .padding({ left: SEARCH_PAGE_INSET, right: SEARCH_PAGE_INSET, top: this.topSafe + 10 });
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
    .backgroundColor(plainGlassFill($r('app.color.surface')))
    .backdropBlur(plainBackdropBlur('bar'))
    .hitTestBehavior(HitTestMode.Transparent);

    }
    .width('100%').height('100%')
    .backgroundColor(mainPageFill(this.appWallpaperOn))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM]);
  }
}
