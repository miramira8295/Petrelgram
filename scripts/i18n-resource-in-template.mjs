// Find Resource values that end up inside a string.
//
// $r() returns a Resource object. Putting one in a template literal or
// concatenating it with + yields "[object Object]" on screen — no compile
// error, no failing test, no gate complaint. It shipped once as the join-live
// dialog reading "[object Object]", because the migration rewrote a ternary of
// two strings into a ternary of two Resources without looking at what consumed
// the result.
//
// Two shapes are reported:
//   1. $r(...) written directly inside a template literal or a + expression.
//   2. a local assigned from an expression containing $r(...), then used inside
//      a template literal in the same file.
//
// Shape 2 over-reports in principle (a same-named local elsewhere), so each hit
// prints its line for a human to judge — this is a finder, not a gate.
import { readFileSync } from 'node:fs';
import { sep } from 'node:path';
import { walkEts, ETS_ROOT, relFromEtsRoot } from './i18n-config.mjs';

const DIRECT = /(?:`[^`]*\$\{[^}]*\$r\(|\$r\([^)]*\)\s*\+|\+\s*\$r\()/;
const ASSIGN = /(?:const|let|var)\s+([A-Za-z_][A-Za-z0-9_]*)\s*(?::[^=]+)?=\s*([^;]*\$r\([^;]*)/g;

let hits = 0;
for (const file of walkEts(ETS_ROOT)) {
  const rel = relFromEtsRoot(file).split(sep).join('/');
  const text = readFileSync(file, 'utf8');
  const lines = text.split('\n');

  lines.forEach((line, i) => {
    if (DIRECT.test(line)) {
      console.log(`${rel}:${i + 1}: [直接] ${line.trim().slice(0, 130)}`);
      hits++;
    }
  });

  ASSIGN.lastIndex = 0;
  let m;
  while ((m = ASSIGN.exec(text)) !== null) {
    const name = m[1];
    const declLine = text.slice(0, m.index).split('\n').length;
    // Only a template-literal interpolation of that exact identifier counts;
    // passing a Resource to a component attribute is correct and common.
    //
    // Each ${...} group is tested on its own rather than trying to reach the
    // identifier from the opening backtick: in `${a}${b}` the first group's
    // closing brace stops any single scan short of b, which is exactly how the
    // first version of this check missed the bug it was written for.
    const word = new RegExp(`\\b${name}\\b`);
    lines.forEach((line, i) => {
      if (i + 1 === declLine || !line.includes('`')) {
        return;
      }
      const groups = line.match(/\$\{[^{}]*\}/g) ?? [];
      if (groups.some((g) => word.test(g))) {
        console.log(`${rel}:${i + 1}: [间接] ${name} 在 ${declLine} 行由 $r() 赋值 → ${line.trim().slice(0, 110)}`);
        hits++;
      }
    });
  }
}
console.log(`共 ${hits} 处可疑`);
