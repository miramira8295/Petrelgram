#!/usr/bin/env node
// Apply one mapping across several files, then merge the resources once.
//
//   node scripts/i18n-apply-many.mjs [--form=r] <mapping.json> <dir-or-file>...
//
// Small sibling files share most of their copy (取消 / 重试 / 加载失败 …), so
// writing one mapping per file duplicates both the work and the keys. This
// splits a shared mapping per file: for each file it applies only the entries
// whose text actually occurs there.
//
// That means a typo in an entry's `text` no longer stops the run the way
// i18n-apply's all-or-nothing check does — it just silently matches nothing.
// The check that replaces it is the leftover count printed per file: a file is
// only done when it reads 0.
import { execFileSync } from 'node:child_process';
import { readFileSync, writeFileSync, statSync, readdirSync, mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const args = process.argv.slice(2);
const form = args.includes('--form=r') ? ['--form=r'] : [];
const positional = args.filter((a) => !a.startsWith('--'));
const [mappingPath, ...targets] = positional;
if (mappingPath === undefined || targets.length === 0) {
  console.error('Usage: node scripts/i18n-apply-many.mjs [--form=r] <mapping.json> <file|dir>...');
  process.exit(1);
}

function expand(target) {
  if (statSync(target).isDirectory()) {
    return readdirSync(target).filter((n) => n.endsWith('.ets')).map((n) => join(target, n));
  }
  return [target];
}

const files = targets.flatMap(expand);
const mapping = JSON.parse(readFileSync(mappingPath, 'utf8'));
const scratch = mkdtempSync(join(tmpdir(), 'i18n-'));

// Entries never replaced in code (declareOnly) are merged once at the end
// rather than per file, so they do not fail the per-file "did it match" test.
const declareOnly = mapping.filter((e) => e.declareOnly === true);
const replaceable = mapping.filter((e) => e.declareOnly !== true);

let touched = 0;
for (const file of files) {
  const source = readFileSync(file, 'utf8');
  const subset = replaceable.filter((e) => {
    if (e.args !== undefined || e.plural !== undefined) {
      return source.includes(`\`${e.text}\``);
    }
    // Plain literals appear with either quote style; i18n-apply accepts both.
    return source.includes(`'${e.text}'`) || source.includes(`\`${e.text}\``);
  });
  if (subset.length === 0) {
    continue;
  }
  const part = join(scratch, 'part.json');
  writeFileSync(part, JSON.stringify(subset));
  try {
    execFileSync(process.execPath, ['scripts/i18n-apply.mjs', ...form, file, part],
      { stdio: 'pipe' });
  } catch (e) {
    console.error(`${file}: 应用失败\n${e.stdout ?? ''}${e.stderr ?? ''}`);
    process.exit(1);
  }
  const left = execFileSync(process.execPath, ['scripts/i18n-lit.mjs', file], { encoding: 'utf8' })
    .trim().split('\n').pop();
  console.log(`${file.split(/[\\/]/).pop()}: 应用 ${subset.length}，剩余 ${left}`);
  touched++;
}

const merge = join(scratch, 'merge.json');
writeFileSync(merge, JSON.stringify(mapping.concat(declareOnly.length > 0 ? [] : [])));
execFileSync(process.execPath, ['scripts/i18n-merge-res.mjs', merge], { stdio: 'inherit' });
console.log(`共处理 ${touched} 个文件`);
