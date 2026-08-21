import { TdClient } from '../tdkit/TdClient';
import { TdObject, TdRequest, TdError } from '../tdkit/TdTypes';
import { str } from '../util/strings';
import { logE } from '../util/log';

// 自定义 Web Push 中转通道的注册。
//
// 背景：华为 Push Kit 无法用于本项目 —— Push Token 由华为按「AGC 应用 + 设备」
// 签发，推送时网关校验发送方 appId 必须与签发方一致，而实际发推送的是 Telegram
// 官方服务器，它只持有 Telegram 自己的凭证。`registerDevice` 也没有任何 appId
// 字段可以覆盖。
//
// Web Push 绕开了这一点：endpoint 是一个普通 HTTPS 地址，Telegram 直接往那里
// POST，不涉及任何应用身份。用户自建的服务器解密后再转发到自己的通道。
//
// 私钥不在应用侧 —— 解密发生在用户的服务器上，所以应用只需要公开材料
// （endpoint + p256dh 公钥 + auth secret），一个秘密都不持有。

const REGISTER_TIMEOUT_MS: number = 15000;

export interface WebPushConfig {
  endpoint: string;
  p256dh: string;
  auth: string;
}

export interface WebPushValidation {
  valid: boolean;
  error: string; // 面向用户的中文说明，valid 为 true 时是空串
}

// TDLib 侧的硬性要求见 DeviceTokenManager.cpp:195-208：endpoint 不能含逗号，
// 两个密钥字段必须是 base64url。这里提前拦下来，好过等 TDLib 报英文错误。
const BASE64URL_PATTERN: RegExp = /^[A-Za-z0-9_-]+$/;
const IPV4_PATTERN: RegExp = /^\d{1,3}(\.\d{1,3}){3}$/;

// 取 https://host[:port]/path 里的 host（去掉端口和 IPv6 的方括号）。
export function endpointHost(endpoint: string): string {
  const rest = endpoint.substring('https://'.length);
  const end = rest.search(/[/?#]/);
  const authority = end < 0 ? rest : rest.substring(0, end);
  if (authority.startsWith('[')) {
    const close = authority.indexOf(']');
    return close > 0 ? authority.substring(1, close) : '';
  }
  const colon = authority.indexOf(':');
  return colon < 0 ? authority : authority.substring(0, colon);
}

function isIpLiteral(host: string): boolean {
  // IPv6 已经在 endpointHost 里去掉了方括号，含冒号即视为 IPv6 字面量。
  return IPV4_PATTERN.test(host) || host.indexOf(':') >= 0;
}

export function validateWebPushConfig(config: WebPushConfig): WebPushValidation {
  const endpoint = config.endpoint.trim();
  if (endpoint === '') {
    return { valid: false, error: str('wp_endpoint_required') };
  }
  // 必须是 https + 域名。
  //
  // TDLib 本身不校验 scheme（DeviceTokenManager.cpp 只查逗号和 base64url），
  // 载荷也是端到端加密的、不依赖 TLS 保密 —— 所以单看客户端，http 是"能填"的。
  // 但实测 Telegram 服务端不会向 http://<IP>:<端口> 的地址投递：同一套密钥和
  // 服务端代码，https + 域名可以稳定收到，换成 http + 裸 IP 则一条都收不到。
  // 究竟是 scheme、裸 IP 还是非标准端口导致的没有进一步区分，所以这里按
  // Web Push 规范取最保守的一档，避免用户在一个静默失效的配置上耗时间。
  if (!endpoint.startsWith('https://')) {
    return { valid: false, error: str('wp_endpoint_https') };
  }
  const host = endpointHost(endpoint);
  if (host === '') {
    return { valid: false, error: str('wp_endpoint_no_host') };
  }
  if (isIpLiteral(host)) {
    return { valid: false, error: str('wp_endpoint_domain') };
  }
  if (endpoint.indexOf(',') >= 0) {
    return { valid: false, error: str('wp_endpoint_comma') };
  }
  const p256dh = config.p256dh.trim();
  if (p256dh === '' || !BASE64URL_PATTERN.test(p256dh)) {
    return { valid: false, error: str('wp_p256dh_base64url') };
  }
  const auth = config.auth.trim();
  if (auth === '' || !BASE64URL_PATTERN.test(auth)) {
    return { valid: false, error: str('wp_auth_base64url') };
  }
  return { valid: true, error: '' };
}

// 标准 Web Push 订阅 JSON 的形状（浏览器 PushSubscription.toJSON() 和绝大多数
// 服务端库都是这个结构）：
//   { "endpoint": "...", "keys": { "p256dh": "...", "auth": "..." } }
// 同时接受平铺写法 { endpoint, p256dh, auth }，因为手写配置的人常这么写。
export const SUBSCRIPTION_JSON_HINT: string =
  '{\n  "endpoint": "https://push.example.com/webpush/xxx",\n'
  + '  "keys": {\n    "p256dh": "B...",\n    "auth": "..."\n  }\n}';

export interface ParsedSubscription {
  config: WebPushConfig;
  error: string; // 空串表示解析成功
}

function stringField(source: Record<string, Object> | undefined, key: string): string {
  if (source === undefined) {
    return '';
  }
  const value = source[key];
  return typeof value === 'string' ? value.trim() : '';
}

export function parseSubscriptionJson(text: string): ParsedSubscription {
  const empty: WebPushConfig = { endpoint: '', p256dh: '', auth: '' };
  const trimmed = text.trim();
  if (trimmed === '') {
    return { config: empty, error: str('wp_paste_first') };
  }
  let root: Record<string, Object>;
  try {
    root = JSON.parse(trimmed) as Record<string, Object>;
  } catch (e) {
    return { config: empty, error: str('wp_bad_json') };
  }
  if (root === null || typeof root !== 'object') {
    return { config: empty, error: str('wp_json_object') };
  }
  const keys = root['keys'] as Record<string, Object> | undefined;
  const config: WebPushConfig = {
    endpoint: stringField(root, 'endpoint'),
    // 嵌套 keys 优先，取不到再看平铺字段。
    p256dh: stringField(keys, 'p256dh') || stringField(root, 'p256dh'),
    auth: stringField(keys, 'auth') || stringField(root, 'auth')
  };
  const missing: string[] = [];
  if (config.endpoint === '') { missing.push('endpoint'); }
  if (config.p256dh === '') { missing.push('p256dh'); }
  if (config.auth === '') { missing.push('auth'); }
  if (missing.length > 0) {
    return { config, error: str('wp_missing_fields', missing.join(str('list_separator'))) };
  }
  return { config, error: '' };
}

export function buildRegisterRequest(config: WebPushConfig): TdRequest {
  const token: TdObject = { '@type': 'deviceTokenWebPush' };
  token['endpoint'] = config.endpoint.trim();
  token['p256dh_base64url'] = config.p256dh.trim();
  token['auth_base64url'] = config.auth.trim();
  const request: TdRequest = { '@type': 'registerDevice' };
  request['device_token'] = token;
  request['other_user_ids'] = [];
  return request;
}

// endpoint 传空串即注销，见 td_api.tl 对 deviceTokenWebPush 的说明
// （"may be empty to deregister a device"）。关掉开关必须走这一步，否则
// Telegram 会一直往一个已经不用的地址投递。
export function buildDeregisterRequest(): TdRequest {
  return buildRegisterRequest({ endpoint: '', p256dh: '', auth: '' });
}

export function parseReceiverId(result: TdObject): string {
  const id = result['id'];
  return id !== undefined ? `${id}` : '';
}

// 注册成功返回 pushReceiverId —— 这是应用内唯一能自证「Telegram 已接受这个
// endpoint」的信号，UI 拿它显示状态。
export function registerWebPush(client: TdClient, config: WebPushConfig): Promise<string> {
  return client.send(buildRegisterRequest(config), REGISTER_TIMEOUT_MS)
    .then((res: TdObject): string => parseReceiverId(res));
}

export function deregisterWebPush(client: TdClient): Promise<void> {
  return client.send(buildDeregisterRequest(), REGISTER_TIMEOUT_MS)
    .then((): void => {})
    .catch((e: TdError): void => {
      // 注销失败不该阻塞用户关开关，记录即可。
      logE(`WebPushRegistration.deregister failed: ${e.message}`);
    });
}
