import { describe, it, expect } from '@ohos/hypium';
import {
  DraftCache, ParsedTdDraft, draftPreviewOf, parseTdDraftMessage, shouldAdoptServerDraft
} from '../main/ets/util/draftCache';
import { TdObject } from '../main/ets/tdkit/TdTypes';

// 用户报：输入一堆文字后返回再进来直接被清空了；且列表该显示已输入的内容。
// 真机日志（1.4.7.2）：`[Draft] save len=3` 之后同一会话 `restore serverLen=0`
// ——setChatDraftMessage 是 fire-and-forget，新页面的 getChat 抢在它前面拿到了
// 还没落草稿的 chat 对象。本地缓存把恢复这一步与服务端往返解耦。
export default function draftCacheTest(): void {
  describe('draftCache', (): void => {
    it('存取：按会话隔离，空串等于清除', 0, (): void => {
      const c: DraftCache = new DraftCache();
      c.put(1, 'hello');
      c.put(2, '');
      expect(c.get(1)).assertEqual('hello');
      expect(c.get(2)).assertEqual('');
      expect(c.get(3)).assertEqual('');
      c.put(1, '');
      expect(c.get(1)).assertEqual('');
    });
    it('序列化往返：进程重启后草稿还在', 0, (): void => {
      const c: DraftCache = new DraftCache();
      c.put(10, 'a\nb');
      c.put(-100200, '带空格 的文本');
      const restored: DraftCache = new DraftCache();
      restored.load(c.serialize());
      expect(restored.get(10)).assertEqual('a\nb');
      expect(restored.get(-100200)).assertEqual('带空格 的文本');
    });
    it('坏数据不炸：空串 / 非法 JSON / 非对象一律当空缓存', 0, (): void => {
      const c: DraftCache = new DraftCache();
      c.load('');
      c.load('{ not json');
      c.load('[1,2,3]');
      expect(c.get(1)).assertEqual('');
    });
    it('列表预览：折行压成一行、超长截断，空草稿返回空', 0, (): void => {
      expect(draftPreviewOf('一行', 20)).assertEqual('一行');
      expect(draftPreviewOf('第一行\n第二行', 20)).assertEqual('第一行 第二行');
      expect(draftPreviewOf('abcdefghij', 4)).assertEqual('abcd…');
      expect(draftPreviewOf('   ', 20)).assertEqual('');
    });
    it('解析 TDLib 1.8.71 draftMessage：正文、时间与 reply_to', 0, (): void => {
      const ft: TdObject = { '@type': 'formattedText' };
      ft['text'] = 'pc draft';
      const content: TdObject = { '@type': 'draftMessageContentText' };
      content['text'] = ft;
      const replyTo: TdObject = { '@type': 'inputMessageReplyToMessage' };
      replyTo['message_id'] = 1048576;
      const draft: TdObject = { '@type': 'draftMessage' };
      draft['date'] = 1764225000;
      draft['content'] = content;
      draft['reply_to'] = replyTo;

      const parsed: ParsedTdDraft = parseTdDraftMessage(draft);
      expect(parsed.text).assertEqual('pc draft');
      expect(parsed.date).assertEqual(1764225000);
      expect(parsed.replyToId).assertEqual(1048576);

      const empty: ParsedTdDraft = parseTdDraftMessage(undefined);
      expect(empty.text).assertEqual('');
      expect(empty.date).assertEqual(0);
      expect(empty.replyToId).assertEqual(0);
    });
    it('草稿冲突裁决：云端时间更新时覆盖本地，本地更新时保留本地', 0, (): void => {
      expect(shouldAdoptServerDraft('old', 100, 'new from pc', 200)).assertTrue();
      expect(shouldAdoptServerDraft('newer local', 200, 'old pc', 100)).assertFalse();
      expect(shouldAdoptServerDraft('', 0, 'from pc', 0)).assertTrue();
      expect(shouldAdoptServerDraft('local', 200, '', 0)).assertFalse();
    });
  });
}
