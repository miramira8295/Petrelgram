#!/usr/bin/env node
// Gate for the i18n migration. Exits non-zero on any failure so it can be wired
// into run-local-tests.sh.
//
//   node scripts/i18n-check.mjs
//
// Four checks:
//   1. every $r('app.string.x') / $r('app.plural.x') key exists in base
//   2. no locale is missing a key that base defines
//   3. no locale defines a key base does not (orphan — usually a rename left behind)
//   4. no new Chinese literal appears in an already-migrated directory
//
// Why a gate rather than discipline: 2600+ strings cannot be migrated by hand
// without omissions, and a missing key degrades silently (the system falls back
// to base, i.e. Chinese) instead of failing loudly. Only a mechanical check can
// tell "migrated" from "looks migrated".

import { existsSync, readFileSync } from 'node:fs';
import {
  APP_SCOPE_STRINGS, BASE_STRINGS, ETS_ROOT, LOCALES, RES_ROOT, findLiterals, isExemptLine,
  isMigrated, relFromEtsRoot, walkEts
} from './i18n-config.mjs';

const failures = [];

function readNames(path, group) {
  if (!existsSync(path)) {
    return null;
  }
  try {
    const json = JSON.parse(readFileSync(path, 'utf8'));
    const list = json[group];
    if (!Array.isArray(list)) {
      return new Set();
    }
    return new Set(list.map((e) => e.name));
  } catch (e) {
    failures.push(`${path} 解析失败: ${e.message}`);
    return new Set();
  }
}

// --- 1. referenced keys exist -----------------------------------------------

// Module strings plus the app-level ones: $r('app.string.x') resolves both, so
// checking only the module's file rejects a valid reference to app_name.
// Kept separate from `baseStrings` for the reachability pass below — AppScope
// entries are referenced from app.json5 as well as from code.
const appScopeStrings = readNames(APP_SCOPE_STRINGS, 'string') ?? new Set();
const baseStrings = readNames(BASE_STRINGS, 'string') ?? new Set();
const knownStrings = new Set([...baseStrings, ...appScopeStrings]);
const basePlurals = readNames(`${RES_ROOT}/base/element/plural.json`, 'plural') ?? new Set();

// Two access paths, both must be checked. $r() is for components; str()/plural()
// is for the stores, services and util functions that have no UI context. A gate
// that only knew about $r() would have reported "0 references" for a fully
// migrated non-UI file and passed it.
const PATTERNS = [
  { re: /\$r\(\s*'app\.string\.([A-Za-z0-9_]+)'/g, kind: 'string', label: "$r('app.string.%s')" },
  { re: /\$r\(\s*'app\.plural\.([A-Za-z0-9_]+)'/g, kind: 'plural', label: "$r('app.plural.%s')" },
  { re: /(?<![A-Za-z0-9_])str\(\s*'([A-Za-z0-9_]+)'/g, kind: 'string', label: "str('%s')" },
  { re: /(?<![A-Za-z0-9_])plural\(\s*'([A-Za-z0-9_]+)'/g, kind: 'plural', label: "plural('%s')" },
];

let refCount = 0;
for (const file of walkEts(ETS_ROOT)) {
  const rel = relFromEtsRoot(file);
  // strings.ets defines str()/plural(); its own references are not lookups.
  if (rel.split(/[\\/]/).join('/') === 'util/strings.ets') {
    continue;
  }
  const text = readFileSync(file, 'utf8');
  for (const p of PATTERNS) {
    p.re.lastIndex = 0;
    let m;
    while ((m = p.re.exec(text)) !== null) {
      refCount++;
      const name = m[1];
      const known = p.kind === 'string' ? knownStrings : basePlurals;
      if (!known.has(name)) {
        failures.push(`${rel} 引用了不存在的 ${p.label.replace('%s', name)}`);
      }
    }
  }
}

// --- 1a. every app.string./app.plural. literal is wrapped in $r() ------------
//
// `Text(('app.string.wp_keygen_note'))` compiles, and check 1b below is happy
// because the key does appear as a literal — but ArkUI renders the qualifier
// itself, so the screen reads "app.string.wp_keygen_note". Losing the `$r`
// leaves a plain string that nothing else in the toolchain objects to. It
// shipped once, from a scripted `str()` → `$r()` rewrite that dropped the
// prefix.
const QUALIFIED = /(?<!\$r\(\s{0,4})'app\.(string|plural)\.([A-Za-z0-9_]+)'/g;
for (const file of walkEts(ETS_ROOT)) {
  const rel = relFromEtsRoot(file);
  const text = readFileSync(file, 'utf8');
  QUALIFIED.lastIndex = 0;
  let q;
  while ((q = QUALIFIED.exec(text)) !== null) {
    const line = text.slice(0, q.index).split('\n').length;
    failures.push(`${rel}:${line} 'app.${q[1]}.${q[2]}' 没有包在 $r() 里，会被当普通字符串渲染`);
  }
}

// --- 1b. every defined key is reachable from the code ------------------------
//
// The check above only sees literal call sites. Keys can also be reached
// indirectly — SERVICE_LABEL_KEYS maps a TDLib type to a key and the caller does
// str(svcKey) — and a typo there is invisible to the gate, the compiler and the
// tests alike. Scanning the sources for the key as a bare literal covers that:
// the key still has to appear somewhere, just not inside str().
const allSource = walkEts(ETS_ROOT)
  .filter((f) => relFromEtsRoot(f).split(/[\\/]/).join('/') !== 'util/strings.ets')
  .map((f) => readFileSync(f, 'utf8'))
  .join('\n');

// Both spellings count: str('x') writes the bare name, $r('app.string.x')
// writes it qualified, and looking for only one of them reports every key used
// by the other as missing.
const unreferenced = [];
for (const name of [...baseStrings, ...basePlurals]) {
  if (allSource.includes(`'${name}'`)
    || allSource.includes(`app.string.${name}'`)
    || allSource.includes(`app.plural.${name}'`)) {
    continue;
  }
  unreferenced.push(name);
}

// --- 1c. resource values are usable ------------------------------------------
//
// A value like "${sizeLabel} · 正在下载" passes every other check in this file:
// the key exists, both locales define it, no source file carries a literal. It
// is still broken — getStringByNameSync() returns it verbatim, so the UI shows
// the template. That shipped for 26 keys before this check existed.
//
// The placeholder counts are compared too: a translation that drops one throws
// at runtime rather than degrading, and one that adds one prints garbage.
const PLACEHOLDER = /%(\d+)\$[sd]/g;

function placeholderIndexes(value) {
  PLACEHOLDER.lastIndex = 0;
  const seen = new Set();
  let m;
  while ((m = PLACEHOLDER.exec(value)) !== null) {
    seen.add(m[1]);
  }
  return [...seen].sort().join(',');
}

function checkValues(path, group) {
  if (!existsSync(path)) {
    return new Map();
  }
  const json = JSON.parse(readFileSync(path, 'utf8'));
  const list = Array.isArray(json[group]) ? json[group] : [];
  const shape = new Map();
  for (const entry of list) {
    // plural entries hold an array of quantity forms; join them, since every
    // form has to take the same placeholders.
    const values = Array.isArray(entry.value)
      ? entry.value.map((v) => v.value) : [entry.value];
    for (const value of values) {
      if (typeof value !== 'string') {
        continue;
      }
      if (value.includes('${')) {
        failures.push(`${path} 的 ${entry.name} 含未转换的模板: ${value}`);
      }
    }
    shape.set(entry.name, placeholderIndexes(values.join('')));
  }
  return shape;
}

const baseShapes = new Map([
  ...checkValues(BASE_STRINGS, 'string'),
  ...checkValues(`${RES_ROOT}/base/element/plural.json`, 'plural')
]);

for (const locale of LOCALES) {
  const localeShapes = new Map([
    ...checkValues(`${RES_ROOT}/${locale}/element/string.json`, 'string'),
    ...checkValues(`${RES_ROOT}/${locale}/element/plural.json`, 'plural')
  ]);
  for (const [name, shape] of localeShapes) {
    const expected = baseShapes.get(name);
    if (expected !== undefined && expected !== shape) {
      failures.push(
        `${locale} 的 ${name} 占位符与 base 不一致: base [${expected}] / ${locale} [${shape}]`);
    }
  }
}

const localeReport = [];
const GROUPS = [
  { file: 'string.json', group: 'string', base: baseStrings },
  { file: 'plural.json', group: 'plural', base: basePlurals },
];

for (const locale of LOCALES) {
  for (const g of GROUPS) {
    if (g.base.size === 0) {
      continue;
    }
    const path = `${RES_ROOT}/${locale}/element/${g.file}`;
    const names = readNames(path, g.group);
    if (names === null) {
      localeReport.push(`${locale}/${g.file}: 尚未建立（base 有 ${g.base.size} 条）`);
      continue;
    }
    const missing = [...g.base].filter((n) => !names.has(n));
    const orphan = [...names].filter((n) => !g.base.has(n));
    localeReport.push(
      `${locale}/${g.file}: ${names.size} 条，缺 ${missing.length}，多余 ${orphan.length}`);
    for (const n of orphan) {
      failures.push(`${locale}/${g.file} 定义了 base 中不存在的 key: ${n}（重命名后遗留？）`);
    }
    // Missing keys fall back to base (Chinese) rather than breaking, so they are
    // reported but do not fail the gate — an untranslated string is a todo, not
    // a defect. Orphans are a defect: they can never be reached.
    if (missing.length > 0) {
      localeReport.push(`  待翻译: ${missing.slice(0, 5).join(', ')}${missing.length > 5 ? ` … 共 ${missing.length}` : ''}`);
    }
  }
}

// --- 4. migrated directories stay clean --------------------------------------

let guarded = 0;
for (const file of walkEts(ETS_ROOT)) {
  const rel = relFromEtsRoot(file);
  if (!isMigrated(rel)) {
    continue;
  }
  guarded++;
  const lines = readFileSync(file, 'utf8').split(/\r?\n/);
  lines.forEach((line, i) => {
    if (isExemptLine(line)) {
      return;
    }
    for (const lit of findLiterals(line)) {
      failures.push(`${rel}:${i + 1} 已迁移目录中出现中文字面量: "${lit.text}"`);
    }
  });
}

// --- report ------------------------------------------------------------------

console.log('i18n 检查');
console.log(`  base 词条        string ${baseStrings.size}  plural ${basePlurals.size}`);
console.log(`  代码中的资源引用  ${refCount} 处`);
for (const line of localeReport) {
  console.log(`  ${line}`);
}
console.log(`  已纳入门禁的文件  ${guarded}`);
// Reported, not failed: a key may legitimately be added ahead of the code that
// uses it. But a long list here usually means a typo or a dead key.
if (unreferenced.length > 0) {
  console.log(`  代码中找不到的 key ${unreferenced.length}: `
    + `${unreferenced.slice(0, 8).join(', ')}${unreferenced.length > 8 ? ' …' : ''}`);
}

if (failures.length > 0) {
  console.log('');
  for (const f of failures) {
    console.log(`  FAIL  ${f}`);
  }
  console.log(`\nI18N CHECK: FAIL (${failures.length} 项)`);
  process.exit(1);
}

console.log('\nI18N CHECK: PASS');
