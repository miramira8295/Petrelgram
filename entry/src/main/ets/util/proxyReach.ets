import { connection, socket } from '@kit.NetworkKit';
import { isIpLiteral } from './proxyLogic';
import { hasIpv4Among, netFamilyOf, pickAddressIndex, stripIpv6Brackets } from './ipFamily';

// 到代理服务器的 TCP 握手耗时（ms）。
//
// 用在 pingProxy 报错、但 TDLib 显示代理已连接的那种情况（issue #31）：ping 给
// 不出数字，用户又想看"代理的延迟"。这个数说明的是"代理服务器可达、多快"，
// 不证明 Telegram 走得通——但同一行旁边的「代理已连接」在证明那件事，两者互补。
// 显示时带 ≈，和 ping 的整条往返区分开。
//
// 域名先经系统 DNS 解一次：socket.connect 的 address 要 IP。
//
// 【family 必须显式写 —— issue #133】官方文档：「1 IPv4，默认为 1；2 IPv6，
// 地址为 IPv6 类型，**该字段必须被显式指定为 2**」。原来字面量那条分支一个
// family 都不给，于是 IPv6 地址被当成 IPv4 去连，纯 v6 代理永远测不出延迟。
// 方括号也要剥：用户常从 URL 里抄成 `[2001:db8::1]`，带括号会被当主机名解析。
//
// 【DNS 那条不再无脑取 [0]】双栈主机的 A 记录常排在前面，纯 v6 网络上那条
// 根本不可达——判据见 util/ipFamily.pickAddressIndex。
export async function measureProxyConnectMs(host: string, port: number, timeoutMs: number): Promise<number> {
  const bare: string = stripIpv6Brackets(host);
  let target: socket.NetAddress = { address: bare, port: port, family: netFamilyOf(bare) };
  if (!isIpLiteral(bare)) {
    const net: connection.NetHandle = await connection.getDefaultNet();
    const addrs: connection.NetAddress[] = await net.getAddressesByName(bare);
    if (addrs.length === 0) {
      throw new Error(`dns: no address for ${bare}`);
    }
    const families: number[] = addrs.map((a: connection.NetAddress): number => a.family ?? 0);
    const at: number = pickAddressIndex(families, hasIpv4Among(families));
    const chosen: connection.NetAddress = addrs[at >= 0 ? at : 0];
    target = { address: chosen.address, port: port, family: chosen.family };
  }
  const tcp: socket.TCPSocket = socket.constructTCPSocketInstance();
  const startedAt: number = Date.now();
  try {
    await tcp.connect({ address: target, timeout: timeoutMs });
    return Date.now() - startedAt;
  } finally {
    try {
      await tcp.close();
    } catch (e) {
      // 关不上也不影响结果：这条连接只为计时，进程退出时自然回收。
    }
  }
}
