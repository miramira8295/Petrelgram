import { common } from '@kit.AbilityKit';
import { promptAction } from '@kit.ArkUI';
import { HdsSubDestination } from '../common/HdsSubDestination';
import { KeyedListDataSource } from '../common/KeyedListDataSource';
import { initVideoPosterStore } from '../../util/videoPosterStore';
import { DownloadCenterList } from './DownloadCenterList';
import { DownloadCenterStorageCard } from './DownloadCenterStorageCard';
import { DownloadCenterStore } from '../../store/DownloadCenterStore';
import { formatBytes } from '../../store/StorageApi';
import { KEY_BG_CACHE_WIFI_ONLY, setBoolean } from '../../store/AppSettings';
import { onBackgroundCachePolicyChanged } from '../../services/BackgroundCache';
import { logChatNavFailure, navigateToChat } from '../../util/chatNav';
import { buildDownloadViewerSet, DownloadViewerSet } from '../../util/downloadViewerSet';
import { openLocalFile } from '../../util/openLocalFile';
import { str } from '../../util/strings';
import {
  accentSoft, COLOR_ON_PRIMARY, COLOR_PRIMARY, COLOR_SURFACE, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY
} from '../../util/theme';
import {
  DC_KIND_PHOTO, DC_KIND_VIDEO, DC_SORT_SIZE, DC_SORT_TIME, DC_SOURCE_MANAGER, DC_STATE_COMPLETE, DC_TAB_ALL, DC_TABS,
  DownloadCenterItem, displayNameOf, downloadCenterItemId, filterDownloadCenterItems, groupDownloadCenterItems
} from '../../util/downloadCenterModel';
import { dcKindLabel } from '../../util/downloadCenterLabels';
import {
  buildDownloadCenterRows, DC_ACTION_ALLOW_CELLULAR, DC_ACTION_CANCEL, DC_ACTION_DELETE, DC_ACTION_JUMP, DC_ACTION_OPEN,
  DC_ACTION_PAUSE, DC_ACTION_RESUME, DC_ACTION_RETRY, DC_ACTION_SAVE, DC_ACTION_SELECT, DcRow, DcRowOptions, dcRowId,
  dcRowLayout
} from '../../util/downloadCenterRows';
import { DcRowVM } from '../../util/downloadCenterRowVM';
import { shouldTopUp } from '../../util/downloadCenterPaging';
import { DeferredRemoval } from '../../util/deferredRemoval';
import { logE, logI } from '../../util/log';

// 下载中心（2026-09-15，设置 → 下载中心；第三版照 Claude Design「下载中心」稿，第四版行复用与分页，第五版补体验）。
//
// 从上到下：存储占用卡片（含「仅在 Wi‑Fi 下后台缓存」）→ 搜索框 → 胶囊类型页签（可横滑；内容区也能左右滑）→
// 「进行中」「已完成」两张卡片（已完成可按时间 / 大小排；「全部」页签里来源不明的缓存折成一行）。
// 标题栏右上角「选择」进批量模式（可全选），底部浮出批量操作条；取消 / 删除先藏起来给几秒「撤销」再真正执行。
// 长按条目：定位到消息 / 用流量继续 / 删除。返回键先退出批量模式。
//
// 滚动结构：外层 Scroll 装着卡片、搜索框、页签条和 Tabs；每个页签的列表（DownloadCenterList，V2）用 nestedScroll
// 让外层先滚——往上滑时存储卡片和搜索框先滚走，页签条停在顶上，再滚列表。Tabs 高度 = 外层视口高 - 页签条高。
//
// 刷新：每个页签按行身份各留一份 DcRowVM，数据变了原地改字段（@Trace），只重算当前页签和左右相邻的，
// 其余标脏、切过去时再算。分页：滑到底续拉；当前页签条目太少自动续拉；输入关键词、按大小排时把全部拉完。
// 数据见 store/DownloadCenterStore，行的切分见 util/downloadCenterRows，分页水位线见 util/downloadCenterPaging。

const PAGE_INSET: number = 16;
const PILL_BAR_HEIGHT: number = 48;
const LIST_END_SPACE: number = 32;
const BATCH_BAR_SPACE: number = 96;
const UNDO_BAR_SPACE: number = 56;
const DANGER_COLOR: string = '#E64646';
const MUTED_COLOR: string = '#8E8E93';
const UNDO_BAR_FILL: string = '#EB2C2C2E';
const UNDO_ACTION_COLOR: string = '#7CC4FF';

@Builder
export function DownloadCenterPageBuilder(): void {
  DownloadCenterPage();
}

@Component
export struct DownloadCenterPage {
  @StorageProp('bottomSafeHeight') private bottomSafe: number = 0;
  @StorageLink(KEY_BG_CACHE_WIFI_ONLY) private wifiOnly: boolean = true;
  @State private query: string = '';
  @State private currentTab: number = 0;
  @State private loading: boolean = true;
  @State private loadingMore: boolean = false;
  @State private batch: boolean = false;
  @State private selectedCount: number = 0;
  @State private cacheBytes: number = 0;
  @State private localBytes: number = 0;
  @State private freeBytes: number = -1;
  @State private clearing: boolean = false;
  @State private viewportHeight: number = 0;
  @State private sortMode: string = DC_SORT_TIME;
  @State private undoMessage: string = '';
  @State private tabItemCounts: number[] = DC_TABS.map((_t: string): number => 0);
  private unsourcedExpanded: boolean = false;
  private items: DownloadCenterItem[] = [];
  private selected: Set<string> = new Set<string>();
  private busy: Set<string> = new Set<string>();
  private dirtyTabs: Set<number> = new Set<number>();
  private navStack: NavPathStack | undefined = undefined;
  private tabsController: TabsController = new TabsController();
  private scroller: Scroller = new Scroller();
  private pillScroller: Scroller = new Scroller();
  private pillXs: number[] = DC_TABS.map((_t: string): number => 0);
  private pillWs: number[] = DC_TABS.map((_t: string): number => 0);
  private pillViewportWidth: number = 0;
  private sources: KeyedListDataSource<DcRowVM>[] =
    DC_TABS.map((t: string): KeyedListDataSource<DcRowVM> => new KeyedListDataSource<DcRowVM>(`dc-${t}`));
  private rowModels: Map<string, DcRowVM>[] =
    DC_TABS.map((_t: string): Map<string, DcRowVM> => new Map<string, DcRowVM>());
  private removal: DeferredRemoval = new DeferredRemoval((): void => { this.onRemovalChanged(); });
  private store: DownloadCenterStore = new DownloadCenterStore((): void => { this.onStoreChanged(); });

  aboutToAppear(): void {
    // 视频海报的缓存目录。组件自己不取 context，由页面初始化一次（见 util/videoPosterStore）。
    initVideoPosterStore(this.ctx().cacheDir);
    this.store.load(this.ctx());
  }

  aboutToDisappear(): void {
    // 等撤销的那一批离开页面就执行：用户看到的是「已删除」，不能因为离开页面就当没发生。
    this.removal.flush();
    this.store.dispose();
  }

  private ctx(): common.UIAbilityContext {
    return getContext(this) as common.UIAbilityContext;
  }

  // —— 数据 ——

  private onStoreChanged(): void {
    this.items = this.store.items();
    this.loading = this.store.loading;
    this.loadingMore = this.store.loadingMore;
    this.cacheBytes = this.store.totalCacheBytes;
    this.localBytes = this.store.savedBytes;
    this.freeBytes = this.store.freeBytes;
    this.removal.forgetMissing(new Set<string>(this.items.map((it: DownloadCenterItem): string => downloadCenterItemId(it))));
    this.pruneSelection();
    this.syncVisibleTabs();
    this.maybeTopUp();
  }

  private onRemovalChanged(): void {
    this.undoMessage = this.removal.message();
    this.markAllDirty();
    this.syncVisibleTabs();
  }

  // 等撤销的条目先从列表里藏起来。
  private visibleItems(): DownloadCenterItem[] {
    return this.items.filter((it: DownloadCenterItem): boolean => !this.removal.isHidden(downloadCenterItemId(it)));
  }

  private rowOptions(tabIndex: number): DcRowOptions {
    return {
      batch: this.batch, selectedIds: this.selected, sort: this.sortMode,
      collapseUnsourced: DC_TABS[tabIndex] === DC_TAB_ALL, unsourcedExpanded: this.unsourcedExpanded
    };
  }

  // 只算当前页签和左右相邻的（左右滑时要看得到），其余标脏。
  private syncVisibleTabs(): void {
    const base: DownloadCenterItem[] = this.visibleItems();
    const counts: number[] = this.tabItemCounts.slice();
    for (let i = 0; i < DC_TABS.length; i++) {
      if (Math.abs(i - this.currentTab) <= 1) {
        this.syncTab(i, base, counts);
        this.dirtyTabs.delete(i);
      } else {
        this.dirtyTabs.add(i);
      }
    }
    this.tabItemCounts = counts;
  }

  private syncDirtyNeighbors(): void {
    const base: DownloadCenterItem[] = this.visibleItems();
    const counts: number[] = this.tabItemCounts.slice();
    let changed: boolean = false;
    for (let i = Math.max(0, this.currentTab - 1); i <= Math.min(DC_TABS.length - 1, this.currentTab + 1); i++) {
      if (this.dirtyTabs.has(i)) {
        this.syncTab(i, base, counts);
        this.dirtyTabs.delete(i);
        changed = true;
      }
    }
    if (changed) {
      this.tabItemCounts = counts;
    }
  }

  // 同一身份、同一布局的行沿用原来的 DcRowVM（原地改字段）；布局变了换新对象，key 跟着变。
  private syncTab(i: number, base: DownloadCenterItem[], counts: number[]): void {
    const filtered: DownloadCenterItem[] = filterDownloadCenterItems(base, DC_TABS[i], this.query);
    const rows: DcRow[] = buildDownloadCenterRows(groupDownloadCenterItems(filtered, this.sortMode), this.rowOptions(i));
    const prev: Map<string, DcRowVM> = this.rowModels[i];
    const next: Map<string, DcRowVM> = new Map<string, DcRowVM>();
    const models: DcRowVM[] = [];
    const ids: string[] = [];
    const keys: string[] = [];
    for (const r of rows) {
      const id: string = dcRowId(r);
      const layout: string = dcRowLayout(r);
      const known: DcRowVM | undefined = prev.get(id);
      const vm: DcRowVM = known !== undefined && known.layout === layout ? known : new DcRowVM(id, layout);
      vm.apply(r);
      next.set(id, vm);
      models.push(vm);
      ids.push(id);
      keys.push(`${id}|${layout}`);
    }
    this.rowModels[i] = next;
    this.sources[i].update(models, ids, keys);
    counts[i] = filtered.length;
  }

  private markAllDirty(): void {
    for (let i = 0; i < DC_TABS.length; i++) {
      this.dirtyTabs.add(i);
    }
  }

  private findItem(id: string): DownloadCenterItem | undefined {
    return this.items.find((it: DownloadCenterItem): boolean => downloadCenterItemId(it) === id);
  }

  // —— 分页、排序、折叠 ——

  private maybeTopUp(): void {
    if (shouldTopUp(this.tabItemCounts[this.currentTab], this.store.hasMore(),
      this.store.loading || this.store.loadingMore)) {
      this.store.loadMore(this.ctx());
    }
  }

  private onListEnd(): void {
    if (this.store.hasMore()) {
      this.store.loadMore(this.ctx());
    }
  }

  private onQueryChanged(value: string): void {
    this.query = value;
    if (value.trim() !== '') {
      this.store.loadAll(this.ctx());
    }
    this.markAllDirty();
    this.syncVisibleTabs();
  }

  // 按大小排要看全部：把各路翻到底。
  private toggleSort(): void {
    this.sortMode = this.sortMode === DC_SORT_SIZE ? DC_SORT_TIME : DC_SORT_SIZE;
    if (this.sortMode === DC_SORT_SIZE) {
      this.store.loadAll(this.ctx());
    }
    this.markAllDirty();
    this.syncVisibleTabs();
  }

  private toggleUnsourced(): void {
    this.unsourcedExpanded = !this.unsourcedExpanded;
    this.markAllDirty();
    this.syncVisibleTabs();
  }

  private setWifiOnly(on: boolean): void {
    setBoolean(KEY_BG_CACHE_WIFI_ONLY, on);
    onBackgroundCachePolicyChanged();
  }

  // —— 页签 ——

  private pickTab(index: number): void {
    if (index !== this.currentTab) {
      this.tabsController.changeIndex(index);
    }
  }

  private onTabChanged(index: number): void {
    this.currentTab = index;
    this.syncDirtyNeighbors();
    this.maybeTopUp();
    const x: number = this.pillXs[index];
    const w: number = this.pillWs[index];
    if (w > 0 && this.pillViewportWidth > 0) {
      this.pillScroller.scrollTo({
        xOffset: Math.max(0, x + w / 2 - this.pillViewportWidth / 2), yOffset: 0,
        animation: { duration: 250, curve: Curve.EaseOut }
      });
    }
  }

  // —— 批量选择 ——

  private toggleBatch(): void {
    this.batch = !this.batch;
    this.setSelection(new Set<string>());
  }

  private leaveBatchOnBack(): boolean {
    if (!this.batch) {
      return false;
    }
    this.toggleBatch();
    return true;
  }

  private toggleSelect(id: string): void {
    const next: Set<string> = new Set<string>(this.selected);
    if (next.has(id)) {
      next.delete(id);
    } else {
      next.add(id);
    }
    this.setSelection(next);
  }

  private setSelection(next: Set<string>): void {
    this.selected = next;
    this.selectedCount = next.size;
    this.markAllDirty();
    this.syncVisibleTabs();
  }

  private tabItemIds(): string[] {
    return filterDownloadCenterItems(this.visibleItems(), DC_TABS[this.currentTab], this.query)
      .map((it: DownloadCenterItem): string => downloadCenterItemId(it));
  }

  private allSelectedInTab(): boolean {
    const ids: string[] = this.tabItemIds();
    return ids.length > 0 && ids.every((id: string): boolean => this.selected.has(id));
  }

  // 全选 = 当前页签（含搜索条件）里已加载的全部条目；再点一次取消。
  private toggleSelectAll(): void {
    this.setSelection(this.allSelectedInTab() ? new Set<string>() : new Set<string>(this.tabItemIds()));
  }

  // 条目没了（取消、删除、清理缓存）就从选中里剔掉。
  private pruneSelection(): void {
    if (this.selected.size === 0) {
      return;
    }
    const next: Set<string> = new Set<string>();
    for (const it of this.items) {
      const id: string = downloadCenterItemId(it);
      if (this.selected.has(id)) {
        next.add(id);
      }
    }
    this.selected = next;
    this.selectedCount = next.size;
  }

  private selectedItems(): DownloadCenterItem[] {
    return this.items.filter((it: DownloadCenterItem): boolean => this.selected.has(downloadCenterItemId(it)));
  }

  private batchSave(): void {
    this.store.saveBatchToLocal(this.ctx(), this.selectedItems()).then((n: number): void => {
      if (n > 0) {
        promptAction.showToast({ message: str('dc_saved_n', n), duration: 1800 });
      }
      this.setSelection(new Set<string>());
    }).catch((e: Object): void => { this.reportFailure('batchSave', e); });
  }

  private batchDelete(): void {
    const picked: DownloadCenterItem[] = this.selectedItems();
    if (picked.length === 0) {
      return;
    }
    this.setSelection(new Set<string>());
    this.deferRemoval(picked, str('dc_deleted_n', picked.length),
      (): Promise<void> => this.store.deleteBatch(picked).then((_n: number): void => {}));
  }

  // 取消 / 删除先藏起来给「撤销」，过几秒（或下一次删除、离开页面）才真正执行；失败放回列表。
  private deferRemoval(items: DownloadCenterItem[], message: string, run: () => Promise<void>): void {
    const ids: string[] = items.map((it: DownloadCenterItem): string => downloadCenterItemId(it));
    this.removal.schedule({
      ids: ids,
      message: message,
      commit: (): void => {
        run().catch((e: Object): void => {
          this.removal.restore(ids);
          this.reportFailure('remove', e);
        });
      }
    });
  }

  // —— 行操作 ——

  private onRowTap(itemId: string): void {
    const it: DownloadCenterItem | undefined = this.findItem(itemId);
    if (it === undefined) {
      return;
    }
    if (this.batch) {
      this.toggleSelect(itemId);
    } else {
      this.openItem(it);
    }
  }

  private onRowAction(itemId: string, action: string): void {
    const it: DownloadCenterItem | undefined = this.findItem(itemId);
    if (it === undefined) {
      return;
    }
    if (action === DC_ACTION_SELECT) {
      this.toggleSelect(itemId);
      return;
    }
    if (action === DC_ACTION_OPEN) {
      this.openItem(it);
      return;
    }
    if (action === DC_ACTION_JUMP) {
      this.jumpToMessage(it);
      return;
    }
    if (action === DC_ACTION_CANCEL) {
      this.deferRemoval([it], str('dc_cancelled', this.itemTitle(it)), (): Promise<void> => this.store.cancel(it));
      return;
    }
    if (action === DC_ACTION_DELETE) {
      this.deferRemoval([it], it.savedLocal ? str('dc_cache_deleted_keep_local') : str('dc_cache_deleted'),
        (): Promise<void> => this.store.deleteCache(it));
      return;
    }
    const key: string = `${itemId}|${action}`;
    if (this.busy.has(key)) {
      return;
    }
    this.busy.add(key);
    this.runAction(it, action).catch((e: Object): void => {
      this.reportFailure(action, e);
    }).finally((): void => { this.busy.delete(key); });
  }

  private runAction(it: DownloadCenterItem, action: string): Promise<void> {
    if (action === DC_ACTION_PAUSE) {
      return this.store.pause(it);
    }
    if (action === DC_ACTION_RESUME || action === DC_ACTION_RETRY) {
      return this.store.resume(this.ctx(), it);
    }
    if (action === DC_ACTION_ALLOW_CELLULAR) {
      return this.store.allowCellular(this.ctx(), it);
    }
    if (action === DC_ACTION_SAVE) {
      return this.store.saveToLocal(this.ctx(), it).then((_saved: boolean): void => {});
    }
    return Promise.resolve();
  }

  private jumpToMessage(it: DownloadCenterItem): void {
    if (it.chatId === 0 || it.messageId === 0) {
      return;
    }
    const params: Record<string, Object> = { 'chatId': it.chatId, 'jumpTo': it.messageId };
    navigateToChat(params).catch(logChatNavFailure);
  }

  private reportFailure(action: string, e: Object): void {
    logE(`DownloadCenter.${action} failed: ${JSON.stringify(e)}`);
    promptAction.showToast({ message: str('dc_action_failed'), duration: 1800 });
  }

  private itemTitle(it: DownloadCenterItem): string {
    const named: string = displayNameOf(it.name);
    return named !== '' ? named : dcKindLabel(it.kind);
  }

  private toggleAll(pauseAll: boolean): void {
    this.store.toggleAll(this.ctx(), pauseAll).catch((e: Object): void => { this.reportFailure('toggleAll', e); });
  }

  private askClearCache(): void {
    promptAction.showDialog({
      title: str('dc_clear_cache'),
      message: str('dc_clear_cache_confirm'),
      buttons: [
        { text: $r('app.string.cancel'), color: MUTED_COLOR },
        { text: $r('app.string.dc_clear_cache_action'), color: DANGER_COLOR }
      ]
    }).then((res: promptAction.ShowDialogSuccessResponse): void => {
      if (res.index === 1) {
        this.clearCache();
      }
    }).catch((_e: Object): void => {});
  }

  private clearCache(): void {
    this.clearing = true;
    this.store.clearAllCache(this.ctx()).then((freed: number): void => {
      promptAction.showToast({ message: str('dc_cache_cleared', formatBytes(freed)), duration: 1800 });
    }).catch((e: Object): void => {
      this.reportFailure('clearCache', e);
    }).finally((): void => { this.clearing = false; });
  }

  // 点条目：完整的图片视频进聊天的媒体查看器（当前页签同类可左右滑），完整的其它文件交给系统应用；
  // 没下完的视频边缓存边播，其它的接着缓存。
  private openItem(it: DownloadCenterItem): void {
    logI(`[DC] open kind=${it.kind} state=${it.state} source=${it.source} path=${it.path !== ''} ` +
      `file=${it.fileId} stack=${this.navStack !== undefined}`);
    if (it.state === DC_STATE_COMPLETE && it.path !== '') {
      // 进不了查看器的（磁盘扫出来、没有 fileId 的视频）同其它文件一样交给系统应用。
      if ((it.kind === DC_KIND_PHOTO || it.kind === DC_KIND_VIDEO) && this.pushViewer(it)) {
        return;
      }
      openLocalFile(this.ctx(), it.path, it.mimeType).then((ok: boolean): void => {
        if (!ok) {
          promptAction.showToast({ message: str('media_file_unavailable'), duration: 1800 });
        }
      });
      return;
    }
    if (it.fileId === 0) {
      return;
    }
    if (it.kind === DC_KIND_VIDEO) {
      if (it.source !== DC_SOURCE_MANAGER) {
        this.store.resume(this.ctx(), it).catch((e: Object): void => { this.reportFailure('resume', e); });
      }
      this.pushViewer(it);
      return;
    }
    this.store.resume(this.ctx(), it).catch((e: Object): void => { this.reportFailure('resume', e); });
  }

  // 推聊天的媒体查看器（pages/main/DownloadPreviewPage）：当前页签 + 搜索下能看的图片 / 视频拼成一组，从点的这一项开始
  // （util/downloadViewerSet）。返回 false = 这一项进不了查看器，由调用方兜底。
  private pushViewer(it: DownloadCenterItem): boolean {
    const stack: NavPathStack | undefined = this.navStack;
    if (stack === undefined) {
      logE('[DC] viewer: navStack missing');
      return false;
    }
    const set: DownloadViewerSet | null =
      buildDownloadViewerSet(this.visibleItems(), it, DC_TABS[this.currentTab], this.query, this.sortMode);
    if (set === null) {
      return false;
    }
    const param: Record<string, Object> = { 'items': set.items, 'startIndex': set.startIndex };
    stack.pushPathByName('DownloadPreviewPage', param);
    return true;
  }

  private listEndSpace(): number {
    return (this.batch ? BATCH_BAR_SPACE : LIST_END_SPACE) + (this.undoMessage !== '' ? UNDO_BAR_SPACE : 0) +
      this.bottomSafe;
  }

  build() {
    HdsSubDestination({
      title: $r('app.string.dc_title'),
      scroller: this.scroller,
      actionIcon: this.batch ? $r('sys.symbol.checkmark') : $r('sys.symbol.checkmark_circle'),
      actionLabel: this.batch ? $r('app.string.dc_batch_done') : $r('app.string.dc_batch_select'),
      onAction: (): void => { this.toggleBatch(); },
      onBackPressed: (): boolean => this.leaveBatchOnBack(),
      onNavStack: (stack: NavPathStack): void => { this.navStack = stack; }
    }) {
      Stack({ alignContent: Alignment.Bottom }) {
        Scroll(this.scroller) {
          Column() {
            Column() {
              DownloadCenterStorageCard({
                cacheBytes: this.cacheBytes, localBytes: this.localBytes, freeBytes: this.freeBytes,
                clearing: this.clearing, wifiOnly: this.wifiOnly,
                onClear: (): void => { this.askClearCache(); },
                onWifiOnlyChange: (on: boolean): void => { this.setWifiOnly(on); }
              });
            }
            .width('100%')
            .padding({ left: PAGE_INSET, right: PAGE_INSET, top: 6, bottom: 12 });
            Column() {
              Search({ value: this.query, placeholder: $r('app.string.dc_search_hint') })
                .width('100%')
                .height(40)
                .backgroundColor(COLOR_SURFACE)
                .borderRadius(12)
                .borderWidth('1px')
                .borderColor($r('app.color.dc_line'))
                .placeholderColor(COLOR_TEXT_SECONDARY)
                .fontColor(COLOR_TEXT_PRIMARY)
                .textFont({ size: 14.5 })
                .searchIcon({ size: 16, color: COLOR_TEXT_SECONDARY })
                .cancelButton({ style: CancelButtonStyle.INPUT })
                .onChange((value: string): void => { this.onQueryChanged(value); });
            }
            .width('100%')
            .padding({ left: PAGE_INSET, right: PAGE_INSET, bottom: 12 });
            this.pillBar();
            Tabs({ controller: this.tabsController, index: this.currentTab }) {
              ForEach(DC_TABS, (_tab: string, i: number) => {
                TabContent() {
                  DownloadCenterList({
                    source: this.sources[i],
                    batch: this.batch,
                    loading: this.loading,
                    loadingMore: this.loadingMore,
                    empty: this.tabItemCounts[i] === 0,
                    endSpace: this.listEndSpace(),
                    onRowTap: (itemId: string): void => { this.onRowTap(itemId); },
                    onRowAction: (itemId: string, action: string): void => { this.onRowAction(itemId, action); },
                    onToggleAll: (pauseAll: boolean): void => { this.toggleAll(pauseAll); },
                    onToggleSort: (): void => { this.toggleSort(); },
                    onToggleGroup: (): void => { this.toggleUnsourced(); },
                    onListEnd: (): void => { this.onListEnd(); }
                  });
                }
              }, (tab: string): string => tab)
            }
            .barHeight(0)
            .width('100%')
            .height(Math.max(0, this.viewportHeight - PILL_BAR_HEIGHT))
            .onChange((index: number): void => { this.onTabChanged(index); });
          }
          .width('100%');
        }
        .width('100%')
        .height('100%')
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
        .onAreaChange((_old: Area, area: Area): void => { this.viewportHeight = area.height as number; });
        if (this.undoMessage !== '' || this.batch) {
          Column({ space: 8 }) {
            if (this.undoMessage !== '') {
              this.undoBar();
            }
            if (this.batch) {
              this.batchBar();
            }
          }
          .width('100%')
          .padding({ left: PAGE_INSET, right: PAGE_INSET, bottom: 18 + this.bottomSafe })
          .hitTestBehavior(HitTestMode.Transparent);
        }
      }
      .width('100%')
      .height('100%');
    }
  }

  @Builder
  pillBar() {
    Scroll(this.pillScroller) {
      Row({ space: 8 }) {
        ForEach(DC_TABS, (tab: string, i: number) => {
          Text(dcKindLabel(tab))
            .fontSize(13.5)
            .fontWeight(600)
            .fontColor(this.currentTab === i ? COLOR_ON_PRIMARY : COLOR_TEXT_PRIMARY)
            .backgroundColor(this.currentTab === i ? COLOR_PRIMARY : $r('app.color.dc_chip'))
            .padding({ left: 14, right: 14, top: 7, bottom: 7 })
            .borderRadius(18)
            .onAreaChange((_old: Area, area: Area): void => {
              this.pillXs[i] = area.position.x as number;
              this.pillWs[i] = area.width as number;
            })
            .onClick((): void => { this.pickTab(i); });
        }, (tab: string): string => tab)
      }
      .padding({ left: PAGE_INSET, right: PAGE_INSET, top: 2, bottom: 13 });
    }
    .width('100%')
    .height(PILL_BAR_HEIGHT)
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .onAreaChange((_old: Area, area: Area): void => { this.pillViewportWidth = area.width as number; });
  }

  @Builder
  undoBar() {
    Row({ space: 12 }) {
      Text(this.undoMessage)
        .fontSize(13.5).fontColor(Color.White)
        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1);
      Text($r('app.string.dc_undo'))
        .fontSize(13.5).fontWeight(600).fontColor(UNDO_ACTION_COLOR)
        .padding({ left: 8, right: 4, top: 4, bottom: 4 })
        .onClick((): void => { this.removal.undo(); });
    }
    .width('100%')
    .padding({ left: 16, right: 12, top: 11, bottom: 11 })
    .backgroundColor(UNDO_BAR_FILL)
    .borderRadius(14)
    .shadow({ radius: 12, color: '#33000000', offsetY: 6 });
  }

  @Builder
  batchBar() {
    Row({ space: 8 }) {
      Text(this.selectedCount > 0 && this.allSelectedInTab()
        ? $r('app.string.dc_deselect_all') : $r('app.string.dc_select_all'))
        .fontSize(13).fontWeight(600).fontColor(COLOR_PRIMARY)
        .onClick((): void => { this.toggleSelectAll(); });
      Text(str('dc_selected_count', this.selectedCount))
        .fontSize(13).fontColor(COLOR_TEXT_SECONDARY)
        .layoutWeight(1);
      Button($r('app.string.dc_batch_save'))
        .height(34)
        .padding({ left: 13, right: 13 })
        .fontSize(13).fontWeight(600)
        .fontColor(COLOR_PRIMARY)
        .backgroundColor(accentSoft())
        .enabled(this.selectedCount > 0)
        .onClick((): void => { this.batchSave(); });
      Button($r('app.string.dc_batch_delete'))
        .height(34)
        .padding({ left: 13, right: 13 })
        .fontSize(13).fontWeight(600)
        .fontColor($r('app.color.dc_err'))
        .backgroundColor($r('app.color.dc_err_soft'))
        .enabled(this.selectedCount > 0)
        .onClick((): void => { this.batchDelete(); });
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 10, bottom: 10 })
    .backgroundColor(COLOR_SURFACE)
    .borderRadius(16)
    .borderWidth('1px')
    .borderColor($r('app.color.dc_line'))
    .shadow({ radius: 17, color: '#38000000', offsetY: 10 });
  }
}
