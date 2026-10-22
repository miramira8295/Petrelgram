import { proxyIpBytes } from './proxyCertificateName';

export interface SocksStep {
  writes: ArrayBuffer[];
  ready: boolean;
  rest: ArrayBuffer;
}

export interface ProxyTarget { host: string; port: number; }

export function proxyTarget(authority: string): ProxyTarget {
  const at = authority.lastIndexOf(':');
  let host = authority.slice(0, at);
  if (host.startsWith('[') && host.endsWith(']')) { host = host.slice(1, -1); }
  return { host: host, port: Number(authority.slice(at + 1)) };
}

export class SocksProxyHandshake {
  private phase: string = 'method';
  private bytes: number[] = [];
  private user: Uint8Array;
  private password: Uint8Array;
  private target: string;
  private auth: boolean;

  constructor(authority: string, user: Uint8Array, password: Uint8Array) {
    if (user.length > 255 || password.length > 255) { throw new Error('proxy credentials too long'); }
    this.user = user; this.password = password; this.target = authority;
    this.auth = user.length > 0 || password.length > 0;
  }

  greeting(): ArrayBuffer { return new Uint8Array([5, 1, this.auth ? 2 : 0]).buffer as ArrayBuffer; }

  private connectRequest(): ArrayBuffer {
    const target = proxyTarget(this.target);
    const ip = proxyIpBytes(target.host);
    const output: number[] = [5, 1, 0];
    if (ip !== undefined) { output.push(ip.length === 4 ? 1 : 4); output.push(...Array.from(ip)); }
    else {
      if (target.host.length > 253) { throw new Error('proxy hostname too long'); }
      output.push(3, target.host.length);
      for (let i = 0; i < target.host.length; i++) { output.push(target.host.charCodeAt(i)); }
    }
    output.push(target.port >> 8, target.port & 255);
    return new Uint8Array(output).buffer as ArrayBuffer;
  }

  push(data: ArrayBuffer): SocksStep {
    const input = new Uint8Array(data);
    const writes: ArrayBuffer[] = [];
    for (let i = 0; i < input.length; i++) {
      if (this.phase === 'ready') { return { writes: writes, ready: true, rest: data.slice(i) }; }
      this.bytes.push(input[i]);
      if (this.bytes.length > 262) { throw new Error('proxy SOCKS reply too large'); }
      if (this.phase === 'method' && this.bytes.length === 2) {
        if (this.bytes[0] !== 5 || this.bytes[1] !== (this.auth ? 2 : 0)) { throw new Error('proxy SOCKS auth rejected'); }
        this.bytes = [];
        if (this.auth) {
          writes.push(new Uint8Array([1, this.user.length, ...Array.from(this.user),
            this.password.length, ...Array.from(this.password)]).buffer as ArrayBuffer);
          this.phase = 'auth';
        } else { writes.push(this.connectRequest()); this.phase = 'reply'; }
      } else if (this.phase === 'auth' && this.bytes.length === 2) {
        if (this.bytes[0] !== 1 || this.bytes[1] !== 0) { throw new Error('proxy SOCKS credentials rejected'); }
        this.bytes = []; this.phase = 'reply'; writes.push(this.connectRequest());
      } else if (this.phase === 'reply' && this.bytes.length >= 4) {
        if (this.bytes[0] !== 5 || this.bytes[1] !== 0 || this.bytes[2] !== 0) { throw new Error('proxy SOCKS CONNECT rejected'); }
        const type = this.bytes[3];
        if (type !== 1 && type !== 3 && type !== 4) { throw new Error('proxy SOCKS address invalid'); }
        const expected = type === 1 ? 10 : (type === 4 ? 22 : (this.bytes.length >= 5 ? 7 + this.bytes[4] : 0));
        if (expected > 0 && this.bytes.length === expected) { this.phase = 'ready'; this.bytes = []; }
      }
    }
    return { writes: writes, ready: this.phase === 'ready', rest: new ArrayBuffer(0) };
  }
}
