import { describe, expect, it } from '@ohos/hypium';
import { SharedItem, SharedPayload } from '../main/ets/util/sharedContent';
import { directShareSteps } from '../main/ets/util/directSharePlan';
import { ShareArrivalHost, sendShareDirectly, remainingDirectShare } from '../main/ets/util/shareArrival';
import { MediaSendItem } from '../main/ets/store/MessageStore';
import { ShareMediaGeometry } from '../main/ets/util/shareLivePhoto';
import { SendProgress } from '../main/ets/util/sendProgress';
import { ForwardMessagesRequestInput } from '../main/ets/util/forwardMessagesRequest';
import { ForwardSendTask } from '../main/ets/util/forwardSendTask';
import { TdObject, TdRequest, TdError } from '../main/ets/tdkit/TdTypes';
import { ShareRow, withSavedTarget, targetDisplayKey } from '../main/ets/util/shareSearch';
import { clearPendingShareIf, peekPendingShare, stashPendingShare, takePendingShare,
  onPendingShareChanged, pendingShareGeneration } from '../main/ets/services/ShareInbox';

function photo(n: number): SharedItem {
  return { kind: 'image', uri: `/photo${n}.jpg`, text: '', title: '', sourceUri: '' };
}
function payload(count: number): SharedPayload {
  const media: SharedItem[] = [];
  for (let i = 0; i < count; i++) { media.push(photo(i)); }
  return { caption: 'caption', media };
}
function row(id: number, title: string): ShareRow {
  return { chatId: id, title, subtitle: '', initials: 'A', avatarPath: '', isSavedMessages: false };
}
class SendHost implements ShareArrivalHost {
  permissionDenied: boolean = false;
  checkPermissions: (payload: SharedPayload) => Promise<void> = (_payload: SharedPayload): Promise<void> =>
    this.permissionDenied ? Promise.reject(new Error('denied')) : Promise.resolve();
  calls: string[] = [];
  failedKind: string = '';
  mediaCounts: number[] = [];
  captions: string[] = [];
  appendMedia: (items: MediaSendItem[]) => number = (): number => 0;
  setDraft: (text: string) => void = (): void => {};
  draftText: () => string = (): string => '';
  scrollToBottom: () => void = (): void => {};
  private send(kind: string, caption: string): Promise<void> {
    this.calls.push(kind);
    this.captions.push(caption);
    return this.failedKind === kind ? Promise.reject(new Error('rejected')) : Promise.resolve();
  }
  sendText: (text: string) => Promise<void> = (text: string): Promise<void> => this.send('text', text);
  sendDocument: (path: string, caption: string) => Promise<void> =
    (_path: string, caption: string): Promise<void> => this.send('file', caption);
  sendAudio: (path: string, caption: string) => Promise<void> =
    (_path: string, caption: string): Promise<void> => this.send('audio', caption);
  sendMedia: (items: MediaSendItem[], caption: string) => Promise<void> =
    (items: MediaSendItem[], caption: string): Promise<void> => {
      this.mediaCounts.push(items.length);
      return this.send('media', caption);
    };
}
function task(ids: number[]): ForwardSendTask {
  return new ForwardSendTask({ toChatId: 0, fromChatId: 10, messageIds: ids, threadRootId: 0,
    sendCopy: false, removeCaption: false, canRemoveCaption: true });
}
function accepted(req: TdRequest): TdObject {
  const result: TdObject = { '@type': 'messages' };
  result['messages'] = (req['message_ids'] as number[]).map((id: number): TdObject => {
    const message: TdObject = { '@type': 'message' };
    message['id'] = id + 1000;
    return message;
  });
  return result;
}

export default function shareWorkflowTest() {
  describe('share workflow', () => {
    it('权限预检仅读取转发重试尚未成功的消息', 0, async () => {
      const forwarding = task([1, 2]);
      expect(forwarding.sourceChatId()).assertEqual(10);
      expect(forwarding.remainingMessageIds(20)).assertDeepEquals([1, 2]);
      try {
        await forwarding.send(20, async (_request: TdRequest): Promise<TdObject> => {
          const message: TdObject = { '@type': 'message', 'id': 101 };
          const response: TdObject = { '@type': 'messages', 'messages': [message, null] };
          return response;
        });
      } catch (_error) {}
      expect(forwarding.remainingMessageIds(20)).assertDeepEquals([2]);
      expect(forwarding.remainingMessageIds(30)).assertDeepEquals([1, 2]);
    });

    it('分享预检拒绝整组时第一批也不能先发', 0, async () => {
      const host = new SendHost(); host.permissionDenied = true;
      let failed: boolean = false;
      try { await sendShareDirectly(payload(12), host); } catch (_error) { failed = true; }
      expect(failed).assertTrue(); expect(host.calls.length).assertEqual(0);
    });
    it('分享预检等待期间关闭会话则不发送', 0, async () => {
      const host = new SendHost(); let active: boolean = true;
      host.checkPermissions = async (_payload: SharedPayload): Promise<void> => { active = false; };
      let failed: boolean = false;
      try { await sendShareDirectly(payload(2), host, new Map(), new SendProgress(), (): boolean => active); }
      catch (_error) { failed = true; }
      expect(failed).assertTrue(); expect(host.calls.length).assertEqual(0);
    });

    it('收藏不在加载窗口也补齐，且去重并覆盖原始昵称', 0, () => {
      const rows = withSavedTarget([row(2, 'B'), row(1, 'My name'), row(1, 'duplicate')], 1, '我的收藏');
      expect(rows.map((r: ShareRow): number => r.chatId)).assertDeepEquals([1, 2]);
      expect(rows[0].title).assertEqual('我的收藏');
      expect(rows[0].isSavedMessages).assertTrue();
      expect(withSavedTarget([], 1, '我的收藏').length).assertEqual(1);
      expect(withSavedTarget([], 0, '我的收藏').length).assertEqual(0);
    });
    it('头像展示签名忽略最后消息，包含收藏身份和首字母', 0, () => {
      const r = row(1, 'A');
      const first = targetDisplayKey(r);
      r.subtitle = 'new incoming message';
      expect(targetDisplayKey(r)).assertEqual(first);
      r.isSavedMessages = true;
      expect(targetDisplayKey(r) === first).assertFalse();
      const second = targetDisplayKey(r);
      r.initials = 'B';
      expect(targetDisplayKey(r) === second).assertFalse();
    });
    it('20张图片全部分批，只有首批带说明', 0, async () => {
      const host = new SendHost();
      await sendShareDirectly(payload(20), host);
      expect(host.mediaCounts).assertDeepEquals([9, 9, 2]);
      expect(host.captions).assertDeepEquals(['caption', '', '']);
    });
    it('GIF与普通相册分开，避免重试时隐藏的部分发送', 0, () => {
      const p = payload(3);
      p.media[1].uri = '/animation.gif';
      const steps = directShareSteps(p);
      expect(steps.length).assertEqual(3);
      expect(steps[1].items[0].uri).assertEqual('/animation.gif');
      expect(steps[2].caption).assertEqual('');
    });
    it('纯文字拒绝不会返回发送成功', 0, async () => {
      const host = new SendHost(); host.failedKind = 'text';
      let rejected: boolean = false;
      try { await sendShareDirectly(payload(0), host); } catch (_) { rejected = true; }
      expect(rejected).assertTrue();
    });
    it('文件拒绝不会返回发送成功，后续音频不会越过失败步骤', 0, async () => {
      const host = new SendHost(); host.failedKind = 'file';
      const p = payload(2); p.media[0].kind = 'file'; p.media[1].kind = 'audio';
      let rejected: boolean = false;
      try { await sendShareDirectly(p, host); } catch (_) { rejected = true; }
      expect(rejected).assertTrue();
      expect(host.calls).assertDeepEquals(['file']);
    });
    it('音频拒绝不会返回发送成功', 0, async () => {
      const host = new SendHost(); host.failedKind = 'audio';
      const p = payload(1); p.media[0].kind = 'audio';
      let rejected: boolean = false;
      try { await sendShareDirectly(p, host); } catch (_) { rejected = true; }
      expect(rejected).assertTrue();
    });
    it('文件部分成功后重试只发剩余步骤', 0, async () => {
      const host = new SendHost(); host.failedKind = 'audio';
      const p = payload(2); p.media[0].kind = 'file'; p.media[1].kind = 'audio';
      const progress = new SendProgress();
      try { await sendShareDirectly(p, host, new Map<string, ShareMediaGeometry>(), progress); } catch (_) {}
      const remaining = remainingDirectShare(p, progress);
      expect(remaining.media.length).assertEqual(1);
      expect(remaining.caption).assertEqual('');
      host.failedKind = '';
      await sendShareDirectly(p, host, new Map<string, ShareMediaGeometry>(), progress);
      expect(host.calls).assertDeepEquals(['file', 'audio', 'audio']);
    });
    it('已成功目标再次执行同一任务也不重发', 0, async () => {
      const host = new SendHost(); const progress = new SendProgress(); const p = payload(1);
      await sendShareDirectly(p, host, new Map<string, ShareMediaGeometry>(), progress);
      await sendShareDirectly(p, host, new Map<string, ShareMediaGeometry>(), progress);
      expect(host.calls.length).assertEqual(1);
    });
    it('关闭发送任务后不启动下一批', 0, async () => {
      const host = new SendHost(); let active: boolean = true;
      host.sendMedia = (): Promise<void> => { active = false; host.calls.push('media'); return Promise.resolve(); };
      let rejected: boolean = false;
      try { await sendShareDirectly(payload(20), host, new Map<string, ShareMediaGeometry>(),
        new SendProgress(), (): boolean => active); } catch (_) { rejected = true; }
      expect(rejected).assertTrue(); expect(host.calls.length).assertEqual(1);
    });
    it('超时步骤禁止盲重试，但普通拒绝允许再试', 0, async () => {
      const progress = new SendProgress(); let calls: number = 0;
      for (let i = 0; i < 2; i++) {
        try { await progress.run(0, (): Promise<void> => { calls++; return Promise.reject(new TdError(-1, 'timeout')); }); }
        catch (_) {}
      }
      expect(calls).assertEqual(1); expect(progress.hasUncertain()).assertTrue();
    });
    it('转发第二批失败后不重复第一批', 0, async () => {
      const ids: number[] = []; for (let i = 1; i <= 101; i++) { ids.push(i); }
      const t = task(ids); const sizes: number[] = []; let failed: boolean = false;
      const port = (req: TdRequest): Promise<TdObject> => {
        const part = req['message_ids'] as number[]; sizes.push(part.length);
        if (part[0] === 101 && !failed) { failed = true; return Promise.reject(new TdError(400, 'rejected')); }
        return Promise.resolve(accepted(req));
      };
      try { await t.send(20, port); } catch (_) {}
      await t.send(20, port);
      expect(sizes).assertDeepEquals([100, 1, 1]);
    });
    it('多目标转发重试不重发已成功目标', 0, async () => {
      const t = task([1]); const targets: number[] = [];
      const port = (req: TdRequest): Promise<TdObject> => {
        targets.push(req['chat_id'] as number); return Promise.resolve(accepted(req));
      };
      await t.send(20, port); await t.send(30, port); await t.send(20, port);
      expect(targets).assertDeepEquals([20, 30]);
    });
    it('转发任务冻结选项与消息，后续修改原对象不改变请求', 0, async () => {
      const input: ForwardMessagesRequestInput = { toChatId: 0, fromChatId: 10, messageIds: [3, 1], threadRootId: 0,
        sendCopy: false, removeCaption: false, canRemoveCaption: true };
      const t = new ForwardSendTask(input);
      input.sendCopy = true; input.messageIds.push(7);
      await t.send(20, (req: TdRequest): Promise<TdObject> => {
        expect(req['send_copy']).assertFalse(); expect(req['message_ids']).assertDeepEquals([1, 3]);
        return Promise.resolve(accepted(req));
      });
    });
    it('转发null结果只重试未成功消息', 0, async () => {
      const t = task([1, 2]); let calls: number = 0;
      const port = (req: TdRequest): Promise<TdObject> => {
        calls++; const response = accepted(req);
        if (calls === 1) {
          const sent = response['messages'] as (TdObject | null)[]; sent[1] = null;
        } else { expect(req['message_ids']).assertDeepEquals([2]); }
        return Promise.resolve(response);
      };
      try { await t.send(20, port); } catch (_) {}
      await t.send(20, port); expect(calls).assertEqual(2);
    });
    it('转发超时不再次发同一目标', 0, async () => {
      const t = task([1]); let calls: number = 0;
      for (let i = 0; i < 2; i++) {
        try { await t.send(20, (): Promise<TdObject> => { calls++; return Promise.reject(new TdError(-1, 'timeout')); }); }
        catch (_) {}
      }
      expect(calls).assertEqual(1); expect(t.hasUncertain()).assertTrue();
    });
    it('旧分享完成不能取走新载荷', 0, () => {
      const previous = takePendingShare(); const a = payload(1); const b = payload(2);
      stashPendingShare(a); stashPendingShare(b);
      expect(clearPendingShareIf(a)).assertFalse(); expect(peekPendingShare() === b).assertTrue();
      expect(clearPendingShareIf(b)).assertTrue(); expect(peekPendingShare() === null).assertTrue();
      if (previous !== null) { stashPendingShare(previous); }
    });
    it('新分享通知旧面板失效，退订后不再触达', 0, () => {
      const previous = takePendingShare(); let calls: number = 0;
      const unsub = onPendingShareChanged((): void => { calls++; });
      stashPendingShare(payload(1)); unsub(); stashPendingShare(payload(2));
      expect(calls).assertEqual(1); takePendingShare();
      if (previous !== null) { stashPendingShare(previous); }
    });
    it('新分享即使已被取走仍会使旧直发的代际失效', 0, () => {
      const previous = takePendingShare();
      const generation: number = pendingShareGeneration();
      stashPendingShare(payload(1)); takePendingShare();
      expect(pendingShareGeneration() > generation).assertTrue();
      if (previous !== null) { stashPendingShare(previous); }
    });
  });
}
