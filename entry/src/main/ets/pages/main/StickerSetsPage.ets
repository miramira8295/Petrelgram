import { router, promptAction } from '@kit.ArkUI';
import { getTdClient } from '../../tdkit/Globals';
import { TdError, TdObject, TdRequest } from '../../tdkit/TdTypes';
import {
  getArchivedStickerSets, reorderInstalledStickerSets, searchInstalledStickerSets,
  setStickerSetInstalled
} from '../../store/StickerApi';
import {
  COLOR_PAGE_BG, COLOR_PRIMARY, COLOR_SURFACE, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY
} from '../../util/theme';
import { plural, str } from '../../util/strings';
import { LANGUAGE_EPOCH } from '../../util/appLanguage';

const CARD_RADIUS: number = 14;

interface StickerSetRow {
  id: string;
  title: string;
  count: number;
  archived: boolean;
}

@Entry
@Component
struct StickerSetsPage {
  @StorageProp(LANGUAGE_EPOCH) langEpoch: number = 0;
  @StorageProp('topSafeHeight') topSafe: number = 0;
  @StorageProp('bottomSafeHeight') bottomSafe: number = 0;
  @State installed: StickerSetRow[] = [];
  @State archived: StickerSetRow[] = [];
  @State query: string = '';
  @State loadState: string = 'loading';
  @State busyId: string = '';
  private active: boolean = false;
  private searchTimer: number = -1;

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
        console.error(`StickerSetsPage.load failed: ${error.message}`);
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
      console.error(`StickerSetsPage.archive failed: ${error.message}`);
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
        console.error(`StickerSetsPage.reorder failed: ${error.message}`);
        promptAction.showToast({ message: $r('app.string.sticker_reorder_failed'), duration: 1500 });
      });
  }

  @Builder
  header() {
    Row({ space: 8 }) {
      Button() {
        SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(24).fontColor([COLOR_TEXT_PRIMARY]);
      }.width(40).height(40).borderRadius(20).backgroundColor(Color.Transparent)
      .onClick((): void => { router.back(); });
      Text($r('app.string.settings_stickers')).fontSize(22).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT_PRIMARY)
        .layoutWeight(1);
      if (this.busyId !== '') { LoadingProgress().width(20).height(20).color(COLOR_PRIMARY); }
    }.width('100%').height(52).padding({ left: 8, right: 16 }).alignItems(VerticalAlign.Center);
  }

  @Builder
  setRow(row: StickerSetRow, index: number, isArchived: boolean) {
    Row({ space: 10 }) {
      Column({ space: 2 }) {
        Text(row.title !== '' ? row.title : $r('app.string.sticker_set_untitled'))
          .fontSize(16).fontColor(COLOR_TEXT_PRIMARY)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
        Text(plural('sticker_set_count', row.count, row.count)).fontSize(11).fontColor(COLOR_TEXT_SECONDARY);
      }.layoutWeight(1).alignItems(HorizontalAlign.Start);
      if (!isArchived && index > 0) {
        Button() {
          SymbolGlyph($r('sys.symbol.arrow_up')).fontSize(16).fontColor([COLOR_TEXT_SECONDARY]);
        }.width(34).height(34).backgroundColor(Color.Transparent)
        .onClick((): void => this.moveUp(index));
      }
      Button() {
        SymbolGlyph($r(isArchived ? 'sys.symbol.arrow_clockwise' : 'sys.symbol.arrow_down_to_line'))
          .fontSize(16).fontColor([COLOR_PRIMARY]);
      }.width(34).height(34).backgroundColor(Color.Transparent)
      .onClick((): void => this.setArchived(row, !isArchived));
      if (!isArchived) {
        Button() {
          SymbolGlyph($r('sys.symbol.trash')).fontSize(16).fontColor(['#E5484D']);
        }.width(34).height(34).backgroundColor(Color.Transparent)
        .onClick((): void => this.remove(row));
      }
    }
    .width('100%').height(58).padding({ left: 14, right: 8 });
  }

  build() {
    Column() {
      this.header();
      Row({ space: 8 }) {
        SymbolGlyph($r('sys.symbol.magnifyingglass')).fontSize(16).fontColor([COLOR_TEXT_SECONDARY]);
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
        Scroll() {
          Column({ space: 12 }) {
            Text(str('sticker_installed_count', this.installed.length)).fontSize(12)
              .fontColor(COLOR_TEXT_SECONDARY).width('100%').padding({ left: 4 });
            Column() {
              ForEach(this.installed, (row: StickerSetRow, index: number) => {
                if (index > 0) {
                  Divider().color($r('app.color.divider')).strokeWidth(0.7).margin({ left: 14 });
                }
                this.setRow(row, index, false);
              }, (row: StickerSetRow): string => `inst_${row.id}`);
            }.width('100%').backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS);
            if (this.archived.length > 0) {
              Text(str('sticker_archived_count', this.archived.length)).fontSize(12)
                .fontColor(COLOR_TEXT_SECONDARY).width('100%').padding({ left: 4 });
              Column() {
                ForEach(this.archived, (row: StickerSetRow, index: number) => {
                  if (index > 0) {
                    Divider().color($r('app.color.divider')).strokeWidth(0.7).margin({ left: 14 });
                  }
                  this.setRow(row, index, true);
                }, (row: StickerSetRow): string => `arch_${row.id}`);
              }.width('100%').backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS);
            }
            Text($r('app.string.sticker_archive_note'))
              .fontSize(12).fontColor(COLOR_TEXT_SECONDARY).lineHeight(18).width('100%');
          }.width('100%').padding({ left: 12, right: 12, bottom: this.bottomSafe + 24 });
        }.layoutWeight(1).width('100%').scrollBar(BarState.Off);
      }
    }
    .width('100%').height('100%').backgroundColor(COLOR_PAGE_BG)
    // 没有这一行时页面的布局区停在安全区边界，状态栏那一条不归页面画，
    // 露出的是窗口底色。padding 只负责把内容让开，铺满是另一回事。
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .padding({ top: this.topSafe });
  }
}
