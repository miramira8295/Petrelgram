import { webview } from '@kit.ArkWeb';
import { logW } from '../../util/log';
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

const TP_SHIM_SCRIPT: string = "(function(){\n  if (window.top !== window) { return; }\n  var shimNonce = (function(){ var m = /[#&]android=([A-Za-z0-9_-]+)/.exec(location.hash || ''); return m ? m[1] : ''; })();\n  function nonceOf(){\n    return shimNonce;\n  }\n  function api(){ return window.__petrelTproxy; }\n  function report(kind, data){\n    var a = api();\n    if (!a || typeof a.post !== 'function') { return false; }\n    try { a.post(kind, data); return true; } catch (e) { return false; }\n  }\n  function toB64(buf){\n    var u = new Uint8Array(buf);\n    var s = '';\n    var step = 8192;\n    for (var i = 0; i < u.length; i += step) {\n      s += String.fromCharCode.apply(null, u.subarray(i, Math.min(i + step, u.length)));\n    }\n    return btoa(s);\n  }\n  function fromB64(str){\n    var bin = atob(str);\n    var out = new Uint8Array(bin.length);\n    for (var i = 0; i < bin.length; i++) { out[i] = bin.charCodeAt(i); }\n    return out.buffer;\n  }\n  var listener = null;\n  var bridge = {\n    postMessage: function(value){\n      if (typeof value === 'string') { report('text', value); return; }\n      if (value instanceof ArrayBuffer) { report('frames', toB64(value)); return; }\n      if (value && value.buffer instanceof ArrayBuffer) { report('frames', toB64(value.buffer)); return; }\n      report('status', 'unsupported-value');\n    }\n  };\n  Object.defineProperty(bridge, 'onmessage', {\n    get: function(){ return listener; },\n    set: function(fn){ listener = fn; },\n    enumerable: true,\n    configurable: false\n  });\n  try {\n    Object.freeze(bridge);\n    Object.defineProperty(window, 'TelegramWebProxy', {\n      value: bridge, writable: false, configurable: false, enumerable: true\n    });\n  } catch (e) {}\n  window.__petrelTproxyDeliver = function(text){\n    if (typeof listener !== 'function') { report('status', 'deliver-without-listener'); return; }\n    try { listener({ data: fromB64(text) }); } catch (e) { report('status', 'deliver-error'); }\n  };\n  var tries = 0;\n  var timer = setInterval(function(){\n    tries++;\n    if (report('init', JSON.stringify({ nonce: nonceOf(), origin: location.origin, href: location.href }))) {\n      clearInterval(timer);\n    } else if (tries >= 60) {\n      clearInterval(timer);\n    }\n  }, 50);\n})();";

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
  @StorageProp(KEY_WEB_PROXY_CARRIER_ORIGIN) private carrierOrigin: string = '';
  @StorageProp(KEY_WEB_PROXY_CARRIER_GEN) @Watch('onCarrierChanged') private carrierGen: number = 0;
  private controller: webview.WebviewController = new webview.WebviewController();
  private bridge: TproxyPageBridge = new TproxyPageBridge();
  // Web 组件的 src 只用来装配第一次加载：之后换成 loadUrl，避免「src 变了」与
  // 「onCarrierChanged 里再 loadUrl」同时发生，把同一个 URL 加载两遍、白丢一轮握手。
  private firstUrl: string = '';
  private lastLoaded: string = '';

  aboutToAppear(): void {
    this.firstUrl = this.carrierUrl;
    this.lastLoaded = this.carrierUrl;
  }

  aboutToDisappear(): void {
    webProxyHost.detachController();
  }

  onCarrierChanged(): void {
    if (this.carrierUrl.length === 0) {
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
      if (this.carrierUrl.length > 0) {
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
          .javaScriptOnDocumentStart([{ script: TP_SHIM_SCRIPT, scriptRules: [this.carrierOrigin] }])
          .onControllerAttached((): void => {
            webProxyHost.attachController(this.controller);
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
