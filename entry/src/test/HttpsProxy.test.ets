import { proxyDnsNameMatches, proxyIpBytes, proxyGeneralNameDer } from '../main/ets/util/proxyCertificateName';
import { describe, expect, it } from '@ohos/hypium';
import { TdObject, TdRequest } from '../main/ets/tdkit/TdTypes';
import {
  ProxyHeaderReader, parseProxyConnect, proxyConnectSucceeded, proxyConnectHeader,
  validHttpsProxy, HttpsProxyRecord, PROXY_HTTPS, HTTPS_PROXY_MARKER, ACTIVE_ROUTE_KEY, PROXY_DIRECT
} from '../main/ets/util/httpsProxyProtocol';
import { HttpsProxyRuntime, HttpsRegistry, ProxyRequestClient } from '../main/ets/services/HttpsProxyTransport';
import { HttpsRelay } from '../main/ets/services/HttpsProxyRelay';

function bytes(text: string): ArrayBuffer {
  const data = new Uint8Array(text.length);
  for (let i = 0; i < text.length; i++) { data[i] = text.charCodeAt(i); }
  return data.buffer as ArrayBuffer;
}

function record(): HttpsProxyRecord {
  return { key: 'key', token: 'local-token', server: 'proxy.example', port: 443,
    username: 'remote-user', password: 'remote-secret' };
}

function httpsRequest(kind: string = 'addProxy'): TdRequest {
  const type: TdObject = { '@type': PROXY_HTTPS };
  type['username'] = 'remote-user'; type['password'] = 'remote-secret';
  const proxy: TdObject = { '@type': 'proxy' };
  proxy['server'] = 'proxy.example'; proxy['port'] = 443; proxy['type'] = type;
  const request: TdRequest = { '@type': kind };
  request['proxy'] = proxy; request['enable'] = true;
  return request;
}

function saved(r: HttpsProxyRecord, enabled: boolean = true): TdObject {
  const type: TdObject = { '@type': 'proxyTypeHttp' };
  type['username'] = HTTPS_PROXY_MARKER + r.key; type['password'] = r.token;
  type['http_only'] = false;
  const proxy: TdObject = { '@type': 'proxy' };
  proxy['server'] = '127.0.0.1'; proxy['port'] = 12345; proxy['type'] = type;
  const row: TdObject = { '@type': 'addedProxy' };
  row['proxy'] = proxy; row['id'] = 9; row['is_enabled'] = enabled;
  return row;
}

class TestRegistry implements HttpsRegistry {
  rows: HttpsProxyRecord[] = [];
  fail: boolean = false;
  read(): HttpsProxyRecord[] { return this.rows.slice(); }
  write(rows: HttpsProxyRecord[]): void {
    if (this.fail) { throw new Error('disk failure'); }
    this.rows = rows.slice();
  }
}

class TestRelay implements HttpsRelay {
  active: Map<string, HttpsProxyRecord> = new Map();
  closed: boolean = false;
  fail: boolean = false;
  delay: Promise<number> | undefined = undefined;
  start(): Promise<number> {
    if (this.fail) { return Promise.reject(new Error('bind failure')); }
    return this.delay ?? Promise.resolve(54321);
  }
  register(r: HttpsProxyRecord): void { this.active.set(r.key, r); }
  replace(r: HttpsProxyRecord): void { this.register(r); }
  unregister(key: string): void { this.active.delete(key); }
  close(): void { this.closed = true; this.active.clear(); }
}

class TestProxyClient implements ProxyRequestClient {
  rows: TdObject[] = [];
  sent: TdRequest[] = [];
  failKind: string = '';
  nextId: number = 100;
  async send(request: TdRequest): Promise<TdObject> {
    this.sent.push(request);
    const kind = request['@type'];
    if (kind === this.failKind) { throw new Error('request timeout'); }
    if (kind === 'getProxies') {
      const list: TdObject = { '@type': 'addedProxies' }; list['proxies'] = this.rows.slice(); return list;
    }
    if (kind === 'addProxy' || kind === 'editProxy') {
      const row: TdObject = { '@type': 'addedProxy' };
      row['id'] = kind === 'addProxy' ? this.nextId++ : request['proxy_id'];
      row['proxy'] = request['proxy']; row['is_enabled'] = request['enable'] === true;
      this.rows = this.rows.filter((r: TdObject): boolean => r['id'] !== row['id']);
      if (row['is_enabled'] === true) { this.rows.forEach((r: TdObject): void => { r['is_enabled'] = false; }); }
      this.rows.push(row); return row;
    }
    if (kind === 'removeProxy') { this.rows = this.rows.filter((r: TdObject): boolean => r['id'] !== request['proxy_id']); }
    if (kind === 'enableProxy' || kind === 'disableProxy') {
      this.rows.forEach((r: TdObject): void => { r['is_enabled'] = kind === 'enableProxy' && r['id'] === request['proxy_id']; });
    }
    return { '@type': 'ok' };
  }
}

function runtime(client: TestProxyClient, store: TestRegistry, relay: TestRelay): HttpsProxyRuntime {
  let seq = 0;
  return new HttpsProxyRuntime(client, store, relay, (): string => `random-${++seq}`);
}

export default function httpsProxyTest() {
  describe('HttpsProxy', () => {
    it('certificate DNS identity allows exact case-insensitive and single-label wildcard names', 0, () => {
      expect(proxyDnsNameMatches('Proxy.Example.com', 'proxy.example.com')).assertTrue();
      expect(proxyDnsNameMatches('proxy.example.com', '*.example.com')).assertTrue();
      expect(proxyDnsNameMatches('example.com', '*.example.com')).assertFalse();
      expect(proxyDnsNameMatches('a.b.example.com', '*.example.com')).assertFalse();
      expect(proxyDnsNameMatches('proxy.example.com', '*.evil.com')).assertFalse();
      expect(proxyDnsNameMatches('example.com', '*.com')).assertFalse();
      expect(proxyDnsNameMatches('proxy.example.com', 'proxy.example.com\x00.evil.com')).assertFalse();
    });
    it('certificate IP identity normalizes compressed IPv6 and embedded IPv4', 0, () => {
      expect(Array.from(proxyIpBytes('2001:db8::1')!).join(',')).assertEqual(
        Array.from(proxyIpBytes('2001:0db8:0:0:0:0:0:1')!).join(','));
      expect(Array.from(proxyIpBytes('::ffff:192.0.2.1')!).join(',')).assertEqual(
        Array.from(proxyIpBytes('::ffff:c000:201')!).join(','));
      expect(proxyIpBytes('256.0.0.1') === undefined).assertTrue();
      expect(proxyIpBytes('01.2.3.4') === undefined).assertTrue();
      expect(proxyIpBytes('1::2::3') === undefined).assertTrue();
      expect(proxyIpBytes('fe80::1%wlan0') === undefined).assertTrue();
    });
    it('certificate GeneralName DER preserves type and long lengths', 0, () => {
      expect(Array.from(proxyGeneralNameDer(0x87, new Uint8Array([127, 0, 0, 1]))).join(','))
        .assertEqual('135,4,127,0,0,1');
      const longName = proxyGeneralNameDer(0x82, new Uint8Array(130));
      expect(longName[0]).assertEqual(130); expect(longName[1]).assertEqual(129);
      expect(longName[2]).assertEqual(130); expect(longName.length).assertEqual(133);
    });
    it('direct remains usable when HTTPS restoration fails', 0, async () => {
      const c = new TestProxyClient(); c.rows = [saved(record())];
      const rt = runtime(c, new TestRegistry(), new TestRelay());
      await rt.send({ '@type': 'disableProxy' } as TdRequest);
      expect(c.sent[c.sent.length - 1]['@type']).assertEqual('disableProxy');
      expect(c.rows[0]['is_enabled']).assertFalse();
    });
    it('CONNECT header handles every possible split without losing tunnel bytes', 0, () => {
      const text = 'CONNECT 149.154.167.50:443 HTTP/1.1\r\nProxy-Authorization: Basic token\r\n\r\n';
      for (let at = 1; at < text.length; at++) {
        const reader = new ProxyHeaderReader();
        expect(reader.push(bytes(text.slice(0, at))) === undefined).assertTrue();
        const result = reader.push(bytes(text.slice(at) + '\x00\xff'))!;
        expect(result.text).assertEqual(text);
        expect(new Uint8Array(result.rest)[0]).assertEqual(0);
        expect(new Uint8Array(result.rest)[1]).assertEqual(255);
      }
    });
    it('oversized unterminated headers are rejected', 0, () => {
      let rejected = false;
      try { new ProxyHeaderReader().push(bytes('X'.repeat(16385))); } catch (_e) { rejected = true; }
      expect(rejected).assertTrue();
    });
    it('CONNECT accepts IPv6 and case-insensitive auth header', 0, () => {
      const result = parseProxyConnect('CONNECT [2001:db8::1]:443 HTTP/1.1\r\nproxy-authorization: Basic abc\r\n\r\n');
      expect(result.authority).assertEqual('[2001:db8::1]:443');
      expect(result.authorization).assertEqual('Basic abc');
    });
    it('request smuggling, invalid ports and duplicate auth are rejected', 0, () => {
      const invalid = ['GET / HTTP/1.1\r\n\r\n', 'CONNECT host:0 HTTP/1.1\r\n\r\n',
        'CONNECT host:65536 HTTP/1.1\r\n\r\n',
        'CONNECT host:443 HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n',
        'CONNECT host:443 HTTP/1.1\r\nProxy-Authorization: a\r\nProxy-Authorization: b\r\n\r\n'];
      for (const value of invalid) {
        let rejected = false; try { parseProxyConnect(value); } catch (_e) { rejected = true; }
        expect(rejected).assertTrue();
      }
    });
    it('only successful HTTP responses open the tunnel', 0, () => {
      expect(proxyConnectSucceeded('HTTP/1.1 200 Connection established\r\n\r\n')).assertTrue();
      expect(proxyConnectSucceeded('HTTP/1.0 204\r\n\r\n')).assertTrue();
      expect(proxyConnectSucceeded('HTTP/1.1 407 Authentication required\r\n\r\n')).assertFalse();
      expect(proxyConnectSucceeded('HTTP/1.1 302 Found\r\n\r\n')).assertFalse();
      expect(proxyConnectSucceeded('HTTP/1.1 2000 bad\r\n\r\n')).assertFalse();
    });
    it('upstream CONNECT is rebuilt without forwarding local authorization', 0, () => {
      expect(proxyConnectHeader('host:443', 'Basic remote')).assertEqual(
        'CONNECT host:443 HTTP/1.1\r\nHost: host:443\r\nProxy-Authorization: Basic remote\r\n\r\n');
      expect(proxyConnectHeader('host:443', '').indexOf('Authorization')).assertEqual(-1);
    });
    it('HTTPS config rejects schemes, header injection and colon in Basic username', 0, () => {
      const r = record(); expect(validHttpsProxy(r)).assertTrue();
      r.server = 'https://proxy.example'; expect(validHttpsProxy(r)).assertFalse();
      r.server = 'host\r\nInjected: yes'; expect(validHttpsProxy(r)).assertFalse();
      r.server = 'proxy.example'; r.username = 'a:b'; expect(validHttpsProxy(r)).assertFalse();
    });
    it('save persists remote credentials but sends only random local credentials to TDLib', 0, async () => {
      const c = new TestProxyClient(); const s = new TestRegistry(); const relay = new TestRelay();
      const result = await runtime(c, s, relay).send(httpsRequest());
      expect(s.rows.find((r: HttpsProxyRecord): boolean => r.key !== ACTIVE_ROUTE_KEY)!.password).assertEqual('remote-secret');
      const native = c.sent.find((r: TdRequest): boolean => r['@type'] === 'addProxy')!;
      expect(JSON.stringify(native).indexOf('remote-secret')).assertEqual(-1);
      expect(JSON.stringify(native).indexOf('remote-user')).assertEqual(-1);
      const proxy = result['proxy'] as TdObject;
      expect(proxy['server']).assertEqual('proxy.example');
      expect((proxy['type'] as TdObject)['@type']).assertEqual(PROXY_HTTPS);
    });
    it('cold restore replaces stale port and preserves enabled native id', 0, async () => {
      const c = new TestProxyClient(); const s = new TestRegistry(); const relay = new TestRelay();
      s.rows = [record()]; c.rows = [saved(s.rows[0])];
      await runtime(c, s, relay).prepare();
      const edit = c.sent.find((r: TdRequest): boolean => r['@type'] === 'editProxy')!;
      expect(edit['proxy_id']).assertEqual(9); expect(edit['enable']).assertTrue();
      expect((edit['proxy'] as TdObject)['port']).assertEqual(54321);
    });
    it('cold restore rotates only the local token before reconnecting', 0, async () => {
      const c = new TestProxyClient(); const s = new TestRegistry();
      s.rows = [record()]; c.rows = [saved(s.rows[0])];
      await runtime(c, s, new TestRelay()).prepare();
      const nativeType = (c.rows[0]['proxy'] as TdObject)['type'] as TdObject;
      expect(nativeType['password'] === 'local-token').assertFalse();
      expect(nativeType['password']).assertEqual(s.rows[0].token);
      expect(s.rows[0].password).assertEqual('remote-secret');
    });
    it('cold restore does not enable a disabled HTTPS entry', 0, async () => {
      const c = new TestProxyClient(); const s = new TestRegistry();
      s.rows = [record()]; c.rows = [saved(s.rows[0], false)];
      await runtime(c, s, new TestRelay()).prepare();
      expect(c.rows[0]['is_enabled']).assertFalse();
    });
    it('missing metadata fails closed without changing native selection', 0, async () => {
      const c = new TestProxyClient(); c.rows = [saved(record())];
      let failed = false;
      try { await runtime(c, new TestRegistry(), new TestRelay()).prepare(); } catch (_e) { failed = true; }
      expect(failed).assertTrue(); expect(c.sent.length).assertEqual(1);
    });
    it('disk failure prevents saving a broken loopback entry', 0, async () => {
      const c = new TestProxyClient(); const s = new TestRegistry(); s.fail = true;
      let failed = false;
      try { await runtime(c, s, new TestRelay()).send(httpsRequest()); } catch (_e) { failed = true; }
      expect(failed).assertTrue();
      expect(c.sent.some((r: TdRequest): boolean => r['@type'] === 'addProxy')).assertFalse();
    });
    it('listener failure prevents enabling a proxy', 0, async () => {
      const c = new TestProxyClient(); const relay = new TestRelay(); relay.fail = true;
      let failed = false;
      try { await runtime(c, new TestRegistry(), relay).send(httpsRequest()); } catch (_e) { failed = true; }
      expect(failed).assertTrue(); expect(c.rows.length).assertEqual(0);
    });
    it('uncertain native add retains persisted configuration for restart recovery', 0, async () => {
      const c = new TestProxyClient(); const s = new TestRegistry();
      const rt = runtime(c, s, new TestRelay()); await rt.prepare(); c.failKind = 'addProxy';
      try { await rt.send(httpsRequest()); } catch (_e) {}
      expect(s.rows.length).assertEqual(2);
      expect(s.rows[1].password).assertEqual('remote-secret');
    });
    it('test does not persist or enable and releases temporary authentication', 0, async () => {
      const c = new TestProxyClient(); const s = new TestRegistry(); const relay = new TestRelay();
      const rt = runtime(c, s, relay);
      await rt.send(httpsRequest('testProxy'));
      expect(s.rows.length).assertEqual(0); expect(c.rows.length).assertEqual(0);
      expect(relay.active.size).assertEqual(0);
      expect(c.sent.some((r: TdRequest): boolean => r['@type'] === 'addProxy' || r['@type'] === 'editProxy' || r['@type'] === 'enableProxy')).assertFalse();
    });
    it('failed test also releases temporary authentication', 0, async () => {
      const c = new TestProxyClient(); c.failKind = 'testProxy'; const relay = new TestRelay();
      try { await runtime(c, new TestRegistry(), relay).send(httpsRequest('testProxy')); } catch (_e) {}
      expect(relay.active.size).assertEqual(0);
    });
    it('delete removes durable credentials and closes the corresponding relay tunnels', 0, async () => {
      const c = new TestProxyClient(); const s = new TestRegistry(); const relay = new TestRelay();
      const rt = runtime(c, s, relay); const added = await rt.send(httpsRequest());
      const remove: TdRequest = { '@type': 'removeProxy' }; remove['proxy_id'] = added['id'];
      await rt.send(remove);
      expect(s.rows.length).assertEqual(1); expect(relay.active.size).assertEqual(1);
      expect(relay.active.get(ACTIVE_ROUTE_KEY)!.type).assertEqual(PROXY_DIRECT);
    });
    it('HTTPS sharing never exposes localhost token or creates a misleading Telegram link', 0, async () => {
      const c = new TestProxyClient(); const rt = runtime(c, new TestRegistry(), new TestRelay());
      const added = await rt.send(httpsRequest()); const request: TdRequest = { '@type': 'getProxyLink' }; request['proxy_id'] = added['id'];
      let failed = false; try { await rt.send(request); } catch (_e) { failed = true; }
      expect(failed).assertTrue();
      expect(c.sent.some((r: TdRequest): boolean => r['@type'] === 'getProxyLink')).assertFalse();
    });
    it('closing runtime rejects queued work and closes its relay', 0, async () => {
      const c = new TestProxyClient(); const relay = new TestRelay(); const rt = runtime(c, new TestRegistry(), relay);
      rt.close(); let failed = false;
      try { await rt.send(httpsRequest()); } catch (_e) { failed = true; }
      expect(failed).assertTrue(); expect(relay.closed).assertTrue(); expect(c.sent.length).assertEqual(0);
    });
    it('account switch during listener startup never writes a stale native proxy', 0, async () => {
      const c = new TestProxyClient(); const relay = new TestRelay();
      let release: (port: number) => void = (_port: number): void => {};
      relay.delay = new Promise<number>((resolve): void => { release = resolve; });
      const rt = runtime(c, new TestRegistry(), relay);
      const operation = rt.send(httpsRequest()).catch((): TdObject => ({ '@type': 'error' }));
      for (let i = 0; i < 8; i++) { await Promise.resolve(); }
      rt.close(); release(54321); await operation;
      expect(c.sent.some((r: TdRequest): boolean => r['@type'] === 'addProxy')).assertFalse();
    });
    it('native MTProto selection and direct fallback retain the public identity', 0, async () => {
      const c = new TestProxyClient();
      const proxy: TdObject = { '@type': 'proxy' }; proxy['server'] = 'native.example'; proxy['port'] = 443;
      const nativeType: TdObject = { '@type': 'proxyTypeMtproto' }; proxy['type'] = nativeType;
      const row: TdObject = { '@type': 'addedProxy' }; row['id'] = 77; row['proxy'] = proxy; row['is_enabled'] = false;
      c.rows = [row];
      const rt = runtime(c, new TestRegistry(), new TestRelay());
      const enable: TdRequest = { '@type': 'enableProxy' }; enable['proxy_id'] = 77;
      await rt.send(enable);
      const list = await rt.send({ '@type': 'getProxies' } as TdRequest);
      expect((list['proxies'] as TdObject[])[0]['is_enabled']).assertTrue();
      await rt.send({ '@type': 'disableProxy' } as TdRequest);
      expect(c.rows.find((r: TdObject): boolean => r['id'] === 77)!['is_enabled']).assertFalse();
    });
    it('HTTP and SOCKS migration preserves IDs and hides the stable ingress', 0, async () => {
      for (const type of ['proxyTypeHttp', 'proxyTypeSocks5']) {
        const c = new TestProxyClient(); const relay = new TestRelay();
        const req = httpsRequest(); ((req['proxy'] as TdObject)['type'] as TdObject)['@type'] = type;
        const row: TdObject = { '@type': 'addedProxy' }; row['id'] = 9; row['is_enabled'] = true; row['proxy'] = req['proxy'];
        c.rows = [row]; const rt = runtime(c, new TestRegistry(), relay);
        const list = (await rt.send({ '@type': 'getProxies' } as TdRequest))['proxies'] as TdObject[];
        expect(list.length).assertEqual(1); expect(list[0]['id']).assertEqual(9); expect(list[0]['is_enabled']).assertTrue();
        expect(((list[0]['proxy'] as TdObject)['type'] as TdObject)['@type']).assertEqual(type);
        expect(relay.active.get(ACTIVE_ROUTE_KEY)!.type).assertEqual(type);
      }
    });
    it('ordinary proxy and direct switches reuse ingress without native reconfiguration', 0, async () => {
      const c = new TestProxyClient(); const relay = new TestRelay(); const rt = runtime(c, new TestRegistry(), relay);
      const added = await rt.send(httpsRequest()); const before = c.sent.length;
      await rt.send({ '@type': 'disableProxy' } as TdRequest);
      expect(relay.active.get(ACTIVE_ROUTE_KEY)!.type).assertEqual(PROXY_DIRECT);
      const enable: TdRequest = { '@type': 'enableProxy' }; enable['proxy_id'] = added['id']; await rt.send(enable);
      expect(relay.active.get(ACTIVE_ROUTE_KEY)!.type).assertEqual(PROXY_HTTPS);
      expect(c.sent.slice(before).every((r: TdRequest): boolean => r['@type'] === 'getProxies')).assertTrue();
    });
    it('HTTP-only mode changes update ingress and deletion safely returns to direct', 0, async () => {
      const c = new TestProxyClient(); const relay = new TestRelay(); const rt = runtime(c, new TestRegistry(), relay);
      const req = httpsRequest(); const type = (req['proxy'] as TdObject)['type'] as TdObject;
      type['@type'] = 'proxyTypeHttp'; type['http_only'] = true;
      const added = await rt.send(req);
      expect(relay.active.get(ACTIVE_ROUTE_KEY)!.httpOnly).assertTrue();
      c.failKind = 'editProxy';
      const remove: TdRequest = { '@type': 'removeProxy' }; remove['proxy_id'] = added['id']; await rt.send(remove);
      expect(c.rows.some((r: TdObject): boolean => r['is_enabled'] === true)).assertFalse();
      expect(c.sent[c.sent.length - 2]['@type']).assertEqual('disableProxy');
    });
    it('restart restores logical selection and direct fallback never resurrects a proxy', 0, async () => {
      const c = new TestProxyClient(); const store = new TestRegistry();
      const first = runtime(c, store, new TestRelay()); const added = await first.send(httpsRequest()); first.close();
      const relay = new TestRelay(); const second = runtime(c, store, relay); await second.prepare();
      expect(relay.active.get(ACTIVE_ROUTE_KEY)!.selectedId).assertEqual(added['id']); second.close();
      c.rows.forEach((r: TdObject): void => { r['is_enabled'] = false; });
      const direct = new TestRelay(); await runtime(c, store, direct).prepare();
      expect(direct.active.get(ACTIVE_ROUTE_KEY)!.type).assertEqual(PROXY_DIRECT);
    });
    it('SOCKS sharing exposes the original address and credentials', 0, async () => {
      const c = new TestProxyClient(); const rt = runtime(c, new TestRegistry(), new TestRelay());
      const req = httpsRequest(); ((req['proxy'] as TdObject)['type'] as TdObject)['@type'] = 'proxyTypeSocks5';
      const added = await rt.send(req); const link: TdRequest = { '@type': 'getProxyLink' }; link['proxy_id'] = added['id'];
      expect((await rt.send(link))['url']).assertEqual('tg://socks?server=proxy.example&port=443&user=remote-user&pass=remote-secret');
    });
    it('direct latency test is isolated from the selected proxy', 0, async () => {
      const c = new TestProxyClient(); const relay = new TestRelay(); const rt = runtime(c, new TestRegistry(), relay);
      await rt.send(httpsRequest()); const before = c.sent.length;
      const ping: TdRequest = { '@type': 'pingProxy' }; ping['proxy_id'] = 0; await rt.send(ping);
      expect(relay.active.get(ACTIVE_ROUTE_KEY)!.type).assertEqual(PROXY_HTTPS);
      expect(c.sent.slice(before).every((r: TdRequest): boolean => r['@type'] === 'testProxy')).assertTrue();
      expect(relay.active.size).assertEqual(2);
    });
    it('crash after native removal restores a missing logical route as direct', 0, async () => {
      const c = new TestProxyClient(); const store = new TestRegistry();
      const first = runtime(c, store, new TestRelay()); const added = await first.send(httpsRequest()); first.close();
      c.rows = c.rows.filter((r: TdObject): boolean => r['id'] !== added['id']);
      const relay = new TestRelay(); const second = runtime(c, store, relay);
      const list = await second.send({ '@type': 'getProxies' } as TdRequest);
      expect((list['proxies'] as TdObject[]).length).assertEqual(0);
      expect(relay.active.get(ACTIVE_ROUTE_KEY)!.type).assertEqual(PROXY_DIRECT);
    });
  });
}
