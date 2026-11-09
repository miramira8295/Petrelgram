// IPv4 / IPv6 的判定与取舍（issue #133）。
//
// 【背景】用户用纯 IPv6 的代理服务器：系统能 ping 通，应用连不上。查出来两处：
//
// 1. `util/proxyReach` 给 socket 的 NetAddress **没写 family**。官方文档：
//    「family：1 IPv4，默认为 1；2 IPv6，地址为 IPv6 类型，**该字段必须被显式
//    指定为 2**」。所以 IPv6 字面量被当成 IPv4 地址去连，必然失败。
// 2. TDLib 的 `prefer_ipv6` 选项我们从来没设过（默认 false）。它就在我们随包的
//    libtdjson.so 里（同时还有 `Failed to find IPv4/IPv6 address` 这句错）。
//    纯 v6 网络下 TDLib 优先找 IPv4 地址，找不到就报那句。
//
// 判定全部抽成纯函数放这里，是因为这两处的验证条件我们**手上没有**——没有纯
// IPv6 网络可测。真机验不了的东西，至少要让逻辑本身被测试钉住。

// socket.NetAddress.family 的取值。文档规定 IPv6 必须显式写 2，不能靠默认。
export const NET_FAMILY_IPV4: number = 1;
export const NET_FAMILY_IPV6: number = 2;

// 用户粘贴 IPv6 地址时常常带方括号（从 URL 里抄的，`[2001:db8::1]:443`）。
// socket 的 address 和 TDLib 的 proxy.server 要的都是**裸地址**，带括号会被
// 当成主机名去做 DNS，然后解析失败。
export function stripIpv6Brackets(host: string): string {
  const trimmed: string = host.trim();
  if (trimmed.length >= 2 && trimmed.startsWith('[') && trimmed.endsWith(']')) {
    return trimmed.substring(1, trimmed.length - 1);
  }
  return trimmed;
}

// 是不是 IPv6 字面量。判据是含冒号——主机名里不可能有冒号（端口在别的字段），
// IPv4 点分里也没有，所以这一条既够用又不会误伤。方括号先剥掉。
export function isIpv6Literal(host: string): boolean {
  return stripIpv6Brackets(host).indexOf(':') >= 0;
}

// 给 socket.NetAddress 用的 family。
export function netFamilyOf(host: string): number {
  return isIpv6Literal(host) ? NET_FAMILY_IPV6 : NET_FAMILY_IPV4;
}

// DNS 解出多条地址时挑哪一条。
//
// 【为什么不能无脑取 [0]】双栈主机上 A 记录常排在前面，而在纯 IPv6 网络里那条
// 根本不可达——表现就是"能 ping 通域名、应用连不上"。按当前网络实际有没有
// IPv4 来挑，没有 IPv4 就只认 v6；反之优先 v4（兼容性更好）。
// 都没有匹配的就退回第一条，让上层去报真实的连接错误，而不是在这里吞掉。
export function pickAddressIndex(families: number[], hasIpv4: boolean): number {
  if (families.length === 0) {
    return -1;
  }
  const want: number = hasIpv4 ? NET_FAMILY_IPV4 : NET_FAMILY_IPV6;
  for (let i = 0; i < families.length; i++) {
    if (families[i] === want) {
      return i;
    }
  }
  return 0;
}

// 本机这条网络有没有 IPv4 地址。linkAddresses 里任意一条是 v4 就算有。
export function hasIpv4Among(families: number[]): boolean {
  for (let i = 0; i < families.length; i++) {
    if (families[i] === NET_FAMILY_IPV4) {
      return true;
    }
  }
  return false;
}

// 要不要给 TDLib 下 prefer_ipv6 = true。
//
// 【为什么是"用户强制开 或 本机没有 IPv4"，而不是三档开关】能想到的第三档
// （在没有 IPv4 的网络上强制关 IPv6）没有任何用处——关了就彻底没网。所以一个
// 布尔加自动兜底就覆盖全了，界面也少一档要解释的东西。
//
// hasIpv4 拿不到时（探测失败、还没探测）传 true：维持 TDLib 的默认行为，
// 不要因为读不到本机地址就把所有人的连接方式改掉。
export function shouldPreferIpv6(userForcedOn: boolean, hasIpv4: boolean): boolean {
  return userForcedOn || !hasIpv4;
}
