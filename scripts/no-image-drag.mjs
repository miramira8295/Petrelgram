// Turn off the system drag on every Image.
//
// ArkUI's Image is draggable by default, so a long press starts a system
// drag-and-drop. In this app that is never wanted — there is no drop target —
// and it actively steals the gesture: a long press on a chat photo dragged the
// image around instead of opening the bubble's context menu.
//
// The flag is inserted directly after the Image(...) constructor. Attribute
// order does not matter in ArkUI, and the constructor call is the one position
// that can be located without parsing the whole attribute chain.
//
// Usage: node scripts/no-image-drag.mjs [--check]
import { readFileSync, writeFileSync } from 'node:fs';
import { sep } from 'node:path';
import { walkEts, ETS_ROOT, relFromEtsRoot } from './i18n-config.mjs';

const check = process.argv.includes('--check');

// Walk from the opening paren to its match, honouring quotes and template
// literals so a paren inside `file://${x}` or 'a(b' does not end the call early.
function matchParen(text, open) {
  let depth = 0;
  let quote = '';
  for (let i = open; i < text.length; i++) {
    const c = text[i];
    if (quote !== '') {
      if (c === '\\') { i++; continue; }
      if (c === quote) { quote = ''; }
      continue;
    }
    if (c === '\'' || c === '"' || c === '`') { quote = c; continue; }
    if (c === '(') { depth++; } else if (c === ')') {
      depth--;
      if (depth === 0) { return i; }
    }
  }
  return -1;
}

let touched = 0;
let sites = 0;
for (const file of walkEts(ETS_ROOT)) {
  const rel = relFromEtsRoot(file).split(sep).join('/');
  let text = readFileSync(file, 'utf8');
  const inserts = [];
  const re = /(?<![A-Za-z0-9_.$])Image\s*\(/g;
  let m;
  while ((m = re.exec(text)) !== null) {
    const open = text.indexOf('(', m.index);
    const close = matchParen(text, open);
    if (close < 0) { continue; }
    // Already handled somewhere in this component's attribute chain? Look at
    // the rest of the statement, which ends at the first ';' outside parens.
    const tail = text.slice(close, Math.min(text.length, close + 1200));
    const stmtEnd = tail.indexOf(';');
    const chain = stmtEnd >= 0 ? tail.slice(0, stmtEnd) : tail;
    if (chain.includes('.draggable(')) { continue; }
    inserts.push(close + 1);
    sites++;
  }
  if (inserts.length === 0) { continue; }
  if (!check) {
    // Back to front so earlier offsets stay valid.
    for (let i = inserts.length - 1; i >= 0; i--) {
      text = `${text.slice(0, inserts[i])}.draggable(false)${text.slice(inserts[i])}`;
    }
    writeFileSync(file, text);
  }
  console.log(`${rel}: ${inserts.length}`);
  touched++;
}
console.log(`${check ? '待处理' : '已处理'} ${touched} 个文件，${sites} 处 Image`);
