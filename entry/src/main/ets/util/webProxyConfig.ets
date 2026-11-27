import { str } from './strings';

export interface WebProxyConfig {
  host: string;            // 例：proxy.example.com 或 proxy.example.com:8443
  path: string;            // 可选部署路径（不含首尾斜杠）
  secret: string;          // MTProxy secret：32/34 位 hex 或 base64url
  allowInvalidCert: boolean; // 仅自建测试环境用，默认 false
}

export interface WebProxyLinkInfo {
  host: string;
  path: string;
  secret: string;
}

export interface WebProxyReachTarget {
  host: string;
  port: number;
}

// 解析 WEB 代理远端域名为 TCP 握手测速目标（默认 HTTPS 443，支持 host:port 与 [ipv6]:port）。
export function webProxyReachTarget(rawHost: string): WebProxyReachTarget | null {
  const host: string = normalizeWebProxyHost(rawHost);
  if (host.length === 0) {
    return null;
  }
  if (host.startsWith('[')) {
    const close: number = host.indexOf(']');
    if (close <= 1) {
      return null;
    }
    const addr: string = host.substring(1, close);
    if (close + 1 < host.length && host.charAt(close + 1) === ':') {
      const port: number = Number(host.substring(close + 2));
      if (!Number.isInteger(port) || port <= 0 || port > 65535) {
        return null;
      }
      return { host: addr, port: port };
    }
    return { host: addr, port: 443 };
  }
  const colon: number = host.lastIndexOf(':');
  if (colon > 0) {
    const addr: string = host.substring(0, colon);
    const port: number = Number(host.substring(colon + 1));
    if (addr.length === 0 || !Number.isInteger(port) || port <= 0 || port > 65535) {
      return null;
    }
    return { host: addr, port: port };
  }
  return { host: host, port: 443 };
}

function isHexText(text: string): boolean {
  if (text.length === 0 || text.length % 2 !== 0) {
    return false;
  }
  for (let i = 0; i < text.length; i++) {
    const ch: string = text.charAt(i);
    const isDigit: boolean = ch >= '0' && ch <= '9';
    const isLower: boolean = ch >= 'a' && ch <= 'f';
    const isUpper: boolean = ch >= 'A' && ch <= 'F';
    if (!isDigit && !isLower && !isUpper) {
      return false;
    }
  }
  return true;
}

function hexBytes(text: string): Uint8Array {
  const out: Uint8Array = new Uint8Array(text.length / 2);
  for (let i = 0; i < out.length; i++) {
    out[i] = parseInt(text.substring(i * 2, i * 2 + 2), 16);
  }
  return out;
}

function base64Value(code: number): number {
  if (code >= 65 && code <= 90) { return code - 65; }       // A-Z
  if (code >= 97 && code <= 122) { return code - 71; }      // a-z
  if (code >= 48 && code <= 57) { return code + 4; }        // 0-9
  if (code === 43 || code === 45) { return 62; }            // + or -
  if (code === 47 || code === 95) { return 63; }            // / or _
  return -1;
}

export function decodeBase64UrlBytes(raw: string): Uint8Array | null {
  const text: string = raw.trim();
  if (text.length === 0) {
    return null;
  }
  let end: number = text.length;
  while (end > 0 && text.charCodeAt(end - 1) === 61) { // '='
    end--;
  }
  const pad: number = text.length - end;
  if (pad > 2 || (pad > 0 && text.length % 4 !== 0)) {
    return null;
  }
  const rem: number = end % 4;
  if (rem === 1) {
    return null;
  }
  const outLen: number = Math.floor(end / 4) * 3 + (rem === 2 ? 1 : rem === 3 ? 2 : 0);
  const out: Uint8Array = new Uint8Array(outLen);
  let at: number = 0;
  let i: number = 0;
  while (i + 4 <= end) {
    const a: number = base64Value(text.charCodeAt(i));
    const b: number = base64Value(text.charCodeAt(i + 1));
    const c: number = base64Value(text.charCodeAt(i + 2));
    const d: number = base64Value(text.charCodeAt(i + 3));
    if (a < 0 || b < 0 || c < 0 || d < 0) {
      return null;
    }
    const triple: number = (a << 18) | (b << 12) | (c << 6) | d;
    out[at++] = (triple >>> 16) & 0xff;
    out[at++] = (triple >>> 8) & 0xff;
    out[at++] = triple & 0xff;
    i += 4;
  }
  if (rem === 2) {
    const a: number = base64Value(text.charCodeAt(i));
    const b: number = base64Value(text.charCodeAt(i + 1));
    if (a < 0 || b < 0) {
      return null;
    }
    out[at++] = ((a << 2) | (b >>> 4)) & 0xff;
  } else if (rem === 3) {
    const a: number = base64Value(text.charCodeAt(i));
    const b: number = base64Value(text.charCodeAt(i + 1));
    const c: number = base64Value(text.charCodeAt(i + 2));
    if (a < 0 || b < 0 || c < 0) {
      return null;
    }
    const triple: number = (a << 10) | (b << 4) | (c >>> 2);
    out[at++] = (triple >>> 8) & 0xff;
    out[at++] = triple & 0xff;
  }
  return out;
}

// MTProxy secret 的规范化。与 OpenGram 鸿蒙端的行为一致：
//   · 32 位 hex（16 字节）= 普通 MTProxy secret；
//   · 34 位 hex（17 字节）且首字节 0xdd = 带随机填充的变体，**整段保留**；
//   · 17 字节且首字节 0x70 = 旧式前缀，剥掉；
//   · base64url（22/23 字符）同样接受。
export function webProxySecretBytes(raw: string): Uint8Array {
  const text: string = raw.trim();
  if (text.length === 0) {
    return new Uint8Array(0);
  }
  let bytes: Uint8Array;
  if (isHexText(text)) {
    bytes = hexBytes(text);
  } else {
    const decoded: Uint8Array | null = decodeBase64UrlBytes(text);
    if (decoded === null) {
      return new Uint8Array(0);
    }
    bytes = decoded;
  }
  if (bytes.length === 17 && bytes[0] === 0x70) {
    const rest: Uint8Array = new Uint8Array(16);
    rest.set(bytes.subarray(1));
    return rest;
  }
  return bytes;
}

// TDLib 1.8.71 原生 proxyTypeWeb.secret 只接受十六进制（32 位 hex 或 dd+32 位 hex）。
// tproxy-server / tg://webproxy 分享链接经常给 base64url（含 0x70 旧前缀），
// 交给 TDLib 前统一转成小写十六进制。
export function normalizeWebProxySecret(raw: string): string {
  const bytes: Uint8Array = webProxySecretBytes(raw);
  if (bytes.length === 0) {
    return raw.trim();
  }
  let hex: string = '';
  for (let i = 0; i < bytes.length; i++) {
    const part: string = bytes[i].toString(16);
    hex += part.length === 1 ? '0' + part : part;
  }
  return hex;
}

// 返回空串表示可用；否则是给用户看的错误提示。
export function webProxySecretProblem(raw: string): string {
  const text: string = raw.trim();
  if (text.length === 0) {
    return str('px_web_err_secret_empty');
  }
  const lower: string = text.toLowerCase();
  if (lower.startsWith('ee')) {
    return str('px_web_err_secret_ee');
  }
  const bytes: Uint8Array = webProxySecretBytes(text);
  if (bytes.length === 0) {
    return str('px_web_err_secret_format');
  }
  if (!(bytes.length === 16 || (bytes.length === 17 && bytes[0] === 0xdd))) {
    return str('px_web_err_secret_len');
  }
  return '';
}

export function normalizeWebProxyHost(raw: string): string {
  let host: string = raw.trim().toLowerCase();
  if (host.startsWith('https://')) {
    host = host.substring(8);
  } else if (host.startsWith('http://')) {
    host = host.substring(7);
  }
  const slash: number = host.indexOf('/');
  if (slash >= 0) {
    host = host.substring(0, slash);
  }
  while (host.endsWith('/')) {
    host = host.substring(0, host.length - 1);
  }
  return host;
}

// BASE_PATH.md:51-59：部署路径是一个或多个 '/' 分隔段，每段以字母/数字开头，
// 其余只允许 [A-Za-z0-9_-]，总长 ≤128，存储时不留首尾斜杠。这里只做规范化，
// 合法性交给 webProxyPathProblem()，避免把非法值悄悄改成另一个部署路径。
export function normalizeWebProxyPath(raw: string): string {
  let path: string = raw.trim();
  while (path.startsWith('/')) {
    path = path.substring(1);
  }
  while (path.endsWith('/')) {
    path = path.substring(0, path.length - 1);
  }
  return path;
}

export function webProxyPathProblem(raw: string): string {
  const path: string = normalizeWebProxyPath(raw);
  if (path.length === 0) {
    return '';
  }
  if (path.length > 128) {
    return str('px_web_err_path_len');
  }
  const segments: string[] = path.split('/');
  for (let i = 0; i < segments.length; i++) {
    const seg: string = segments[i];
    if (seg.length === 0) {
      return str('px_web_err_path_empty_seg');
    }
    for (let j = 0; j < seg.length; j++) {
      const ch: string = seg.charAt(j);
      const isDigit: boolean = ch >= '0' && ch <= '9';
      const isUpper: boolean = ch >= 'A' && ch <= 'Z';
      const isLower: boolean = ch >= 'a' && ch <= 'z';
      const isExtra: boolean = ch === '_' || ch === '-';
      if (!(isDigit || isUpper || isLower || isExtra)) {
        return str('px_web_err_path_chars');
      }
      if (j === 0 && isExtra) {
        return str('px_web_err_path_start');
      }
    }
  }
  return '';
}

export function webProxyConfigProblem(cfg: WebProxyConfig): string {
  const host: string = normalizeWebProxyHost(cfg.host);
  if (host.length === 0) {
    return str('px_web_err_host_empty');
  }
  if (host.indexOf(' ') >= 0) {
    return str('px_web_err_host_space');
  }
  if (host.indexOf('?') >= 0 || host.indexOf('#') >= 0) {
    return str('px_web_err_host_query');
  }
  // 密钥被误填进域名框：32/34 位纯 hex（dd 前缀的 tproxy secret）明显不是域名。
  // 真机上出现过卡片标题显示一串 hex、连不上的问题，保存前就拦下来。
  if (host.length >= 32 && host.length <= 34 && host.indexOf('.') < 0 && isHexText(host)) {
    return str('px_web_err_host_is_secret');
  }
  const pathProblem: string = webProxyPathProblem(cfg.path);
  if (pathProblem.length > 0) {
    return pathProblem;
  }
  const secret: string = webProxySecretProblem(cfg.secret);
  if (secret.length > 0) {
    return secret;
  }
  return '';
}

// 用户习惯把整条分享链接粘进表单（tg://webproxy?server=…&secret=… 或
// https://t.me/webproxy?server=…&secret=…）。这里拆成三个字段；返回 null 表示
// 「这只是一段普通文本」，调用方按原样处理，避免把正常输入的域名当链接。
export function parseWebProxyLink(raw: string): WebProxyLinkInfo | null {
  const text: string = raw.trim();
  if (text.length === 0) {
    return null;
  }
  const lower: string = text.toLowerCase();
  if (lower.indexOf('webproxy?') < 0 && lower.indexOf('server=') < 0) {
    return null;
  }
  const qmark: number = text.indexOf('?');
  if (qmark < 0) {
    return null;
  }
  let query: string = text.substring(qmark + 1);
  const hash: number = query.indexOf('#');
  if (hash >= 0) {
    query = query.substring(0, hash);
  }
  let server: string = '';
  let secret: string = '';
  let path: string = '';
  const pairs: string[] = query.split('&');
  for (let i = 0; i < pairs.length; i++) {
    const pair: string = pairs[i];
    const eq: number = pair.indexOf('=');
    if (eq <= 0) {
      continue;
    }
    const key: string = pair.substring(0, eq).toLowerCase();
    let value: string = pair.substring(eq + 1);
    try {
      value = decodeURIComponent(value);
    } catch (_err) {
      continue;
    }
    if (key === 'server' || key === 'host') {
      server = value.trim();
    } else if (key === 'secret') {
      secret = value.trim();
    } else if (key === 'path') {
      path = value.trim();
    }
  }
  if (server.length === 0) {
    return null;
  }
  // server 里可能带协议头、端口或部署路径：https://host:8443/a/b、host:443、host/a/b。
  let serverNoScheme: string = server;
  const serverLower: string = server.toLowerCase();
  if (serverLower.startsWith('https://')) {
    serverNoScheme = server.substring(8);
  } else if (serverLower.startsWith('http://')) {
    serverNoScheme = server.substring(7);
  }
  let host: string = normalizeWebProxyHost(serverNoScheme);
  const slash: number = serverNoScheme.indexOf('/');
  if (path.length === 0 && slash >= 0) {
    path = serverNoScheme.substring(slash + 1).trim();
  }
  path = normalizeWebProxyPath(path);
  // 仅剥离 HTTPS 默认端口 :443（与 WebView location.origin 及 HMAC 上下文对齐），
  // 保留自定义端口（如 :8443）。
  const colon: number = host.lastIndexOf(':');
  if (colon > 0 && host.indexOf(']') < 0) {
    const tail: string = host.substring(colon + 1);
    if (tail === '443') {
      host = host.substring(0, colon);
    }
  }
  if (host.length === 0) {
    return null;
  }
  return { host: host, path: path, secret: secret };
}
