import { http } from '@kit.NetworkKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { TdClient } from '../tdkit/TdClient';
import { str } from '../util/strings';
import { pushRelayBase, pushRelayToken } from '../tdkit/ApiCredentials';
import {
  KEY_MEOW_AUTH, KEY_MEOW_ENDPOINT, KEY_MEOW_NICKNAME, KEY_MEOW_P256DH, KEY_MEOW_PENDING_DELETE, KEY_MEOW_SECRET,
  KEY_MEOW_SUBKEY, WEBPUSH_MODE_CUSTOM, WEBPUSH_MODE_MEOW, setString
} from '../store/AppSettings';
import {
  WebPushConfig, deregisterWebPush, registerWebPush, setWebPushChannel, validateWebPushConfig
} from './WebPushRegistration';
import { logE, logI } from '../util/log';

// MeoW 推送模式：用户只填 MeoW 用户名，三个 Web Push 字段 (endpoint / p256dh /
// auth) 由作者自建的中转服务器下发，再复用 WebPushRegistration 那条已经跑通的
// registerDevice(deviceTokenWebPush) 路径注册进 TDLib。
//
// 中转服务器持有解密私钥，能看到消息发送者与内容摘要 —— 这是 MeoW 模式相对
// 手工模式（私钥留在用户自己的服务器上）额外付出的信任代价，界面上必须提示。
//
// 接口约定见服务端实现（固定，不在本仓库内），两步注册 + 验证码：
//   POST   {base}/register          { subKey, meow } -> { pendingId }
//     服务器往该 MeoW 昵称推一条验证码，pendingId 5 分钟过期。MeoW 是纯昵称
//     寻址、无鉴权的，谁都能往任意昵称推消息 —— 不验证的话，别人能拿别人的
//     昵称注册，把自己的 Telegram 消息全部转推过去。验证码证明用户确实拥有
//     这个昵称。
//   POST   {base}/register/confirm  { subKey, pendingId, code } -> { endpoint, p256dh, auth, secret }
//     验证码错误或过期返回 400/403。
//   DELETE {base}/register          { subKey, secret } -> 200
//     2026-09-17 起中转只凭 subKey 删、删不删得到都回 200（issue #196：secret 没存住的
//     用户永远删不掉映射，点了注销仍收到推送）。secret 照带，兼容还没升级的中转——
//     那种中转 secret 不对回 403，客户端按"没删掉"处理、下次启动重试。
//
// 主键是 subKey 而不是 Telegram userId：userId 是客户端自报的、随便一个群里
// 点头像就能看到，用它当主键会有"先到先得抢注"和"重装丢了 secret 就永久锁死"
// 两个问题。subKey 由客户端首次用到时随机生成（CryptoArchitectureKit 的安全
// 随机数，不是 Math.random()），服务器完全不认识 Telegram 账号，没有身份可
// 冒充。代价是重装即新订阅，可接受。
//
// 每个请求都带 Authorization: Bearer {pushRelayToken}，用来挡掉公网随机扫描；
// pushRelayBase 和 pushRelayToken 任一为空都视为"这份构建没有配置中转"，
// MeoW 入口整个隐藏。

const REQUEST_TIMEOUT_MS: number = 15000;
const SUBKEY_BYTE_LEN: number = 24; // 48 位十六进制，足够的熵

export function meowRelayEnabled(): boolean {
  return pushRelayBase.trim() !== '' && pushRelayToken.trim() !== '';
}

// 页面用哪个模式打开：MeoW 是首选默认值，但仅在中转地址配置齐全时才可能出现。
// relayEnabled 为 false 时无论存过什么偏好都必须回落到手工模式 —— 否则会出现
// "默认停在一个界面上根本不存在的模式"，页面空白或渲染出错。relayEnabled 为
// true 时尊重用户存过的显式偏好（无论是哪一种），只有从未选过（storedMode
// 为空）才落到新默认值 MeoW。
export function resolveWebPushMode(relayEnabled: boolean, storedMode: string): string {
  if (!relayEnabled) {
    return WEBPUSH_MODE_CUSTOM;
  }
  if (storedMode === WEBPUSH_MODE_CUSTOM || storedMode === WEBPUSH_MODE_MEOW) {
    return storedMode;
  }
  return WEBPUSH_MODE_MEOW;
}

export interface MeowValidation {
  valid: boolean;
  error: string;
}

export function validateMeowNickname(nickname: string): MeowValidation {
  if (nickname.trim() === '') {
    return { valid: false, error: str('meow_nickname_required') };
  }
  return { valid: true, error: '' };
}

export function validateMeowCode(code: string): MeowValidation {
  if (code.trim() === '') {
    return { valid: false, error: str('meow_code_required') };
  }
  return { valid: true, error: '' };
}

export interface MeowRegisterStartBody {
  subKey: string;
  meow: string;
}

export function buildMeowRegisterStartBody(subKey: string, meow: string): MeowRegisterStartBody {
  return { subKey, meow: meow.trim() };
}

export interface MeowConfirmBody {
  subKey: string;
  pendingId: string;
  code: string;
}

export function buildMeowConfirmBody(subKey: string, pendingId: string, code: string): MeowConfirmBody {
  return { subKey, pendingId, code: code.trim() };
}

export interface MeowDeleteRequestBody {
  subKey: string;
  secret: string;
}

export function buildMeowDeleteBody(subKey: string, secret: string): MeowDeleteRequestBody {
  return { subKey, secret };
}

// 只有 200 算删掉了。新中转删不删得到都回 200；旧中转 secret 不对回 403，那就是没删。
export function meowRelayDeleteSucceeded(responseCode: number): boolean {
  return responseCode === 200;
}

function stringField(source: Record<string, Object>, key: string): string {
  const value = source[key];
  return typeof value === 'string' ? value.trim() : '';
}

// 诊断用：只记**有哪些键**，绝不记值。secret / auth / p256dh 就是推送的
// 解密密钥，一旦进了 hilog，任何能连上设备的人都读得到。
function logShape(step: string, root: Record<string, Object> | null, text: string): void {
  if (root === null) {
    logE(`[meow] ${step}: body is not a JSON object, len=${text.length}`);
    return;
  }
  logE(`[meow] ${step}: keys=${Object.keys(root).join(',')}`);
}

function parseJsonObject(text: string): Record<string, Object> | null {
  let root: Object;
  try {
    root = JSON.parse(text) as Object;
  } catch (e) {
    return null;
  }
  if (root === null || typeof root !== 'object') {
    return null;
  }
  return root as Record<string, Object>;
}

// 服务端自己的错误说明。它在「这个昵称已经注册过」这类情况下仍然回 200，
// body 里既没有 pendingId 也没有那套 Web Push 字段，带的是这么一句话。
// 原来一律归成"数据不完整，请稍后重试"，等于把服务端说的话丢掉——用户照着
// 提示重试多少次都是同一个结果。
//
// 三个键名都认：不同版本的中转服务端用法不一。
function serverMessage(source: Record<string, Object>): string {
  const keys: string[] = ['error', 'message', 'msg'];
  for (const key of keys) {
    const text = stringField(source, key);
    if (text !== '') {
      return text;
    }
  }
  return '';
}

export interface MeowStartResult {
  pendingId: string;
  error: string; // 空串表示解析成功
}

// 解析 {base}/register 的响应体，只取 pendingId —— 这一步按接口约定不返回
// 任何密钥。
export function parseMeowStartResponse(text: string): MeowStartResult {
  const root = parseJsonObject(text);
  if (root === null) {
    logShape('register', null, text);
    return { pendingId: '', error: str('meow_bad_response') };
  }
  const pendingId = stringField(root, 'pendingId');
  if (pendingId === '') {
    logShape('register', root, text);
    const said = serverMessage(root);
    return { pendingId: '', error: said !== '' ? said : str('meow_bad_response') };
  }
  return { pendingId, error: '' };
}

export interface MeowConfirmResult {
  config: WebPushConfig;
  secret: string;
  error: string; // 空串表示解析成功且三个字段与 secret 齐全
}

// 解析 {base}/register/confirm 的响应体。三个 Web Push 字段缺任一都视为服务端
// 返回不完整 —— 一个残缺的配置注册进 TDLib 只会静默收不到推送，不去猜测默认值。
//
// secret 是个例外。已经注册过再注册一次时，服务端仍然回 200、三个字段齐全，
// 但**不再下发 secret**（它认为这个 subKey 的 secret 早发过了）。secret 只用于
// 注销（DELETE 带 secret，403 表示不对），本地本来就存着上一次那份——传进来
// 接上即可，不该让用户卡在"数据不完整，请稍后重试"上，那句提示还会误导他
// 一遍遍重试。
//
// 两边都没有才是真的走不下去：那样注册得上也注销不掉。
export function parseMeowConfirmResponse(text: string, knownSecret: string = ''): MeowConfirmResult {
  const empty: WebPushConfig = { endpoint: '', p256dh: '', auth: '' };
  const root = parseJsonObject(text);
  if (root === null) {
    logShape('confirm', null, text);
    return { config: empty, secret: '', error: str('meow_bad_response') };
  }
  const config: WebPushConfig = {
    endpoint: stringField(root, 'endpoint'),
    p256dh: stringField(root, 'p256dh'),
    auth: stringField(root, 'auth')
  };
  // 服务端给了以服务端为准，没给才回落到本地那份。
  const fromServer = stringField(root, 'secret');
  const secret = fromServer !== '' ? fromServer : knownSecret;
  if (config.endpoint === '' || config.p256dh === '' || config.auth === '' || secret === '') {
    logShape('confirm', root, text);
    const said = serverMessage(root);
    return { config, secret, error: said !== '' ? said : str('meow_bad_response') };
  }
  return { config, secret, error: '' };
}

function toError(e: Object, fallbackMessage: string): Error {
  return e instanceof Error ? e : new Error(fallbackMessage);
}

function toHex(data: Uint8Array): string {
  let out = '';
  for (let i = 0; i < data.length; i++) {
    const byte = data[i];
    out += byte < 16 ? `0${byte.toString(16)}` : byte.toString(16);
  }
  return out;
}

// 只读：注销时用，没有 subKey 就没有可注销的订阅，不必为此生成一个新的。
export function getMeowSubKey(): string {
  return AppStorage.get<string>(KEY_MEOW_SUBKEY) ?? '';
}

// 新造一把 subKey。两条通道共用这个生成器，但**各存各的键**——
// 共用一把钥匙正是 2026-09-21 查出的孤儿订阅之源，见 util/pushSubKeyMigration。
export function newSubKey(): string {
  const random = cryptoFramework.createRandom();
  const blob = random.generateRandomSync(SUBKEY_BYTE_LEN);
  return toHex(blob.data);
}

// 首次用到时才生成，生成后落盘复用 —— 一台设备一个账号对应一个 subKey，
// 重装即换新订阅（旧订阅由服务端按 TTL 清理）。
//
// ⚠️ **这把只给 MeoW**。华为通道用 getOrCreateHmsSubKey（在 HmsRelayRegistration），
// 因为下面两处清空只对 MeoW 成立，HMS 跟着被清就会留下删不掉的孤儿订阅。
export function getOrCreateMeowSubKey(): string {
  const existing = AppStorage.get<string>(KEY_MEOW_SUBKEY) ?? '';
  if (existing !== '') {
    return existing;
  }
  const subKey = newSubKey();
  setString(KEY_MEOW_SUBKEY, subKey);
  return subKey;
}

function authHeader(): Record<string, string> {
  return {
    'Content-Type': 'application/json',
    'Authorization': `Bearer ${pushRelayToken}`
  };
}

// 第一步：把昵称交给中转服务器，服务器往该昵称推一条验证码。返回 pendingId，
// 供第二步 confirm 使用。
export async function startMeowRegistration(meow: string): Promise<string> {
  if (!meowRelayEnabled()) {
    throw new Error(str('meow_relay_unconfigured'));
  }
  const nickCheck = validateMeowNickname(meow);
  if (!nickCheck.valid) {
    throw new Error(nickCheck.error);
  }
  const body: MeowRegisterStartBody = buildMeowRegisterStartBody(getOrCreateMeowSubKey(), meow);
  const request = http.createHttp();
  let responseText: string;
  try {
    const response = await request.request(`${pushRelayBase}/register`, {
      method: http.RequestMethod.POST,
      connectTimeout: REQUEST_TIMEOUT_MS,
      readTimeout: REQUEST_TIMEOUT_MS,
      header: authHeader(),
      extraData: JSON.stringify(body)
    });
    if (response.responseCode !== 200) {
      throw new Error(str('meow_http_error', `${response.responseCode}`));
    }
    responseText = String(response.result);
  } catch (e) {
    throw toError(e, str('meow_network_error'));
  } finally {
    request.destroy();
  }
  const parsed = parseMeowStartResponse(responseText);
  if (parsed.error !== '') {
    throw new Error(parsed.error);
  }
  return parsed.pendingId;
}

export interface MeowRegisterOutcome {
  receiverId: string;
  secret: string;
}

// 第二步：把用户填回来的验证码交给中转服务器确认，拿到 Web Push 三元组后复用
// 已验证过的 registerWebPush 路径。
export async function confirmMeowRegistration(
  client: TdClient, pendingId: string, code: string, meow: string,
  // 重复注册时服务端不再下发 secret，本地那份接上去（见 parseMeowConfirmResponse）。
  knownSecret: string = ''
): Promise<MeowRegisterOutcome> {
  if (!meowRelayEnabled()) {
    throw new Error(str('meow_relay_unconfigured'));
  }
  const codeCheck = validateMeowCode(code);
  if (!codeCheck.valid) {
    throw new Error(codeCheck.error);
  }
  const body: MeowConfirmBody = buildMeowConfirmBody(getOrCreateMeowSubKey(), pendingId, code);
  const request = http.createHttp();
  let responseText: string;
  try {
    const response = await request.request(`${pushRelayBase}/register/confirm`, {
      method: http.RequestMethod.POST,
      connectTimeout: REQUEST_TIMEOUT_MS,
      readTimeout: REQUEST_TIMEOUT_MS,
      header: authHeader(),
      extraData: JSON.stringify(body)
    });
    if (response.responseCode === 400 || response.responseCode === 403) {
      throw new Error(str('meow_code_invalid'));
    }
    if (response.responseCode !== 200) {
      throw new Error(str('meow_http_error', `${response.responseCode}`));
    }
    responseText = String(response.result);
  } catch (e) {
    throw toError(e, str('meow_network_error'));
  } finally {
    request.destroy();
  }
  const parsed = parseMeowConfirmResponse(responseText, knownSecret);
  if (parsed.error !== '') {
    // 三个字段齐全、独独两边都没有 secret：中转早把这个 subKey 记成"已注册"
    // （secret 只在首次响应里发一次），本机那份又没存上——这台机器用这个 subKey
    // 永远注册不上，也注销不掉（注销要 secret）。唯一的出路是换一个 subKey，对
    // 中转来说就是一次全新注册，会重新发 secret。清掉本地 subKey，下次
    // getOrCreateMeowSubKey 会生成新的；旧订阅留在中转上无害——Telegram 那边
    // registerDevice 是替换语义，不会再往旧的推。（issue #60 / #39：报告人
    // "取消注册之后重注册好几次都不行"走的就是这个死循环。）
    const configComplete: boolean = parsed.config.endpoint !== '' &&
      parsed.config.p256dh !== '' && parsed.config.auth !== '';
    if (configComplete && parsed.secret === '') {
      setString(KEY_MEOW_SUBKEY, '');
      throw new Error(str('meow_secret_lost_reset'));
    }
    throw new Error(parsed.error);
  }
  const check = validateWebPushConfig(parsed.config);
  if (!check.valid) {
    throw new Error(check.error);
  }
  // **secret 收到就落盘，先于 Telegram 那一步。** 中转只在首次注册的响应里下发
  // 一次 secret（之后同一个 subKey 再 confirm 都不再给）。原来是等 registerWebPush
  // 成功才存：Telegram 那步一失败——网络抖一下就够——本地没存、中转不再发，此后
  // 每次重试都是"中转服务器返回的数据不完整，请稍后重试"，永远出不来
  // （issue #60 / #39）。secret 只用于注销，存下来对 Telegram 那步没有任何依赖。
  setString(KEY_MEOW_SECRET, parsed.secret);
  const receiverId = await registerWebPush(client, parsed.config);
  setString(KEY_MEOW_NICKNAME, meow.trim());
  // 三项与通道一起记下：启动/切账号重注册靠它们（WebPushRegistration.startupPushConfig），
  // 原来不存，重注册就读成了自定义那份。
  setString(KEY_MEOW_ENDPOINT, parsed.config.endpoint);
  setString(KEY_MEOW_P256DH, parsed.config.p256dh);
  setString(KEY_MEOW_AUTH, parsed.config.auth);
  setWebPushChannel(WEBPUSH_MODE_MEOW);
  return { receiverId, secret: parsed.secret };
}

export interface MeowDeregisterOutcome {
  // 非空：中转没删掉这份订阅（已记下，下次登录就绪时自动再删）。
  relayWarning: string;
  // 非空：向 Telegram 注销失败的原因。
  telegramError: string;
}

// 通知中转删掉 subKey 这份映射。返回失败原因，'' = 删掉了。
async function deleteRelaySubscription(subKey: string, secret: string): Promise<string> {
  const request = http.createHttp();
  try {
    const response = await request.request(`${pushRelayBase}/register`, {
      method: http.RequestMethod.DELETE,
      connectTimeout: REQUEST_TIMEOUT_MS,
      readTimeout: REQUEST_TIMEOUT_MS,
      header: authHeader(),
      extraData: JSON.stringify(buildMeowDeleteBody(subKey, secret))
    });
    return meowRelayDeleteSucceeded(response.responseCode) ? '' : `HTTP ${response.responseCode}`;
  } catch (e) {
    return toError(e, str('meow_network_error')).message;
  } finally {
    request.destroy();
  }
}

// 注销分两半，**任意一半生效推送就会停**：中转删掉映射后再投递就是 404；Telegram
// 注销后就不再投递。原来两半都可能被静默跳过（没存 secret 就不发删除、Telegram 失败
// 只记日志），界面却显示「已注销」，推送照旧（issue #196）。现在：
// - 中转那半总是发，只凭 subKey；没删掉就把 subKey 记进待删，下次登录就绪时重试；
// - Telegram 那半的失败原样交给页面显示；
// - 本机的 subKey 一律换新（旧的要么删了、要么在待删里），下次注册是全新订阅。
export async function deregisterMeowPush(
  client: TdClient, subKey: string, secret: string
): Promise<MeowDeregisterOutcome> {
  let relayWarning = '';
  if (meowRelayEnabled() && subKey !== '') {
    const relayError: string = await deleteRelaySubscription(subKey, secret);
    if (relayError !== '') {
      setString(KEY_MEOW_PENDING_DELETE, subKey);
      relayWarning = str('meow_deregister_relay_retry', relayError);
    }
  }
  const telegramError: string = await deregisterWebPush(client);
  setString(KEY_MEOW_SUBKEY, '');
  setString(KEY_MEOW_SECRET, '');
  setString(KEY_MEOW_NICKNAME, '');
  setString(KEY_MEOW_ENDPOINT, '');
  setString(KEY_MEOW_P256DH, '');
  setString(KEY_MEOW_AUTH, '');
  setWebPushChannel('');
  return { relayWarning, telegramError };
}

// 上次注销时中转没删掉的那份映射，再删一次。登录就绪时调，静默失败、下次再来。
export async function retryPendingMeowRelayDelete(): Promise<void> {
  const pending: string = AppStorage.get<string>(KEY_MEOW_PENDING_DELETE) ?? '';
  if (pending === '' || !meowRelayEnabled()) {
    return;
  }
  const relayError: string = await deleteRelaySubscription(pending, '');
  if (relayError !== '') {
    logE(`[meow] pending relay delete still failing: ${relayError}`);
    return;
  }
  // 期间又记了别的待删（不太可能）就别清掉它。
  if ((AppStorage.get<string>(KEY_MEOW_PENDING_DELETE) ?? '') === pending) {
    setString(KEY_MEOW_PENDING_DELETE, '');
  }
  logI('[meow] pending relay delete done');
}
