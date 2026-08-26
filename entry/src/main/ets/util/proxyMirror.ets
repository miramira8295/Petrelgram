// 代理清单的本机镜像。
//
// 代理存在 TDLib 里，而 TDLib 数据库是**按账号槽**分开的：加了第二个账号，
// 代理列表是空的，要重新一条条加（issue #131）。这里在本机留一份镜像，换到
// 一个还没有代理的账号时补回去。
//
// 镜像里有服务器地址和凭据，**只落本机 Preferences，任何日志都不许打**。
import { ProxyEntry, PROXY_SOCKS5 } from '../store/ProxyApi';

export const KEY_PROXY_MIRROR: string = 'proxyMirror';
// 不参与同步的代理（按 proxyKeyOf 记）。存"排除表"而不是"允许表"：默认同步，
// 用户在 ⋮ 菜单里单条关掉才进这个表，老用户不用迁移。
export const KEY_PROXY_SYNC_OFF: string = 'proxySyncOff';

interface MirrorRow {
  server: string;
  port: number;
  type: string;
  username: string;
  password: string;
  secret: string;
  httpOnly: boolean;
}

function rowOf(entry: ProxyEntry): MirrorRow {
  return {
    server: entry.server, port: entry.port, type: entry.type,
    username: entry.username, password: entry.password,
    secret: entry.secret, httpOnly: entry.httpOnly
  };
}

// 同一台服务器的同一端口同一协议算同一条：id 是 TDLib 给的，换账号就变了，
// 不能拿来判重。
export function proxyKeyOf(entry: ProxyEntry): string {
  return `${entry.type}|${entry.server}|${entry.port}`;
}

export function serializeProxyMirror(entries: ProxyEntry[]): string {
  if (entries.length === 0) {
    return '';
  }
  return JSON.stringify(entries.map((e: ProxyEntry): MirrorRow => rowOf(e)));
}

export function parseProxyMirror(raw: string): ProxyEntry[] {
  if (raw === '') {
    return [];
  }
  try {
    const rows = JSON.parse(raw) as MirrorRow[];
    if (!Array.isArray(rows)) {
      return [];
    }
    const out: ProxyEntry[] = [];
    for (const r of rows) {
      const server: string = (r.server ?? '').toString();
      const port: number = Number(r.port);
      if (server === '' || !Number.isFinite(port) || port <= 0) {
        continue;
      }
      out.push({
        id: 0, server: server, port: Math.round(port),
        type: (r.type ?? PROXY_SOCKS5).toString(),
        username: (r.username ?? '').toString(),
        password: (r.password ?? '').toString(),
        secret: (r.secret ?? '').toString(),
        httpOnly: r.httpOnly === true,
        lastUsedDate: 0, isEnabled: false
      });
    }
    return out;
  } catch (e) {
    return []; // 坏了就当没有，绝不把内容打进日志
  }
}

// 镜像里有、当前账号没有的那些。补回去时一律不启用：换账号的那一刻自动切代理
// 会把连接状态搅乱，用户自己点启用更稳妥。
export function missingFromAccount(mirror: ProxyEntry[], current: ProxyEntry[]): ProxyEntry[] {
  const have = new Set<string>();
  for (const e of current) {
    have.add(proxyKeyOf(e));
  }
  const out: ProxyEntry[] = [];
  const seen = new Set<string>();
  for (const e of mirror) {
    const key = proxyKeyOf(e);
    if (have.has(key) || seen.has(key)) {
      continue;
    }
    seen.add(key);
    out.push(e);
  }
  return out;
}

export function parseSyncOff(raw: string): string[] {
  if (raw === '') {
    return [];
  }
  try {
    const rows = JSON.parse(raw) as string[];
    return Array.isArray(rows) ? rows.filter((r: string): boolean => typeof r === 'string') : [];
  } catch (e) {
    return [];
  }
}

export function serializeSyncOff(keys: string[]): string {
  return keys.length === 0 ? '' : JSON.stringify(keys);
}

export function syncEnabledFor(entry: ProxyEntry, syncOff: string[]): boolean {
  return syncOff.indexOf(proxyKeyOf(entry)) < 0;
}

export function toggledSyncOff(entry: ProxyEntry, syncOff: string[]): string[] {
  const key = proxyKeyOf(entry);
  const at = syncOff.indexOf(key);
  if (at < 0) {
    return [...syncOff, key];
  }
  return syncOff.filter((k: string): boolean => k !== key);
}

// 只镜像允许同步的那些。
export function syncableOf(entries: ProxyEntry[], syncOff: string[]): ProxyEntry[] {
  return entries.filter((e: ProxyEntry): boolean => syncEnabledFor(e, syncOff));
}
