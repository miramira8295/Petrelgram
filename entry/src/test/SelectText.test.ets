import { describe, it, expect } from '@ohos/hypium';
import { TdClient } from '../main/ets/tdkit/TdClient';
import { TdObject, TdBridge } from '../main/ets/tdkit/TdTypes';
import { UserStore } from '../main/ets/store/UserStore';
import { buildMessageEntry, cloneMessage, MessageEntry } from '../main/ets/store/MessageEntry';
import { EMPTY_SELECT_TEXT, selectTextPayload, SelectTextPayload }
  from '../main/ets/pages/chat/SelectTextOverlay';

class FakeBridge implements TdBridge {
  onReceive: (json: string) => void = (): void => {};
  init(cb: (json: string) => void): void { this.onReceive = cb; }
  send(json: string): void {}
}

function entryOf(text: string): MessageEntry {
  const bridge = new FakeBridge();
  const client = new TdClient(bridge);
  const users = new UserStore(client);
  client.start();
  const ft: TdObject = { '@type': 'formattedText' };
  ft['text'] = text;
  const content: TdObject = { '@type': 'messageText' };
  content['text'] = ft;
  const sender: TdObject = { '@type': 'messageSenderUser' };
  sender['user_id'] = 7;
  const m: TdObject = { '@type': 'message' };
  m['id'] = 1; m['is_outgoing'] = false; m['sender_id'] = sender; m['date'] = 100;
  m['content'] = content;
  return cloneMessage(buildMessageEntry(m, users));
}

export default function selectTextTest() {
  describe('selectTextPayload', () => {
    it('正文和实体按引用带过来，不复制', 0, (): void => {
      const e = entryOf('hello');
      const p: SelectTextPayload = selectTextPayload(e);
      expect(p.text).assertEqual('hello');
      expect(p.entities === e.textEntities).assertTrue();
      expect(p.emojiIds === e.inlineCustomEmojiIds).assertTrue();
    });

    // 界面上看不见的东西不该出现在选择层里——用户点「隐藏译文」之后再点
    // 「选择文本」，层里就不该冒出那段译文。
    it('译文被隐藏时不带进选择层', 0, (): void => {
      const e = entryOf('hello');
      e.translatedText = '你好';
      e.translationHidden = true;
      expect(selectTextPayload(e).translatedText).assertEqual('');
    });

    it('译文显示时带进选择层', 0, (): void => {
      const e = entryOf('hello');
      e.translatedText = '你好';
      e.translationHidden = false;
      expect(selectTextPayload(e).translatedText).assertEqual('你好');
    });

    // 引用块画不画只看有没有被回复的消息，不看引用文本到没到——异步取回来的
    // 引用内容晚一拍，条件写成 replyText !== '' 会让引用块在浮层里凭空出现。
    it('有回复目标就画引用块，与引用文本是否到达无关', 0, (): void => {
      const e = entryOf('hello');
      e.replyToMessageId = 55;
      e.replyText = '';
      expect(selectTextPayload(e).hasReply).assertTrue();
      e.replyToMessageId = 0;
      expect(selectTextPayload(e).hasReply).assertFalse();
    });

    it('EMPTY 是"没打开"的空值，不能带任何内容', 0, (): void => {
      expect(EMPTY_SELECT_TEXT.text).assertEqual('');
      expect(EMPTY_SELECT_TEXT.translatedText).assertEqual('');
      expect(EMPTY_SELECT_TEXT.hasReply).assertFalse();
      expect(EMPTY_SELECT_TEXT.entities.length).assertEqual(0);
    });
  });
}
