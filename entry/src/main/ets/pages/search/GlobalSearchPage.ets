import { promptAction, router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { getTdClient, getTdFilesDirectory } from '../../tdkit/Globals';
import { openLocalFile } from '../../util/openLocalFile';
import { formatFileSize } from '../../util/formatFileSize';
import { TdObject, TdRequest, TdError } from '../../tdkit/TdTypes';
import { GlobalSearchStore, SearchRow } from '../../store/GlobalSearchStore';
import { AvatarView } from '../chatlist/AvatarView';
import { AvatarViewer } from '../common/AvatarViewer';
import { ScannedFile, scanDownloadedFiles } from '../../util/downloadedFileScan';
import { LocalVideoPlayer } from '../common/LocalVideoPlayer';
import { formatPreview } from '../../util/formatPreview';
import { formatTime } from '../../util/formatTime';
import {
  COLOR_PRIMARY,
  COLOR_TEXT_PRIMARY,
  COLOR_TEXT_SECONDARY,
  COLOR_TAB_SELECTED,
  COLOR_TAB_UNSELECTED,
  COLOR_TAB_PILL_BG
} from '../../util/theme';
import { KEY_POWER_SMOOTH_TRANSITIONS, powerAnimationDuration } from '../../store/AppSettings';
import {
  DownloadCounts, DownloadEntry, DownloadPage, DownloadQuery, defaultDownloadQuery,
  downloadErrorMessage, emptyDownloadCounts, removeDownload, searchDownloads,
  setAllDownloadsPaused, setDownloadPaused
} from '../../store/DownloadApi';
import { plural, str } from '../../util/strings';
import { LANGUAGE_EPOCH } from '../../util/appLanguage';
import { overlayBlur, overlayMaterial, MATERIAL_EPOCH } from '../../util/overlayMaterial';
import { logChatNavFailure, navigateToChat } from '../../util/chatNav';
import { logE, logI } from '../../util/log';
import { readableContentWidth } from '../../util/contentWidth';

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
const TABS: string[] = [str('tab_chats'), str('gn_channel'), str('gs_apps'), str('gs_posts'), str('cpp_media'), str('gs_downloads'), str('cpp_links'), str('storage_file'), str('storage_audio'), str('storage_voice')];
const TAB_CHATS: number = 0;
const TAB_CHANNELS: number = 1;
const TAB_APPS: number = 2;
const TAB_POSTS: number = 3;
const TAB_MEDIA: number = 4;
const TAB_DOWNLOADS: number = 5;
const TAB_LINKS: number = 6;
const TAB_FILES: number = 7;
const TAB_AUDIO: number = 8;
const TAB_VOICE: number = 9;
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
// Photos below this size are almost certainly auto-downloaded thumbnails, not
// media the user pulled down — keep them out of the downloads list.
const MIN_PHOTO_BYTES: number = 100 * 1024;
const MAX_DOWNLOAD_ITEMS: number = 300;
// Cap on pages fetched automatically when a tab's filter hides every hit.
const MAX_AUTO_PAGES: number = 5;

interface DownloadItem {
  path: string;
  name: string;
  kind: string;    // 'photo' | 'video' | 'file'
  sizeLabel: string;
  mtime: number;   // ms — sort key
  dateLabel: string;
  fileId: number;  // >0 for download-manager items (live progress via updateFile)
  progress: number; // 0-99 while downloading, 100 when complete
  // 仅下载管理器登记过的条目（fileId > 0）才可暂停/移除；磁盘扫描出来的历史
  // 文件没有 file_id，TDLib 无从操作，所以这两个字段对它们恒为 false。
  isPaused: boolean;
  preview: string; // 来源消息摘要
  // 来源消息坐标，用于长按"定位到消息"。磁盘扫描出来的历史文件没有这层关联
  // （文件名里不含 chat/message），两者恒为 0，菜单里相应不提供该项。
  chatId: number;
  messageId: number;
}

// Global search (Telegram-style): an empty query shows frequent contacts and
// recently opened chats; a typed query searches chats/channels by name or
// messages ("帖子") globally.
@Entry
@Component
struct GlobalSearchPage {
  // 材质档位（厚度/光感）改变时重绘。overlayMaterial 是 util，订阅不了
  // AppStorage，只能由调用方订阅，同 LANGUAGE_EPOCH 的做法。
  @StorageProp(MATERIAL_EPOCH) private materialEpoch: number = 0;
  @StorageProp(LANGUAGE_EPOCH) langEpoch: number = 0;
  @StorageProp('topSafeHeight') topSafe: number = 0;
  // 窗口宽（不是屏幕宽），限宽用。平板上把结果列拉满 2880px，头像贴最左、时间
  // 贴最右，眼睛要横扫整屏才读得完一行（设备截图实测）。
  @StorageProp('screenWidthVp') screenW: number = 360;
  @State query: string = '';
  @State tab: number = 0;
  @State searchFocused: boolean = false;
  @State searchPending: boolean = false;
  @State clearPressed: boolean = false;
  @State cancelPressed: boolean = false;
  @State closingSearch: boolean = false;
  @State searchHeaderVisible: boolean = false;
  @State resultOpeningKey: string = '';
  @State topUsers: SearchRow[] = [];
  @State recent: SearchRow[] = [];
  @State recentlyOpened: SearchRow[] = [];
  @State topLoaded: boolean = false;
  @State recentLoaded: boolean = false;
  @State openedLoaded: boolean = false;
  @State topFailed: boolean = false;
  @State recentFailed: boolean = false;
  @State openedFailed: boolean = false;
  @State clearingRecent: boolean = false;
  @State chatResults: SearchRow[] = [];
  @State chatSearching: boolean = false;
  @State chatSearchFailed: boolean = false;
  @State joinedChannels: SearchRow[] = [];
  @State similarChannels: SearchRow[] = [];
  @State apps: SearchRow[] = [];
  @State joinedLoaded: boolean = false;
  @State similarLoaded: boolean = false;
  @State appsLoaded: boolean = false;
  @State joinedFailed: boolean = false;
  @State similarFailed: boolean = false;
  @State appsFailed: boolean = false;
  // 帖子 (message) search state.
  @State items: FoundItem[] = [];
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
    .backgroundColor($r('app.color.surface'))
  }

  @Styles
  resultRowPressedStyle() {
    .backgroundColor($r('app.color.surface_alt'))
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
    .backgroundColor($r('app.color.surface_alt'))
  }

  @Styles
  retryActionNormalStyle() {
    .backgroundColor($r('app.color.surface_alt'))
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
    if (index === TAB_DOWNLOADS) {
      this.loadDownloads();
      this.loadActiveDownloads();
    }
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
    const params = router.getParams() as Record<string, Object> | undefined;
    const q = params !== undefined ? (params['query'] as string | undefined) : undefined;
    if (q !== undefined && q !== '') {
      // Hashtag entry — straight into the 帖子 (global posts) tab.
      this.query = q;
      this.tab = TAB_POSTS;
      this.searchMessages('');
    }
  }

  aboutToDisappear(): void {
    if (this.unsubFile !== null) { this.unsubFile(); this.unsubFile = null; }
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
    this.closingSearch = true;
    this.cancelPressed = false;
    this.closeSearchTimer = setTimeout((): void => {
      this.closeSearchTimer = -1;
      this.closingSearch = false;
    }, 650);
    try {
      router.back();
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
    if (this.tab === TAB_DOWNLOADS) {
      return str('gs_search_downloads');
    }
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

  @State downloads: DownloadItem[] = [];      // completed, from the filesystem scan
  @State activeDownloads: DownloadItem[] = []; // in-flight, from TDLib's download manager
  @State downloadsLoaded: boolean = false;
  @State downloadsScanning: boolean = false;
  @State downloadCounts: DownloadCounts = emptyDownloadCounts();
  @State downloadActionBusy: boolean = false;
  // 待确认移除的条目：!== null 时弹确认框，同时决定"是否删除本地文件"的默认值。
  @State pendingRemoval: DownloadItem | null = null;
  // 应用内预览的目标。图片走 AvatarViewer（同一套缩放/拖动/下滑关闭），
  // 视频走 LocalVideoPlayer；文档类没有通用渲染器，仍交给系统应用。
  @State previewItem: DownloadItem | null = null;
  @State previewTapX: number = 0;
  @State previewTapY: number = 0;
  @State removeAlsoDeletesFile: boolean = false;
  @State removeSheetShown: boolean = false;
  private unsubFile: (() => void) | null = null;

  // Active (in-progress) downloads from TDLib's download manager. Fetched on
  // every 下载 tab visit; progress rows update live via updateFile.
  private loadActiveDownloads(): void {
    const query: DownloadQuery = defaultDownloadQuery();
    query.onlyActive = true;
    searchDownloads(getTdClient(), query).then((page: DownloadPage) => {
      const fresh: DownloadItem[] = [];
      for (const entry of page.entries) {
        fresh.push({
          path: '', name: this.downloadEntryName(entry), kind: 'file',
          sizeLabel: '', mtime: entry.addDate * 1000,
          dateLabel: '', fileId: entry.fileId, progress: 0,
          isPaused: entry.isPaused, preview: entry.preview,
          chatId: entry.chatId, messageId: entry.messageId
        });
        this.refreshFileProgress(entry.fileId);
      }
      this.activeDownloads = fresh;
      this.downloadCounts = page.counts;
      if (this.unsubFile === null && fresh.length > 0) {
        this.unsubFile = getTdClient().onUpdate('updateFile', (u: TdObject) => {
          const f = u['file'] as TdObject | undefined;
          if (f !== undefined) {
            this.applyDownloadFile(f);
          }
        });
      }
    }).catch((e: Object) => {
      logE(`GlobalSearchPage.searchFileDownloads failed: ${downloadErrorMessage(str('gs_action_load_downloads'), e)}`);
      promptAction.showToast({ message: downloadErrorMessage(str('gs_action_load_downloads'), e), duration: 1800 });
    });
  }

  // 下载项的显示名：优先取消息里的原始文件名，退回消息摘要。
  private downloadEntryName(entry: DownloadEntry): string {
    if (entry.fileName !== '') {
      return entry.fileName;
    }
    return entry.preview !== '' ? entry.preview : str('gs_media_file');
  }

  // 所有进行中的条目都已暂停时，顶部按钮切换成"全部继续"。
  private allDownloadsPaused(): boolean {
    return this.downloadCounts.activeCount === 0 && this.downloadCounts.pausedCount > 0;
  }

  private async toggleOneDownload(item: DownloadItem): Promise<void> {
    if (item.fileId === 0 || this.downloadActionBusy) {
      return;
    }
    this.downloadActionBusy = true;
    const next = !item.isPaused;
    try {
      await setDownloadPaused(getTdClient(), item.fileId, next);
      // 乐观更新只为消除按钮延迟，权威状态仍以随后的列表刷新为准。
      this.activeDownloads = this.activeDownloads.map((it: DownloadItem): DownloadItem =>
        it.fileId === item.fileId ? this.withPaused(it, next) : it);
      this.reloadDownloadState();
    } catch (e) {
      promptAction.showToast({ message: downloadErrorMessage(next ? str('gs_action_pause') : str('gs_action_resume'), e), duration: 1800 });
    }
    this.downloadActionBusy = false;
  }

  private withPaused(item: DownloadItem, paused: boolean): DownloadItem {
    return {
      path: item.path, name: item.name, kind: item.kind, sizeLabel: item.sizeLabel,
      mtime: item.mtime, dateLabel: item.dateLabel, fileId: item.fileId,
      progress: item.progress, isPaused: paused, preview: item.preview,
      chatId: item.chatId, messageId: item.messageId
    };
  }

  private async toggleAllDownloads(): Promise<void> {
    if (this.downloadActionBusy) {
      return;
    }
    this.downloadActionBusy = true;
    const pauseAll = !this.allDownloadsPaused();
    try {
      await setAllDownloadsPaused(getTdClient(), pauseAll);
      this.reloadDownloadState();
    } catch (e) {
      promptAction.showToast({
        message: downloadErrorMessage(pauseAll ? str('gs_action_pause_all') : str('gs_action_resume_all'), e), duration: 1800
      });
    }
    this.downloadActionBusy = false;
  }

  private async confirmRemoveDownload(item: DownloadItem, deleteFromCache: boolean): Promise<void> {
    if (item.fileId === 0) {
      return;
    }
    try {
      await removeDownload(getTdClient(), item.fileId, deleteFromCache);
      this.activeDownloads = this.activeDownloads.filter((it: DownloadItem) => it.fileId !== item.fileId);
      // 删除了本地文件时磁盘扫描结果也过期了，强制重扫。
      if (deleteFromCache) {
        this.downloadsLoaded = false;
        this.loadDownloads();
      }
      this.reloadDownloadState();
    } catch (e) {
      promptAction.showToast({ message: downloadErrorMessage(str('gs_action_remove'), e), duration: 1800 });
    }
  }

  // 任何写操作之后重新拉一次列表，让计数与暂停态回到服务端权威值。
  private reloadDownloadState(): void {
    this.loadActiveDownloads();
  }

  private refreshFileProgress(fileId: number): void {
    const req: TdRequest = { '@type': 'getFile' };
    req['file_id'] = fileId;
    getTdClient().send(req).then((f: TdObject) => { this.applyDownloadFile(f); })
      .catch((e: TdError) => { logE(`GlobalSearchPage.getFile failed: ${e.message}`); });
  }

  private applyDownloadFile(file: TdObject): void {
    const id = (file['id'] as number | undefined) ?? 0;
    if (id === 0 || this.activeDownloads.findIndex((it: DownloadItem) => it.fileId === id) < 0) {
      return;
    }
    const local = file['local'] as TdObject | undefined;
    const done = local !== undefined ? ((local['is_downloading_completed'] as boolean | undefined) ?? false) : false;
    const path = local !== undefined ? ((local['path'] as string | undefined) ?? '') : '';
    const got = local !== undefined ? ((local['downloaded_size'] as number | undefined) ?? 0) : 0;
    const total = (file['expected_size'] as number | undefined) ?? ((file['size'] as number | undefined) ?? 0);
    const progress = done ? 100 : (total > 0 ? Math.min(99, Math.floor(got * 100 / total)) : 0);
    this.activeDownloads = this.activeDownloads.map((it: DownloadItem): DownloadItem => it.fileId === id
      ? {
        path: done ? path : it.path, name: it.name, kind: it.kind,
        sizeLabel: total > 0 ? formatFileSize(total) : it.sizeLabel,
        mtime: it.mtime, dateLabel: done ? str('gs_just_now') : it.dateLabel,
        fileId: it.fileId, progress, isPaused: it.isPaused, preview: it.preview,
        chatId: it.chatId, messageId: it.messageId
      } : it);
  }

  // Scan TDLib's download directories for media/files already on disk,
  // newest first. Small photos are skipped (auto-downloaded thumbnails).
  // 扫描本身跑在 TaskPool 里 —— 见 util/downloadedFileScan.ets 的说明，同步扫
  // 会因为文件数量把主线程卡到被系统杀掉。
  private loadDownloads(): void {
    if (this.downloadsLoaded) {
      return;
    }
    this.downloadsLoaded = true;
    this.downloadsScanning = true;
    scanDownloadedFiles(getTdFilesDirectory(), MIN_PHOTO_BYTES, MAX_DOWNLOAD_ITEMS)
      .then((found: ScannedFile[]): void => {
        this.downloads = found.map((f: ScannedFile): DownloadItem => {
          return {
            path: f.path, name: f.name, kind: f.kind,
            sizeLabel: formatFileSize(f.size),
            mtime: f.mtimeSec * 1000,
            dateLabel: this.downloadDate(f.mtimeSec),
            fileId: 0, progress: 100, isPaused: false, preview: '',
            chatId: 0, messageId: 0
          };
        });
        this.downloadsScanning = false;
      })
      .catch((e: Object): void => {
        logE(`GlobalSearchPage.scanDownloadedFiles failed: ${JSON.stringify(e)}`);
        this.downloadsScanning = false;
        // 允许下次进入 tab 时重试，否则一次失败会让列表永久空白。
        this.downloadsLoaded = false;
      });
  }

  private downloadDate(sec: number): string {
    const d = new Date(sec * 1000);
    return `${d.getFullYear()}-${d.getMonth() + 1}-${d.getDate()}`;
  }

  // 图片/视频在应用内看，其余（文档、压缩包……）没有通用渲染器，交给系统应用。
  private openDownloadItem(it: DownloadItem): void {
    if (it.progress < 100 || it.path === '') {
      return;
    }
    if (it.kind === 'photo' || it.kind === 'video') {
      this.previewItem = it;
      return;
    }
    openLocalFile(getContext(this) as common.UIAbilityContext, it.path, '');
  }

  private canLocateDownload(it: DownloadItem): boolean {
    return it.chatId !== 0 && it.messageId !== 0;
  }

  // 和 openChat / openApp / openResult 一样先过防连点闸门。这一处的目标也是
  // 一条具体消息，所以 key 与 openResult 同格式——同一条消息无论从哪个 tab
  // 点进去都是同一把闸。
  //
  // 这里本来没有闸门：它是长按菜单里的 MenuItem，菜单点一次就关，"连点两次"
  // 看着不可能。但那条安全网押的是"两次点击是两个宏任务、中间微任务队列必然
  // 排空"这个隐含前提——openChatAndClose 里的 router.back() 挂在 navigateToChat
  // 的 then 上，双 back 会把下面的页面一起弹掉。不把正确性押在事件循环时序上。
  private locateDownloadMessage(it: DownloadItem): void {
    if (!this.canLocateDownload(it)) {
      return;
    }
    const openingKey = `message:${it.chatId}:${it.messageId}`;
    if (!this.beginResultOpening(openingKey)) {
      return;
    }
    const params: Record<string, Object> = { 'chatId': it.chatId, 'jumpTo': it.messageId };
    this.openChatAndClose(params);
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
    } else if (this.tab === TAB_DOWNLOADS) {
      // Filtered client-side — nothing to fetch.
      this.cancelInFlight();
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
      req['chat_list'] = { '@type': 'chatListMain' } as TdObject;
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

  // 会话被推进的是**聊天页签的栈**，而本页是 router 页、整个盖在那条栈上面：
  // 只推不关，用户看到的是"什么都没发生"。形状取自 NewGroupPage.openCreatedGroup
  // ——漏斗成功之后再把本页弹掉，露出下面已经切到聊天页签的会话。
  // router.back() 是同步 void、正常失败不抛，所以它不需要自己的 try/catch；
  // 真正会失败的是 navigateToChat（栈未注册时回退整页路由），由 catch 收尾，
  // 此时本页留在原地，防连点闸门由 beginResultOpening 的 900ms 定时器解开。
  // closingSearch 是"取消"按钮那条路已经调过 router.back() 的标记：那 650ms 窗口
  // 里再弹一次会把下面的页面一起弹掉，所以要挡；反过来本路径也要立起这个标记，
  // 免得成功之后又被一次点击弹第二层。
  private openChatAndClose(params: Record<string, Object>): void {
    navigateToChat(params).then((): void => {
      if (this.closingSearch) {
        return;
      }
      this.closingSearch = true;
      router.back();
    }).catch(logChatNavFailure);
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
              .fontColor([this.searchFocused ? COLOR_PRIMARY : COLOR_TEXT_SECONDARY])
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
              .fontColor([COLOR_TEXT_SECONDARY]);
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
      .backgroundColor($r('app.color.surface'))
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
    .backgroundColor($r('app.color.surface'))
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

      Scroll() {
        Row({ space: 4 }) {
          ForEach(this.resolvedTopUsers(), (row: SearchRow) => {
            Column({ space: 6 }) {
              Stack({ alignContent: Alignment.Center }) {
                AvatarView({
                  avatarPath: row.avatarPath,
                  initials: row.initials,
                  colorSeed: row.chatId,
                  avatarSize: 58,
                  savedMessages: this.store !== null && row.chatId === this.store.selfChatId()
                });
                if (this.resultOpeningKey === `chat:${row.chatId}`) {
                  Circle({ width: 58, height: 58 }).fill('#66000000');
                  LoadingProgress().width(20).height(20).color(Color.White);
                }
              }
              Text(row.title)
                .fontSize(13)
                .fontColor(COLOR_TEXT_PRIMARY)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .width(68)
                .textAlign(TextAlign.Center);
            }
            .width(78)
            .height(92)
            .padding({ top: 6 })
            .borderRadius(14)
            .stateStyles({
              normal: this.landingActionNormalStyle,
              pressed: this.landingActionPressedStyle
            })
            .accessibilityText(str('gs_frequent_a11y', row.title))
            .onClick((): void => { this.openChat(row.chatId); });
          }, (row: SearchRow) => `top_${row.chatId}_${row.title}_${row.avatarPath}`);
        }
        .padding({ left: 8, right: 8, bottom: 8 });
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .width('100%');
    }
    .width('calc(100% - 20vp)')
    .margin({ left: 10, right: 10, top: 8 })
    .backgroundColor($r('app.color.surface'))
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
  recentSection() {
    Column() {
      Row() {
        Row({ space: 6 }) {
          SymbolGlyph($r('sys.symbol.clock'))
            .fontSize(16)
            .fontColor([COLOR_TEXT_SECONDARY]);
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

      Column() {
        ForEach(this.resolvedRecent(), (row: SearchRow, index: number) => {
          this.chatRow(row, index > 0);
        }, (row: SearchRow) =>
          `recent_${row.chatId}_${row.title}_${row.subtitle}_${row.avatarPath}`);
      }
      .width('100%');
    }
    .width('calc(100% - 20vp)')
    .margin({ left: 10, right: 10, top: 10, bottom: 10 })
    .backgroundColor($r('app.color.surface'))
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
  recentlyOpenedSection() {
    Column() {
      Row({ space: 6 }) {
        SymbolGlyph($r('sys.symbol.clock'))
          .fontSize(16)
          .fontColor([COLOR_TEXT_SECONDARY]);
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

      Column() {
        ForEach(this.resolvedRecentlyOpened(), (row: SearchRow, index: number) => {
          this.chatRow(row, index > 0);
        }, (row: SearchRow) =>
          `opened_${row.chatId}_${row.title}_${row.subtitle}_${row.avatarPath}`);
      }
      .width('100%');
    }
    .width('calc(100% - 20vp)')
    .margin({ left: 10, right: 10, top: 10, bottom: 10 })
    .backgroundColor($r('app.color.surface'))
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
          .fontColor([COLOR_TEXT_SECONDARY]);
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
    .backgroundColor($r('app.color.surface'))
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
    .backgroundColor($r('app.color.surface'))
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
  @Builder
  landing() {
    Scroll() {
      Column() {
        if (this.resolvedTopUsers().length > 0) {
          this.frequentSection();
        }
        if (this.resolvedRecent().length > 0) {
          this.recentSection();
        }
        if (this.resolvedRecentlyOpened().length > 0) {
          this.recentlyOpenedSection();
        }
        if (this.resolvedTopUsers().length === 0 && this.resolvedRecent().length === 0 &&
          this.resolvedRecentlyOpened().length === 0) {
          if (this.landingResolving()) {
            this.landingLoadingState();
          } else if (this.landingFailed()) {
            this.landingErrorState();
          } else {
            this.landingEmptyState();
          }
        }
      }
      .width('100%')
      .padding({ bottom: 8 });
    }
    .layoutWeight(1)
    .width('100%')
    .align(Alignment.Top)
    .edgeEffect(EdgeEffect.Spring)
    .scrollBar(BarState.Off);
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
    .backgroundColor($r('app.color.surface'))
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
          .fontColor([COLOR_TEXT_SECONDARY]);
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
    .backgroundColor($r('app.color.surface'))
    .borderRadius(20)
    .transition(TransitionEffect.OPACITY
      .combine(TransitionEffect.scale({ x: 0.97, y: 0.97 }))
      .animation({
        duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 180),
        curve: Curve.EaseOut
      }));
  }

  // 频道 tab landing: joined channels + server-recommended channels.
  @Builder
  channelsLanding() {
    Scroll() {
      Column() {
        if (this.joinedChannels.length > 0) {
          this.sectionHeader(str('gs_joined_channels'));
          Column() {
            ForEach(this.joinedChannels, (r: SearchRow, idx: number) => {
              this.chatRow(r, idx > 0);
            }, (r: SearchRow) => `jc_${r.chatId}_${r.title}_${r.subtitle}_${r.avatarPath}`);
          }.width('100%').backgroundColor($r('app.color.surface'));
        }
        if (this.similarChannels.length > 0) {
          this.sectionHeader(str('gs_similar_channels'));
          Column() {
            ForEach(this.similarChannels, (r: SearchRow, idx: number) => {
              this.chatRow(r, idx > 0);
            }, (r: SearchRow) => `sc_${r.chatId}_${r.title}_${r.subtitle}_${r.avatarPath}`);
          }.width('100%').backgroundColor($r('app.color.surface'));
        }
        if (this.joinedChannels.length === 0 && this.similarChannels.length === 0) {
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
      }.width('100%');
    }
    .layoutWeight(1).width('100%')
    .align(Alignment.Top)
    .edgeEffect(EdgeEffect.Spring)
    .scrollBar(BarState.Off);
  }

  @Builder
  appRow(r: SearchRow, showDivider: boolean) {
    Column() {
      if (showDivider) {
        Divider().color($r('app.color.divider')).strokeWidth(0.7)
          .margin({ left: SEARCH_RESULT_DIVIDER_INSET });
      }
      Row({ space: 12 }) {
        AvatarView({ avatarPath: r.avatarPath, initials: r.initials, colorSeed: r.userId, avatarSize: 48 });
        Column({ space: 3 }) {
          Text(r.title !== '' ? r.title : '…')
            .fontSize(16).fontWeight(FontWeight.Medium).fontColor(COLOR_TEXT_PRIMARY)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
          if (r.subtitle !== '') {
            Text(r.subtitle).fontSize(13).fontColor(COLOR_TEXT_SECONDARY)
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
          }
        }.alignItems(HorizontalAlign.Start).layoutWeight(1);
        Row() {
          if (this.resultOpeningKey === `app:${r.userId}`) {
            LoadingProgress().width(16).height(16).color(Color.White);
          } else {
            Text($r('app.string.open')).fontSize(14).fontWeight(FontWeight.Medium).fontColor(Color.White);
          }
        }
        .width(58).height(30)
        .justifyContent(FlexAlign.Center)
        .backgroundColor(COLOR_PRIMARY)
        .borderRadius(15);
      }
      .width('100%')
      .constraintSize({ minHeight: 64 })
      .padding({ left: 14, right: 14, top: 8, bottom: 8 })
      .alignItems(VerticalAlign.Center)
      .stateStyles({
        normal: this.resultRowNormalStyle,
        pressed: this.resultRowPressedStyle
      })
      .accessibilityText(str('gs_open_a11y', r.title, r.subtitle !== '' ? str('gs_comma') + r.subtitle : ''))
      .onClick(() => { this.openApp(r.userId); });
    }
  }

  // 应用 tab: top-grossing mini apps; a typed query filters by name.
  @Builder
  appsList() {
    Scroll() {
      Column() {
        this.sectionHeader(str('gs_popular_apps'));
        Column() {
          ForEach(this.filteredAppResults(),
            (r: SearchRow, idx: number) => {
              this.appRow(r, idx > 0);
            }, (r: SearchRow) => `app_${r.userId}_${r.title}_${r.subtitle}_${r.avatarPath}`);
        }.width('100%').backgroundColor($r('app.color.surface'));
        if (this.filteredAppResults().length === 0 && this.query.trim() === '') {
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
      }.width('100%');
    }
    .layoutWeight(1).width('100%')
    .align(Alignment.Top)
    .edgeEffect(EdgeEffect.Spring)
    .scrollBar(BarState.Off);
  }

  @Builder
  downloadRow(it: DownloadItem, showDivider: boolean) {
    Column() {
      if (showDivider) {
        Divider().color($r('app.color.divider')).strokeWidth(0.7)
          .margin({ left: SEARCH_RESULT_DIVIDER_INSET });
      }
      Row({ space: 12 }) {
        if (it.kind === 'photo') {
          Image(`file://${it.path}`).draggable(false)
            .width(48).height(48).borderRadius(8).objectFit(ImageFit.Cover);
        } else {
          Row() {
            SymbolGlyph($r(it.kind === 'video' ? 'sys.symbol.play_fill' : 'sys.symbol.doc_text'))
              .fontSize(20).fontColor([Color.White]);
          }
          .width(48).height(48).borderRadius(8).backgroundColor(COLOR_PRIMARY)
          .justifyContent(FlexAlign.Center);
        }
        Column({ space: 3 }) {
          Text(it.name).fontSize(15).fontWeight(FontWeight.Medium).fontColor(COLOR_TEXT_PRIMARY)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
          if (it.progress < 100) {
            Progress({ value: it.progress, total: 100, type: ProgressType.Linear })
              .width('92%').height(4).color(it.isPaused ? COLOR_TEXT_SECONDARY : COLOR_PRIMARY);
            Text(str('gs_download_state', it.sizeLabel !== '' ? it.sizeLabel + ' · ' : '', it.isPaused ? str('gs_paused') : str('gs_downloading'), it.progress))
              .fontSize(13).fontColor(COLOR_TEXT_SECONDARY);
          } else {
            Text(`${it.sizeLabel}${it.dateLabel !== '' ? ' · ' + it.dateLabel : ''}`)
              .fontSize(13).fontColor(COLOR_TEXT_SECONDARY);
          }
          if (it.preview !== '') {
            Text(it.preview).fontSize(12).fontColor(COLOR_TEXT_SECONDARY)
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
          }
        }.alignItems(HorizontalAlign.Start).layoutWeight(1);
        // 只有下载管理器登记过的条目才给操作按钮，避免对磁盘扫描项做无效调用。
        if (it.fileId !== 0) {
          if (it.progress < 100) {
            Button({ type: ButtonType.Circle }) {
              SymbolGlyph($r(it.isPaused ? 'sys.symbol.play_fill' : 'sys.symbol.pause_fill'))
                .fontSize(18).fontColor([COLOR_PRIMARY]);
            }
            .width(34).height(34).backgroundColor(Color.Transparent)
            .enabled(!this.downloadActionBusy)
            .accessibilityText(it.isPaused ? $r('app.string.gs_resume_download') : $r('app.string.gs_pause_download'))
            .onClick(() => { this.toggleOneDownload(it); });
          }
          Button({ type: ButtonType.Circle }) {
            SymbolGlyph($r('sys.symbol.trash')).fontSize(18).fontColor([COLOR_TEXT_SECONDARY]);
          }
          .width(34).height(34).backgroundColor(Color.Transparent)
          .accessibilityText($r('app.string.gs_remove_download'))
          .onClick(() => {
            this.removeAlsoDeletesFile = false;
            this.pendingRemoval = it;
            this.removeSheetShown = true;
          });
        }
      }
      .width('100%').padding({ left: 14, right: 14, top: 8, bottom: 8 })
      .alignItems(VerticalAlign.Center)
      .stateStyles({
        normal: this.resultRowNormalStyle,
        pressed: this.resultRowPressedStyle
      })
      .accessibilityText(str('gs_download_a11y', it.name, it.progress < 100 ? str('gs_downloading') : it.sizeLabel))
      .onClick((event: ClickEvent) => {
        this.previewTapX = event.windowX;
        this.previewTapY = event.windowY;
        this.openDownloadItem(it);
      })
      .bindContextMenu(this.downloadRowMenu(it), ResponseType.LongPress, { systemMaterial: overlayMaterial('menu') });
    }
  }

  @Builder
  downloadRowMenu(it: DownloadItem) {
    Menu() {
      if (this.canLocateDownload(it)) {
        MenuItem({ startIcon: $r('sys.symbol.arrow_up_left_and_arrow_down_right'), content: $r('app.string.gs_jump_to_message') })
          .onClick((): void => { this.locateDownloadMessage(it); });
      }
      if (it.progress >= 100 && it.path !== '') {
        MenuItem({ startIcon: $r('sys.symbol.arrow_right_and_square'), content: $r('app.string.gs_open_with') })
          .onClick((): void => {
            openLocalFile(getContext(this) as common.UIAbilityContext, it.path, '');
          });
      }
      if (it.fileId !== 0) {
        MenuItem({ startIcon: $r('sys.symbol.trash'), content: $r('app.string.gs_remove_download') })
          .onClick((): void => {
            this.removeAlsoDeletesFile = false;
            this.pendingRemoval = it;
            this.removeSheetShown = true;
          });
      }
    }
  }

  // 下载 tab: everything TDLib has downloaded to disk, newest first; a typed
  // query filters by file name.
  // In-flight items (dedup'd against the completed scan by path) lead the
  // list, then completed files, newest first.
  private mergedDownloads(): DownloadItem[] {
    const donePaths = new Set<string>();
    const active = this.activeDownloads.filter((it: DownloadItem) => {
      if (it.progress >= 100 && it.path !== '') {
        donePaths.add(it.path);
      }
      return true;
    });
    const completed = this.downloads.filter((it: DownloadItem) => !donePaths.has(it.path));
    const q = this.query.trim().toLowerCase();
    return [...active, ...completed].filter((it: DownloadItem) =>
      q === '' || it.name.toLowerCase().includes(q));
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

  // 计数条：TDLib 的 downloadedFileCounts 是列表的权威统计，比客户端数组长度可靠。
  @Builder
  downloadCountsBar() {
    Row({ space: 10 }) {
      Column({ space: 2 }) {
        Text(str('gs_active_n', this.downloadCounts.activeCount)).fontSize(13).fontColor(COLOR_TEXT_PRIMARY);
        Text(str('gs_paused_completed', this.downloadCounts.pausedCount, this.downloadCounts.completedCount))
          .fontSize(12).fontColor(COLOR_TEXT_SECONDARY);
      }.alignItems(HorizontalAlign.Start).layoutWeight(1);
      if (this.downloadCounts.activeCount + this.downloadCounts.pausedCount > 0) {
        Button(this.allDownloadsPaused() ? $r('app.string.gs_action_resume_all') : $r('app.string.gs_action_pause_all'))
          .fontSize(14).fontColor(COLOR_PRIMARY)
          .backgroundColor(COLOR_TAB_PILL_BG)
          .height(32).padding({ left: 14, right: 14 })
          .enabled(!this.downloadActionBusy)
          .onClick(() => { this.toggleAllDownloads(); });
      }
    }
    .width('100%').padding({ left: 14, right: 14, top: 10, bottom: 10 })
    .alignItems(VerticalAlign.Center);
  }

  @Builder
  removeDownloadSheet() {
    Column({ space: 14 }) {
      Text($r('app.string.gs_remove_download')).fontSize(17).fontWeight(FontWeight.Medium).fontColor(COLOR_TEXT_PRIMARY);
      Text(this.pendingRemoval !== null ? this.pendingRemoval.name : '')
        .fontSize(14).fontColor(COLOR_TEXT_SECONDARY)
        .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis });
      Row({ space: 10 }) {
        Checkbox().select(this.removeAlsoDeletesFile)
          .onChange((checked: boolean) => { this.removeAlsoDeletesFile = checked; });
        Text($r('app.string.gs_delete_local')).fontSize(14).fontColor(COLOR_TEXT_PRIMARY).layoutWeight(1);
      }.width('100%').alignItems(VerticalAlign.Center);
      Row({ space: 12 }) {
        Button($r('app.string.cancel')).fontSize(15).fontColor(COLOR_TEXT_SECONDARY)
          .backgroundColor(COLOR_TAB_PILL_BG).layoutWeight(1).height(42)
          .onClick(() => { this.removeSheetShown = false; });
        Button($r('app.string.gs_action_remove')).fontSize(15).fontColor(Color.White)
          .backgroundColor(COLOR_PRIMARY).layoutWeight(1).height(42)
          .onClick(() => {
            const target = this.pendingRemoval;
            const deleteFile = this.removeAlsoDeletesFile;
            this.removeSheetShown = false;
            if (target !== null) {
              this.confirmRemoveDownload(target, deleteFile);
            }
          });
      }.width('100%');
    }
    .width('100%').padding(20).alignItems(HorizontalAlign.Start);
  }

  @Builder
  downloadsList() {
    Column() {
      this.downloadCountsBar();
      List() {
        ForEach(this.mergedDownloads(), (it: DownloadItem, idx: number) => {
          ListItem() {
            this.downloadRow(it, idx > 0);
          }.backgroundColor($r('app.color.surface'));
        }, (it: DownloadItem) =>
          `dl_${it.fileId}_${it.path}_${it.progress}_${it.isPaused}_${it.sizeLabel}_${it.dateLabel}`);
        if (this.downloadsScanning && this.downloads.length === 0) {
          ListItem() {
            Column({ space: 10 }) {
              LoadingProgress().width(32).height(32).color(COLOR_PRIMARY);
              Text($r('app.string.gs_scanning')).fontSize(14).fontColor(COLOR_TEXT_SECONDARY);
            }
            .width('100%').padding({ top: 48 });
          }
        } else if (this.downloads.length === 0 && this.activeDownloads.length === 0) {
          ListItem() {
            Text($r('app.string.gs_no_downloads')).fontSize(14).fontColor(COLOR_TEXT_SECONDARY)
              .width('100%').textAlign(TextAlign.Center).padding({ top: 48 });
          }
        }
      }
      .layoutWeight(1).width('100%')
      .edgeEffect(EdgeEffect.Spring)
      .scrollBar(BarState.Off);
    }
    .layoutWeight(1)
    .width('calc(100% - 24vp)')
    .margin({ left: 12, right: 12, top: 12, bottom: 12 })
    .backgroundColor($r('app.color.surface'))
    .borderRadius(20)
    .clip(true)
    .bindSheet($$this.removeSheetShown, this.removeDownloadSheet(), {
      height: SheetSize.FIT_CONTENT,
      backgroundColor: $r('app.color.surface'),
      onDisappear: () => { this.pendingRemoval = null; },
      blurStyle: overlayBlur('dialog'), systemMaterial: overlayMaterial('dialog')
    });
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
    .backgroundColor($r('app.color.surface'))
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
    .backgroundColor($r('app.color.surface'))
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
        LoadingProgress().width(36).height(36).color(COLOR_TEXT_SECONDARY);
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
            }.backgroundColor($r('app.color.surface'));
          }, (r: SearchRow) => `res_${r.chatId}_${r.title}_${r.subtitle}_${r.avatarPath}`);
      }
      .layoutWeight(1)
      .width('calc(100% - 24vp)')
      .margin({ left: 12, right: 12, top: 12, bottom: 12 })
      .backgroundColor($r('app.color.surface'))
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
      .backgroundColor($r('app.color.surface'))
      .borderRadius(20);
    } else {
      Grid() {
        ForEach(this.visibleItems(), (it: FoundItem) => {
          GridItem() {
            Stack({ alignContent: Alignment.BottomEnd }) {
              if (it.thumbPath !== '') {
                Image(`file://${it.thumbPath}`).draggable(false)
                  .width('100%').height('100%').objectFit(ImageFit.Cover);
              } else {
                Column().width('100%').height('100%').backgroundColor($r('app.color.surface_alt'));
              }
              if (it.isVideo) {
                Row({ space: 3 }) {
                  SymbolGlyph($r('sys.symbol.play_fill')).fontSize(10).fontColor([Color.White]);
                  Text(it.duration).fontSize(11).fontColor(Color.White);
                }
                .backgroundColor('#00000066').borderRadius(8)
                .padding({ left: 5, right: 5, top: 1, bottom: 1 })
                .margin({ right: 4, bottom: 4 });
              }
            }
            .width('100%').aspectRatio(1)
            .clip(true)
            .stateStyles({
              normal: this.mediaResultNormalStyle,
              pressed: this.mediaResultPressedStyle
            })
            .accessibilityText(str('gs_media_a11y', it.isVideo ? str('storage_video') : str('storage_photo'), it.chatTitle))
            .onClick(() => { this.openResult(it); });
          }
        }, (it: FoundItem) => `m_${it.chatId}_${it.messageId}_${it.chatTitle}_${it.thumbPath}`);
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
      .layoutWeight(1)
      .width('calc(100% - 24vp)')
      .margin({ left: 12, right: 12, top: 12, bottom: 12 })
      .backgroundColor($r('app.color.surface'))
      .borderRadius(20)
      .clip(true)
      .onReachEnd(() => {
        if (this.nextOffset !== '' && !this.loading && !this.pagingError) {
          this.searchMessages(this.nextOffset);
        }
      });
    }
  }

  @Builder
  msgRow(it: FoundItem) {
    Row({ space: 12 }) {
      AvatarView({ avatarPath: it.avatarPath, initials: it.initials, colorSeed: it.chatId, avatarSize: 44 });
      Column({ space: 3 }) {
        Row() {
          Text(it.chatTitle !== '' ? it.chatTitle : '...')
            .fontSize(15).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT_PRIMARY)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1);
          if (this.resultOpeningKey === `message:${it.chatId}:${it.messageId}`) {
            LoadingProgress().width(16).height(16).color(COLOR_PRIMARY);
          } else {
            Text(formatTime(it.date, this.nowSec)).fontSize(12).fontColor(COLOR_TEXT_SECONDARY);
          }
        }.width('100%');
        Text(it.preview).fontSize(14).fontColor(COLOR_TEXT_SECONDARY)
          .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis });
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1);
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding({ left: 14, right: 14, top: 10, bottom: 10 })
    .constraintSize({ minHeight: 66 })
    .stateStyles({
      normal: this.resultRowNormalStyle,
      pressed: this.resultRowPressedStyle
    })
    .accessibilityText(`${it.chatTitle}，${it.preview}`)
    .onClick(() => { this.openResult(it); });
  }

  // 聊天/频道/应用 with a typed query: matched objects on top, hashtag public
  // posts (for #tags) above them, and a 消息 message-results section below —
  // Telegram's combined layout.
  @Builder
  combinedResults() {
    Scroll() {
      Column() {
        if (this.visibleHashtagPosts().length > 0) {
          Row() {
            Text($r('app.string.gs_public_posts')).fontSize(14).fontWeight(FontWeight.Medium).fontColor(COLOR_TEXT_SECONDARY)
              .layoutWeight(1);
            Text($r('app.string.gs_show_more')).fontSize(14).fontColor(COLOR_PRIMARY)
              .onClick(() => {
                // Hashtag results expand into the official 帖子 category.
                this.controller.changeIndex(TAB_POSTS);
              });
          }.width('100%').padding({ left: 16, right: 16, top: 10, bottom: 6 });
          Column() {
            ForEach(this.visibleHashtagPosts().slice(0, 3), (it: FoundItem, idx: number) => {
              if (idx > 0) {
                Divider().color($r('app.color.divider')).strokeWidth(0.7)
                  .margin({ left: SEARCH_RESULT_DIVIDER_INSET });
              }
              this.msgRow(it);
            }, (it: FoundItem) =>
              `ht_${it.chatId}_${it.messageId}_${it.chatTitle}_${it.avatarPath}`);
          }.width('100%');
        }
        if (this.tab === TAB_APPS) {
          if (this.filteredAppResults().length > 0) {
            this.sectionHeader(str('gs_apps'));
          }
          Column() {
            ForEach(this.filteredAppResults(),
              (r: SearchRow, idx: number) => {
                this.appRow(r, idx > 0);
              }, (r: SearchRow) => `capp_${r.userId}_${r.title}_${r.subtitle}_${r.avatarPath}`);
          }.width('100%').backgroundColor($r('app.color.surface'));
          if (this.filteredAppResults().length === 0 &&
            (!this.appsLoaded || this.appsFailed ||
              this.apps.some((row: SearchRow) => row.title === ''))) {
            this.appSearchInlineState();
          }
        } else {
          if (this.filteredChatResults().length > 0) {
            this.sectionHeader(this.tab === TAB_CHANNELS ? str('gn_channel') : str('gs_chats_and_contacts'));
          }
          Column() {
            ForEach(this.filteredChatResults(),
              (r: SearchRow, idx: number) => {
                this.chatRow(r, idx > 0);
              }, (r: SearchRow) => `cres_${r.chatId}_${r.title}_${r.subtitle}_${r.avatarPath}`);
          }.width('100%').backgroundColor($r('app.color.surface'));
          if (this.filteredChatResults().length === 0 &&
            (this.chatSearching || this.chatSearchFailed)) {
            this.chatSearchInlineState();
          }
        }
        this.sectionHeader(str('cps_messages'));
        if (this.messageError !== '') {
          this.messageErrorState(true);
        } else if ((this.loading || this.resolvingMessageRows()) && this.visibleItems().length === 0) {
          this.messageLoadingState(true);
        } else {
          Column() {
            ForEach(this.visibleItems(), (it: FoundItem, idx: number) => {
              if (idx > 0) {
                Divider().color($r('app.color.divider')).strokeWidth(0.7)
                  .margin({ left: SEARCH_RESULT_DIVIDER_INSET });
              }
              this.msgRow(it);
            }, (it: FoundItem) =>
              `cm_${it.chatId}_${it.messageId}_${it.chatTitle}_${it.avatarPath}`);
          }.width('100%');
          if (this.visibleItems().length === 0 && this.searchedOnce && this.searchExhausted()) {
            Text($r('app.string.cp_no_messages_found')).fontSize(14).fontColor(COLOR_TEXT_SECONDARY)
              .width('100%').textAlign(TextAlign.Center).padding(16);
          }
          if (this.pagingBusy || this.pagingError ||
            (this.loadedPageCount > 1 && this.nextOffset === '')) {
            this.paginationFooter();
          }
        }
      }.width('100%');
    }
    .layoutWeight(1)
    .width('calc(100% - 24vp)')
    .margin({ left: 12, right: 12, top: 12, bottom: 12 })
    .align(Alignment.Top)
    .edgeEffect(EdgeEffect.Spring)
    .scrollBar(BarState.Off)
    .backgroundColor($r('app.color.surface'))
    .borderRadius(20)
    .clip(true)
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
          SymbolGlyph($r('sys.symbol.magnifyingglass')).fontSize(16).fontColor([Color.White]);
          Text(str('gs_search_for', this.query.trim()))
            .fontSize(16).fontWeight(FontWeight.Medium).fontColor(Color.White)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            .constraintSize({ maxWidth: 200 });
          SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(14).fontColor([Color.White]);
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
      .backgroundColor($r('app.color.surface'))
      .borderRadius(20);
    } else {
      List() {
        ForEach(this.visibleItems(), (it: FoundItem) => {
          ListItem() {
            this.msgRow(it);
          }
        }, (it: FoundItem) =>
          `${it.chatId}_${it.messageId}_${it.chatTitle}_${it.avatarPath}`);
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
      .backgroundColor($r('app.color.surface'))
      .borderRadius(20)
      .clip(true)
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
    if (idx === TAB_DOWNLOADS) {
      this.downloadsList();
    } else if (idx === TAB_APPS && this.query.trim() === '') {
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

  // 预览是页内浮层而不是独立路由，返回键要先关它，否则会直接退出搜索页。
  onBackPress(): boolean {
    if (this.previewItem !== null) {
      this.previewItem = null;
      return true;
    }
    return false;
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
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
    .backgroundColor($r('app.color.page_bg'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM]);

      if (this.previewItem !== null) {
        this.downloadPreviewOverlay(this.previewItem!);
      }
    }
    .width('100%').height('100%');
  }

  @Builder
  downloadPreviewOverlay(it: DownloadItem) {
    Column() {
      if (it.kind === 'video') {
        LocalVideoPlayer({
          videoPath: it.path,
          title: it.name,
          onClose: (): void => { this.previewItem = null; }
        });
      } else {
        AvatarViewer({
          imagePath: it.path,
          originX: this.previewTapX,
          originY: this.previewTapY,
          onClose: (): void => { this.previewItem = null; }
        });
      }
    }
    .width('100%').height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM]);
  }
}
