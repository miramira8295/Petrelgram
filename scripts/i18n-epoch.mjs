// Give every component that renders str()/plural() a LANGUAGE_EPOCH observer.
//
// Why this is needed at all: $r('app.string.x') is a Resource and ArkUI
// re-resolves it when the configuration changes, so it follows a language
// switch by itself. str('x') returns a plain string, baked into whatever build
// pass produced it. A component whose visible text comes from str() therefore
// keeps the old language until something else happens to rebuild it — which is
// why the bottom dock and the folder bar's "All" only changed after a restart.
//
// applyAppLanguage() bumps LANGUAGE_EPOCH; a @StorageProp on that key makes the
// component rebuild, and any str() called from build() (directly or through a
// method) re-evaluates. This does NOT help a str() whose result was cached into
// a field at construction time — those have to be recomputed by hand.
//
// Usage: node scripts/i18n-epoch.mjs [--check]
import { readFileSync, writeFileSync } from 'node:fs';
import { join, sep } from 'node:path';
import { walkEts, ETS_ROOT, relFromEtsRoot } from './i18n-config.mjs';

const check = process.argv.includes('--check');
const PROP = '  @StorageProp(LANGUAGE_EPOCH) langEpoch: number = 0;';
const IMPORT_RE = /import\s*\{([^}]*)\}\s*from\s*'([^']*appLanguage)'/;

// Split a file into struct bodies so only the structs that actually call str()
// get the observer. Brace counting is enough here: these are whole files of
// well-formed ArkTS, and a decorator always sits immediately above its struct.
function structRanges(text) {
  const ranges = [];
  const re = /(@(?:Component|Entry|ComponentV2|Reusable)\b[^\n]*\n(?:\s*@[^\n]*\n)*)\s*(?:export\s+)?struct\s+(\w+)\s*\{/g;
  let m;
  while ((m = re.exec(text)) !== null) {
    const open = text.indexOf('{', m.index + m[0].length - 1);
    let depth = 0;
    let i = open;
    for (; i < text.length; i++) {
      if (text[i] === '{') { depth++; }
      else if (text[i] === '}') { depth--; if (depth === 0) { break; } }
    }
    ranges.push({ name: m[2], bodyStart: open + 1, bodyEnd: i });
  }
  return ranges;
}

function relImport(file) {
  const rel = relFromEtsRoot(file).split(sep).join('/');
  const depth = rel.split('/').length - 1;
  return `${'../'.repeat(depth)}util/appLanguage`;
}

const CALL = /(?<![A-Za-z0-9_.])(?:str|plural)\s*\(/;

const changed = [];
for (const file of walkEts(ETS_ROOT)) {
  const rel = relFromEtsRoot(file).split(sep).join('/');
  if (rel === 'util/appLanguage.ets' || rel === 'util/strings.ets') {
    continue;
  }
  let text = readFileSync(file, 'utf8');
  const ranges = structRanges(text);
  if (ranges.length === 0) {
    continue;
  }
  // Work back to front so earlier offsets stay valid.
  const targets = ranges
    .filter((r) => CALL.test(text.slice(r.bodyStart, r.bodyEnd)))
    .filter((r) => !/@StorageProp\(LANGUAGE_EPOCH\)/.test(text.slice(r.bodyStart, r.bodyEnd)))
    .sort((a, b) => b.bodyStart - a.bodyStart);
  if (targets.length === 0) {
    continue;
  }
  if (check) {
    changed.push(`${rel}: ${targets.map((t) => t.name).join(', ')}`);
    continue;
  }
  for (const t of targets) {
    text = `${text.slice(0, t.bodyStart)}\n${PROP}${text.slice(t.bodyStart)}`;
  }
  // Import LANGUAGE_EPOCH, merging into an existing appLanguage import.
  if (!/\bLANGUAGE_EPOCH\b/.test(text.split('\n').filter((l) => l.startsWith('import')).join('\n'))) {
    const existing = text.match(IMPORT_RE);
    if (existing !== null) {
      const names = existing[1].split(',').map((s) => s.trim()).filter((s) => s !== '');
      names.push('LANGUAGE_EPOCH');
      text = text.replace(IMPORT_RE, `import { ${names.join(', ')} } from '${existing[2]}'`);
    } else {
      const lines = text.split('\n');
      let last = 0;
      for (let i = 0; i < lines.length; i++) {
        if (lines[i].startsWith('import ')) { last = i; }
      }
      lines.splice(last + 1, 0, `import { LANGUAGE_EPOCH } from '${relImport(file)}';`);
      text = lines.join('\n');
    }
  }
  writeFileSync(file, text);
  changed.push(`${rel}: ${targets.map((t) => t.name).join(', ')}`);
}

for (const line of changed) {
  console.log(line);
}
console.log(`${check ? '需要处理' : '已处理'} ${changed.length} 个文件`);
