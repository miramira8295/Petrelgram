// 运行日志的上报。缓冲本身在 util/log——那一层被 148 个文件引用，依赖只有
// CoreFileKit；碰网络和端点配置的是这里。
//
// **必须由用户主动触发。** 这份日志含 [StoreDiag] 的消息 id 这类东西，属于聊天
// 痕迹，和崩溃记录（不含任何用户内容、默认自动上报）不是一回事。所以这里只提供
// "发出去"这个能力，什么时候发由设置页里用户点的那一下决定，且点之前要把发什么
// 说清楚。

import { http } from '@kit.NetworkKit';
import { crashReportBase, crashReportToken } from '../tdkit/ApiCredentials';
import { diagLogText } from '../util/log';

const UPLOAD_TIMEOUT_MS: number = 15000;

export interface DiagUploadResult {
  ok: boolean;
  // 失败时给用户看的原因（HTTP 码或异常信息）。成功时为空。
  reason: string;
}

export function diagUploadConfigured(): boolean {
  return crashReportBase !== '' && crashReportToken !== '';
}

// note 是用户可选填的一句话——"我点了转发之后就白屏了"这种，往往比日志本身
// 更能定位。snapshot 是环境快照，由调用方组装。
export function uploadDiagLog(note: string, snapshot: string): Promise<DiagUploadResult> {
  if (!diagUploadConfigured()) {
    return Promise.resolve({ ok: false, reason: 'not-configured' } as DiagUploadResult);
  }
  const request = http.createHttp();
  const body: string = JSON.stringify({
    note, snapshot, lines: diagLogText()
  } as Record<string, string>);
  const options: http.HttpRequestOptions = {
    method: http.RequestMethod.POST,
    header: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${crashReportToken}`
    } as Record<string, string>,
    extraData: body,
    connectTimeout: UPLOAD_TIMEOUT_MS,
    readTimeout: UPLOAD_TIMEOUT_MS
  };
  return request.request(`${crashReportBase}/log`, options)
    .then((res: http.HttpResponse): DiagUploadResult => {
      request.destroy();
      const ok: boolean = res.responseCode >= 200 && res.responseCode < 300;
      return { ok, reason: ok ? '' : `HTTP ${res.responseCode}` } as DiagUploadResult;
    }).catch((e: Error): DiagUploadResult => {
      request.destroy();
      return { ok: false, reason: e.message } as DiagUploadResult;
    });
}
