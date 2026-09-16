import { SymbolGlyphModifier } from '@kit.ArkUI';
import { KeyedListDataSource } from '../common/KeyedListDataSource';
import { DownloadCenterRow } from './DownloadCenterRow';
import { formatBytes } from '../../store/StorageApi';
import { guardKey } from '../../util/keyGuard';
import { str } from '../../util/strings';
import { COLOR_PRIMARY, COLOR_SURFACE, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY } from '../../util/theme';
import {
  DC_SECTION_ACTIVE, DC_SORT_SIZE, DC_STATE_COMPLETE, DC_STATE_WAITING_WIFI
} from '../../util/downloadCenterModel';
import {
  DC_ACTION_ALLOW_CELLULAR, DC_ACTION_CANCEL, DC_ACTION_DELETE, DC_ACTION_JUMP, DC_LAYOUT_GROUP, DC_LAYOUT_HEADER
} from '../../util/downloadCenterRows';
import { DcRowVM } from '../../util/downloadCenterRowVM';

// 下载中心一个页签的列表（2026-09-15；第四版行复用，第五版加折叠行、排序切换、长按菜单）。
//
// 单独做成 V2 组件，是因为行组件要 @ReusableV2 复用，而官方《@ReusableV2装饰器》的混用表写明：
// V1 普通组件不能包含 V2 复用组件（编译报错）——页面本身是 V1（HdsSubDestination 那一套）。
// 行数据是 DcRowVM（@ObservedV2）：key 只含身份 + 布局，进度、速度、勾选这些变化走 @Trace，不重建行；
// 布局即 reuseId。长按条目：定位到消息 / 用流量继续 / 删除缓存（或取消）。
// 滚到底报 onListEnd，由页面决定续不续拉下一页。

const PAGE_INSET: number = 16;
const SECTION_GAP: number = 18;
const ROW_RADIUS: number = 14;
const HAIRLINE: string = '1px';

@ComponentV2
export struct DownloadCenterList {
  @Require @Param source: KeyedListDataSource<DcRowVM>;
  @Param batch: boolean = false;
  @Param loading: boolean = false;
  @Param loadingMore: boolean = false;
  @Param empty: boolean = false;
  @Param endSpace: number = 32;
  @Event onRowTap: (itemId: string) => void = (_itemId: string): void => {};
  @Event onRowAction: (itemId: string, action: string) => void = (_itemId: string, _action: string): void => {};
  @Event onToggleAll: (pauseAll: boolean) => void = (_pauseAll: boolean): void => {};
  @Event onToggleSort: () => void = (): void => {};
  @Event onToggleGroup: () => void = (): void => {};
  @Event onListEnd: () => void = (): void => {};

  build() {
    List() {
      LazyForEach(this.source, (vm: DcRowVM) => {
        ListItem() {
          if (vm.layout === DC_LAYOUT_HEADER) {
            DownloadCenterSectionHeader({
              row: vm,
              onToggleAll: (pauseAll: boolean): void => { this.onToggleAll(pauseAll); },
              onToggleSort: (): void => { this.onToggleSort(); }
            });
          } else if (vm.layout === DC_LAYOUT_GROUP) {
            DownloadCenterGroupRow({ row: vm });
          } else {
            Column() {
              DownloadCenterRow({
                row: vm,
                batch: this.batch,
                onAction: (itemId: string, action: string): void => { this.onRowAction(itemId, action); }
              })
                .reuse({ reuseId: (): string => vm.layout });
            }
            .width('100%')
            .bindContextMenu(this.rowMenu(vm), ResponseType.LongPress);
          }
        }
        .width('100%')
        .padding({ left: PAGE_INSET, right: PAGE_INSET, bottom: vm.last ? SECTION_GAP : 0 })
        .onClick((): void => {
          if (vm.layout === DC_LAYOUT_GROUP) {
            this.onToggleGroup();
          } else if (vm.layout !== DC_LAYOUT_HEADER) {
            this.onRowTap(vm.itemId);
          }
        });
      }, (vm: DcRowVM, index: number): string => guardKey(this.source.keyTableId, index, `${vm.rowId}|${vm.layout}`))
      if (this.loadingMore) {
        ListItem() {
          Row() {
            LoadingProgress().width(24).height(24).color(COLOR_PRIMARY);
          }
          .width('100%')
          .justifyContent(FlexAlign.Center)
          .padding({ top: 8, bottom: 16 });
        }
      }
      if (this.empty && !this.loadingMore) {
        ListItem() {
          this.emptyState();
        }
      }
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.None)
    .nestedScroll({
      scrollForward: NestedScrollMode.PARENT_FIRST,
      scrollBackward: NestedScrollMode.SELF_FIRST
    })
    .cachedCount(4)
    .contentEndOffset(this.endSpace)
    .onReachEnd((): void => { this.onListEnd(); });
  }

  @Builder
  rowMenu(vm: DcRowVM) {
    Menu() {
      if (vm.canJump) {
        MenuItem({
          symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.arrow_up_right')),
          content: $r('app.string.dc_jump_to_message')
        }).onClick((): void => { this.onRowAction(vm.itemId, DC_ACTION_JUMP); });
      }
      if (vm.state === DC_STATE_WAITING_WIFI) {
        MenuItem({
          symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.arrow_down_circle')),
          content: $r('app.string.dc_allow_cellular')
        }).onClick((): void => { this.onRowAction(vm.itemId, DC_ACTION_ALLOW_CELLULAR); });
      }
      MenuItem({
        symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.trash')),
        content: vm.state === DC_STATE_COMPLETE ? $r('app.string.dc_delete_cache') : $r('app.string.dc_action_cancel')
      }).onClick((): void => {
        this.onRowAction(vm.itemId, vm.state === DC_STATE_COMPLETE ? DC_ACTION_DELETE : DC_ACTION_CANCEL);
      });
    }
  }

  @Builder
  emptyState() {
    Column({ space: 4 }) {
      if (this.loading) {
        LoadingProgress().width(32).height(32).color(COLOR_PRIMARY);
        Text($r('app.string.dc_loading')).fontSize(14).fontColor(COLOR_TEXT_SECONDARY).margin({ top: 8 });
      } else {
        SymbolGlyph($r('sys.symbol.magnifyingglass')).fontSize(44).fontColor([COLOR_TEXT_SECONDARY]).opacity(0.5);
        Text($r('app.string.dc_empty_title')).fontSize(14).fontColor(COLOR_TEXT_SECONDARY).margin({ top: 8 });
        Text($r('app.string.dc_empty_sub')).fontSize(12.5).fontColor(COLOR_TEXT_SECONDARY).opacity(0.8);
      }
    }
    .width('100%')
    .padding({ left: 30, right: 30, top: 60, bottom: 60 });
  }
}

// 段头：「进行中 · N」右边带「全部暂停 / 全部开始」，「已完成 · N」右边带「按时间 / 按大小」。
@ComponentV2
struct DownloadCenterSectionHeader {
  @Require @Param row: DcRowVM;
  @Event onToggleAll: (pauseAll: boolean) => void = (_pauseAll: boolean): void => {};
  @Event onToggleSort: () => void = (): void => {};

  build() {
    Row() {
      Text(this.row.section === DC_SECTION_ACTIVE
        ? str('dc_section_active_count', this.row.count) : str('dc_section_done_count', this.row.count))
        .fontSize(13).fontWeight(600).fontColor(COLOR_TEXT_SECONDARY)
        .layoutWeight(1);
      if (this.row.section === DC_SECTION_ACTIVE) {
        Text(this.row.anyDownloading ? $r('app.string.dc_pause_all') : $r('app.string.dc_start_all'))
          .fontSize(13).fontWeight(600).fontColor(COLOR_PRIMARY)
          .onClick((): void => { this.onToggleAll(this.row.anyDownloading); });
      } else if (this.row.sort !== '') {
        Text(this.row.sort === DC_SORT_SIZE ? $r('app.string.dc_sort_size') : $r('app.string.dc_sort_time'))
          .fontSize(13).fontWeight(600).fontColor(COLOR_PRIMARY)
          .onClick((): void => { this.onToggleSort(); });
      }
    }
    .width('100%')
    .padding({ left: 4, right: 4, top: 2, bottom: 8 });
  }
}

// 折叠行：来源不明的缓存（磁盘扫描出来、名字多半是一串数字）合成一行，点一下展开 / 收起。
@ComponentV2
struct DownloadCenterGroupRow {
  @Require @Param row: DcRowVM;

  build() {
    Column() {
      Row({ space: 11 }) {
        Row() {
          SymbolGlyph($r('sys.symbol.folder')).fontSize(22).fontColor(['#6B7A89']);
        }
        .width(44).height(44).borderRadius(12)
        .backgroundColor('#226B7A89')
        .justifyContent(FlexAlign.Center);
        Column({ space: 3 }) {
          Text(str('dc_group_unsourced', this.row.groupCount))
            .width('100%')
            .fontSize(14.5).fontWeight(600).fontColor(COLOR_TEXT_PRIMARY)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
          Text(str('dc_group_unsourced_sub', formatBytes(this.row.groupBytes)))
            .width('100%')
            .fontSize(12).fontColor(COLOR_TEXT_SECONDARY)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start);
        SymbolGlyph($r('sys.symbol.chevron_down')).fontSize(16).fontColor([COLOR_TEXT_SECONDARY])
          .rotate({ angle: this.row.expanded ? 180 : 0 });
      }
      .width('100%')
      .padding({ left: 14, right: 14, top: 12, bottom: 12 })
      .alignItems(VerticalAlign.Center);
      if (!this.row.last) {
        Divider().strokeWidth(HAIRLINE).color($r('app.color.dc_line'));
      }
    }
    .width('100%')
    .backgroundColor(COLOR_SURFACE)
    .borderWidth({
      left: HAIRLINE, right: HAIRLINE, top: this.row.first ? HAIRLINE : 0, bottom: this.row.last ? HAIRLINE : 0
    })
    .borderColor($r('app.color.dc_line'))
    .borderRadius({
      topLeft: this.row.first ? ROW_RADIUS : 0, topRight: this.row.first ? ROW_RADIUS : 0,
      bottomLeft: this.row.last ? ROW_RADIUS : 0, bottomRight: this.row.last ? ROW_RADIUS : 0
    })
    .clip(true);
  }
}
