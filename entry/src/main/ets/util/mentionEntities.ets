import { TdObject } from '../tdkit/TdTypes';

// 没有用户名的成员怎么被 @ 到。
//
// `@username` 之所以能用，是**服务器扫文本**认出 `@xxx` 这个模式并自己补上
// 实体。而没有设用户名的人，文本里根本没有可扫的东西——发出去就是一串普通
// 文字，对方收不到提及通知（群里实测过）。
//
// Telegram 为此提供了 textEntityTypeMentionName：按 user_id 提及，不依赖
// 用户名，显示成对方的名字。客户端必须自己算好偏移把实体带上。
export interface NameMention {
  name: string;
  userId: number;
}

interface Span {
  offset: number;
  length: number;
  userId: number;
}

// TDLib 的实体偏移以 **UTF-16 code unit** 计。ArkTS 的字符串同样是 UTF-16，
// 所以 indexOf / length 直接可用，不需要按码点换算。
//
// 同一个名字在文本里出现多次时全部标注：无法可靠区分"哪一次是点出来的"
// （用户可以任意编辑草稿），而多标一次的后果只是对方多收到一条提及，
// 比漏标导致完全收不到要好。
export function buildMentionEntities(text: string, mentions: NameMention[]): TdObject[] {
  const spans: Span[] = [];
  for (const mention of mentions) {
    const name = mention.name;
    if (name === '' || mention.userId <= 0) {
      continue;
    }
    let from: number = 0;
    while (from <= text.length - name.length) {
      const at: number = text.indexOf(name, from);
      if (at < 0) {
        break;
      }
      spans.push({ offset: at, length: name.length, userId: mention.userId });
      from = at + name.length;
    }
  }
  if (spans.length === 0) {
    return [];
  }
  // 按起点排序，长的优先：两个成员的名字互为前缀时（"张三" 与 "张三丰"），
  // 取长的那个，短的那次跳过，否则会把同一段文字标给两个人。
  spans.sort((a: Span, b: Span): number => a.offset !== b.offset
    ? a.offset - b.offset : b.length - a.length);
  const out: TdObject[] = [];
  let usedUntil: number = -1;
  for (const span of spans) {
    if (span.offset < usedUntil) {
      continue;
    }
    const type: TdObject = { '@type': 'textEntityTypeMentionName' };
    type['user_id'] = span.userId;
    const entity: TdObject = { '@type': 'textEntity' };
    entity['offset'] = span.offset;
    entity['length'] = span.length;
    entity['type'] = type;
    out.push(entity);
    usedUntil = span.offset + span.length;
  }
  return out;
}
