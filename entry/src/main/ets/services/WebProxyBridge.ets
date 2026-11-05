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
// 字节泵的节流参数。每条 socket 消息都单独 send 一次会把 UI 线程排满——
// 实测一个图片多的页面能把它堵到 6 秒，系统 watchdog 直接杀进程
// （THREAD_BLOCK_6S）。所以攒一小会儿再一次性发。
const FLUSH_DELAY_MS: number = 16;
const FLUSH_BYTES: number = 256 * 1024;
const MAX_PENDING_BYTES: number = 2 * 1024 * 1024;
const REAP_INTERVAL_MS: number = 30000;
// 固定用字节而不是字符串发：send() 的 string 分支依赖编码，出问题时是静默
// 断连，页面只会看到 reset。
const CONNECT_ESTABLISHED: number[] = [
  0x48, 0x54, 0x54, 0x50, 0x2f, 0x31, 0x2e, 0x31, 0x20, 0x32, 0x30, 0x30, 0x20,
  0x43, 0x6f, 0x6e, 0x6e, 0x65, 0x63, 0x74, 0x69, 0x6f, 0x6e, 0x20, 0x45, 0x73,
  0x74, 0x61, 0x62, 0x6c, 0x69, 0x73, 0x68, 0x65, 0x64, 0x0d, 0x0a, 0x0d, 0x0a
];

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

// 握手阶段用 ByteStream 逐字段读，握手完成后同一条 socket 直接当隧道用，
// 剩余字节不能丢，所以这里把流交给字节泵。
class StreamingTunnel implements BridgeTunnel {
  private sock: socket.TCPSocket;
  private stream: ByteStream;
  private sink: ((data: ArrayBuffer) => void) | null = null;
  private closedCb: (() => void) | null = null;

  constructor(sock: socket.TCPSocket, stream: ByteStream) {
    this.sock = sock;
    this.stream = stream;
    this.stream.release((data: ArrayBuffer): void => {
      if (this.sink !== null) {
        this.sink(data);
      }
    });
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
    this.sink = cb;
  }

  onClosed(cb: () => void): void {
    this.closedCb = cb;
    this.sock.on('close', (): void => {
      const resolved = this.closedCb;
      if (resolved !== null) { resolved(); }
    });
    this.sock.on('error', (): void => {
      const resolved = this.closedCb;
      if (resolved !== null) { resolved(); }
    });
  }
}

interface Peer {
  client: socket.TCPSocketConnection | null;
  tunnel: BridgeTunnel | null;
  closed: boolean;
  lastActive: number;
  toTunnel: ByteRelay | null;
  toClient: ByteRelay | null;
}

// 把零碎的 socket 消息攒成少数几次 send。
//
// 【为什么必须攒】socket 回调跑在主线程上，一个页面几百上千条消息就是几百上千
// 个 JS 任务 + 同样多次 send。线程没机会让出去，UI 卡到 6 秒就会触发系统
// watchdog 把整个应用杀掉。攒批之后任务数降到每秒几十个。
class ByteRelay {
  private chunks: ArrayBuffer[] = [];
  private bytes: number = 0;
  private timer: number = -1;
  private stopped: boolean = false;
  private sink: (data: ArrayBuffer) => Promise<void>;

  constructor(sink: (data: ArrayBuffer) => Promise<void>) {
    this.sink = sink;
  }

  pending(): number {
    return this.bytes;
  }

  push(data: ArrayBuffer): void {
    if (this.stopped) {
      return;
    }
    this.chunks.push(data);
    this.bytes += data.byteLength;
    if (this.bytes >= FLUSH_BYTES || this.bytes >= MAX_PENDING_BYTES) {
      this.flush();
      return;
    }
    if (this.timer < 0) {
      this.timer = setTimeout((): void => {
        this.timer = -1;
        this.flush();
      }, FLUSH_DELAY_MS);
    }
  }

  flush(): void {
    if (this.stopped) {
      return;
    }
    if (this.timer >= 0) {
      clearTimeout(this.timer);
      this.timer = -1;
    }
    if (this.bytes === 0) {
      return;
    }
    let payload: ArrayBuffer;
    if (this.chunks.length === 1) {
      payload = this.chunks[0];
    } else {
      const joined = new Uint8Array(this.bytes);
      let offset: number = 0;
      for (let i = 0; i < this.chunks.length; i++) {
        const part = new Uint8Array(this.chunks[i]);
        joined.set(part, offset);
        offset += part.length;
      }
      payload = joined.buffer as ArrayBuffer;
    }
    this.chunks = [];
    this.bytes = 0;
    this.sink(payload).catch((): void => { this.stopped = true; });
  }

  stop(): void {
    this.stopped = true;
    if (this.timer >= 0) {
      clearTimeout(this.timer);
      this.timer = -1;
    }
    this.chunks = [];
    this.bytes = 0;
  }
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
// 空闲回收用「一个定时器扫一遍」，而不是每条消息重置一次定时器——后者在
// 大页面上等于给主线程又加了几千次 timer 分配。
let reaper: number = -1;

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
  peers.delete(peer);
  if (peer.toTunnel !== null) {
    peer.toTunnel.stop();
    peer.toTunnel = null;
  }
  if (peer.toClient !== null) {
    peer.toClient.stop();
    peer.toClient = null;
  }
  if (peer.tunnel !== null) {
    peer.tunnel.close();
    peer.tunnel = null;
  }
  if (peer.client !== null) {
    peer.client.close().catch((): void => {});
    peer.client = null;
  }
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

// SOCKS5 握手自己来，不用 TCPConnectOptions.proxy。
//
// 【为什么】用它跑第一条 CONNECT 时主线程会卡死 6 秒以上（真机日志：accept 到
// 请求后不再有任何输出，紧接着 THREAD_BLOCK_6S 把进程杀掉）。那条路径是 NetStack
// 内部的，我们既看不到也改不了，所以退回普通 TCP + 手写握手：多几十行，但每一步
// 都在自己的控制里，也能顺带把 RFC1929 鉴权做完整。
class ByteStream {
  private chunks: Uint8Array[] = [];
  private size: number = 0;
  private resolveRead: ((data: Uint8Array) => void) | null = null;
  private rejectRead: ((e: Error) => void) | null = null;
  private want: number = 0;
  private closed: boolean = false;
  private forward: ((data: ArrayBuffer) => void) | null = null;

  push(data: ArrayBuffer): void {
    if (this.forward !== null) {
      this.forward(data);
      return;
    }
    this.chunks.push(new Uint8Array(data));
    this.size += data.byteLength;
    this.pump();
  }

  onClosed(): void {
    this.closed = true;
    this.pump();
  }

  // 握手完成后把流交给字节泵；此前攒下的剩余字节先补发出去。
  release(cb: (data: ArrayBuffer) => void): void {
    this.forward = cb;
    while (this.chunks.length > 0) {
      const head = this.chunks.shift();
      if (head !== undefined) {
        cb(head.buffer as ArrayBuffer);
      }
    }
    this.size = 0;
  }

  read(count: number): Promise<Uint8Array> {
    this.want = count;
    return new Promise<Uint8Array>((resolve: (v: Uint8Array) => void,
      reject: (e: Error) => void): void => {
      this.resolveRead = resolve;
      this.rejectRead = reject;
      // 没有超时的话上游不吭声就会一直挂着，页面只会白屏，看不到任何错误。
      const timer: number = setTimeout((): void => {
        if (this.resolveRead === null) {
          return;
        }
        const current = this.rejectRead;
        this.resolveRead = null;
        this.rejectRead = null;
        if (current !== null) {
          current(new Error(`upstream timeout after ${this.size} bytes`));
        }
      }, DIAL_TIMEOUT_MS);
      const wrappedResolve = (v: Uint8Array): void => {
        clearTimeout(timer);
        resolve(v);
      };
      this.resolveRead = wrappedResolve;
      this.pump();
    });
  }

  private pump(): void {
    if (this.resolveRead === null) {
      return;
    }
    if (this.size >= this.want) {
      const out = new Uint8Array(this.want);
      let offset: number = 0;
      while (offset < this.want) {
        const head = this.chunks[0];
        const take: number = Math.min(head.length, this.want - offset);
        out.set(head.subarray(0, take), offset);
        offset += take;
        if (take === head.length) {
          this.chunks.shift();
        } else {
          this.chunks[0] = head.subarray(take);
        }
      }
      this.size -= this.want;
      const resolve = this.resolveRead;
      this.resolveRead = null;
      this.rejectRead = null;
      resolve(out);
      return;
    }
    if (this.closed) {
      const reject = this.rejectRead;
      this.resolveRead = null;
      this.rejectRead = null;
      if (reject !== null) {
        reject(new Error('upstream closed during handshake'));
      }
    }
  }
}

function bytesOf(values: number[]): ArrayBuffer {
  const out = new Uint8Array(values.length);
  for (let i = 0; i < values.length; i++) {
    out[i] = values[i];
  }
  return out.buffer as ArrayBuffer;
}

let diagDial: number = 0;

function diagDialLog(text: string): void {
  diagDial++;
  if (diagDial <= 12) {
    logW(`[WebBridge] socks5 ${text}`);
  }
}

async function dialSocks5(target: WebProxyTarget, host: string, port: number): Promise<BridgeTunnel> {
  const sock: socket.TCPSocket = socket.constructTCPSocketInstance();
  const stream = new ByteStream();
  sock.on('message', (info: socket.SocketMessageInfo): void => { stream.push(info.message); });
  sock.on('close', (): void => { stream.onClosed(); });
  sock.on('error', (): void => { stream.onClosed(); });
  const options: socket.TCPConnectOptions = {
    address: addrOf(target.host, target.port),
    timeout: DIAL_TIMEOUT_MS
  };
  await sock.connect(options);
  diagDialLog('tcp connected');

  // 1) 问候：同时声明"匿名"和"用户名密码"，让代理挑。
  const wantAuth: boolean = target.username !== '';
  await sock.send({ data: bytesOf(wantAuth ? [0x05, 0x02, 0x00, 0x02] : [0x05, 0x01, 0x00]) });
  const greeting = await stream.read(2);
  diagDialLog(`method=0x${greeting[1].toString(16)}`);
  if (greeting[0] !== 0x05) {
    sock.close().catch((): void => {});
    throw new Error('socks5: bad version');
  }
  const method: number = greeting[1];
  if (method === 0x02) {
    if (!wantAuth) {
      sock.close().catch((): void => {});
      throw new Error('socks5: proxy requires auth but none configured');
    }
    const user = new util.TextEncoder().encodeInto(target.username);
    const pass = new util.TextEncoder().encodeInto(target.password);
    const auth = new Uint8Array(3 + user.length + pass.length);
    auth[0] = 0x01;
    auth[1] = user.length;
    auth.set(user, 2);
    auth[2 + user.length] = pass.length;
    auth.set(pass, 3 + user.length);
    await sock.send({ data: auth.buffer as ArrayBuffer });
    const result = await stream.read(2);
    diagDialLog(`auth status=0x${result[1].toString(16)}`);
    if (result[1] !== 0x00) {
      sock.close().catch((): void => {});
      throw new Error('socks5: auth rejected');
    }
  } else if (method !== 0x00) {
    sock.close().catch((): void => {});
    throw new Error(`socks5: no acceptable auth method (0x${method.toString(16)})`);
  }

  // 2) CONNECT：只用域名/IPv4/IPv6 三种地址形态。
  const bare = stripIpv6Brackets(host);
  const request: number[] = [0x05, 0x01, 0x00];
  if (isIpv6Literal(bare)) {
    request.push(0x04);
    const parts = bare.split(':');
    // 完整 IPv6 展开交给正则不现实，这里只处理已压缩的常见写法：用 8 组补齐。
    const expanded: number[] = expandIpv6(bare);
    for (let i = 0; i < expanded.length; i++) {
      request.push(expanded[i]);
    }
  } else if (/^\d+\.\d+\.\d+\.\d+$/.test(bare)) {
    request.push(0x01);
    const octets = bare.split('.');
    request.push(Number(octets[0]) & 0xff, Number(octets[1]) & 0xff,
      Number(octets[2]) & 0xff, Number(octets[3]) & 0xff);
  } else {
    const name = new util.TextEncoder().encodeInto(bare);
    request.push(0x03, name.length);
    for (let i = 0; i < name.length; i++) {
      request.push(name[i]);
    }
  }
  request.push((port >> 8) & 0xff, port & 0xff);
  await sock.send({ data: bytesOf(request) });
  diagDialLog(`connect sent atyp=0x${request[3].toString(16)}`);

  const head = await stream.read(4);
  diagDialLog(`reply rep=0x${head[1].toString(16)} atyp=0x${head[3].toString(16)}`);
  if (head[1] !== 0x00) {
    sock.close().catch((): void => {});
    throw new Error(`socks5: connect rejected (0x${head[1].toString(16)})`);
  }
  const atyp: number = head[3];
  if (atyp === 0x01) {
    await stream.read(4 + 2);
  } else if (atyp === 0x04) {
    await stream.read(16 + 2);
  } else {
    const len = await stream.read(1);
    await stream.read(len[0] + 2);
  }
  diagDialLog(`tunnel ready -> ${host}:${port}`);
  return new StreamingTunnel(sock, stream);
}

// 已压缩的 IPv6 字面量 → 16 字节。只做协议需要的最小子集：支持 "::" 压缩。
function expandIpv6(bare: string): number[] {
  const out: number[] = [];
  const halves: string[] = bare.split('::');
  const headParts: string[] = halves[0] === '' ? [] : halves[0].split(':');
  const tailParts: string[] = halves.length > 1 && halves[1] !== '' ? halves[1].split(':') : [];
  const missing: number = Math.max(0, 8 - headParts.length - tailParts.length);
  const groups: string[] = [];
  for (let i = 0; i < headParts.length; i++) { groups.push(headParts[i]); }
  for (let i = 0; i < missing; i++) { groups.push('0'); }
  for (let i = 0; i < tailParts.length; i++) { groups.push(tailParts[i]); }
  while (groups.length < 8) { groups.push('0'); }
  for (let i = 0; i < groups.length; i++) {
    const value = parseInt(groups[i] === '' ? '0' : groups[i], 16) & 0xffff;
    out.push((value >> 8) & 0xff, value & 0xff);
  }
  return out;
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

// 【临时诊断·验完删】
let diagUp: number = 0;
let diagDown: number = 0;
let diagPump: number = 0;

function pump(peer: Peer, client: socket.TCPSocketConnection, tunnel: BridgeTunnel): void {
  let upBytes: number = 0;
  let downBytes: number = 0;
  const toTunnel = new ByteRelay((data: ArrayBuffer): Promise<void> => {
    upBytes += data.byteLength;
    diagUp += data.byteLength;
    if (diagPump < 16) { diagPump++; logW(`[WebBridge] up +${data.byteLength} total=${diagUp}`); }
    return tunnel.sendBytes(data);
  });
  const toClient = new ByteRelay((data: ArrayBuffer): Promise<void> => {
    downBytes += data.byteLength;
    diagDown += data.byteLength;
    if (diagPump < 16) { diagPump++; logW(`[WebBridge] down +${data.byteLength} total=${diagDown}`); }
    const options: socket.TCPSendOptions = { data: data };
    return client.send(options);
  });
  peer.toTunnel = toTunnel;
  peer.toClient = toClient;
  peer.lastActive = Date.now();
  client.on('message', (info: socket.SocketMessageInfo): void => {
    if (peer.closed) {
      return;
    }
    peer.lastActive = Date.now();
    // 单条隧道积压太多就直接断：继续攒会把内存和主线程一起拖死。
    if (toTunnel.pending() >= MAX_PENDING_BYTES) {
      closePeer(peer);
      return;
    }
    toTunnel.push(info.message);
  });
  tunnel.onMessage((data: ArrayBuffer): void => {
    if (peer.closed) {
      return;
    }
    peer.lastActive = Date.now();
    if (toClient.pending() >= MAX_PENDING_BYTES) {
      closePeer(peer);
      return;
    }
    toClient.push(data);
  });
  client.on('close', (): void => {
    logW(`[WebBridge] client closed up=${upBytes} down=${downBytes}`);
    closePeer(peer);
  });
  tunnel.onClosed((): void => {
    logW(`[WebBridge] tunnel closed up=${upBytes} down=${downBytes}`);
    closePeer(peer);
  });
}

// 【临时诊断·验完删】看是不是连接风暴/异常请求把主线程拖死。
let diagAccepts: number = 0;
let diagLogged: number = 0;

function diagLogAccept(): void {
  diagAccepts++;
  if (diagAccepts === 1 || diagAccepts % 50 === 0) {
    logW(`[WebBridge] accepts=${diagAccepts} peers=${peers.size}`);
  }
}

function diagLogRequest(head: string): void {
  if (diagLogged >= 120) {
    return;
  }
  diagLogged++;
  const lineEnd: number = head.indexOf('\r\n');
  const firstLine: string = lineEnd >= 0 ? head.substring(0, lineEnd) : head.substring(0, 80);
  logW(`[WebBridge] req#${diagLogged} ${firstLine}`);
}

function handleClient(client: socket.TCPSocketConnection, target: WebProxyTarget): void {
  diagLogAccept();
  const peer: Peer = {
    client: client, tunnel: null, closed: false,
    lastActive: Date.now(), toTunnel: null, toClient: null
  };
  if (peers.size >= MAX_PEERS) {
    logW(`[WebBridge] too many peers (${peers.size}), refusing`);
    client.close().catch((): void => {});
    return;
  }
  peers.add(peer);
  let head: string = '';
  let handshaking: boolean = false;
  const decoder = util.TextDecoder.create('utf-8');
  client.on('message', (info: socket.SocketMessageInfo): void => {
    if (peer.closed || handshaking) {
      return;
    }
    peer.lastActive = Date.now();
    head += decoder.decodeToString(new Uint8Array(info.message));
    if (head.indexOf('\r\n\r\n') < 0) {
      if (head.length > HEAD_LIMIT) {
        closePeer(peer);
      }
      return;
    }
    handshaking = true;
    diagLogRequest(head);
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
      // 先把两个方向的泵接上再回 200：Web 内核收到 200 会立刻发 ClientHello，
      // 泵晚一步接就把它丢了（TLS 握手直接 reset）。
      pump(peer, client, tunnel);
      if (request.isConnect) {
        const reply: socket.TCPSendOptions = { data: bytesOf(CONNECT_ESTABLISHED) };
        client.send(reply).catch((e: Error): void => {
          logW(`[WebBridge] 200 reply failed: ${e.message}`);
          closePeer(peer);
        });
      } else {
        // 非 CONNECT 的 http：把请求行改写成 origin-form 再灌进隧道。绝对 URI
        // 直接发给源服务器是错的，而 WebView 对 http 页面就是这么发的。
        tunnel.sendText(`${request.rewritten}${request.rest}`).catch((e: Error): void => {
          logW(`[WebBridge] head forward failed: ${e.message}`);
          closePeer(peer);
        });
      }
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
  if (reaper >= 0) {
    clearInterval(reaper);
    reaper = -1;
  }
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
