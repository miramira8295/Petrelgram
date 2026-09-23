import {
  HEIGHT_BP_LG, KEY_HEIGHT_BREAKPOINT, KEY_WIDTH_BREAKPOINT, WIDTH_BP_SM, isSplitByBreakpoint
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
  COLOR_TAB_SELECTED,
  COLOR_TAB_UNSELECTED,
  COLOR_TAB_PILL_BG,
  mainCardFill, mainPageFill, COLOR_ON_PRIMARY
} from '../../util/theme';
import {
  KEY_APP_BG_ON, KEY_POWER_SMOOTH_TRANSITIONS, powerAnimationDuration, KEY_FORCE_SINGLE_COLUMN
} from '../../store/AppSettings';
import { plural, str } from '../../util/strings';
import { LANGUAGE_EPOCH } from '../../util/appLanguage';
import { overlayMaterial, MATERIAL_EPOCH } from '../../util/overlayMaterial';
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
const TABS: string[] = [str('tab_chats'), str('gn_channel'), str('gs_apps'), str('gs_posts'), str('cpp_media'), str('cpp_links'), str('storage_file'), str('storage_audio'), str('storage_voice')];
const TAB_CHATS: number = 0;
const TAB_CHANNELS: number = 1;
const TAB_APPS: number = 2;
const TAB_POSTS: number = 3;
const TAB_MEDIA: number = 4;
// 原来的「下载」页签（下标 5）搬去了「设置 › 下载中心」（2026-09-15），后面几个依次前移。
const TAB_LINKS: number = 5;
const TAB_FILES: number = 6;
const TAB_AUDIO: number = 7;
const TAB_VOICE: number = 8;
const SEARCH_TAB_BAR_HEIGHT: number = 44;
const SEARCH_TAB_INDICATOR_HEIGHT: number = 32;
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
// messages ("帖子") globally.
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
  // 下载列表和应用榜按 query 过滤，query 变了要同步它们的数据源（见 syncQueryFilteredData）。
  @State @Watch('syncQueryFilteredData') query: string = '';
  @State @Watch('syncTabFilteredData') tab: number = 0;
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
  private failedPagingOffset: string = '';
  private autoPages: number = 0; // consecutive auto-fetched pages that rendered nothing
  private debounceTimer: number = -1;
  private searchHeaderTimer: number = -1;
  private closeSearchTimer: number = -1;
  private hashtagSearchSeq: number = 0;
  private postsQuotaSeq: number = 0;
  private resultOpeningTimer: number = -1;
  private clearRecentDialogOpen: boolean = false;
  private store: GlobalSearchStore | null = null;
  private unsub: (() => void) | null = null;
  // Sliding selection pill (same pattern as the chat-list tab bar): frames are
  // recorded per pill; the pill interpolates during content swipes.
  @State indicatorX: number = 8;
  @State indicatorW: number = 0;
  private tabXs: number[] = [];
  private tabWs: number[] = [];
  private tabsWidth: number = 0;
  private tabViewW: number = 0;
  private tabScroller: Scroller = new Scroller();
  private controller: TabsController = new TabsController();
  // 结果列表的 LazyForEach 数据源（见 syncXxxData）。Tabs 里各 tab 的容器同时活着，同一份
  // 数据被两个容器用到时各开一个：key 格式不同，诊断 key 表（util/keyGuard）不能共用。
  private joinedChannelsData: KeyedListDataSource<SearchRow> = new KeyedListDataSource<SearchRow>('gs-joined');
  private similarChannelsData: KeyedListDataSource<SearchRow> = new KeyedListDataSource<SearchRow>('gs-similar');
  private combinedChatsData: KeyedListDataSource<SearchRow> = new KeyedListDataSource<SearchRow>('gs-chats');
  private messageItemsData: KeyedListDataSource<FoundItem> = new KeyedListDataSource<FoundItem>('gs-messages');
  private combinedMessagesData: KeyedListDataSource<FoundItem> = new KeyedListDataSource<FoundItem>('gs-combined-messages');
  private mediaItemsData: KeyedListDataSource<FoundItem> = new KeyedListDataSource<FoundItem>('gs-media');
  private topUsersData: KeyedListDataSource<SearchRow> = new KeyedListDataSource<SearchRow>('gs-top');
  private recentData: KeyedListDataSource<SearchRow> = new KeyedListDataSource<SearchRow>('gs-recent');
  private recentlyOpenedData: KeyedListDataSource<SearchRow> = new KeyedListDataSource<SearchRow>('gs-opened');
  private appsData: KeyedListDataSource<SearchRow> = new KeyedListDataSource<SearchRow>('gs-apps');
  private combinedAppsData: KeyedListDataSource<SearchRow> = new KeyedListDataSource<SearchRow>('gs-combined-apps');

  @Styles
  tabNormalStyle() {
    .opacity(1)
  }

  @Styles
  tabPressedStyle() {
    .opacity(0.62)
  }

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

  private moveIndicatorTo(pos: number): void {
    const n = TABS.length;
    if (this.tabWs.length === 0) {
      return;
    }
    const p = Math.max(0, Math.min(n - 1, pos));
    const i0 = Math.floor(p);
    const i1 = Math.min(n - 1, i0 + 1);
    const f = p - i0;
    const x0 = this.tabXs[i0] ?? 8;
    const x1 = this.tabXs[i1] ?? x0;
    const w0 = this.tabWs[i0] ?? 0;
    const w1 = this.tabWs[i1] ?? w0;
    this.indicatorX = x0 + (x1 - x0) * f;
    this.indicatorW = w0 + (w1 - w0) * f;
  }

  private ensureTabVisible(index: number): void {
    const x = this.tabXs[index] ?? 0;
    const w = this.tabWs[index] ?? 0;
    if (w === 0 || this.tabViewW === 0) {
      return;
    }
    const off = this.tabScroller.currentOffset().xOffset;
    let target = -1;
    if (x < off + 8) {
      target = Math.max(0, x - 8);
    } else if (x + w > off + this.tabViewW - 8) {
      target = x + w - this.tabViewW + 8;
    }
    if (target >= 0) {
      this.tabScroller.scrollTo({
        xOffset: target,
        yOffset: 0,
        animation: {
          duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 200),
          curve: Curve.EaseOut
        }
      });
    }
  }

  // Tab became current (tap or settled swipe): update state, settle the pill,
  // keep it visible, and fire the tab's data loads.
  private onTabSelected(index: number): void {
    if (this.debounceTimer !== -1) {
      clearTimeout(this.debounceTimer);
      this.debounceTimer = -1;
    }
    this.searchPending = false;
    this.tab = index;
    this.hashtagSearchSeq++;
    this.postsQuotaSeq++;
    animateTo({
      duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 200), curve: Curve.EaseOut
    }, () => { this.moveIndicatorTo(index); });
    this.ensureTabVisible(index);
    this.runSearch();
  }

  aboutToAppear(): void {
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
      this.topUsers = store.topUsers;
      this.recent = store.recent;
      this.recentlyOpened = store.recentlyOpened;
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
      this.tab = restored.tab;
      this.runSearch();
    }
  }

  aboutToDisappear(): void {
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
    this.closingSearch = false;
    this.searchHeaderVisible = false;
    if (this.unsub !== null) { this.unsub(); this.unsub = null; }
    if (this.store !== null) { this.store.close(); this.store = null; }
  }

  private onQueryChanged(v: string): void {
    this.query = v;
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
    return str('gs_search_chats');
  }

  private searchBusy(): boolean {
    if (this.searchPending) {
      return true;
    }
    if (this.tab === TAB_CHATS || this.tab === TAB_CHANNELS) {
      return this.chatSearching || this.loading;
    }
    return this.loading;
  }

  // Rows the current tab actually shows: the 频道 tab keeps only messages from
  // channels, so a page of hits can render as nothing at all.
  private visibleItems(): FoundItem[] {
    const resolved = this.items.filter((it: FoundItem) => it.chatTitle !== '');
    return this.tab === TAB_CHANNELS
      ? resolved.filter((it: FoundItem) => it.isChannelChat)
      : resolved;
  }

  private visibleHashtagPosts(): FoundItem[] {
    return this.hashtagPosts.filter((it: FoundItem) => it.chatTitle !== '');
  }

  private resolvingMessageRows(): boolean {
    return this.items.some((it: FoundItem) => it.chatTitle === '');
  }

  // The 频道 filter can discard an entire page of hits, leaving a screen with
  // nothing to scroll — onReachEnd would never fire and the tab would look
  // empty while more pages exist. Pull the next pages ourselves, bounded.
  private maybeAutoPage(): void {
    if (this.tab !== TAB_CHANNELS || this.loading || this.pagingBusy || this.pagingError) {
      return;
    }
    if (this.resolvingMessageRows()) {
      return;
    }
    if (this.visibleItems().length > 0 || this.nextOffset === '' || this.autoPages >= MAX_AUTO_PAGES) {
      return;
    }
    this.autoPages += 1;
    this.searchMessages(this.nextOffset);
  }

  // True once paging has stopped for good — only then may the tab claim there
  // is nothing to show (a hit whose chat type is still resolving isn't a miss).
  private searchExhausted(): boolean {
    if (this.loading || this.pagingBusy || this.pagingError || this.messageError !== '') {
      return false;
    }
    if (this.items.some((it: FoundItem) => it.chatTitle === '')) {
      return false;
    }
    return this.tab !== TAB_CHANNELS || this.nextOffset === '' || this.autoPages >= MAX_AUTO_PAGES;
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
      this.store.searchChats(this.query);
    }
  }

  private runSearch(): void {
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
    } else if (this.isFilterTab()) {
      this.searchMessages('');
    } else {
      // 聊天/频道/应用: matched objects on top + a 消息 section below.
      if (this.tab !== TAB_APPS && this.store !== null) {
        this.store.searchChats(this.query);
      }
      this.searchMessages('');
      const q = this.query.trim();
      if (q.startsWith('#') && q.length > 1) {
        this.loadHashtagPosts('');
      } else {
        this.hashtagPosts = [];
      }
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
    const req: TdRequest = mode === 'posts' ? { '@type': 'searchPublicPosts' }
      : (mode === 'tagposts' ? { '@type': 'searchPublicMessagesByTag' } : { '@type': 'searchMessages' });
    if (mode === 'filter' || mode === 'all') {
      // **不设 chat_list**（issue #139）：TDLib 省略这一项时搜的是**所有**会话
      // 列表，归档里的消息才搜得到。原来固定 chatListMain，归档会话的内容一条
      // 都出不来，而官方客户端的全局搜索是含归档的。
      if (filterType !== '') {
        req['filter'] = { '@type': filterType } as TdObject;
      }
      if (this.tab === TAB_CHANNELS) {
        // Match Telegram Android: make channel type part of the TDLib message
        // search itself. Fetching all message types and filtering them after
        // pagination loses valid channel hits whenever other chats fill a page.
        req['chat_type_filter'] = {
          '@type': 'searchMessagesChatTypeFilterChannel'
        } as TdObject;
      }
    }
    if (mode === 'tagposts') {
      // The hashtag API wants a tag — prefix bare keywords with '#'.
      req['tag'] = q.startsWith('#') ? q : `#${q}`;
    } else {
      req['query'] = q;
    }
    req['offset'] = offset;
    req['limit'] = 30;
    getTdClient().send(req).then((res: TdObject) => {
      if (seq !== this.seq) {
        return;
      }
      this.pagingBusy = false;
      this.loading = false;
      this.messageError = '';
      this.pagingError = false;
      this.failedPagingOffset = '';
      this.searchedOnce = true;
      const responseOffset = (res['next_offset'] as string | undefined) ?? '';
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
      this.items = this.mergeFoundItems(this.items, fresh, offset === '');
      if (mode === 'posts') {
        this.loadPostsQuota(); // a search just burned one — refresh the count
      }
      // getChat still resolves the title/avatar and defensively verifies the
      // type, while TDLib already limits the 频道 tab to channel messages.
      if (offset === '') {
        this.autoPages = 0;
      }
      this.maybeAutoPage();
    }).catch((e: TdError) => {
      if (seq !== this.seq) {
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
      preview: formatPreview(m),
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
          preview: it.preview, date: it.date,
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
      const type = chat['type'] as TdObject | undefined;
      const isChannel = type !== undefined
        && ((type['@type'] as string | undefined) ?? '') === 'chatTypeSupergroup'
        && (((type as TdObject)['is_channel'] as boolean | undefined) ?? false);
      this.channelFlags.set(chatId, isChannel);
      this.patchItems(chatId, (it: FoundItem): FoundItem => ({
        chatId: it.chatId, messageId: it.messageId, chatTitle: title,
        preview: it.preview, date: it.date,
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
              preview: it.preview, date: it.date,
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
      rememberSearchSession(this.query, this.tab, Date.now());
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

  @Builder
  searchTabPill(title: string, index: number) {
    Row() {
      Text(title)
        .fontSize(14)
        .fontWeight(this.tab === index ? FontWeight.Medium : FontWeight.Normal)
        .fontColor(this.tab === index ? COLOR_TAB_SELECTED : COLOR_TAB_UNSELECTED)
        .maxLines(1);
    }
    .height(SEARCH_TAB_BAR_HEIGHT)
    .padding({ left: 12, right: 12 })
    .margin({ right: 2 })
    .borderRadius(SEARCH_TAB_BAR_HEIGHT / 2)
    .stateStyles({
      normal: this.tabNormalStyle,
      pressed: this.tabPressedStyle
    })
    .onAreaChange((_old: Area, area: Area) => {
      this.tabXs[index] = area.position.x as number;
      this.tabWs[index] = area.width as number;
      if (index === this.tab) {
        this.moveIndicatorTo(index);
      }
    })
    .accessibilityText(this.tab === index ? str('gs_selected_a11y', title) : title)
    .onClick((): void => {
      if (index !== this.tab) {
        this.controller.changeIndex(index);
      }
    });
  }

  @Builder
  tabsBar() {
    Column() {
      Scroll(this.tabScroller) {
        Stack({ alignContent: Alignment.TopStart }) {
          // Match the home folder bar: a fixed-height pill follows horizontal
          // content swipes and settles under the newly selected category.
          Row()
            .width(this.indicatorW)
            .height(SEARCH_TAB_INDICATOR_HEIGHT)
            .borderRadius(SEARCH_TAB_INDICATOR_HEIGHT / 2)
            .backgroundColor(COLOR_TAB_PILL_BG)
            .position({
              x: this.indicatorX,
              y: (SEARCH_TAB_BAR_HEIGHT - SEARCH_TAB_INDICATOR_HEIGHT) / 2
            });
          Row() {
            ForEach(TABS, (title: string, index: number) => {
              this.searchTabPill(title, index);
            }, (title: string) => title);
          }
          .padding({ left: 8, right: 8 })
          .height(SEARCH_TAB_BAR_HEIGHT);
        }
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .align(Alignment.Start)
      .width('100%')
      .onAreaChange((_old: Area, area: Area) => {
        this.tabViewW = area.width as number;
        this.ensureTabVisible(this.tab);
      });
    }
    .backgroundColor(mainCardFill(this.appWallpaperOn, false))
    .borderRadius(SEARCH_TAB_BAR_HEIGHT / 2)
    .clip(true)
    .margin({ top: 6 });
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
    .width('calc(100% - 20vp)')
    .margin({ left: 10, right: 10, top: 8 })
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
          SearchChatRow({
            chatId: r.chatId, title: r.title, subtitle: r.subtitle, avatarPath: r.avatarPath,
            initials: r.initials, savedMessages: this.isSavedMessagesChat(r.chatId),
            opening: this.resultOpeningKey === `chat:${r.chatId}`, wallpaperOn: this.appWallpaperOn
          });
        }
        .accessibilityText(`${r.title}${r.subtitle !== '' ? '，' + r.subtitle : ''}`)
        .onClick(() => { this.openChat(r.chatId); });
      }, (r: SearchRow, index: number): string =>
        guardKey(this.recentData.keyTableId, index, searchRowKey(r)));
    }
    .divider({ strokeWidth: 0.7, color: $r('app.color.divider'), startMargin: SEARCH_RESULT_DIVIDER_INSET })
    .width('calc(100% - 20vp)')
    .margin({ left: 10, right: 10, top: 10, bottom: 10 })
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

  @Builder
  recentlyOpenedHeader() {
    Column() {
      Row({ space: 6 }) {
        SymbolGlyph($r('sys.symbol.clock'))
          .fontSize(16)
          .fontColor([COLOR_ICON_SECONDARY]);
        Text($r('app.string.gs_recent_chats'))
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(COLOR_TEXT_PRIMARY);
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
          SearchChatRow({
            chatId: r.chatId, title: r.title, subtitle: r.subtitle, avatarPath: r.avatarPath,
            initials: r.initials, savedMessages: this.isSavedMessagesChat(r.chatId),
            opening: this.resultOpeningKey === `chat:${r.chatId}`, wallpaperOn: this.appWallpaperOn
          });
        }
        .accessibilityText(`${r.title}${r.subtitle !== '' ? '，' + r.subtitle : ''}`)
        .onClick(() => { this.openChat(r.chatId); });
      }, (r: SearchRow, index: number): string =>
        guardKey(this.recentlyOpenedData.keyTableId, index, searchRowKey(r)));
    }
    .divider({ strokeWidth: 0.7, color: $r('app.color.divider'), startMargin: SEARCH_RESULT_DIVIDER_INSET })
    .width('calc(100% - 20vp)')
    .margin({ left: 10, right: 10, top: 10, bottom: 10 })
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
    .width('calc(100% - 24vp)')
    .height(214)
    .margin({ left: 12, right: 12, top: 12 })
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
    .width('calc(100% - 24vp)')
    .height(220)
    .margin({ left: 12, right: 12, top: 12 })
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
    List() {
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
        if (tab === TAB_CHANNELS) {
          this.retryChannels();
        } else {
          this.retryApps();
        }
      });
    }
    .width('calc(100% - 24vp)')
    .height(214)
    .margin({ left: 12, right: 12, top: 12 })
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
    .width('calc(100% - 24vp)')
    .height(194)
    .margin({ left: 12, right: 12, top: 12 })
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
            this.catalogErrorState(str('gs_channels_failed'), TAB_CHANNELS);
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
        this.sectionHeader(str('gs_popular_apps'));
      }
      ListItemGroup() {
        LazyForEach(this.appsData, (r: SearchRow) => {
          ListItem() {
            SearchAppRow({
              userId: r.userId, title: r.title, subtitle: r.subtitle, avatarPath: r.avatarPath,
              initials: r.initials, opening: this.resultOpeningKey === `app:${r.userId}`,
              wallpaperOn: this.appWallpaperOn
            });
          }
          .accessibilityText(str('gs_open_a11y', r.title, r.subtitle !== '' ? str('gs_comma') + r.subtitle : ''))
          .onClick(() => { this.openApp(r.userId); });
        }, (r: SearchRow, index: number): string =>
          guardKey(this.appsData.keyTableId, index, appRowKey(r)));
      }
      .divider({ strokeWidth: 0.7, color: $r('app.color.divider'), startMargin: SEARCH_RESULT_DIVIDER_INSET })
      .backgroundColor(mainCardFill(this.appWallpaperOn, false));
      if (this.filteredAppResults().length === 0 && this.query.trim() === '') {
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
      row.title !== '' && (this.tab === TAB_CHATS || row.isChannel));
  }

  private filteredAppResults(): SearchRow[] {
    const q = this.query.trim().toLowerCase();
    return this.apps.filter((row: SearchRow) =>
      row.title !== '' && (q === '' || row.title.toLowerCase().includes(q)));
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
    const rows: SearchRow[] = this.filteredChatResults();
    this.combinedChatsData.update(rows,
      rows.map((r: SearchRow): string => searchRowId(r)),
      rows.map((r: SearchRow): string => searchRowKey(r)));
  }

  // 消息结果同样按 tab 过滤（频道 tab 只留频道消息）：items 和 tab 变了都走这里。
  private syncFoundItemsData(): void {
    const rows: FoundItem[] = this.visibleItems();
    const ids: string[] = rows.map((it: FoundItem): string => foundItemId(it));
    const keys: string[] = rows.map((it: FoundItem): string => foundItemKey(it));
    this.messageItemsData.update(rows, ids, keys);
    this.combinedMessagesData.update(rows, ids, keys);
    this.mediaItemsData.update(rows, ids, rows.map((it: FoundItem): string => mediaItemKey(it)));
  }

  private syncTabFilteredData(): void {
    this.syncChatResultsData();
    this.syncFoundItemsData();
  }

  private syncQueryFilteredData(): void {
    this.syncAppsData();
  }

  // 应用榜按 query 过滤：应用 tab 和综合结果各一个容器。
  private syncAppsData(): void {
    const rows: SearchRow[] = this.filteredAppResults();
    const ids: string[] = rows.map((r: SearchRow): string => appRowId(r));
    const keys: string[] = rows.map((r: SearchRow): string => appRowKey(r));
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
    .width(compact ? '100%' : 'calc(100% - 24vp)')
    .height(compact ? 106 : '100%')
    .margin({
      left: compact ? 0 : 12,
      right: compact ? 0 : 12,
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
    .width(compact ? '100%' : 'calc(100% - 24vp)')
    .height(compact ? 166 : '100%')
    .margin({
      left: compact ? 0 : 12,
      right: compact ? 0 : 12,
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
    if (this.chatSearching) {
      Row({ space: 8 }) {
        LoadingProgress().width(19).height(19).color(COLOR_PRIMARY);
        Text(this.tab === TAB_CHANNELS ? $r('app.string.gs_searching_channels') : $r('app.string.gs_searching_chats'))
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
        Text(this.tab === TAB_CHANNELS ? $r('app.string.gs_channel_search_failed') : $r('app.string.gs_chat_search_failed'))
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
        Text(this.tab === TAB_CHANNELS ? $r('app.string.gs_no_channels') : $r('app.string.gs_no_chats'))
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
      .width('calc(100% - 24vp)')
      .margin({ left: 12, right: 12, top: 12, bottom: 12 })
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
      .width('calc(100% - 24vp)')
      .margin({ left: 12, right: 12, top: 12, bottom: 12 })
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
      .width('calc(100% - 24vp)')
      .margin({ left: 12, right: 12, top: 12, bottom: 12 })
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
                this.controller.changeIndex(TAB_POSTS);
              });
          }.width('100%').padding({ left: 16, right: 16, top: 10, bottom: 6 });
        }
        ListItemGroup() {
          // 最多三条，ForEach 就够了。
          ForEach(this.visibleHashtagPosts().slice(0, 3), (it: FoundItem) => {
            ListItem() {
              SearchMessageRow({
                chatId: it.chatId, chatTitle: it.chatTitle, avatarPath: it.avatarPath, initials: it.initials,
                preview: it.preview, timeLabel: formatTime(it.date, this.nowSec),
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
                userId: r.userId, title: r.title, subtitle: r.subtitle, avatarPath: r.avatarPath,
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
            this.sectionHeader(this.tab === TAB_CHANNELS ? str('gn_channel') : str('gs_chats_and_contacts'));
          }
        }
        ListItemGroup() {
          LazyForEach(this.combinedChatsData, (r: SearchRow) => {
            ListItem() {
              SearchChatRow({
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
                preview: it.preview, timeLabel: formatTime(it.date, this.nowSec),
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
    .width('calc(100% - 24vp)')
    .margin({ left: 12, right: 12, top: 12, bottom: 12 })
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
    } else if (this.visibleItems().length === 0 && this.searchedOnce && this.searchExhausted()) {
      Column() {
        Text(this.tab === TAB_LINKS ? $r('app.string.gs_no_links')
          : (this.tab === TAB_FILES ? $r('app.string.gs_no_files')
            : (this.tab === TAB_AUDIO ? $r('app.string.gs_no_music')
              : (this.tab === TAB_VOICE ? $r('app.string.gs_no_voice') : $r('app.string.cp_no_messages_found')))))
          .fontSize(14).fontColor(COLOR_TEXT_SECONDARY);
      }
      .layoutWeight(1)
      .width('calc(100% - 24vp)')
      .margin({ left: 12, right: 12, top: 12, bottom: 12 })
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
              preview: it.preview, timeLabel: formatTime(it.date, this.nowSec),
              opening: this.resultOpeningKey === `message:${it.chatId}:${it.messageId}`,
              wallpaperOn: this.appWallpaperOn
            });
          }
          .accessibilityText(`${it.chatTitle}，${it.preview}`)
          .onClick(() => { this.openResult(it); });
        }, (it: FoundItem, index: number): string =>
          guardKey(this.messageItemsData.keyTableId, index, foundItemKey(it)));
        if (this.pagingBusy || this.pagingError ||
          (this.loadedPageCount > 1 && this.nextOffset === '')) {
          ListItem() {
            this.paginationFooter();
          }
        }
      }
      .layoutWeight(1)
      .width('calc(100% - 24vp)')
      .margin({ left: 12, right: 12, top: 12, bottom: 12 })
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
        if (this.nextOffset !== '' && !this.loading && !this.pagingError &&
          end >= this.items.length - 5) {
          this.searchMessages(this.nextOffset);
        }
      });
    }
  }

  @Builder
  tabBody(idx: number) {
    if (idx === TAB_APPS && this.query.trim() === '') {
      this.appsList();
    } else if (idx === TAB_MEDIA) {
      this.mediaGrid();
    } else if (filterTypeForTab(idx) !== '') {
      // 链接/文件/音乐/语音: typed-message results, query optional.
      this.messageResults();
    } else if (idx === TAB_POSTS) {
      // Prompt (with explicit 搜索 button) until a search actually ran.
      if (this.loading || this.searchedOnce) {
        this.messageResults();
      } else {
        this.postsPrompt();
      }
    } else if (this.query.trim() === '') {
      if (idx === TAB_CHATS) {
        this.landing();
      } else {
        this.channelsLanding();
      }
    } else {
      this.combinedResults();
    }
  }

  build() {
    NavDestination() {
      this.body();
    }
    .hideTitleBar(true)
    .onReady((context: NavDestinationContext): void => {
      this.navStack = context.pathStack;
    })
    .width('100%').height('100%')
    .backgroundColor(mainPageFill(this.appWallpaperOn));
  }

  @Builder
  body() {
    Stack({ alignContent: Alignment.TopStart }) {
    // NavDestination 自带的页面层会隔断 MainScreen 的壁纸，和资料详情页一样在
    // 当前目的页内重画一层；分栏时 AppBackdrop 会按统一规则自动停止绘制。
    AppBackdrop({ split: isSplitByBreakpoint(this.widthBp, this.heightBp, this.forceSingleColumn) });
    Column() {
      Column() {
        // 搜索框和分类条跟着下面的结果列一起限宽、一起居中。它们语义上像标题栏
        // （通栏也说得通），但它们和结果卡片是上下贴着的一组，一个通栏一个居中
        // 会明显不对齐；何况一个 2880px 宽的输入框本身就没法看。
        Column() {
          this.searchBar();
          this.tabsBar();
        }
        .width('100%')
        .constraintSize({ maxWidth: readableContentWidth(this.screenW) })
        .padding({ left: 12, right: 12, top: this.topSafe + 10, bottom: 8 });
      }
      .width('100%')
      // Column 默认左对齐：限了宽不居中就是把内容全堆在屏幕左边，比不限还难看。
      .alignItems(HorizontalAlign.Center);

      Tabs({ controller: this.controller, index: this.tab }) {
        ForEach(TABS, (t: string, idx: number) => {
          TabContent() {
            // 这一页的限宽只能套在 tabBody 外面，不像联系人/设置那样落在滚动容器
            // 内部：十个 tab 各有各的容器，其中六个（聊天结果 / 媒体宫格 / 消息结果
            // / 下载 / 组合结果 / 各种空态）**自己就是那张卡片**——List/Grid/Scroll
            // 上直接挂着 calc(100% - 24vp) + 圆角 + surface 背景，卡片外面本来就
            // 不是内容区。套在外面还有一个好处：空态、加载态、错误态、以后新加的
            // 状态全部自动同宽，不会漏掉某个分支导致 tab 之间宽度不一。
            // 已知代价：limit 之后滚动容器本身收窄了，两侧留白按不动、拖不动页面。
            Column() {
              Column() {
                this.tabBody(idx);
              }
              .width('100%').height('100%')
              .constraintSize({ maxWidth: readableContentWidth(this.screenW) });
            }
            .width('100%').height('100%')
            // Column 默认左对齐：限了宽不居中，结果卡就全堆在屏幕左边了。
            .alignItems(HorizontalAlign.Center);
          }
        }, (t: string) => t);
      }
      .barHeight(0)
      .layoutWeight(1)
      .onAreaChange((_old: Area, area: Area) => { this.tabsWidth = area.width as number; })
      // Content swipe in progress: the pill tracks the finger continuously.
      .onGestureSwipe((index: number, event: TabsAnimationEvent) => {
        if (this.tabsWidth > 0) {
          this.moveIndicatorTo(index - event.currentOffset / this.tabsWidth);
        }
      })
      .onAnimationStart((_index: number, targetIndex: number) => {
        animateTo({
          duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 250), curve: Curve.EaseOut
        }, () => { this.moveIndicatorTo(targetIndex); });
        this.ensureTabVisible(targetIndex);
      })
      .onChange((index: number) => { this.onTabSelected(index); });
    }
    .width('100%').height('100%')
    .backgroundColor(mainPageFill(this.appWallpaperOn))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM]);

    }
    .width('100%').height('100%')
    .backgroundColor(mainPageFill(this.appWallpaperOn))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM]);
  }
}
