import { TdObject, TdRequest } from '../tdkit/TdTypes';
import { logE } from './log';

// 举报流程（会话与消息共用）。
//
// TDLib 的举报只有一个入口 `reportChat`：不带 message_ids 是举报会话，带了就是
// 举报这些消息。服务端把原因做成一棵树，每次调用返回三种结果之一——
//   · reportChatResultOk              举报已受理
//   · reportChatResultOptionRequired  要用户在 options 里选一个原因，再带 option_id 调
//   · reportChatResultTextRequired    要用户补一段说明（is_optional 表示可不填）
// 这里把「下一步是什么」抽成纯函数、把「怎么把下一步呈现给用户」抽成接口，
// 页面只负责把 UI 接上。issue #201 第 5 条之前消息举报是个 toast 占位，会话
// 举报那份状态机住在 ChatProfilePage 里，现在合成一份。

export interface ReportTarget {
  chatId: number;
  // 空数组 = 举报整个会话。
  messageIds: number[];
}

export interface ReportOption {
  id: string;
  text: string;
}

export interface ReportStep {
  kind: string;   // 'ok' | 'options' | 'text' | 'unsupported'
  title: string;
  options: ReportOption[];
  optionId: string;
  textOptional: boolean;
}

// UI 侧要提供的三件事。都返回 Promise 好让流程写成一条直线；null = 用户取消。
export interface ReportFlowUi {
  pickOption(title: string, options: ReportOption[]): Promise<ReportOption | null>;
  askText(): Promise<string | null>;
  // 参数是字符串资源的键（cpp_report_*），由 UI 侧翻译——这样纯逻辑不碰资源。
  toast(key: string): void;
}

// promptAction.showActionMenu 最多 6 个按钮。Telegram 顶层原因一般 6–8 个，
// 超出的截掉；要全量得换 bindSheet 列表，先不做。
export const REPORT_OPTION_LIMIT: number = 6;

export function reportRequest(target: ReportTarget, optionId: string, text: string): TdRequest {
  const req: TdRequest = { '@type': 'reportChat' };
  req['chat_id'] = target.chatId;
  req['option_id'] = optionId;
  req['message_ids'] = target.messageIds.slice();
  req['text'] = text;
  return req;
}

function emptyStep(kind: string): ReportStep {
  return { kind, title: '', options: [], optionId: '', textOptional: false };
}

export function parseReportStep(result: TdObject, requestedOptionId: string): ReportStep {
  const typeName: string = (result['@type'] as string | undefined) ?? '';
  if (typeName === 'reportChatResultOk') {
    return emptyStep('ok');
  }
  if (typeName === 'reportChatResultOptionRequired') {
    const raw: TdObject[] = (result['options'] as TdObject[] | undefined) ?? [];
    const options: ReportOption[] = raw.slice(0, REPORT_OPTION_LIMIT).map((o: TdObject): ReportOption => ({
      id: (o['id'] as string | undefined) ?? '',
      text: (o['text'] as string | undefined) ?? ''
    } as ReportOption));
    const step: ReportStep = emptyStep('options');
    step.title = (result['title'] as string | undefined) ?? '';
    step.options = options;
    return step;
  }
  if (typeName === 'reportChatResultTextRequired') {
    const step: ReportStep = emptyStep('text');
    step.optionId = (result['option_id'] as string | undefined) ?? requestedOptionId;
    step.textOptional = (result['is_optional'] as boolean | undefined) ?? false;
    return step;
  }
  return emptyStep('unsupported');
}

// 走完整棵树。取消（UI 返回 null）就静默结束——用户自己收手，不需要提示。
export async function runReportFlow(
  send: (req: TdRequest) => Promise<TdObject>,
  target: ReportTarget, ui: ReportFlowUi,
  optionId: string = '', text: string = ''
): Promise<void> {
  let result: TdObject;
  try {
    result = await send(reportRequest(target, optionId, text));
  } catch (e) {
    logE(`reportFlow: request failed: ${(e as Error).message}`);
    ui.toast('cpp_report_failed');
    return;
  }
  const step: ReportStep = parseReportStep(result, optionId);
  if (step.kind === 'ok') {
    ui.toast('cpp_report_sent');
    return;
  }
  if (step.kind === 'options') {
    if (step.options.length === 0) {
      ui.toast('cpp_report_unsupported');
      return;
    }
    const chosen: ReportOption | null = await ui.pickOption(step.title, step.options);
    if (chosen === null) {
      return;
    }
    return runReportFlow(send, target, ui, chosen.id, '');
  }
  if (step.kind === 'text') {
    // 可选说明不打扰用户，直接带空文本再提交一次（服务端此时会给 Ok）。
    // 只有必填才弹输入框——举报树里「其他」那一支基本都是必填，之前这里直接
    // 放弃，等于「其他」永远举报不了。
    if (step.textOptional) {
      return runReportFlow(send, target, ui, step.optionId, '');
    }
    const typed: string | null = await ui.askText();
    if (typed === null || typed.trim() === '') {
      return;
    }
    return runReportFlow(send, target, ui, step.optionId, typed.trim());
  }
  ui.toast('cpp_report_step_unsupported');
}
