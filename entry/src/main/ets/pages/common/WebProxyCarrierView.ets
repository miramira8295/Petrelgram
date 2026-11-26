import { webview } from '@kit.ArkWeb';
import { logI, logW } from '../../util/log';
import {
  KEY_WEB_PROXY_CARRIER_GEN, KEY_WEB_PROXY_CARRIER_ORIGIN, KEY_WEB_PROXY_CARRIER_URL, webProxyHost
} from '../../services/WebProxyHost';

// 隐藏的 WEB 代理载体。
//
// 它不属于任何业务页面：挂在 Index 根 Stack 里，1×1、不可点、不可滚，只负责让
// 用户 tproxy-server 部署的 bridge 页跑起来。页面卸载 = 载体没了 = 会话重建。
//
// 安全边界（对齐官方 ANDROID.md，鸿蒙能做到的部分）：
//   · javaScriptProxy 带 permission，只有 bridge 那个 origin 能调用；
//   · 注入脚本自己校验 window.top 与 location.origin；
//   · 禁止文件/数据库访问、禁止混合内容、禁止新窗口/下载/权限申请；
//   · 主框架导航只允许目标 origin，证书错误默认拒绝（自建测试可显式放行）。

const TP_SHIM_SCRIPT: string = "(function(){\n  if (window.top !== window) { return; }\n  var shimNonce = (function(){ var m = /[#&]android=([A-Za-z0-9_-]+)/.exec(location.hash || ''); return m ? m[1] : ''; })();\n  function nonceOf(){\n    return shimNonce;\n  }\n  function api(){ return window.__petrelTproxy; }\n  function report(kind, data){\n    var a = api();\n    if (!a || typeof a.post !== 'function') { return false; }\n    try { a.post(kind, data); return true; } catch (e) { return false; }\n  }\n  function toB64(buf){\n    var u = new Uint8Array(buf);\n    var s = '';\n    var step = 8192;\n    for (var i = 0; i < u.length; i += step) {\n      s += String.fromCharCode.apply(null, u.subarray(i, Math.min(i + step, u.length)));\n    }\n    return btoa(s);\n  }\n  function fromB64(str){\n    var bin = atob(str);\n    var out = new Uint8Array(bin.length);\n    for (var i = 0; i < bin.length; i++) { out[i] = bin.charCodeAt(i); }\n    return out.buffer;\n  }\n  function enrichInit(v){\n    try {\n      if (v.indexOf('tproxy-android-init') < 0) { return v; }\n      var o = JSON.parse(v);\n      o.origin = String(location.origin || '');\n      o.href = String(location.href || '');\n      return JSON.stringify(o);\n    } catch (e) { return v; }\n  }\n  var listener = null;\n  var bridge = {\n    postMessage: function(value){\n      if (typeof value === 'string') { report('text', enrichInit(value)); return; }\n      if (value instanceof ArrayBuffer) { report('frames', toB64(value)); return; }\n      if (value && value.buffer instanceof ArrayBuffer) { report('frames', toB64(value.buffer)); return; }\n      report('status', 'unsupported-value');\n    }\n  };\n  Object.defineProperty(bridge, 'onmessage', {\n    get: function(){ return listener; },\n    set: function(fn){ listener = fn; },\n    enumerable: true,\n    configurable: false\n  });\n  try {\n    Object.freeze(bridge);\n    Object.defineProperty(window, 'TelegramWebProxy', {\n      value: bridge, writable: false, configurable: false, enumerable: true\n    });\n  } catch (e) {}\n  window.__petrelTproxyDeliver = function(text){\n    if (typeof listener !== 'function') { report('status', 'deliver-without-listener'); return; }\n    try { listener({ data: fromB64(text) }); } catch (e) { report('status', 'deliver-error'); }\n  };\n  var tries = 0;\n  var timer = setInterval(function(){\n    tries++;\n    if (report('init', JSON.stringify({ nonce: nonceOf(), origin: location.origin, href: location.href }))) {\n      clearInterval(timer);\n    } else if (tries >= 60) {\n      clearInterval(timer);\n    }\n  }, 50);\n})();";

// 会话健康探测：读 shim 暴露的 TelegramWebProxy.onmessage（就是页面挂给我们的
// listener）。不产生流量、不依赖网络，空闲时也能判断载体是否还活着。
const TP_PROBE_SCRIPT: string = "(function(){\n  if (window.top !== window) { return; }\n  window.__petrelTproxyProbe = function(){\n    try {\n      var p = window.TelegramWebProxy;\n      if (!p) { return 'noscript'; }\n      return (typeof p.onmessage === 'function') ? 'ok' : 'nolisten';\n    } catch (e) { return 'probe-error'; }\n  };\n})();";

class TproxyPageBridge {
  post(kind: string, data: string): void {
    webProxyHost.onPageMessage(kind, data);
  }
}

function tproxyBridgePermission(origin: string): string {
  const match = /^https:\/\/(\[[^\]]+\]|[^:\/]+)(?::([0-9]+))?$/.exec(origin);
  const rule: Record<string, string> = {
    'scheme': 'https',
    'host': match === null ? 'invalid.invalid' : match[1],
    'port': match === null ? '' : (match[2] ?? ''),
    'path': ''
  };
  const permission: Record<string, Object> = { 'urlPermissionList': [rule] };
  const root: Record<string, Object> = { 'javascriptProxyPermission': permission };
  return JSON.stringify(root);
}

@Component
export struct WebProxyCarrierView {
  @StorageProp(KEY_WEB_PROXY_CARRIER_URL) @Watch('onCarrierChanged') private carrierUrl: string = '';
  // javaScriptProxy 的 permission 与 javaScriptOnDocumentStart 的 scriptRules 都绑在
  // 「建 Web 节点那一刻的 origin」上，换代理域名后同一节点不会重新绑定：页面能加载，
  // 但桥接对象被拒，init 永远到不了宿主（真机 00:31:19 实测，换配置后一直握手超时）。
  // 因此 origin 变化时要把 Web 子树整体销毁再重建。
  @StorageProp(KEY_WEB_PROXY_CARRIER_ORIGIN) @Watch('onOriginChanged') private carrierOrigin: string = '';
  @StorageProp(KEY_WEB_PROXY_CARRIER_GEN) @Watch('onCarrierChanged') private carrierGen: number = 0;
  @StorageProp('appIsForeground') @Watch('onAppForegroundChanged') private appForeground: boolean = true;
  private controller: webview.WebviewController = new webview.WebviewController();
  private bridge: TproxyPageBridge = new TproxyPageBridge();
  private boundOrigin: string = '';
  // 偶数=挂载 Web，奇数=卸载（靠一次 build 的空档销毁旧节点）。
  @State private mountId: number = 0;
  private remountTimer: number = -1;
  // Web 组件的 src 只用来装配第一次加载：之后换成 loadUrl，避免「src 变了」与
  // 「onCarrierChanged 里再 loadUrl」同时发生，把同一个 URL 加载两遍、白丢一轮握手。
  private firstUrl: string = '';
  private lastLoaded: string = '';

  aboutToAppear(): void {
    this.boundOrigin = this.carrierOrigin;
    this.firstUrl = this.carrierUrl;
    this.lastLoaded = this.carrierUrl;
  }

  aboutToDisappear(): void {
    if (this.remountTimer >= 0) {
      clearTimeout(this.remountTimer);
      this.remountTimer = -1;
    }
    webProxyHost.detachController();
  }

  onOriginChanged(): void {
    const origin: string = this.carrierOrigin;
    if (origin.length === 0 || origin === this.boundOrigin) {
      return;
    }
    // 节点还没建出来（冷启动首次拿到 origin）：只记住新值，让装配时直接用新 origin
    // 绑定桥接与加载 URL；这里再重挂一遍等于白加载一次。
    if (this.firstUrl.length === 0) {
      this.boundOrigin = origin;
      return;
    }
    logI('[WebProxy] carrier host changed, recreating web view: ' + origin);
    this.boundOrigin = origin;
    webProxyHost.detachController();
    // 先卸载旧节点；等一帧让 AppStorage 里的新 URL 落地，再用新 URL 当 src 重建。
    // 否则新节点会拿着旧的 carrierUrl 去加载，被 onLoadIntercept 当成外域拦掉，
    // 之后 firstUrl 不再是状态量、也不会触发重建，会话就永远停在握手超时。
    this.mountId++;
    if (this.remountTimer >= 0) {
      clearTimeout(this.remountTimer);
    }
    this.remountTimer = setTimeout((): void => {
      this.remountTimer = -1;
      this.controller = new webview.WebviewController();
      this.firstUrl = this.carrierUrl;
      this.lastLoaded = this.carrierUrl;
      this.mountId++;
    }, 32);
  }

  onAppForegroundChanged(): void {
    if (this.appForeground) {
      webProxyHost.onAppForeground();
    }
  }

  onCarrierChanged(): void {
    if (this.carrierUrl.length === 0) {
      // 载体被关掉（关闭代理/停服）：Web 子节点会随 if 消失，但本组件实例还在。
      // 清掉上一轮的 src，否则下次打开会拿旧 URL（含旧 nonce）去装配新节点，
      // 页面加载成功却一直「nonce mismatch」，握手永远起不来。
      this.firstUrl = '';
      this.lastLoaded = '';
      return;
    }
    if (this.mountId % 2 === 1) {
      // 正在按新 origin 重建节点，这期间不做 loadUrl。
      return;
    }
    if (this.firstUrl.length === 0) {
      // Web 节点还没建出来：直接把它作为初始 src，交给 build 装配。
      this.firstUrl = this.carrierUrl;
      this.lastLoaded = this.carrierUrl;
      return;
    }
    if (this.carrierUrl === this.lastLoaded) {
      return;
    }
    this.lastLoaded = this.carrierUrl;
    try {
      this.controller.loadUrl(this.carrierUrl);
    } catch (err) {
      logW('[WebProxy] carrier load failed: ' + (err as Error).message);
      this.lastLoaded = '';
    }
  }

  build() {
    Stack() {
      if (this.carrierUrl.length > 0 && this.mountId % 2 === 0) {
        Web({ src: this.firstUrl.length > 0 ? this.firstUrl : this.carrierUrl, controller: this.controller })
          .javaScriptAccess(true)
          .domStorageAccess(true)
          .onlineImageAccess(true)
          .multiWindowAccess(false)
          .fileAccess(false)
          .databaseAccess(false)
          .geolocationAccess(false)
          .mixedMode(MixedMode.None)
          .zoomAccess(false)
          .javaScriptProxy({
            object: this.bridge, name: '__petrelTproxy', methodList: ['post'],
            controller: this.controller, permission: tproxyBridgePermission(this.carrierOrigin)
          })
          .javaScriptOnDocumentStart([
            { script: TP_SHIM_SCRIPT, scriptRules: [this.carrierOrigin] },
            { script: TP_PROBE_SCRIPT, scriptRules: [this.carrierOrigin] }
          ])
          .onControllerAttached((): void => {
            webProxyHost.attachController(this.controller);
            webProxyHost.setProbeRunner((): Promise<string> => {
              return this.controller.runJavaScript(
                "window.__petrelTproxyProbe?window.__petrelTproxyProbe():'missing'");
            });
          })
          .onLoadIntercept((event): boolean => {
            const target: string = event.data.getRequestUrl();
            const allowed: boolean = target.startsWith(this.carrierOrigin + '/')
              || target === this.carrierOrigin || target.startsWith('about:');
            if (!allowed) {
              logW('[WebProxy] blocked navigation to foreign origin');
            }
            return !allowed;
          })
          .onWindowNew((): void => {
            logW('[WebProxy] blocked new window');
          })
          .onDownloadStart((): void => {
            logW('[WebProxy] blocked download');
          })
          .onPermissionRequest((event): void => {
            event.request.deny();
          })
          .onSslErrorEventReceive((event): void => {
            if (webProxyHost.allowInvalidCert()) {
              logW('[WebProxy] accepting invalid certificate (test mode)');
              event.handler.handleConfirm();
            } else {
              logW('[WebProxy] rejected invalid certificate');
              event.handler.handleCancel();
            }
          })
          .onErrorReceive((event): void => {
            if (event && event.request.isMainFrame()) {
              webProxyHost.onPageLoadError('onErrorReceive');
            }
          })
          .onHttpErrorReceive((event): void => {
            if (event && event.request.isMainFrame() && event.response.getResponseCode() >= 400) {
              webProxyHost.onPageLoadError('http ' + event.response.getResponseCode());
            }
          })
          .onPageBegin((): void => {
            // 页面重载/渲染进程恢复时旧文档的 JS 上下文已经没了，宿主必须在这里
            // 丢掉旧会话，等新文档重新握手。
            webProxyHost.onPageBegin();
          })
          .onPageEnd((): void => {
            logW('[WebProxy] carrier page loaded');
          })
          .width(1).height(1)
          .opacity(0.01)
          .hitTestBehavior(HitTestMode.None);
      }
    }
    .width(1).height(1)
    .hitTestBehavior(HitTestMode.None);
  }
}
