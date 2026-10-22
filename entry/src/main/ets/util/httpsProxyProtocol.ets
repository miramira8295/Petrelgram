// Protocol parsing is independent of sockets so fragmented/coalesced reads are testable.
export const PROXY_HTTPS: string = 'proxyTypeHttps';
export const PROXY_DIRECT: string = 'direct';
export const ACTIVE_ROUTE_KEY: string = '00000000-0000-4000-8000-000000000000';
export const HTTPS_PROXY_MARKER: string = 'petrel_tls_';
export const PROXY_HEADER_LIMIT: number = 16384;

export interface HttpsProxyConfig {
  type?: string;
  httpOnly?: boolean;
  server: string;
  port: number;
  username: string;
  password: string;
}

export interface HttpsProxyRecord extends HttpsProxyConfig {
  key: string;
  token: string;
  selectedId?: number;
}

export interface ProxyHeader {
  text: string;
  rest: ArrayBuffer;
}

export class ProxyHeaderReader {
  private bytes: number[] = [];
  push(data: ArrayBuffer): ProxyHeader | undefined {
    const input = new Uint8Array(data);
    for (let i = 0; i < input.length; i++) {
      const b = input[i];
      this.bytes.push(b);
      if (this.bytes.length > PROXY_HEADER_LIMIT) { throw new Error('proxy header too large'); }
      const n = this.bytes.length;
      if (n >= 4 && this.bytes[n - 4] === 13 && this.bytes[n - 3] === 10 &&
        this.bytes[n - 2] === 13 && b === 10) {
        const text = this.bytes.map((value: number): string => String.fromCharCode(value)).join('');
        this.bytes = [];
        return { text: text, rest: data.slice(i + 1) };
      }
    }
    return undefined;
  }
}

export interface ProxyConnectRequest {
  authority: string;
  authorization: string;
}

export function parseProxyConnect(text: string): ProxyConnectRequest {
  const lines = text.split('\r\n');
  const match = /^CONNECT (\[[0-9a-fA-F:.]+\]|[A-Za-z0-9.-]+):([0-9]{1,5}) HTTP\/1\.[01]$/.exec(lines[0]);
  if (match === null || Number(match[2]) < 1 || Number(match[2]) > 65535) {
    throw new Error('invalid proxy CONNECT');
  }
  let authorization = '';
  for (let i = 1; i < lines.length; i++) {
    const at = lines[i].indexOf(':');
    if (at < 0) { continue; }
    const name = lines[i].slice(0, at).toLowerCase();
    if (name === 'proxy-authorization') {
      if (authorization !== '') { throw new Error('duplicate proxy authorization'); }
      authorization = lines[i].slice(at + 1).trim();
    }
    if (name === 'transfer-encoding' || name === 'content-length') {
      throw new Error('unexpected proxy request body');
    }
  }
  return { authority: `${match[1]}:${match[2]}`, authorization: authorization };
}

export function proxyConnectSucceeded(text: string): boolean {
  return /^HTTP\/1\.[01] 2[0-9][0-9](?: |\r\n)/.test(text);
}

export function proxyConnectHeader(authority: string, authorization: string): string {
  // authority came from parseProxyConnect; authorization is generated Base64, never user text.
  return `CONNECT ${authority} HTTP/1.1\r\nHost: ${authority}\r\n` +
    (authorization === '' ? '' : `Proxy-Authorization: ${authorization}\r\n`) + '\r\n';
}

export function validHttpsProxy(config: HttpsProxyConfig): boolean {
  return typeof config.server === 'string' && config.server.length > 0 && config.server.length <= 253 &&
    /^[A-Za-z0-9.:-]+$/.test(config.server) && Number.isInteger(config.port) &&
    config.port > 0 && config.port <= 65535 && typeof config.username === 'string' &&
    typeof config.password === 'string' && config.username.indexOf(':') < 0 &&
    config.username.length <= 1024 && config.password.length <= 4096;
}

export function relayProxyType(config: HttpsProxyConfig): string { return config.type ?? PROXY_HTTPS; }

export function usesProxyRelay(type: string): boolean {
  return type === PROXY_HTTPS || type === 'proxyTypeHttp' || type === 'proxyTypeSocks5' || type === PROXY_DIRECT;
}

export function validRelayProxy(config: HttpsProxyConfig): boolean {
  const type = relayProxyType(config);
  if (type === PROXY_DIRECT) { return config.server === '' && config.port === 0; }
  if (!usesProxyRelay(type) || (config.httpOnly === true && type !== 'proxyTypeHttp')) { return false; }
  // SOCKS credentials are length-prefixed, so ':' is legal (unlike HTTP Basic username).
  if (type === 'proxyTypeSocks5') {
    return validHttpsProxy({ server: config.server, port: config.port, username: '', password: config.password }) &&
      typeof config.username === 'string' && config.username.length <= 255 && config.password.length <= 255;
  }
  return validHttpsProxy(config);
}

export function proxyAsciiBytes(text: string): ArrayBuffer {
  return new Uint8Array(text.split('').map((c: string): number => c.charCodeAt(0))).buffer as ArrayBuffer;
}

export interface ProxyHttpPost {
  authorization: string;
  contentLength: number;
  lines: string[];
}

// TDLib's HTTP-only transport uses POST HTTP://dc:80/api with Content-Length.
export function parseProxyHttpPost(text: string): ProxyHttpPost {
  const lines = text.split('\r\n');
  if (!/^POST HTTP:\/\/(\[[0-9a-fA-F:.]+\]|[A-Za-z0-9.-]+):[0-9]{1,5}\/api HTTP\/1\.[01]$/i.test(lines[0])) {
    throw new Error('invalid proxy HTTP request');
  }
  let authorization = ''; let length = -1;
  const retained: string[] = [lines[0]];
  for (let i = 1; i < lines.length; i++) {
    if (lines[i] === '') { continue; }
    const at = lines[i].indexOf(':');
    if (at < 1 || /[\r\n]/.test(lines[i])) { throw new Error('invalid proxy HTTP header'); }
    const name = lines[i].slice(0, at).toLowerCase();
    if (!/^[a-z0-9!#$%&'*+.^_`|~-]+$/.test(name)) { throw new Error('invalid proxy HTTP header name'); }
    const value = lines[i].slice(at + 1).trim();
    if (name === 'proxy-authorization') {
      if (authorization !== '') { throw new Error('duplicate proxy authorization'); }
      authorization = value; continue;
    }
    if (name === 'transfer-encoding') { throw new Error('proxy chunked request unsupported'); }
    if (name === 'content-length') {
      if (length !== -1 || !/^\d+$/.test(value)) { throw new Error('invalid proxy content length'); }
      length = Number(value);
    }
    retained.push(lines[i]);
  }
  if (!Number.isSafeInteger(length) || length < 0 || length > 64 * 1024 * 1024) {
    throw new Error('invalid proxy content length');
  }
  return { authorization: authorization, contentLength: length, lines: retained };
}

export class ProxyHttpRequestRewriter {
  private header = new ProxyHeaderReader();
  private remaining: number = 0;
  private localAuth: string;
  private remoteAuth: string;
  constructor(localAuth: string, remoteAuth: string) { this.localAuth = localAuth; this.remoteAuth = remoteAuth; }
  push(data: ArrayBuffer): ArrayBuffer[] {
    const output: ArrayBuffer[] = [];
    let rest = data;
    while (rest.byteLength > 0) {
      if (this.remaining > 0) {
        const count = Math.min(this.remaining, rest.byteLength);
        output.push(rest.slice(0, count)); this.remaining -= count; rest = rest.slice(count);
      } else {
        const header = this.header.push(rest);
        if (header === undefined) { break; }
        const parsed = parseProxyHttpPost(header.text);
        if (parsed.authorization !== this.localAuth) { throw new Error('proxy local authentication rejected'); }
        if (this.remoteAuth !== '') { parsed.lines.push('Proxy-Authorization: ' + this.remoteAuth); }
        output.push(proxyAsciiBytes(parsed.lines.join('\r\n') + '\r\n\r\n'));
        this.remaining = parsed.contentLength;
        rest = header.rest;
      }
    }
    return output;
  }
}
