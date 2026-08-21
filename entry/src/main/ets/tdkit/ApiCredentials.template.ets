// Copy this file to ApiCredentials.ets (same directory), then generate the packed
// values from your own credentials obtained at https://my.telegram.org/apps :
//
//   node scripts/gen-creds.mjs <api_id> <api_hash>
//
// Paste the three constants it prints below. The real ApiCredentials.ets is
// gitignored — never commit it. Values are obfuscated (not encrypted), which
// only raises the bar against casual extraction from the packaged app.
import { decodeEnv, RuntimeEnv } from './credCodec';

const _n: number = 0;
const _r: number = 0;
const _s: string = '';

const _env: RuntimeEnv = decodeEnv(_n, _r, _s);
export const clientRev: number = _env.id;
export const clientSig: string = _env.token;

// Optional: base URL of a self-hosted push relay for the MeoW push mode
// (WebPushPage). Leave empty to hide the MeoW entry entirely — the app then
// only offers the manual "paste endpoint/p256dh/auth" WebPush mode.
export const pushRelayBase: string = '';
// Bearer token sent on every relay request. Must also be non-empty (along
// with pushRelayBase) for the MeoW entry to appear.
export const pushRelayToken: string = '';

// Optional: base URL of a crash-report collector. Leave empty to disable
// uploading entirely — crashes are still recorded locally either way.
//
// 崩溃上报的接收端。留空则完全不上传（本地记录照常留）。
// 期望接口：POST {crashReportBase}/crash，Content-Type: application/json，
// Authorization: Bearer {crashReportToken}，请求体是一条 CrashRecord
// （见 services/crashReport）。返回 2xx 视为成功，之后不再重发这一条。
//
// 载荷里**没有任何用户内容**：只有时间、应用版本、崩溃类型、前后台、进程存活
// 时长、异常名/信息/堆栈。hilog 与 external_log 刻意不取——那两样含聊天痕迹。
//
// 如果收集端就跑在上面那个推送中转上（推荐），这两行直接引用即可——/crash 和
// /log 走的是中转里同一个 requireToken，校验的就是同一个 RELAY_TOKEN，不必
// 另立一个秘密：
//
//   export const crashReportBase: string = pushRelayBase;
//   export const crashReportToken: string = pushRelayToken;
//
export const crashReportBase: string = '';
export const crashReportToken: string = '';
