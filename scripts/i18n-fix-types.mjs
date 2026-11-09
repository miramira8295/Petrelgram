#!/usr/bin/env node
// Build, then convert every $r() the compiler rejected as a Resource-where-a-
// string-is-required back to str().
//
//   node scripts/i18n-fix-types.mjs
//
// $r() is the right form for text a component renders — ArkUI re-resolves it on
// a configuration change, so it follows a language switch. It is the wrong form
// wherever a plain string is required: a string-typed @State, a model field, a
// comparison, or a parameter still declared `string`. Only the compiler knows
// which sites those are, and a full build reports all of them at once.
//
// Deliberately narrow: it rewrites only lines the compiler flagged with a
// string/Resource mismatch, so the $r() calls that should stay are untouched.
import { execFileSync } from 'node:child_process';

// Point HVIGORW_JS at your DevEco install, e.g.
//   <DevEco Studio>/tools/hvigor/bin/hvigorw.js
const HVIGOR = process.env.HVIGORW_JS ?? '';
if (HVIGOR === '') {
  console.error('set HVIGORW_JS to the hvigorw.js inside your DevEco Studio install');
  process.exit(2);
}

let output = '';
try {
  output = execFileSync(process.execPath,
    [HVIGOR, '--mode', 'project', '-p', 'product=default', 'assembleApp',
      '-p', 'buildMode=debug', '--no-daemon'],
    { encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 });
} catch (e) {
  output = `${e.stdout ?? ''}${e.stderr ?? ''}`;
}

// Two shapes for the same problem.
//
// Direct: "Type 'Resource' is not assignable to type 'string'".
//
// Through an overload: a `cond ? str(…) : $r(…)` expression has type
// `string | Resource`, which fits neither accessibilityText overload, so the
// compiler reports "No overload matches this call" and lists both failures.
// The fix is identical — make the whole expression a string.
const PATTERNS = [
  /Error Message: (?:Type|Argument of type) '(?:string \| )?Resource'[^]*?At File: ([^\s:]+(?::[^\s:]+)?):(\d+):\d+/g,
  /Error Message: No overload matches this call\.[^]*?'string \| Resource'[^]*?At File: ([^\s:]+(?::[^\s:]+)?):(\d+):\d+/g
];

const byFile = new Map();
for (const pattern of PATTERNS) {
  pattern.lastIndex = 0;
  let m;
  while ((m = pattern.exec(output)) !== null) {
    const file = m[1];
    if (!byFile.has(file)) {
      byFile.set(file, new Set());
    }
    byFile.get(file).add(m[2]);
  }
}

if (byFile.size === 0) {
  console.log('没有 Resource/string 类型不匹配');
  process.exit(0);
}

for (const [file, lines] of byFile) {
  const sorted = [...lines].sort((a, b) => Number(a) - Number(b));
  const out = execFileSync(process.execPath,
    ['scripts/i18n-to-str.mjs', file, ...sorted], { encoding: 'utf8' });
  process.stdout.write(out);
}
console.log(`处理了 ${byFile.size} 个文件；重新构建以确认`);
