// Strict SAN matching: no CN fallback, partial wildcards or multi-label wildcards.
export function proxyDnsNameMatches(host: string, name: string): boolean {
  const wanted = host.toLowerCase().replace(/\.$/, '');
  const offered = name.toLowerCase().replace(/\.$/, '');
  if (!/^[a-z0-9.-]+$/.test(wanted) || !/^(\*\.)?[a-z0-9.-]+$/.test(offered)) { return false; }
  if (wanted === offered) { return true; }
  const parts = wanted.split('.');
  return offered.startsWith('*.') && parts.length >= 3 && parts[0] !== '' &&
    !parts[0].startsWith('xn--') && parts.slice(1).join('.') === offered.slice(2);
}

export function proxyIpBytes(host: string): Uint8Array | undefined {
  if (/^\d+\.\d+\.\d+\.\d+$/.test(host)) {
    const parts = host.split('.');
    if (parts.some((p: string): boolean => Number(p) > 255 || (p.length > 1 && p[0] === '0'))) { return undefined; }
    return new Uint8Array(parts.map((p: string): number => Number(p)));
  }
  if (host.indexOf(':') < 0 || host.indexOf('%') >= 0) { return undefined; }
  let normalized = host;
  if (host.indexOf('.') >= 0) {
    const at = host.lastIndexOf(':');
    const v4 = proxyIpBytes(host.slice(at + 1));
    if (v4 === undefined || v4.length !== 4) { return undefined; }
    normalized = host.slice(0, at + 1) + ((v4[0] << 8) | v4[1]).toString(16) + ':' +
      ((v4[2] << 8) | v4[3]).toString(16);
  }
  const halves = normalized.split('::');
  if (halves.length > 2) { return undefined; }
  const left = halves[0] === '' ? [] : halves[0].split(':');
  const right = halves.length === 1 || halves[1] === '' ? [] : halves[1].split(':');
  const count = left.length + right.length;
  if ((halves.length === 1 && count !== 8) || (halves.length === 2 && count >= 8)) { return undefined; }
  const groups: string[] = left.slice();
  if (halves.length === 2) { for (let i = count; i < 8; i++) { groups.push('0'); } }
  groups.push(...right);
  if (groups.some((g: string): boolean => !/^[0-9a-fA-F]{1,4}$/.test(g))) { return undefined; }
  const result = new Uint8Array(16);
  for (let i = 0; i < groups.length; i++) {
    const value = parseInt(groups[i], 16); result[2 * i] = value >> 8; result[2 * i + 1] = value & 255;
  }
  return result;
}

// GeneralName's context tag and DER length are required by X509Cert.match (API 12+).
export function proxyGeneralNameDer(tag: number, value: Uint8Array): Uint8Array {
  if (value.length > 253) { throw new Error('proxy certificate name too long'); }
  const prefix = value.length < 128 ? [tag, value.length] : [tag, 0x81, value.length];
  const result = new Uint8Array(prefix.length + value.length);
  result.set(prefix); result.set(value, prefix.length); return result;
}
