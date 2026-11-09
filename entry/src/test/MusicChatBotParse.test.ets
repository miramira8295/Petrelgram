import { describe, expect, it } from '@ohos/hypium';
import { TdObject } from '../main/ets/tdkit/TdTypes';
import {
  ChatBotHit, ChatBotListLine, inlineButtonData, isChatBotListMessage, parseChatBotList,
  parseNumberedList
} from '../main/ets/util/musicChatBotParse';

// 会话式音乐机器人回复的解析（2026-09-20）。样本抄自 @music_v1bot 的真机回复。
//
// 这两个 bot 的内联模式只搜不给文件（四次不同角度实测 audio=0），拿歌只能在
// 私聊里发 /search、然后点它回复里的编号按钮。格式是 bot 自己排的、没有契约，
// 所以这些用例同时钉住两件事：正常样本要解析对，**格式变了要解析成空**
// （调用方据此明确报错，而不是静默当成"没搜到"）。

const REAL_TEXT: string = '搜索源 网易云音乐，当前为第1页，搜索结果如下：\n'
  + '1. 想你就写信 (Live) 周杰伦 李硕 张鑫\n'
  + '2. 想你就写信 杜宣达\n'
  + '3. 想你就写信 (Live版) 张钰琪 张碧晨\n'
  + '4. 想你就写信(曹杨版) 小熊的皮卡丘';

function callbackButton(text: string, data: string): TdObject {
  const type: TdObject = { '@type': 'inlineKeyboardButtonTypeCallback' };
  type['data'] = data;
  const button: TdObject = { '@type': 'inlineKeyboardButton' };
  button['text'] = text;
  button['type'] = type;
  return button;
}

function urlButton(text: string, url: string): TdObject {
  const type: TdObject = { '@type': 'inlineKeyboardButtonTypeUrl' };
  type['url'] = url;
  const button: TdObject = { '@type': 'inlineKeyboardButton' };
  button['text'] = text;
  button['type'] = type;
  return button;
}

function listMessage(text: string, buttons: TdObject[]): TdObject {
  const formatted: TdObject = { '@type': 'formattedText' };
  formatted['text'] = text;
  const content: TdObject = { '@type': 'messageText' };
  content['text'] = formatted;
  const markup: TdObject = { '@type': 'replyMarkupInlineKeyboard' };
  markup['rows'] = [buttons];
  const message: TdObject = { '@type': 'message' };
  message['content'] = content;
  message['reply_markup'] = markup;
  return message;
}

export default function musicChatBotParseTest() {
  describe('parseNumberedList', () => {
    it('reads_the_real_sample', 0, () => {
      const lines: ChatBotListLine[] = parseNumberedList(REAL_TEXT);
      expect(lines.length).assertEqual(4);
      expect(lines[0].index).assertEqual(1);
      expect(lines[0].label).assertEqual('想你就写信 (Live) 周杰伦 李硕 张鑫');
      expect(lines[3].index).assertEqual(4);
      // 表头那一行没有编号，不能混进来。
      expect(lines[0].label.includes('搜索源')).assertFalse();
    });

    it('tolerates_chinese_punctuation_and_parens', 0, () => {
      const lines: ChatBotListLine[] = parseNumberedList('1、甲\n2) 乙');
      expect(lines.length).assertEqual(2);
      expect(lines[1].label).assertEqual('乙');
    });

    it('returns_empty_for_unnumbered_text', 0, () => {
      expect(parseNumberedList('没有搜索到结果').length).assertEqual(0);
      expect(parseNumberedList('').length).assertEqual(0);
    });
  });

  describe('inlineButtonData', () => {
    it('keeps_only_callback_buttons', 0, () => {
      const markup: TdObject = { '@type': 'replyMarkupInlineKeyboard' };
      markup['rows'] = [[callbackButton('1', 'YWJj'), urlButton('打开', 'https://x')]];
      const map: Map<string, string> = inlineButtonData(markup);
      expect(map.size).assertEqual(1);
      expect(map.get('1')).assertEqual('YWJj');
      // 链接按钮点了不会让 bot 发歌，不能收。
      expect(map.has('打开')).assertFalse();
    });

    it('ignores_other_markups', 0, () => {
      const other: TdObject = { '@type': 'replyMarkupShowKeyboard' };
      expect(inlineButtonData(other).size).assertEqual(0);
      expect(inlineButtonData(undefined).size).assertEqual(0);
    });
  });

  describe('parseChatBotList', () => {
    it('pairs_lines_with_buttons_by_number_not_position', 0, () => {
      // 按钮故意打乱顺序：对应关系必须按按钮文字上的数字走。
      const message: TdObject = listMessage(REAL_TEXT, [
        callbackButton('3', 'ZA=='), callbackButton('1', 'YQ=='),
        callbackButton('4', 'ZQ=='), callbackButton('2', 'Yg==')
      ]);
      const hits: ChatBotHit[] = parseChatBotList(message);
      expect(hits.length).assertEqual(4);
      expect(hits[0].index).assertEqual(1);
      expect(hits[0].callbackData).assertEqual('YQ==');
      expect(hits[0].label).assertEqual('想你就写信 (Live) 周杰伦 李硕 张鑫');
      expect(hits[2].index).assertEqual(3);
      expect(hits[2].callbackData).assertEqual('ZA==');
    });

    it('drops_lines_without_a_button', 0, () => {
      const message: TdObject = listMessage(REAL_TEXT, [callbackButton('2', 'Yg==')]);
      const hits: ChatBotHit[] = parseChatBotList(message);
      expect(hits.length).assertEqual(1);
      expect(hits[0].index).assertEqual(2);
    });

    it('returns_empty_when_the_format_changed', 0, () => {
      // 这三种都必须是空，调用方据此报「读不懂 bot 的回复」而不是「没搜到」。
      expect(parseChatBotList(listMessage('没有编号的回复', [callbackButton('1', 'YQ==')]))
        .length).assertEqual(0);
      expect(parseChatBotList(listMessage(REAL_TEXT, [])).length).assertEqual(0);
      expect(parseChatBotList(null).length).assertEqual(0);
    });

    it('ignores_non_text_messages', 0, () => {
      const audio: TdObject = { '@type': 'message' };
      audio['content'] = { '@type': 'messageAudio' } as TdObject;
      expect(parseChatBotList(audio).length).assertEqual(0);
      expect(isChatBotListMessage(audio)).assertFalse();
    });

    it('isChatBotListMessage_recognises_the_real_reply', 0, () => {
      expect(isChatBotListMessage(listMessage(REAL_TEXT, [callbackButton('1', 'YQ==')])))
        .assertTrue();
    });
  });
}
