import { TdObject } from '../tdkit/TdTypes';
import { isLinkEntityType } from './richText';

// 把消息正文里"不代表用户所用语言"的片段抹掉，只留下真正能用来判断语种的字。
//
// 【为什么需要】TranslationService.looksLikeTargetLanguage 靠数文字系统来决定
// 一条消息要不要发翻译请求。它数的是原始字符串，于是 URL 里的拉丁字母也投票。
// 2026-09-10 真机实例：一条中文标题 + 六条 YouTube/短链的机器人消息，
// han=58、latin=165，汉字占比 0.26 < 0.5 → 被判成"不是中文"，白翻一遍，
// 顺带把消息样式冲掉（见 MessageStore.applyTranslation 那一路）。
// 摘掉 URL 之后是 0.62，正确跳过。
//
// looksLikeTargetLanguage 自己的注释里早就写着 total===0 是
// "pure emoji/digits/links"——作者本来就认为链接不该投票，只是实现没做到。
//
// 【为什么用实体而不是正则】TDLib 服务端已经把 url / mention / hashtag /
// command / email / 电话 / 卡号都标成实体了，偏移和长度都是 UTF-16 码元，
// 和 JS 的字符串下标同一套。自己写正则去猜域名只会漏。
// 只有实体数组为空时才退回正则兜底（本地拼的消息、老缓存）。
//
// 【哪些该摘】链接类 + 代码类。引用块（BlockQuote / ExpandableBlockQuote）
// **不摘**——引用里的正文是实打实的自然语言，摘了会把判定带偏。

// 代码类实体：等宽片段里的标识符是语法不是语种。
function isCodeEntityType(t: string): boolean {
  return t === 'textEntityTypeCode' || t === 'textEntityTypePre'
    || t === 'textEntityTypePreCode';
}

function isNonLinguisticEntityType(t: string): boolean {
  return isLinkEntityType(t) || isCodeEntityType(t);
}

// 实体缺席时的兜底。只认协议、www. 和邮箱这三种一眼可辨的形态；裸域名不猜，
// 猜错的代价（把正常文字抹掉）比漏掉的代价大。
const LINKISH_RE: RegExp =
  /(?:https?:\/\/[^\s]+|www\.[^\s]+|[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,})/gi;

// 抹掉的片段用空格填回去，长度保持不变——调用方可能还要拿偏移做别的事，
// 而且空格本来就不参与文字系统统计。
function blankRange(chars: string[], offset: number, length: number): void {
  const from: number = Math.max(0, offset);
  const to: number = Math.min(chars.length, offset + length);
  for (let i = from; i < to; i++) {
    chars[i] = ' ';
  }
}

export function linguisticTextOf(text: string, entities: TdObject[]): string {
  if (text === '') {
    return '';
  }
  const chars: string[] = text.split('');
  let masked: boolean = false;
  for (const e of entities) {
    const type = e['type'] as TdObject | undefined;
    if (type === undefined) {
      continue;
    }
    const name = (type['@type'] as string | undefined) ?? '';
    if (!isNonLinguisticEntityType(name)) {
      continue;
    }
    blankRange(chars, (e['offset'] as number | undefined) ?? 0,
      (e['length'] as number | undefined) ?? 0);
    masked = true;
  }
  if (masked) {
    return chars.join('');
  }
  // 没有实体可用才动正则。lastIndex 是全局正则的可变状态，每次用前归零，
  // 免得上一次调用的残留把这一次的第一个匹配跳过去。
  LINKISH_RE.lastIndex = 0;
  return text.replace(LINKISH_RE, (m: string): string => ' '.repeat(m.length));
}
