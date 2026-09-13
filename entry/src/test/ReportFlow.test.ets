import { describe, it, expect } from '@ohos/hypium';
import {
  parseReportStep, reportRequest, runReportFlow, ReportFlowUi, ReportOption, ReportStep,
  REPORT_OPTION_LIMIT
} from '../main/ets/util/reportFlow';
import { TdObject, TdRequest } from '../main/ets/tdkit/TdTypes';

// 举报流程（issue #201 第 5 条）：消息举报与会话举报走同一个 reportChat，返回
// 三种结果之一，这里把「下一步是什么」从页面里抽成纯函数钉住。

function optionsResult(title: string, ids: string[]): TdObject {
  const r: TdObject = { '@type': 'reportChatResultOptionRequired' };
  r['title'] = title;
  r['options'] = ids.map((id: string): TdObject => {
    const o: TdObject = { '@type': 'reportOption' };
    o['id'] = id; o['text'] = `text-${id}`;
    return o;
  });
  return r;
}

function textResult(optionId: string, optional: boolean): TdObject {
  const r: TdObject = { '@type': 'reportChatResultTextRequired' };
  r['option_id'] = optionId; r['is_optional'] = optional;
  return r;
}

class FakeUi implements ReportFlowUi {
  picked: string[] = [];        // 每次弹选项时选的 id；'' = 取消
  typed: string[] = [];         // 每次要文本时输入的内容；'' = 取消
  toasts: string[] = [];
  pickCalls: number = 0;
  askCalls: number = 0;
  pickOption(_title: string, options: ReportOption[]): Promise<ReportOption | null> {
    const want: string = this.picked[this.pickCalls++] ?? '';
    const hit: ReportOption | undefined = options.find((o: ReportOption): boolean => o.id === want);
    return Promise.resolve(hit ?? null);
  }
  askText(): Promise<string | null> {
    const t: string = this.typed[this.askCalls++] ?? '';
    return Promise.resolve(t === '' ? null : t);
  }
  toast(key: string): void { this.toasts.push(key); }
}

export default function reportFlowTest(): void {
  describe('reportFlow', (): void => {

    it('请求体：会话举报 message_ids 为空，消息举报带 id；option/text 原样透传', 0, (): void => {
      const chatReq: TdRequest = reportRequest({ chatId: -1001, messageIds: [] }, '', '');
      expect(chatReq['@type']).assertEqual('reportChat');
      expect((chatReq['message_ids'] as number[]).length).assertEqual(0);
      const msgReq: TdRequest = reportRequest({ chatId: -1001, messageIds: [42] }, 'abc', 'why');
      expect((msgReq['message_ids'] as number[])[0]).assertEqual(42);
      expect(msgReq['option_id']).assertEqual('abc');
      expect(msgReq['text']).assertEqual('why');
    });

    it('解析：Ok / 选项 / 文本 / 未知 四种形状', 0, (): void => {
      expect(parseReportStep({ '@type': 'reportChatResultOk' }, '').kind).assertEqual('ok');
      const opt: ReportStep = parseReportStep(optionsResult('为什么', ['a', 'b']), '');
      expect(opt.kind).assertEqual('options');
      expect(opt.title).assertEqual('为什么');
      expect(opt.options.length).assertEqual(2);
      expect(opt.options[1].text).assertEqual('text-b');
      const txt: ReportStep = parseReportStep(textResult('a', false), 'a');
      expect(txt.kind).assertEqual('text');
      expect(txt.optionId).assertEqual('a');
      expect(txt.textOptional).assertFalse();
      expect(parseReportStep({ '@type': 'somethingNew' }, '').kind).assertEqual('unsupported');
    });

    it('选项超过上限只展示前 N 个（showActionMenu 的按钮上限）', 0, (): void => {
      const ids: string[] = [];
      for (let i = 0; i < REPORT_OPTION_LIMIT + 3; i++) { ids.push(`o${i}`); }
      expect(parseReportStep(optionsResult('t', ids), '').options.length).assertEqual(REPORT_OPTION_LIMIT);
    });

    it('完整路径：选原因 → 必填说明 → 提交成功', 0, async (): Promise<void> => {
      const sent: TdRequest[] = [];
      const send = (req: TdRequest): Promise<TdObject> => {
        sent.push(req);
        if (sent.length === 1) { return Promise.resolve(optionsResult('t', ['spam', 'other'])); }
        if (sent.length === 2) { return Promise.resolve(textResult('other', false)); }
        return Promise.resolve({ '@type': 'reportChatResultOk' } as TdObject);
      };
      const ui: FakeUi = new FakeUi();
      ui.picked = ['other']; ui.typed = ['这是详细说明'];
      await runReportFlow(send, { chatId: -1, messageIds: [7] }, ui);
      expect(sent.length).assertEqual(3);
      expect(sent[2]['option_id']).assertEqual('other');
      expect(sent[2]['text']).assertEqual('这是详细说明');
      expect(ui.toasts.join(',')).assertEqual('cpp_report_sent');
    });

    it('可选说明不打扰用户：直接带空文本再提交', 0, async (): Promise<void> => {
      const sent: TdRequest[] = [];
      const send = (req: TdRequest): Promise<TdObject> => {
        sent.push(req);
        return Promise.resolve(sent.length === 1
          ? textResult('spam', true)
          : ({ '@type': 'reportChatResultOk' } as TdObject));
      };
      const ui: FakeUi = new FakeUi();
      await runReportFlow(send, { chatId: -1, messageIds: [7] }, ui, 'spam');
      expect(ui.askCalls).assertEqual(0);
      expect(sent.length).assertEqual(2);
      expect(ui.toasts.join(',')).assertEqual('cpp_report_sent');
    });

    it('用户在选项或文本处取消：静默结束，不再发请求、不 toast', 0, async (): Promise<void> => {
      let calls: number = 0;
      const send = (_req: TdRequest): Promise<TdObject> => {
        calls++;
        return Promise.resolve(calls === 1 ? optionsResult('t', ['a']) : textResult('a', false));
      };
      const cancelAtPick: FakeUi = new FakeUi();
      await runReportFlow(send, { chatId: -1, messageIds: [] }, cancelAtPick);
      expect(calls).assertEqual(1);
      expect(cancelAtPick.toasts.length).assertEqual(0);
      calls = 0;
      const cancelAtText: FakeUi = new FakeUi();
      cancelAtText.picked = ['a'];
      await runReportFlow(send, { chatId: -1, messageIds: [] }, cancelAtText);
      expect(calls).assertEqual(2);
      expect(cancelAtText.toasts.length).assertEqual(0);
    });

    it('空选项列表 / 未知步骤 / 请求失败 各自 toast 对应文案', 0, async (): Promise<void> => {
      const empty: FakeUi = new FakeUi();
      await runReportFlow((_r: TdRequest): Promise<TdObject> => Promise.resolve(optionsResult('t', [])),
        { chatId: -1, messageIds: [] }, empty);
      expect(empty.toasts.join(',')).assertEqual('cpp_report_unsupported');
      const unknown: FakeUi = new FakeUi();
      await runReportFlow((_r: TdRequest): Promise<TdObject> => Promise.resolve({ '@type': 'x' } as TdObject),
        { chatId: -1, messageIds: [] }, unknown);
      expect(unknown.toasts.join(',')).assertEqual('cpp_report_step_unsupported');
      const failed: FakeUi = new FakeUi();
      await runReportFlow((_r: TdRequest): Promise<TdObject> => Promise.reject(new Error('boom')),
        { chatId: -1, messageIds: [] }, failed);
      expect(failed.toasts.join(',')).assertEqual('cpp_report_failed');
    });
  });
}
