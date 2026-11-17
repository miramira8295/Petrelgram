import { DocumentEmbedResizeBridge, setDocumentEmbedHeight } from '../../util/documentEmbedMetrics';
import { DocumentEmbedNavigation, documentEmbedUrl, documentEmbedBridgePermission } from '../../util/documentEmbedNavigation';
import { DrawnDocumentArticleImage } from './DrawnDocumentArticleImage';
import { webview } from '@kit.ArkWeb';
import { DrawnDocumentWidget } from '../../util/drawnDocumentWidget';
import { documentEmbedPool } from '../../util/documentEmbedLease';
import { COLOR_TEXT_SECONDARY } from '../../util/theme';

// Fixed-size ArticleViewer HTML/URL embed. No MiniApp bridge or bot authorization.
// Dwell avoids creating WebViews for cells traversed during a fling. At most two
// live hosts across documents; offscreen/reused hosts release their lease.
@ComponentV2
export struct DrawnDocumentEmbed {
  @Require @Param widget: DrawnDocumentWidget;
  @Param boxWidth: number = 0;
  @Param boxHeight: number = 0;
  @Event onMetricsChanged: () => void = (): void => {};
  @Event onClaim: () => boolean = (): boolean => false;
  @Event onOpen: (url: string) => void = (_url: string): void => {};
  @Local private ready: boolean = false;
  @Local private failed: boolean = false;
  private controller: webview.WebviewController = new webview.WebviewController();
  private visible: boolean = false;
  private timer: number = -1;
  private generation: number = 0;
  private leased: boolean = false;
  private cancelWait: (() => void) | null = null;
  private resizeTimer: number = -1;
  private pendingHeight: number = 0;
  private resizeBridge: DocumentEmbedResizeBridge = new DocumentEmbedResizeBridge((_height: number): void => {});
  private navigation: DocumentEmbedNavigation = new DocumentEmbedNavigation();
  private loadTimer: number = -1;
  @Local private loaded: boolean = false;
  private stop(): void {
    this.generation++;
    this.resizeBridge.dispose();
    if (this.resizeTimer !== -1) { clearTimeout(this.resizeTimer); this.resizeTimer = -1; }
    this.pendingHeight = 0;
    if (this.timer !== -1) { clearTimeout(this.timer); this.timer = -1; }
    this.cancelWait?.(); this.cancelWait = null;
    if (this.ready) { try { this.controller.stop(); } catch (_) {} }
    this.ready = false; this.loaded = false;
    if (this.loadTimer !== -1) { clearTimeout(this.loadTimer); this.loadTimer = -1; }
    if (this.leased) { this.leased = false; documentEmbedPool.release(); }
  }
  private schedule(): void {
    this.stop(); this.failed = false;
    if (!this.visible) { return; }
    const generation = this.generation;
    this.timer = setTimeout((): void => {
      this.timer = -1;
      if (generation !== this.generation || !this.visible) { return; }
      const grant = (): void => {
        this.cancelWait = null;
        if (generation !== this.generation || !this.visible) { documentEmbedPool.release(); return; }
        this.leased = true;
        this.navigation.reset((this.widget.html ?? '') !== '' ? 'https://telegram.org/embed' : (this.widget.url ?? ''));
        this.controller = new webview.WebviewController();
        const owner = this.widget;
        this.resizeBridge = new DocumentEmbedResizeBridge((height: number): void => {
          if (generation !== this.generation || owner !== this.widget || !this.visible) { return; }
          this.pendingHeight = height;
          if (this.resizeTimer !== -1) { return; }
          this.resizeTimer = setTimeout((): void => {
            this.resizeTimer = -1;
            if (generation === this.generation && owner === this.widget && this.visible &&
              setDocumentEmbedHeight(owner, this.boxWidth, this.pendingHeight)) { this.onMetricsChanged(); }
          }, 100);
        });
        this.ready = true;
      };
      if (documentEmbedPool.tryAcquire()) { grant(); }
      else { this.cancelWait = documentEmbedPool.wait(grant); }
    }, 160);
  }
  @Monitor('widget') sourceChanged(): void { this.schedule(); }
  aboutToDisappear(): void { this.visible = false; this.stop(); }
  private load(): void {
    if (!this.ready || !this.visible) { return; }
    try {
      // Android uses the same base for relative HTML resources.
      const generation = this.generation;
      if (this.loadTimer !== -1) { clearTimeout(this.loadTimer); }
      this.loadTimer = setTimeout((): void => {
        this.loadTimer = -1;
        if (generation === this.generation && !this.loaded) { this.fail(); }
      }, 15000);
      if ((this.widget.html ?? '') !== '') {
        this.controller.loadData(this.widget.html ?? '', 'text/html', 'UTF-8', 'https://telegram.org/embed');
      }
    } catch (_) { this.fail(); }
  }
  private fail(): void { this.stop(); this.failed = true; }
  private finished(): void {
    if (!this.ready) { return; }
    this.loaded = true; this.navigation.loaded();
    if (this.loadTimer !== -1) { clearTimeout(this.loadTimer); this.loadTimer = -1; }
  }
  private current(controller: webview.WebviewController, widget: DrawnDocumentWidget, generation: number): boolean {
    return this.ready && this.visible && this.controller === controller && this.widget === widget && this.generation === generation;
  }
  @Builder private webContent(controller: webview.WebviewController, widget: DrawnDocumentWidget, generation: number, bridge: DocumentEmbedResizeBridge) {
        Web({ src: (widget.html ?? '') !== '' ? 'about:blank' : (widget.url ?? ''), controller: controller, renderMode: RenderMode.SYNC_RENDER })
          .width(this.boxWidth).height(this.boxHeight)
          .javaScriptAccess(true).domStorageAccess(true).onlineImageAccess(true)
          .fileAccess(false).multiWindowAccess(false).mixedMode(MixedMode.None)
          .mediaPlayGestureAccess(true)
          .javaScriptProxy({ object: bridge, name: 'TelegramWebviewProxy', methodList: ['postEvent'],
            controller: controller, permission: documentEmbedBridgePermission((widget.html ?? '') !== '' ? 'https://telegram.org/embed' : (widget.url ?? '')) })
          .javaScriptOnDocumentStart(widget.allowScrolling === true ? [] : [{
            script: "document.addEventListener('DOMContentLoaded',function(){document.documentElement.style.overflow='hidden';if(document.body){document.body.style.overflow='hidden';}});",
            scriptRules: ['*']
          }])
          .onTouch((event: TouchEvent): void => {
            if (event.type === TouchType.Down && this.current(controller, widget, generation)) { this.onClaim(); }
          })
          .onControllerAttached((): void => { if (this.current(controller, widget, generation)) { this.load(); } })
          .onPageEnd((event): void => {
            if (event?.url !== 'about:blank' && this.current(controller, widget, generation)) { this.finished(); }
          })
          .onErrorReceive((event): void => {
            if (this.current(controller, widget, generation) && event && event.request.isMainFrame()) { this.fail(); }
          })
          .onHttpErrorReceive((event): void => {
            if (this.current(controller, widget, generation) && event && event.request.isMainFrame() && event.response.getResponseCode() >= 400) { this.fail(); }
          })
          .onLoadIntercept((event): boolean => {
            if (!this.current(controller, widget, generation)) { return true; }
            const url = event.data.getRequestUrl();
            const decision = this.navigation.decide(url, event.data.isMainFrame(),
              event.data.isRequestGesture(), event.data.isRedirect());
            if (decision === 'open' && this.onClaim()) { this.onOpen(url); }
            return decision !== 'allow';
          });
  }
  build() {
    Stack() {
      if (this.ready) {
        this.webContent(this.controller, this.widget, this.generation, this.resizeBridge);
      }
      if (!this.loaded) {
        if (this.widget.avatar !== undefined || (this.widget.avatarMini ?? '') !== '') {
          DrawnDocumentArticleImage({ widget: this.widget, boxWidth: this.boxWidth, boxHeight: this.boxHeight });
        }
        if (!this.failed) { LoadingProgress().width(24).height(24).hitTestBehavior(HitTestMode.None); }
      }
      if (this.failed) {
        Text($r('app.string.mb_web_link')).fontColor(COLOR_TEXT_SECONDARY)
          .onClick((): void => {
            if (this.onClaim() && documentEmbedUrl(this.widget.url ?? '')) { this.onOpen(this.widget.url ?? ''); }
          });
      }
    }.width(this.boxWidth).height(this.boxHeight).clip(true)
      .onVisibleAreaChange([0], (visible: boolean): void => {
        if (this.visible !== visible) { this.visible = visible; this.schedule(); }
      });
  }
}
