import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { util } from '@kit.ArkTS';
import { webview } from '@kit.ArkWeb';
import { logE, logI, logW } from '../util/log';
import { WebProxyFrameSink, webProxyTransport } from './WebProxyTransport';

// Telegram WEB Proxy 的**载体状态机**。
//
// 载体 = 用户自己的 tproxy-server 部署提供的 https 页面（bridge 页）。它已经实现了
// 官方 PROTOCOL.md 的客户端一侧：拿 bootstrap token 换 session、POST 上下行、把字节
// 按帧投给我们。App 这边只负责三件事：
//   1. 拼一个带 capability + nonce 的 URL，把页面装进隐藏 WebView；
//   2. 在页面里装一个只读的 TelegramWebProxy 对象，把它的 postMessage 转成帧字节；
//   3. 把 WebProxyTransport 攒好的下行帧喂回页面。
//
// 与官方 ANDROID.md 的对应关系：Android 用 addWebMessageListener 做 origin 隔离，
// 鸿蒙 ArkWeb 只有全局 javaScriptProxy，所以隔离换成 permission（限定 origin）+
// 注入脚本自己校验 window.top 与 location.origin。

export const KEY_WEB_PROXY_CARRIER_URL: string = 'webProxyCarrierUrl';
export const KEY_WEB_PROXY_CARRIER_ORIGIN: string = 'webProxyCarrierOrigin';
export const KEY_WEB_PROXY_CARRIER_STATE: string = 'webProxyCarrierState';
export const KEY_WEB_PROXY_CARRIER_GEN: string = 'webProxyCarrierGen';

// 页面对 App 的一次握手。nonce 必须与我们放进 URL 片段的那一份完全一致。
export interface WebProxyPageInit {
  nonce?: string;
  origin?: string;
  href?: string;
}

export interface WebProxyConfig {
  host: string;            // 例：proxy.example.com 或 proxy.example.com:8443
  path: string;            // 可选部署路径（不含首尾斜杠）
  secret: string;          // MTProxy secret：32/34 位 hex 或 base64url
  allowInvalidCert: boolean; // 仅自建测试环境用，默认 false
}

export interface WebProxyHostListener {
  onSessionReady(port: number): void;
  onSessionFailed(reason: string): void;
}

const BRIDGE_CONTEXT_PREFIX: string = 'tdesktop-web-proxy-bridge-v1';
const BRIDGE_CONTEXT_V2_PREFIX: string = 'tdesktop-web-proxy-bridge-v2';
const HANDSHAKE_TIMEOUT_MS: number = 10000;
const SESSION_TOTAL_TIMEOUT_MS: number = 45000;
// 官方参考实现的重连节奏：2s 起，翻倍，封顶 30s。
const RETRY_BACKOFF_MS: number[] = [2000, 4000, 8000, 16000, 30000];
// 一次性交给页面的最大批（与 WebProxyTransport 的上限一致）。
const MAX_JS_QUEUE: number = 64;

function toBase64Url(bytes: Uint8Array): string {
  const helper: util.Base64Helper = new util.Base64Helper();
  const standard: string = helper.encodeToStringSync(bytes);
  let out: string = '';
  for (let i = 0; i < standard.length; i++) {
    const ch: string = standard.charAt(i);
    if (ch === '=') {
      continue;
    }
    if (ch === '+') {
      out += '-';
    } else if (ch === '/') {
      out += '_';
    } else {
      out += ch;
    }
  }
  return out;
}

function fromBase64Url(text: string): Uint8Array {
  let standard: string = '';
  for (let i = 0; i < text.length; i++) {
    const ch: string = text.charAt(i);
    if (ch === '-') {
      standard += '+';
    } else if (ch === '_') {
      standard += '/';
    } else {
      standard += ch;
    }
  }
  while (standard.length % 4 !== 0) {
    standard += '=';
  }
  const helper: util.Base64Helper = new util.Base64Helper();
  return helper.decodeSync(standard);
}

export function base64OfBytes(bytes: Uint8Array): string {
  const helper: util.Base64Helper = new util.Base64Helper();
  return helper.encodeToStringSync(bytes);
}

export function bytesOfBase64(text: string): Uint8Array | null {
  try {
    const helper: util.Base64Helper = new util.Base64Helper();
    return helper.decodeSync(text);
  } catch (err) {
    logW('[WebProxy] base64 decode failed: ' + (err as Error).message);
    return null;
  }
}

function isHexText(text: string): boolean {
  if (text.length === 0 || text.length % 2 !== 0) {
    return false;
  }
  for (let i = 0; i < text.length; i++) {
    const ch: string = text.charAt(i);
    const isDigit: boolean = ch >= '0' && ch <= '9';
    const isLower: boolean = ch >= 'a' && ch <= 'f';
    const isUpper: boolean = ch >= 'A' && ch <= 'F';
    if (!isDigit && !isLower && !isUpper) {
      return false;
    }
  }
  return true;
}

function hexBytes(text: string): Uint8Array {
  const out: Uint8Array = new Uint8Array(text.length / 2);
  for (let i = 0; i < out.length; i++) {
    out[i] = parseInt(text.substring(i * 2, i * 2 + 2), 16);
  }
  return out;
}

// MTProxy secret 的规范化。与 OpenGram 鸿蒙端的行为一致：
//   · 32 位 hex（16 字节）= 普通 MTProxy secret；
//   · 34 位 hex（17 字节）且首字节 0xdd = 带随机填充的变体，**整段保留**；
//   · 17 字节且首字节 0x70 = 旧式前缀，剥掉；
//   · base64url（22 字符）同样接受。
export function webProxySecretBytes(raw: string): Uint8Array {
  const text: string = raw.trim();
  if (text.length === 0) {
    return new Uint8Array(0);
  }
  let bytes: Uint8Array;
  if (isHexText(text)) {
    bytes = hexBytes(text);
  } else {
    const decoded: Uint8Array | null = bytesOfBase64(text.replace('-', '+').replace('_', '/'));
    if (decoded === null) {
      return new Uint8Array(0);
    }
    bytes = decoded;
  }
  if (bytes.length === 17 && bytes[0] === 0x70) {
    const rest: Uint8Array = new Uint8Array(16);
    rest.set(bytes.subarray(1));
    return rest;
  }
  return bytes;
}

// 返回空串表示可用；否则是给用户看的错误提示。
export function webProxySecretProblem(raw: string): string {
  const text: string = raw.trim();
  if (text.length === 0) {
    return 'secret 不能为空';
  }
  const lower: string = text.toLowerCase();
  if (lower.startsWith('ee')) {
    return 'ee 开头的 secret 只用于 fake-TLS，WEB 代理不支持';
  }
  const bytes: Uint8Array = webProxySecretBytes(text);
  if (bytes.length === 0) {
    return 'secret 不是合法的 hex/base64url';
  }
  if (!(bytes.length === 16 || (bytes.length === 17 && bytes[0] === 0xdd))) {
    return 'secret 必须是 16 字节（或 dd + 16 字节）';
  }
  return '';
}

export function normalizeWebProxyHost(raw: string): string {
  let host: string = raw.trim().toLowerCase();
  if (host.startsWith('https://')) {
    host = host.substring(8);
  } else if (host.startsWith('http://')) {
    host = host.substring(7);
  }
  const slash: number = host.indexOf('/');
  if (slash >= 0) {
    host = host.substring(0, slash);
  }
  while (host.endsWith('/')) {
    host = host.substring(0, host.length - 1);
  }
  return host;
}

export function webProxyConfigProblem(cfg: WebProxyConfig): string {
  const host: string = normalizeWebProxyHost(cfg.host);
  if (host.length === 0) {
    return '代理域名不能为空';
  }
  if (host.indexOf(' ') >= 0) {
    return '代理域名里不能有空格';
  }
  if (host.indexOf('?') >= 0 || host.indexOf('#') >= 0) {
    return '代理域名里不能带查询串或片段';
  }
  const secret: string = webProxySecretProblem(cfg.secret);
  if (secret.length > 0) {
    return secret;
  }
  return '';
}

export interface WebProxyLinkInfo {
  host: string;
  path: string;
  secret: string;
}

// 用户习惯把整条分享链接粘进表单（tg://webproxy?server=…&secret=… 或
// https://t.me/webproxy?server=…&secret=…）。这里拆成三个字段；返回 null 表示
// 「这只是一段普通文本」，调用方按原样处理，避免把正常输入的域名当链接。
export function parseWebProxyLink(raw: string): WebProxyLinkInfo | null {
  const text: string = raw.trim();
  if (text.length === 0) {
    return null;
  }
  const lower: string = text.toLowerCase();
  if (lower.indexOf('webproxy?') < 0 && lower.indexOf('server=') < 0) {
    return null;
  }
  const qmark: number = text.indexOf('?');
  if (qmark < 0) {
    return null;
  }
  let query: string = text.substring(qmark + 1);
  const hash: number = query.indexOf('#');
  if (hash >= 0) {
    query = query.substring(0, hash);
  }
  let server: string = '';
  let secret: string = '';
  let path: string = '';
  const pairs: string[] = query.split('&');
  for (let i = 0; i < pairs.length; i++) {
    const pair: string = pairs[i];
    const eq: number = pair.indexOf('=');
    if (eq <= 0) {
      continue;
    }
    const key: string = pair.substring(0, eq).toLowerCase();
    let value: string = pair.substring(eq + 1);
    try {
      value = decodeURIComponent(value);
    } catch (err) {
      continue;
    }
    if (key === 'server' || key === 'host') {
      server = value.trim();
    } else if (key === 'secret') {
      secret = value.trim();
    } else if (key === 'path') {
      path = value.trim();
    }
  }
  if (server.length === 0) {
    return null;
  }
  // server 里可能带端口或部署路径：host:443、host/a/b。
  let host: string = normalizeWebProxyHost(server);
  const slash: number = server.indexOf('/');
  if (path.length === 0 && slash >= 0) {
    path = server.substring(slash + 1).trim();
  }
  while (path.startsWith('/')) {
    path = path.substring(1);
  }
  while (path.endsWith('/')) {
    path = path.substring(0, path.length - 1);
  }
  const colon: number = host.lastIndexOf(':');
  if (colon > 0 && host.indexOf(']') < 0) {
    const tail: string = host.substring(colon + 1);
    if (tail.length > 0 && tail.indexOf('.') < 0) {
      host = host.substring(0, colon);
    }
  }
  if (host.length === 0) {
    return null;
  }
  return { host: host, path: path, secret: secret };
}

function randomBase64Url(byteCount: number): string {
  const random: cryptoFramework.Random = cryptoFramework.createRandom();
  const blob: cryptoFramework.DataBlob = random.generateRandomSync(byteCount);
  return toBase64Url(blob.data);
}

// capability = base64url(HMAC-SHA256(key = secret 原始字节, msg = "<prefix>\n" + host))
// 官方 PROTOCOL.md 的 v1 形态；带部署路径时用 v2 并把 path 并进 context。
function bridgeCapability(secretBytes: Uint8Array, host: string, path: string): string {
  try {
    const generator: cryptoFramework.SymKeyGenerator = cryptoFramework.createSymKeyGenerator('HMAC');
    const keyBlob: cryptoFramework.DataBlob = { data: secretBytes };
    const key: cryptoFramework.SymKey = generator.convertKeySync(keyBlob);
    const mac: cryptoFramework.Mac = cryptoFramework.createMac('SHA256');
    mac.initSync(key);
    const encoder: util.TextEncoder = new util.TextEncoder();
    const context: string = path.length > 0
      ? BRIDGE_CONTEXT_V2_PREFIX + '\n' + host + '/' + path
      : BRIDGE_CONTEXT_PREFIX + '\n' + host;
    const message: cryptoFramework.DataBlob = { data: encoder.encodeInto(context) };
    mac.updateSync(message);
    const digest: cryptoFramework.DataBlob = mac.doFinalSync();
    return toBase64Url(digest.data);
  } catch (err) {
    logE('[WebProxy] capability hmac failed: ' + (err as Error).message);
    return '';
  }
}

export class WebProxyHost implements WebProxyFrameSink {
  private config: WebProxyConfig | null = null;
  private listener: WebProxyHostListener | null = null;
  private controller: webview.WebviewController | null = null;
  private state: string = 'idle';
  private nonce: string = '';
  private url: string = '';
  private origin: string = '';
  private generation: number = 0;
  private retries: number = 0;
  private ready: boolean = false;
  private stopped: boolean = true;
  private handshakeTimer: number = -1;
  private totalTimer: number = -1;
  private retryTimer: number = -1;
  private jsQueue: string[] = [];
  private jsBusy: boolean = false;

  setListener(listener: WebProxyHostListener): void {
    this.listener = listener;
  }

  configure(cfg: WebProxyConfig): void {
    this.config = cfg;
  }

  currentState(): string {
    return this.state;
  }

  isReady(): boolean {
    return this.ready;
  }

  allowInvalidCert(): boolean {
    const cfg: WebProxyConfig | null = this.config;
    return cfg !== null && cfg.allowInvalidCert;
  }

  // Web 组件初始化完成时由页面调用。此刻 controller 已经能 loadUrl。
  attachController(controller: webview.WebviewController): void {
    this.controller = controller;
  }

  detachController(): void {
    this.controller = null;
  }

  // 开一次新会话：新 nonce、新 capability、新 URL，页面重新加载。
  begin(): void {
    const cfg: WebProxyConfig | null = this.config;
    if (cfg === null) {
      return;
    }
    const host: string = normalizeWebProxyHost(cfg.host);
    const secretBytes: Uint8Array = webProxySecretBytes(cfg.secret);
    const capability: string = bridgeCapability(secretBytes, host, cfg.path);
    if (capability.length === 0 || host.length === 0) {
      this.scheduleRetry('cannot build carrier url');
      return;
    }
    this.stopped = false;
    this.ready = false;
    this.nonce = randomBase64Url(32);
    this.origin = 'https://' + host;
    const pathPrefix: string = cfg.path.length > 0 ? '/' + cfg.path : '';
    this.url = this.origin + pathPrefix + '/?bridge=' + capability + '#android=' + this.nonce;
    this.generation++;
    this.state = 'loading';
    this.jsQueue = [];
    this.jsBusy = false;
    this.publish();
    this.armHandshake();
  }

  stop(): void {
    this.stopped = true;
    this.ready = false;
    this.state = 'stopped';
    this.clearTimers();
    this.jsQueue = [];
    this.jsBusy = false;
    AppStorage.setOrCreate<string>(KEY_WEB_PROXY_CARRIER_URL, '');
    AppStorage.setOrCreate<string>(KEY_WEB_PROXY_CARRIER_STATE, this.state);
    webProxyTransport.carrierLost('host stopped');
  }

  // 页面侧 javaScriptProxy 的唯一入口：post(kind, data)。
  onPageMessage(kind: string, data: string): void {
    if (this.stopped) {
      return;
    }
    if (kind === 'init') {
      this.onPageInit(data);
      return;
    }
    if (kind === 'frames') {
      const bytes: Uint8Array | null = bytesOfBase64(data);
      if (bytes !== null) {
        webProxyTransport.feed(bytes);
      }
      return;
    }
    if (kind === 'text') {
      // 页面按 PROTOCOL.md 会先发一条 JSON 控制值 {"t":"tproxy-android-init",...}。
      // 这条消息本身就是「注入脚本已经在页面里跑起来」的证据：即使我们自己的
      // init 推送被时序挡住，也可以用它完成握手。
      if (data.length > 0 && data.length <= 4096 && data.indexOf('tproxy-android-init') >= 0) {
        this.onPageInit(data);
        return;
      }
      logI('[WebProxy] page text ' + data.length + ' bytes');
      return;
    }
    if (kind === 'status') {
      logW('[WebProxy] page status: ' + data);
      return;
    }
  }

  // 页面加载失败（onErrorReceive / onHttpErrorReceive）。
  onPageLoadError(reason: string): void {
    if (this.stopped || this.ready) {
      return;
    }
    this.scheduleRetry('page load failed: ' + reason);
  }

  // WebProxyFrameSink：下行帧交给页面。
  deliverFrames(bytes: Uint8Array): void {
    if (this.stopped || bytes.length === 0) {
      return;
    }
    if (this.jsQueue.length >= MAX_JS_QUEUE) {
      this.scheduleRetry('js delivery queue overflow');
      return;
    }
    this.jsQueue.push(base64OfBytes(bytes));
    this.pumpJs();
  }

  // WebProxyFrameSink：传输层会话状态变化。
  carrierChanged(reason: string): void {
    if (this.stopped) {
      return;
    }
    if (reason === 'ready') {
      this.clearHandshakeTimers();
      this.ready = true;
      this.state = 'ready';
      this.retries = 0;
      AppStorage.setOrCreate<string>(KEY_WEB_PROXY_CARRIER_STATE, this.state);
      logI('[WebProxy] carrier ready');
      const listener: WebProxyHostListener | null = this.listener;
      if (listener !== null) {
        listener.onSessionReady(webProxyTransport.currentPort());
      }
      return;
    }
    this.scheduleRetry(reason);
  }

  private onPageInit(raw: string): void {
    let init: WebProxyPageInit | null = null;
    try {
      init = JSON.parse(raw) as WebProxyPageInit;
    } catch (err) {
      this.scheduleRetry('bad init json');
      return;
    }
    if (init === null) {
      return;
    }
    const nonce: string = init.nonce ?? '';
    if (nonce.length !== this.nonce.length || nonce !== this.nonce) {
      logW('[WebProxy] nonce mismatch, ignoring page');
      return;
    }
    logI('[WebProxy] page handshake ok, starting tproxy session');
    this.clearHandshakeTimers();
    this.state = 'session';
    AppStorage.setOrCreate<string>(KEY_WEB_PROXY_CARRIER_STATE, this.state);
    this.totalTimer = setTimeout((): void => {
      this.totalTimer = -1;
      if (!this.ready) {
        this.scheduleRetry('session not ready in ' + SESSION_TOTAL_TIMEOUT_MS + 'ms');
      }
    }, SESSION_TOTAL_TIMEOUT_MS);
    webProxyTransport.beginSession();
  }

  private armHandshake(): void {
    this.clearHandshakeTimers();
    this.handshakeTimer = setTimeout((): void => {
      this.handshakeTimer = -1;
      if (this.state === 'loading') {
        this.scheduleRetry('page handshake timeout');
      }
    }, HANDSHAKE_TIMEOUT_MS);
  }

  private clearHandshakeTimers(): void {
    if (this.handshakeTimer >= 0) {
      clearTimeout(this.handshakeTimer);
      this.handshakeTimer = -1;
    }
    if (this.totalTimer >= 0) {
      clearTimeout(this.totalTimer);
      this.totalTimer = -1;
    }
  }

  private clearTimers(): void {
    this.clearHandshakeTimers();
    if (this.retryTimer >= 0) {
      clearTimeout(this.retryTimer);
      this.retryTimer = -1;
    }
  }

  private publish(): void {
    AppStorage.setOrCreate<string>(KEY_WEB_PROXY_CARRIER_ORIGIN, this.origin);
    AppStorage.setOrCreate<string>(KEY_WEB_PROXY_CARRIER_STATE, this.state);
    AppStorage.setOrCreate<number>(KEY_WEB_PROXY_CARRIER_GEN, this.generation);
    AppStorage.setOrCreate<string>(KEY_WEB_PROXY_CARRIER_URL, this.url);
  }

  private pumpJs(): void {
    if (this.jsBusy || this.stopped) {
      return;
    }
    const next: string | undefined = this.jsQueue.shift();
    if (next === undefined) {
      return;
    }
    const controller: webview.WebviewController | null = this.controller;
    if (controller === null) {
      this.jsQueue = [];
      return;
    }
    this.jsBusy = true;
    const script: string = 'window.__petrelTproxyDeliver&&window.__petrelTproxyDeliver(\'' + next + '\')';
    controller.runJavaScript(script).then((): void => {
      this.jsBusy = false;
      this.pumpJs();
    }).catch((err: Error): void => {
      this.jsBusy = false;
      this.jsQueue = [];
      this.scheduleRetry('deliver to page failed: ' + err.message);
    });
  }

  private scheduleRetry(reason: string): void {
    if (this.stopped) {
      return;
    }
    logW('[WebProxy] session lost: ' + reason);
    this.ready = false;
    this.state = 'retrying';
    this.clearHandshakeTimers();
    this.jsQueue = [];
    this.jsBusy = false;
    AppStorage.setOrCreate<string>(KEY_WEB_PROXY_CARRIER_STATE, this.state);
    webProxyTransport.carrierLost(reason);
    const listener: WebProxyHostListener | null = this.listener;
    if (listener !== null) {
      listener.onSessionFailed(reason);
    }
    const index: number = Math.min(this.retries, RETRY_BACKOFF_MS.length - 1);
    const delay: number = RETRY_BACKOFF_MS[index];
    this.retries++;
    if (this.retryTimer >= 0) {
      clearTimeout(this.retryTimer);
    }
    this.retryTimer = setTimeout((): void => {
      this.retryTimer = -1;
      this.begin();
    }, delay);
  }
}

export const webProxyHost: WebProxyHost = new WebProxyHost();
