import { describe, expect, it } from '@ohos/hypium';
import {
  decodeBase64UrlBytes,
  normalizeWebProxyHost,
  normalizeWebProxyPath,
  parseWebProxyLink,
  webProxyConfigProblem,
  webProxyPathProblem,
  webProxyReachTarget,
  webProxySecretBytes,
  webProxySecretProblem
} from '../main/ets/util/webProxyConfig';

export default function webProxyConfigTest(): void {
  describe('WebProxyConfig', (): void => {
    it('decodes 16-byte hex and dd-prefixed 17-byte secrets', 0, (): void => {
      const hex16 = '0123456789abcdef0123456789abcdef';
      const bytes16 = webProxySecretBytes(hex16);
      expect(bytes16.length).assertEqual(16);
      expect(bytes16[0]).assertEqual(0x01);
      expect(bytes16[15]).assertEqual(0xef);
      expect(webProxySecretProblem(hex16)).assertEqual('');

      const dd17 = 'dd' + hex16;
      const bytes17 = webProxySecretBytes(dd17);
      expect(bytes17.length).assertEqual(17);
      expect(bytes17[0]).assertEqual(0xdd);
      expect(webProxySecretProblem(dd17)).assertEqual('');
    });

    it('strips legacy 0x70 prefix from 17-byte secrets', 0, (): void => {
      const legacy = '70' + 'aabbccddeeff00112233445566778899';
      const bytes = webProxySecretBytes(legacy);
      expect(bytes.length).assertEqual(16);
      expect(bytes[0]).assertEqual(0xaa);
      expect(webProxySecretProblem(legacy)).assertEqual('');
    });

    it('decodes base64url secrets containing multiple dashes and underscores', 0, (): void => {
      // 16 bytes: 0xfb, 0xff, 0xfe, 0xfb, 0xff, 0xfe, ... => base64url has multiple '-' and '_'
      const b64url = '-__--__--__--__--__--w';
      const decoded = decodeBase64UrlBytes(b64url);
      expect(decoded !== null).assertTrue();
      expect(decoded!.length).assertEqual(16);
      expect(decoded![0]).assertEqual(0xfb);
      expect(decoded![1]).assertEqual(0xff);
      expect(decoded![2]).assertEqual(0xfe);
      expect(webProxySecretBytes(b64url).length).assertEqual(16);
      expect(webProxySecretProblem(b64url)).assertEqual('');
    });

    it('rejects empty, ee fake-TLS, malformed, and wrong-length secrets', 0, (): void => {
      expect(webProxySecretProblem('')).assertEqual('px_web_err_secret_empty');
      expect(webProxySecretProblem('ee0123456789abcdef0123456789abcdef6578616d706c65')).assertEqual('px_web_err_secret_ee');
      expect(webProxySecretProblem('not valid!@#')).assertEqual('px_web_err_secret_format');
      expect(webProxySecretProblem('01234567')).assertEqual('px_web_err_secret_len');
      expect(decodeBase64UrlBytes('a')).assertNull();
      expect(decodeBase64UrlBytes('abc===')).assertNull();
    });

    it('normalizes host and path and rejects invalid deployment paths', 0, (): void => {
      expect(normalizeWebProxyHost('  HTTPS://Proxy.Example.COM:8443/sub/path ')).assertEqual('proxy.example.com:8443');
      expect(normalizeWebProxyPath('  ///a/b_1-c///  ')).assertEqual('a/b_1-c');
      expect(webProxyPathProblem('/t7k2xw/v1/')).assertEqual('');
      expect(webProxyPathProblem('')).assertEqual('');
      expect(webProxyPathProblem('a//b')).assertEqual('px_web_err_path_empty_seg');
      expect(webProxyPathProblem('-bad')).assertEqual('px_web_err_path_start');
      expect(webProxyPathProblem('a/b?c=1')).assertEqual('px_web_err_path_chars');
      expect(webProxyPathProblem('a'.repeat(129))).assertEqual('px_web_err_path_len');
    });

    it('rejects secret accidentally pasted into host field', 0, (): void => {
      const secret = 'dd0123456789abcdef0123456789abcdef';
      expect(webProxyConfigProblem({
        host: secret,
        path: '',
        secret: secret,
        allowInvalidCert: false
      })).assertEqual('px_web_err_host_is_secret');
    });

    it('parses tg://webproxy and t.me/webproxy links while preserving custom ports', 0, (): void => {
      const secret = 'dd0123456789abcdef0123456789abcdef';
      const customPort = parseWebProxyLink(`tg://webproxy?server=proxy.example.com:8443&path=/edge/v1/&secret=${secret}`);
      expect(customPort !== null).assertTrue();
      expect(customPort!.host).assertEqual('proxy.example.com:8443');
      expect(customPort!.path).assertEqual('edge/v1');
      expect(customPort!.secret).assertEqual(secret);

      const defaultPort = parseWebProxyLink(`https://t.me/webproxy?server=proxy.example.com:443&secret=${secret}`);
      expect(defaultPort !== null).assertTrue();
      expect(defaultPort!.host).assertEqual('proxy.example.com');
      expect(defaultPort!.path).assertEqual('');

      const withSchemeAndPath = parseWebProxyLink(`https://t.me/webproxy?server=${encodeURIComponent('https://proxy.example.com:8443/relay/a')}&secret=${secret}`);
      expect(withSchemeAndPath !== null).assertTrue();
      expect(withSchemeAndPath!.host).assertEqual('proxy.example.com:8443');
      expect(withSchemeAndPath!.path).assertEqual('relay/a');
    });

    it('returns null for ordinary hosts or non-webproxy telegram links', 0, (): void => {
      expect(parseWebProxyLink('proxy.example.com')).assertNull();
      expect(parseWebProxyLink('https://t.me/webproxy_channel')).assertNull();
      expect(parseWebProxyLink('')).assertNull();
    });

    it('resolves remote reach target for WEB proxy with default and custom ports', 0, (): void => {
      const def = webProxyReachTarget('proxy.example.com');
      expect(def !== null).assertTrue();
      expect(def!.host).assertEqual('proxy.example.com');
      expect(def!.port).assertEqual(443);

      const custom = webProxyReachTarget('https://proxy.example.com:8443/sub');
      expect(custom !== null).assertTrue();
      expect(custom!.host).assertEqual('proxy.example.com');
      expect(custom!.port).assertEqual(8443);

      const ipv6 = webProxyReachTarget('[2001:db8::1]:9443');
      expect(ipv6 !== null).assertTrue();
      expect(ipv6!.host).assertEqual('2001:db8::1');
      expect(ipv6!.port).assertEqual(9443);

      expect(webProxyReachTarget('')).assertNull();
      expect(webProxyReachTarget('proxy.example.com:99999')).assertNull();
    });
  });
}
