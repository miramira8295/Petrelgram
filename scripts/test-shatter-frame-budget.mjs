// Native coverage/budget/range tests and real ArkTS lifecycle replay. Browser
// shader pixel comparison is separate (test-shatter-shaders.mjs).
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const temporary = fs.mkdtempSync(path.join(os.tmpdir(), 'petrel-shatter-frame-'));
function run(command, args) {
  const result = spawnSync(command, args, { cwd: root, env: process.env, stdio: 'inherit' });
  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error(`${command} failed: ${result.status}`);
}
try {
  const binary = path.join(temporary, 'geometry');
  run(process.env.CXX || 'clang++', ['-std=c++17', '-O2', '-fsanitize=address,undefined',
    'entry/src/test/native/shatter_geometry_test.cpp', '-o', binary]);
  run(binary, []);
  run('python3', ['scripts/test-shatter-pixels.py']);
  run(process.execPath, ['scripts/test-shatter-lifecycle.mjs']);
} finally {
  fs.rmSync(temporary, { recursive: true, force: true });
}
