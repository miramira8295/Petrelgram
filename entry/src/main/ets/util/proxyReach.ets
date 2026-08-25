import { connection, socket } from '@kit.NetworkKit';
import { isIpLiteral } from './proxyLogic';

// 到代理服务器的 TCP 握手耗时（ms）。
//
// 用在 pingProxy 报错、但 TDLib 显示代理已连接的那种情况（issue #31）：ping 给
// 不出数字，用户又想看"代理的延迟"。这个数说明的是"代理服务器可达、多快"，
// 不证明 Telegram 走得通——但同一行旁边的「代理已连接」在证明那件事，两者互补。
// 显示时带 ≈，和 ping 的整条往返区分开。
//
// 域名先经系统 DNS 解一次：socket.connect 的 address 要 IP。
export async function measureProxyConnectMs(host: string, port: number, timeoutMs: number): Promise<number> {
  let target: socket.NetAddress = { address: host, port: port };
  if (!isIpLiteral(host)) {
    const net: connection.NetHandle = await connection.getDefaultNet();
    const addrs: connection.NetAddress[] = await net.getAddressesByName(host);
    if (addrs.length === 0) {
      throw new Error(`dns: no address for ${host}`);
    }
    target = { address: addrs[0].address, port: port, family: addrs[0].family };
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
