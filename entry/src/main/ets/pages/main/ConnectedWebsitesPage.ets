import { router, promptAction } from '@kit.ArkUI';
import { TdError } from '../../tdkit/TdTypes';
import {
  ConnectedWebsite, disconnectAllWebsites, disconnectWebsite, getConnectedWebsites
} from '../../store/PrivacyApi';
import {
  COLOR_PAGE_BG, COLOR_PRIMARY, COLOR_SURFACE,
  COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY
} from '../../util/theme';
import { plural, str } from '../../util/strings';
import { LANGUAGE_EPOCH } from '../../util/appLanguage';
import { logE } from '../../util/log';
import { readableContentWidth } from '../../util/contentWidth';

const CARD_RADIUS: number = 16;
const COLOR_DANGER: string = '#E5484D';

@Entry
@Component
struct ConnectedWebsitesPage {
  @StorageProp(LANGUAGE_EPOCH) langEpoch: number = 0;
  @StorageProp('topSafeHeight') topSafe: number = 0;
  @StorageProp('bottomSafeHeight') bottomSafe: number = 0;
  // 窗口宽（不是屏幕宽），限宽用。平板上把一列拉满 2880px 眼睛要横扫一行。
  @StorageProp('screenWidthVp') screenW: number = 360;
  @State loadState: string = 'loading';
  @State websites: ConnectedWebsite[] = [];
  @State actionKey: string = '';
  private active: boolean = false;
  private sequence: number = 0;

  aboutToAppear(): void {
    this.active = true;
    this.load();
  }

  aboutToDisappear(): void {
    this.active = false;
    this.sequence++;
  }

  private load(): void {
    const sequence = ++this.sequence;
    this.loadState = 'loading';
    getConnectedWebsites().then((rows: ConnectedWebsite[]): void => {
      if (!this.active || sequence !== this.sequence) { return; }
      this.websites = rows.sort((a: ConnectedWebsite, b: ConnectedWebsite): number =>
        b.lastActiveDate - a.lastActiveDate);
      this.loadState = 'ready';
    }).catch((error: TdError): void => {
      if (!this.active || sequence !== this.sequence) { return; }
      logE(`ConnectedWebsitesPage.load failed: ${error.message}`);
      this.loadState = 'error';
    });
  }

  private dateLabel(seconds: number): string {
    if (seconds <= 0) { return str('cw_unknown_time'); }
    const date = new Date(seconds * 1000);
    const month = `${date.getMonth() + 1}`.padStart(2, '0');
    const day = `${date.getDate()}`.padStart(2, '0');
    const hour = `${date.getHours()}`.padStart(2, '0');
    const minute = `${date.getMinutes()}`.padStart(2, '0');
    return `${date.getFullYear()}-${month}-${day} ${hour}:${minute}`;
  }

  private remove(row: ConnectedWebsite): void {
    if (this.actionKey !== '') { return; }
    promptAction.showDialog({
      title: $r('app.string.cw_disconnect_title'),
      message: str('cw_disconnect_confirm', row.domain !== '' ? row.domain : str('cw_this_site')),
      buttons: [
        { text: $r('app.string.cancel'), color: COLOR_TEXT_SECONDARY as string },
        { text: $r('app.string.cw_disconnect'), color: COLOR_DANGER }
      ]
    }).then((result: promptAction.ShowDialogSuccessResponse): void => {
      if (!this.active || result.index !== 1 || this.actionKey !== '') { return; }
      const before = this.websites.slice();
      this.actionKey = `${row.id}`;
      this.websites = this.websites.filter((item: ConnectedWebsite): boolean => item.id !== row.id);
      disconnectWebsite(row.id).then((): void => {
        if (!this.active) { return; }
        this.actionKey = '';
      }).catch((error: TdError): void => {
        logE(`ConnectedWebsitesPage.disconnect failed: ${error.message}`);
        if (!this.active) { return; }
        this.websites = before;
        this.actionKey = '';
        promptAction.showToast({ message: $r('app.string.cw_disconnect_failed'), duration: 1800 });
      });
    }).catch((): void => {});
  }

  private removeAll(): void {
    if (this.actionKey !== '' || this.websites.length === 0) { return; }
    promptAction.showDialog({
      title: $r('app.string.cw_disconnect_all'),
      message: plural('cw_disconnect_all_confirm', this.websites.length, this.websites.length),
      buttons: [
        { text: $r('app.string.cancel'), color: COLOR_TEXT_SECONDARY as string },
        { text: $r('app.string.cw_disconnect_all_confirm_button'), color: COLOR_DANGER }
      ]
    }).then((result: promptAction.ShowDialogSuccessResponse): void => {
      if (!this.active || result.index !== 1 || this.actionKey !== '') { return; }
      const before = this.websites.slice();
      this.actionKey = 'all';
      this.websites = [];
      disconnectAllWebsites().then((): void => {
        if (!this.active) { return; }
        this.actionKey = '';
      }).catch((error: TdError): void => {
        logE(`ConnectedWebsitesPage.disconnectAll failed: ${error.message}`);
        if (!this.active) { return; }
        this.websites = before;
        this.actionKey = '';
        promptAction.showToast({ message: $r('app.string.cw_disconnect_failed'), duration: 1800 });
      });
    }).catch((): void => {});
  }

  @Builder
  header() {
    Row({ space: 8 }) {
      Button() {
        SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(24).fontColor([COLOR_TEXT_PRIMARY]);
      }.width(40).height(40).borderRadius(20).backgroundColor(Color.Transparent)
      .onClick((): void => { router.back(); });
      Text($r('app.string.cw_title')).fontSize(22).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT_PRIMARY)
        .layoutWeight(1);
      if (this.actionKey !== '') { LoadingProgress().width(20).height(20).color(COLOR_PRIMARY); }
    }.width('100%').height(52).padding({ left: 8, right: 16 }).alignItems(VerticalAlign.Center);
  }

  @Builder
  websiteRow(row: ConnectedWebsite) {
    Row({ space: 12 }) {
      Stack({ alignContent: Alignment.Center }) {
        Text(row.domain !== '' ? row.domain.substring(0, 1).toUpperCase() : 'W')
          .fontSize(20).fontWeight(FontWeight.Bold).fontColor(Color.White);
      }.width(46).height(46).borderRadius(23).backgroundColor(COLOR_PRIMARY);
      Column({ space: 3 }) {
        Text(row.domain !== '' ? row.domain : $r('app.string.cw_unknown_site')).fontSize(16).fontWeight(FontWeight.Medium)
          .fontColor(COLOR_TEXT_PRIMARY).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
        Text(`${row.browser}${row.platform !== '' ? ` · ${row.platform}` : ''}`)
          .fontSize(13).fontColor(COLOR_TEXT_SECONDARY).maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis });
        Text(row.location !== ''
          ? str('cw_last_active_at', this.dateLabel(row.lastActiveDate), row.location)
          : str('cw_last_active', this.dateLabel(row.lastActiveDate)))
          .fontSize(12).fontColor(COLOR_TEXT_SECONDARY).maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis });
      }.layoutWeight(1).alignItems(HorizontalAlign.Start);
      Button($r('app.string.cw_disconnect')).height(36).fontSize(13).fontColor(COLOR_DANGER).backgroundColor(Color.Transparent)
        .enabled(this.actionKey === '').onClick((): void => { this.remove(row); });
    }
    .width('100%').constraintSize({ minHeight: 72 }).padding({ left: 12, right: 8, top: 8, bottom: 8 });
  }

  build() {
    Column() {
      this.header();
      if (this.loadState === 'loading') {
        Column({ space: 9 }) {
          LoadingProgress().width(34).height(34).color(COLOR_PRIMARY);
          Text($r('app.string.cw_loading')).fontSize(13).fontColor(COLOR_TEXT_SECONDARY);
        }.layoutWeight(1).width('100%').justifyContent(FlexAlign.Center);
      } else if (this.loadState === 'error') {
        Column({ space: 10 }) {
          Text($r('app.string.cw_load_failed')).fontSize(17).fontColor(COLOR_TEXT_PRIMARY);
          Button($r('app.string.settings_reload')).onClick((): void => { this.load(); });
        }.layoutWeight(1).width('100%').justifyContent(FlexAlign.Center);
      } else if (this.websites.length === 0) {
        Column({ space: 9 }) {
          SymbolGlyph($r('sys.symbol.link')).fontSize(50).fontColor([COLOR_TEXT_SECONDARY]);
          Text($r('app.string.cw_empty')).fontSize(18).fontWeight(FontWeight.Medium).fontColor(COLOR_TEXT_PRIMARY);
          Text($r('app.string.cw_empty_sub')).fontSize(13).fontColor(COLOR_TEXT_SECONDARY);
        }.layoutWeight(1).width('100%').justifyContent(FlexAlign.Center);
      } else {
        Scroll() {
          // 两层 Column 是故意的：外层铺满、负责居中，内层才是被限宽的内容。
          // 限宽如果加在 Scroll 上，滚动条和边缘回弹会跟着一起缩进来，侧边留白
          // 区域还会拖不动页面。
          Column() {
            Column({ space: 12 }) {
              Column() {
                ForEach(this.websites, (row: ConnectedWebsite, index: number) => {
                  if (index > 0) {
                    Divider().color($r('app.color.divider')).strokeWidth(0.7).margin({ left: 70 });
                  }
                  this.websiteRow(row);
                }, (row: ConnectedWebsite): string => `website_${row.id}`);
              }.width('100%').backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS).padding(4);

              Button($r('app.string.cw_disconnect_all')).width('100%').height(48).borderRadius(24)
                .fontSize(16).fontColor(COLOR_DANGER).backgroundColor(COLOR_SURFACE)
                .enabled(this.actionKey === '').onClick((): void => { this.removeAll(); });

              Text($r('app.string.cw_note'))
                .fontSize(12).fontColor(COLOR_TEXT_SECONDARY).lineHeight(18)
                .width('100%').padding({ left: 16, right: 16 });
            }
            .width('100%')
            .constraintSize({ maxWidth: readableContentWidth(this.screenW) })
            .padding({ left: 12, right: 12, top: 6, bottom: this.bottomSafe + 24 });
          }
          .width('100%')
          // Column 默认左对齐：限了宽不居中就是把内容全堆在屏幕左边，比不限还难看。
          .alignItems(HorizontalAlign.Center);
        }.layoutWeight(1).width('100%').scrollBar(BarState.Off);
      }
    }
    .width('100%').height('100%').backgroundColor(COLOR_PAGE_BG)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .padding({ top: this.topSafe });
  }
}
