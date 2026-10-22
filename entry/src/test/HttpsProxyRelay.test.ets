import { resolvePreferIpv6 } from '../main/ets/services/NetworkIpPreference';
import { describe, expect, it } from '@ohos/hypium';
import { HttpsTunnel, RelayTlsEndpoint } from '../main/ets/services/HttpsProxyRelay';
import { SocksProxyHandshake } from '../main/ets/util/socksProxyProtocol';
import { ProxyHttpRequestRewriter, PROXY_DIRECT } from '../main/ets/util/httpsProxyProtocol';
import { HttpsProxyRecord } from '../main/ets/util/httpsProxyProtocol';

function buffer(text: string): ArrayBuffer {
  const bytes = new Uint8Array(text.length);
  for (let i = 0; i < text.length; i++) { bytes[i] = text.charCodeAt(i); }
  return bytes.buffer as ArrayBuffer;
}

function stringOf(data: ArrayBuffer): string {
  return Array.from(new Uint8Array(data)).map((v: number): string => String.fromCharCode(v)).join('');
}

// The real HttpsTunnel state machine with deterministic socket boundaries, no external network.
class RelaySocketFake implements RelayTlsEndpoint {
  sent: ArrayBuffer[] = [];
  connects: string[] = [];
  families: number[] = [];
  bindings: number[] = [];
  closed: boolean = false;
  failConnect: boolean = false;
  connectBarrier: Promise<void> | undefined = undefined;
  validCertificate: boolean = true;
  message: (data: ArrayBuffer) => void = (_data: ArrayBuffer): void => {};
  onData(callback: (data: ArrayBuffer) => void): void { this.message = callback; }
  onEnd(_callback: () => void): void {}
  async bind(family: number): Promise<void> { this.bindings.push(family); }
  async connect(host: string, _port: number, family: number, _timeout: number): Promise<void> {
    this.connects.push(host); this.families.push(family);
    if (this.failConnect) { throw new Error('connection refused'); }
    if (this.connectBarrier !== undefined) { await this.connectBarrier; }
  }
  async verifyName(_host: string): Promise<void> {
    if (!this.validCertificate) { throw new Error('hostname mismatch'); }
  }
  async send(value: string | ArrayBuffer): Promise<void> {
    this.sent.push(typeof value === 'string' ? buffer(value) : value);
  }
  close(): void { this.closed = true; this.message = (_data: ArrayBuffer): void => {}; }
  receive(data: ArrayBuffer): void { this.message(data); }
}

const target: HttpsProxyRecord = {
  key: 'test-key', token: 'test-token', server: 'proxy.example', port: 443, username: '', password: ''
};
const request: string = 'CONNECT 149.154.167.50:443 HTTP/1.1\r\nProxy-Authorization: Basic local\r\n\r\n';

async function settle(): Promise<void> { for (let i = 0; i < 30; i++) { await Promise.resolve(); } }

function tunnel(local: RelaySocketFake, remote: RelaySocketFake, validCertificate: boolean = true): HttpsTunnel {
  remote.validCertificate = validCertificate;
  return new HttpsTunnel(local,
    (auth: string): HttpsProxyRecord | undefined => auth === 'Basic local' ? target : undefined,
    (_done: HttpsTunnel): void => {}, (): RelayTlsEndpoint => remote,
    (): RelayTlsEndpoint => remote, async (): Promise<boolean> => false);
}

export default function httpsProxyRelayTest() {
  describe('HttpsProxyRelay', () => {
    it('pure IPv6 networks automatically prefer IPv6 with the manual switch off', 0, async () => {
      expect(await resolvePreferIpv6(async (): Promise<boolean> => false, (): boolean => false)).assertTrue();
    });
    it('dual stack networks retain IPv4 priority with the manual switch off', 0, async () => {
      expect(await resolvePreferIpv6(async (): Promise<boolean> => true, (): boolean => false)).assertFalse();
    });
    it('manual IPv6 preference skips optional network probing', 0, async () => {
      let probes = 0;
      expect(await resolvePreferIpv6(async (): Promise<boolean> => { probes++; return true; },
        (): boolean => true)).assertTrue();
      expect(probes).assertEqual(0);
    });
    it('network probe rejection preserves the default family order', 0, async () => {
      expect(await resolvePreferIpv6(async (): Promise<boolean> => { throw new Error('probe failed'); },
        (): boolean => false)).assertFalse();
    });
    it('stalled network probe cannot block relay connection setup', 0, async () => {
      expect(await resolvePreferIpv6((): Promise<boolean> => new Promise<boolean>(() => {}),
        (): boolean => false)).assertFalse();
    });
    it('preference changes during probing use the latest manual setting', 0, async () => {
      let forced = false;
      expect(await resolvePreferIpv6(async (): Promise<boolean> => { forced = true; return true; },
        (): boolean => forced)).assertTrue();
    });
    it('each probe reads the current network rather than a previous family preference', 0, async () => {
      let hasIpv4 = false;
      const probe = async (): Promise<boolean> => hasIpv4;
      expect(await resolvePreferIpv6(probe, (): boolean => false)).assertTrue();
      hasIpv4 = true;
      expect(await resolvePreferIpv6(probe, (): boolean => false)).assertFalse();
    });
    it('HTTP SOCKS and TLS relay domains use the effective IPv6 policy', 0, async () => {
      for (const type of ['proxyTypeHttp', 'proxyTypeSocks5', 'proxyTypeHttps']) {
        const local = new RelaySocketFake(); const remote = new RelaySocketFake();
        const route: HttpsProxyRecord = { key: 'v6', token: 't', server: 'proxy.example', port: 443,
          username: '', password: '', type: type };
        const t = new HttpsTunnel(local, (_auth: string): HttpsProxyRecord => route, (_t: HttpsTunnel): void => {},
          (): RelayTlsEndpoint => remote, (): RelayTlsEndpoint => remote,
          (): Promise<boolean> => resolvePreferIpv6(async (): Promise<boolean> => false, (): boolean => false));
        t.start(); local.receive(buffer(request)); await settle();
        expect(remote.families.join(',')).assertEqual('2'); expect(remote.bindings.join(',')).assertEqual('2');
        expect(remote.connects[0]).assertEqual('proxy.example'); t.close();
      }
    });
    it('failed IPv6 connection falls back to IPv4 on a fresh socket', 0, async () => {
      const local = new RelaySocketFake(); const first = new RelaySocketFake(); const second = new RelaySocketFake();
      first.failConnect = true; let calls = 0;
      const t = new HttpsTunnel(local, (_auth: string): HttpsProxyRecord => target, (_t: HttpsTunnel): void => {},
        (): RelayTlsEndpoint => calls++ === 0 ? first : second, (): RelayTlsEndpoint => second,
        async (): Promise<boolean> => true);
      t.start(); local.receive(buffer(request)); await settle();
      expect(first.families.join(',')).assertEqual('2'); expect(first.closed).assertTrue();
      expect(second.families.join(',')).assertEqual('1'); expect(second.sent.length).assertEqual(1); t.close();
    });
    it('failed IPv4 connection retains IPv6 fallback when IPv6 priority is off', 0, async () => {
      const local = new RelaySocketFake(); const first = new RelaySocketFake(); const second = new RelaySocketFake();
      first.failConnect = true; let calls = 0;
      const t = new HttpsTunnel(local, (_auth: string): HttpsProxyRecord => target, (_t: HttpsTunnel): void => {},
        (): RelayTlsEndpoint => calls++ === 0 ? first : second, (): RelayTlsEndpoint => second,
        async (): Promise<boolean> => false);
      t.start(); local.receive(buffer(request)); await settle();
      expect(first.families.join(',')).assertEqual('1'); expect(first.closed).assertTrue();
      expect(second.families.join(',')).assertEqual('2'); expect(second.sent.length).assertEqual(1); t.close();
    });
    it('IP literals use their own address family without consulting domain preference', 0, async () => {
      for (const host of ['[2001:db8::1]', '192.0.2.1']) {
        const local = new RelaySocketFake(); const remote = new RelaySocketFake(); let probes = 0;
        const route: HttpsProxyRecord = { key: 'literal', token: 't', server: host, port: 443,
          username: '', password: '', type: 'proxyTypeHttp' };
        const t = new HttpsTunnel(local, (_auth: string): HttpsProxyRecord => route, (_t: HttpsTunnel): void => {},
          (): RelayTlsEndpoint => remote, (): RelayTlsEndpoint => remote,
          async (): Promise<boolean> => { probes++; return true; });
        t.start(); local.receive(buffer(request)); await settle();
        expect(probes).assertEqual(0); expect(remote.families.join(',')).assertEqual(host.startsWith('[') ? '2' : '1');
        expect(remote.connects[0]).assertEqual(host.startsWith('[') ? '2001:db8::1' : host); t.close();
      }
    });
    it('closing during network probing prevents late sockets from being opened', 0, async () => {
      const local = new RelaySocketFake(); const remote = new RelaySocketFake();
      let finish: (value: boolean) => void = (_value: boolean): void => {};
      const preference = new Promise<boolean>((resolve: (value: boolean) => void): void => { finish = resolve; });
      const t = new HttpsTunnel(local, (_auth: string): HttpsProxyRecord => target, (_t: HttpsTunnel): void => {},
        (): RelayTlsEndpoint => remote, (): RelayTlsEndpoint => remote, (): Promise<boolean> => preference);
      t.start(); local.receive(buffer(request)); t.close(); finish(true); await settle();
      expect(remote.bindings.length).assertEqual(0); expect(remote.connects.length).assertEqual(0);
      expect(local.closed).assertTrue();
    });

    it('unauthenticated loopback client cannot open an upstream connection', 0, async () => {
      const local = new RelaySocketFake(); const remote = new RelaySocketFake(); const t = tunnel(local, remote);
      t.start(); local.receive(buffer('CONNECT example.com:443 HTTP/1.1\r\n\r\n')); await settle();
      expect(local.closed).assertTrue(); expect(remote.connects.length).assertEqual(0); t.close();
    });
    it('TLS hostname rejection sends neither CONNECT nor proxy credentials', 0, async () => {
      const local = new RelaySocketFake(); const remote = new RelaySocketFake(); const t = tunnel(local, remote, false);
      t.start(); local.receive(buffer(request)); await settle();
      expect(local.closed).assertTrue(); expect(remote.sent.length).assertEqual(0); t.close();
    });
    it('fragmented CONNECT and response preserve early binary payload in both directions', 0, async () => {
      const local = new RelaySocketFake(); const remote = new RelaySocketFake(); const t = tunnel(local, remote);
      t.start(); local.receive(buffer(request.slice(0, 15))); local.receive(buffer(request.slice(15) + '\x00\xff'));
      await settle();
      expect(stringOf(remote.sent[0])).assertEqual(
        'CONNECT 149.154.167.50:443 HTTP/1.1\r\nHost: 149.154.167.50:443\r\n\r\n');
      expect(remote.sent.length).assertEqual(1);
      remote.receive(buffer('HTTP/1.1 200 OK\r\n')); remote.receive(buffer('\r\n\xfe\x00'));
      await settle();
      expect(stringOf(remote.sent[1])).assertEqual('\x00\xff');
      expect(stringOf(local.sent[1])).assertEqual('\xfe\x00');
      local.receive(buffer('next')); remote.receive(buffer('reply')); await settle();
      expect(stringOf(remote.sent[2])).assertEqual('next'); expect(stringOf(local.sent[2])).assertEqual('reply');
      expect(remote.connects[0]).assertEqual('proxy.example'); t.close();
    });
    it('upstream rejection closes both sockets without returning a successful local tunnel', 0, async () => {
      const local = new RelaySocketFake(); const remote = new RelaySocketFake(); const t = tunnel(local, remote);
      t.start(); local.receive(buffer(request)); await settle();
      remote.receive(buffer('HTTP/1.1 407 Proxy Authentication Required\r\n\r\n')); await settle();
      expect(local.closed).assertTrue(); expect(remote.closed).assertTrue(); expect(local.sent.length).assertEqual(0); t.close();
    });
    it('unbounded pre-handshake buffering is rejected and releases sockets', 0, async () => {
      const local = new RelaySocketFake(); const remote = new RelaySocketFake(); const t = tunnel(local, remote);
      t.start(); local.receive(buffer(request)); local.receive(new ArrayBuffer(512 * 1024 + 1)); await settle();
      expect(local.closed).assertTrue(); expect(remote.connects.length).assertEqual(0); t.close();
    });
    it('closing during TLS setup prevents late CONNECT and clears local handlers', 0, async () => {
      const local = new RelaySocketFake(); const remote = new RelaySocketFake(); const t = tunnel(local, remote);
      let finish: () => void = (): void => {};
      remote.connectBarrier = new Promise<void>((resolve: () => void): void => { finish = resolve; });
      t.start(); local.receive(buffer(request)); await settle();
      expect(remote.connects.length).assertEqual(1);
      t.close(); finish(); await settle();
      local.receive(buffer('late'));
      expect(local.closed).assertTrue(); expect(remote.closed).assertTrue(); expect(remote.sent.length).assertEqual(0);
    });
    it('SOCKS authenticated fragmented handshake preserves the first payload', 0, () => {
      const handshake = new SocksProxyHandshake('[2001:db8::1]:443', new Uint8Array([117]), new Uint8Array([112]));
      expect(Array.from(new Uint8Array(handshake.greeting())).join(',')).assertEqual('5,1,2');
      expect(handshake.push(buffer('\x05')).writes.length).assertEqual(0);
      expect(Array.from(new Uint8Array(handshake.push(buffer('\x02')).writes[0])).join(',')).assertEqual('1,1,117,1,112');
      const connect = new Uint8Array(handshake.push(buffer('\x01\x00')).writes[0]);
      expect(connect.length).assertEqual(22); expect(connect[3]).assertEqual(4); expect(connect[21]).assertEqual(187);
      const response = '\x05\x00\x00\x01\x7f\x00\x00\x01\x00\x50';
      for (let i = 0; i < response.length - 1; i++) { expect(handshake.push(buffer(response.charAt(i))).ready).assertFalse(); }
      const ready = handshake.push(buffer(response.slice(-1) + 'payload'));
      expect(ready.ready).assertTrue(); expect(stringOf(ready.rest)).assertEqual('payload');
    });
    it('SOCKS uses remote DNS and rejects authentication downgrade and connection failures', 0, () => {
      const handshake = new SocksProxyHandshake('dc.example:443', new Uint8Array(0), new Uint8Array(0));
      const connect = new Uint8Array(handshake.push(buffer('\x05\x00')).writes[0]);
      expect(connect[3]).assertEqual(3); expect(connect[4]).assertEqual(10);
      let rejected = false;
      try { handshake.push(buffer('\x05\x05\x00\x01')); } catch (_e) { rejected = true; }
      expect(rejected).assertTrue(); rejected = false;
      try { new SocksProxyHandshake('host:443', new Uint8Array([1]), new Uint8Array([2])).push(buffer('\x05\x00')); }
      catch (_e) { rejected = true; }
      expect(rejected).assertTrue();
    });
    it('HTTP-only rewrites every keepalive header while preserving fragmented binary bodies', 0, () => {
      const header = 'POST HTTP://149.154.167.50:80/api HTTP/1.1\r\nProxy-Authorization: Basic local\r\nContent-Length: 3\r\n\r\n';
      const stream = header + '\x00\xffa' + header + 'xyz';
      for (let at = 1; at < stream.length; at++) {
        const rewrite = new ProxyHttpRequestRewriter('Basic local', 'Basic upstream');
        const output = [...rewrite.push(buffer(stream.slice(0, at))), ...rewrite.push(buffer(stream.slice(at)))];
        const text = output.map((b: ArrayBuffer): string => stringOf(b)).join('');
        expect(text.indexOf('Basic local')).assertEqual(-1);
        expect(text.split('Basic upstream').length).assertEqual(3);
        expect(text.indexOf('\x00\xffaPOST') >= 0).assertTrue();
        expect(text.endsWith('xyz')).assertTrue();
      }
    });
    it('HTTP-only reauthenticates subsequent requests and rejects ambiguous framing', 0, () => {
      const prefix = 'POST HTTP://host:80/api HTTP/1.1\r\nProxy-Authorization: Basic local\r\n';
      for (const bad of ['Content-Length: 0\r\nContent-Length: 1', 'Transfer-Encoding: chunked', 'Content-Length: -1']) {
        let rejected = false;
        try { new ProxyHttpRequestRewriter('Basic local', '').push(buffer(prefix + bad + '\r\n\r\n')); }
        catch (_e) { rejected = true; }
        expect(rejected).assertTrue();
      }
      const rewrite = new ProxyHttpRequestRewriter('Basic local', '');
      rewrite.push(buffer(prefix + 'Content-Length: 0\r\n\r\n'));
      let rejected = false;
      try { rewrite.push(buffer(prefix.replace('Basic local', 'Basic wrong') + 'Content-Length: 0\r\n\r\n')); }
      catch (_e) { rejected = true; }
      expect(rejected).assertTrue();
    });
    it('direct relay connects to the requested destination without an upstream proxy handshake', 0, async () => {
      const local = new RelaySocketFake(); const remote = new RelaySocketFake();
      const route: HttpsProxyRecord = { key: 'direct', token: 't', server: '', port: 0, username: '', password: '', type: PROXY_DIRECT };
      const t = new HttpsTunnel(local, (_auth: string): HttpsProxyRecord => route, (_t: HttpsTunnel): void => {},
        (): RelayTlsEndpoint => { throw new Error('unexpected TLS'); }, (): RelayTlsEndpoint => remote, async (): Promise<boolean> => false);
      t.start(); local.receive(buffer(request + 'payload')); await settle();
      expect(remote.connects[0]).assertEqual('149.154.167.50');
      expect(stringOf(remote.sent[0])).assertEqual('payload');
      expect(stringOf(local.sent[0]).startsWith('HTTP/1.1 200')).assertTrue(); t.close();
    });
    it('plain HTTP relay uses TCP CONNECT and preserves buffered payload', 0, async () => {
      const local = new RelaySocketFake(); const remote = new RelaySocketFake();
      const route: HttpsProxyRecord = { key: 'http', token: 't', server: 'http.example', port: 8080, username: '', password: '', type: 'proxyTypeHttp' };
      const t = new HttpsTunnel(local, (_auth: string): HttpsProxyRecord => route, (_t: HttpsTunnel): void => {},
        (): RelayTlsEndpoint => { throw new Error('unexpected TLS'); }, (): RelayTlsEndpoint => remote, async (): Promise<boolean> => false);
      t.start(); local.receive(buffer(request + 'payload')); await settle();
      expect(stringOf(remote.sent[0]).startsWith('CONNECT ')).assertTrue(); expect(local.sent.length).assertEqual(0);
      remote.receive(buffer('HTTP/1.1 200 OK\r\n\r\nreply')); await settle();
      expect(stringOf(remote.sent[1])).assertEqual('payload'); expect(stringOf(local.sent[1])).assertEqual('reply'); t.close();
    });
    it('SOCKS relay waits for CONNECT success before flushing client payload', 0, async () => {
      const local = new RelaySocketFake(); const remote = new RelaySocketFake();
      const route: HttpsProxyRecord = { key: 'socks', token: 't', server: 'socks.example', port: 1080, username: '', password: '', type: 'proxyTypeSocks5' };
      const t = new HttpsTunnel(local, (_auth: string): HttpsProxyRecord => route, (_t: HttpsTunnel): void => {},
        (): RelayTlsEndpoint => { throw new Error('unexpected TLS'); }, (): RelayTlsEndpoint => remote, async (): Promise<boolean> => false);
      t.start(); local.receive(buffer(request + 'payload')); await settle();
      expect(Array.from(new Uint8Array(remote.sent[0])).join(',')).assertEqual('5,1,0');
      remote.receive(buffer('\x05\x00')); await settle(); expect(local.sent.length).assertEqual(0);
      remote.receive(buffer('\x05\x00\x00\x01\x7f\x00\x00\x01\x00\x50reply')); await settle();
      expect(stringOf(remote.sent[2])).assertEqual('payload'); expect(stringOf(local.sent[1])).assertEqual('reply'); t.close();
    });
    it('HTTP-only tunnel forwards raw POST responses without synthetic CONNECT success', 0, async () => {
      const local = new RelaySocketFake(); const remote = new RelaySocketFake();
      const route: HttpsProxyRecord = { key: 'http', token: 't', server: 'http.example', port: 8080,
        username: '', password: '', type: 'proxyTypeHttp', httpOnly: true };
      const t = new HttpsTunnel(local, (_auth: string): HttpsProxyRecord => route, (_t: HttpsTunnel): void => {},
        (): RelayTlsEndpoint => { throw new Error('unexpected TLS'); }, (): RelayTlsEndpoint => remote, async (): Promise<boolean> => false);
      const post = 'POST HTTP://149.154.167.50:80/api HTTP/1.1\r\nProxy-Authorization: Basic local\r\nContent-Length: 3\r\n\r\n';
      t.start(); local.receive(buffer(post + 'a')); local.receive(buffer('bc')); await settle();
      expect(local.sent.length).assertEqual(0);
      const sent = remote.sent.map((b: ArrayBuffer): string => stringOf(b)).join('');
      expect(sent.indexOf('Authorization')).assertEqual(-1); expect(sent.endsWith('abc')).assertTrue();
      const reply = 'HTTP/1.1 200 OK\r\nContent-Length: 1\r\n\r\nx';
      remote.receive(buffer(reply)); await settle();
      expect(stringOf(local.sent[0])).assertEqual(reply); t.close();
    });
  });
}
