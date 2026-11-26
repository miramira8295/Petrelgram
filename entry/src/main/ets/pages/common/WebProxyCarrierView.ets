import { webview } from '@kit.ArkWeb';
import { logI, logW } from '../../util/log';
import {
  KEY_WEB_PROXY_CARRIERS, webProxyCarrierManager, WebProxyCarrierSpec
} from '../../services/WebProxyHost';

// TDLib 1.8.71 原生 proxyTypeWeb 隐藏载体视图。
//
// 挂在 Index 根 Stack 里，1×1、不可点、不可滚。TDLib 通过 updateWebProxyCarrierOpened
// 打开一个或多个载体（主连接载体 + pingProxy/testProxy 临时载体），每个 carrier.id
// 独立对应一个隐藏 Web 组件；updateWebProxyCarrierClosed 时随 ForEach 销毁。
//
// 安全边界（对齐 td_api.tl webProxyCarrier 规范）：
//   · javaScriptProxy 带 permission，仅允许 carrier.origin 调用；
//   · 注入脚本在文档起始运行，严格校验 window.top === window 与 location.origin === carrier.origin；
//   · 仅暴露只读的 window[bridge_object_name]（postMessage + onmessage）；
//   · 禁止文件/数据库/定位/混合内容/新窗口/下载/权限申请，拒绝非法证书；
//   · 永不输出 carrier.url 到日志或错误消息。

function buildCarrierShimScript(origin: string, bridgeObjectName: string): string {
  const expectedOriginJson: string = JSON.stringify(origin.toLowerCase());
  const bridgeNameJson: string = JSON.stringify(bridgeObjectName);
  return "(function(){\n"
    + "  if (window.top !== window) { return; }\n"
    + "  if (String(location.origin || '').toLowerCase() !== " + expectedOriginJson + ") { return; }\n"
    + "  function api(){ return window.__petrelTdWebProxy; }\n"
    + "  function send(kind, data){\n"
    + "    var a = api();\n"
    + "    if (!a || typeof a.post !== 'function') { return; }\n"
    + "    a.post(kind, data);\n"
    + "  }\n"
    + "  function toB64(u){\n"
    + "    var s = '';\n"
    + "    var step = 8192;\n"
    + "    for (var i = 0; i < u.length; i += step) {\n"
    + "      s += String.fromCharCode.apply(null, u.subarray(i, Math.min(i + step, u.length)));\n"
    + "    }\n"
    + "    return btoa(s);\n"
    + "  }\n"
    + "  function fromB64(str){\n"
    + "    var bin = atob(str);\n"
    + "    var out = new Uint8Array(bin.length);\n"
    + "    for (var i = 0; i < bin.length; i++) { out[i] = bin.charCodeAt(i); }\n"
    + "    return out.buffer;\n"
    + "  }\n"
    + "  var listener = null;\n"
    + "  var pending = [];\n"
    + "  function dispatch(ev){\n"
    + "    if (typeof listener === 'function') {\n"
    + "      try { listener(ev); } catch (e) {}\n"
    + "    } else if (pending.length < 128) {\n"
    + "      pending.push(ev);\n"
    + "    }\n"
    + "  }\n"
    + "  var bridge = {\n"
    + "    postMessage: function(value){\n"
    + "      if (typeof value === 'string') { send('text', value); return; }\n"
    + "      if (value instanceof ArrayBuffer) { send('binary', toB64(new Uint8Array(value))); return; }\n"
    + "      if (ArrayBuffer.isView(value)) {\n"
    + "        send('binary', toB64(new Uint8Array(value.buffer, value.byteOffset, value.byteLength)));\n"
    + "        return;\n"
    + "      }\n"
    + "      throw new TypeError('Unsupported message value');\n"
    + "    }\n"
    + "  };\n"
    + "  Object.defineProperty(bridge, 'onmessage', {\n"
    + "    get: function(){ return listener; },\n"
    + "    set: function(fn){\n"
    + "      listener = fn;\n"
    + "      if (typeof listener === 'function' && pending.length > 0) {\n"
    + "        var list = pending;\n"
    + "        pending = [];\n"
    + "        for (var i = 0; i < list.length; i++) {\n"
    + "          try { listener(list[i]); } catch (e) {}\n"
    + "        }\n"
    + "      }\n"
    + "    },\n"
    + "    enumerable: true,\n"
    + "    configurable: false\n"
    + "  });\n"
    + "  try {\n"
    + "    Object.freeze(bridge);\n"
    + "    Object.defineProperty(window, " + bridgeNameJson + ", {\n"
    + "      value: bridge, writable: false, configurable: false, enumerable: true\n"
    + "    });\n"
    + "  } catch (e) {}\n"
    + "  window.__petrelTdWebProxyDeliver = function(kind, payload){\n"
    + "    var data = kind === 'binary' ? fromB64(payload) : payload;\n"
    + "    dispatch({ data: data });\n"
    + "  };\n"
    + "})();";
}

class TdWebProxyPageBridge {
  private carrierId: number;

  constructor(carrierId: number) {
    this.carrierId = carrierId;
  }

  post(kind: string, data: string): void {
    webProxyCarrierManager.onPageMessage(this.carrierId, kind, data);
  }
}

function carrierBridgePermission(origin: string): string {
  const match = /^https:\/\/(\[[^\]]+\]|[^:\/]+)(?::([0-9]+))?$/i.exec(origin);
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
struct TdWebProxyCarrierItemView {
  spec: WebProxyCarrierSpec = {
    id: 0, proxyId: 0, url: '', origin: '', pathPrefix: '',
    bridgeObjectName: 'TelegramWebProxy', isTemporary: false
  };
  private controller: webview.WebviewController = new webview.WebviewController();
  private bridge: TdWebProxyPageBridge = new TdWebProxyPageBridge(0);
  private shimScript: string = '';

  aboutToAppear(): void {
    this.bridge = new TdWebProxyPageBridge(this.spec.id);
    this.shimScript = buildCarrierShimScript(this.spec.origin, this.spec.bridgeObjectName);
  }

  aboutToDisappear(): void {
    webProxyCarrierManager.detachController(this.spec.id);
  }

  build() {
    Web({ src: this.spec.url, controller: this.controller })
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
        object: this.bridge,
        name: '__petrelTdWebProxy',
        methodList: ['post'],
        controller: this.controller,
        permission: carrierBridgePermission(this.spec.origin)
      })
      .javaScriptOnDocumentStart([
        { script: this.shimScript, scriptRules: [this.spec.origin] }
      ])
      .onControllerAttached((): void => {
        webProxyCarrierManager.attachController(this.spec.id, this.controller);
      })
      .onLoadIntercept((event): boolean => {
        const target: string = event.data.getRequestUrl();
        const origin: string = this.spec.origin;
        const allowed: boolean = target.startsWith(origin + '/')
          || target === origin || target.startsWith('about:');
        if (!allowed) {
          logW(`[WebProxy] carrier ${this.spec.id} blocked navigation to foreign origin`);
        }
        return !allowed;
      })
      .onWindowNew((): void => {
        logW(`[WebProxy] carrier ${this.spec.id} blocked new window`);
      })
      .onDownloadStart((): void => {
        logW(`[WebProxy] carrier ${this.spec.id} blocked download`);
      })
      .onPermissionRequest((event): void => {
        event.request.deny();
      })
      .onSslErrorEventReceive((event): void => {
        logW(`[WebProxy] carrier ${this.spec.id} rejected invalid certificate`);
        event.handler.handleCancel();
        webProxyCarrierManager.onPageError(this.spec.id, 'load_failed', 'ssl error');
      })
      .onErrorReceive((event): void => {
        if (event && event.request.isMainFrame()) {
          webProxyCarrierManager.onPageError(this.spec.id, 'load_failed', 'network error');
        }
      })
      .onHttpErrorReceive((event): void => {
        if (event && event.request.isMainFrame() && event.response.getResponseCode() >= 400) {
          webProxyCarrierManager.onPageError(
            this.spec.id, 'load_failed', 'http ' + event.response.getResponseCode()
          );
        }
      })
      .onRenderExited((): void => {
        webProxyCarrierManager.onPageError(this.spec.id, 'terminated');
      })
      .onPageEnd((): void => {
        logI(`[WebProxy] carrier ${this.spec.id} page loaded`);
      })
      .width(1).height(1)
      .opacity(0.01)
      .hitTestBehavior(HitTestMode.None);
  }
}

@Component
export struct WebProxyCarrierView {
  @StorageProp(KEY_WEB_PROXY_CARRIERS) private carriers: WebProxyCarrierSpec[] = [];

  build() {
    Stack() {
      ForEach(this.carriers, (item: WebProxyCarrierSpec) => {
        TdWebProxyCarrierItemView({ spec: item })
      }, (item: WebProxyCarrierSpec): string => `${item.id}`)
    }
    .width(1).height(1)
    .hitTestBehavior(HitTestMode.None);
  }
}
