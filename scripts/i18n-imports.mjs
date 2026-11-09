#!/usr/bin/env node
// Adds the str()/plural()/Intl imports a migrated file now needs.
//
//   node scripts/i18n-imports.mjs <dir-or-file>...
//
// After a migration pass a file may call str(), plural() or one of the Intl
// helpers without importing them. The compiler catches it, but only one file at
// a time and only after a full build; doing it here keeps the edit loop short.
// A file that already imports what it needs is left alone.
import { readFileSync, writeFileSync, readdirSync, statSync } from 'node:fs';
import { join, relative, sep } from 'node:path';

const ETS_ROOT = join('entry', 'src', 'main', 'ets');
const INTL_FNS = ['clockTime', 'decimal', 'decimalUpTo', 'fullDate', 'fullDateTime',
  'monthDay', 'monthDayTime', 'usd'];

function expand(target) {
  if (statSync(target).isDirectory()) {
    return readdirSync(target).filter((n) => n.endsWith('.ets')).map((n) => join(target, n));
  }
  return [target];
}

// Bare call, not a property access or a longer identifier ending in the name.
function calls(source, name) {
  return new RegExp(`(?<![A-Za-z0-9_.'"])${name}\\s*\\(`).test(source);
}

// How many directories up `util/` is from this file.
function utilPath(file) {
  const depth = relative(ETS_ROOT, file).split(sep).length - 1;
  return depth === 0 ? './util' : `${'../'.repeat(depth)}util`;
}

let changed = 0;
for (const file of process.argv.slice(2).flatMap(expand)) {
  const source = readFileSync(file, 'utf8');
  const base = utilPath(file);
  const wanted = [];

  // An import for the module may already exist while still missing a name —
  // a file that used plural() and now also uses str(). Amend it in place
  // rather than adding a second import of the same module.
  let text = source;
  function ensure(module, names) {
    if (names.length === 0) {
      return;
    }
    const re = new RegExp(`import \\{([^}]*)\\} from '${base}/${module}';`);
    const found = text.match(re);
    if (found === null) {
      wanted.push(`import { ${names.join(', ')} } from '${base}/${module}';`);
      return;
    }
    const have = found[1].split(',').map((s) => s.trim()).filter(Boolean);
    const merged = [...new Set(have.concat(names))].sort();
    if (merged.length !== have.length) {
      text = text.replace(re, `import { ${merged.join(', ')} } from '${base}/${module}';`);
    }
  }

  ensure('strings', [calls(source, 'plural') ? 'plural' : null, calls(source, 'str') ? 'str' : null]
    .filter(Boolean));
  ensure('intlFormat', INTL_FNS.filter((n) => calls(source, n)));

  if (wanted.length === 0) {
    if (text !== source) {
      writeFileSync(file, text);
      console.log(`${file.split(/[\\/]/).pop()}: 合并到已有 import`);
      changed++;
    }
    continue;
  }

  const lines = text.split(/\r?\n/);
  let last = -1;
  for (let i = 0; i < lines.length; i++) {
    if (/^import /.test(lines[i]) || /^} from '/.test(lines[i])) {
      last = i;
    } else if (last >= 0 && lines[i].trim() !== '' && !/^\s/.test(lines[i])) {
      break;
    }
  }
  lines.splice(last + 1, 0, ...wanted);
  writeFileSync(file, lines.join('\n'));
  console.log(`${file.split(/[\\/]/).pop()}: +${wanted.length}`);
  changed++;
}
console.log(`共 ${changed} 个文件补了 import`);
