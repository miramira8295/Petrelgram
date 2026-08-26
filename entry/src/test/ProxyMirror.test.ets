import { describe, expect, it } from '@ohos/hypium';
import { ProxyEntry, PROXY_MTPROTO, PROXY_SOCKS5 } from '../main/ets/store/ProxyApi';
import {
  missingFromAccount, parseProxyMirror, parseSyncOff, proxyKeyOf, serializeProxyMirror,
  serializeSyncOff, syncEnabledFor, syncableOf, toggledSyncOff
} from '../main/ets/util/proxyMirror';

function entry(server: string, port: number, type: string = PROXY_SOCKS5): ProxyEntry {
  return {
    id: 7, server: server, port: port, type: type, username: 'u', password: 'p',
    secret: '', httpOnly: false, lastUsedDate: 123, isEnabled: true
  };
}

export default function proxyMirrorTest() {
  describe('proxyMirror', () => {
    it('往返：凭据保留，id/启用态不带走', 0, (): void => {
      const back = parseProxyMirror(serializeProxyMirror([entry('example.test', 1080)]));
      expect(back.length).assertEqual(1);
      expect(back[0].server).assertEqual('example.test');
      expect(back[0].port).assertEqual(1080);
      expect(back[0].username).assertEqual('u');
      expect(back[0].password).assertEqual('p');
      expect(back[0].id).assertEqual(0);
      expect(back[0].isEnabled).assertFalse();
    });
    it('空列表与坏数据都得到空', 0, (): void => {
      expect(serializeProxyMirror([])).assertEqual('');
      expect(parseProxyMirror('').length).assertEqual(0);
      expect(parseProxyMirror('{oops').length).assertEqual(0);
      expect(parseProxyMirror('{"a":1}').length).assertEqual(0);
      expect(parseProxyMirror('[{"server":"","port":1}]').length).assertEqual(0);
      expect(parseProxyMirror('[{"server":"a.test","port":0}]').length).assertEqual(0);
    });
    it('判重看协议+地址+端口，不看 id', 0, (): void => {
      expect(proxyKeyOf(entry('a.test', 1080))).assertEqual(proxyKeyOf(entry('a.test', 1080)));
      expect(proxyKeyOf(entry('a.test', 1080)) === proxyKeyOf(entry('a.test', 1081))).assertFalse();
      expect(proxyKeyOf(entry('a.test', 1080)) ===
        proxyKeyOf(entry('a.test', 1080, PROXY_MTPROTO))).assertFalse();
    });
    it('默认允许同步，关掉后进排除表，再点回来', 0, (): void => {
      const a = entry('a.test', 1080);
      expect(syncEnabledFor(a, [])).assertTrue();
      const off = toggledSyncOff(a, []);
      expect(off.length).assertEqual(1);
      expect(syncEnabledFor(a, off)).assertFalse();
      expect(toggledSyncOff(a, off).length).assertEqual(0);
      expect(parseSyncOff(serializeSyncOff(off)).join(',')).assertEqual(off.join(','));
      expect(parseSyncOff('').length).assertEqual(0);
      expect(parseSyncOff('nope').length).assertEqual(0);
    });
    it('镜像只收允许同步的', 0, (): void => {
      const a = entry('a.test', 1080);
      const b = entry('b.test', 443);
      const kept = syncableOf([a, b], toggledSyncOff(b, []));
      expect(kept.length).assertEqual(1);
      expect(kept[0].server).assertEqual('a.test');
    });
    it('只补当前账号缺的那些，镜像内部也去重', 0, (): void => {
      const mirror = [entry('a.test', 1080), entry('b.test', 443), entry('a.test', 1080)];
      const missing = missingFromAccount(mirror, [entry('a.test', 1080)]);
      expect(missing.length).assertEqual(1);
      expect(missing[0].server).assertEqual('b.test');
      expect(missingFromAccount(mirror, []).length).assertEqual(2);
    });
  });
}
