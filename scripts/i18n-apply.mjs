#!/usr/bin/env node
// Apply a reviewed text→key mapping to one source file and add the resources.
//
//   node scripts/i18n-apply.mjs <file.ets> <mapping.json>
//
// mapping.json: [{ "text": "直播已结束", "key": "live_media_ended", "en": "Stream ended" }]
// Optional per-entry fields:
//   "args": ["input.retrySeconds"]  → template literal, becomes str(key, ...args)
//   "plural": "input.count"         → becomes plural(key, count, count)
//   "skip": true                    → leave in place (matching literal, not copy)
//   "form": "r" | "str"             → overrides the default form for this entry
//
// Pass --form=r for UI files. It emits $r('app.string.key') instead of
// str('key'), and the difference is not cosmetic: ArkUI re-resolves a Resource
// when the configuration changes, so $r() text updates the moment the language
// is switched, while a str() result is already baked into the built UI and
// stays in the old language until that component happens to rebuild.
//
// Entries with args/plural always use str()/plural() — they need formatting,
// which $r() cannot do.
//
// The mapping is written by hand on purpose. Keys generated from the text would
// be meaningless to a translator, and deciding whether a literal is copy or a
// matching value cannot be automated — liveViewerHeaderPresentation matches on
// Chinese substrings, and rewriting those would have silently broken it.

import { readFileSync, writeFileSync } from 'node:fs';

const args = process.argv.slice(2);
const defaultForm = args.includes('--form=r') ? 'r' : 'str';
const positional = args.filter((a) => !a.startsWith('--'));
const [target, mappingPath] = positional;
if (target === undefined || mappingPath === undefined) {
  console.error('Usage: node scripts/i18n-apply.mjs [--form=r] <file.ets> <mapping.json>');
  process.exit(1);
}

const mapping = JSON.parse(readFileSync(mappingPath, 'utf8'));
let source = readFileSync(target, 'utf8');
const applied = [];
const missed = [];

for (const entry of mapping) {
  // declareOnly: the key is only reached from inside an expression this run
  // rewrites (an args entry that calls str() itself), so there is no literal
  // left to replace — but the resource still has to exist.
  if (entry.skip === true || entry.declareOnly === true) {
    continue;
  }
  let needle;
  let replacement;
  if (entry.plural !== undefined) {
    needle = '`' + entry.text + '`';
    replacement = `plural('${entry.key}', ${entry.plural}, ${entry.plural})`;
  } else if (entry.args !== undefined) {
    needle = '`' + entry.text + '`';
    replacement = `str('${entry.key}', ${entry.args.join(', ')})`;
  } else {
    const form = entry.form !== undefined ? entry.form : defaultForm;
    replacement = form === 'r' ? `$r('app.string.${entry.key}')` : `str('${entry.key}')`;
    // A literal with no interpolation is sometimes still written with
    // backticks. Both spellings are the same string, so accept either.
    needle = source.includes(`'${entry.text}'`) ? `'${entry.text}'` : `\`${entry.text}\``;
  }
  if (!source.includes(needle)) {
    missed.push(`${entry.key}: 未在文件中找到 ${needle}`);
    continue;
  }
  // Replace every occurrence: identical wording should share one key.
  const count = source.split(needle).length - 1;
  source = source.split(needle).join(replacement);
  applied.push(`${entry.key} ×${count}`);
}

if (missed.length > 0) {
  console.error('未应用：');
  for (const m of missed) {
    console.error(`  ${m}`);
  }
  console.error('\n没有写入任何改动 — 修正映射后重试。');
  process.exit(1);
}

writeFileSync(target, source);
const strings = mapping.filter((e) => e.skip !== true && e.plural === undefined).length;
const plurals = mapping.filter((e) => e.skip !== true && e.plural !== undefined).length;
console.log(`${target}: 应用 ${applied.length} 条（string ${strings}，plural ${plurals}）`);
console.log(`资源合并：node scripts/i18n-merge-res.mjs ${mappingPath}`);
