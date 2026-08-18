import { router, promptAction } from '@kit.ArkUI';
import { webview } from '@kit.ArkWeb';
import { common } from '@kit.AbilityKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { openUrl } from '../../util/openUrl';
import { webBrowserTarget } from '../../util/webBrowserNav';
import { normalizeTelegramLink } from '../../util/linkNav';
import { openTelegramLink } from '../../util/openTelegramLink';
import {
  COLOR_PAGE_BG, COLOR_PRIMARY, COLOR_SURFACE, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY
} from '../../util/theme';
import { overlayMaterial } from '../../util/overlayMaterial';

interface BrowserParams {
  url?: string;
}

function hostOf(url: string): string {
  let rest = url;
  const scheme = rest.indexOf('://');
  if (scheme >= 0) { rest = rest.substring(scheme + 3); }
  const slash = rest.indexOf('/');
  return slash >= 0 ? rest.substring(0, slash) : rest;
}

@Entry
@Component
struct InAppBrowserPage {
  @StorageProp('topSafeHeight') topSafe: number = 0;
  @StorageProp('bottomSafeHeight') bottomSafe: number = 0;
  @State pageTitle: string = '';
  @State currentUrl: string = '';
  @State progress: number = 0;
  @State loadFailed: boolean = false;
  private controller: webview.WebviewController = new webview.WebviewController();
  private initialUrl: string = '';

  aboutToAppear(): void {
    const params = router.getParams() as BrowserParams | undefined;
    this.initialUrl = webBrowserTarget(params?.url ?? '');
    this.currentUrl = this.initialUrl;
  }

  onBackPress(): boolean {
    try {
      if (this.controller.accessBackward()) {
        this.controller.backward();
        return true;
      }
    } catch (caught) {
      const error = caught as BusinessError;
      console.error(`InAppBrowser back failed: ${error.code} ${error.message}`);
    }
    return false;
  }

  // Telegram resources tapped inside a web page belong back in the app; only
  // real web navigation stays inside this WebView.
  private interceptTelegram(url: string): boolean {
    if (!url.startsWith('tg://') && normalizeTelegramLink(url) === '') { return false; }
    openTelegramLink(getContext(this) as common.UIAbilityContext, url, false);
    return true;
  }

  private openExternally(): void {
    const target = this.currentUrl !== '' ? this.currentUrl : this.initialUrl;
    openUrl(getContext(this) as common.UIAbilityContext, target, (): void => {
      promptAction.showToast({ message: $r('app.string.web_no_browser'), duration: 1800 });
    });
  }

  private copyLink(): void {
    const target = this.currentUrl !== '' ? this.currentUrl : this.initialUrl;
    const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, target);
    pasteboard.getSystemPasteboard().setData(data).then((): void => {
      promptAction.showToast({ message: $r('app.string.link_copied'), duration: 1400 });
    }).catch((error: BusinessError): void => {
      console.error(`InAppBrowser copy failed: ${error.code} ${error.message}`);
      promptAction.showToast({ message: $r('app.string.copy_failed'), duration: 1400 });
    });
  }

  private reload(): void {
    this.loadFailed = false;
    try {
      this.controller.refresh();
    } catch (caught) {
      const error = caught as BusinessError;
      console.error(`InAppBrowser reload failed: ${error.code} ${error.message}`);
    }
  }

  @Builder
  moreMenu() {
    Menu() {
      MenuItem({ content: $r('app.string.web_reload') })
        .onClick((): void => this.reload());
      MenuItem({ content: $r('app.string.fl_copy_link') })
        .onClick((): void => this.copyLink());
      MenuItem({ content: $r('app.string.web_open_external') })
        .onClick((): void => this.openExternally());
    }
  }

  @Builder
  header() {
    Row({ space: 6 }) {
      Button() {
        SymbolGlyph($r('sys.symbol.xmark')).fontSize(20).fontColor([COLOR_TEXT_PRIMARY]);
      }.width(40).height(40).borderRadius(20).backgroundColor(Color.Transparent)
      .onClick((): void => { router.back(); });
      Column({ space: 1 }) {
        Text(this.pageTitle !== '' ? this.pageTitle : $r('app.string.web_page'))
          .fontSize(16).fontWeight(FontWeight.Medium).fontColor(COLOR_TEXT_PRIMARY)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
        Text(hostOf(this.currentUrl)).fontSize(11).fontColor(COLOR_TEXT_SECONDARY)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
      }.layoutWeight(1).alignItems(HorizontalAlign.Start);
      Button() {
        SymbolGlyph($r('sys.symbol.dot_grid_2x2')).fontSize(20).fontColor([COLOR_TEXT_PRIMARY]);
      }.width(40).height(40).borderRadius(20).backgroundColor(Color.Transparent)
      .bindMenu(this.moreMenu(), { systemMaterial: overlayMaterial('menu') });
    }.width('100%').height(50).padding({ left: 6, right: 6 }).alignItems(VerticalAlign.Center)
    .backgroundColor(COLOR_SURFACE);
  }

  build() {
    Column() {
      this.header();
      if (this.progress < 100 && !this.loadFailed) {
        Progress({ value: this.progress, total: 100, type: ProgressType.Linear })
          .width('100%').height(2).color(COLOR_PRIMARY);
      }
      Stack({ alignContent: Alignment.Center }) {
        Web({ src: this.initialUrl, controller: this.controller })
          .domStorageAccess(true)
          .onLoadIntercept((event): boolean => {
            const url = event.data.getRequestUrl();
            return this.interceptTelegram(url);
          })
          .onPageBegin((event): void => {
            if (event) {
              this.currentUrl = event.url;
              this.loadFailed = false;
            }
          })
          .onTitleReceive((event): void => {
            if (event) { this.pageTitle = event.title; }
          })
          .onProgressChange((event): void => {
            if (event) { this.progress = event.newProgress; }
          })
          .onErrorReceive((event): void => {
            // Only a main-frame failure means the page is unusable; subresource
            // errors (ads, trackers) fire this too and must not blank the page.
            if (event && event.request.isMainFrame()) {
              this.loadFailed = true;
            }
          })
          .width('100%').height('100%');

        if (this.loadFailed) {
          Column({ space: 12 }) {
            SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
              .fontSize(46).fontColor([COLOR_TEXT_SECONDARY]);
            Text($r('app.string.web_load_failed')).fontSize(16).fontColor(COLOR_TEXT_PRIMARY);
            Button($r('app.string.settings_reload')).height(38).fontSize(14)
              .onClick((): void => this.reload());
          }.width('100%').height('100%').justifyContent(FlexAlign.Center)
          .backgroundColor(COLOR_PAGE_BG);
        }
      }.layoutWeight(1).width('100%');
    }
    .width('100%').height('100%')
    .backgroundColor(COLOR_PAGE_BG)
    .padding({ top: this.topSafe, bottom: this.bottomSafe });
  }
}
