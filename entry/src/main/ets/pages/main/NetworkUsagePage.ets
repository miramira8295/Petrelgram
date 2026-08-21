import { router, promptAction } from '@kit.ArkUI';
import {
  NetworkUsage, NetworkBreakdown, formatBytes, formatDuration,
  getNetworkUsage, resetNetworkUsage
} from '../../store/StorageApi';
import { TdError } from '../../tdkit/TdTypes';
import {
  COLOR_DIVIDER, COLOR_PAGE_BG, COLOR_PRIMARY, COLOR_SURFACE,
  COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY
} from '../../util/theme';
import { str } from '../../util/strings';
import { fullDate } from '../../util/intlFormat';
import { LANGUAGE_EPOCH } from '../../util/appLanguage';
import { logE } from '../../util/log';
import { readableContentWidth } from '../../util/contentWidth';

const CARD_RADIUS: number = 14;
const DANGER: string = '#E64646';

@Entry
@Component
struct NetworkUsagePage {
  @StorageProp(LANGUAGE_EPOCH) langEpoch: number = 0;
  @StorageProp('topSafeHeight') topSafe: number = 0;
  @StorageProp('bottomSafeHeight') bottomSafe: number = 0;
  // 窗口宽（不是屏幕宽），限宽用。平板上把一列拉满 2880px 眼睛要横扫一行。
  @StorageProp('screenWidthVp') screenW: number = 360;
  @State usage: NetworkUsage | null = null;
  @State loading: boolean = true;
  @State refreshing: boolean = false;
  @State errorText: string = '';
  @State warning: string = '';
  @State resetting: boolean = false;
  private active: boolean = false;
  private sequence: number = 0;

  @Styles
  actionNormalStyle() {
    .backgroundColor(Color.Transparent).opacity(1).scale({ x: 1, y: 1 })
  }

  @Styles
  actionPressedStyle() {
    .backgroundColor($r('app.color.surface_alt')).opacity(0.74).scale({ x: 0.94, y: 0.94 })
  }

  aboutToAppear(): void { this.active = true; this.load(true); }
  aboutToDisappear(): void { this.active = false; this.sequence++; }

  private load(initial: boolean): void {
    const current = ++this.sequence;
    if (initial && this.usage === null) { this.loading = true; this.errorText = ''; }
    else { this.refreshing = true; this.warning = ''; }
    getNetworkUsage().then((value: NetworkUsage): void => {
      if (!this.active || current !== this.sequence) { return; }
      this.usage = value;
      this.loading = false;
      this.refreshing = false;
      this.errorText = '';
      this.warning = '';
    }).catch((error: TdError): void => {
      if (!this.active || current !== this.sequence) { return; }
      this.loading = false;
      this.refreshing = false;
      if (this.usage === null) { this.errorText = str('network_unreadable'); }
      else { this.warning = str('network_refresh_failed'); }
      logE(`NetworkUsagePage.load failed: ${error.message}`);
    });
  }

  private sinceLabel(): string {
    if (this.usage === null || this.usage.sinceDate <= 0) { return str('network_since_unknown'); }
    // The date goes through Intl, not into the resource string: "2026-8-6" is a
    // format, and English wants "Aug 6, 2026".
    return str('network_since', fullDate(new Date(this.usage.sinceDate * 1000)));
  }

  private reset(): void {
    if (this.resetting) { return; }
    promptAction.showDialog({
      title: $r('app.string.network_reset'), message: $r('app.string.network_reset_confirm'),
      buttons: [
        { text: $r('app.string.cancel'), color: COLOR_TEXT_SECONDARY as string },
        { text: $r('app.string.reset'), color: DANGER }
      ]
    }).then((result: promptAction.ShowDialogSuccessResponse): void => {
      if (result.index !== 1 || this.resetting) { return; }
      this.resetting = true;
      resetNetworkUsage().then((): void => {
        this.resetting = false;
        promptAction.showToast({ message: $r('app.string.network_reset_done'), duration: 1500 });
        this.load(false);
      }).catch((error: TdError): void => {
        this.resetting = false;
        logE(`NetworkUsagePage.reset failed: ${error.message}`);
        promptAction.showToast({ message: $r('app.string.reset_failed_retry'), duration: 1700 });
        this.load(false);
      });
    });
  }

  private maxTotal(items: NetworkBreakdown[]): number {
    let max = 1;
    for (const item of items) { max = Math.max(max, item.sent + item.received); }
    return max;
  }

  @Builder
  header() {
    Row({ space: 8 }) {
      Row() { SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(25).fontColor([COLOR_TEXT_PRIMARY]); }
      .width(44).height(44).borderRadius(22).justifyContent(FlexAlign.Center)
      .stateStyles({ normal: this.actionNormalStyle, pressed: this.actionPressedStyle })
      .onClick((): void => router.back());
      Text($r('app.string.network_title')).fontSize(22).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT_PRIMARY)
        .layoutWeight(1);
      Row() {
        if (this.refreshing) { LoadingProgress().width(18).height(18).color(COLOR_PRIMARY); }
        else { SymbolGlyph($r('sys.symbol.arrow_clockwise')).fontSize(20).fontColor([COLOR_PRIMARY]); }
      }.width(44).height(44).borderRadius(22).justifyContent(FlexAlign.Center)
      .enabled(!this.loading && !this.refreshing && !this.resetting)
      .stateStyles({ normal: this.actionNormalStyle, pressed: this.actionPressedStyle })
      .onClick((): void => this.load(false));
    }.width('100%').height(56).padding({ left: 8, right: 8 }).alignItems(VerticalAlign.Center);
  }

  @Builder
  summaryCard() {
    Column({ space: 14 }) {
      Text(this.sinceLabel()).fontSize(12).fontColor(COLOR_TEXT_SECONDARY).width('100%');
      Row({ space: 10 }) {
        Column({ space: 3 }) {
          Text($r('app.string.network_received')).fontSize(13).fontColor(COLOR_TEXT_SECONDARY);
          Text(this.usage !== null ? formatBytes(this.usage.received) : '—')
            .fontSize(23).fontWeight(FontWeight.Bold).fontColor(COLOR_PRIMARY);
        }.layoutWeight(1).alignItems(HorizontalAlign.Start);
        Divider().vertical(true).height(44).strokeWidth(0.5).color(COLOR_DIVIDER);
        Column({ space: 3 }) {
          Text($r('app.string.network_sent')).fontSize(13).fontColor(COLOR_TEXT_SECONDARY);
          Text(this.usage !== null ? formatBytes(this.usage.sent) : '—')
            .fontSize(23).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT_PRIMARY);
        }.layoutWeight(1).alignItems(HorizontalAlign.Start);
      }.width('100%');
      if (this.usage !== null && this.usage.callDuration > 0) {
        Row() {
          Text($r('app.string.network_total_calls')).fontSize(13).fontColor(COLOR_TEXT_SECONDARY).layoutWeight(1);
          Text(formatDuration(this.usage.callDuration)).fontSize(13).fontColor(COLOR_TEXT_PRIMARY);
        }.width('100%');
      }
    }.width('100%').padding(16).backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS);
  }

  @Builder
  breakdownRow(item: NetworkBreakdown, max: number) {
    Column({ space: 7 }) {
      Row() {
        Text(item.label).fontSize(15).fontColor(COLOR_TEXT_PRIMARY).layoutWeight(1);
        Text(formatBytes(item.sent + item.received)).fontSize(14).fontColor(COLOR_TEXT_SECONDARY);
      }.width('100%');
      Stack({ alignContent: Alignment.Start }) {
        Row().width('100%').height(6).borderRadius(3).backgroundColor($r('app.color.surface_alt'));
        Row().width(`${Math.max(2, Math.round(((item.sent + item.received) / max) * 100))}%`)
          .height(6).borderRadius(3).backgroundColor(COLOR_PRIMARY);
      }.width('100%').height(6);
      Row() {
        Text(`↓ ${formatBytes(item.received)}`).fontSize(11).fontColor(COLOR_PRIMARY);
        Text(`↑ ${formatBytes(item.sent)}`).fontSize(11).fontColor(COLOR_TEXT_SECONDARY)
          .margin({ left: 12 });
        Blank();
        if (item.duration > 0) {
          Text(formatDuration(item.duration)).fontSize(11).fontColor(COLOR_TEXT_SECONDARY);
        }
      }.width('100%');
    }.width('100%').padding({ left: 14, right: 14, top: 11, bottom: 11 });
  }

  @Builder
  breakdownCard(title: ResourceStr, items: NetworkBreakdown[]) {
    Column() {
      Text(title).fontSize(14).fontWeight(FontWeight.Medium).fontColor(COLOR_PRIMARY)
        .width('100%').padding({ left: 14, right: 14, top: 12, bottom: 6 });
      ForEach(items, (item: NetworkBreakdown, index: number) => {
        if (index > 0) { Divider().strokeWidth(0.5).color(COLOR_DIVIDER).margin({ left: 14 }); }
        this.breakdownRow(item, this.maxTotal(items));
      }, (item: NetworkBreakdown): string => item.key);
    }.width('100%').backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS);
  }

  @Builder
  loadingState() {
    Column({ space: 11 }) {
      LoadingProgress().width(34).height(34).color(COLOR_PRIMARY);
      Text($r('app.string.network_loading')).fontSize(15).fontColor(COLOR_TEXT_PRIMARY);
    }.width('100%').padding({ top: 72, bottom: 72 }).backgroundColor(COLOR_SURFACE)
      .borderRadius(CARD_RADIUS);
  }

  @Builder
  errorState() {
    Column({ space: 10 }) {
      SymbolGlyph($r('sys.symbol.exclamationmark_circle')).fontSize(34).fontColor([DANGER]);
      Text($r('app.string.network_load_failed')).fontSize(18).fontWeight(FontWeight.Medium).fontColor(COLOR_TEXT_PRIMARY);
      Text(this.errorText).fontSize(13).fontColor(COLOR_TEXT_SECONDARY);
      Text($r('app.string.settings_reload')).fontSize(14).fontColor(Color.White).padding({ left: 17, right: 17, top: 10, bottom: 10 })
        .backgroundColor(COLOR_PRIMARY).borderRadius(20).onClick((): void => this.load(true));
    }.width('100%').padding({ top: 54, bottom: 54 }).backgroundColor(COLOR_SURFACE)
      .borderRadius(CARD_RADIUS);
  }

  @Builder
  emptyState() {
    Column({ space: 9 }) {
      SymbolGlyph($r('sys.symbol.data_proportion')).fontSize(36).fontColor([COLOR_PRIMARY]);
      Text($r('app.string.network_empty')).fontSize(18).fontWeight(FontWeight.Medium).fontColor(COLOR_TEXT_PRIMARY);
      Text($r('app.string.network_empty_sub'))
        .fontSize(13).fontColor(COLOR_TEXT_SECONDARY).textAlign(TextAlign.Center);
    }.width('100%').padding({ top: 52, bottom: 52 }).backgroundColor(COLOR_SURFACE)
      .borderRadius(CARD_RADIUS);
  }

  build() {
    Column() {
      this.header();
      Scroll() {
        // 两层 Column 是故意的：外层铺满、负责居中，内层才是被限宽的内容。
        // 限宽如果加在 Scroll 上，滚动条和边缘回弹会跟着一起缩进来，侧边留白
        // 区域还会拖不动页面；做在里面则留白仍在 Scroll 的命中区，能拖。
        // 分类占比条按父宽的百分比算，跟着内层一起收窄，不用另外处理。
        Column() {
          Column({ space: 12 }) {
            if (this.warning !== '') {
              Text(this.warning).fontSize(12).fontColor('#FF9500').width('100%')
                .padding(10).backgroundColor('#12FF9500').borderRadius(10);
            }
            if (this.loading && this.usage === null) { this.loadingState(); }
            else if (this.errorText !== '' && this.usage === null) { this.errorState(); }
            else if (this.usage !== null && this.usage.sent + this.usage.received <= 0) {
              this.emptyState();
            } else if (this.usage !== null) {
              this.summaryCard();
              if (this.usage.byNetwork.length > 0) { this.breakdownCard($r('app.string.network_by_network'), this.usage.byNetwork); }
              if (this.usage.byCategory.length > 0) { this.breakdownCard($r('app.string.network_by_type'), this.usage.byCategory); }
            }
            Row({ space: 8 }) {
              if (this.resetting) { LoadingProgress().width(17).height(17).color(DANGER); }
              Text(this.resetting ? $r('app.string.resetting') : $r('app.string.network_reset'))
                .fontSize(15).fontColor(DANGER).fontWeight(FontWeight.Medium);
            }.width('100%').height(46).justifyContent(FlexAlign.Center)
              .backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS)
              .enabled(!this.resetting && !this.loading).onClick((): void => this.reset());
          }
          .width('100%')
          .constraintSize({ maxWidth: readableContentWidth(this.screenW) })
          .padding({ left: 12, right: 12, top: 6, bottom: this.bottomSafe + 24 });
        }
        .width('100%')
        // Column 默认左对齐：限了宽不居中就是把内容全堆在屏幕左边，比不限还难看。
        .alignItems(HorizontalAlign.Center);
      }.layoutWeight(1).width('100%').scrollBar(BarState.Off).edgeEffect(EdgeEffect.Spring);
    }.width('100%').height('100%').backgroundColor(COLOR_PAGE_BG)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .padding({ top: this.topSafe });
  }
}
