import { fileIo } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { TdClient } from '../tdkit/TdClient';
import { TdObject, TdRequest } from '../tdkit/TdTypes';
import {
  HttpsProxyRecord, HttpsProxyConfig, PROXY_HTTPS, HTTPS_PROXY_MARKER, validRelayProxy,
  PROXY_DIRECT, ACTIVE_ROUTE_KEY, relayProxyType, usesProxyRelay
} from '../util/httpsProxyProtocol';
import { HttpsProxyRelay, HttpsRelay } from './HttpsProxyRelay';
import { ProxyProbeCancellation } from '../util/ProxyProbeCancellation';

export interface HttpsRegistry {
  read(): HttpsProxyRecord[];
  write(records: HttpsProxyRecord[]): void;
}

// Per-account sandbox file. Upstream passwords NEVER go in the local HTTP handshake.
// Persist before asking TDLib to save its loopback entry; atomic replacement survives crashes.
class FileHttpsRegistry implements HttpsRegistry {
  private path: string;
  constructor(path: string) { this.path = path; }
  read(): HttpsProxyRecord[] {
    if (!fileIo.accessSync(this.path)) { return []; }
    const rows = JSON.parse(fileIo.readTextSync(this.path)) as HttpsProxyRecord[];
    if (!Array.isArray(rows) || rows.some((r: HttpsProxyRecord): boolean =>
      !validRelayProxy(r) || (r.selectedId !== undefined && (!Number.isInteger(r.selectedId) || r.selectedId < 0)) || !/^[a-f0-9-]{36}$/.test(r.key) || !/^[a-f0-9-]{36}$/.test(r.token))) {
      throw new Error('proxy registry invalid');
    }
    return rows;
  }
  write(records: HttpsProxyRecord[]): void {
    const temp = this.path + '.tmp';
    const file = fileIo.openSync(temp, fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
    try {
      fileIo.writeSync(file.fd, JSON.stringify(records));
      fileIo.fsyncSync(file.fd);
    } finally { fileIo.closeSync(file); }
    fileIo.renameSync(temp, this.path);
  }
}

export interface ProxyRequestClient {
  send(request: TdRequest, timeoutMs?: number): Promise<TdObject>;
}

function copy(source: TdObject): TdObject {
  const result: TdObject = {};
  for (const key of Object.keys(source)) { result[key] = source[key]; }
  return result;
}

function localKey(proxy: TdObject): string {
  const type = proxy['type'] as TdObject | undefined;
  const username = (type?.['username'] as string | undefined) ?? '';
  if (proxy['server'] === '127.0.0.1' && type?.['@type'] === 'proxyTypeHttp' &&
    username.startsWith(HTTPS_PROXY_MARKER)) { return username.slice(HTTPS_PROXY_MARKER.length); }
  return '';
}

function configOf(proxy: TdObject): HttpsProxyConfig {
  const type = proxy['type'] as TdObject;
  return {
    server: (proxy['server'] as string) ?? '', port: (proxy['port'] as number) ?? 0,
    username: (type['username'] as string) ?? '', password: (type['password'] as string) ?? '',
    type: type['@type'] as string, httpOnly: type['http_only'] === true
  };
}

function nativeProxy(record: HttpsProxyRecord, port: number, httpOnly: boolean = record.httpOnly ?? false): TdObject {
  const type: TdObject = { '@type': 'proxyTypeHttp' };
  type['username'] = HTTPS_PROXY_MARKER + record.key;
  type['password'] = record.token;
  type['http_only'] = httpOnly;
  const proxy: TdObject = { '@type': 'proxy' };
  proxy['server'] = '127.0.0.1'; proxy['port'] = port; proxy['type'] = type;
  return proxy;
}

// Saved native IDs remain visible to callers. One hidden HTTP entry is TDLib's live
// ingress; route changes inside that ingress close old tunnels without reconfiguring TDLib.
export class HttpsProxyRuntime {
  private records: HttpsProxyRecord[] = [];
  private loaded: boolean = false;
  private initialized: boolean = false;
  private closed: boolean = false;
  private queue: Promise<void> = Promise.resolve();
  private recoveryTimer: number = -1;
  private recoveryDelay: number = 1000;
  private listenerRevision: number = 0;
  private ingressId: number = 0;
  private client: ProxyRequestClient;
  private registry: HttpsRegistry;
  private relay: HttpsRelay;
  private randomId: () => string;

  constructor(client: ProxyRequestClient, registry: HttpsRegistry, relay?: HttpsRelay,
    randomId: () => string = (): string => util.generateRandomUUID(true)) {
    this.client = client; this.registry = registry; this.randomId = randomId;
    this.relay = relay ?? new HttpsProxyRelay((): void => this.recoverListener());
  }

  private recoverListener(): void {
    if (this.closed) { return; }
    this.initialized = false; this.listenerRevision++;
    if (this.recoveryTimer !== -1) { return; }
    this.recoveryTimer = setTimeout((): void => {
      this.recoveryTimer = -1;
      this.prepare().then((): void => { this.recoveryDelay = 1000; }, (): void => {
        this.recoveryDelay = Math.min(30000, this.recoveryDelay * 2); this.recoverListener();
      });
    }, this.recoveryDelay);
  }

  private assertOpen(): void { if (this.closed) { throw new Error('proxy runtime closed'); } }
  private serial<T>(task: () => Promise<T>): Promise<T> {
    const result = this.queue.then(async (): Promise<T> => { this.assertOpen(); return task(); });
    this.queue = result.then((): void => {}, (): void => {}); return result;
  }
  prepare(): Promise<void> { return this.serial((): Promise<void> => this.restore()); }

  private async rawList(): Promise<TdObject[]> {
    const result = await this.client.send({ '@type': 'getProxies' } as TdRequest);
    this.assertOpen(); return (result['proxies'] as TdObject[] | undefined) ?? [];
  }
  private persist(records: HttpsProxyRecord[]): void { this.registry.write(records); this.records = records; }
  private record(key: string): HttpsProxyRecord {
    const record = this.records.find((r: HttpsProxyRecord): boolean => r.key === key);
    if (record === undefined) { throw new Error('proxy configuration missing'); }
    return record;
  }
  private control(): HttpsProxyRecord { return this.record(ACTIVE_ROUTE_KEY); }
  private selected(rows: TdObject[]): number {
    const active = rows.find((r: TdObject): boolean => r['is_enabled'] === true);
    if (active === undefined) { return 0; }
    return localKey(active['proxy'] as TdObject) === ACTIVE_ROUTE_KEY ?
      this.control().selectedId ?? 0 : active['id'] as number;
  }
  private route(id: number, rows: TdObject[]): HttpsProxyRecord {
    const control = this.control();
    let config: HttpsProxyConfig = { type: PROXY_DIRECT, server: '', port: 0, username: '', password: '' };
    if (id > 0) {
      const row = rows.find((r: TdObject): boolean => r['id'] === id && id !== this.ingressId);
      if (row === undefined) { throw new Error('proxy route missing'); }
      const key = localKey(row['proxy'] as TdObject);
      if (key === '' || key === ACTIVE_ROUTE_KEY) { throw new Error('proxy route is native'); }
      config = this.record(key);
    }
    return { server: config.server, port: config.port, username: config.username, password: config.password,
      type: relayProxyType(config), httpOnly: config.httpOnly === true,
      key: control.key, token: control.token, selectedId: id };
  }
  private setSelected(id: number): void {
    this.persist(this.records.map((r: HttpsProxyRecord): HttpsProxyRecord => r.key !== ACTIVE_ROUTE_KEY ? r : {
      key: r.key, token: r.token, type: PROXY_DIRECT, server: '', port: 0, username: '', password: '', selectedId: id
    }));
  }
  private createRecord(config: HttpsProxyConfig): HttpsProxyRecord {
    if (!validRelayProxy(config)) { throw new Error('invalid proxy configuration'); }
    return { server: config.server, port: config.port, username: config.username, password: config.password,
      type: relayProxyType(config), httpOnly: config.httpOnly === true, key: this.randomId(), token: this.randomId() };
  }
  private savedRecord(config: HttpsProxyConfig): HttpsProxyRecord {
    const known = this.records.find((r: HttpsProxyRecord): boolean => r.key !== ACTIVE_ROUTE_KEY &&
      relayProxyType(r) === relayProxyType(config) && (r.httpOnly === true) === (config.httpOnly === true) &&
      r.server === config.server && r.port === config.port && r.username === config.username && r.password === config.password);
    if (known !== undefined) { return known; }
    const record = this.createRecord(config); this.persist([...this.records, record]); return record;
  }
  private async updateNative(row: TdObject, record: HttpsProxyRecord, port: number, enable: boolean): Promise<TdObject> {
    const edit: TdRequest = { '@type': 'editProxy' };
    edit['proxy_id'] = row['id']; edit['proxy'] = nativeProxy(record, port); edit['enable'] = enable;
    const result = await this.client.send(edit, 20000); this.assertOpen(); return result;
  }

  private async restore(): Promise<void> {
    if (this.initialized) { return; }
    const revision = this.listenerRevision;
    if (!this.loaded) {
      const next = this.registry.read().map((r: HttpsProxyRecord): HttpsProxyRecord => ({
        server: r.server, port: r.port, username: r.username, password: r.password,
        type: relayProxyType(r), httpOnly: r.httpOnly === true, selectedId: r.selectedId,
        key: r.key, token: this.randomId()
      }));
      if (next.length > 0) { this.persist(next); } else { this.records = next; }
      this.loaded = true;
    }
    let rows = await this.rawList();
    // Resolve the logical selection before migrating or hiding any native entry.
    let selected = this.selected(rows);
    if (selected > 0 && !rows.some((r: TdObject): boolean => r['id'] === selected)) { selected = 0; }
    if (!this.records.some((r: HttpsProxyRecord): boolean => r.key === ACTIVE_ROUTE_KEY)) {
      this.persist([...this.records, { key: ACTIVE_ROUTE_KEY, token: this.randomId(), type: PROXY_DIRECT,
        server: '', port: 0, username: '', password: '', selectedId: selected }]);
    }
    const port = await this.relay.start(); this.assertOpen();
    for (const row of rows) {
      const proxy = row['proxy'] as TdObject; const key = localKey(proxy);
      if (key === ACTIVE_ROUTE_KEY) { this.ingressId = row['id'] as number; continue; }
      const config = configOf(proxy);
      if (key === '' && !usesProxyRelay(relayProxyType(config))) { continue; }
      const record = key === '' ? this.savedRecord(config) : this.record(key);
      this.relay.register(record);
      // Preserve the current native selection until the shared ingress is ready.
      await this.updateNative(row, record, port, row['is_enabled'] === true);
    }
    rows = await this.rawList();
    const selectedRow = rows.find((r: TdObject): boolean => r['id'] === selected);
    const managed = selected === 0 || (selectedRow !== undefined && localKey(selectedRow['proxy'] as TdObject) !== '');
    this.setSelected(selected);
    const route = this.route(managed ? selected : 0, rows);
    this.relay.replace(route);
    const ingress = rows.find((r: TdObject): boolean => localKey(r['proxy'] as TdObject) === ACTIVE_ROUTE_KEY);
    if (ingress === undefined) {
      const add: TdRequest = { '@type': 'addProxy' }; add['proxy'] = nativeProxy(route, port); add['enable'] = managed;
      const added = await this.client.send(add, 20000); this.assertOpen(); this.ingressId = added['id'] as number;
    } else {
      const edited = await this.updateNative(ingress, route, port, managed);
      this.ingressId = edited['id'] as number;
    }
    if (!this.ingressId) { throw new Error('proxy ingress missing'); }
    await this.prune(); this.assertOpen();
    if (revision !== this.listenerRevision) { throw new Error('proxy listener changed'); }
    this.initialized = true;
  }

  private decoded(row: TdObject, selected: number): TdObject {
    const proxy = row['proxy'] as TdObject | undefined; if (proxy === undefined) { return row; }
    const key = localKey(proxy); const result = copy(row); result['is_enabled'] = row['id'] === selected;
    if (key === '') { return result; }
    const record = this.record(key); const type: TdObject = { '@type': relayProxyType(record) };
    type['username'] = record.username; type['password'] = record.password; type['http_only'] = record.httpOnly === true;
    const original: TdObject = { '@type': 'proxy' };
    original['server'] = record.server; original['port'] = record.port; original['type'] = type; result['proxy'] = original;
    return result;
  }

  private async select(id: number, rows: TdObject[]): Promise<TdObject> {
    const oldId = this.selected(rows);
    const row = rows.find((r: TdObject): boolean => r['id'] === id && id !== this.ingressId);
    if (id > 0 && row === undefined) { throw new Error('proxy route missing'); }
    if (row !== undefined && localKey(row['proxy'] as TdObject) === '') {
      const enable: TdRequest = { '@type': 'enableProxy' }; enable['proxy_id'] = id;
      const result = await this.client.send(enable, 20000); this.assertOpen();
      this.relay.replace(this.route(0, rows));
      // Native selection is authoritative even if the optional selection snapshot cannot be written.
      try { this.setSelected(id); } catch (_error) {}
      return result;
    }
    const route = this.route(id, rows);
    const ingress = rows.find((r: TdObject): boolean => r['id'] === this.ingressId);
    if (ingress === undefined) { throw new Error('proxy ingress missing'); }
    this.setSelected(id);
    this.relay.replace(route);
    const nativeType = (ingress['proxy'] as TdObject)['type'] as TdObject;
    const modeChanged = (nativeType['http_only'] === true) !== (route.httpOnly === true);
    // The common switch path does not edit, disable or enable anything in TDLib.
    if (ingress['is_enabled'] === true && !modeChanged) { return { '@type': 'ok' }; }
    try {
      if (modeChanged) {
        await this.updateNative(ingress, route, await this.relay.start(), true);
      } else {
        const enable: TdRequest = { '@type': 'enableProxy' }; enable['proxy_id'] = this.ingressId;
        await this.client.send(enable, 20000);
      }
      this.assertOpen(); return { '@type': 'ok' };
    } catch (error) {
      // A timed-out native switch may have succeeded. Confirm before restoring the old route.
      const actual = await this.rawList();
      const current = actual.find((r: TdObject): boolean => r['id'] === this.ingressId && r['is_enabled'] === true);
      if (current !== undefined && (((current['proxy'] as TdObject)['type'] as TdObject)['http_only'] === true) ===
        (route.httpOnly === true)) { return { '@type': 'ok' }; }
      const old = actual.find((r: TdObject): boolean => r['id'] === oldId);
      const rollbackId = old === undefined ? 0 : oldId;
      this.setSelected(rollbackId);
      this.relay.replace(this.route(rollbackId === 0 || (old !== undefined && localKey(old['proxy'] as TdObject) !== '') ? rollbackId : 0, actual));
      throw new Error('proxy switch failed');
    }
  }

  private async selectDirect(): Promise<TdObject> {
    try { await this.restore(); return await this.select(0, await this.rawList()); }
    catch (_error) {
      this.assertOpen(); this.initialized = false;
      // Native direct remains an escape hatch if the listener, registry or HTTP-only edit failed.
      return this.client.send({ '@type': 'disableProxy' } as TdRequest, 20000);
    }
  }

  send(request: TdRequest, timeoutMs: number = 20000, cancellation?: ProxyProbeCancellation): Promise<TdObject> {
    if (request['@type'] === 'pingProxy' || request['@type'] === 'testProxy') {
      const probe = (): Promise<TdObject> => request['@type'] === 'pingProxy' ?
        this.ping(request, timeoutMs, cancellation) : this.test(request, timeoutMs, cancellation);
      return cancellation === undefined ? probe() : cancellation.run(probe);
    }
    return this.serial(async (): Promise<TdObject> => {
      const kind = request['@type'];
      if (kind === 'disableProxy') { return this.selectDirect(); }
      await this.restore(); this.assertOpen();
      let rows = await this.rawList();
      if (kind === 'getProxies') {
        const result: TdObject = { '@type': 'addedProxies' }; const selected = this.selected(rows);
        result['proxies'] = rows.filter((r: TdObject): boolean => localKey(r['proxy'] as TdObject) !== ACTIVE_ROUTE_KEY)
          .map((r: TdObject): TdObject => this.decoded(r, selected));
        return result;
      }
      if (kind === 'enableProxy') { return this.select(request['proxy_id'] as number, rows); }
      if (kind === 'getProxyLink') {
        const row = rows.find((r: TdObject): boolean => r['id'] === request['proxy_id']);
        if (row === undefined || row['id'] === this.ingressId) { throw new Error('proxy route missing'); }
        const key = localKey(row['proxy'] as TdObject);
        if (key !== '') {
          const record = this.record(key);
          if (relayProxyType(record) !== 'proxyTypeSocks5') { throw new Error('HTTP proxy sharing unsupported'); }
          const result: TdObject = { '@type': 'httpUrl' };
          result['url'] = `tg://socks?server=${encodeURIComponent(record.server)}&port=${record.port}` +
            (record.username === '' ? '' : `&user=${encodeURIComponent(record.username)}`) +
            (record.password === '' ? '' : `&pass=${encodeURIComponent(record.password)}`);
          return result;
        }
      }
      const oldId = this.selected(rows);
      let outgoing = request;
      if (kind === 'addProxy' || kind === 'editProxy') {
        const proxy = request['proxy'] as TdObject; const config = configOf(proxy);
        if (usesProxyRelay(relayProxyType(config))) {
          const record = this.savedRecord(config); this.relay.register(record);
          const port = await this.relay.start(); this.assertOpen();
          outgoing = copy(request) as TdRequest; outgoing['proxy'] = nativeProxy(record, port); outgoing['enable'] = false;
        }
      }
      if ((kind === 'removeProxy' || kind === 'editProxy') && request['proxy_id'] === this.ingressId) {
        throw new Error('proxy ingress is internal');
      }
      const result = await this.client.send(outgoing, timeoutMs); this.assertOpen();
      if (kind === 'addProxy' || kind === 'editProxy') {
        rows = await this.rawList();
        if (request['enable'] === true) { await this.select(result['id'] as number, rows); }
        else if (kind === 'editProxy' && oldId === request['proxy_id']) { await this.selectDirect(); }
        await this.prune();
        return this.decoded(result, this.selected(await this.rawList()));
      }
      if (kind === 'removeProxy') {
        if (oldId === request['proxy_id']) { await this.selectDirect(); }
        await this.prune();
      }
      return result;
    });
  }

  private async prune(): Promise<void> {
    try {
      const rows = await this.rawList();
      const keys = rows.map((r: TdObject): string => localKey(r['proxy'] as TdObject));
      const previous = this.records;
      const retained = this.records.filter((r: HttpsProxyRecord): boolean => r.key === ACTIVE_ROUTE_KEY || keys.indexOf(r.key) >= 0);
      this.persist(retained);
      previous.forEach((r: HttpsProxyRecord): void => {
        if (r.key !== ACTIVE_ROUTE_KEY && keys.indexOf(r.key) < 0) { this.relay.unregister(r.key); }
      });
    } catch (_error) { /* Uncertain native results retain recoverable credentials. */ }
  }

  private async ping(request: TdRequest, timeoutMs: number, cancellation?: ProxyProbeCancellation): Promise<TdObject> {
    if (request['proxy_id'] !== 0) {
      await this.prepare(); this.assertOpen();
      cancellation?.assertActive();
      if (request['proxy_id'] === this.ingressId) { throw new Error('proxy ingress is internal'); }
      if (cancellation !== undefined) {
        const row = (await this.rawList()).find((item: TdObject): boolean => item['id'] === request['proxy_id']);
        cancellation.assertActive();
        if (row === undefined) { throw new Error('proxy probe route missing'); }
        const key = localKey(row['proxy'] as TdObject);
        const config = key === '' ? configOf(row['proxy'] as TdObject) : this.record(key);
        if (usesProxyRelay(relayProxyType(config))) {
          const started = Date.now();
          // A race gets unique credentials. Revoke them immediately on cancel;
          // never close another caller's test or the selected route's tunnels.
          await this.testConfig(config, timeoutMs, cancellation);
          return { '@type': 'seconds', 'seconds': (Date.now() - started) / 1000 };
        }
      }
      return this.client.send(request, timeoutMs);
    }
    // Direct latency probing must not restore or select the shared ingress.
    // Restoring here could edit the hidden native proxy and turn the system
    // proxy on as a side effect of merely opening the proxy page.
    this.assertOpen();
    const started = Date.now();
    await this.testConfig({ type: PROXY_DIRECT, server: '', port: 0, username: '', password: '' }, timeoutMs, cancellation);
    const result: TdObject = { '@type': 'seconds' }; result['seconds'] = (Date.now() - started) / 1000; return result;
  }
  private async testConfig(config: HttpsProxyConfig, timeoutMs: number,
    cancellation?: ProxyProbeCancellation): Promise<TdObject> {
    cancellation?.assertActive();
    const record = this.createRecord(config); this.relay.register(record);
    let released = false;
    const release = (): void => {
      if (released) { return; }
      released = true;
      this.relay.unregister(record.key);
    };
    const unsubscribe = cancellation?.subscribe(release);
    try {
      const port = await this.relay.start(); this.assertOpen();
      cancellation?.assertActive();
      const request: TdRequest = { '@type': 'testProxy' };
      request['proxy'] = nativeProxy(record, port); request['dc_id'] = 2; request['timeout'] = Math.max(1, timeoutMs / 1000 - 2);
      return await this.client.send(request, timeoutMs);
    } finally { unsubscribe?.(); release(); }
  }
  private async test(request: TdRequest, timeoutMs: number, cancellation?: ProxyProbeCancellation): Promise<TdObject> {
    // Form tests use a temporary relay entry and must not restore the saved
    // route first.  restore() may add/edit/enable the hidden ingress, which
    // makes a latency test change the visible system-proxy switch.
    this.assertOpen();
    const config = configOf(request['proxy'] as TdObject);
    return usesProxyRelay(relayProxyType(config)) ? this.testConfig(config, timeoutMs, cancellation) : this.client.send(request, timeoutMs);
  }
  close(): void {
    this.closed = true;
    if (this.recoveryTimer !== -1) { clearTimeout(this.recoveryTimer); this.recoveryTimer = -1; }
    this.relay.close();
  }
  // See HttpsProxyRelay.dropOlderThan: forces native TDLib to redial instead of
  // waiting out a ping timeout on a connection that died while it was suspended.
  dropTunnelsBefore(createdBefore: number): number {
    return this.closed ? 0 : this.relay.dropOlderThan(createdBefore);
  }
}

class NativeProxyClient implements ProxyRequestClient {
  private client: TdClient;
  constructor(client: TdClient) { this.client = client; }
  send(request: TdRequest, timeoutMs: number = 20000): Promise<TdObject> {
    return this.client.send(request, timeoutMs);
  }
}

const runtimes: Map<TdClient, HttpsProxyRuntime> = new Map();

export function attachHttpsProxyRuntime(client: TdClient, databaseDir: string): void {
  runtimes.set(client, new HttpsProxyRuntime(new NativeProxyClient(client),
    new FileHttpsRegistry(`${databaseDir}/https-proxies.json`)));
}

export function restoreHttpsProxyRuntime(client: TdClient): Promise<void> {
  return runtimes.get(client)?.prepare() ?? Promise.resolve();
}

export function detachHttpsProxyRuntime(client: TdClient): void {
  runtimes.get(client)?.close();
  runtimes.delete(client);
}

// Close relay tunnels that predate `createdBefore`. Used after returning to the
// foreground: native TDLib then redials at once instead of waiting out its ping
// timeout on connections that died while the process was suspended.
export function dropRelayTunnelsBefore(client: TdClient, createdBefore: number): number {
  return runtimes.get(client)?.dropTunnelsBefore(createdBefore) ?? 0;
}

export function sendProxyRequest(client: TdClient, request: TdRequest, timeoutMs: number = 20000,
  cancellation?: ProxyProbeCancellation): Promise<TdObject> {
  const runtime = runtimes.get(client);
  if (runtime !== undefined) { return runtime.send(request, timeoutMs, cancellation); }
  return cancellation === undefined ? client.send(request, timeoutMs) :
    cancellation.run((): Promise<TdObject> => client.send(request, timeoutMs));
}
