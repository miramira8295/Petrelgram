// Shared configuration for the i18n tooling (i18n-extract.mjs, i18n-check.mjs).
//
// Key convention: <domain>_<component>_<meaning>, e.g. chat_forward_title.
// The domain comes from the source directory so 2600+ keys stay locatable and
// migration can proceed one domain at a time.

import { readdirSync, statSync } from 'node:fs';
import { join, relative, sep } from 'node:path';

export const ETS_ROOT = 'entry/src/main/ets';
export const RES_ROOT = 'entry/src/main/resources';
export const BASE_STRINGS = `${RES_ROOT}/base/element/string.json`;
// App-level resources. $r('app.string.x') resolves these too — app_name lives
// here, not in the module — so a checker that only reads the module's file
// reports a perfectly valid reference as missing.
export const APP_SCOPE_STRINGS = 'AppScope/resources/base/element/string.json';

// Locales that carry translations. `base` holds the source language (zh-Hans)
// and is what the system falls back to when no qualifier matches, so there is
// deliberately no zh_CN directory — it would duplicate base and drift from it.
//
// Trade-off accepted: a device set to an unsupported language (say French)
// falls back to Chinese rather than English. The alternative — base in English,
// zh_CN for Chinese — would block every migration step on having an English
// translation ready, which would stall the migration itself. Revisit once the
// English catalogue is complete.
export const LOCALES = ['en_US', 'zh_Hant', 'ru', 'uk', 'fa', 'ar', 'id', 'ms', 'tr', 'vi', 'th', 'ja', 'ko', 'de', 'fr', 'es', 'pt', 'it', 'hi'];

// Source directory → key domain. Longest prefix wins.
const DOMAIN_RULES = [
  ['pages/chat', 'chat'],
  ['pages/chatlist', 'chatlist'],
  ['pages/login', 'login'],
  ['pages/main', 'settings'],
  ['pages/profile', 'profile'],
  ['pages/search', 'search'],
  ['pages/story', 'story'],
  ['services', 'service'],
  ['store', 'store'],
  ['util', 'util'],
  ['entryability', 'app'],
];

export function domainOf(relPath) {
  const posix = relPath.split(sep).join('/');
  let best = ['', 'misc'];
  for (const rule of DOMAIN_RULES) {
    if (posix.startsWith(rule[0]) && rule[0].length > best[0].length) {
      best = rule;
    }
  }
  return best[1];
}

// Directories already migrated. The gate rejects new Chinese literals here.
// The migration is complete, so this now covers every source directory —
// a new one has to be added here as well, or the gate silently skips it.
export const MIGRATED = [
  'entryability',
  'entrybackupability',
  'workability',
  'util',
  'store',
  'services',
  'tdkit',
  'pages/call',
  'pages/chat',
  'pages/chatlist',
  'pages/common',
  'pages/login',
  'pages/main',
  'pages/profile',
  'pages/search',
  'pages/story',
  'pages/web'
];

export function isMigrated(relPath) {
  const posix = relPath.split(sep).join('/');
  return MIGRATED.some((dir) => posix === dir || posix.startsWith(`${dir}/`));
}

export function walkEts(dir, out = []) {
  for (const name of readdirSync(dir)) {
    const full = join(dir, name);
    if (statSync(full).isDirectory()) {
      walkEts(full, out);
    } else if (name.endsWith('.ets')) {
      out.push(full);
    }
  }
  return out;
}

export function relFromEtsRoot(file) {
  return relative(ETS_ROOT, file);
}

// A line is exempt when it is a comment or a console call — those never reach
// the UI, and forcing them through resources would only add noise.
// `// i18n-exempt: <reason>` on the line itself opts a literal out. It exists
// for text that must NOT be translated — a language's own name in a language
// picker, a brand, a protocol token — and it demands a written reason so the
// exception is reviewable rather than invisible.
export function isExemptLine(line) {
  const trimmed = line.trim();
  return trimmed.startsWith('//') || trimmed.startsWith('*') || trimmed.startsWith('/*')
    || /console\.(log|info|warn|error|debug)\s*\(/.test(line)
    || /\/\/\s*i18n-exempt:\s*\S/.test(line);
}

export const CJK = /[一-鿿]/;

// Sentence built by concatenation. The official localization guidance forbids
// this: word order, capitalisation and punctuation differ per language, so a
// sentence assembled from parts cannot be translated correctly. Such sites must
// become one key with a placeholder ("打开%s"), never one key per fragment.
export function hasConcatenation(line) {
  return /'[^']*[一-鿿][^']*'\s*\+|\+\s*'[^']*[一-鿿][^']*'/.test(line);
}

// Chinese-bearing literals: single-quoted, double-quoted, and template strings.
// Template literals are reported separately because they need placeholder keys
// (%1$s) rather than a plain lookup.
// Cut a trailing `// …` comment, but only one that starts outside a string —
// otherwise the `//` in a URL like 'https://example.com' would truncate the
// line. A comment describing a field ("// \"3月1日\" from userFullInfo") is not
// copy and must not be reported.
function stripTrailingComment(line) {
  let quote = '';
  for (let i = 0; i < line.length; i++) {
    const c = line[i];
    if (quote !== '') {
      if (c === '\\') {
        i++;
      } else if (c === quote) {
        quote = '';
      }
      continue;
    }
    if (c === "'" || c === '"' || c === '`') {
      quote = c;
    } else if (c === '/' && line[i + 1] === '/') {
      return line.slice(0, i);
    }
  }
  return line;
}

export function findLiterals(rawLine) {
  const line = stripTrailingComment(rawLine);
  const found = [];
  const re = /'([^'\\]*(?:\\.[^'\\]*)*)'|"([^"\\]*(?:\\.[^"\\]*)*)"|`([^`\\]*(?:\\.[^`\\]*)*)`/g;
  let m;
  while ((m = re.exec(line)) !== null) {
    const raw = m[0];
    const text = m[1] ?? m[2] ?? m[3] ?? '';
    if (!CJK.test(text)) {
      continue;
    }
    found.push({
      text,
      raw,
      template: raw.startsWith('`'),
      interpolated: raw.startsWith('`') && /\$\{/.test(raw),
    });
  }
  return found;
}
