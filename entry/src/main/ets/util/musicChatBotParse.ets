import { TdObject } from '../tdkit/TdTypes';

// 会话式音乐机器人（@music_v1bot / @Music163bot）回复的解析（2026-09-20）。
//
// 【为什么要解析文本】这两个 bot 的**内联模式只搜不给文件**（2026-09-20 真机
// 四次不同角度验证：裸关键词、`search 词`、歌曲 id、`ne <id>`，一律 audio=0）。
// 拿到文件只有一条路：在它的私聊里发 `/search 关键词`，它回一条
//
//     搜索源 网易云音乐，当前为第1页，搜索结果如下：
//     1. 想你就写信 (Live) 周杰伦 李硕 张鑫
//     2. 想你就写信 杜宣达
//     ...
//
// 外加一排内联键盘按钮 [1][2][3]…，点哪个它就发哪首的音频消息。
//
// 【格式是 bot 自己排的，没有契约】所以这里定两条护栏：
//   1. 按钮和歌的对应**不靠位置**，靠按钮文字里的那个数字去匹配行首编号——
//      bot 增删按钮、换行序都不会错位；
//   2. 一行都解析不出来时返回空数组，调用方据此明确报错，
//      **不许静默当成"没搜到"**——那样 bot 改版式我们永远察觉不到。
//
// 【不拆标题和歌手】那一行里两者之间没有任何分隔符（真机样本：
// 「想你就写信 (Live) 周杰伦 李硕 张鑫」），拆只能靠猜。整行原样显示。

export interface ChatBotListLine {
  index: number;
  label: string;
}

export interface ChatBotHit {
  index: number;
  // 整行文字（去掉行首编号），直接当曲目名显示。
  label: string;
  // 按钮的 callback data（base64，TDLib 的 bytes 在 JSON 接口里就是 base64）。
  // 原样回传给 callbackQueryPayloadData，不要解码。
  callbackData: string;
}

// 行首编号 + 一个点 + 空白，后面是内容。宽松一点：点后面没空格也认。
const LINE_RE: RegExp = /^\s*(\d{1,3})[.、)]\s*(.+?)\s*$/;

export function parseNumberedList(text: string): ChatBotListLine[] {
  const out: ChatBotListLine[] = [];
  for (const raw of text.split('\n')) {
    const m: RegExpMatchArray | null = raw.match(LINE_RE);
    if (m === null) {
      continue;
    }
    const index: number = Number.parseInt(m[1], 10);
    const label: string = m[2];
    if (!Number.isFinite(index) || index <= 0 || label === '') {
      continue;
    }
    out.push({ index: index, label: label });
  }
  return out;
}

// 内联键盘里所有「回调型」按钮：按钮文字 → callback data。
// 非回调按钮（链接、切换内联等）不要——点它们不会让 bot 发歌。
export function inlineButtonData(markup: TdObject | undefined): Map<string, string> {
  const out: Map<string, string> = new Map<string, string>();
  if (markup === undefined) {
    return out;
  }
  if ((markup['@type'] as string | undefined) !== 'replyMarkupInlineKeyboard') {
    return out;
  }
  const rows = markup['rows'] as TdObject[][] | undefined;
  if (rows === undefined) {
    return out;
  }
  for (const row of rows) {
    for (const button of row) {
      const type = button['type'] as TdObject | undefined;
      if (type === undefined ||
        (type['@type'] as string | undefined) !== 'inlineKeyboardButtonTypeCallback') {
        continue;
      }
      const text: string = ((button['text'] as string | undefined) ?? '').trim();
      const data: string = (type['data'] as string | undefined) ?? '';
      if (text !== '' && data !== '' && !out.has(text)) {
        out.set(text, data);
      }
    }
  }
  return out;
}

function messageText(message: TdObject): string {
  const content = message['content'] as TdObject | undefined;
  if (content === undefined || (content['@type'] as string | undefined) !== 'messageText') {
    return '';
  }
  const formatted = content['text'] as TdObject | undefined;
  return formatted !== undefined ? ((formatted['text'] as string | undefined) ?? '') : '';
}

// 一条 bot 回复 → 可点的搜索结果。解析不出来返回空数组（调用方必须报错，别当没搜到）。
export function parseChatBotList(message: TdObject | null | undefined): ChatBotHit[] {
  if (message === undefined || message === null) {
    return [];
  }
  const lines: ChatBotListLine[] = parseNumberedList(messageText(message));
  if (lines.length === 0) {
    return [];
  }
  const buttons: Map<string, string> = inlineButtonData(
    message['reply_markup'] as TdObject | undefined);
  const out: ChatBotHit[] = [];
  for (const line of lines) {
    const data: string | undefined = buttons.get(`${line.index}`);
    if (data === undefined) {
      continue;   // 这一行没有对应按钮，点不了，不展示
    }
    out.push({ index: line.index, label: line.label, callbackData: data });
  }
  return out;
}

// 这条消息是不是"可点的搜索结果列表"。用于在会话里认出 bot 的那条回复。
export function isChatBotListMessage(message: TdObject | null | undefined): boolean {
  return parseChatBotList(message).length > 0;
}
