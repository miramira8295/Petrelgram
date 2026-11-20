import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
const ts = (await import(process.env.TYPESCRIPT_MODULE || 'typescript')).default;
const code = ts.transpileModule(fs.readFileSync('entry/src/main/ets/services/VideoStreamSession.ets', 'utf8'), {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
}).outputText;
const MB = 1024 * 1024;
function setup() {
  const requests = [], timers = [];
  let notify;
  const context = vm.createContext({ exports: {}, require: name => {
    if (name.includes('/log')) return { logW() {}, logE() {} };
    if (name.includes('file.fs')) return {};
    throw new Error('Unexpected dependency: ' + name);
  }, setTimeout: fn => { timers.push(fn); return timers.length; } });
  vm.runInContext(code, context);
  const client = {
    onUpdate(_name, fn) { notify = fn; return () => { notify = null; }; },
    send(req) { return new Promise((resolve, reject) => requests.push({ ...req, resolve, reject })); }
  };
  const session = new context.exports.VideoStreamSession(client, 7, 512 * MB);
  const file = (offset, length) => ({ id: 7, size: 512 * MB, local: {
    path: '/cache/video', download_offset: offset, downloaded_prefix_size: length,
    downloaded_size: length, is_downloading_completed: false
  } });
  return { session, requests, timers, file, update: (offset, length) => notify({ file: file(offset, length) }) };
}
const flush = async () => { for (let i = 0; i < 6; i++) await Promise.resolve(); };
test('seek promotes a queued prefetch immediately without awaiting old download', () => {
  const { session, requests } = setup();
  session.setReadAheadBytes(64 * MB);
  assert.equal(requests.length, 1);
  session.noteReadHead(32 * MB, true);
  assert.equal(requests.length, 2);
  assert.equal(requests[1].offset, 32 * MB);
  assert.equal(requests[1].priority, 32);
  assert.ok(requests[1].limit > 0);
});
test('repeated urgent reads in the same active range do not restart the download', () => {
  const { session, requests } = setup();
  session.start();
  session.noteReadHead(128 * MB, true);
  for (let i = 0; i < 1000; i++) session.noteReadHead(128 * MB + 700, true);
  assert.equal(requests.length, 2);
});
for (const failOld of [false, true]) test(`A/B/A ignores late ${failOld ? 'failure' : 'success'} and preserves new A ownership`, async () => {
  const { session, requests, file } = setup();
  session.noteReadHead(32 * MB, true);
  const oldA = requests[0];
  session.noteReadHead(128 * MB, true);
  session.noteReadHead(32 * MB, true);
  assert.equal(requests.length, 3);
  if (failOld) oldA.reject({ message: 'old timeout' }); else oldA.resolve(file(32 * MB, 0));
  await flush();
  session.noteReadHead(32 * MB, true);
  assert.equal(requests.length, 3);
  requests[2].resolve(file(32 * MB, 6 * MB));
  await flush();
  session.noteReadHead(128 * MB, true);
  assert.equal(requests.at(-1).offset, 128 * MB, 'old B cannot keep new B marked pending');
});
test('seek discards obsolete lookahead; completing target cannot return to old window', async () => {
  const { session, requests, file } = setup();
  session.setReadAheadBytes(64 * MB);
  session.noteReadHead(128 * MB, true);
  requests[1].resolve(file(128 * MB, 6 * MB));
  await flush();
  assert.ok(requests.length >= 3);
  assert.ok(requests[2].offset >= 128 * MB);
});
test('retry timer from an obsolete playback window cannot displace seek download', async () => {
  const { session, requests, timers, file } = setup();
  session.noteReadHead(32 * MB, true);
  requests[0].reject({ message: 'temporary error' });
  await flush();
  session.noteReadHead(128 * MB, true);
  const current = requests.at(-1);
  for (const timer of [...timers]) timer();
  current.resolve(file(128 * MB, 64 * MB));
  await flush();
  assert.equal(requests.at(-1), current);
});
test('close silences late updates and callbacks and issues no further requests', async () => {
  const { session, requests, timers, file } = setup(); let calls = 0;
  session.subscribeProgress(() => calls++);
  session.start();session.close(); const before = calls;
  requests[0].resolve(file(0, 6 * MB));await flush();
  for (const timer of [...timers]) timer();
  assert.equal(requests.length, 1);assert.equal(calls, before);
});
test('cached seek retains real downloaded ranges and does not redownload them', () => {
  const { session, requests, update } = setup();
  update(128 * MB, 64 * MB);
  session.noteReadHead(128 * MB, true);
  assert.equal(requests.length, 0);
  assert.deepEqual(Array.from(session.bufferedRangesFlat()), [128 * MB, 192 * MB]);
});
test('a progress listener that seeks cannot have its new active request cleared by old completion', async () => {
  const { session, requests, file } = setup();let moved = false;
  session.subscribeProgress(buffered => {
    if (buffered > 0 && !moved) { moved = true;session.noteReadHead(128 * MB, true); }
  });
  session.start();requests[0].resolve(file(0, 6 * MB));await flush();
  assert.equal(requests.length, 2);
  assert.equal(requests[1].offset, 128 * MB);
});
