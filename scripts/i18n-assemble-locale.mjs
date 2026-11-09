#!/usr/bin/env node
// Assemble a locale's string.json from chunk files.
//   node scripts/i18n-assemble-locale.mjs <localeDir> <chunk1.json> <chunk2.json> ...
// Each chunk is a JSON ARRAY of {name, value}. Chunks are concatenated in the
// given order and written to entry/src/main/resources/<localeDir>/element/string.json.
// Run i18n-validate-locale.mjs afterwards.

import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';

const [locale, ...chunks] = process.argv.slice(2);
if (!locale || chunks.length === 0) {
  console.error('usage: i18n-assemble-locale.mjs <localeDir> <chunks...>');
  process.exit(2);
}
const entries = [];
for (const file of chunks) {
  const arr = JSON.parse(readFileSync(file, 'utf8'));
  if (!Array.isArray(arr)) { console.error(`${file}: not an array`); process.exit(1); }
  entries.push(...arr);
}
const dir = `entry/src/main/resources/${locale}/element`;
mkdirSync(dir, { recursive: true });
writeFileSync(`${dir}/string.json`, JSON.stringify({ string: entries }, null, 2) + '\n');
console.log(`${locale}: wrote ${entries.length} entries`);
