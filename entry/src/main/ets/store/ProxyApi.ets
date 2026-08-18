import { getTdClient } from '../tdkit/Globals';
import { TdError, TdObject, TdRequest } from '../tdkit/TdTypes';

// Proxy management remains entirely inside TDLib. No native socket, call,
// media, or DNS implementation is replaced by this module.
export const PROXY_SOCKS5: string = 'proxyTypeSocks5';
export const PROXY_MTPROTO: string = 'proxyTypeMtproto';
export const PROXY_HTTP: string = 'proxyTypeHttp';

export interface ProxyEntry {
  id: number;
  server: string;
  port: number;
  type: string;
  username: string;
  password: string;
  secret: string;
  httpOnly: boolean;
  lastUsedDate: number;
  isEnabled: boolean;
}

export function proxyTypeLabel(type: string): string {
  if (type === PROXY_MTPROTO) { return 'MTProto'; }
  if (type === PROXY_HTTP) { return 'HTTP'; }
  return 'SOCKS5';
}

export function proxyObjectOf(entry: ProxyEntry): TdObject {
  const type: TdObject = { '@type': entry.type };
  if (entry.type === PROXY_MTPROTO) {
    type['secret'] = entry.secret;
  } else {
    type['username'] = entry.username;
    type['password'] = entry.password;
    if (entry.type === PROXY_HTTP) {
      type['http_only'] = entry.httpOnly;
    }
  }
  const proxy: TdObject = { '@type': 'proxy' };
  proxy['server'] = entry.server;
  proxy['port'] = entry.port;
  proxy['type'] = type;
  return proxy;
}

export function proxyEntryFromAddedObject(added: TdObject): ProxyEntry {
  const proxy = (added['proxy'] as TdObject | undefined) ?? {} as TdObject;
  const type = (proxy['type'] as TdObject | undefined) ?? {} as TdObject;
  return {
    id: (added['id'] as number | undefined) ?? 0,
    server: (proxy['server'] as string | undefined) ?? '',
    port: (proxy['port'] as number | undefined) ?? 0,
    type: (type['@type'] as string | undefined) ?? PROXY_SOCKS5,
    username: (type['username'] as string | undefined) ?? '',
    password: (type['password'] as string | undefined) ?? '',
    secret: (type['secret'] as string | undefined) ?? '',
    httpOnly: (type['http_only'] as boolean | undefined) ?? false,
    lastUsedDate: (added['last_used_date'] as number | undefined) ?? 0,
    isEnabled: (added['is_enabled'] as boolean | undefined) ?? false
  };
}

export async function listProxies(): Promise<ProxyEntry[]> {
  const result = await getTdClient().send({ '@type': 'getProxies' } as TdRequest);
  const list = (result['proxies'] as TdObject[] | undefined) ?? [];
  return list.map((added: TdObject): ProxyEntry => proxyEntryFromAddedObject(added));
}

export async function addProxy(entry: ProxyEntry, enable: boolean): Promise<ProxyEntry> {
  const request: TdRequest = { '@type': 'addProxy' };
  request['proxy'] = proxyObjectOf(entry);
  request['enable'] = enable;
  const result = await getTdClient().send(request, 20000);
  return proxyEntryFromAddedObject(result);
}

export async function editProxy(entry: ProxyEntry, enable: boolean): Promise<ProxyEntry> {
  const request: TdRequest = { '@type': 'editProxy' };
  request['proxy_id'] = entry.id;
  request['proxy'] = proxyObjectOf(entry);
  request['enable'] = enable;
  const result = await getTdClient().send(request, 20000);
  return proxyEntryFromAddedObject(result);
}

export async function enableProxy(id: number): Promise<void> {
  const request: TdRequest = { '@type': 'enableProxy' };
  request['proxy_id'] = id;
  await getTdClient().send(request, 20000);
}

export async function disableProxy(): Promise<void> {
  await getTdClient().send({ '@type': 'disableProxy' } as TdRequest, 20000);
}

export async function removeProxy(id: number): Promise<void> {
  const request: TdRequest = { '@type': 'removeProxy' };
  request['proxy_id'] = id;
  await getTdClient().send(request, 20000);
}

// Computes Telegram round-trip time through a SAVED proxy. TDLib's pingProxy
// takes proxy_id only — passing a proxy object is silently ignored and the
// request degrades to a direct-connection ping. proxyId 0 measures the direct
// connection on purpose.
export async function pingProxy(proxyId: number): Promise<number> {
  const request: TdRequest = { '@type': 'pingProxy' };
  request['proxy_id'] = proxyId;
  const result = await getTdClient().send(request, 12000);
  const seconds = (result['seconds'] as number | undefined) ?? -1;
  if (!Number.isFinite(seconds) || seconds < 0) {
    throw new TdError(-1, 'invalid proxy ping result');
  }
  return seconds;
}

// Full handshake through an UNSAVED proxy config (the add/edit form). TDLib's
// testProxy returns Ok, so latency is the measured wall time.
export async function testProxy(entry: ProxyEntry): Promise<number> {
  const request: TdRequest = { '@type': 'testProxy' };
  // 这个 TDLib 构建的 proxy 系列 API 收的是完整 proxy 对象，不是标准 schema
  // 的 server/port/type 平铺字段——平铺形状实测被拒（"Proxy must be
  // non-empty"，请求 JSON 完全符合标准 schema 却过不去），而同文件的
  // addProxy/editProxy 一直用 proxy 对象且工作正常。
  request['proxy'] = proxyObjectOf(entry);
  request['dc_id'] = 2;
  request['timeout'] = 10;
  console.error(`[proxy] testProxy request: ${JSON.stringify(request)}`);
  const startedAt = Date.now();
  await getTdClient().send(request, 12000);
  return (Date.now() - startedAt) / 1000;
}

export async function getProxyShareLink(id: number): Promise<string> {
  const request: TdRequest = { '@type': 'getProxyLink' };
  request['proxy_id'] = id;
  const result = await getTdClient().send(request);
  return (result['url'] as string | undefined) ?? '';
}

export async function getProxyConnectionState(): Promise<string> {
  const result = await getTdClient().send({ '@type': 'getConnectionState' } as TdRequest, 6000);
  return (result['@type'] as string | undefined) ?? '';
}
