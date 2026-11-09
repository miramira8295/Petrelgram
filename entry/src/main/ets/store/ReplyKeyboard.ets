import { TdObject } from '../tdkit/TdTypes';

// Bot custom reply keyboard (TDLib replyMarkupShowKeyboard) — the button rows
// that sit under the input bar. This is CHAT-level state, not message-level:
// chat.reply_markup_message_id names the message carrying the active markup
// (0 = none), and updateChatReplyMarkup moves it.

// The only button type we can honour today: tapping it sends its label as an
// ordinary text message. Every other type needs a capability we don't have
// (location/contact/poll/web app), so those are shown but rejected on tap.
export const KB_TEXT: string = 'keyboardButtonTypeText';

export interface KeyboardBtn {
  text: string;
  type: string;  // keyboardButtonType* ('' when TDLib sent no type)
  style: string; // 'primary' | 'success' | 'danger' | '' (default look)
}

// Bot-chosen button color (TDLib buttonStyle*, Bot API 9.x). '' = default.
// Shared by reply-keyboard and inline-keyboard parsing.
export function buttonStyleOf(btn: TdObject): string {
  const s = btn['style'] as TdObject | undefined;
  const t = s !== undefined ? ((s['@type'] as string | undefined) ?? '') : '';
  if (t === 'buttonStylePrimary') {
    return 'primary';
  }
  if (t === 'buttonStyleSuccess') {
    return 'success';
  }
  if (t === 'buttonStyleDanger') {
    return 'danger';
  }
  return '';
}

export interface ReplyKeyboard {
  messageId: number;
  rows: KeyboardBtn[][];
  isPersistent: boolean;
  oneTime: boolean;   // hide the keyboard again after one button is tapped
  resize: boolean;
  placeholder: string;
}

// A message's reply_markup as a reply keyboard, or null when the message
// carries no markup / a markup of another kind (inline keyboard, force reply,
// remove keyboard — the last of which simply means "no keyboard").
export function parseReplyKeyboard(msg: TdObject): ReplyKeyboard | null {
  const markup = msg['reply_markup'] as TdObject | undefined;
  if (markup === undefined) {
    return null;
  }
  if ((markup['@type'] as string | undefined) !== 'replyMarkupShowKeyboard') {
    return null;
  }
  const rawRows = (markup['rows'] as TdObject[][] | undefined) ?? [];
  const rows: KeyboardBtn[][] = [];
  for (const rawRow of rawRows) {
    const row: KeyboardBtn[] = [];
    for (const b of rawRow) {
      const t = b['type'] as TdObject | undefined;
      const text = (b['text'] as string | undefined) ?? '';
      if (text === '') {
        continue;
      }
      row.push({
        text,
        type: t !== undefined ? ((t['@type'] as string | undefined) ?? '') : '',
        style: buttonStyleOf(b)
      });
    }
    if (row.length > 0) {
      rows.push(row);
    }
  }
  if (rows.length === 0) {
    return null;
  }
  return {
    messageId: (msg['id'] as number | undefined) ?? 0,
    rows,
    isPersistent: (markup['is_persistent'] as boolean | undefined) ?? false,
    oneTime: (markup['one_time'] as boolean | undefined) ?? false,
    resize: (markup['resize_keyboard'] as boolean | undefined) ?? false,
    placeholder: (markup['input_field_placeholder'] as string | undefined) ?? ''
  };
}
