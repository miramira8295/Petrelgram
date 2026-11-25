import { socket } from '@kit.NetworkKit';
import { logE, logI, logW } from '../util/log';

// Telegram WEB Proxy（tproxy）的**本机侧车**。
//
// 【它为什么存在】本仓的 TDLib 只认 proxyTypeHttp / proxyTypeMtproto / proxyTypeSocks5，
// 没有 1.8.69 才加的 proxyTypeWeb。官方 App 里 tgnet 自己就是 tproxy 客户端，
// 它直接跟载体（WebView 里的 bridge 页）说帧协议；我们没有那层传输，所以在本机起一个
// **只给本进程用**的 TCP 服务端，让 tgnet 用 proxyTypeMtproto 连过来：
//
//   tgnet --(obfuscated2 + MTProxy 变换后的字节)--> 127.0.0.1:<池端口> [这里]
//        --tproxy 帧(OPEN/DATA/CLOSE/WINDOW/HELLO)--> 隐藏 WebView 的 bridge 页
//        --> 用户的 tproxy-server 部署 --> 标准 MTProxy --> Telegram DC
//
// 【为什么不需要加密】tgnet 以为自己在连 MTProxy，obfuscated2 与 AES-CTR 都由它自己
// 做完了；侧车和 WebView 看到的全是变换后的密文。与官方 ANDROID.md 的 Java sidecar
// 完全同构——不自己实现加密协议。
//
// 【帧格式（PROTOCOL.md v1，全部大端）】
//   type:u8 | stream_id:u24 | payload_len:u32 | payload
//   OPEN 0x01(C,流非0,空) DATA 0x02(双向,非空) CLOSE 0x03(双向) WINDOW 0x04(双向,payload=u32 非0)
//   PING 0x05(R,流0,<=64B) PONG 0x06(原样回) HELLO 0x10(C,流0,1字节值1)
//   WELCOME 0x11(R,流0,空) BYE 0x1f(R,流0,原因)
//   单帧 payload 上限 1 MiB，DATA 分块 <= 64 KiB，每流每方向初始 4 MiB credit。

const FRAME_OPEN: number = 0x01;
const FRAME_DATA: number = 0x02;
const FRAME_CLOSE: number = 0x03;
const FRAME_WINDOW: number = 0x04;
const FRAME_PING: number = 0x05;
const FRAME_PONG: number = 0x06;
const FRAME_HELLO: number = 0x10;
const FRAME_WELCOME: number = 0x11;
const FRAME_BYE: number = 0x1f;

const HEADER_BYTES: number = 8;
const MAX_FRAME_PAYLOAD: number = 1024 * 1024;
const MAX_DATA_CHUNK: number = 64 * 1024;
const STREAM_CREDIT: number = 4 * 1024 * 1024;
// 单流待发上限。超过就关这一条流，而不是无限攒——内存上限比「多活一会儿」重要。
const MAX_STREAM_BACKLOG: number = 8 * 1024 * 1024;
// 攒批：16ms 或 256 KiB 就交给载体。逐条 socket 消息单独发会把 UI 线程排满
// （本仓 WebProxyBridge 真机实测过 THREAD_BLOCK_6S）。
const FLUSH_DELAY_MS: number = 16;
const FLUSH_BYTES: number = 256 * 1024;
const MAX_CARRIER_BATCH: number = 2 * 1024 * 1024;
const MAX_FRAMES_PER_BATCH: number = 4096;

const LISTEN_HOST: string = '127.0.0.1';
// 端口池：避开常用端口，也避开 WebProxyBridge 的 7891。
const PORT_POOL_START: number = 47810;
const PORT_POOL_END: number = 47879;
const WELCOME_TIMEOUT_MS: number = 15000;

// 一条逻辑流的本地状态。两个方向各有独立队列，混在一起会互相踩。
class SidecarStream {
  id: number;
  conn: socket.TCPSocketConnection;
  // 往载体方向：还能发多少 DATA 字节（回 WINDOW 后加回来）。
  sendCredit: number;
  // tgnet 发来、但 credit 不够还没封成 DATA 帧的剩余字节。
  blocked: Uint8Array[];
  blockedBytes: number;
  // 载体方向：已收到、还没写进 socket 的字节。
  incoming: Uint8Array[];
  incomingBytes: number;
  // socket.send 必须串行，否则数据顺序会乱。
  writing: boolean;
  // 累计已交给 socket 的字节；攒到 64 KiB 再回 WINDOW。
  receivedSinceWindow: number;
  closed: boolean;
  // OPEN 帧是否已发出：WELCOME 之前协议不允许发 OPEN。
  openSent: boolean;

  constructor(id: number, conn: socket.TCPSocketConnection) {
    this.id = id;
    this.conn = conn;
    this.sendCredit = STREAM_CREDIT;
    this.blocked = [];
    this.blockedBytes = 0;
    this.incoming = [];
    this.incomingBytes = 0;
    this.writing = false;
    this.receivedSinceWindow = 0;
    this.closed = false;
    this.openSent = false;
  }
}

class ParsedFrame {
  type: number;
  streamId: number;
  payload: Uint8Array;

  constructor(type: number, streamId: number, payload: Uint8Array) {
    this.type = type;
    this.streamId = streamId;
    this.payload = payload;
  }
}

function readU24(view: Uint8Array, offset: number): number {
  return (view[offset] << 16) | (view[offset + 1] << 8) | view[offset + 2];
}

function readU32(view: Uint8Array, offset: number): number {
  return ((view[offset] * 0x1000000) + (view[offset + 1] << 16) + (view[offset + 2] << 8) + view[offset + 3]) >>> 0;
}

function writeU24(view: Uint8Array, offset: number, value: number): void {
  view[offset] = (value >>> 16) & 0xff;
  view[offset + 1] = (value >>> 8) & 0xff;
  view[offset + 2] = value & 0xff;
}

function writeU32(view: Uint8Array, offset: number, value: number): void {
  view[offset] = (value >>> 24) & 0xff;
  view[offset + 1] = (value >>> 16) & 0xff;
  view[offset + 2] = (value >>> 8) & 0xff;
  view[offset + 3] = value & 0xff;
}

function concatBytes(parts: Uint8Array[]): Uint8Array {
  let total: number = 0;
  for (let i = 0; i < parts.length; i++) {
    total += parts[i].length;
  }
  const out: Uint8Array = new Uint8Array(total);
  let at: number = 0;
  for (let i = 0; i < parts.length; i++) {
    out.set(parts[i], at);
    at += parts[i].length;
  }
  return out;
}

// 侧车对载体的两个出口：
//   · deliverFrames：把攒好的整批帧交给 WebView（下行只走这一个方法）；
//   · carrierChanged：会话就绪 / 会话失败，让 Host 决定重连还是报错。
export interface WebProxyFrameSink {
  deliverFrames(bytes: Uint8Array): void;
  carrierChanged(reason: string): void;
}

export class WebProxyTransport {
  private server: socket.TCPSocketServer | null = null;
  private sink: WebProxyFrameSink | null = null;
  private streams: Map<number, SidecarStream> = new Map<number, SidecarStream>();
  private nextStreamId: number = 1;
  private listening: boolean = false;
  private ready: boolean = false;
  private port: number = 0;

  // 发往载体的缓冲。
  private outbox: Uint8Array[] = [];
  private outboxBytes: number = 0;
  private outboxFrames: number = 0;
  private flushTimer: number = -1;
  private welcomeTimer: number = -1;

  // 载体给我们的字节可能被任意切分，这里做粘包。
  private inbound: Uint8Array = new Uint8Array(0);

  isRunning(): boolean {
    return this.listening;
  }

  isReady(): boolean {
    return this.ready;
  }

  currentPort(): number {
    return this.port;
  }

  attachSink(sink: WebProxyFrameSink): void {
    this.sink = sink;
  }

  // 接收载体回传的整批帧（可能是半帧，粘包器会处理）。
  feed(bytes: Uint8Array): void {
    if (!this.listening) {
      return;
    }
    if (this.inbound.length === 0) {
      this.inbound = bytes;
    } else {
      this.inbound = concatBytes([this.inbound, bytes]);
    }
    this.drainInbound();
  }

  // 起本地监听。返回真正绑上的端口；端口池全占时抛错。
  async start(): Promise<number> {
    if (this.listening) {
      return this.port;
    }
    // 每个候选端口都用一个全新的 server 实例：listen 失败的实例不保证还能复用，
    // 在同一个实例上连续重试可能让整个端口池都绑不上。
    let srv: socket.TCPSocketServer | null = null;
    let bound: number = 0;
    let lastError: string = '';
    for (let port = PORT_POOL_START; port <= PORT_POOL_END; port++) {
      const candidate: socket.TCPSocketServer = socket.constructTCPSocketServerInstance();
      const addr: socket.NetAddress = { address: LISTEN_HOST, port: port, family: 1 };
      try {
        await candidate.listen(addr);
        srv = candidate;
        bound = port;
        break;
      } catch (err) {
        lastError = (err as Error).message;
        candidate.close().catch((): void => {});
      }
    }
    if (bound === 0 || srv === null) {
      throw new Error('web proxy sidecar: no free local port (' + lastError + ')');
    }
    this.server = srv;
    this.port = bound;
    this.listening = true;
    this.ready = false;
    srv.on('connect', (conn: socket.TCPSocketConnection): void => {
      this.acceptClient(conn);
    });
    logI('[WebProxy] sidecar listening on ' + LISTEN_HOST + ':' + bound);
    return bound;
  }

  // App 校完 nonce、载体可用之后调用：发 HELLO，并起 15s 等 WELCOME。
  // OPEN 只能在 WELCOME 之后发，所以此前 tgnet 连上来的流先挂着。
  beginSession(): void {
    if (!this.listening) {
      return;
    }
    const hello: Uint8Array = new Uint8Array(HEADER_BYTES + 1);
    hello[0] = FRAME_HELLO;
    writeU24(hello, 1, 0);
    writeU32(hello, 4, 1);
    hello[HEADER_BYTES] = 1;
    this.pushOutbound(hello);
    if (this.welcomeTimer >= 0) {
      clearTimeout(this.welcomeTimer);
    }
    this.welcomeTimer = setTimeout((): void => {
      this.welcomeTimer = -1;
      if (!this.ready) {
        this.failSession('no WELCOME within ' + WELCOME_TIMEOUT_MS + 'ms');
      }
    }, WELCOME_TIMEOUT_MS);
  }

  // 载体没了（页面崩了/被销毁/超时）：关全部本地流，保留监听等下一个载体。
  carrierLost(reason: string): void {
    if (!this.listening) {
      return;
    }
    logW('[WebProxy] carrier lost: ' + reason);
    this.ready = false;
    if (this.welcomeTimer >= 0) {
      clearTimeout(this.welcomeTimer);
      this.welcomeTimer = -1;
    }
    this.closeAllStreams();
    this.inbound = new Uint8Array(0);
    this.dropOutbox();
  }

  async stop(): Promise<void> {
    this.listening = false;
    this.ready = false;
    if (this.welcomeTimer >= 0) {
      clearTimeout(this.welcomeTimer);
      this.welcomeTimer = -1;
    }
    this.closeAllStreams();
    this.inbound = new Uint8Array(0);
    this.dropOutbox();
    const srv: socket.TCPSocketServer | null = this.server;
    this.server = null;
    this.port = 0;
    if (srv !== null) {
      try {
        await srv.close();
      } catch (err) {
        logW('[WebProxy] sidecar close failed: ' + (err as Error).message);
      }
    }
  }

  private acceptClient(conn: socket.TCPSocketConnection): void {
    if (!this.listening) {
      conn.close().catch((): void => {});
      return;
    }
    const id: number = this.nextStreamId;
    // 流号在会话内不复用（PROTOCOL.md）；3 字节用满后回绕。
    this.nextStreamId = id >= 0xffffff ? 1 : id + 1;
    const stream: SidecarStream = new SidecarStream(id, conn);
    this.streams.set(id, stream);

    conn.on('message', (info: socket.SocketMessageInfo): void => {
      this.onSocketBytes(stream, info.message);
    });
    conn.on('close', (): void => {
      this.closeStream(stream, true);
    });

    // OPEN 只能在 WELCOME 之后发（PROTOCOL.md）。载体还没握上手时先挂着，
    // 已连上来的字节也一起攒着，由 onWelcome() 补发。
    if (this.ready) {
      this.sendOpen(stream);
    }
  }

  // tgnet 发来的字节：能发就切成 DATA 帧，发不动的进 blocked，等 WINDOW 回来补发。
  private onSocketBytes(stream: SidecarStream, data: ArrayBuffer): void {
    if (stream.closed || !this.listening) {
      return;
    }
    if (!stream.openSent) {
      // 会话还没就绪：先按序攒下，WELCOME 之后连 OPEN 一起发。
      const held: Uint8Array = new Uint8Array(data);
      stream.blocked.push(held);
      stream.blockedBytes += held.length;
      if (stream.blockedBytes > MAX_STREAM_BACKLOG) {
        logW('[WebProxy] stream ' + stream.id + ' backlog overflow before welcome');
        this.closeStream(stream, true);
      }
      return;
    }
    const bytes: Uint8Array = new Uint8Array(data);
    if (stream.blockedBytes > 0) {
      // 有积压时必须保序：先补齐队列，新字节排在后面。
      stream.blocked.push(bytes);
      stream.blockedBytes += bytes.length;
      if (stream.blockedBytes > MAX_STREAM_BACKLOG) {
        logW('[WebProxy] stream ' + stream.id + ' backlog overflow, closing');
        this.closeStream(stream, true);
        return;
      }
      this.resumeBlocked(stream);
      return;
    }
    this.emitData(stream, bytes);
  }

  private sendOpen(stream: SidecarStream): void {
    if (stream.openSent || stream.closed) {
      return;
    }
    const open: Uint8Array = new Uint8Array(HEADER_BYTES);
    open[0] = FRAME_OPEN;
    writeU24(open, 1, stream.id);
    writeU32(open, 4, 0);
    this.pushOutbound(open);
    stream.openSent = true;
  }

  // 从 blocked 队列里尽量多地封成 DATA 帧。
  private resumeBlocked(stream: SidecarStream): void {
    while (stream.blocked.length > 0 && stream.sendCredit > 0 && !stream.closed) {
      const head: Uint8Array = stream.blocked[0];
      const room: number = Math.min(MAX_DATA_CHUNK, head.length, stream.sendCredit);
      if (room <= 0) {
        return;
      }
      this.emitData(stream, head.subarray(0, room));
      stream.blockedBytes -= room;
      if (room === head.length) {
        stream.blocked.shift();
      } else {
        stream.blocked[0] = head.subarray(room);
      }
    }
  }

  // 把一段字节按 credit 封成 DATA 帧；剩余的进 blocked（保序）。
  private emitData(stream: SidecarStream, bytes: Uint8Array): void {
    let at: number = 0;
    while (at < bytes.length) {
      if (stream.sendCredit <= 0) {
        break;
      }
      const room: number = Math.min(MAX_DATA_CHUNK, bytes.length - at, stream.sendCredit);
      const frame: Uint8Array = new Uint8Array(HEADER_BYTES + room);
      frame[0] = FRAME_DATA;
      writeU24(frame, 1, stream.id);
      writeU32(frame, 4, room);
      frame.set(bytes.subarray(at, at + room), HEADER_BYTES);
      this.pushOutbound(frame);
      stream.sendCredit -= room;
      at += room;
    }
    if (at < bytes.length) {
      const rest: Uint8Array = bytes.subarray(at).slice(0);
      stream.blocked.push(rest);
      stream.blockedBytes += rest.length;
      if (stream.blockedBytes > MAX_STREAM_BACKLOG) {
        logW('[WebProxy] stream ' + stream.id + ' backlog overflow, closing');
        this.closeStream(stream, true);
      }
    }
  }

  private drainInbound(): void {
    while (this.inbound.length >= HEADER_BYTES) {
      const type: number = this.inbound[0];
      const streamId: number = readU24(this.inbound, 1);
      const len: number = readU32(this.inbound, 4);
      if (len > MAX_FRAME_PAYLOAD) {
        this.failSession('oversized frame ' + len);
        return;
      }
      if (this.inbound.length < HEADER_BYTES + len) {
        return; // 半帧，等下一批
      }
      const payload: Uint8Array = this.inbound.slice(HEADER_BYTES, HEADER_BYTES + len);
      this.inbound = this.inbound.slice(HEADER_BYTES + len);
      this.handleFrame(new ParsedFrame(type, streamId, payload));
    }
  }

  private handleFrame(frame: ParsedFrame): void {
    if (frame.type === FRAME_DATA) {
      this.onRemoteData(frame.streamId, frame.payload);
    } else if (frame.type === FRAME_CLOSE) {
      this.onRemoteClose(frame.streamId);
    } else if (frame.type === FRAME_WINDOW) {
      this.onRemoteWindow(frame.streamId, frame.payload);
    } else if (frame.type === FRAME_WELCOME) {
      this.onWelcome();
    } else if (frame.type === FRAME_PING) {
      // 桥接页把 stream id 0 的帧一律判非法（pushLane 里 if (!id) throw），
      // 所以 PONG 没法经这条载体回去；tproxy v1 relay 也不发 PING，忽略即可。
      logW('[WebProxy] relay ping ignored');
    } else if (frame.type === FRAME_PONG) {
      // v1 我们不主动发 PING，收到就对端在探活，忽略即可。
    } else if (frame.type === FRAME_BYE) {
      this.failSession('relay closed session');
    } else if (frame.type === FRAME_OPEN) {
      // 服务端不该发 OPEN；记一条日志但不炸整个载体。
      logW('[WebProxy] unexpected OPEN for stream ' + frame.streamId);
    } else {
      logW('[WebProxy] unknown frame type ' + frame.type);
    }
  }

  private onWelcome(): void {
    if (this.welcomeTimer >= 0) {
      clearTimeout(this.welcomeTimer);
      this.welcomeTimer = -1;
    }
    if (this.ready) {
      return;
    }
    this.ready = true;
    logI('[WebProxy] tproxy session ready, streams=' + this.streams.size);
    // WELCOME 之后，之前挂着的流的 OPEN 才能发出去；这里把已连上的流按顺序补发 OPEN。
    const pending: number[] = [];
    this.streams.forEach((_s: SidecarStream, id: number): void => {
      pending.push(id);
    });
    for (let i = 0; i < pending.length; i++) {
      const stream: SidecarStream | undefined = this.streams.get(pending[i]);
      if (stream !== undefined) {
        if (!stream.openSent) {
          this.sendOpen(stream);
        }
        this.resumeBlocked(stream);
      }
    }
    const sink: WebProxyFrameSink | null = this.sink;
    if (sink !== null) {
      sink.carrierChanged('ready');
    }
  }

  private onRemoteData(streamId: number, payload: Uint8Array): void {
    const stream: SidecarStream | undefined = this.streams.get(streamId);
    if (stream === undefined) {
      // 流已关（tombstone）：按协议直接丢，不重开。
      return;
    }
    if (stream.incomingBytes + payload.length > STREAM_CREDIT) {
      logE('[WebProxy] stream ' + streamId + ' exceeded credit window');
      this.closeStream(stream, true);
      return;
    }
    stream.incoming.push(payload.slice(0));
    stream.incomingBytes += payload.length;
    this.pumpStreamWrites(stream);
  }

  private pumpStreamWrites(stream: SidecarStream): void {
    if (stream.writing || stream.closed) {
      return;
    }
    const head: Uint8Array | undefined = stream.incoming.shift();
    if (head === undefined) {
      // 队列空了：把还没归还的 credit 立刻还掉。只按 64 KiB 攒批会有个死角——
      // 一条流长期发小包、总量攒不到 64 KiB 就停住，4 MiB credit 会永不归还。
      if (stream.receivedSinceWindow > 0) {
        this.sendWindow(stream, stream.receivedSinceWindow);
        stream.receivedSinceWindow = 0;
      }
      return;
    }
    stream.incomingBytes -= head.length;
    stream.writing = true;
    const payload: ArrayBuffer = head.buffer.slice(head.byteOffset, head.byteOffset + head.length) as ArrayBuffer;
    const options: socket.TCPSendOptions = { data: payload };
    stream.conn.send(options).then((): void => {
      stream.writing = false;
      if (stream.closed) {
        return;
      }
      stream.receivedSinceWindow += head.length;
      if (stream.receivedSinceWindow >= MAX_DATA_CHUNK) {
        this.sendWindow(stream, stream.receivedSinceWindow);
        stream.receivedSinceWindow = 0;
      }
      this.pumpStreamWrites(stream);
    }).catch((err: Error): void => {
      stream.writing = false;
      logW('[WebProxy] stream ' + stream.id + ' write failed: ' + err.message);
      this.closeStream(stream, true);
    });
  }

  private sendWindow(stream: SidecarStream, credit: number): void {
    const frame: Uint8Array = new Uint8Array(HEADER_BYTES + 4);
    frame[0] = FRAME_WINDOW;
    writeU24(frame, 1, stream.id);
    writeU32(frame, 4, 4);
    writeU32(frame, HEADER_BYTES, credit);
    this.pushOutbound(frame);
  }

  private onRemoteWindow(streamId: number, payload: Uint8Array): void {
    const stream: SidecarStream | undefined = this.streams.get(streamId);
    if (stream === undefined || payload.length < 4) {
      return;
    }
    const credit: number = readU32(payload, 0);
    if (credit === 0) {
      return;
    }
    stream.sendCredit = Math.min(STREAM_CREDIT, stream.sendCredit + credit);
    this.resumeBlocked(stream);
  }

  private onRemoteClose(streamId: number): void {
    const stream: SidecarStream | undefined = this.streams.get(streamId);
    if (stream === undefined) {
      return;
    }
    // 对端已经知道这条流关了，不用再回 CLOSE。
    this.closeStream(stream, false);
  }

  // notifyCarrier=false 表示对端先关的，不用回 CLOSE。
  private closeStream(stream: SidecarStream, notifyCarrier: boolean): void {
    if (stream.closed) {
      return;
    }
    stream.closed = true;
    this.streams.delete(stream.id);
    if (notifyCarrier) {
      const frame: Uint8Array = new Uint8Array(HEADER_BYTES);
      frame[0] = FRAME_CLOSE;
      writeU24(frame, 1, stream.id);
      writeU32(frame, 4, 0);
      this.pushOutbound(frame);
    }
    stream.incoming = [];
    stream.incomingBytes = 0;
    stream.blocked = [];
    stream.blockedBytes = 0;
    stream.conn.close().catch((): void => {});
  }

  private closeAllStreams(): void {
    const ids: number[] = [];
    this.streams.forEach((_s: SidecarStream, id: number): void => {
      ids.push(id);
    });
    for (let i = 0; i < ids.length; i++) {
      const stream: SidecarStream | undefined = this.streams.get(ids[i]);
      if (stream !== undefined) {
        this.closeStream(stream, true);
      }
    }
    this.streams.clear();
  }

  private dropOutbox(): void {
    if (this.flushTimer >= 0) {
      clearTimeout(this.flushTimer);
      this.flushTimer = -1;
    }
    this.outbox = [];
    this.outboxBytes = 0;
    this.outboxFrames = 0;
  }

  private pushOutbound(frame: Uint8Array): void {
    this.outbox.push(frame);
    this.outboxBytes += frame.length;
    this.outboxFrames += 1;
    if (this.outboxBytes >= FLUSH_BYTES || this.outboxFrames >= MAX_FRAMES_PER_BATCH) {
      this.flush();
      return;
    }
    if (this.flushTimer < 0) {
      this.flushTimer = setTimeout((): void => {
        this.flushTimer = -1;
        this.flush();
      }, FLUSH_DELAY_MS);
    }
  }

  private flush(): void {
    if (this.flushTimer >= 0) {
      clearTimeout(this.flushTimer);
      this.flushTimer = -1;
    }
    if (this.outbox.length === 0) {
      return;
    }
    const batch: Uint8Array = concatBytes(this.outbox);
    this.outbox = [];
    this.outboxBytes = 0;
    this.outboxFrames = 0;
    const sink: WebProxyFrameSink | null = this.sink;
    if (sink === null) {
      return;
    }
    let at: number = 0;
    while (at < batch.length) {
      const end: number = Math.min(at + MAX_CARRIER_BATCH, batch.length);
      sink.deliverFrames(batch.subarray(at, end));
      at = end;
    }
  }

  private failSession(reason: string): void {
    logE('[WebProxy] session failed: ' + reason);
    this.ready = false;
    if (this.welcomeTimer >= 0) {
      clearTimeout(this.welcomeTimer);
      this.welcomeTimer = -1;
    }
    this.closeAllStreams();
    this.inbound = new Uint8Array(0);
    this.dropOutbox();
    const sink: WebProxyFrameSink | null = this.sink;
    if (sink !== null) {
      sink.carrierChanged('failed:' + reason);
    }
  }
}

// 全应用一个实例：同一时刻只允许一个活动 WEB 代理（TDLib 侧也只有一个）。
export const webProxyTransport: WebProxyTransport = new WebProxyTransport();
