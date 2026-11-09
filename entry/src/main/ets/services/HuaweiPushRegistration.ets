import { pushService } from '@kit.PushKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { TdClient } from '../tdkit/TdClient';
import { TdObject, TdRequest, TdError } from '../tdkit/TdTypes';

// 探针：验证 Telegram 官方服务器能否直接投递到华为 Push Kit 通道。
//
// 实测确认不通 —— Push Token 由本应用自己的 AGC 应用身份签发，而实际发推送的
// 是 Telegram 官方服务器，它只持有
// Telegram 自己的 HMS 凭证，两者的发送方身份对不上。`registerDevice` 也没有
// 任何字段可以覆盖发送方。这里把 getToken 与 registerDevice 的完整结果
// （含错误码）都保留下来，用于证实或证伪这个判断，本身就是本次验证的产出。
//
// 参照 WebPushRegistration.ets 的写法：不静默吞错误，返回结构化结果给 UI，
// 不只是打日志。

const REGISTER_TIMEOUT_MS: number = 15000;

export interface HuaweiPushResult {
  success: boolean;
  token: string; // 成功时的 push token；取 token 失败则为空串
  pushReceiverId: string; // registerDevice 成功时 TDLib 返回的 id；否则为空串
  errorCode: number; // 取 token 或 registerDevice 失败时的错误码；成功为 0
  errorMessage: string; // 失败时的完整错误文案；成功为空串
}

function tokenFailure(code: number, message: string): HuaweiPushResult {
  return {
    success: false,
    token: '',
    pushReceiverId: '',
    errorCode: code,
    errorMessage: message
  };
}

function registerFailure(token: string, code: number, message: string): HuaweiPushResult {
  return {
    success: false,
    token,
    pushReceiverId: '',
    errorCode: code,
    errorMessage: message
  };
}

export function buildRegisterRequest(token: string): TdRequest {
  const deviceToken: TdObject = { '@type': 'deviceTokenHuaweiPush' };
  deviceToken['token'] = token;
  deviceToken['encrypt'] = false;
  const request: TdRequest = { '@type': 'registerDevice' };
  request['device_token'] = deviceToken;
  request['other_user_ids'] = [];
  return request;
}

export function parseReceiverId(result: TdObject): string {
  const id = result['id'];
  return id !== undefined ? `${id}` : '';
}

// 取 token 并向 TDLib 注册。两步中任意一步失败都会带着完整的错误码/文案
// resolve（不是 reject）——调用方按 result.success 分支即可，不需要 try/catch。
export function registerHuaweiPush(client: TdClient): Promise<HuaweiPushResult> {
  return pushService.getToken()
    .then((token: string): Promise<HuaweiPushResult> => {
      if (token === '') {
        return Promise.resolve(tokenFailure(0, 'pushService.getToken resolved with an empty token'));
      }
      return client.send(buildRegisterRequest(token), REGISTER_TIMEOUT_MS)
        .then((res: TdObject): HuaweiPushResult => {
          return {
            success: true,
            token,
            pushReceiverId: parseReceiverId(res),
            errorCode: 0,
            errorMessage: ''
          };
        })
        .catch((e: TdError): HuaweiPushResult => registerFailure(token, e.code, e.message));
    })
    .catch((e: BusinessError): HuaweiPushResult => tokenFailure(e.code, e.message));
}
