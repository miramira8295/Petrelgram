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
// READY 之后的会话健康检查：只探测页面里 listener 是否还在，不看流量，
// 所以正常空闲（没有收发）不会被误判成掉线。
const HEALTH_INTERVAL_MS: number = 20000;
const HEALTH_MAX_MISSES: number = 2;
// 页面 init 去抖：同一次加载可能既走 'init' 通道、又走 'text' 里的
// tproxy-android-init，两条路都会到达这里。
const INIT_DEDUPE_MS: number = 1500;
// listener 丢失要连续几次才判定会话失效：单次可能是「帧先到、页面还没挂上
// onmessage」的启动竞态。
const LISTENER_LOSS_MISSES: number = 3;

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

// runJavaScript 返回的是脚本结果的 JSON 序列化：字符串会被带上双引号，
// 例如 'ok' 实际拿到的是 "\"ok\""。这里统一剥掉引号再比较。
function normalizeProbeResult(raw: string): string {
  const text: string = raw.trim();
  if (text.length >= 2 && text.charAt(0) === '"' && text.charAt(text.length - 1) === '"') {
    return text.substring(1, text.length - 1);
  }
  return text;
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

// BASE_PATH.md:51-59：部署路径是一个或多个 '/' 分隔段，每段以字母/数字开头，
// 其余只允许 [A-Za-z0-9_-]，总长 ≤128，存储时不留首尾斜杠。这里只做规范化，
// 合法性交给 webProxyPathProblem()，避免把非法值悄悄改成另一个部署路径。
export function normalizeWebProxyPath(raw: string): string {
  let path: string = raw.trim();
  while (path.startsWith('/')) {
    path = path.substring(1);
  }
  while (path.endsWith('/')) {
    path = path.substring(0, path.length - 1);
  }
  return path;
}

export function webProxyPathProblem(raw: string): string {
  const path: string = normalizeWebProxyPath(raw);
  if (path.length === 0) {
    return '';
  }
  if (path.length > 128) {
    return '部署路径不能超过 128 个字符';
  }
  const segments: string[] = path.split('/');
  for (let i = 0; i < segments.length; i++) {
    const seg: string = segments[i];
    if (seg.length === 0) {
      return '部署路径里不能有空段（不能出现 //）';
    }
    for (let j = 0; j < seg.length; j++) {
      const ch: string = seg.charAt(j);
      const isDigit: boolean = ch >= '0' && ch <= '9';
      const isUpper: boolean = ch >= 'A' && ch <= 'Z';
      const isLower: boolean = ch >= 'a' && ch <= 'z';
      const isExtra: boolean = ch === '_' || ch === '-';
      if (!(isDigit || isUpper || isLower || isExtra)) {
        return '部署路径只能用字母、数字、下划线和连字符';
      }
      if (j === 0 && isExtra) {
        return '部署路径的每一段都要以字母或数字开头';
      }
    }
  }
  return '';
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
  // 密钥被误填进域名框：32/34 位纯 hex（dd 前缀的 tproxy secret）明显不是域名。
  // 真机上出现过卡片标题显示一串 hex、连不上的问题，保存前就拦下来。
  if (host.length >= 32 && host.length <= 34 && host.indexOf('.') < 0) {
    const hexOnly: boolean = Array.from(host).every((ch: string): boolean => {
      const code: number = ch.charCodeAt(0);
      const isDigit: boolean = code >= 48 && code <= 57;
      const isLower: boolean = code >= 97 && code <= 102;
      const isUpper: boolean = code >= 65 && code <= 70;
      return isDigit || isLower || isUpper;
    });
    if (hexOnly) {
      return '这里要填代理域名（如 proxy.example.com），密钥请填到下面的密钥框';
    }
  }
  const pathProblem: string = webProxyPathProblem(cfg.path);
  if (pathProblem.length > 0) {
    return pathProblem;
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
    // BASE_PATH.md:34-39：带部署路径时必须用 v2 上下文，host 与 path 各占一段、
    // 之间用 '\n' 分隔（不是 '/'）。写成 host + '/' + path 时 relay 算出来的
    // capability 完全不同，任何 /<path>/ 部署都会握手失败。
    const context: string = path.length > 0
      ? BRIDGE_CONTEXT_V2_PREFIX + '\n' + host + '\n' + path
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
  // 部署路径前缀（形如 '/t7k2xw'，根部署为空串）。握手时用来核对页面确实落在
  // 我们请求的那条 base 上（PROTOCOL.md:71-72 要求校验当前导航）。
  private pathPrefix: string = '';
  private generation: number = 0;
  private retries: number = 0;
  private ready: boolean = false;
  private stopped: boolean = true;
  private handshakeTimer: number = -1;
  private totalTimer: number = -1;
  private retryTimer: number = -1;
  private jsQueue: string[] = [];
  private jsBusy: boolean = false;
  // 页面侧 listener 探测器（WebProxyCarrierView 注入 runJavaScript 实现）。
  private probeRunner: (() => Promise<string>) | null = null;
  private healthTimer: number = -1;
  private listenerMisses: number = 0;
  private probeMisses: number = 0;
  private probeInFlight: boolean = false;
  private lastInitAt: number = 0;

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
    this.probeRunner = null;
    this.stopHealth();
  }

  // 由 WebProxyCarrierView 在 onControllerAttached 时注入：读 __petrelTproxyProbe，
  // 返回 'ok' / 'nolisten' / 'noscript' / 'missing'。
  setProbeRunner(runner: () => Promise<string>): void {
    this.probeRunner = runner;
  }

  // 开一次新会话：新 nonce、新 capability、新 URL，页面重新加载。
  begin(): void {
    const cfg: WebProxyConfig | null = this.config;
    if (cfg === null) {
      return;
    }
    // 上一段会话遗留的重试定时器必须先取消：否则它会在新会话握手期间触发 begin()，
    // 重置 nonce 后页面 URL 只有 fragment 变化、文档不会重载，旧 nonce 的 init 被拒，
    // 新会话必然 handshake timeout（真机 00:28:58 实测，换配置后空转）。
    this.clearRetryTimer();
    const host: string = normalizeWebProxyHost(cfg.host);
    const secretBytes: Uint8Array = webProxySecretBytes(cfg.secret);
    const path: string = normalizeWebProxyPath(cfg.path);
    const capability: string = bridgeCapability(secretBytes, host, path);
    if (capability.length === 0 || host.length === 0) {
      this.scheduleRetry('cannot build carrier url');
      return;
    }
    this.stopped = false;
    this.ready = false;
    this.stopHealth();
    this.listenerMisses = 0;
    this.probeMisses = 0;
    this.probeInFlight = false;
    this.nonce = randomBase64Url(32);
    this.origin = 'https://' + host;
    this.pathPrefix = path.length > 0 ? '/' + path : '';
    this.url = this.origin + this.pathPrefix + '/?bridge=' + capability + '#android=' + this.nonce;
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
    this.stopHealth();
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
      logI('[WebProxy] page text ' + data.length + ' bytes: ' + data.slice(0, 200));
      return;
    }
    if (kind === 'status') {
      logW('[WebProxy] page status: ' + data);
      // 页面明确报告「有帧要收，但监听器不在了」：这是载体 JS 上下文被换掉的
      // 直接证据，必须进入会话恢复，不能只记一条日志。
      if (data === 'deliver-without-listener') {
        this.onListenerLost();
      }
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
      this.listenerMisses = 0;
      this.probeMisses = 0;
      AppStorage.setOrCreate<string>(KEY_WEB_PROXY_CARRIER_STATE, this.state);
      logI('[WebProxy] carrier ready');
      this.startHealth();
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
    // PROTOCOL.md:71-72：平台绑定要在 WebMessage 边界上校验「激活的 WebView、主框架、
    // 精确 origin 与当前导航」。javaScriptProxy 的 permission 已把 scheme/host 限死，
    // 这里再用注入脚本带回的 location 复核 origin 与 base 路径，避免页面被导航到
    // 同 host 的其它路径后仍然驱动会话。
    const pageOrigin: string = (init.origin ?? '').toLowerCase();
    const pageHref: string = init.href ?? '';
    if (pageOrigin.length > 0) {
      if (pageOrigin !== this.origin.toLowerCase()) {
        logW('[WebProxy] page init origin mismatch, ignoring: ' + pageOrigin);
        return;
      }
    } else {
      logW('[WebProxy] page init without origin field');
    }
    if (pageHref.length > 0) {
      if (!pageHref.toLowerCase().startsWith(this.origin.toLowerCase())) {
        logW('[WebProxy] page init href outside carrier origin: ' + pageHref.slice(0, 120));
        return;
      }
      const rest: string = pageHref.substring(this.origin.length);
      const expectedPrefix: string = this.pathPrefix.length > 0 ? this.pathPrefix + '/' : '/';
      if (!rest.startsWith(expectedPrefix)) {
        logW('[WebProxy] page init href on unexpected path: ' + rest.slice(0, 120));
        return;
      }
    }
    const now: number = Date.now();
    if (this.state === 'session' || this.state === 'ready') {
      if (now - this.lastInitAt < INIT_DEDUPE_MS) {
        logW('[WebProxy] duplicate page init ignored');
        return;
      }
      // 页面重新初始化（同一文档里重建会话、或旧文档的会话已不可用）：
      // 先彻底拆掉旧会话，再按新会话重新握手，不能直接忽略。
      logW('[WebProxy] page re-init, restarting tproxy session');
      this.resetSession('page re-init');
    }
    this.lastInitAt = now;
    this.clearRetryTimer();
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

  // 页面文档重新加载（手动 reload、渲染进程恢复、loadUrl）时，旧文档的 JS 上下文
  // 已经没了。旧会话必须作废，回到 loading 等新文档发 init；如果新文档一直不发，
  // armHandshake 的超时会走 scheduleRetry 整页重载。
  onPageBegin(): void {
    if (this.stopped) {
      return;
    }
    if (this.state !== 'session' && this.state !== 'ready') {
      return;
    }
    // 重载后的新文档拿的是同一个 capability，而 bootstrap capability 是
    // 一次性 bearer，relay 不会二次放行；等它用旧 URL 重新握手只会白等 10s。
    // 直接走恢复流程：用新 nonce + 新 capability 重建载体。
    logW('[WebProxy] carrier document reloaded, restarting with fresh capability');
    this.recoverSession('page reloaded');
  }

  // 页面报 deliver-without-listener。会话已就绪时出现，说明页面 JS 上下文被换掉，
  // 后面的帧全部会被静默丢弃 —— 必须进入恢复流程。
  private onListenerLost(): void {
    if (this.stopped || this.state !== 'ready') {
      return;
    }
    this.listenerMisses++;
    if (this.listenerMisses >= LISTENER_LOSS_MISSES) {
      this.recoverSession('page listener lost x' + this.listenerMisses);
      return;
    }
    this.probeListener();
  }

  // 探测页面里的 listener 是否还在。runJavaScript 本身失败按连续失败计数，
  // 避免一次偶发异常就把好会话拆掉。
  private probeListener(): void {
    if (this.probeInFlight || this.stopped) {
      return;
    }
    // 应用在后台时 ArkWeb 可能挂起页面 JS，runJavaScript 会失败或超时。
    // 这种「探不到」不能当成掉线，否则后台待久了会被误判并反复重载。
    if (!this.appForeground()) {
      return;
    }
    const runner: (() => Promise<string>) | null = this.probeRunner;
    if (runner === null) {
      this.probeMisses++;
      if (this.probeMisses >= HEALTH_MAX_MISSES) {
        this.recoverSession('probe runner missing');
      }
      return;
    }
    this.probeInFlight = true;
    runner().then((result: string): void => {
      this.probeInFlight = false;
      if (this.stopped || this.state !== 'ready') {
        return;
      }
      const verdict: string = normalizeProbeResult(result);
      if (verdict === 'ok') {
        this.listenerMisses = 0;
        this.probeMisses = 0;
        return;
      }
      logW('[WebProxy] listener probe: ' + verdict);
      this.recoverSession('page listener ' + verdict);
    }).catch((err: Error): void => {
      this.probeInFlight = false;
      if (this.stopped || this.state !== 'ready') {
        return;
      }
      this.probeMisses++;
      logW('[WebProxy] listener probe failed (' + this.probeMisses + '): ' + err.message);
      if (this.probeMisses >= HEALTH_MAX_MISSES) {
        this.recoverSession('probe failed: ' + err.message);
      }
    });
  }

  // 回到前台时补一次探测：后台期间被跳过的健康检查在这里补上。
  onAppForeground(): void {
    if (this.state === 'ready') {
      this.probeListener();
    }
  }

  private appForeground(): boolean {
    const flag: boolean | undefined = AppStorage.get<boolean>('appIsForeground');
    return flag === undefined ? true : flag;
  }

  // 会话级恢复：先彻底拆掉旧会话（关流、清队列、停健康检查），再走既有的
  // 退避重连（2s/4s/8s/16s/30s），状态同步与失败通知复用 scheduleRetry。
  private recoverSession(reason: string): void {
    if (this.stopped) {
      return;
    }
    logW('[WebProxy] recovering session: ' + reason);
    this.resetSession(reason);
    this.scheduleRetry(reason);
  }

  private resetSession(reason: string): void {
    this.stopHealth();
    this.clearHandshakeTimers();
    this.ready = false;
    this.listenerMisses = 0;
    this.probeMisses = 0;
    this.probeInFlight = false;
    this.jsQueue = [];
    this.jsBusy = false;
    webProxyTransport.carrierLost(reason);
  }

  private clearRetryTimer(): void {
    if (this.retryTimer >= 0) {
      clearTimeout(this.retryTimer);
      this.retryTimer = -1;
    }
  }

  private startHealth(): void {
    this.stopHealth();
    this.healthTimer = setInterval((): void => {
      if (this.state === 'ready') {
        this.probeListener();
      }
    }, HEALTH_INTERVAL_MS);
  }

  private stopHealth(): void {
    if (this.healthTimer >= 0) {
      clearInterval(this.healthTimer);
      this.healthTimer = -1;
    }
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
      logW('[WebProxy] drop js, no controller');
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
