import { socket } from '@kit.NetworkKit';
import { connection } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { logE, logW } from '../util/log';
import { isIpv6Literal, stripIpv6Brackets } from '../util/ipFamily';
import { TdClient } from '../tdkit/TdClient';
import { TdObject, TdRequest } from '../tdkit/TdTypes';

// 小程序 / 内置浏览器的代理。
//
// 【为什么要在本机起一个转发】ArkWeb 唯一的原生代理入口是
// webview.ProxyController.applyProxyOverride，它只收 `[scheme://]host[:port]`
// 这样的规则串，**没有任何位置放用户名密码**。实测那两个需要鉴权的 SOCKS5
// 代理就是这样：规则配上去了，内核也收到了（NWebExtensionProxyDelegateImpl
// ::NotifyProxyInfo），但页面一个都打不开——上游在握手阶段就把没带凭据的
// 连接拒了。
//
// 所以反过来做：Web 内核只指一个**本机、无鉴权**的 HTTP 代理（就是这里），
// 三种上游协议和它们的鉴权都在这一跳补：
//   · socks5 → 交给 NetStack 自己的 SOCKS5 客户端（ProxyOptions 带凭据）
//   · http   → TCP 连代理，发 CONNECT + Proxy-Authorization: Basic
//   · https  → 先 TLS 连到代理，再在隧道里发同样的 CONNECT
// 之后双向搬字节，WebView 的 TLS 在隧道里端到端跑，我们看不到明文。
//
// 【边界】只处理 CONNECT（https 必走）和绝对 URI 的 http 请求，够 WebView 用；
// 不做缓存；吞吐受 ArkTS 字节泵限制，静态资源没问题，大文件会慢。

export const WEB_PROXY_KIND_SOCKS5: string = 'socks5';
export const WEB_PROXY_KIND_HTTP: string = 'http';
export const WEB_PROXY_KIND_HTTPS: string = 'https';

export interface WebProxyTarget {
  kind: string;
  host: string;
  port: number;
  username: string;
  password: string;
}

const BRIDGE_HOST: string = '127.0.0.1';
const BRIDGE_PORT: number = 7891;
const HEAD_LIMIT: number = 8192;
const DIAL_TIMEOUT_MS: number = 12000;
const MAX_PEERS: number = 96;
const IDLE_TIMEOUT_MS: number = 120000;
const DIAL_FAILURE_LIMIT: number = 3;

// 一条已经打通到上游的字节隧道。TCPSocket / TLSSocket 的方法签名不一样，
// 用这层薄封装让后面的搬运代码只写一份。
interface BridgeTunnel {
  sendText(text: string): Promise<void>;
  sendBytes(data: ArrayBuffer): Promise<void>;
  close(): void;
  onMessage(cb: (data: ArrayBuffer) => void): void;
  onClosed(cb: () => void): void;
}

class TcpTunnel implements BridgeTunnel {
  private sock: socket.TCPSocket;

  constructor(sock: socket.TCPSocket) {
    this.sock = sock;
  }

  sendText(text: string): Promise<void> {
    const options: socket.TCPSendOptions = { data: text };
    return this.sock.send(options);
  }

  sendBytes(data: ArrayBuffer): Promise<void> {
    const options: socket.TCPSendOptions = { data: data };
    return this.sock.send(options);
  }

  close(): void {
    this.sock.close().catch((): void => {});
  }

  onMessage(cb: (data: ArrayBuffer) => void): void {
    this.sock.on('message', (info: socket.SocketMessageInfo): void => {
      cb(info.message);
    });
  }

  onClosed(cb: () => void): void {
    this.sock.on('close', (): void => { cb(); });
    this.sock.on('error', (): void => { cb(); });
  }
}

class TlsTunnel implements BridgeTunnel {
  private sock: socket.TLSSocket;

  constructor(sock: socket.TLSSocket) {
    this.sock = sock;
  }

  sendText(text: string): Promise<void> {
    return this.sock.send(text);
  }

  sendBytes(data: ArrayBuffer): Promise<void> {
    return this.sock.send(data);
  }

  close(): void {
    this.sock.close().catch((): void => {});
  }

  onMessage(cb: (data: ArrayBuffer) => void): void {
    this.sock.on('message', (info: socket.SocketMessageInfo): void => {
      cb(info.message);
    });
  }

  onClosed(cb: () => void): void {
    this.sock.on('close', (): void => { cb(); });
    this.sock.on('error', (): void => { cb(); });
  }
}

interface Peer {
  client: socket.TCPSocketConnection | null;
  tunnel: BridgeTunnel | null;
  closed: boolean;
  idle: number;
}

interface RequestTarget {
  isConnect: boolean;
  host: string;
  port: number;
  head: string;
  rewritten: string;
  rest: string;
}

let server: socket.TCPSocketServer | null = null;
let running: boolean = false;
// 每次起桥只报第一条请求：它同时是"Web 内核到底有没有走本机这一跳"的证据。
let sawFirstRequest: boolean = false;
// 连续拨号失败计数。上游挂了的时候，与其让每个页面都白屏，不如把桥撤掉、
// 让 Web 回到直连——用户哪怕少个代理，也好过完全打不开。
let dialFailures: number = 0;
let configured: WebProxyTarget | null = null;
const peers: Set<Peer> = new Set<Peer>();

function addrOf(host: string, port: number): socket.NetAddress {
  const bare: string = stripIpv6Brackets(host);
  const addr: socket.NetAddress = {
    address: bare,
    port: port,
    family: isIpv6Literal(bare) ? 2 : 1
  };
  return addr;
}

function closePeer(peer: Peer): void {
  if (peer.closed) {
    return;
  }
  peer.closed = true;
  if (peer.idle >= 0) {
    clearTimeout(peer.idle);
    peer.idle = -1;
  }
  peers.delete(peer);
  if (peer.tunnel !== null) {
    peer.tunnel.close();
    peer.tunnel = null;
  }
  if (peer.client !== null) {
    peer.client.close().catch((): void => {});
    peer.client = null;
  }
}

function touchPeer(peer: Peer): void {
  if (peer.closed) {
    return;
  }
  if (peer.idle >= 0) {
    clearTimeout(peer.idle);
  }
  peer.idle = setTimeout((): void => { closePeer(peer); }, IDLE_TIMEOUT_MS);
}

// Basic 凭据。密码只在内存里拼一次，不进日志。
function basicAuthHeader(target: WebProxyTarget): string {
  if (target.username === '') {
    return '';
  }
  const raw: Uint8Array = new util.TextEncoder().encodeInto(`${target.username}:${target.password}`);
  const token: string = new util.Base64Helper().encodeToStringSync(raw);
  return `Proxy-Authorization: Basic ${token}\r\n`;
}

// 等代理回 CONNECT 的响应头。200 之后剩下的字节不算隧道数据（此时对端还
// 什么都没发），所以读完丢掉是安全的。
function readProxyHead(tunnel: BridgeTunnel): Promise<string> {
  return new Promise<string>((resolve: (v: string) => void, reject: (e: Error) => void): void => {
    const decoder = util.TextDecoder.create('utf-8');
    let buffered: string = '';
    let settled: boolean = false;
    const timer: number = setTimeout((): void => {
      if (settled) {
        return;
      }
      settled = true;
      reject(new Error('proxy head timeout'));
    }, DIAL_TIMEOUT_MS);
    tunnel.onMessage((data: ArrayBuffer): void => {
      if (settled) {
        return;
      }
      buffered += decoder.decodeToString(new Uint8Array(data));
      const end: number = buffered.indexOf('\r\n\r\n');
      if (end >= 0) {
        settled = true;
        clearTimeout(timer);
        resolve(buffered);
      } else if (buffered.length > HEAD_LIMIT) {
        settled = true;
        clearTimeout(timer);
        reject(new Error('proxy head too large'));
      }
    });
    tunnel.onClosed((): void => {
      if (settled) {
        return;
      }
      settled = true;
      clearTimeout(timer);
      reject(new Error('proxy closed during handshake'));
    });
  });
}

async function dialSocks5(target: WebProxyTarget, host: string, port: number): Promise<BridgeTunnel> {
  const proxy: socket.ProxyOptions = {
    type: socket.ProxyTypes.SOCKS5,
    address: addrOf(target.host, target.port)
  };
  // NetStack 的 SOCKS5 客户端自己完成 RFC1929 握手，我们不用手搓。
  if (target.username !== '') {
    proxy.username = target.username;
    proxy.password = target.password;
  }
  const options: socket.TCPConnectOptions = {
    address: addrOf(host, port),
    timeout: DIAL_TIMEOUT_MS,
    proxy: proxy
  };
  const sock: socket.TCPSocket = socket.constructTCPSocketInstance();
  await sock.connect(options);
  return new TcpTunnel(sock);
}

async function dialHttpProxy(target: WebProxyTarget, host: string, port: number,
  secure: boolean): Promise<BridgeTunnel> {
  let tunnel: BridgeTunnel;
  if (secure) {
    const tls: socket.TLSSocket = socket.constructTLSSocketInstance();
    const secureOptions: socket.TLSSecureOptions = {};
    const options: socket.TLSConnectOptions = {
      address: addrOf(target.host, target.port),
      secureOptions: secureOptions
    };
    await tls.connect(options);
    tunnel = new TlsTunnel(tls);
  } else {
    const tcp: socket.TCPSocket = socket.constructTCPSocketInstance();
    const options: socket.TCPConnectOptions = {
      address: addrOf(target.host, target.port),
      timeout: DIAL_TIMEOUT_MS
    };
    await tcp.connect(options);
    tunnel = new TcpTunnel(tcp);
  }
  const hostPort: string = isIpv6Literal(host) ? `[${stripIpv6Brackets(host)}]:${port}` : `${host}:${port}`;
  const head: string = `CONNECT ${hostPort} HTTP/1.1\r\n`
    + `Host: ${hostPort}\r\n`
    + basicAuthHeader(target)
    + 'Proxy-Connection: keep-alive\r\n\r\n';
  await tunnel.sendText(head);
  const reply: string = await readProxyHead(tunnel);
  const firstLine: string = reply.split('\r\n')[0];
  if (firstLine.indexOf(' 200') < 0) {
    tunnel.close();
    if (firstLine.indexOf(' 407') >= 0) {
      throw new Error('proxy auth rejected');
    }
    throw new Error(`proxy refused: ${firstLine}`);
  }
  return tunnel;
}

function dialUpstream(target: WebProxyTarget, host: string, port: number): Promise<BridgeTunnel> {
  if (target.kind === WEB_PROXY_KIND_SOCKS5) {
    return dialSocks5(target, host, port);
  }
  if (target.kind === WEB_PROXY_KIND_HTTPS) {
    return dialHttpProxy(target, host, port, true);
  }
  return dialHttpProxy(target, host, port, false);
}

// GET http://host:port/path HTTP/1.1 → GET /path HTTP/1.1（隧道里要 origin-form）
function rewriteToOriginForm(head: string): string {
  const lines: string[] = head.split('\r\n');
  if (lines.length === 0) {
    return head;
  }
  const parts: string[] = lines[0].split(' ');
  if (parts.length < 3) {
    return head;
  }
  const schemeEnd: number = parts[1].indexOf('://');
  if (schemeEnd < 0) {
    return head;
  }
  const afterScheme: string = parts[1].substring(schemeEnd + 3);
  const slash: number = afterScheme.indexOf('/');
  const originForm: string = slash >= 0 ? afterScheme.substring(slash) : '/';
  lines[0] = `${parts[0]} ${originForm} ${parts[2]}`;
  return lines.join('\r\n');
}

function parseTarget(head: string): RequestTarget | null {
  const lineEnd: number = head.indexOf('\r\n');
  const firstLine: string = lineEnd >= 0 ? head.substring(0, lineEnd) : head;
  const parts: string[] = firstLine.split(' ');
  if (parts.length < 2) {
    return null;
  }
  const method: string = parts[0];
  const url: string = parts[1];
  const headEnd: number = head.indexOf('\r\n\r\n');
  const rest: string = headEnd >= 0 ? head.substring(headEnd + 4) : '';
  if (method === 'CONNECT') {
    const idx: number = url.lastIndexOf(':');
    if (idx <= 0) {
      return null;
    }
    const result: RequestTarget = {
      isConnect: true,
      host: url.substring(0, idx),
      port: Number(url.substring(idx + 1)),
      head: head,
      rewritten: head,
      rest: rest
    };
    return result;
  }
  const match: RegExpMatchArray | null = url.match(/^https?:\/\/([^/:]+)(?::(\d+))?/);
  if (match === null) {
    return null;
  }
  const secure: boolean = url.startsWith('https://');
  const result: RequestTarget = {
    isConnect: secure,
    host: match[1],
    port: match[2] !== undefined ? Number(match[2]) : (secure ? 443 : 80),
    head: head,
    rewritten: rewriteToOriginForm(head),
    rest: rest
  };
  return result;
}

function pump(peer: Peer, client: socket.TCPSocketConnection, tunnel: BridgeTunnel): void {
  client.on('message', (info: socket.SocketMessageInfo): void => {
    if (peer.closed) {
      return;
    }
    touchPeer(peer);
    tunnel.sendBytes(info.message).catch((): void => { closePeer(peer); });
  });
  tunnel.onMessage((data: ArrayBuffer): void => {
    if (peer.closed) {
      return;
    }
    touchPeer(peer);
    const options: socket.TCPSendOptions = { data: data };
    client.send(options).catch((): void => { closePeer(peer); });
  });
  client.on('close', (): void => { closePeer(peer); });
  tunnel.onClosed((): void => { closePeer(peer); });
  touchPeer(peer);
}

function handleClient(client: socket.TCPSocketConnection, target: WebProxyTarget): void {
  const peer: Peer = { client: client, tunnel: null, closed: false, idle: -1 };
  if (peers.size >= MAX_PEERS) {
    logW(`[WebBridge] too many peers (${peers.size}), refusing`);
    client.close().catch((): void => {});
    return;
  }
  peers.add(peer);
  touchPeer(peer);
  let head: string = '';
  let handshaking: boolean = false;
  const decoder = util.TextDecoder.create('utf-8');
  client.on('message', (info: socket.SocketMessageInfo): void => {
    if (peer.closed || handshaking) {
      return;
    }
    touchPeer(peer);
    head += decoder.decodeToString(new Uint8Array(info.message));
    if (head.indexOf('\r\n\r\n') < 0) {
      if (head.length > HEAD_LIMIT) {
        closePeer(peer);
      }
      return;
    }
    handshaking = true;
    const request: RequestTarget | null = parseTarget(head);
    if (request === null) {
      const bad: socket.TCPSendOptions = { data: 'HTTP/1.1 400 Bad Request\r\nContent-Length: 0\r\n\r\n' };
      client.send(bad).catch((): void => {}).then((): void => { closePeer(peer); });
      return;
    }
    if (!sawFirstRequest) {
      sawFirstRequest = true;
      logW(`[WebBridge] first request -> ${request.host}:${request.port} (${request.isConnect ? 'CONNECT' : 'http'})`);
    }
    dialUpstream(target, request.host, request.port).then((tunnel: BridgeTunnel): void => {
      if (peer.closed) {
        tunnel.close();
        return;
      }
      peer.tunnel = tunnel;
      dialFailures = 0;
      if (request.isConnect) {
        const reply: socket.TCPSendOptions = { data: 'HTTP/1.1 200 Connection Established\r\n\r\n' };
        client.send(reply).catch((): void => { closePeer(peer); });
      } else {
        // 非 CONNECT 的 http：把请求行改写成 origin-form 再灌进隧道。绝对 URI
        // 直接发给源服务器是错的，而 WebView 对 http 页面就是这么发的。
        tunnel.sendText(`${request.rewritten}${request.rest}`).catch((): void => { closePeer(peer); });
      }
      pump(peer, client, tunnel);
    }).catch((e: Error): void => {
      logW(`[WebBridge] dial ${request.host}:${request.port} failed: ${e.message}`);
      const fail: socket.TCPSendOptions = { data: 'HTTP/1.1 502 Bad Gateway\r\nContent-Length: 0\r\n\r\n' };
      client.send(fail).catch((): void => {}).then((): void => { closePeer(peer); });
      dialFailures++;
      if (dialFailures >= DIAL_FAILURE_LIMIT && running) {
        logW(`[WebBridge] ${dialFailures} consecutive failures, falling back to direct`);
        stopWebBridge();
      }
    });
  });
  client.on('close', (): void => { closePeer(peer); });
}

/** 桥是否在跑（设置页显示状态用）。 */
export function webBridgeRunning(): boolean {
  return running;
}

export function webBridgeTarget(): WebProxyTarget | null {
  return configured;
}

/**
 * 起本地转发并把 Web 内核指过来。target 是用户当前启用的代理，凭据就取
 * TDLib 里存的那份。
 */
export async function startWebBridge(target: WebProxyTarget): Promise<boolean> {
  if (running) {
    if (configured !== null && configured.kind === target.kind &&
      configured.host === target.host && configured.port === target.port &&
      configured.username === target.username && configured.password === target.password) {
      return true;
    }
    stopWebBridge();
  }
  configured = target;
  try {
    const srv: socket.TCPSocketServer = socket.constructTCPSocketServerInstance();
    srv.on('connect', (client: socket.TCPSocketConnection): void => {
      handleClient(client, target);
    });
    await srv.listen(addrOf(BRIDGE_HOST, BRIDGE_PORT));
    server = srv;
    running = true;
    try {
      const proxy: connection.HttpProxy = {
        host: BRIDGE_HOST, port: BRIDGE_PORT, exclusionList: []
      };
      connection.setAppHttpProxy(proxy);
    } catch (e) {
      logW(`[WebBridge] setAppHttpProxy failed: ${(e as Error).message}`);
      stopWebBridge();
      return false;
    }
    // 凭据不进日志：只报协议和地址。
    logW(`[WebBridge] ${target.kind} ${stripIpv6Brackets(target.host)}:${target.port} `
      + `auth=${target.username === '' ? 'none' : 'basic'} -> ${BRIDGE_HOST}:${BRIDGE_PORT}`);
    return true;
  } catch (e) {
    logE(`[WebBridge] listen failed: ${(e as Error).message}`);
    configured = null;
    return false;
  }
}

/** 停桥并让 Web 回到直连。 */
export function stopWebBridge(): void {
  if (!running && server === null) {
    configured = null;
    return;
  }
  running = false;
  configured = null;
  try {
    const empty: connection.HttpProxy = { host: '', port: 0, exclusionList: [] };
    connection.setAppHttpProxy(empty);
  } catch (e) {
    logW(`[WebBridge] clear proxy failed: ${(e as Error).message}`);
  }
  peers.forEach((peer: Peer): void => { closePeer(peer); });
  peers.clear();
  if (server !== null) {
    const closing: socket.TCPSocketServer = server;
    server = null;
    closing.close().catch((): void => {});
  }
  logW('[WebBridge] stopped');
}

// TDLib 的 proxy 类型字符串。
const TD_PROXY_SOCKS5: string = 'proxyTypeSocks5';
const TD_PROXY_HTTP: string = 'proxyTypeHttp';

function kindOfTdType(type: string): string {
  if (type === TD_PROXY_SOCKS5) { return WEB_PROXY_KIND_SOCKS5; }
  if (type === TD_PROXY_HTTP) { return WEB_PROXY_KIND_HTTP; }
  return '';
}

function targetOfEntry(row: TdObject): WebProxyTarget | null {
  const proxy = (row['proxy'] as TdObject | undefined) ?? {} as TdObject;
  const type = (proxy['type'] as TdObject | undefined) ?? {} as TdObject;
  const typeName: string = (type['@type'] as string | undefined) ?? '';
  const kind: string = kindOfTdType(typeName);
  const host: string = stripIpv6Brackets((proxy['server'] as string | undefined) ?? '');
  const port: number = (proxy['port'] as number | undefined) ?? 0;
  if (kind === '' || host === '' || port <= 0) {
    return null;
  }
  const target: WebProxyTarget = {
    kind: kind,
    host: host,
    port: port,
    username: (type['username'] as string | undefined) ?? '',
    password: (type['password'] as string | undefined) ?? ''
  };
  return target;
}

/**
 * 把 TDLib 当前启用的代理接给 Web 内核。传 client 而不是自己取，避免
 * store ← services 互相 import。
 */
export async function syncWebBridgeFromTd(client: TdClient): Promise<boolean> {
  try {
    const result = await client.send({ '@type': 'getProxies' } as TdRequest, 20000);
    const rows = (result['proxies'] as TdObject[] | undefined) ?? [];
    if (rows.length === 0) {
      return false;
    }
    let enabled: TdObject | null = null;
    for (let i = 0; i < rows.length; i++) {
      if ((rows[i]['is_enabled'] as boolean | undefined) === true) {
        enabled = rows[i];
        break;
      }
    }
    if (enabled === null) {
      stopWebBridge();
      return false;
    }
    const target: WebProxyTarget | null = targetOfEntry(enabled);
    if (target === null) {
      // MTProto 之类的协议 Web 内核不认识，只能直连。
      stopWebBridge();
      return false;
    }
    return await startWebBridge(target);
  } catch (e) {
    logW(`[WebBridge] sync failed: ${(e as Error).message}`);
    return false;
  }
}
