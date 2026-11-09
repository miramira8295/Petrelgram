#!/usr/bin/env node
// Lists the Chinese literals the gate would flag in one file, with line numbers.
//   node scripts/i18n-lit.mjs entry/src/main/ets/util/foo.ets
import { readFileSync } from 'node:fs';
import { findLiterals, isExemptLine } from './i18n-config.mjs';

const lines = readFileSync(process.argv[2], 'utf8').split(/\r?\n/);
let n = 0;
lines.forEach((line, i) => {
  if (isExemptLine(line)) {
    return;
  }
  for (const lit of findLiterals(line)) {
    n++;
    console.log(`${i + 1}: ${lit.text}`);
  }
});
console.log(`共 ${n}`);
