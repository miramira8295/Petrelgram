import { fileIo } from '@kit.CoreFileKit';
import { TdClient } from '../tdkit/TdClient';
import { TdObject, TdRequest } from '../tdkit/TdTypes';
import { logE, logI, logW } from '../util/log';

// 1.5.5 及以前的代理是"假的"：用户填的真实地址留在本机 JSON，TDLib 里存的是
// 127.0.0.1:<本地中继端口> + 用户名 petrel_tls_<key>，入口那条还带着 enable。
// 中继层删掉之后那些端口没人监听，TDLib 会一直卡在连接中——而且是**升级即复现**，
// 用户没有任何办法自己修好（代理页显示的是解码后的真实地址，删掉再加也一样，
// 因为入口是隐藏的）。
//
// 所以删除中继层的前提是这份迁移先跑：把假条目还原成真实地址，还原不了的
// （TLS 代理已经不支持）删掉，入口那条无条件删除。
//
// 幂等：跑完之后库里不再有 127.0.0.1 的条目，再跑一次什么也不会做。
const ACTIVE_ROUTE_KEY: string = '00000000-0000-4000-8000-000000000000';
const RELAY_MARKER: string = 'petrel_tls_';
const PROXY_HTTPS: string = 'proxyTypeHttps';
const PROXY_SOCKS5: string = 'proxyTypeSocks5';
const PROXY_HTTP: string = 'proxyTypeHttp';
const REGISTRY_FILE: string = 'https-proxies.json';
const REQUEST_TIMEOUT_MS: number = 20000;

interface LegacyRecord {
  key: string;
  type?: string;
  httpOnly?: boolean;
  server: string;
  port: number;
  username: string;
  password: string;
}

function isOurs(proxy: TdObject): boolean {
  const type = proxy['type'] as TdObject | undefined;
  if (proxy['server'] !== '127.0.0.1' || type === undefined || type['@type'] !== PROXY_HTTP) {
    return false;
  }
  return ((type['username'] as string | undefined) ?? '').startsWith(RELAY_MARKER);
}

function relayKey(proxy: TdObject): string {
  const type = proxy['type'] as TdObject;
  return ((type['username'] as string | undefined) ?? '').slice(RELAY_MARKER.length);
}

// 读不回来就当没有：宁可删掉这条代理，也不能把一个指向 127.0.0.1 的条目留在库里。
function readRegistry(path: string): LegacyRecord[] {
  try {
    if (!fileIo.accessSync(path)) {
      return [];
    }
    const rows = JSON.parse(fileIo.readTextSync(path)) as LegacyRecord[];
    if (!Array.isArray(rows)) {
      return [];
    }
    return rows.filter((r: LegacyRecord): boolean => typeof r.key === 'string' && r.key.length > 0 &&
      typeof r.server === 'string' && r.server.length > 0 && Number.isInteger(r.port) && r.port > 0);
  } catch (error) {
    logW(`[proxy-migration] registry unreadable: ${(error as Error).message}`);
    return [];
  }
}

function nativeType(record: LegacyRecord): TdObject | undefined {
  const kind = record.type ?? PROXY_HTTPS;
  // TLS 代理没有承载者了（TDLib 的 ProxyType 只有 socks5/http/mtproto）。
  if (kind === PROXY_HTTPS) {
    return undefined;
  }
  if (kind !== PROXY_HTTP && kind !== PROXY_SOCKS5) {
    return undefined;
  }
  const type: TdObject = { '@type': kind };
  type['username'] = record.username;
  type['password'] = record.password;
  if (kind === PROXY_HTTP) {
    type['http_only'] = record.httpOnly === true;
  }
  return type;
}

export class ProxyMigration {
  private databaseDirectory: string;
  private done: boolean = false;
  private pending: Promise<void> | undefined = undefined;

  constructor(databaseDirectory: string) {
    this.databaseDirectory = databaseDirectory;
  }

  private registryPath(): string {
    return `${this.databaseDirectory}/${REGISTRY_FILE}`;
  }

  // 已经迁移过就直接返回。失败不设 done，下一次调用会重来——密码还在 JSON 里，
  // 只要别把 JSON 删掉就还有救。
  ensure(client: TdClient): Promise<void> {
    if (this.done) {
      return Promise.resolve();
    }
    if (this.pending === undefined) {
      this.pending = this.run(client).then((): void => {
        this.done = true;
        this.pending = undefined;
      }, (error: Error): never => {
        this.pending = undefined;
        throw error;
      });
    }
    return this.pending;
  }

  private async send(client: TdClient, request: TdRequest): Promise<TdObject> {
    return client.send(request, REQUEST_TIMEOUT_MS);
  }

  private async run(client: TdClient): Promise<void> {
    const records = readRegistry(this.registryPath());
    const result = await this.send(client, { '@type': 'getProxies' } as TdRequest);
    const rows = (result['proxies'] as TdObject[] | undefined) ?? [];
    let converted = 0;
    let dropped = 0;
    for (const row of rows) {
      const proxy = row['proxy'] as TdObject | undefined;
      if (proxy === undefined || !isOurs(proxy)) {
        continue;
      }
      const id = (row['id'] as number | undefined) ?? 0;
      const enabled = row['is_enabled'] === true;
      const key = relayKey(proxy);
      // 隐藏入口：先关掉再删，否则删除的瞬间 TDLib 还指着它。
      if (key === ACTIVE_ROUTE_KEY) {
        if (enabled) {
          await this.send(client, { '@type': 'disableProxy' } as TdRequest);
        }
        await this.send(client, this.removeRequest(id));
        dropped++;
        continue;
      }
      const record = records.find((item: LegacyRecord): boolean => item.key === key);
      const type = record === undefined ? undefined : nativeType(record);
      if (record === undefined || type === undefined) {
        if (enabled) {
          await this.send(client, { '@type': 'disableProxy' } as TdRequest);
        }
        await this.send(client, this.removeRequest(id));
        dropped++;
        continue;
      }
      const edit: TdRequest = { '@type': 'editProxy' };
      const native: TdObject = { '@type': 'proxy' };
      native['server'] = record.server;
      native['port'] = record.port;
      native['type'] = type;
      edit['proxy_id'] = id;
      edit['proxy'] = native;
      edit['enable'] = enabled;
      await this.send(client, edit);
      converted++;
    }
    if (converted === 0 && dropped === 0) {
      return;
    }
    logI(`[proxy-migration] restored=${converted} removed=${dropped}`);
    // 只有整轮成功了才丢弃凭据副本；失败时留着，下次启动还能重试。
    try {
      if (fileIo.accessSync(this.registryPath())) {
        fileIo.unlinkSync(this.registryPath());
      }
    } catch (error) {
      logW(`[proxy-migration] registry cleanup failed: ${(error as Error).message}`);
    }
  }

  private removeRequest(id: number): TdRequest {
    const request: TdRequest = { '@type': 'removeProxy' };
    request['proxy_id'] = id;
    return request;
  }
}

const migrations: Map<TdClient, ProxyMigration> = new Map();

export function attachProxyMigration(client: TdClient, databaseDirectory: string): void {
  migrations.set(client, new ProxyMigration(databaseDirectory));
}

export function detachProxyMigration(client: TdClient): void {
  migrations.delete(client);
}

// 调用方不关心失败：迁移失败最多是这次显示的是旧条目，下次启动再试。
export function ensureProxyMigration(client: TdClient): Promise<void> {
  const migration = migrations.get(client);
  if (migration === undefined) {
    return Promise.resolve();
  }
  return migration.ensure(client).catch((error: Error): void => {
    logE(`[proxy-migration] failed: ${error.message}`);
  });
}
