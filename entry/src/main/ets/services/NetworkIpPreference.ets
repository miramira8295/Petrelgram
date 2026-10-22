import { connection } from '@kit.NetworkKit';
import { KEY_PREFER_IPV6 } from '../store/AppSettings';
import { hasIpv4Among, shouldPreferIpv6 } from '../util/ipFamily';
import { logW } from '../util/log';

// 本机当前这条默认网络有没有 IPv4 地址。拿不到就返回 true（维持默认行为）。
async function deviceHasIpv4(): Promise<boolean> {
  try {
    const available: boolean = await connection.hasDefaultNet();
    if (!available) {
      return true;
    }
    const handle: connection.NetHandle = await connection.getDefaultNet();
    if (handle.netId === 0) {
      return true;
    }
    const props: connection.ConnectionProperties = await connection.getConnectionProperties(handle);
    const families: number[] = props.linkAddresses.map(
      (link: connection.LinkAddress): number => link.address.family ?? 0);
    if (families.length === 0) {
      return true;
    }
    return hasIpv4Among(families);
  } catch (e) {
    const err = e as Error;
    logW(`[ipv6] link address probe failed: ${err.message}`);
    return true;
  }
}

// TDLib 和应用内代理转发共用有效偏好；每次读取当前网络，避免切网后沿用旧值。
// 探测是可选信息，最多占 250ms；失败/未知保持 IPv4 优先并保留连接层跨族回退。
export async function resolvePreferIpv6(
  probe: () => Promise<boolean> = deviceHasIpv4,
  forced: () => boolean = (): boolean => AppStorage.get<boolean>(KEY_PREFER_IPV6) ?? false
): Promise<boolean> {
  if (forced()) { return true; }
  let timer: number = -1;
  const fallback = new Promise<boolean>((resolve: (value: boolean) => void): void => {
    timer = setTimeout((): void => resolve(true), 250);
  });
  let hasIpv4: boolean = true;
  try { hasIpv4 = await Promise.race([probe(), fallback]); }
  catch (_error) { /* Optional probe failure keeps the default family order. */ }
  finally { clearTimeout(timer); }
  // 设置可能在探测期间变化，使用完成时的值。
  return shouldPreferIpv6(forced(), hasIpv4);
}
