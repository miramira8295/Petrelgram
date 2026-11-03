import { describe, expect, it } from '@ohos/hypium';
import { buildMessageEntry, MessageEntry } from '../main/ets/store/MessageEntry';
import { TdBridge, TdObject } from '../main/ets/tdkit/TdTypes';
import { TdClient } from '../main/ets/tdkit/TdClient';
import { UserStore } from '../main/ets/store/UserStore';
import { canRenderLightweightPlainTextRow } from '../main/ets/util/messageBubbleReuse';

// `canRenderLightweightPlainTextRow` 的判据单测。
//
// 这个文件原来测的是同一模块里那套**生产零调用**的复用键算法
// （messageBubbleReuseId 等，9 条用例）。那套算法在 2026-11-02 随死代码一起删掉，
// 文件名与导出名保留下来，只保留仍然活的这条判据的覆盖。
//
// 为什么必须留着：它决定一行走轻量纯文本渲染还是完整富文本树，两个调用方
// （ChatTimelineSession 的 prepare、ChatTimelineHost 的 templateId）必须用同一份
// 结果，否则模板池和实际渲染树会错配。

class FakeBridge implements TdBridge {
  onReceive: (json: string) => void = (): void => {};
  init(cb: (json: string) => void): void { this.onReceive = cb; }
  send(_json: string): void {}
}

function usersOf(): UserStore {
  const bridge = new FakeBridge();
  const client = new TdClient(bridge);
  const users = new UserStore(client);
  client.start();
  const user: TdObject = { '@type': 'user' };
  user['id'] = 7;
  user['first_name'] = 'Ann';
  const update: TdObject = { '@type': 'updateUser' };
  update['user'] = user;
  bridge.onReceive(JSON.stringify(update));
  return users;
}

function textEntry(id: number): MessageEntry {
  const formatted: TdObject = { '@type': 'formattedText' };
  formatted['text'] = `plain-${id}`;
  const content: TdObject = { '@type': 'messageText' };
  content['text'] = formatted;
  const sender: TdObject = { '@type': 'messageSenderUser' };
  sender['user_id'] = 7;
  const message: TdObject = { '@type': 'message' };
  message['id'] = id;
  message['is_outgoing'] = false;
  message['sender_id'] = sender;
  message['date'] = 100;
  message['content'] = content;
  return buildMessageEntry(message, usersOf());
}

export default function plainTextBubbleReuseTest() {
  describe('LightweightPlainTextGate', () => {
    it('纯文本、单成员、非相册才走轻量渲染', 0, () => {
      expect(canRenderLightweightPlainTextRow(textEntry(1), 1, 0)).assertTrue();
    });

    it('相册行不走轻量渲染', 0, () => {
      expect(canRenderLightweightPlainTextRow(textEntry(2), 1, 3)).assertFalse();
    });

    it('多成员行不走轻量渲染', 0, () => {
      expect(canRenderLightweightPlainTextRow(textEntry(3), 2, 0)).assertFalse();
    });

    it('转发过的消息不走轻量渲染', 0, () => {
      const entry: MessageEntry = textEntry(4);
      entry.forwardFrom = 'someone';
      expect(canRenderLightweightPlainTextRow(entry, 1, 0)).assertFalse();
    });

    it('有反应的、带评论的都不走轻量渲染', 0, () => {
      const reacted: MessageEntry = textEntry(5);
      reacted.reactions = [{ emoji: '👍', count: 1, isChosen: false, customEmojiId: '', customEmojiPath: '' }];
      expect(canRenderLightweightPlainTextRow(reacted, 1, 0)).assertFalse();

      const commented: MessageEntry = textEntry(6);
      commented.commentCount = 2;
      expect(canRenderLightweightPlainTextRow(commented, 1, 0)).assertFalse();
    });

    it('有译文的消息不走轻量渲染（要显示译文块）', 0, () => {
      const entry: MessageEntry = textEntry(7);
      entry.translatedText = '译文';
      expect(canRenderLightweightPlainTextRow(entry, 1, 0)).assertFalse();
    });

    it('任一链接预览字段非空都不走轻量渲染', 0, () => {
      const entry: MessageEntry = textEntry(8);
      entry.linkTitle = 'Title';
      expect(canRenderLightweightPlainTextRow(entry, 1, 0)).assertFalse();
    });
  });
}
