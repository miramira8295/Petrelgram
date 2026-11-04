import { webview } from '@kit.ArkWeb';
import { logW } from '../util/log';
import { isIpv6Literal, stripIpv6Brackets } from '../util/ipFamily';
import { TdClient } from '../tdkit/TdClient';
import { TdObject, TdRequest } from '../tdkit/TdTypes';

// ArkWeb（小程序、内置浏览器）的代理。
//
// 【为什么单独一份】TDLib 的代理只作用于 TDLib 自己的连接，Web 组件走的是另
// 一套网络栈，两者互不认识。用户开了代理以后，Telegram 消息能过，小程序里却
// 还是直连——在需要代理的网络里就是打不开。Web 内核提供了 applyProxyOverride
// 这个原生入口（API 15 起），一次配置作用于全应用所有 Web，不需要我们再在本机
// 起转发服务。
//
// 【为什么不是 connection.setAppHttpProxy】那个接口只写"代理规则"，实际转发还
// 要调用方在 http 请求里显式打开 usingProxy；Web 内核不读它。
//
// 【能表达什么】规则的 scheme 只有 http / https / socks 三种：
//  · SOCKS5 代理 → socks://（Web 内核自己完成 SOCKS5 握手，HTTPS 由它自己 CONNECT）
//  · HTTP 代理   → http://（HTTPS 目标同样由它自己 CONNECT）
//  · MTProto     → 表达不了，只能让 Web 直连，调用方据此清掉配置
// SOCKS5 的用户名/密码这里的规则格式带不上，需要鉴权的 SOCKS5 代理对 Web 无效。

export const WEB_PROXY_SCHEME_SOCKS: string = 'socks';
export const WEB_PROXY_SCHEME_HTTP: string = 'http';

let scheme: string = '';
let host: string = '';
let port: number = 0;
// 配置是否已经成功交给 Web 内核。applyProxyOverride 在 Web 引擎还没起来时会
// 抛错，所以这里记状态，页面打开时再补一次（ensureWebProxy）。
let applied: boolean = false;

/** 规则串：[scheme://]host[:port]，IPv6 字面量必须带方括号。 */
function ruleOf(ruleScheme: string, ruleHost: string, rulePort: number): string {
  const bare: string = stripIpv6Brackets(ruleHost);
  const address: string = isIpv6Literal(bare) ? `[${bare}]` : bare;
  return `${ruleScheme}://${address}:${rulePort}`;
}

function apply(): void {
  if (scheme === '' || host === '') {
    return;
  }
  const rule: string = ruleOf(scheme, host, port);
  try {
    const config = new webview.ProxyConfig();
    // 默认的隐式直连规则（localhost、链路本地地址）保持不动：本机回环不该被
    // 送去远端代理。
    config.insertProxyRule(rule);
    webview.ProxyController.applyProxyOverride(config, (): void => {
      applied = true;
    });
    // 日志打在调用点而不是回调里：回调在 Web 内核起来之后才触发，还没有任何
    // Web 实例时可能一直不回来，那样就分不清"没配上"和"配上了但还没生效"。
    logW(`[WebProxy] active ${rule}`);
  } catch (e) {
    applied = false;
    logW(`[WebProxy] apply failed: ${(e as Error).message}`);
  }
}

/**
 * 设置 Web 侧的代理。scheme 取 'socks' 或 'http'；空串表示清掉。
 * host 传裸地址（方括号会被剥掉）。
 */
export function setWebProxy(nextScheme: string, nextHost: string, nextPort: number): void {
  const changed: boolean = nextScheme !== scheme || nextHost !== host || nextPort !== port;
  scheme = nextScheme;
  host = nextHost;
  port = nextPort;
  if (scheme === '' || host === '') {
    clearWebProxy();
    return;
  }
  if (!changed && applied) {
    return;
  }
  apply();
}

/** 撤掉 Web 侧代理，回到直连。 */
export function clearWebProxy(): void {
  const had: boolean = applied || scheme !== '';
  scheme = '';
  host = '';
  port = 0;
  applied = false;
  if (!had) {
    return;
  }
  try {
    webview.ProxyController.removeProxyOverride((): void => {
      logW('[WebProxy] cleared');
    });
  } catch (e) {
    logW(`[WebProxy] clear failed: ${(e as Error).message}`);
  }
}

// TDLib 的 proxy 类型（store/ProxyApi 里那几个字符串常量，这里不 import 它们，
// 否则 services ↔ store 会绕成环）。
const TD_PROXY_SOCKS5: string = 'proxyTypeSocks5';
const TD_PROXY_HTTP: string = 'proxyTypeHttp';

function webSchemeOfType(type: string): string {
  if (type === TD_PROXY_SOCKS5) { return WEB_PROXY_SCHEME_SOCKS; }
  if (type === TD_PROXY_HTTP) { return WEB_PROXY_SCHEME_HTTP; }
  return '';
}

/**
 * 把 TDLib 当前启用的代理映射到 Web 内核。
 *
 * 传入 client 而不是自己 getTdClient()，是为了让 ProxyAutoSwitchService 也能
 * 直接用（它持有自己的 TdClient），同时不引入 store → services → store 的循环
 * 依赖。任何异常都吞掉：Web 侧配不上不该让"启用代理"这个动作失败。
 */
export async function syncWebProxyFromTd(client: TdClient): Promise<void> {
  try {
    const result = await client.send({ '@type': 'getProxies' } as TdRequest, 20000);
    const raw = (result['proxies'] as TdObject[] | undefined) ?? [];
    let enabledType: string = '';
    let enabledServer: string = '';
    let enabledPort: number = 0;
    let found: boolean = false;
    for (let i = 0; i < raw.length; i++) {
      const row: TdObject = raw[i];
      if ((row['is_enabled'] as boolean | undefined) !== true) {
        continue;
      }
      // getProxies 的行是 { id, proxy: {...}, is_enabled }——代理本体嵌在
      // proxy 里，不是平铺在行上（ProxyMigration 里也是这么读的）。
      const proxy = (row['proxy'] as TdObject | undefined) ?? {} as TdObject;
      const type = (proxy['type'] as TdObject | undefined) ?? {} as TdObject;
      enabledType = (type['@type'] as string | undefined) ?? '';
      enabledServer = (proxy['server'] as string | undefined) ?? '';
      enabledPort = (proxy['port'] as number | undefined) ?? 0;
      found = true;
      break;
    }
    if (!found) {
      // 启动早期 getProxies 可能还没数据，这时不要清配置，否则会把上一轮
      // 的有效配置抹掉。真删掉最后一个代理的情况，列表同样非空过，不受影响。
      if (raw.length > 0) {
        clearWebProxy();
      }
      return;
    }
    const scheme: string = webSchemeOfType(enabledType);
    if (scheme === '' || enabledServer === '' || enabledPort <= 0) {
      // MTProto 代理 Web 内核不认识，只能让它直连。
      clearWebProxy();
      return;
    }
    setWebProxy(scheme, stripIpv6Brackets(enabledServer), enabledPort);
  } catch (e) {
    logW(`[WebProxy] sync failed: ${(e as Error).message}`);
  }
}
