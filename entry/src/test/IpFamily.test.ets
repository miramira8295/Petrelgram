import { describe, it, expect } from '@ohos/hypium';
import {
  hasIpv4Among, isIpv6Literal, netFamilyOf, NET_FAMILY_IPV4, NET_FAMILY_IPV6,
  pickAddressIndex, shouldPreferIpv6, stripIpv6Brackets
} from '../main/ets/util/ipFamily';

export default function ipFamilyTest() {
  describe('IpFamily', () => {
    it('方括号被剥掉：socket 和 TDLib 要的都是裸地址', 0, () => {
      expect(stripIpv6Brackets('[2001:db8::1]')).assertEqual('2001:db8::1');
      expect(stripIpv6Brackets('  [::1]  ')).assertEqual('::1');
      expect(stripIpv6Brackets('2001:db8::1')).assertEqual('2001:db8::1');
      expect(stripIpv6Brackets('proxy.example.com')).assertEqual('proxy.example.com');
      expect(stripIpv6Brackets('  1.2.3.4 ')).assertEqual('1.2.3.4');
    });

    it('只剥成对的方括号，不动半边的', 0, () => {
      expect(stripIpv6Brackets('[2001:db8::1')).assertEqual('[2001:db8::1');
      expect(stripIpv6Brackets('2001:db8::1]')).assertEqual('2001:db8::1]');
      expect(stripIpv6Brackets('[]')).assertEqual('');
    });

    it('IPv6 字面量的判据是含冒号', 0, () => {
      expect(isIpv6Literal('2001:db8::1')).assertTrue();
      expect(isIpv6Literal('[2001:db8::1]')).assertTrue();
      expect(isIpv6Literal('::1')).assertTrue();
      expect(isIpv6Literal('fe80::1%eth0')).assertTrue();
      expect(isIpv6Literal('1.2.3.4')).assertFalse();
      expect(isIpv6Literal('proxy.example.com')).assertFalse();
      expect(isIpv6Literal('')).assertFalse();
    });

    // 这条是 issue #133 的直接修复点：文档规定 IPv6 必须显式写 2，
    // 漏了就按默认 1（IPv4）去连，永远连不上。
    it('family：IPv6 必须是 2，其余是 1', 0, () => {
      expect(netFamilyOf('2001:db8::1')).assertEqual(NET_FAMILY_IPV6);
      expect(netFamilyOf('[2001:db8::1]')).assertEqual(NET_FAMILY_IPV6);
      expect(netFamilyOf('1.2.3.4')).assertEqual(NET_FAMILY_IPV4);
      expect(netFamilyOf('proxy.example.com')).assertEqual(NET_FAMILY_IPV4);
    });

    it('有 IPv4 时优先挑 IPv4，没有时挑 IPv6', 0, () => {
      const both: number[] = [NET_FAMILY_IPV6, NET_FAMILY_IPV4];
      expect(pickAddressIndex(both, true)).assertEqual(1);
      expect(pickAddressIndex(both, false)).assertEqual(0);
    });

    // 无脑取 [0] 正是"域名 ping 得通、应用连不上"的来源：双栈主机的 A 记录
    // 常排在前面，而纯 v6 网络上那条不可达。
    it('纯 IPv6 网络上跳过排在前面的 IPv4 记录', 0, () => {
      const dual: number[] = [NET_FAMILY_IPV4, NET_FAMILY_IPV4, NET_FAMILY_IPV6];
      expect(pickAddressIndex(dual, false)).assertEqual(2);
    });

    it('没有匹配的族就退回第一条，让上层报真实错误而不是在这里吞掉', 0, () => {
      expect(pickAddressIndex([NET_FAMILY_IPV4], false)).assertEqual(0);
      expect(pickAddressIndex([NET_FAMILY_IPV6], true)).assertEqual(0);
    });

    it('空列表返回 -1', 0, () => {
      expect(pickAddressIndex([], true)).assertEqual(-1);
      expect(pickAddressIndex([], false)).assertEqual(-1);
    });

    it('本机有没有 IPv4', 0, () => {
      expect(hasIpv4Among([NET_FAMILY_IPV6, NET_FAMILY_IPV4])).assertTrue();
      expect(hasIpv4Among([NET_FAMILY_IPV6])).assertFalse();
      expect(hasIpv4Among([])).assertFalse();
    });

    it('prefer_ipv6：用户强制开，或本机没有 IPv4', 0, () => {
      expect(shouldPreferIpv6(false, true)).assertFalse();   // 常规双栈，维持 TDLib 默认
      expect(shouldPreferIpv6(true, true)).assertTrue();     // 用户强制
      expect(shouldPreferIpv6(false, false)).assertTrue();   // 纯 v6，自动兜底
      expect(shouldPreferIpv6(true, false)).assertTrue();
    });

    // 探测不到本机地址时必须当成"有 IPv4"传进来，否则一次读取失败就会把所有
    // 人的连接方式改掉。这条钉住调用方的约定。
    it('探测失败按 hasIpv4=true 传入时不改变默认行为', 0, () => {
      expect(shouldPreferIpv6(false, true)).assertFalse();
    });
  });
}
