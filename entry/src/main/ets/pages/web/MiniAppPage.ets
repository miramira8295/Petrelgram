import { showToast } from '../../util/toast';
import { router, promptAction } from '@kit.ArkUI';
import { webview } from '@kit.ArkWeb';
import { common } from '@kit.AbilityKit';
import { getTdClient } from '../../tdkit/Globals';
import { TdRequest } from '../../tdkit/TdTypes';
import { closeMiniApp } from '../../store/BotApi';
import { refreshWebBridge } from '../../store/ProxyApi';
import { MiniAppLaunch, MiniAppSession, miniAppOrigin, miniAppTheme } from '../../util/miniAppModel';
import {
  MiniAppBridge, MiniAppEvent, MiniAppButton, miniAppButton, miniAppBootstrap,
  miniAppBridgePermission, miniAppReceiveScript, miniAppString, miniAppColor,
  miniAppUrlWithFullscreenSupport
} from '../../util/miniAppBridge';
import { openTelegramLink } from '../../util/openTelegramLink';
import { normalizeTelegramLink } from '../../util/linkNav';
import { openWebUrl } from '../../util/webBrowserNav';
import { str } from '../../util/strings';
import { relativeLuminance } from '../../util/colorMath';
import { MATERIAL_EPOCH } from '../../util/overlayMaterial';
import { COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY, COLOR_SURFACE,
  COLOR_PAGE_BG, KEY_APP_DARK } from '../../util/theme';

// 首次打开小程序给足时间：冷启动时上游连接/代理可能还在建，30s 会把
// 「慢」误判成「打不开」。
const MINI_APP_LOAD_TIMEOUT_MS: number = 60000;
// 自动重试前留一点余量，等上游就绪。
const MINI_APP_AUTO_RETRY_DELAY_MS: number = 2000;
// 连续自动重试的上限。成功加载一次就归零，所以「开一次页面」最多刷 3 次。
const MINI_APP_AUTO_RETRY_LIMIT: number = 3;
// 全屏顶部条的内容高度（不含状态栏）。对齐官方 dp(8+30+8)=46：web 顶边本来就在
// 状态栏下方，顶部条以透明浮层叠在那里，页面按 safe-top(状态栏) + content-top(此值) 预留。
const MINI_APP_FULLSCREEN_BAR_HEIGHT: number = 46;

@Entry
@Component
struct MiniAppPage {
  @StorageProp(MATERIAL_EPOCH) private materialEpoch: number = 0;
  @StorageProp('topSafeHeight') topSafe: number = 0;
  @StorageProp('bottomSafeHeight') bottomSafe: number = 0;
  @StorageProp(KEY_APP_DARK) @Watch('themeChanged') private appDark: boolean = false;
  @StorageProp('appIsForeground') @Watch('visibilityChanged') private appForeground: boolean = true;
  @State private title: string = '';
  @State private appUrl: string = '';
  @State private origin: string = '';
  @State private progress: number = 0;
  @State private loading: boolean = true;
  @State private failed: boolean = false;
  @State private backVisible: boolean = false;
  @State private mainButton: MiniAppButton = miniAppButton({});
  @State private secondaryButton: MiniAppButton = miniAppButton({});
  @State private headerColor: string = '';
  @State private pageBackground: string = '';
  @State private fullscreen: boolean = false;
  // 全屏顶部条右侧「⋮」弹出的菜单（刷新/关闭），对齐官方 Telegram 的更多按钮。
  @State private chromeMenuShown: boolean = false;
  private controller: webview.WebviewController = new webview.WebviewController();
  private bridge: MiniAppBridge = new MiniAppBridge((event: MiniAppEvent): void => this.onEvent(event));
  private session: MiniAppSession = new MiniAppSession(
    (request: TdRequest) => getTdClient().send(request, 20000), closeMiniApp);
  private launch: MiniAppLaunch | null = null;
  private disposed: boolean = false;
  private closing: boolean = false;
  private needsCloseConfirmation: boolean = false;
  private dialogOpen: boolean = false;
  private loadTimer: number = -1;
  // 冷启动时上游网络/代理可能还没就绪，首帧请求会失败。给一次静默自动重试：
  // 失败页面上点「重新加载」其实也是这样救回来的，只是让用户少点一下。
  private autoRetryCount: number = 0;
  private viewportHeight: number = 0;
  private pageVisible: boolean = true;

  aboutToAppear(): void {
    // 代理可能在后台被自动切换换掉，开页面前让桥跟一次（内部失败只记日志）。
    refreshWebBridge();
    this.launch = this.getUIContext().getRouter().getParams() as MiniAppLaunch;
    this.title = this.launch?.title ?? '';
    this.start();
  }

  aboutToDisappear(): void {
    this.disposed = true;
    this.clearLoadTimer();
    this.bridge.dispose();
    this.session.close();
    try { this.controller.deleteJavaScriptRegister('PetrelMiniApp'); } catch (_) {}
  }

  onPageShow(): void { this.pageVisible = true; this.visibilityChanged(); }
  onPageHide(): void { this.pageVisible = false; this.visibilityChanged(); }

  private visibilityChanged(): void {
    if (this.disposed || this.appUrl === '') { return; }
    const visible = this.pageVisible && this.appForeground;
    this.emit('visibility_changed', { 'is_visible': visible });
    try {
      if (visible) { this.controller.onActive(); }
      else { this.controller.onInactive(); }
    } catch (_) {}
  }

  private headerInk(): ResourceColor {
    if (this.headerColor === '') { return COLOR_TEXT_PRIMARY; }
    return relativeLuminance(this.headerColor) > 0.179 ? '#000000' : '#ffffff';
  }

  @Builder
  chromeMenu() {
    Column() {
      Text(str('web_reload')).fontSize(15).fontColor(this.headerInk()).width('100%').height(44)
        .padding({ left: 16, right: 16 }).textAlign(TextAlign.Start)
        .onClick((): void => { this.chromeMenuShown = false; this.reload(); });
      Text(str('tglink_close')).fontSize(15).fontColor(this.headerInk()).width('100%').height(44)
        .padding({ left: 16, right: 16 }).textAlign(TextAlign.Start)
        .onClick((): void => { this.chromeMenuShown = false; this.close(); });
    }.width(160).backgroundColor(Color.White).borderRadius(12)
      .padding({ top: 4, bottom: 4 });
  }

  // 全屏顶部条上的灰色胶囊：对齐官方 Telegram 的 secondary 按钮（半透明灰底 +
  // 白色字形），浅色取 30% 黑、深色取 32% 白（20% 太淡，白字压不住）。
  private chromePillFill(): ResourceColor {
    return this.appDark ? '#52FFFFFF' : '#4D000000';
  }

  // 头部的三块自绘玻璃已改为系统沉浸材质承载（2026-11-18 全应用统一），
  // 原来的 @Styles headerGlass() 一并撤掉。

  private async start(): Promise<void> {
    if (this.launch === null || this.disposed) { return; }
    this.failed = false;
    this.loading = true;
    try {
      const result = await this.session.open(this.launch, this.appDark);
      if (result === null || this.disposed) { return; }
      this.origin = miniAppOrigin(result.url);
      this.appUrl = miniAppUrlWithFullscreenSupport(result.url);
      this.armLoadTimer();
    } catch (_) {
      if (!this.disposed) { this.failed = true; this.loading = false; }
    }
  }

  private clearLoadTimer(): void {
    if (this.loadTimer !== -1) { clearTimeout(this.loadTimer); this.loadTimer = -1; }
  }

  private armLoadTimer(): void {
    this.clearLoadTimer();
    this.loadTimer = setTimeout((): void => {
      this.loadTimer = -1;
      if (this.retryOnce('load-timeout')) { return; }
      this.failed = true;
      this.loading = false;
    }, MINI_APP_LOAD_TIMEOUT_MS);
  }

  private loaded(): void {
    this.clearLoadTimer();
    this.loading = false;
    // 这一页真的加载出来了：把自动重试额度还回去，下一段导航还能再自愈。
    this.autoRetryCount = 0;
  }

  // 最多自动重试 MINI_APP_AUTO_RETRY_LIMIT 次；每次成功加载（onPageEnd）归零。
  // 到上限后把决定权交回用户（失败页上的「重新加载」），避免网络真断时无限刷新。
  private retryOnce(reason: string): boolean {
    if (this.autoRetryCount >= MINI_APP_AUTO_RETRY_LIMIT || this.appUrl === '' || this.disposed) {
      return false;
    }
    this.autoRetryCount++;
    setTimeout((): void => { if (!this.disposed) { this.reload(); } }, MINI_APP_AUTO_RETRY_DELAY_MS);
    return true;
  }

  private reload(): void {
    if (this.appUrl === '') { this.start(); return; }
    this.failed = false;
    this.loading = true;
    this.progress = 0;
    this.armLoadTimer();
    try { this.controller.refresh(); } catch (_) { this.failed = true; this.loaded(); }
  }

  private emit(name: string, data: Record<string, Object> = {}): void {
    if (this.disposed || this.appUrl === '') { return; }
    try {
      this.controller.runJavaScript(miniAppReceiveScript(name, data)).catch((): void => {});
    } catch (_) {} // Area/theme callbacks may arrive before the Web controller attaches.
  }

  private themeChanged(): void {
    this.headerColor = '';
    this.pageBackground = '';
    this.emit('theme_changed', { 'theme_params': miniAppTheme(this.appDark) });
  }

  private viewportChanged(): void {
    if (this.viewportHeight <= 0) { return; }
    this.emit('viewport_changed', { 'height': this.viewportHeight,
      'is_state_stable': true, 'is_expanded': true });
    this.safeAreaChanged();
  }

  private safeAreaChanged(): void {
    const bottom = this.mainButton.visible || this.secondaryButton.visible ? 0 : this.bottomSafe;
    // 全屏时 web 内容铺到屏幕最顶、原生顶部条改成浮层压在它上面（对齐 Telegram
    // Android 的 fullscreen chrome）。expandSafeArea 之后整页从 y=0 开始，所以
    // safe top 报状态栏高度、content top 报顶部条内容高度(46)：页面预留的
    // 状态栏+46 正好被原生条完整盖住，不会再露出被裁掉一半的标题；
    // 非全屏（legacy 页面）保持 0。
    const top = this.fullscreen ? this.topSafe : 0;
    const contentTop = this.fullscreen ? MINI_APP_FULLSCREEN_BAR_HEIGHT : 0;
    this.emit('safe_area_changed', { 'top': top, 'bottom': bottom, 'left': 0, 'right': 0 });
    // 对齐 Telegram Android：content_safe_area 只报 top，bottom 恒 0。
    this.emit('content_safe_area_changed', { 'top': contentTop, 'bottom': 0, 'left': 0, 'right': 0 });
  }

  // Bot API 8.0 全屏。nmBot 这类页面在 fullscreen compact 模式下会自己
  // 收起顶部那条按键行、并把底部页签按 --tg-safe-area-inset-bottom 抬高；
  // 原生侧只切状态并重报安全区，不加 padding、不注入脚本。
  // 页面在 load 完成前就可能读过一次安全区、之后不再重读；全屏切换后补发几次，
  // 避免首次进入时少算 content_safe_area 那 46vp（商业页顶部图标会被多裁一截）。
  private armSafeAreaRepeats(): void {
    const delays: number[] = [200, 700, 1600];
    for (let i = 0; i < delays.length; i++) {
      const delay: number = delays[i];
      setTimeout((): void => {
        if (this.disposed || !this.fullscreen) { return; }
        this.safeAreaChanged();
      }, delay);
    }
  }

  private requestFullscreen(data: Record<string, Object>): void {
    if (this.fullscreen) { this.emit('fullscreen_failed', { 'error': 'ALREADY_FULLSCREEN' }); return; }
    this.fullscreen = true;
    this.emit('fullscreen_changed', { 'is_fullscreen': true, 'blur_enabled': data['blur'] !== false });
    this.viewportChanged();
    this.armSafeAreaRepeats();
  }

  private exitFullscreen(): void {
    const wasFullscreen = this.fullscreen;
    this.fullscreen = false;
    this.emit('fullscreen_changed', { 'is_fullscreen': false });
    if (wasFullscreen) { this.viewportChanged(); }
  }

  private async close(): Promise<void> {
    if (this.closing || this.disposed) { return; }
    this.closing = true;
    if (this.needsCloseConfirmation) {
      try {
        const result = await this.getUIContext().getPromptAction().showDialog({ title: str('miniapp_close_title'),
          message: str('miniapp_close_message'), buttons: [
            { text: str('cancel'), color: '#707579' }, { text: str('tglink_close'), color: '#3390ec' }
          ] });
        if (result.index !== 1) { this.closing = false; return; }
      } catch (_) { this.closing = false; return; }
    }
    if (!this.disposed) { this.session.close(); this.getUIContext().getRouter().back(); }
  }

  onBackPress(): boolean {
    this.back();
    return true;
  }

  private back(): void {
    if (this.backVisible && !this.failed) { this.emit('back_button_pressed'); return; }
    try {
      if (this.controller.accessBackward()) { this.controller.backward(); return; }
    } catch (_) {}
    this.close();
  }

  private openLink(url: string, telegram: boolean): void {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    if (telegram) {
      if (url.startsWith('/') && !url.startsWith('//')) {
        openTelegramLink(context, `https://t.me${url}`, false);
      }
    } else if (/^https?:\/\//i.test(url)) {
      if (normalizeTelegramLink(url) !== '') { openTelegramLink(context, url, false); }
      else { openWebUrl(context, url); }
    }
  }

  private intercept(url: string): boolean {
    if (miniAppOrigin(url) === this.origin && this.origin !== '') { return false; }
    // Keep the bridge on the launch origin. Never hand an authorization URL
    // to another application, nor forward arbitrary custom schemes.
    if (url.startsWith('tg://') || normalizeTelegramLink(url) !== '') {
      openTelegramLink(this.getUIContext().getHostContext() as common.UIAbilityContext, url, false);
    } else if (/^https?:\/\//i.test(url)) {
      openWebUrl(this.getUIContext().getHostContext() as common.UIAbilityContext, url, (): void => {}, true);
    }
    return true;
  }

  private async popup(data: Record<string, Object>): Promise<void> {
    if (this.dialogOpen) { return; }
    const message = miniAppString(data, 'message').substring(0, 256);
    if (message === '') { this.emit('popup_closed'); return; }
    const rawButtons = data['buttons'];
    const buttons: Record<string, Object>[] = Array.isArray(rawButtons)
      ? (rawButtons as Record<string, Object>[]).slice(0, 3) : [];
    const labels: promptAction.Button[] = [];
    const ids: string[] = [];
    for (const button of buttons) {
      if (button === null || typeof button !== 'object') { continue; }
      const type = miniAppString(button, 'type');
      const label = type === 'cancel' ? str('cancel') : type === 'close' ? str('tglink_close')
        : type === 'ok' ? str('color_picker_confirm') : miniAppString(button, 'text').substring(0, 64);
      if (label === '') { continue; }
      labels.push({ text: label, color: type === 'destructive' ? '#e53935' : '#3390ec' });
      ids.push(miniAppString(button, 'id').substring(0, 64));
    }
    if (labels.length === 0) { labels.push({ text: str('color_picker_confirm'), color: '#3390ec' }); ids.push(''); }
    this.dialogOpen = true;
    try {
      const result = await this.getUIContext().getPromptAction().showDialog({
        title: miniAppString(data, 'title').substring(0, 64), message, buttons: labels });
      this.emit('popup_closed', { 'button_id': ids[result.index] ?? '' });
    } catch (_) { this.emit('popup_closed'); }
    this.dialogOpen = false;
  }

  private unsupported(): void {
    showToast($r('app.string.miniapp_feature_unsupported'));
  }

  private onEvent(event: MiniAppEvent): void {
    if (this.disposed) { return; }
    const data = event.data;
    switch (event.name) {
      case 'web_app_ready': this.loaded(); this.viewportChanged(); break;
      case 'web_app_close': this.close(); break;
      case 'web_app_request_theme':
        this.emit('theme_changed', { 'theme_params': miniAppTheme(this.appDark) }); break;
      case 'web_app_expand':
      case 'web_app_request_viewport': this.viewportChanged(); break;
      case 'web_app_request_safe_area':
      case 'web_app_request_content_safe_area':
        this.safeAreaChanged(); break;
      case 'web_app_setup_back_button': this.backVisible = data['is_visible'] === true; break;
      case 'web_app_setup_main_button': this.mainButton = miniAppButton(data); break;
      case 'web_app_setup_secondary_button': this.secondaryButton = miniAppButton(data); break;
      case 'web_app_setup_closing_behavior': this.needsCloseConfirmation = data['need_confirmation'] === true; break;
      case 'web_app_set_header_color':
        this.headerColor = miniAppColor(miniAppString(data, 'color'),
          miniAppTheme(this.appDark)[miniAppString(data, 'color_key')] ?? miniAppTheme(this.appDark)['bg_color']); break;
      case 'web_app_set_background_color':
        this.pageBackground = miniAppColor(miniAppString(data, 'color'), miniAppTheme(this.appDark)['bg_color']); break;
      case 'web_app_open_link': this.openLink(miniAppString(data, 'url'), false); break;
      case 'web_app_open_tg_link': this.openLink(miniAppString(data, 'path_full'), true); break;
      case 'web_app_open_popup': this.popup(data); break;
      case 'web_app_open_invoice':
        this.emit('invoice_closed', { 'slug': miniAppString(data, 'slug'), 'status': 'cancelled' });
        this.unsupported(); break;
      case 'web_app_request_write_access': this.emit('write_access_requested', { 'status': 'cancelled' }); break;
      case 'web_app_request_phone': this.emit('phone_requested', { 'status': 'cancelled' }); break;
      case 'web_app_read_text_from_clipboard':
        this.emit('clipboard_text_received', { 'req_id': miniAppString(data, 'req_id') }); break;
      case 'web_app_invoke_custom_method':
        this.emit('custom_method_invoked', { 'req_id': miniAppString(data, 'req_id'), 'error': 'UNSUPPORTED_METHOD' }); break;
      case 'web_app_request_fullscreen': this.requestFullscreen(data); break;
      case 'web_app_exit_fullscreen': this.exitFullscreen(); break;
      case 'web_app_data_send':
      case 'web_app_switch_inline_query':
        this.unsupported(); break;
      case 'web_app_open_scan_qr_popup':
        this.emit('scan_qr_popup_closed'); this.unsupported(); break;
    }
  }

  // 普通（非全屏）小程序顶栏对齐官方 Telegram Android 的标准动作栏：
  // 左「✕ 关闭」（有历史时变「← 返回」）、中间居中标题、右「˅ + ⋮」菜单。
  // 官方从不显示网址；站点把 document.title 设成 URL 时这里也退回通用标题。
  private headerTitleText(): string {
    const raw = this.title.trim();
    if (raw === '' || raw.indexOf('://') >= 0) { return str('gs_mini_app'); }
    return raw;
  }

  @Builder
  header() {
    Row() {
      Button() {
        SymbolGlyph(this.backVisible ? $r('sys.symbol.chevron_left') : $r('sys.symbol.xmark'))
          .fontSize(20).fontColor([this.headerInk()]);
      }
      .width(40).height(40).borderRadius(20).backgroundColor(Color.Transparent)
      .accessibilityText(str(this.backVisible ? 'back' : 'tglink_close'))
      .onClick((): void => { if (this.backVisible) { this.back(); } else { this.close(); } });

      Text(this.headerTitleText())
        .layoutWeight(1).textAlign(TextAlign.Center).fontSize(17).fontWeight(FontWeight.Medium)
        .fontColor(this.headerInk()).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        .padding({ left: 8, right: 8 })
        .hitTestBehavior(HitTestMode.None);

      Row({ space: 2 }) {
        Button() { SymbolGlyph($r('sys.symbol.chevron_down')).fontSize(20).fontColor([this.headerInk()]); }
          .width(38).height(40).borderRadius(19).backgroundColor(Color.Transparent)
          .accessibilityText(str('tglink_close'))
          .onClick((): void => { this.close(); });
        Button() {
          Column({ space: 3.5 }) {
            Row().width(4).height(4).borderRadius(2).backgroundColor(this.headerInk());
            Row().width(4).height(4).borderRadius(2).backgroundColor(this.headerInk());
            Row().width(4).height(4).borderRadius(2).backgroundColor(this.headerInk());
          }
        }
        .width(38).height(40).borderRadius(19).backgroundColor(Color.Transparent)
        .accessibilityText(str('web_reload'))
        .onClick((): void => { this.chromeMenuShown = !this.chromeMenuShown; })
        .bindPopup(this.chromeMenuShown, {
          builder: this.chromeMenu,
          placement: Placement.BottomRight,
          onStateChange: (e: PopupStateChangeParam): void => {
            if (!e.isVisible) { this.chromeMenuShown = false; }
          }
        });
      }
    }.width('100%').height(54 + this.topSafe)
      .padding({ top: this.topSafe, left: 6, right: 6 })
      .backgroundColor(this.headerColor || COLOR_SURFACE);
  }

  // 全屏顶部条对齐官方 Telegram Android（BotWebViewSheet 里 actionBar 是
  // setBackgroundColor(Color.TRANSPARENT) 的透明浮层）：只有左右两颗灰色胶囊，
  // 条本身不刷底色、中间也不画标题——页面自己的大图/标题就画在这条带里，
  // 一旦刷底色就会把它们切掉（商业、Copilot 页顶部被截断就是这么来的）。
  // 只有状态栏那一条刷页面头色，避免与下面的页面底色出现接缝。
  @Builder
  fullscreenHeader() {
    Column() {
      Row().width('100%').height(this.topSafe).backgroundColor(this.headerColor || COLOR_SURFACE);
      Row() {
        Row({ space: 7 }) {
          SymbolGlyph($r('sys.symbol.xmark')).fontSize(16).fontColor([Color.White]);
          Text(str('tglink_close')).fontSize(15).fontWeight(FontWeight.Medium).fontColor(Color.White).maxLines(1);
        }.height(37).padding({ left: 15, right: 18 }).borderRadius(18.5)
          .backgroundColor(this.chromePillFill())
          .accessibilityText(str('tglink_close'))
          .onClick((): void => { this.close(); });

        Blank();

        Row() {
          SymbolGlyph($r('sys.symbol.chevron_down')).fontSize(19).fontColor([Color.White])
            .accessibilityText(str('tglink_close'))
            .onClick((): void => { this.close(); });
          Column({ space: 3.5 }) {
            Row().width(4.5).height(4.5).borderRadius(2.25).backgroundColor(Color.White);
            Row().width(4.5).height(4.5).borderRadius(2.25).backgroundColor(Color.White);
            Row().width(4.5).height(4.5).borderRadius(2.25).backgroundColor(Color.White);
          }.padding({ left: 19 })
            .accessibilityText(str('web_reload'))
            .onClick((): void => { this.chromeMenuShown = !this.chromeMenuShown; })
            .bindPopup(this.chromeMenuShown, {
              builder: this.chromeMenu,
              placement: Placement.BottomRight,
              onStateChange: (e: PopupStateChangeParam): void => {
                if (!e.isVisible) { this.chromeMenuShown = false; }
              }
            });
        }.height(37).padding({ left: 16, right: 16 }).borderRadius(18.5)
          .backgroundColor(this.chromePillFill());
      }.width('100%').height(MINI_APP_FULLSCREEN_BAR_HEIGHT).padding({ left: 8, right: 8 });
    }.width('100%');
  }

  @Builder
  actionButton(button: MiniAppButton, event: string) {
    Button() {
      Row({ space: 8 }) {
        if (button.progress) { LoadingProgress().width(18).height(18).color(button.textColor); }
        Text(button.text).fontSize(15).fontWeight(FontWeight.Medium).fontColor(button.textColor)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
      }.justifyContent(FlexAlign.Center);
    }.height(46).layoutWeight(1).borderRadius(12).backgroundColor(button.color)
      .enabled(button.active && !button.progress).onClick((): void => this.emit(event));
  }

  build() {
    Stack({ alignContent: Alignment.Top }) {
      Column() {
        if (!this.fullscreen) {
          this.header();
          Progress({ value: this.loading ? this.progress : 100, total: 100, type: ProgressType.Linear })
            .height(2).width('100%').color(COLOR_PRIMARY).opacity(this.loading ? 1 : 0);
        }
        Stack() {
        if (this.appUrl !== '') {
          Web({ src: this.appUrl, controller: this.controller })
            .javaScriptAccess(true).domStorageAccess(true).onlineImageAccess(true).multiWindowAccess(false)
            .fileAccess(false).mixedMode(MixedMode.None)
            .darkMode(this.appDark ? WebDarkMode.On : WebDarkMode.Off).forceDarkAccess(false)
            .backgroundColor(this.pageBackground || COLOR_PAGE_BG)
            .javaScriptProxy({ object: this.bridge, name: 'PetrelMiniApp', methodList: ['postEvent'],
              controller: this.controller, permission: miniAppBridgePermission(this.appUrl) })
            .javaScriptOnDocumentStart([{ script: miniAppBootstrap(), scriptRules: [this.origin] }])
            .onLoadIntercept((event): boolean => event.data.isMainFrame() && this.intercept(event.data.getRequestUrl()))
            .onPageBegin((): void => {
              this.failed = false; this.loading = true; this.progress = 0; this.fullscreen = false;
              this.backVisible = false; this.mainButton = miniAppButton({}); this.secondaryButton = miniAppButton({});
              this.needsCloseConfirmation = false;
              this.armLoadTimer();
            })
            .onPageEnd((): void => {
              this.loaded(); this.emit('theme_changed', { 'theme_params': miniAppTheme(this.appDark) });
              this.viewportChanged(); this.visibilityChanged(); this.armSafeAreaRepeats();
            })
            .onTitleReceive((event): void => {
              if (event && this.launch?.title === '') { this.title = event.title; }
            })
            .onProgressChange((event): void => { if (event) { this.progress = event.newProgress; } })
            .onErrorReceive((event): void => {
              if (event && event.request.isMainFrame()) {
                if (this.retryOnce('main-frame-error')) { return; }
                this.failed = true;
                this.loaded();
              }
            })
            .onHttpErrorReceive((event): void => {
              if (event && event.request.isMainFrame() && event.response.getResponseCode() >= 400) {
                this.failed = true; this.loaded();
              }
            })
            .width('100%').height('100%');
        }
        if (this.appUrl === '' && !this.failed) {
          Column({ space: 12 }) {
            LoadingProgress().width(36).height(36).color(COLOR_PRIMARY);
            Text($r('app.string.loading_short')).fontSize(14).fontColor(COLOR_TEXT_SECONDARY);
          }.width('100%').height('100%').justifyContent(FlexAlign.Center);
        }
        if (this.failed) {
          Column({ space: 14 }) {
            SymbolGlyph($r('sys.symbol.exclamationmark_circle')).fontSize(44).fontColor([COLOR_TEXT_SECONDARY]);
            Text($r('app.string.cp_cannot_open_miniapp')).fontSize(16).fontColor(COLOR_TEXT_PRIMARY);
            Button($r('app.string.settings_reload')).onClick((): void => this.reload());
          }.width('100%').height('100%').justifyContent(FlexAlign.Center).backgroundColor(COLOR_PAGE_BG);
        }
        }.layoutWeight(1).width('100%').onAreaChange((_old: Area, area: Area): void => {
        this.viewportHeight = Number(area.height); this.viewportChanged();
      });
      if (!this.failed && (this.mainButton.visible || this.secondaryButton.visible)) {
        Row({ space: 10 }) {
          if (this.secondaryButton.visible) { this.actionButton(this.secondaryButton, 'secondary_button_pressed'); }
          if (this.mainButton.visible) { this.actionButton(this.mainButton, 'main_button_pressed'); }
        }.width('100%').padding({ left: 12, right: 12, top: 10, bottom: 10 + this.bottomSafe })
          .backgroundColor(COLOR_SURFACE);
      }
      }.width('100%').height('100%');
      // 全屏：原生顶部条改为浮层，盖住页面自己的全屏 header，web 内容铺到屏幕最顶。
      if (this.fullscreen) {
        this.fullscreenHeader();
      }
    }.width('100%').height('100%').backgroundColor(this.pageBackground || COLOR_PAGE_BG)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM]);
  }
}
