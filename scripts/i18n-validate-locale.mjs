#!/usr/bin/env node
// Validate a locale's string.json / plural.json against base.
//   node scripts/i18n-validate-locale.mjs <localeDir>   e.g. ru, ja, zh_Hant
//
// Checks: JSON parses; entry count and NAME ORDER identical to base;
// per-entry placeholder multiset (%1$s / %2$d / %d / %s / %%) identical;
// plural entries each contain an "other" quantity.
// Exit 0 = clean. Written for the parallel translation agents: run this until
// it passes before reporting a language done.

import { readFileSync, existsSync } from 'node:fs';

const locale = process.argv[2];
if (!locale) { console.error('usage: i18n-validate-locale.mjs <localeDir>'); process.exit(2); }

const RES = 'entry/src/main/resources';
const errors = [];

function placeholders(v) {
  return (v.match(/%(\d+\$)?[sd]|%%|%d|%s/g) || []).sort().join(',');
}

// --- strings ---
const base = JSON.parse(readFileSync(`${RES}/base/element/string.json`, 'utf8')).string;
const locPath = `${RES}/${locale}/element/string.json`;
if (!existsSync(locPath)) { console.error(`missing ${locPath}`); process.exit(1); }
let loc;
try { loc = JSON.parse(readFileSync(locPath, 'utf8')).string; }
catch (e) { console.error(`string.json parse error: ${e.message}`); process.exit(1); }

if (loc.length !== base.length) {
  errors.push(`entry count ${loc.length} != base ${base.length}`);
}
const n = Math.min(loc.length, base.length);
for (let i = 0; i < n; i++) {
  if (loc[i].name !== base[i].name) {
    errors.push(`order mismatch at index ${i}: ${loc[i].name} != base ${base[i].name}`);
    break; // one desync floods everything after it
  }
  if (typeof loc[i].value !== 'string' || loc[i].value === '') {
    errors.push(`${loc[i].name}: empty/invalid value`);
    continue;
  }
  const bp = placeholders(base[i].value);
  const lp = placeholders(loc[i].value);
  if (bp !== lp) {
    errors.push(`${loc[i].name}: placeholders [${lp}] != base [${bp}]`);
  }
}

// --- plurals ---
const basePl = JSON.parse(readFileSync(`${RES}/base/element/plural.json`, 'utf8')).plural;
const plPath = `${RES}/${locale}/element/plural.json`;
if (!existsSync(plPath)) {
  errors.push(`missing ${plPath}`);
} else {
  let pl;
  try { pl = JSON.parse(readFileSync(plPath, 'utf8')).plural; }
  catch (e) { errors.push(`plural.json parse error: ${e.message}`); pl = []; }
  if (pl.length !== basePl.length) {
    errors.push(`plural count ${pl.length} != base ${basePl.length}`);
  }
  const baseNames = new Set(basePl.map((e) => e.name));
  for (const entry of pl) {
    if (!baseNames.has(entry.name)) { errors.push(`plural orphan: ${entry.name}`); continue; }
    const quantities = (entry.value || []).map((v) => v.quantity);
    if (!quantities.includes('other')) { errors.push(`plural ${entry.name}: no "other" form`); }
    for (const v of entry.value || []) {
      if (!/%d/.test(v.value)) { errors.push(`plural ${entry.name}/${v.quantity}: missing %d`); }
    }
  }
}

if (errors.length > 0) {
  for (const e of errors.slice(0, 30)) { console.error(`FAIL ${e}`); }
  if (errors.length > 30) { console.error(`... and ${errors.length - 30} more`); }
  process.exit(1);
}
console.log(`${locale}: OK (${loc.length} strings, plurals present)`);
