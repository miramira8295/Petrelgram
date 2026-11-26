// WEB proxy 的 secret 与 bridge capability。
//
// 官方（tproxy-server/PROTOCOL.md）：
//   context = UTF8("tdesktop-web-proxy-bridge-v1\n" + H)
//   bridge  = base64url-no-padding(HMAC-SHA256(key = S, message = context))
// 其中 H 是 relay 主机名、S 是 MTProxy secret 的原始字节（**包含 dd 前缀**，
// 官方测试向量对 16 字节与 dd 前缀两种情况给了两个不同的 capability）。
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { util } from '@kit.ArkTS';

export const WEB_PROXY_BRIDGE_CONTEXT: string = 'tdesktop-web-proxy-bridge-v1\n';

function hexDigit(code: number): number {
  if (code >= 48 && code <= 57) { return code - 48; }
  if (code >= 97 && code <= 102) { return code - 87; }
  if (code >= 65 && code <= 70) { return code - 55; }
  return -1;
}

export function isHexText(text: string): boolean {
  if (text.length === 0 || text.length % 2 !== 0) {
    return false;
  }
  for (let i = 0; i < text.length; i++) {
    if (hexDigit(text.charCodeAt(i)) < 0) {
      return false;
    }
  }
  return true;
}

export function bytesOfHex(text: string): Uint8Array {
  const count: number = Math.floor(text.length / 2);
  const out: Uint8Array = new Uint8Array(count);
  for (let i = 0; i < count; i++) {
    const high: number = hexDigit(text.charCodeAt(i * 2));
    const low: number = hexDigit(text.charCodeAt(i * 2 + 1));
    out[i] = ((high < 0 ? 0 : high) << 4) | (low < 0 ? 0 : low);
  }
  return out;
}

export function hexOfBytes(bytes: Uint8Array): string {
  const digits: string = '0123456789abcdef';
  let out: string = '';
  for (let i = 0; i < bytes.length; i++) {
    out += digits[(bytes[i] ?? 0) >> 4];
    out += digits[(bytes[i] ?? 0) & 0x0f];
  }
  return out;
}

// 合法 secret：16 字节；17 字节且以 0xdd 开头；21+ 字节且以 0xee 开头。
// （官方 ANDROID.md：relay 风格只接受 16/dd，ee 被 Android/desktop 明确拒绝，
//  这里也拒 ee，但保留识别能力用于提示。）
export function secretBytesOf(text: string): Uint8Array | null {
  const clean: string = text.trim().toLowerCase();
  if (!isHexText(clean)) {
    return null;
  }
  const bytes: Uint8Array = bytesOfHex(clean);
  if (bytes.length === 16) {
    return bytes;
  }
  if (bytes.length === 17 && (bytes[0] ?? 0) === 0xdd) {
    return bytes;
  }
  if (bytes.length >= 21 && (bytes[0] ?? 0) === 0xee) {
    return bytes;
  }
  return null;
}

export function secretProblem(text: string): string {
  const clean: string = text.trim().toLowerCase();
  if (clean.length === 0) {
    return 'secret 不能为空';
  }
  if (!isHexText(clean)) {
    return 'secret 必须是十六进制（0-9 a-f）';
  }
  const bytes: Uint8Array = bytesOfHex(clean);
  if (bytes.length === 16) {
    return '';
  }
  if (bytes.length === 17 && (bytes[0] ?? 0) === 0xdd) {
    return '';
  }
  if (bytes.length >= 21 && (bytes[0] ?? 0) === 0xee) {
    return 'WEB proxy 不支持 ee 开头的 secret（官方 Android/desktop 同样拒绝）';
  }
  return `secret 长度不对：${bytes.length} 字节（应为 16 字节，或 dd 开头的 17 字节）`;
}

export function base64UrlOf(bytes: Uint8Array): string {
  const standard: string = new util.Base64Helper().encodeToStringSync(bytes);
  return standard.split('+').join('-').split('/').join('_').split('=').join('');
}

export function base64UrlDecode(text: string): Uint8Array | null {
  const standard: string = text.trim().split('-').join('+').split('_').join('/');
  const pad: number = (4 - (standard.length % 4)) % 4;
  let padded: string = standard;
  for (let i = 0; i < pad; i++) {
    padded += '=';
  }
  try {
    const bytes: Uint8Array = new util.Base64Helper().decodeSync(padded);
    return bytes.length > 0 ? bytes : null;
  } catch (e) {
    return null;
  }
}

// bridge capability：relay 用来认「这台机器的这份 secret 被授权过」。
export async function bridgeCapabilityOf(host: string, secret: Uint8Array): Promise<string> {
  const mac: cryptoFramework.Mac = cryptoFramework.createMac('SHA256');
  const keyBlob: cryptoFramework.DataBlob = { data: secret };
  await mac.init(keyBlob);
  const context: string = WEB_PROXY_BRIDGE_CONTEXT + host.trim().toLowerCase();
  const contextBytes: Uint8Array = new util.TextEncoder().encodeInto(context);
  const messageBlob: cryptoFramework.DataBlob = { data: contextBytes };
  await mac.update(messageBlob);
  const digest: cryptoFramework.DataBlob = await mac.doFinal();
  return base64UrlOf(digest.data);
}
