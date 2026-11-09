#!/usr/bin/env node
// 向 base 与全部 locale 的同一位置追加新键。
//   node scripts/i18n-add-key.mjs <keys.json>
// keys.json: [{ "name": "x", "values": { "base": "中文", "en_US": "English", ... } }]
// i18n-validate-locale.mjs 要求条目数与名称顺序和 base 完全一致，所以只能
// 一律追加到末尾，且每个 locale 都必须补上 —— 缺一个就是门禁失败。
import { readFileSync, writeFileSync } from 'node:fs';
import { LOCALES, RES_ROOT } from './i18n-config.mjs';

const entries = JSON.parse(readFileSync(process.argv[2], 'utf8'));
const targets = ['base', ...LOCALES];
for (const locale of targets) {
  const path = `${RES_ROOT}/${locale}/element/string.json`;
  const json = JSON.parse(readFileSync(path, 'utf8'));
  for (const entry of entries) {
    if (json.string.some((e) => e.name === entry.name)) {
      continue;
    }
    const value = entry.values[locale] ?? entry.values.en_US ?? entry.values.base;
    json.string.push({ name: entry.name, value });
  }
  writeFileSync(path, JSON.stringify(json, null, 2) + '\n');
  console.log(`${locale}: ok`);
}
