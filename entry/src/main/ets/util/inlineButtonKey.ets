import { InlineBtn } from '../store/MessageEntry';

// Bot inline-keyboard nodes capture their click target in the ForEach builder.
// A stable-looking label is therefore not an identity: two messages commonly
// use the same text while pointing at different URLs/callback payloads.
function field(value: string): string {
  // Length-prefix every field so text containing our separators cannot make
  // two different buttons collapse to the same key.
  return `${value.length}:${value}`;
}

function signature(button: InlineBtn): string {
  return `${field(button.text)}${field(button.url)}${field(button.callbackData)}${field(button.webAppUrl ?? '')}` +
    `${button.isGame ? 'g' : '-'}${field(button.style)}`;
}

export function inlineButtonKey(rowIndex: number, buttonIndex: number, button: InlineBtn): string {
  return `ib_${rowIndex}_${buttonIndex}_${signature(button)}`;
}

// The outer key must carry the full row identity too. If only an inner button
// key changes, ArkUI never reruns that inner ForEach because the outer row
// builder itself was reused.
export function inlineButtonRowKey(rowIndex: number, row: InlineBtn[]): string {
  const parts: string[] = [`ibrow_${rowIndex}`];
  for (const button of row) {
    const sig: string = signature(button);
    parts.push(`_${sig.length}:${sig}`);
  }
  return parts.join('');
}

export interface InlineKeyboardKeyPlan {
  rows: string[];
  buttons: string[][];
}

// MessageEntry replaces keyboard arrays when markup changes. One mounted
// keyboard retains only its latest array. Each button is visited exactly once
// on a miss; progress/theme/width updates reuse all keys without serialization.
export class InlineKeyboardKeys {
  private source: InlineBtn[][] | null = null;
  private current: InlineKeyboardKeyPlan = { rows: [], buttons: [] };
  prepare(rows: InlineBtn[][]): InlineKeyboardKeyPlan {
    if (this.source === rows) { return this.current; }
    const rowKeys: string[] = [], buttonKeys: string[][] = [];
    for (let i = 0; i < rows.length; i++) {
      const row = rows[i], parts: string[] = [`ibrow_${i}`], keys: string[] = [];
      for (let j = 0; j < row.length; j++) {
        const sig = signature(row[j]);
        keys.push(`ib_${i}_${j}_${sig}`); parts.push(`_${sig.length}:${sig}`);
      }
      rowKeys.push(parts.join('')); buttonKeys.push(keys);
    }
    this.source = rows; this.current = { rows: rowKeys, buttons: buttonKeys }; return this.current;
  }
}
