#!/usr/bin/env node
// Merge the resource fragment produced by i18n-apply.mjs into base and en_US.
//
//   node scripts/i18n-merge-res.mjs <mapping.json>
//
// Reads the same mapping file i18n-apply.mjs consumes — one source of truth, no
// intermediate fragment to go stale. base carries the Chinese source text,
// en_US the "en" field. Entries already present are left untouched, so
// re-running is safe.

import { readFileSync, writeFileSync } from 'node:fs';
import { RES_ROOT } from './i18n-config.mjs';

const mappingPath = process.argv[2];
if (mappingPath === undefined) {
  console.error('Usage: node scripts/i18n-merge-res.mjs <mapping.json>');
  process.exit(1);
}
const mapping = JSON.parse(readFileSync(mappingPath, 'utf8'));

// For an entry with args/plural, `text` is the template literal being replaced
// — "${sizeLabel} · 正在下载" — which is a matching pattern, not a resource
// value. Writing it as one produced 26 keys whose placeholders were never
// placeholders, so the app rendered the template. Such entries must carry an
// explicit `zh` with real %1$s / %1$d placeholders.
const bad = [];
for (const e of mapping) {
  if (e.skip === true) {
    continue;
  }
  const templated = (e.args !== undefined || e.plural !== undefined) && e.declareOnly !== true;
  if (templated && e.zh === undefined) {
    bad.push(`${e.key}: 缺少 zh（中文资源值，须用 %1$s / %1$d 占位符）`);
  }
  if (typeof e.zh === 'string' && e.zh.includes('${')) {
    bad.push(`${e.key}: zh 仍含 \${...}`);
  }
  if (typeof e.en === 'string' && e.en.includes('${')) {
    bad.push(`${e.key}: en 仍含 \${...}`);
  }
}
if (bad.length > 0) {
  console.error('资源值不可用：');
  for (const line of bad) {
    console.error(`  ${line}`);
  }
  process.exit(1);
}
const fragment = {
  strings: mapping.filter((e) => e.skip !== true && e.plural === undefined),
  plurals: mapping.filter((e) => e.skip !== true && e.plural !== undefined),
};

function merge(path, group, rows, pick) {
  const json = JSON.parse(readFileSync(path, 'utf8'));
  if (!Array.isArray(json[group])) {
    json[group] = [];
  }
  let added = 0;
  for (const row of rows) {
    if (json[group].some((e) => e.name === row.name)) {
      continue;
    }
    json[group].push(pick(row));
    added++;
  }
  writeFileSync(path, `${JSON.stringify(json, null, 2)}\n`);
  return { added, total: json[group].length };
}

// zh when given (required for args entries, see the guard above), otherwise the
// literal being replaced — which for a plain entry *is* the resource value.
const strRows = fragment.strings.map((e) => ({ name: e.key, zh: e.zh ?? e.text, en: e.en }));
// A plural's source text still carries ${...}; the resource form uses %d.
const plRows = fragment.plurals.map((e) => ({
  name: e.key,
  zh: e.zhPlural ?? [{ quantity: 'other', value: e.text.replace(/\$\{[^}]*\}/, '%d') }],
  en: e.enPlural ?? [
    { quantity: 'one', value: (e.en ?? '').replace(/\$\{[^}]*\}/, '%d') },
    { quantity: 'other', value: (e.en ?? '').replace(/\$\{[^}]*\}/, '%d') },
  ],
}));

for (const target of [
  { locale: 'base', field: 'zh' },
  { locale: 'en_US', field: 'en' },
]) {
  const s = merge(`${RES_ROOT}/${target.locale}/element/string.json`, 'string', strRows,
    (r) => ({ name: r.name, value: r[target.field] }));
  let report = `${target.locale}: string +${s.added} (${s.total})`;
  if (plRows.length > 0) {
    const p = merge(`${RES_ROOT}/${target.locale}/element/plural.json`, 'plural', plRows,
      (r) => ({ name: r.name, value: r[target.field] }));
    report += `, plural +${p.added} (${p.total})`;
  }
  console.log(report);
}
