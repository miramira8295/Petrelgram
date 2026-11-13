import { TdObject } from '../tdkit/TdTypes';

// TDLib's bounded first page is newest-first. Select at most 12 neighbours of
// the landing anchor, return oldest-first for the production album grouper.
// Only local text/photo/video messages, <=8K text and <=128 entities in total.
export function drawnHomeMessages(raw: TdObject[], anchor: number): TdObject[] {
  const count = Math.min(raw.length, 30);
  let center = 0;
  if (anchor > 0) {
    let distance = Number.POSITIVE_INFINITY;
    for (let i = 0; i < count; i++) {
      const d = Math.abs(((raw[i]['id'] as number | undefined) ?? 0) - anchor);
      if (d < distance) { distance = d; center = i; }
    }
  }
  const start = Math.max(0, Math.min(center - 5, count - 12));
  const end = Math.min(count, start + 12);
  const chosen: TdObject[] = [];
  let chars = 0, entities = 0;
  for (let i = end - 1; i >= start; i--) {
    const message = raw[i];
    const content = message['content'] as TdObject | undefined;
    if (content === undefined || (message['reply_markup'] !== undefined && message['reply_markup'] !== null)) { continue; }
    const type = content['@type'] as string;
    if (type !== 'messageText' && type !== 'messagePhoto' && type !== 'messageVideo') { continue; }
    if (content['link_preview'] !== undefined && content['link_preview'] !== null) { continue; }
    const ft = content[type === 'messageText' ? 'text' : 'caption'] as TdObject | undefined;
    const text = (ft?.['text'] as string | undefined) ?? '';
    const spans = (ft?.['entities'] as TdObject[] | undefined) ?? [];
    if (text.length > 2048 || chars + text.length > 8192 || spans.length > 64 || entities + spans.length > 128) { continue; }
    chars += text.length; entities += spans.length; chosen.push(message);
  }
  return chosen;
}
