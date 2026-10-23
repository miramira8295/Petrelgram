import { resolvePreferIpv6 } from './NetworkIpPreference';
import { stripIpv6Brackets } from '../util/ipFamily';
import { SocksProxyHandshake, proxyTarget, ProxyTarget } from '../util/socksProxyProtocol';
import { verifyProxyCertificateName } from './HttpsProxyCertificate';
import { socket } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import {
  HttpsProxyRecord, HTTPS_PROXY_MARKER, ProxyHeaderReader, parseProxyConnect,
  proxyConnectHeader, proxyConnectSucceeded, relayProxyType, PROXY_DIRECT, PROXY_HTTPS,
  ProxyHttpRequestRewriter, parseProxyHttpPost, proxyAsciiBytes
} from '../util/httpsProxyProtocol';

const MAX_CONNECTIONS: number = 32;
const MAX_QUEUED_BYTES: number = 512 * 1024;
const HANDSHAKE_TIMEOUT: number = 15000;
const CONNECT_OK: ArrayBuffer = new Uint8Array('HTTP/1.1 200 Connection Established\r\n\r\n'
  .split('').map((c: string): number => c.charCodeAt(0))).buffer as ArrayBuffer;

function basic(user: string, password: string): string {
  return 'Basic ' + new util.Base64Helper().encodeToStringSync(
    new util.TextEncoder().encodeInto(`${user}:${password}`));
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
  constructor(local: socket.TCPSocketConnection) { this.socket = local; }
  onData(callback: (data: ArrayBuffer) => void): void {
    this.socket.on('message', (info: socket.SocketMessageInfo): void => callback(info.message));
  }
  onEnd(callback: () => void): void { this.socket.on('close', callback); this.socket.on('error', callback); }
  send(data: string | ArrayBuffer): Promise<void> { return this.socket.send({ data: data }); }
  close(): void {
    try { this.socket.off('message'); this.socket.off('close'); this.socket.off('error'); } catch (_error) {}
    try { this.socket.close().catch((): void => {}); } catch (_error) {}
  }
}

class TlsRelayEndpoint implements RelayTlsEndpoint {
  private socket: socket.TLSSocket = socket.constructTLSSocketInstance();
  bind(family: number): Promise<void> {
    return this.socket.bind({ address: family === 2 ? '::' : '0.0.0.0', family: family, port: 0 });
  }
  onData(callback: (data: ArrayBuffer) => void): void {
    this.socket.on('message', (info: socket.SocketMessageInfo): void => callback(info.message));
  }
  onEnd(callback: () => void): void { this.socket.on('close', callback); this.socket.on('error', callback); }
  connect(host: string, port: number, family: number, timeout: number): Promise<void> {
    return this.socket.connect({ address: { address: host, port: port, family: family },
      secureOptions: { protocols: [socket.Protocol.TLSv12, socket.Protocol.TLSv13] },
      ALPNProtocols: ['http/1.1'], skipRemoteValidation: false, timeout: timeout });
  }
  verifyName(host: string): Promise<void> { return verifyProxyCertificateName(this.socket, host); }
  send(data: string | ArrayBuffer): Promise<void> { return this.socket.send(data); }
  close(): void {
    try { this.socket.off('message'); this.socket.off('close'); this.socket.off('error'); } catch (_error) {}
    try { this.socket.close().catch((): void => {}); } catch (_error) {}
  }
}

class TcpRelayEndpoint implements RelayTlsEndpoint {
  private socket: socket.TCPSocket = socket.constructTCPSocketInstance();
  bind(family: number): Promise<void> {
    return this.socket.bind({ address: family === 2 ? '::' : '0.0.0.0', family: family, port: 0 });
  }
  onData(callback: (data: ArrayBuffer) => void): void {
    this.socket.on('message', (info: socket.SocketMessageInfo): void => callback(info.message));
  }
  onEnd(callback: () => void): void { this.socket.on('close', callback); this.socket.on('error', callback); }
  connect(host: string, port: number, family: number, timeout: number): Promise<void> {
    return this.socket.connect({ address: { address: host, port: port, family: family }, timeout: timeout });
  }
  async verifyName(_host: string): Promise<void> {}
  send(data: string | ArrayBuffer): Promise<void> { return this.socket.send({ data: data }); }
  close(): void {
    try { this.socket.off('message'); this.socket.off('close'); this.socket.off('error'); } catch (_error) {}
    try { this.socket.close().catch((): void => {}); } catch (_error) {}
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

  start(): void {
    this.timer = setTimeout((): void => this.close(), HANDSHAKE_TIMEOUT);
    this.local.onData((data: ArrayBuffer): void => {
      try { this.receiveLocal(data); } catch (_error) { this.close(); }
    });
    this.local.onEnd((): void => this.close());
  }

  private receiveLocal(data: ArrayBuffer): void {
    if (this.closed) { return; }
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
      this.socks = new SocksProxyHandshake(authority, new util.TextEncoder().encodeInto(record.username),
        new util.TextEncoder().encodeInto(record.password));
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
          if (done) { if (this.tls === trial) { this.close(); } return; }
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
}

export class HttpsProxyRelay implements HttpsRelay {
  private server: socket.TCPSocketServer | undefined = undefined;
  private starting: Promise<number> | undefined = undefined;
  private closed: boolean = false;
  private credentials: Map<string, HttpsProxyRecord> = new Map();
  private tunnels: Set<HttpsTunnel> = new Set();
  private restart: () => void;
  private listenerGeneration: number = 0;
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
      if (this.closed || this.tunnels.size >= MAX_CONNECTIONS) { local.close().catch((): void => {}); return; }
      const tunnel = new HttpsTunnel(new LocalRelayEndpoint(local),
        (authorization: string): HttpsProxyRecord | undefined => this.credentials.get(authorization),
        (done: HttpsTunnel): void => { this.tunnels.delete(done); });
      this.tunnels.add(tunnel);
      try { tunnel.start(); } catch (_error) { tunnel.close(); }
    });
    server.on('error', (): void => {
      if (this.closed || this.server !== server) { return; }
      this.listenerGeneration++;
      this.stopListener();
      this.starting = undefined;
      this.restart();
    });
    try {
      await server.listen({ address: '127.0.0.1', family: 1, port: 0 });
      const address = await server.getLocalAddress();
      if (this.closed || this.server !== server || address.address !== '127.0.0.1' || !address.port) {
        throw new Error('invalid proxy listener');
      }
      return address.port;
    } catch (_error) {
      server.close().catch((): void => {});
      throw new Error('proxy listener unavailable');
    }
  }

  private stopListener(): void {
    this.tunnels.forEach((tunnel: HttpsTunnel): void => tunnel.close());
    this.tunnels.clear();
    if (this.server !== undefined) {
      try { this.server.off('connect'); this.server.off('error'); } catch (_error) {}
      try { this.server.close().catch((): void => {}); } catch (_error) {}
      this.server = undefined;
    }
  }

  close(): void {
    this.closed = true;
    this.listenerGeneration++;
    this.credentials.clear();
    this.stopListener();
  }
}
