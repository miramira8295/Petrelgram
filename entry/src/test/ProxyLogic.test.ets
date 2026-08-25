import { describe, it, expect } from '@ohos/hypium';
import { TdObject } from '../main/ets/tdkit/TdTypes';
import {
  PROXY_HTTP, PROXY_MTPROTO, PROXY_SOCKS5, ProxyEntry,
  proxyEntryFromAddedObject, proxyObjectOf
} from '../main/ets/store/ProxyApi';
import {
  parseProxyPort, proxyActionErrorText, proxyConnectionText,
  proxyFormError, sameProxyConfiguration, enabledProxyConnected, isIpLiteral
} from '../main/ets/util/proxyLogic';

function entry(type: string): ProxyEntry {
  return {
    id: 7, server: 'proxy.example.com', port: 443, type: type,
    username: 'user', password: 'pass', secret: 'secret', httpOnly: false,
    lastUsedDate: 100, isEnabled: false
  };
}

export default function proxyLogicTest() {
  describe('ProxyLogic', (): void => {
    it('accepts_only_strict_valid_ports', 0, (): void => {
      expect(parseProxyPort('443')).assertEqual(443);
      expect(parseProxyPort(' 1080 ')).assertEqual(1080);
      expect(parseProxyPort('80abc')).assertEqual(0);
      expect(parseProxyPort('0')).assertEqual(0);
      expect(parseProxyPort('65536')).assertEqual(0);
    });

    it('validates_required_proxy_fields', 0, (): void => {
      expect(proxyFormError('', '443', PROXY_SOCKS5, '')).assertEqual('proxy_server_required');
      expect(proxyFormError('host', 'abc', PROXY_SOCKS5, ''))
        .assertEqual('proxy_port_invalid');
      expect(proxyFormError('host', '443', PROXY_MTPROTO, ''))
        .assertEqual('proxy_secret_required');
      expect(proxyFormError('host', '443', PROXY_MTPROTO, 'secret')).assertEqual('');
    });

    it('preserves_http_only_and_added_proxy_metadata', 0, (): void => {
      const httpType: TdObject = {
        '@type': PROXY_HTTP, 'username': 'u', 'password': 'p', 'http_only': true
      };
      const proxy: TdObject = {
        '@type': 'proxy', 'server': 'http.example.com', 'port': 8080, 'type': httpType
      };
      const added: TdObject = {
        '@type': 'addedProxy', 'id': 12, 'last_used_date': 99,
        'is_enabled': true, 'proxy': proxy
      };
      const parsed = proxyEntryFromAddedObject(added);
      expect(parsed.id).assertEqual(12);
      expect(parsed.httpOnly).assertTrue();
      expect(parsed.lastUsedDate).assertEqual(99);
      expect(parsed.isEnabled).assertTrue();

      const encoded = proxyObjectOf(parsed);
      const encodedType = encoded['type'] as TdObject;
      expect(encodedType['http_only'] as boolean).assertTrue();
      expect(encodedType['username'] as string).assertEqual('u');
    });

    it('detects_duplicates_without_mixing_proxy_types', 0, (): void => {
      const first = entry(PROXY_SOCKS5);
      const duplicate = entry(PROXY_SOCKS5);
      duplicate.id = 8;
      duplicate.server = 'PROXY.EXAMPLE.COM';
      expect(sameProxyConfiguration(first, duplicate)).assertTrue();
      duplicate.type = PROXY_HTTP;
      expect(sameProxyConfiguration(first, duplicate)).assertFalse();
    });

    it('maps_connection_and_action_states', 0, (): void => {
      expect(proxyConnectionText('connectionStateReady', true)).assertEqual('proxy_state_connected');
      expect(proxyConnectionText('connectionStateReady', false)).assertEqual('proxy_state_direct');
      expect(proxyConnectionText('connectionStateConnectingToProxy', true))
        .assertEqual('proxy_state_connecting_proxy');
      expect(proxyActionErrorText('request timeout', '启用代理'))
        .assertEqual('proxy_error_timeout(启用代理)');
    });
    // issue #31：pingProxy 对某些代理报错但实际可用；启用中的代理以连接状态为准。
    it('启用中的代理连上了就算可用，ping 报错不算数', 0, (): void => {
      expect(enabledProxyConnected(true, 'connectionStateReady')).assertTrue();
      expect(enabledProxyConnected(true, 'connectionStateUpdating')).assertTrue();
    });
    it('没连上、或不是启用中的那个，都不算', 0, (): void => {
      expect(enabledProxyConnected(true, 'connectionStateConnectingToProxy')).assertFalse();
      expect(enabledProxyConnected(true, 'connectionStateWaitingForNetwork')).assertFalse();
      expect(enabledProxyConnected(true, '')).assertFalse();
      expect(enabledProxyConnected(false, 'connectionStateReady')).assertFalse();
    });
    it('IP 字面量不走 DNS', 0, (): void => {
      expect(isIpLiteral('1.2.3.4')).assertTrue();
      expect(isIpLiteral('2001:db8::1')).assertTrue();
      expect(isIpLiteral('proxy.example.com')).assertFalse();
      expect(isIpLiteral('1.2.3')).assertFalse();
    });
  });
}
