import { str } from './strings';
import {
  PROXY_HTTP, PROXY_MTPROTO, ProxyEntry
} from '../store/ProxyApi';
import { logE } from './log';

export function parseProxyPort(rawPort: string): number {
  const value = rawPort.trim();
  if (!/^\d+$/.test(value)) { return 0; }
  const port = Number(value);
  if (!Number.isInteger(port) || port < 1 || port > 65535) { return 0; }
  return port;
}

export function proxyFormError(
  server: string, rawPort: string, type: string, secret: string
): string {
  if (server.trim() === '') { return str('proxy_server_required'); }
  if (parseProxyPort(rawPort) === 0) { return str('proxy_port_invalid'); }
  if (type === PROXY_MTPROTO && secret.trim() === '') {
    return str('proxy_secret_required');
  }
  return '';
}

export function sameProxyConfiguration(left: ProxyEntry, right: ProxyEntry): boolean {
  if (left.server.trim().toLowerCase() !== right.server.trim().toLowerCase() ||
    left.port !== right.port || left.type !== right.type) {
    return false;
  }
  if (left.type === PROXY_MTPROTO) { return left.secret === right.secret; }
  if (left.type === PROXY_HTTP && left.httpOnly !== right.httpOnly) { return false; }
  return left.username === right.username && left.password === right.password;
}

export function proxyActionErrorText(rawMessage: string, action: string): string {
  // 原始文案只在这里出现一次，映射之后就只剩一句面向用户的话了。代理出问题
  // 时"连不上"和"参数非法"用户要做的事完全不同，而下面的分流全靠关键词猜，
  // 猜错了没有别的线索——所以原文得留在日志里。
  logE(`[proxy] ${action} failed, raw: ${rawMessage}`);
  const message = rawMessage.toUpperCase();
  if (message.indexOf('TIMEOUT') >= 0) { return str('proxy_error_timeout', action); }
  if (message.indexOf('NETWORK') >= 0 || message.indexOf('CONNECTION') >= 0) {
    return str('proxy_error_offline', action);
  }
  if (message.indexOf('PROXY') >= 0 || message.indexOf('SERVER') >= 0 ||
    message.indexOf('PORT') >= 0 || message.indexOf('SECRET') >= 0) {
    return str('proxy_error_invalid_params');
  }
  return str('proxy_error_generic', action);
}

export function proxyConnectionText(state: string, usingProxy: boolean): string {
  if (state === 'connectionStateReady') { return str(usingProxy ? 'proxy_state_connected' : 'proxy_state_direct'); }
  if (state === 'connectionStateConnectingToProxy') { return str('proxy_state_connecting_proxy'); }
  if (state === 'connectionStateConnecting') { return str('proxy_state_connecting'); }
  if (state === 'connectionStateWaitingForNetwork') { return str('proxy_state_waiting_network'); }
  if (state === 'connectionStateUpdating') { return str('proxy_state_updating'); }
  return str(usingProxy ? 'proxy_state_reading_proxy' : 'proxy_state_reading');
}

// 列表里某一行的代理是不是"实际在用且连着"。
//
// pingProxy 对某些代理会报错（TDLib 那边 ping 出去 pong 回不来），而代理本身
// 完全可用——用户拿"无法连接"和"明明能用"一对比，就认定是 bug（issue #31）。
// 对**当前启用**的那个代理有更真的判据：TDLib 的连接状态。Ready / Updating
// 都算连着（Updating 是在拉更新，请求照发不误，和 Globals 里的口径一致）。
// 未启用的代理没有这个判据，只能信 ping。
export function enabledProxyConnected(isEnabled: boolean, connectionState: string): boolean {
  return isEnabled &&
    (connectionState === 'connectionStateReady' || connectionState === 'connectionStateUpdating');
}
