import { connection } from '@kit.NetworkKit';
import { getTdClient, isReady } from '../tdkit/Globals';
import { TdObject, TdRequest } from '../tdkit/TdTypes';
import { KEY_PREFER_IPV6 } from '../store/AppSettings';
import { hasIpv4Among, shouldPreferIpv6 } from '../util/ipFamily';
import { logI, logW } from '../util/log';

// 给 TDLib 下 `prefer_ipv6`（issue #133）。
//
// 【为什么需要】纯 IPv6 网络下用户报「代理能 ping 通、应用连不上」。TDLib 这个
// 选项默认 false，会优先去找 IPv4 地址，找不到就报 `Failed to find IPv4/IPv6
// address`——这两个字符串都在我们随包的 libtdjson.so 里，不是猜的。全项目
// 此前 grep `prefer_ipv6` 为 0 次。
//
// 【为什么自动而不是只给开关】纯 v6 环境的用户装上应用就连不上，连不上就看不到
// 设置里那个开关能救他——自动探测是唯一能让第一次启动就work的路。开关留着，
// 给双栈但想强制走 v6 的人（以及自动探测判错时的出口）。
//
// 【探测失败一律按"有 IPv4"处理】读不到本机地址就维持 TDLib 默认行为。一次读取
// 失败不该把所有人的连接方式改掉。
//
// ⚠️ **这条路我们验不了真实效果**：手上没有纯 IPv6 网络。能验的只有「选项被
// TDLib 接受、当前网络不回归」。真实效果要靠 issue #133 的两位报告者实测。

// 上次真正下发过的值。TDLib 的 setOption 不贵，但网络回调会密集触发，
// 没必要每次都发一遍；也让日志只在真的改变时出现一行。
let lastApplied: boolean | null = null;

function sendPreferIpv6(value: boolean): Promise<void> {
  const request: TdRequest = { '@type': 'setOption' };
  request['name'] = 'prefer_ipv6';
  request['value'] = {
    '@type': 'optionValueBoolean',
    'value': value
  } as TdObject;
  return getTdClient().send(request).then((): void => {});
}

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

// 重新判定并（仅在结果变化时）下发。启动与每次网络变化各调一次。
// **永不抛异常**：它挂在网络回调上，一个可选优化不该有能力打断那条链路。
export async function applyPreferIpv6(): Promise<void> {
  if (!isReady()) {
    return;
  }
  const forced: boolean = AppStorage.get<boolean>(KEY_PREFER_IPV6) ?? false;
  const hasIpv4: boolean = await deviceHasIpv4();
  const want: boolean = shouldPreferIpv6(forced, hasIpv4);
  if (lastApplied === want) {
    return;
  }
  try {
    await sendPreferIpv6(want);
    lastApplied = want;
    logI(`[ipv6] prefer_ipv6=${want} (forced=${forced} hasIpv4=${hasIpv4})`);
  } catch (e) {
    const err = e as Error;
    logW(`[ipv6] setOption prefer_ipv6 failed: ${err.message}`);
  }
}

// 切账号 / 重建客户端之后，下一次判定必须真的发出去——新的 TDLib 实例上
// 这个选项是默认值，而我们这边还记着上一个实例的状态。
export function resetPreferIpv6Cache(): void {
  lastApplied = null;
}
