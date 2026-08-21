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
import { overlayMaterial, MATERIAL_EPOCH } from '../../util/overlayMaterial';
import { logE } from '../../util/log';

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
  // 材质档位（厚度/光感）改变时重绘。overlayMaterial 是 util，订阅不了
  // AppStorage，只能由调用方订阅，同 LANGUAGE_EPOCH 的做法。
  @StorageProp(MATERIAL_EPOCH) private materialEpoch: number = 0;
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
      logE(`InAppBrowser back failed: ${error.code} ${error.message}`);
    }
    return false;
  }

  // Telegram resources tapped inside a web page belong back in the app; only
  // real web navigation stays inside this WebView.
  private interceptTelegram(url: string): boolean {
    if (url.startsWith('tg://') || normalizeTelegramLink(url) !== '') {
      openTelegramLink(getContext(this) as common.UIAbilityContext, url, false);
      return true;
    }
    // 非 http(s) 的私有 scheme（baiduboxapp:// 一类的拉起自家 App 跳转）不能
    // 交给 Web 组件——它渲染不了，主框架直接判失败，整页变成错误态（issue #77
    // 百度网盘正是这么挂的）。转交系统试着拉起对应应用，拉不起来就地忽略，
    // 网页本身留在原地。
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      openUrl(getContext(this) as common.UIAbilityContext, url, (): void => {});
      return true;
    }
    return false;
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
      logE(`InAppBrowser copy failed: ${error.code} ${error.message}`);
      promptAction.showToast({ message: $r('app.string.copy_failed'), duration: 1400 });
    });
  }

  private reload(): void {
    this.loadFailed = false;
    try {
      this.controller.refresh();
    } catch (caught) {
      const error = caught as BusinessError;
      logE(`InAppBrowser reload failed: ${error.code} ${error.message}`);
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
    }
    .width('100%')
    // 顶栏自己吃掉状态栏那一条：高度加上 topSafe、内容用 padding 顶下来，
    // 于是那条由**顶栏的底色**来画，和顶栏浑然一体。
    //
    // 之前是根容器 padding 把整页推下来，那条归根容器画、是 page_bg，而顶栏
    // 是 surface —— 两个颜色紧挨着，看着仍然不沉浸（issue #7 原话："状态栏
    // 跟顶栏的颜色是不一样的"）。
    .height(50 + this.topSafe)
    .padding({ left: 6, right: 6, top: this.topSafe })
    .alignItems(VerticalAlign.Center)
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
          // 百度系站点按 UA 分流，认不出的 UA 直接给错误页/白页。ArkWeb 默认
          // UA 带着 ArkWeb 标识，不在它们的白名单里——去掉自有标识、对齐主流
          // 移动端 Chrome 的形状，站点才走正常的移动版路径。
          .onControllerAttached((): void => {
            try {
              const ua: string = this.controller.getUserAgent();
              this.controller.setCustomUserAgent(
                ua.replace(/ArkWeb\/[\d.]+ /, '').replace('Mobile ', 'Mobile Safari/537.36 '));
            } catch (e) {
              // UA 设不上就用默认——大多数站点仍可用，不值得让整页失败。
            }
          })
          // target=_blank / window.open 的链接在本窗口继续开，而不是无声吞掉
          // ——没有这一段，网盘里"打开/下载"一类按钮点了没反应。
          .multiWindowAccess(false)
          .javaScriptAccess(true)
          .onlineImageAccess(true)
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
    // 少了 expandSafeArea 时，页面的布局区停在安全区边界，状态栏那一条不归
    // 页面画，露出的是窗口底色——看着就是"没沉浸"。padding 只负责把内容让开
    // 那一条，铺不铺满是另一回事，两个都要有。其余页面都是这么写的。
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    // 顶部不再由这里让开——那一条交给顶栏自己画（见上面的说明）。底部照旧。
    .padding({ bottom: this.bottomSafe });
  }
}
