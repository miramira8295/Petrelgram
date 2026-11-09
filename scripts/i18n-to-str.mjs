#!/usr/bin/env node
// Converts $r('app.string.X') to str('X') on specific lines.
//
//   node scripts/i18n-to-str.mjs <file.ets> <line> [line...]
//
// $r() is the right form for text a component renders — ArkUI re-resolves it
// when the language changes. It is the wrong form anywhere a plain string is
// required: assignment to a string-typed @State, a model field, string
// comparison, or a parameter still declared `string`. The compiler points at
// exactly those lines; this applies the fix to them and nothing else, so the
// $r() calls that should stay are left alone.
//
// Line numbers are 1-based, matching the compiler's own report.
import { readFileSync, writeFileSync } from 'node:fs';

const [, , target, ...rawLines] = process.argv;
if (target === undefined || rawLines.length === 0) {
  console.error('Usage: node scripts/i18n-to-str.mjs <file.ets> <line> [line...]');
  process.exit(1);
}

const wanted = new Set(rawLines.map((n) => Number(n)));
const lines = readFileSync(target, 'utf8').split(/\r?\n/);
const pattern = /\$r\('app\.string\.([A-Za-z0-9_]+)'\)/g;

let changed = 0;
const missed = [];
for (const n of wanted) {
  const i = n - 1;
  if (i < 0 || i >= lines.length) {
    missed.push(`${n}: 超出文件范围`);
    continue;
  }
  // The compiler points at the start of the expression, but a ternary often
  // continues onto the next line or two and that is where the $r() sits. Look
  // ahead only until the first line that has one — the whole span belongs to
  // the one expression the compiler rejected.
  let target = -1;
  for (let k = i; k <= i + 2 && k < lines.length; k++) {
    pattern.lastIndex = 0;
    if (pattern.test(lines[k])) {
      target = k;
      break;
    }
  }
  if (target < 0) {
    missed.push(`${n}: 该行及后两行都没有 $r('app.string.…')`);
    continue;
  }
  pattern.lastIndex = 0;
  lines[target] = lines[target].replace(pattern, (_m, key) => `str('${key}')`);
  changed++;
}

writeFileSync(target, lines.join('\n'));
console.log(`${target}: 转换 ${changed} 行`);
for (const m of missed) {
  console.log(`  跳过 ${m}`);
}
