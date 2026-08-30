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
  return `${field(button.text)}${field(button.url)}${field(button.callbackData)}` +
    `${button.isGame ? 'g' : '-'}${field(button.style)}`;
}

export function inlineButtonKey(rowIndex: number, buttonIndex: number, button: InlineBtn): string {
  return `ib_${rowIndex}_${buttonIndex}_${signature(button)}`;
}

// The outer key must carry the full row identity too. If only an inner button
// key changes, ArkUI never reruns that inner ForEach because the outer row
// builder itself was reused.
export function inlineButtonRowKey(rowIndex: number, row: InlineBtn[]): string {
  let out: string = `ibrow_${rowIndex}`;
  for (const button of row) {
    const sig: string = signature(button);
    out += `_${sig.length}:${sig}`;
  }
  return out;
}
