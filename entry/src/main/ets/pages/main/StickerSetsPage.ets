import { router, promptAction } from '@kit.ArkUI';
import { getTdClient } from '../../tdkit/Globals';
import { TdError, TdObject, TdRequest } from '../../tdkit/TdTypes';
import {
  getArchivedStickerSets, reorderInstalledStickerSets, searchInstalledStickerSets,
  setStickerSetInstalled
} from '../../store/StickerApi';
import {
  COLOR_PAGE_BG, COLOR_PRIMARY, COLOR_SURFACE, COLOR_TEXT_PRIMARY, COLOR_ICON_SECONDARY, COLOR_TEXT_SECONDARY
} from '../../util/theme';
import { plural, str } from '../../util/strings';
import { LANGUAGE_EPOCH } from '../../util/appLanguage';
import { logE } from '../../util/log';
import { HdsSubDestination } from '../common/HdsSubDestination';
import { KeyedListDataSource } from '../common/KeyedListDataSource';
import { guardKey } from '../../util/keyGuard';

const CARD_RADIUS: number = 14;

interface StickerSetRow {
  id: string;
  title: string;
  count: number;
  archived: boolean;
}

// 列表行的显示数据。能不能上移取决于它在已安装列表里的位置，所以放进行数据和 key：
// LazyForEach 下挪动之后，新的首行才会去掉上移按钮。
interface StickerSetItem {
  id: string;
  title: string;
  count: number;
  canMoveUp: boolean;
}

function stickerSetKey(item: StickerSetItem): string {
  return `${item.id}_${item.title}_${item.count}_${item.canMoveUp}`;
}

// 路由表（router_map.json）的 buildFunction 指向这里。系统在跳转时动态加载本模块
// 并调用它，页面因此不再进 main_pages.json——一个页面不能同时是 router 页和
// NavDestination。形状与试点的 PowerUsagePageBuilder 一致。
@Builder
export function StickerSetsPageBuilder(): void {
  StickerSetsPage();
}

@Component
export struct StickerSetsPage {
  private hdsScroller: Scroller = new Scroller();
  @StorageProp(LANGUAGE_EPOCH) langEpoch: number = 0;
  @StorageProp('topSafeHeight') topSafe: number = 0;
  @StorageProp('bottomSafeHeight') bottomSafe: number = 0;
  @State @Watch('syncInstalledData') installed: StickerSetRow[] = [];
  @State @Watch('syncArchivedData') archived: StickerSetRow[] = [];
  @State query: string = '';
  @State loadState: string = 'loading';
  @State busyId: string = '';
  private active: boolean = false;
  private searchTimer: number = -1;
  // 两张卡各自的 LazyForEach 数据源（见 syncInstalledData / syncArchivedData）。
  private installedData: KeyedListDataSource<StickerSetItem> = new KeyedListDataSource<StickerSetItem>('sticker-installed');
  private archivedData: KeyedListDataSource<StickerSetItem> = new KeyedListDataSource<StickerSetItem>('sticker-archived');

  aboutToAppear(): void {
    this.active = true;
    this.load();
  }

  aboutToDisappear(): void {
    this.active = false;
    if (this.searchTimer !== -1) { clearTimeout(this.searchTimer); }
  }

  private rowOf(set: TdObject): StickerSetRow {
    return {
      id: `${set['id']}`,
      title: (set['title'] as string | undefined) ?? '',
      count: (set['size'] as number | undefined) ?? 0,
      archived: (set['is_archived'] as boolean | undefined) ?? false
    };
  }

  private load(): void {
    this.loadState = 'loading';
    const req: TdRequest = { '@type': 'getInstalledStickerSets' };
    req['sticker_type'] = { '@type': 'stickerTypeRegular' } as TdObject;
    Promise.all([getTdClient().send(req), getArchivedStickerSets()])
      .then((results: Object[]): void => {
        if (!this.active) { return; }
        const installedRaw = ((results[0] as TdObject)['sets'] as TdObject[] | undefined) ?? [];
        this.installed = installedRaw.map((s: TdObject): StickerSetRow => this.rowOf(s));
        this.archived = (results[1] as TdObject[]).map((s: TdObject): StickerSetRow => this.rowOf(s));
        this.loadState = 'ready';
      }).catch((error: TdError): void => {
        if (!this.active) { return; }
        logE(`StickerSetsPage.load failed: ${error.message}`);
        this.loadState = 'error';
      });
  }

  private onQueryChange(value: string): void {
    this.query = value;
    if (this.searchTimer !== -1) { clearTimeout(this.searchTimer); }
    this.searchTimer = setTimeout((): void => {
      this.searchTimer = -1;
      if (value.trim() === '') {
        this.load();
        return;
      }
      searchInstalledStickerSets(value.trim()).then((sets: TdObject[]): void => {
        if (!this.active) { return; }
        this.installed = sets.map((s: TdObject): StickerSetRow => this.rowOf(s));
        this.loadState = 'ready';
      }).catch((): void => {});
    }, 280);
  }

  // Archive keeps the pack in the account (restorable) instead of deleting it.
  private setArchived(row: StickerSetRow, archived: boolean): void {
    if (this.busyId !== '') { return; }
    this.busyId = row.id;
    setStickerSetInstalled(row.id, !archived, archived).then((): void => {
      if (!this.active) { return; }
      this.busyId = '';
      promptAction.showToast({ message: archived ? $r('app.string.sticker_archived') : $r('app.string.sticker_restored'), duration: 1400 });
      this.load();
    }).catch((error: TdError): void => {
      if (!this.active) { return; }
      this.busyId = '';
      logE(`StickerSetsPage.archive failed: ${error.message}`);
      promptAction.showToast({ message: $r('app.string.action_failed_retry'), duration: 1600 });
    });
  }

  private remove(row: StickerSetRow): void {
    if (this.busyId !== '') { return; }
    this.busyId = row.id;
    setStickerSetInstalled(row.id, false, false).then((): void => {
      if (!this.active) { return; }
      this.busyId = '';
      promptAction.showToast({ message: $r('app.string.sticker_set_removed'), duration: 1400 });
      this.load();
    }).catch((): void => {
      if (!this.active) { return; }
      this.busyId = '';
      promptAction.showToast({ message: $r('app.string.remove_failed'), duration: 1500 });
    });
  }

  // Move one pack up; the whole order is then pushed to the server so it
  // syncs across devices.
  private moveUp(index: number): void {
    if (index <= 0 || this.busyId !== '') { return; }
    const next = this.installed.slice();
    const moved = next[index];
    next[index] = next[index - 1];
    next[index - 1] = moved;
    this.installed = next;
    reorderInstalledStickerSets(next.map((r: StickerSetRow): string => r.id))
      .catch((error: TdError): void => {
        logE(`StickerSetsPage.reorder failed: ${error.message}`);
        promptAction.showToast({ message: $r('app.string.sticker_reorder_failed'), duration: 1500 });
      });
  }

  private itemOf(row: StickerSetRow, canMoveUp: boolean): StickerSetItem {
    return { id: row.id, title: row.title, count: row.count, canMoveUp: canMoveUp };
  }

  // 两张卡的 LazyForEach 数据源同步（@Watch 触发）。
  private syncInstalledData(): void {
    const items: StickerSetItem[] = this.installed.map((r: StickerSetRow, index: number): StickerSetItem =>
      this.itemOf(r, index > 0));
    this.installedData.update(items,
      items.map((i: StickerSetItem): string => i.id),
      items.map((i: StickerSetItem): string => stickerSetKey(i)));
  }

  private syncArchivedData(): void {
    const items: StickerSetItem[] = this.archived.map((r: StickerSetRow): StickerSetItem => this.itemOf(r, false));
    this.archivedData.update(items,
      items.map((i: StickerSetItem): string => i.id),
      items.map((i: StickerSetItem): string => stickerSetKey(i)));
  }

  // 行内按钮只报 id（和行自己当下是否已归档）：两张卡共用一个复用池，节点上的回调不随
  // 新的一行更新，所以回调里不能写死是哪张卡、更不能攥行对象。这里按 id 找回当下那一项。
  private moveUpById(id: string): void {
    this.moveUp(this.installed.findIndex((r: StickerSetRow): boolean => r.id === id));
  }

  private toggleArchivedById(id: string, rowArchived: boolean): void {
    const source: StickerSetRow[] = rowArchived ? this.archived : this.installed;
    const row: StickerSetRow | undefined = source.find((r: StickerSetRow): boolean => r.id === id);
    if (row !== undefined) {
      this.setArchived(row, !rowArchived);
    }
  }

  private removeById(id: string): void {
    const row: StickerSetRow | undefined = this.installed.find((r: StickerSetRow): boolean => r.id === id);
    if (row !== undefined) {
      this.remove(row);
    }
  }

  build() {
    Column() {
    // 搜索框和三个状态分支一起包进来——只包 Scroll 那一支的话，加载态和
    // 搜索框就跑到标题栏外面去了。
    HdsSubDestination({
      title: $r('app.string.settings_stickers'),
      pageBackground: COLOR_PAGE_BG,
      scroller: this.hdsScroller
    }) {
      Column() {
      Row({ space: 8 }) {
        SymbolGlyph($r('sys.symbol.magnifyingglass')).fontSize(16).fontColor([COLOR_ICON_SECONDARY]);
        TextInput({ placeholder: $r('app.string.sticker_search'), text: this.query })
          .fontSize(15).layoutWeight(1).backgroundColor(Color.Transparent).padding(0)
          .onChange((value: string): void => this.onQueryChange(value));
      }
      .height(42).margin({ left: 12, right: 12, bottom: 8 }).padding({ left: 12, right: 12 })
      .backgroundColor(COLOR_SURFACE).borderRadius(14);
      if (this.loadState === 'loading') {
        Column({ space: 9 }) {
          LoadingProgress().width(32).height(32).color(COLOR_PRIMARY);
          Text($r('app.string.sticker_loading')).fontSize(13).fontColor(COLOR_TEXT_SECONDARY);
        }.layoutWeight(1).width('100%').justifyContent(FlexAlign.Center);
      } else if (this.loadState === 'error') {
        Column({ space: 10 }) {
          Text($r('app.string.load_failed')).fontSize(16).fontColor(COLOR_TEXT_PRIMARY);
          Button($r('app.string.settings_reload')).onClick((): void => this.load());
        }.layoutWeight(1).width('100%').justifyContent(FlexAlign.Center);
      } else {
        // 两张卡各是一个 ListItemGroup，行走 LazyForEach + 复用行（StickerSetRowView）；分隔线交给
        // 组的 divider（原来按 index > 0 在行内画，LazyForEach 下挪动后首行顶上会留一条）。
        List({ scroller: this.hdsScroller, space: 12 }) {
          ListItem() {
            Text(str('sticker_installed_count', this.installed.length)).fontSize(12)
              .fontColor(COLOR_TEXT_SECONDARY).width('100%').padding({ left: 4 });
          }
          ListItemGroup() {
            LazyForEach(this.installedData, (item: StickerSetItem) => {
              ListItem() {
                StickerSetRowView({
                  setId: item.id, title: item.title, stickerCount: item.count,
                  archived: false, canMoveUp: item.canMoveUp,
                  onMoveUp: (id: string): void => { this.moveUpById(id); },
                  onToggleArchive: (id: string, rowArchived: boolean): void => { this.toggleArchivedById(id, rowArchived); },
                  onRemove: (id: string): void => { this.removeById(id); }
                });
              }
            }, (item: StickerSetItem, index: number): string =>
              guardKey(this.installedData.keyTableId, index, stickerSetKey(item)));
          }
          .divider({ strokeWidth: 0.7, color: $r('app.color.divider'), startMargin: 14 })
          .width('100%').backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS);
          if (this.archived.length > 0) {
            ListItem() {
              Text(str('sticker_archived_count', this.archived.length)).fontSize(12)
                .fontColor(COLOR_TEXT_SECONDARY).width('100%').padding({ left: 4 });
            }
            ListItemGroup() {
              LazyForEach(this.archivedData, (item: StickerSetItem) => {
                ListItem() {
                  StickerSetRowView({
                    setId: item.id, title: item.title, stickerCount: item.count,
                    archived: true, canMoveUp: item.canMoveUp,
                    onMoveUp: (id: string): void => { this.moveUpById(id); },
                    onToggleArchive: (id: string, rowArchived: boolean): void => { this.toggleArchivedById(id, rowArchived); },
                    onRemove: (id: string): void => { this.removeById(id); }
                  });
                }
              }, (item: StickerSetItem, index: number): string =>
                guardKey(this.archivedData.keyTableId, index, stickerSetKey(item)));
            }
            .divider({ strokeWidth: 0.7, color: $r('app.color.divider'), startMargin: 14 })
            .width('100%').backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS);
          }
          ListItem() {
            Text($r('app.string.sticker_archive_note'))
              .fontSize(12).fontColor(COLOR_TEXT_SECONDARY).lineHeight(18).width('100%');
          }
        }
        .layoutWeight(1).width('100%').scrollBar(BarState.Off).cachedCount(4)
        .padding({ left: 12, right: 12 })
        // 底部留白原来是内容列的 padding（随内容滚动），在 List 上对应 contentEndOffset。
        .contentEndOffset(this.bottomSafe + 24)
        // 不裁剪，内容才能穿到标题栏底下——渐变模糊模糊的正是这部分。
        .clip(false);
      }
      }.width('100%').height('100%');
    }
    }.width('100%').height('100%');
  }
}

// 贴纸集的一行（原 setRow）。复用组件；三个按钮只报贴纸集 id（归档键再带上行自己的状态）。
@Reusable
@Component
struct StickerSetRowView {
  @Prop setId: string = '';
  @Prop title: string = '';
  @Prop stickerCount: number = 0;
  @Prop archived: boolean = false;
  @Prop canMoveUp: boolean = false;
  onMoveUp: (id: string) => void = (_id: string): void => {};
  onToggleArchive: (id: string, rowArchived: boolean) => void = (_id: string, _rowArchived: boolean): void => {};
  onRemove: (id: string) => void = (_id: string): void => {};

  build() {
    Row({ space: 10 }) {
      Column({ space: 2 }) {
        Text(this.title !== '' ? this.title : $r('app.string.sticker_set_untitled'))
          .fontSize(16).fontColor(COLOR_TEXT_PRIMARY)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
        Text(plural('sticker_set_count', this.stickerCount, this.stickerCount)).fontSize(11).fontColor(COLOR_TEXT_SECONDARY);
      }.layoutWeight(1).alignItems(HorizontalAlign.Start);
      if (!this.archived && this.canMoveUp) {
        Button() {
          SymbolGlyph($r('sys.symbol.arrow_up')).fontSize(16).fontColor([COLOR_ICON_SECONDARY]);
        }.width(34).height(34).backgroundColor(Color.Transparent)
        .onClick((): void => { this.onMoveUp(this.setId); });
      }
      Button() {
        SymbolGlyph(this.archived ? $r('sys.symbol.arrow_clockwise') : $r('sys.symbol.arrow_down_to_line'))
          .fontSize(16).fontColor([COLOR_PRIMARY]);
      }.width(34).height(34).backgroundColor(Color.Transparent)
      .onClick((): void => { this.onToggleArchive(this.setId, this.archived); });
      if (!this.archived) {
        Button() {
          SymbolGlyph($r('sys.symbol.trash')).fontSize(16).fontColor(['#E5484D']);
        }.width(34).height(34).backgroundColor(Color.Transparent)
        .onClick((): void => { this.onRemove(this.setId); });
      }
    }
    .width('100%').height(58).padding({ left: 14, right: 8 });
  }
}
