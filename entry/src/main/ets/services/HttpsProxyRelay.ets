import { resolvePreferIpv6 } from './NetworkIpPreference';
import { stripIpv6Brackets } from '../util/ipFamily';
import { SocksProxyHandshake, proxyTarget, ProxyTarget } from '../util/socksProxyProtocol';
import { verifyProxyCertificateName } from './HttpsProxyCertificate';
import { socket } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { logW } from '../util/log';
import {
  HttpsProxyRecord, HTTPS_PROXY_MARKER, ProxyHeaderReader, parseProxyConnect,
  proxyConnectHeader, proxyConnectSucceeded, relayProxyType, PROXY_DIRECT, PROXY_HTTPS,
  ProxyHttpRequestRewriter, parseProxyHttpPost, proxyAsciiBytes
} from '../util/httpsProxyProtocol';

const MAX_CONNECTIONS: number = 32;
const MAX_QUEUED_BYTES: number = 512 * 1024;
const HANDSHAKE_TIMEOUT: number = 15000;
// A tunnel that moves no bytes in either direction still owns one of
// MAX_CONNECTIONS. Handshakes have HANDSHAKE_TIMEOUT; established tunnels had
// nothing. TDLib pings every 60s by default, so 90s leaves a 30s margin.
const IDLE_TIMEOUT: number = 90000;
const IDLE_SWEEP_INTERVAL: number = 15000;
// Diagnostic bucketing only: "idle this long" is the shape of a zombie slot.
const IDLE_DIAGNOSTIC_MS: number = 30000;
const CONNECT_OK: ArrayBuffer = new Uint8Array('HTTP/1.1 200 Connection Established\r\n\r\n'
  .split('').map((c: string): number => c.charCodeAt(0))).buffer as ArrayBuffer;

// HarmonyOS documents encodeInto('') as undefined despite its Uint8Array type.
// Keep empty credentials valid without calling the encoder. A failed nonempty
// encoding must never silently turn configured credentials into no-auth.
export function encodeProxyUtf8(text: string,
  encode: (value: string) => Uint8Array | undefined =
    (value: string): Uint8Array => new util.TextEncoder().encodeInto(value)): Uint8Array {
  if (text.length === 0) { return new Uint8Array(0); }
  const bytes = encode(text);
  if (bytes === undefined || bytes.length === 0) { throw new Error('proxy credential encoding failed'); }
  return bytes;
}

function basic(user: string, password: string): string {
  return 'Basic ' + new util.Base64Helper().encodeToStringSync(
    encodeProxyUtf8(`${user}:${password}`));
}

export interface RelayEndpoint {
  onData(callback: (data: ArrayBuffer) => void): void;
  onEnd(callback: () => void): void;
  send(data: string | ArrayBuffer): Promise<void>;
  close(): void;
}

export interface RelayTlsEndpoint extends RelayEndpoint {
  bind(family: number): Promise<void>;
  connect(host: string, port: number, family: number, timeout: number): Promise<void>;
  verifyName(host: string): Promise<void>;
}

class LocalRelayEndpoint implements RelayEndpoint {
  private socket: socket.TCPSocketConnection;
  private closed: boolean = false;
  private retired: boolean = false;
  private receiverReady: boolean = false;
  private nativeCloseStarted: boolean = false;
  private pendingSends: number = 0;
  private message: ((data: ArrayBuffer) => void) | undefined = undefined;
  private end: (() => void) | undefined = undefined;
  constructor(local: socket.TCPSocketConnection) {
    this.socket = local;
    localRelayEndpoints.add(this);
    // Native ClientHandler waits for this listener. Register even for rejected
    // connections, and retain both the object and listeners until native close.
    // off(message) or GC before that event can strand its initialization thread.
    this.socket.on('message', (info: socket.SocketMessageInfo): void => {
      // A message proves ClientHandler has read its fd from the native map.
      // Merely registering the listener does not: early close can erase that
      // entry before WaitForManagerReady reads it (map[] then yields fd 0).
      this.receiverReady = true;
      if (this.closed) { this.closeWhenReady(); } else { this.message?.(info.message); }
    });
    this.socket.on('close', (): void => this.retire());
    this.socket.on('error', (): void => {
      const end = this.end;
      this.close();
      end?.();
    });
  }
  onData(callback: (data: ArrayBuffer) => void): void {
    if (!this.closed) { this.message = callback; }
  }
  onEnd(callback: () => void): void { if (!this.closed) { this.end = callback; } }
  async send(data: string | ArrayBuffer): Promise<void> {
    if (this.closed) { throw new Error('local relay closed'); }
    this.pendingSends++;
    try { await this.socket.send({ data: data }); }
    finally { this.pendingSends--; this.closeWhenReady(); }
  }
  close(): void {
    if (this.closed) { return; }
    this.closed = true;
    this.message = undefined;
    this.end = undefined;
    this.closeWhenReady();
  }
  private closeWhenReady(): void {
    if (!this.closed || !this.receiverReady || this.retired || this.nativeCloseStarted || this.pendingSends > 0) {
      return;
    }
    this.nativeCloseStarted = true;
    // Until first data (or peer close) keep the listener and fd intact. This is
    // an initialization handshake, not a delay guessed from the native timing.
    try { this.socket.close().catch((): void => { this.checkAlive(); }); }
    catch (_error) { this.checkAlive(); }
  }
  async checkAlive(): Promise<void> {
    if (this.retired) { return; }
    try { await this.socket.getRemoteAddress(); }
    catch (_error) {
      // Native accepted-client receive errors are reported on the SERVER, and
      // may remove this client without a per-client close event. No fd remains.
      this.retire();
    }
  }
  private retire(): void {
    if (this.retired) { return; }
    this.retired = true;
    const end = this.end;
    this.closed = true;
    this.message = undefined;
    this.end = undefined;
    try { this.socket.off('message'); this.socket.off('close'); this.socket.off('error'); } catch (_error) {}
    localRelayEndpoints.delete(this);
    end?.();
  }
}

// Native close may arrive after the listener/relay itself has been replaced.
// Do not let that replacement finalize a client still entering ClientHandler.
const localRelayEndpoints: Set<LocalRelayEndpoint> = new Set();

// Never overlap a native close with bind/connect/send. Logical cancellation is
// immediate; physical cleanup follows the in-flight operation, at most once.
// This also avoids the old close-now + close-again-in-finally sequence.
class RelayOperationGate {
  private closed: boolean = false;
  private pending: number = 0;
  private touched: boolean = false;
  private closeStarted: boolean = false;
  private cleanup: () => Promise<void>;
  constructor(cleanup: () => Promise<void>) { this.cleanup = cleanup; }
  alive(): boolean { return !this.closed; }
  async run(task: () => Promise<void>): Promise<void> {
    if (this.closed) { throw new Error('relay dial cancelled'); }
    this.pending++; this.touched = true;
    try { await task(); }
    finally { this.pending--; this.drain(); }
  }
  close(): void { this.closed = true; this.drain(); }
  private drain(): void {
    if (!this.closed || this.pending !== 0 || !this.touched || this.closeStarted) { return; }
    this.closeStarted = true;
    this.cleanup().catch((): void => {});
  }
}

class TlsRelayEndpoint implements RelayTlsEndpoint {
  private socket: socket.TLSSocket = socket.constructTLSSocketInstance();
  private gate: RelayOperationGate = new RelayOperationGate(async (): Promise<void> => {
    // Failed construction/bind or peer close need not own a live socket.
    const state = await this.socket.getState();
    if (!state.isClose) { await this.socket.close(); }
  });
  bind(family: number): Promise<void> {
    return this.gate.run((): Promise<void> => this.socket.bind({
      address: family === 2 ? '::' : '0.0.0.0', family: family, port: 0 }));
  }
  onData(callback: (data: ArrayBuffer) => void): void {
    this.socket.on('message', (info: socket.SocketMessageInfo): void => {
      if (this.gate.alive()) { callback(info.message); }
    });
  }
  onEnd(callback: () => void): void { this.socket.on('close', callback); this.socket.on('error', callback); }
  connect(host: string, port: number, family: number, timeout: number): Promise<void> {
    return this.gate.run((): Promise<void> => this.socket.connect({
      address: { address: host, port: port, family: family },
      secureOptions: { protocols: [socket.Protocol.TLSv12, socket.Protocol.TLSv13] },
      ALPNProtocols: ['http/1.1'], skipRemoteValidation: false, timeout: timeout }));
  }
  verifyName(host: string): Promise<void> {
    return this.gate.run((): Promise<void> => verifyProxyCertificateName(this.socket, host));
  }
  send(data: string | ArrayBuffer): Promise<void> {
    return this.gate.run((): Promise<void> => this.socket.send(data));
  }
  close(): void {
    if (!this.gate.alive()) { return; }
    try { this.socket.off('message'); this.socket.off('close'); this.socket.off('error'); } catch (_error) {}
    this.gate.close();
  }
}

class TcpRelayEndpoint implements RelayTlsEndpoint {
  private socket: socket.TCPSocket = socket.constructTCPSocketInstance();
  private gate: RelayOperationGate = new RelayOperationGate(async (): Promise<void> => {
    const state = await this.socket.getState();
    if (!state.isClose) { await this.socket.close(); }
  });
  bind(family: number): Promise<void> {
    return this.gate.run((): Promise<void> => this.socket.bind({
      address: family === 2 ? '::' : '0.0.0.0', family: family, port: 0 }));
  }
  onData(callback: (data: ArrayBuffer) => void): void {
    this.socket.on('message', (info: socket.SocketMessageInfo): void => {
      if (this.gate.alive()) { callback(info.message); }
    });
  }
  onEnd(callback: () => void): void { this.socket.on('close', callback); this.socket.on('error', callback); }
  connect(host: string, port: number, family: number, timeout: number): Promise<void> {
    return this.gate.run((): Promise<void> => this.socket.connect({
      address: { address: host, port: port, family: family }, timeout: timeout }));
  }
  async verifyName(_host: string): Promise<void> {}
  send(data: string | ArrayBuffer): Promise<void> {
    return this.gate.run((): Promise<void> => this.socket.send({ data: data }));
  }
  close(): void {
    if (!this.gate.alive()) { return; }
    try { this.socket.off('message'); this.socket.off('close'); this.socket.off('error'); } catch (_error) {}
    this.gate.close();
  }
}

// Ordered, bounded writes: do not allow a slow endpoint to grow an unbounded Promise chain.
class RelayWriter {
  private chain: Promise<void> = Promise.resolve();
  private queued: number = 0;
  private send: (data: ArrayBuffer) => Promise<void>;
  private failed: () => void;
  private alive: () => boolean;
  constructor(send: (data: ArrayBuffer) => Promise<void>, failed: () => void, alive: () => boolean) {
    this.send = send; this.failed = failed; this.alive = alive;
  }

  write(data: ArrayBuffer): void {
    if (data.byteLength === 0 || !this.alive()) { return; }
    if (this.queued + data.byteLength > MAX_QUEUED_BYTES) { this.failed(); return; }
    this.queued += data.byteLength;
    this.chain = this.chain.then(async (): Promise<void> => {
      try { if (this.alive()) { await this.send(data); } }
      finally { this.queued -= data.byteLength; }
    }).catch((): void => this.failed());
  }
}

export class HttpsTunnel {
  private tls: RelayTlsEndpoint | undefined = undefined;
  private cancelDial: (() => void) | undefined = undefined;
  private closed: boolean = false;
  private phase: string = 'request';
  private createdAt: number = Date.now();
  // Zero-byte liveness. Updated at the tunnel's only two inlets, so neither
  // direction can refresh it by accident.
  private lastActivity: number = Date.now();
  private bytesOut: number = 0;
  private bytesIn: number = 0;
  private request = new ProxyHeaderReader();
  private response = new ProxyHeaderReader();
  private pending: ArrayBuffer[] = [];
  private pendingBytes: number = 0;
  private earlyRemote: ArrayBuffer[] = [];
  private earlyBytes: number = 0;
  private socks: SocksProxyHandshake | undefined = undefined;
  private httpRewriter: ProxyHttpRequestRewriter | undefined = undefined;
  private timer: number = -1;
  private toLocal: RelayWriter;
  private toRemote: RelayWriter;
  recordKey: string = '';

  private local: RelayEndpoint;
  private authenticate: (authorization: string) => HttpsProxyRecord | undefined;
  private finished: (tunnel: HttpsTunnel) => void;
  private createTls: () => RelayTlsEndpoint;
  private createTcp: () => RelayTlsEndpoint;
  private preferIpv6: () => Promise<boolean>;
  constructor(local: RelayEndpoint,
    authenticate: (authorization: string) => HttpsProxyRecord | undefined,
    finished: (tunnel: HttpsTunnel) => void,
    createTls: () => RelayTlsEndpoint = (): RelayTlsEndpoint => new TlsRelayEndpoint(),
    createTcp: () => RelayTlsEndpoint = (): RelayTlsEndpoint => new TcpRelayEndpoint(),
    preferIpv6: () => Promise<boolean> = resolvePreferIpv6) {
    this.local = local; this.authenticate = authenticate; this.finished = finished;
    this.createTls = createTls; this.createTcp = createTcp; this.preferIpv6 = preferIpv6;
    this.toLocal = new RelayWriter((data: ArrayBuffer): Promise<void> => local.send(data),
      (): void => this.close(), (): boolean => !this.closed);
    this.toRemote = new RelayWriter((data: ArrayBuffer): Promise<void> => this.tls!.send(data),
      (): void => this.close(), (): boolean => !this.closed && this.phase !== 'connecting' && this.tls !== undefined);
  }

  diagnosticPhase(): string { return this.phase; }
  diagnosticAgeMs(now: number): number { return Math.max(0, now - this.createdAt); }
  diagnosticIdleMs(now: number): number { return Math.max(0, now - this.lastActivity); }
  diagnosticCreatedAtMs(): number { return this.createdAt; }
  diagnosticBytesIn(): number { return this.bytesIn; }
  diagnosticBytesOut(): number { return this.bytesOut; }

  start(): void {
    this.timer = setTimeout((): void => this.close(), HANDSHAKE_TIMEOUT);
    this.local.onData((data: ArrayBuffer): void => {
      try { this.receiveLocal(data); } catch (_error) { this.close(); }
    });
    this.local.onEnd((): void => this.close());
  }

  private receiveLocal(data: ArrayBuffer): void {
    if (this.closed) { return; }
    this.lastActivity = Date.now(); this.bytesOut += data.byteLength;
    if (this.httpRewriter !== undefined) {
      for (const chunk of this.httpRewriter.push(data)) {
        if (this.phase === 'http-stream') { this.toRemote.write(chunk); } else { this.queue(chunk); }
      }
      return;
    }
    if (this.phase === 'tunnel') { this.toRemote.write(data); return; }
    if (this.phase !== 'request') { this.queue(data); return; }
    const header = this.request.push(data);
    if (header === undefined) { return; }
    if (header.text.startsWith('POST ')) {
      const request = parseProxyHttpPost(header.text);
      const record = this.authenticate(request.authorization);
      if (record === undefined || relayProxyType(record) !== 'proxyTypeHttp' || !record.httpOnly) {
        this.close(); return;
      }
      this.recordKey = record.key; this.phase = 'connecting';
      this.httpRewriter = new ProxyHttpRequestRewriter(request.authorization,
        record.username === '' && record.password === '' ? '' : basic(record.username, record.password));
      for (const chunk of this.httpRewriter.push(proxyAsciiBytes(header.text))) { this.queue(chunk); }
      for (const chunk of this.httpRewriter.push(header.rest)) { this.queue(chunk); }
      this.connect(record, '').catch((): void => this.close());
      return;
    }
    const request = parseProxyConnect(header.text);
    const record = this.authenticate(request.authorization);
    if (record === undefined) { this.close(); return; }
    if (record.httpOnly) { this.close(); return; }
    this.recordKey = record.key;
    this.phase = 'connecting';
    this.queue(header.rest);
    this.connect(record, request.authority).catch((): void => this.close());
  }

  private queue(data: ArrayBuffer): void {
    if (data.byteLength === 0) { return; }
    this.pendingBytes += data.byteLength;
    if (this.pendingBytes > MAX_QUEUED_BYTES) { this.close(); return; }
    this.pending.push(data);
  }

  private async connect(record: HttpsProxyRecord, authority: string): Promise<void> {
    if (this.closed) { return; }
    const type = relayProxyType(record);
    const target: ProxyTarget = type === PROXY_DIRECT ? proxyTarget(authority) : { host: record.server, port: record.port };
    const host = stripIpv6Brackets(target.host);
    const literal = host.indexOf(':') >= 0 || /^\d+\.\d+\.\d+\.\d+$/.test(host);
    const preferred = host.indexOf(':') >= 0 || (!literal && await this.preferIpv6()) ? 2 : 1;
    if (this.closed) { return; }
    const families = literal ? [preferred] : [preferred, preferred === 1 ? 2 : 1];
    const connected = await this.dial(host, target.port, families, type === PROXY_HTTPS);
    if (connected === undefined || this.closed) { this.close(); return; }
    if (this.httpRewriter !== undefined) {
      this.phase = 'http-stream';
      clearTimeout(this.timer); this.timer = -1;
      this.flushPending();
    } else if (type === PROXY_DIRECT) {
      this.tunnelReady();
    } else if (type === 'proxyTypeSocks5') {
      this.socks = new SocksProxyHandshake(authority, encodeProxyUtf8(record.username),
        encodeProxyUtf8(record.password));
      this.phase = 'socks'; this.toRemote.write(this.socks.greeting());
    } else {
      this.phase = 'response';
      this.toRemote.write(proxyAsciiBytes(proxyConnectHeader(authority,
        record.username === '' && record.password === '' ? '' : basic(record.username, record.password))));
    }
    const early = this.earlyRemote; this.earlyRemote = []; this.earlyBytes = 0;
    for (const chunk of early) { this.receiveRemote(chunk); }
  }

  // Happy Eyeballs: retain the first connected (and, for HTTPS, verified)
  // socket. The other family starts after 250ms, independently of a hung OS
  // connect promise. Buffers belong to attempts until one owns the tunnel.
  private dial(host: string, port: number, families: number[], secure: boolean): Promise<RelayTlsEndpoint | undefined> {
    return new Promise<RelayTlsEndpoint | undefined>((resolve): void => {
      const trials: RelayTlsEndpoint[] = [];
      let next = 0;
      let failed = 0;
      let done = false;
      let launchTimer = -1;
      const finish = (winner: RelayTlsEndpoint | undefined): void => {
        if (done) { return; }
        done = true;
        if (launchTimer !== -1) { clearTimeout(launchTimer); launchTimer = -1; }
        this.cancelDial = undefined;
        this.tls = winner;
        for (const trial of trials) { if (trial !== winner) { trial.close(); } }
        resolve(winner);
      };
      this.cancelDial = (): void => finish(undefined);
      const launch = (): void => {
        if (done || this.closed || next >= families.length) { return; }
        const family = families[next++];
        let trial: RelayTlsEndpoint;
        try { trial = secure ? this.createTls() : this.createTcp(); }
        catch (_error) {
          failed++;
          if (next < families.length) { launch(); }
          else if (failed === next) { finish(undefined); }
          return;
        }
        trials.push(trial);
        let ended = false;
        let buffered: ArrayBuffer[] = [];
        let bytes = 0;
        const fail = (): void => {
          if (ended) { return; }
          ended = true;
          buffered = [];
          if (done) {
            if (this.tls === trial) { this.close(); } else { trial.close(); }
            return;
          }
          failed++;
          trial.close();
          if (launchTimer !== -1) { clearTimeout(launchTimer); launchTimer = -1; }
          if (next < families.length) { launch(); }
          else if (failed === next) { finish(undefined); }
        };
        trial.onEnd(fail);
        trial.onData((data: ArrayBuffer): void => {
          if (ended || this.closed) { return; }
          if (done) {
            if (this.tls === trial) {
              try { this.receiveRemote(data); } catch (_error) { this.close(); }
            }
            return;
          }
          bytes += data.byteLength;
          if (bytes > MAX_QUEUED_BYTES) { fail(); return; }
          buffered.push(data);
        });
        const connect = async (): Promise<void> => {
          await trial.bind(family);
          if (ended || done || this.closed) { trial.close(); return; }
          // Keep the original hostname for DNS, TLS SNI and identity checks.
          await trial.connect(host, port, family, HANDSHAKE_TIMEOUT);
          if (ended || done || this.closed) { trial.close(); return; }
          if (secure) { await trial.verifyName(host); }
          if (ended || done || this.closed) { trial.close(); return; }
          this.earlyRemote = buffered; this.earlyBytes = bytes;
          buffered = [];
          finish(trial);
        };
        connect().catch(fail);
      };
      launch();
      if (!done && next < families.length) {
        launchTimer = setTimeout((): void => { launchTimer = -1; launch(); }, 250);
      }
    });
  }

  private flushPending(): void {
    for (const chunk of this.pending) { this.toRemote.write(chunk); }
    this.pending = []; this.pendingBytes = 0;
  }

  private tunnelReady(): void {
    clearTimeout(this.timer); this.timer = -1;
    this.phase = 'tunnel'; this.toLocal.write(CONNECT_OK); this.flushPending();
  }

  private receiveRemote(data: ArrayBuffer): void {
    if (this.closed) { return; }
    this.lastActivity = Date.now(); this.bytesIn += data.byteLength;
    if (this.phase === 'connecting') {
      this.earlyBytes += data.byteLength;
      if (this.earlyBytes > MAX_QUEUED_BYTES) { this.close(); return; }
      this.earlyRemote.push(data); return;
    }
    if (this.phase === 'tunnel' || this.phase === 'http-stream') { this.toLocal.write(data); return; }
    if (this.phase === 'socks' && this.socks !== undefined) {
      const step = this.socks.push(data);
      for (const write of step.writes) { this.toRemote.write(write); }
      if (step.ready) { this.tunnelReady(); this.toLocal.write(step.rest); }
      return;
    }
    if (this.phase !== 'response') { this.close(); return; }
    const header = this.response.push(data);
    if (header === undefined) { return; }
    if (!proxyConnectSucceeded(header.text)) { this.close(); return; }
    this.tunnelReady();
    this.toLocal.write(header.rest);
  }

  close(): void {
    if (this.closed) { return; }
    this.closed = true;
    this.cancelDial?.();
    if (this.timer !== -1) { clearTimeout(this.timer); this.timer = -1; }
    this.pending = [];
    this.pendingBytes = 0;
    this.earlyRemote = []; this.earlyBytes = 0;
    this.local.close();
    this.tls?.close();
    this.finished(this);
  }
}

export interface HttpsRelay {
  start(): Promise<number>;
  register(record: HttpsProxyRecord): void;
  replace(record: HttpsProxyRecord): void;
  unregister(key: string): void;
  close(): void;
  // Close tunnels created before this instant; returns how many were closed.
  dropOlderThan(createdBefore: number): number;
}

export class HttpsProxyRelay implements HttpsRelay {
  private server: socket.TCPSocketServer | undefined = undefined;
  private starting: Promise<number> | undefined = undefined;
  private closed: boolean = false;
  private credentials: Map<string, HttpsProxyRecord> = new Map();
  private tunnels: Set<HttpsTunnel> = new Set();
  private restart: () => void;
  private listenerGeneration: number = 0;
  private rejectedConnections: number = 0;
  private completedPhases: Map<string, number> = new Map();
  // Kept monotonic across tunnel closings, so the summary can report a byte
  // delta instead of a number that drops whenever a tunnel retires.
  private completedBytesIn: number = 0;
  private completedBytesOut: number = 0;
  private lastSummaryBytes: number = 0;
  private lastSummaryAt: number = 0;
  private lastCapacityCheckLog: number = 0;
  private sweepTimer: number = -1;
  private localClients: Set<LocalRelayEndpoint> = new Set();
  private checkingServer: socket.TCPSocketServer | undefined = undefined;
  private checkingClients: boolean = false;
  constructor(restart: () => void = (): void => {}) { this.restart = restart; }

  register(record: HttpsProxyRecord): void {
    this.credentials.set(basic(HTTPS_PROXY_MARKER + record.key, record.token), record);
  }

  replace(record: HttpsProxyRecord): void {
    this.register(record);
    // Switch only live-route tunnels; independent latency tests keep their own credentials.
    this.tunnels.forEach((tunnel: HttpsTunnel): void => { if (tunnel.recordKey === record.key) { tunnel.close(); } });
  }

  unregister(key: string): void {
    this.credentials.forEach((record: HttpsProxyRecord, authorization: string): void => {
      if (record.key === key) { this.credentials.delete(authorization); }
    });
    this.tunnels.forEach((tunnel: HttpsTunnel): void => { if (tunnel.recordKey === key) { tunnel.close(); } });
  }

  // Force-close tunnels that predate `createdBefore`, leaving newer ones alone.
  // Closing from this side makes native TDLib read EOF at once, so it redials
  // instead of waiting out a ping timeout on a connection the proxy already
  // dropped while the process was suspended. Tunnels created after the mark are
  // the redial in progress and must not be touched.
  dropOlderThan(createdBefore: number): number {
    const victims: HttpsTunnel[] = [];
    this.tunnels.forEach((tunnel: HttpsTunnel): void => {
      if (tunnel.diagnosticCreatedAtMs() < createdBefore) { victims.push(tunnel); }
    });
    for (const tunnel of victims) { tunnel.close(); }
    return victims.length;
  }

  start(): Promise<number> {
    if (this.closed) { return Promise.reject(new Error('proxy runtime closed')); }
    if (this.starting === undefined) {
      const generation = ++this.listenerGeneration;
      this.starting = this.listen().catch((): never => {
        if (generation === this.listenerGeneration && !this.closed) {
          this.stopListener();
          this.starting = undefined;
          this.restart();
        }
        throw new Error('proxy listener unavailable');
      });
    }
    return this.starting;
  }

  private async listen(): Promise<number> {
    const server = socket.constructTCPSocketServerInstance();
    this.server = server;
    server.on('connect', (local: socket.TCPSocketConnection): void => {
      const endpoint = new LocalRelayEndpoint(local);
      if (this.closed || this.server !== server || this.tunnels.size >= MAX_CONNECTIONS) {
        endpoint.close();
        if (this.server === server && !this.closed) { this.checkClients(); }
        this.rejectedConnections++;
        if ((this.rejectedConnections & (this.rejectedConnections - 1)) === 0) {
          logW(`[proxy-lifecycle] rejected=${this.rejectedConnections} active=${this.tunnels.size} nativePending=${localRelayEndpoints.size} ${this.capacitySummary()}`);
        }
        return;
      }
      const tunnel = new HttpsTunnel(endpoint,
        (authorization: string): HttpsProxyRecord | undefined => this.credentials.get(authorization),
        (done: HttpsTunnel): void => {
          if (this.tunnels.delete(done)) {
            const phase = done.diagnosticPhase();
            this.completedPhases.set(phase, (this.completedPhases.get(phase) ?? 0) + 1);
            this.completedBytesIn += done.diagnosticBytesIn();
            this.completedBytesOut += done.diagnosticBytesOut();
          }
          this.localClients.delete(endpoint);
        });
      this.localClients.add(endpoint);
      this.tunnels.add(tunnel);
      try { tunnel.start(); } catch (_error) { tunnel.close(); }
    });
    server.on('error', (): void => { this.checkServer(server); });
    try {
      await server.listen({ address: '127.0.0.1', family: 1, port: 0 });
      const address = await server.getLocalAddress();
      if (this.closed || this.server !== server || address.address !== '127.0.0.1' || !address.port) {
        throw new Error('invalid proxy listener');
      }
      this.startSweep();
      return address.port;
    } catch (_error) {
      // stopListener owns the current server; stale listen completions must
      // not close a newly created listener or issue duplicate native closes.
      if (this.server === server) { this.stopListener(); }
      throw new Error('proxy listener unavailable');
    }
  }

  // Aggregate phases/ages/bytes only: never include target addresses,
  // credentials, request contents or account identifiers in diagnostics.
  private capacitySummary(): string {
    const now = Date.now();
    const phases: Map<string, number> = new Map();
    let oldest = 0;
    let liveIn = 0;
    let liveOut = 0;
    let idle = 0;
    this.tunnels.forEach((tunnel: HttpsTunnel): void => {
      const phase = tunnel.diagnosticPhase();
      phases.set(phase, (phases.get(phase) ?? 0) + 1);
      oldest = Math.max(oldest, tunnel.diagnosticAgeMs(now));
      liveIn += tunnel.diagnosticBytesIn();
      liveOut += tunnel.diagnosticBytesOut();
      if (tunnel.diagnosticIdleMs(now) >= IDLE_DIAGNOSTIC_MS) { idle++; }
    });
    let active = '';
    let completed = '';
    phases.forEach((count: number, phase: string): void => { active += `${phase}:${count},`; });
    this.completedPhases.forEach((count: number, phase: string): void => { completed += `${phase}:${count},`; });
    // moved= is the number that separates a working tunnel from a zombie: bytes
    // carried since the previous summary, over however long that was. Totals are
    // monotonic (retired tunnels roll into completedBytes*) so the delta cannot
    // go negative when a tunnel closes.
    const total = this.completedBytesIn + this.completedBytesOut + liveIn + liveOut;
    const moved = this.lastSummaryAt === 0 ? 0 : Math.max(0, total - this.lastSummaryBytes);
    const elapsed = this.lastSummaryAt === 0 ? 0 : Math.max(0, now - this.lastSummaryAt);
    this.lastSummaryBytes = total;
    this.lastSummaryAt = now;
    return `phases=[${active}] oldestMs=${oldest} bytes=[in:${liveIn},out:${liveOut}] `
      + `moved=${moved}B/${elapsed}ms idle=[>${IDLE_DIAGNOSTIC_MS / 1000}s:${idle}] completed=[${completed}]`;
  }

  private startSweep(): void {
    if (this.sweepTimer !== -1) { return; }
    this.sweepTimer = setInterval((): void => this.sweepIdle(), IDLE_SWEEP_INTERVAL);
  }

  private stopSweep(): void {
    if (this.sweepTimer === -1) { return; }
    clearInterval(this.sweepTimer);
    this.sweepTimer = -1;
  }

  // Reclaim established tunnels that have moved no bytes in either direction.
  // Handshake phases keep their own HANDSHAKE_TIMEOUT; closing them here would
  // only race it. One interval for the whole relay rather than a per-tunnel
  // timeout: resetting a timer on every chunk is pure overhead under load.
  private sweepIdle(): void {
    if (this.closed) { return; }
    const now = Date.now();
    const victims: HttpsTunnel[] = [];
    this.tunnels.forEach((tunnel: HttpsTunnel): void => {
      const phase = tunnel.diagnosticPhase();
      if (phase !== 'tunnel' && phase !== 'http-stream') { return; }
      if (tunnel.diagnosticIdleMs(now) < IDLE_TIMEOUT) { return; }
      victims.push(tunnel);
    });
    if (victims.length === 0) { return; }
    let bytes = 0;
    for (const tunnel of victims) {
      bytes += tunnel.diagnosticBytesIn() + tunnel.diagnosticBytesOut();
    }
    for (const tunnel of victims) { tunnel.close(); }
    logW(`[proxy-idle] closed=${victims.length} idleMs>=${IDLE_TIMEOUT} theirBytes=${bytes}B `
      + `remaining=${this.tunnels.size} ${this.capacitySummary()}`);
  }

  private async checkClients(): Promise<void> {
    if (this.checkingClients) { return; }
    this.checkingClients = true;
    const before = this.tunnels.size;
    try {
      const checks: Promise<void>[] = [];
      this.localClients.forEach((client: LocalRelayEndpoint): void => { checks.push(client.checkAlive()); });
      await Promise.all(checks);
      const now = Date.now();
      if (before >= MAX_CONNECTIONS && now - this.lastCapacityCheckLog >= 5000) {
        this.lastCapacityCheckLog = now;
        logW(`[proxy-capacity] checked=${before} remaining=${this.tunnels.size} ${this.capacitySummary()}`);
      }
    } finally { this.checkingClients = false; }
  }

  private async checkServer(server: socket.TCPSocketServer): Promise<void> {
    if (this.closed || this.server !== server || this.checkingServer === server) { return; }
    this.checkingServer = server;
    try {
      const state = await server.getState();
      if (this.closed || this.server !== server) { return; }
      if (state.isBound && !state.isClose) {
        // NetStack reports accepted-client receive failures on this listener.
        // Retire only dead clients; keep healthy business tunnels and port.
        await this.checkClients();
        return;
      }
    } catch (_error) { /* A genuinely unavailable listener needs recovery. */ }
    finally { if (this.checkingServer === server) { this.checkingServer = undefined; } }
    if (this.closed || this.server !== server) { return; }
    this.listenerGeneration++;
    this.stopListener();
    this.starting = undefined;
    this.restart();
  }

  private stopListener(): void {
    this.stopSweep();
    this.tunnels.forEach((tunnel: HttpsTunnel): void => tunnel.close());
    this.tunnels.clear();
    this.localClients.clear();
    if (this.server !== undefined) {
      const server = this.server;
      this.server = undefined;
      // Keep connect registered: native accepts already queued before close
      // still need to pass through LocalRelayEndpoint and be safely retired.
      try { server.close().catch((): void => {}); } catch (_error) {}
    }
  }

  close(): void {
    this.closed = true;
    this.listenerGeneration++;
    this.credentials.clear();
    this.stopListener();
  }
}
