#!/usr/bin/env node
// Survey the Chinese literals still hardcoded in ArkTS sources and propose keys.
//
//   node scripts/i18n-extract.mjs                 # summary by domain
//   node scripts/i18n-extract.mjs --domain util   # one domain, with key proposals
//   node scripts/i18n-extract.mjs --domain util --json > /tmp/util.json
//
// This never edits anything. Migration is a human decision per string: the tool
// proposes, the developer confirms. What it does guarantee is that nothing is
// silently missed — the counts here and in i18n-check.mjs come from the same
// scanner, so "0 remaining" means 0.

import { readFileSync } from 'node:fs';
import {
  ETS_ROOT, domainOf, findLiterals, hasConcatenation, isExemptLine, relFromEtsRoot, walkEts
} from './i18n-config.mjs';

const args = process.argv.slice(2);
const wantDomain = args.includes('--domain') ? args[args.indexOf('--domain') + 1] : '';
const asJson = args.includes('--json');

// Proposed key stem from the source text. Chinese cannot be transliterated
// usefully here, so the stem is derived from the file and a short hash, and is
// meant to be renamed by hand into something meaningful.
function keyStem(text) {
  let h = 0;
  for (let i = 0; i < text.length; i++) {
    h = (h * 31 + text.charCodeAt(i)) >>> 0;
  }
  return h.toString(36).slice(0, 6);
}

function componentOf(relPath) {
  const file = relPath.split(/[\\/]/).pop() ?? '';
  return file.replace(/\.ets$/, '')
    .replace(/([a-z0-9])([A-Z])/g, '$1_$2')
    .toLowerCase();
}

const rows = [];
for (const file of walkEts(ETS_ROOT)) {
  const rel = relFromEtsRoot(file);
  const domain = domainOf(rel);
  if (wantDomain !== '' && domain !== wantDomain) {
    continue;
  }
  const lines = readFileSync(file, 'utf8').split(/\r?\n/);
  lines.forEach((line, i) => {
    if (isExemptLine(line)) {
      return;
    }
    const concat = hasConcatenation(line);
    for (const lit of findLiterals(line)) {
      rows.push({
        domain,
        file: rel,
        line: i + 1,
        text: lit.text,
        interpolated: lit.interpolated,
        concatenated: concat,
        key: `${domain}_${componentOf(rel)}_${keyStem(lit.text)}`,
      });
    }
  });
}

if (asJson) {
  console.log(JSON.stringify(rows, null, 2));
  process.exit(0);
}

const uniqueTexts = new Set(rows.map((r) => r.text));
const interpolated = rows.filter((r) => r.interpolated);

if (wantDomain === '') {
  const byDomain = new Map();
  for (const r of rows) {
    const d = byDomain.get(r.domain) ?? { total: 0, interp: 0, files: new Set() };
    d.total++;
    if (r.interpolated) {
      d.interp++;
    }
    d.files.add(r.file);
    byDomain.set(r.domain, d);
  }
  console.log('待迁移中文字面量 — 按域汇总\n');
  console.log('域'.padEnd(12) + '出现'.padStart(8) + '插值'.padStart(8) + '文件'.padStart(8));
  console.log('-'.repeat(36));
  for (const [domain, d] of [...byDomain].sort((a, b) => b[1].total - a[1].total)) {
    console.log(domain.padEnd(12)
      + String(d.total).padStart(8)
      + String(d.interp).padStart(8)
      + String(d.files.size).padStart(8));
  }
  console.log('-'.repeat(36));
  console.log('合计'.padEnd(12) + String(rows.length).padStart(8) + String(interpolated.length).padStart(8));
  console.log(`\n唯一文案 ${uniqueTexts.size} 条`);

  const concatRows = rows.filter((r) => r.concatenated);
  if (concatRows.length > 0) {
    const sites = [...new Set(concatRows.map((r) => `${r.file}:${r.line}`))];
    console.log(`\n拼接组句 ${sites.length} 处 —— 必须合成一条带占位符的整句，`);
    console.log('不可按片段各拆一个 key（官方本地化约束）：');
    for (const s of sites) {
      console.log(`  ${s}`);
    }
  }
  console.log('\n看某个域的详情与 key 建议：node scripts/i18n-extract.mjs --domain <域>');
  process.exit(0);
}

console.log(`域 ${wantDomain} — ${rows.length} 处，唯一文案 ${uniqueTexts.size} 条\n`);

// One key per unique text: identical wording should share a key rather than
// multiply into near-duplicates that translators must handle separately.
const byText = new Map();
for (const r of rows) {
  const hit = byText.get(r.text) ?? { key: r.key, uses: [] };
  hit.uses.push(`${r.file}:${r.line}`);
  byText.set(r.text, hit);
}

for (const [text, hit] of byText) {
  const flag = interpolated.some((r) => r.text === text) ? '  [插值 — 需占位符或复数]' : '';
  console.log(`${hit.key}${flag}`);
  console.log(`  "${text}"`);
  console.log(`  ${hit.uses.slice(0, 3).join('  ')}${hit.uses.length > 3 ? `  (+${hit.uses.length - 3})` : ''}`);
  console.log('');
}

console.log('--- 可粘贴进 base/element/string.json 的片段 ---');
const entries = [...byText].map(([text, hit]) => ({ name: hit.key, value: text }));
console.log(JSON.stringify(entries, null, 2));
console.log('\n提示：key 是按内容哈希生成的占位名，落库前请改成有语义的名字。');
