import { describe, it, expect } from '@ohos/hypium';
import {
  BearerIds, NET_KIND_CELLULAR, NET_KIND_NONE, NET_KIND_OTHER, NET_KIND_VPN, NET_KIND_WIFI,
  bearerKindOf, resolveThroughVpn
} from '../main/ets/util/netBearer';

// 与 connection.NetBearType 同值：CELLULAR=0, WIFI=1, VPN=4（BLUETOOTH=2, ETHERNET=3）
const IDS: BearerIds = { wifi: 1, cellular: 0, vpn: 4 };

export default function netBearerTest() {
  describe('netBearer', () => {
    it('recognises_wifi_and_cellular', 0, () => {
      expect(bearerKindOf([1], IDS)).assertEqual(NET_KIND_WIFI);
      expect(bearerKindOf([0], IDS)).assertEqual(NET_KIND_CELLULAR);
      // 同时挂着时 Wi-Fi 优先
      expect(bearerKindOf([0, 1], IDS)).assertEqual(NET_KIND_WIFI);
    });

    // 这就是真机上那 30 次 network=other 的来源：默认网络的承载是 VPN。
    it('vpn_is_reported_as_vpn_not_other', 0, () => {
      expect(bearerKindOf([4], IDS)).assertEqual(NET_KIND_VPN);
    });

    it('ethernet_or_bluetooth_is_other_and_empty_is_none', 0, () => {
      expect(bearerKindOf([3], IDS)).assertEqual(NET_KIND_OTHER);
      expect(bearerKindOf([], IDS)).assertEqual(NET_KIND_NONE);
    });

    it('sees_through_vpn_to_the_physical_bearer', 0, () => {
      expect(resolveThroughVpn(NET_KIND_VPN, [NET_KIND_WIFI])).assertEqual(NET_KIND_WIFI);
      expect(resolveThroughVpn(NET_KIND_VPN, [NET_KIND_CELLULAR])).assertEqual(NET_KIND_CELLULAR);
      expect(resolveThroughVpn(NET_KIND_VPN, [NET_KIND_CELLULAR, NET_KIND_WIFI])).assertEqual(NET_KIND_WIFI);
    });

    it('vpn_with_nothing_underneath_stays_vpn', 0, () => {
      expect(resolveThroughVpn(NET_KIND_VPN, [])).assertEqual(NET_KIND_VPN);
      expect(resolveThroughVpn(NET_KIND_VPN, [NET_KIND_OTHER])).assertEqual(NET_KIND_VPN);
    });

    it('non_vpn_defaults_pass_through', 0, () => {
      expect(resolveThroughVpn(NET_KIND_WIFI, [NET_KIND_CELLULAR])).assertEqual(NET_KIND_WIFI);
      expect(resolveThroughVpn(NET_KIND_NONE, [NET_KIND_WIFI])).assertEqual(NET_KIND_NONE);
    });
  });
}
