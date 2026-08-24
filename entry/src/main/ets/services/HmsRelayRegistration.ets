import { http } from '@kit.NetworkKit';
import { pushService } from '@kit.PushKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { TdClient } from '../tdkit/TdClient';
import { pushRelayBase, pushRelayToken } from '../tdkit/ApiCredentials';
import { getOrCreateMeowSubKey } from './MeowPushRegistration';
import { registerWebPush, WebPushConfig } from './WebPushRegistration';
import {
  KEY_HMS_PUSH_TOKEN, KEY_WEBPUSH_AUTH, KEY_WEBPUSH_ENABLED,
  KEY_WEBPUSH_ENDPOINT, KEY_WEBPUSH_MODE, KEY_WEBPUSH_P256DH, setBoolean, setString
} from '../store/AppSettings';
import { logE, logI, logW } from '../util/log';

// 华为 Push Kit 通道的注册。
//
// 链路：Telegram →（WebPush）→ 自建中转 → HMS → 设备。
// Telegram 那头注册的**永远是 deviceTokenWebPush**——华为直连早被证否（我们的
// api_id 在 Telegram 侧没登记华为凭据，400 APP_PUSH_APIKEY_MISSING，而
// my.telegram.org 没有这个配置入口）。设备 token 只用在中转到设备这后半段。
//
// **可用性判据是 getToken() 成不成功，不是构建类型。**
// 真正的门槛是签名身份与 AGC 应用是否一致，而 getToken 检验的正好是这个。
// 用 debug/release 标志会判错两次：自己签的调试包 debug=true 但能取到 token；
// 别人拿 GitHub 的未签名包自签之后各种标志都正常，却必然取不到。GitHub 上发的
// 就是未签名包，所以对绝大多数用户这条通道根本不存在——那不是故障，是预期。

const REQUEST_TIMEOUT_MS: number = 15000;

// webPushMode 的取值。'hms' 是本模块注册成功后写入的，界面据此显示当前通道。
export const WEBPUSH_MODE_HMS: string = 'hms';

export interface HmsTokenResult {
  available: boolean;
  token: string;
  // 取不到时的原因。**要留完整错误码**：是 client_id 没配、签名不对、还是设备
  // 没有 HMS，全靠这个码区分，只记一句"失败"等于把排查路堵死。
  errorCode: number;
  errorMessage: string;
}

// 试着取设备 token。**永不抛异常**——调用方多半在启动路径上，一个可选通道不该
// 有能力中断登录流程。
export async function fetchHmsToken(): Promise<HmsTokenResult> {
  try {
    const token: string = await pushService.getToken();
    if (token === '') {
      return { available: false, token: '', errorCode: 0, errorMessage: 'empty token' };
    }
    return { available: true, token: token, errorCode: 0, errorMessage: '' };
  } catch (e) {
    const err = e as BusinessError;
    return { available: false, token: '', errorCode: err.code, errorMessage: err.message };
  }
}

export interface HmsRegisterBody {
  subKey: string;
  pushToken: string;
}

export function buildHmsRegisterBody(subKey: string, pushToken: string): HmsRegisterBody {
  return { subKey: subKey, pushToken: pushToken };
}

export interface HmsRegisterResponse {
  endpoint: string;
  p256dh: string;
  auth: string;
  error: string;
}

// 解析中转的响应。响应形状与 /register/confirm 逐字段相同，但这里单独解析而不是
// 复用 MeoW 那个：那边多一个 secret 的语义（只在首次注册时非空），混在一起会让
// 两条路的错误信息互相污染。
export function parseHmsRegisterResponse(raw: string): HmsRegisterResponse {
  const empty: HmsRegisterResponse = { endpoint: '', p256dh: '', auth: '', error: '' };
  let parsed: Record<string, Object>;
  try {
    parsed = JSON.parse(raw) as Record<string, Object>;
  } catch (e) {
    return { endpoint: '', p256dh: '', auth: '', error: 'invalid json' };
  }
  const serverError = (parsed['error'] as string | undefined) ?? '';
  if (serverError !== '') {
    return { endpoint: '', p256dh: '', auth: '', error: serverError };
  }
  const endpoint = (parsed['endpoint'] as string | undefined) ?? '';
  const p256dh = (parsed['p256dh'] as string | undefined) ?? '';
  const auth = (parsed['auth'] as string | undefined) ?? '';
  if (endpoint === '' || p256dh === '' || auth === '') {
    return { endpoint: '', p256dh: '', auth: '', error: 'incomplete response' };
  }
  return { endpoint: endpoint, p256dh: p256dh, auth: auth, error: '' };
}

// 这次是不是需要重新向中转注册。
//
// **不是每次启动都注册**：那是一次白白的网络往返，而且会把中转的注册限流桶
// 打满（每 IP 有窗口配额，同一个 Wi-Fi 下多台设备会互相挤掉）。
// 只有两种情况要重注册：从没注册过，或者设备 token 变了（重装、系统换 token）。
export function needsHmsRegistration(storedToken: string, freshToken: string, endpoint: string): boolean {
  if (freshToken === '') {
    return false;
  }
  if (endpoint === '') {
    return true;
  }
  return storedToken !== freshToken;
}

function authHeader(): Record<string, string> {
  const header: Record<string, string> = { 'Content-Type': 'application/json' };
  if (pushRelayToken !== '') {
    header['Authorization'] = `Bearer ${pushRelayToken}`;
  }
  return header;
}

// 向中转注册设备 token，拿回 Web Push 三元组。
async function postHmsRegistration(subKey: string, pushToken: string): Promise<HmsRegisterResponse> {
  const request = http.createHttp();
  try {
    const response = await request.request(`${pushRelayBase}/register/hms`, {
      method: http.RequestMethod.POST,
      connectTimeout: REQUEST_TIMEOUT_MS,
      readTimeout: REQUEST_TIMEOUT_MS,
      header: authHeader(),
      extraData: JSON.stringify(buildHmsRegisterBody(subKey, pushToken))
    });
    if (response.responseCode !== 200) {
      // 503 = 中转没配华为通道。这不是错误，是那台中转只跑 MeoW。
      return {
        endpoint: '', p256dh: '', auth: '',
        error: `HTTP ${response.responseCode}`
      };
    }
    return parseHmsRegisterResponse(String(response.result));
  } finally {
    request.destroy();
  }
}

// 完整流程：取 token → 注册到中转 → 把 endpoint 交给 Telegram。
//
// **整个流程静默失败**：它跑在登录就绪的回调里，任何一步出问题都只记日志。
// 用户没配中转、中转没开华为通道、设备取不到 token——三种都是正常状态，不该
// 弹任何东西。真正需要用户知道的场景在设置页里显示。
export async function ensureHmsPushRegistered(client: TdClient): Promise<boolean> {
  // **进门先记一笔。**
  //
  // 原来这里的早退没有任何日志，结果排查时分不清"根本没被调用"和"调用了但中转
  // 没配"——两者的下一步完全不同（前者查登录回调有没有触发，后者查
  // ApiCredentials），而现象都是"日志里什么都没有"。一条 info 就把这个岔口消掉。
  logI(`[HMS] ensure start, relay configured=${pushRelayBase !== ''}`);
  if (pushRelayBase === '') {
    return false;
  }
  const tokenResult: HmsTokenResult = await fetchHmsToken();
  if (!tokenResult.available) {
    // 未签名包必然走到这里，不是故障，用 info 而不是 error。
    logI(`[HMS] channel unavailable on this device (${tokenResult.errorCode}: ${tokenResult.errorMessage})`);
    return false;
  }

  const storedToken: string = AppStorage.get<string>(KEY_HMS_PUSH_TOKEN) ?? '';
  const endpoint: string = AppStorage.get<string>(KEY_WEBPUSH_ENDPOINT) ?? '';
  if (!needsHmsRegistration(storedToken, tokenResult.token, endpoint)) {
    logI('[HMS] device token unchanged, skipping re-registration');
    return true;
  }

  let parsed: HmsRegisterResponse;
  try {
    parsed = await postHmsRegistration(getOrCreateMeowSubKey(), tokenResult.token);
  } catch (e) {
    logW(`[HMS] relay registration request failed: ${e}`);
    return false;
  }
  if (parsed.error !== '') {
    logW(`[HMS] relay rejected registration: ${parsed.error}`);
    return false;
  }

  const config: WebPushConfig = {
    endpoint: parsed.endpoint, p256dh: parsed.p256dh, auth: parsed.auth
  };
  try {
    const receiverId: string = await registerWebPush(client, config);
    // **先注册成功再落盘**：反过来的话，Telegram 那步失败会留下一份"看着已配置
    // 好、实际收不到推送"的设置，而且 needsHmsRegistration 下次会因为 token 没变
    // 而跳过重试，故障就永久化了。
    setString(KEY_WEBPUSH_ENDPOINT, parsed.endpoint);
    setString(KEY_WEBPUSH_P256DH, parsed.p256dh);
    setString(KEY_WEBPUSH_AUTH, parsed.auth);
    setString(KEY_HMS_PUSH_TOKEN, tokenResult.token);
    setString(KEY_WEBPUSH_MODE, WEBPUSH_MODE_HMS);
    setBoolean(KEY_WEBPUSH_ENABLED, true);
    logI(`[HMS] push registered, receiver id ${receiverId}`);
    return true;
  } catch (e) {
    logE(`[HMS] Telegram registerDevice failed: ${JSON.stringify(e)}`);
    return false;
  }
}
