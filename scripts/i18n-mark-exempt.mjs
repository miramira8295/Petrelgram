#!/usr/bin/env node
// Append `// i18n-exempt: <reason>` to specific lines.
//
//   node scripts/i18n-mark-exempt.mjs <file.ets> "<reason>" <line> [line...]
//
// For literals that must NOT be translated. The live-stream pages pass Chinese
// labels to replaceSession()/scheduleRecovery()/refreshGroupCall(), and those
// arguments only ever reach console.info — they are trace tags, not copy.
// Translating them would cost a translator's time and make the logs harder to
// grep, so they are exempted rather than migrated.
//
// Lines are 1-based. A line that already carries the marker is left alone.
import { readFileSync, writeFileSync } from 'node:fs';

const [, , target, reason, ...rawLines] = process.argv;
if (target === undefined || reason === undefined || rawLines.length === 0) {
  console.error('Usage: node scripts/i18n-mark-exempt.mjs <file.ets> "<reason>" <line>...');
  process.exit(1);
}

const lines = readFileSync(target, 'utf8').split(/\r?\n/);
let marked = 0;
for (const raw of rawLines) {
  const i = Number(raw) - 1;
  if (i < 0 || i >= lines.length || lines[i].includes('i18n-exempt:')) {
    continue;
  }
  lines[i] = `${lines[i].replace(/\s+$/, '')} // i18n-exempt: ${reason}`;
  marked++;
}
writeFileSync(target, lines.join('\n'));
console.log(`${target.split(/[\\/]/).pop()}: 标注 ${marked} 行`);
