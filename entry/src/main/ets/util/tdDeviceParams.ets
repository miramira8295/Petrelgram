// setTdlibParameters 里交代给 Telegram 的设备三项：机型、系统版本、应用版本。
// 它们会出现在「设置 → 设备」（活跃会话）列表里，别的客户端也看得到。
//
// issue #147：这三项原来写死在 AuthService 里——'HarmonyOS Device'、'1.3.1'，
// 系统版本压根没传（TDLib 拿 uname 补成「HongMeng Kernel 1.13.0」）。版本号靠
// 发版时手改，忘一次就一直陈旧，所以改成运行时从包信息和 deviceInfo 里读。
//
// 本文件只有纯函数，**不 import 任何 kit**：宿主单测里 deviceInfo 是读不到真值
// 的设备常量（和 diagLogHeader 同一个理由）。真正去读的那层在
// tdDeviceParamsReader.ets。

export interface TdDeviceParams {
  deviceModel: string;
  systemVersion: string;
  applicationVersion: string;
}

// 原始读数。字符串空串、数字 0 都表示「没取到」。
export interface DeviceFacts {
  marketName: string;
  productModel: string;
  distributionOSVersion: string;
  osFullName: string;
  sdkApiVersion: number;
  versionName: string;
}

// TDLib 拒绝空的 device_model / application_version（setTdlibParameters 直接
// 报错，登录卡死），所以兜底值必须非空。
export const FALLBACK_DEVICE_MODEL: string = 'HarmonyOS Device';
export const FALLBACK_APP_VERSION: string = 'unknown';
// 固定写 HarmonyOS 而不读 distributionOSName：本应用只跑在 HarmonyOS 上（HDS、
// HMS 一堆依赖），而那个字段由发行方定义、各机型返回什么未经实测。
const SYSTEM_NAME: string = 'HarmonyOS';
// osFullName 形如 OpenHarmony-5.0.0.102(SP3)，只留后半段。
const OS_FULL_NAME_PREFIX: string = 'OpenHarmony-';

export const FALLBACK_TD_DEVICE_PARAMS: TdDeviceParams = {
  deviceModel: FALLBACK_DEVICE_MODEL,
  systemVersion: SYSTEM_NAME,
  applicationVersion: FALLBACK_APP_VERSION
};

function firstNonEmpty(candidates: string[], fallback: string): string {
  for (const c of candidates) {
    if (c.trim() !== '') {
      return c.trim();
    }
  }
  return fallback;
}

function osVersionText(facts: DeviceFacts): string {
  const full: string = facts.osFullName.startsWith(OS_FULL_NAME_PREFIX)
    ? facts.osFullName.substring(OS_FULL_NAME_PREFIX.length)
    : facts.osFullName;
  return firstNonEmpty([facts.distributionOSVersion, full], '');
}

// 系统版本带上 API 号：同一个版本号在不同机型上功能开关不一样（沉浸光感要
// 26、图标自选要 26），排查用户反馈时这个数比版本号更有用。
export function resolveTdDeviceParams(facts: DeviceFacts): TdDeviceParams {
  const version: string = osVersionText(facts);
  const api: string = facts.sdkApiVersion > 0 ? ` (API ${facts.sdkApiVersion})` : '';
  const systemVersion: string = version === ''
    ? `${SYSTEM_NAME}${api}`
    : `${SYSTEM_NAME} ${version}${api}`;
  return {
    deviceModel: firstNonEmpty([facts.marketName, facts.productModel], FALLBACK_DEVICE_MODEL),
    systemVersion: systemVersion,
    applicationVersion: firstNonEmpty([facts.versionName], FALLBACK_APP_VERSION)
  };
}
