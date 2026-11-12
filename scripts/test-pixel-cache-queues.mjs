// Execute the real cache with deterministic worker/timer/native image IO.
import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
const imported = await import(process.env.TYPESCRIPT_MODULE || 'typescript');
const ts = imported.default || imported;
const base = 'entry/src/main/ets/util/';
const flush = async () => { for (let i = 0; i < 12; i++) await Promise.resolve(); };
function rig(file) {
  const jobs = [], timers = new Map(), freed = [], errors = [];
  let nextTimer = 0;
  function pixels(name, width = 24, height = 16) {
    return { name, getImageInfo: async () => ({ size: { width, height }, stride: width * 4 }),
      getImageInfoSync: () => ({ size: { width, height }, stride: width * 4 }),
      release: () => freed.push(name) };
  }
  const ctx = vm.createContext({
    IMAGE_CAP_BYTES: 1e9, imagePixelLimitNow: n => n, IMAGE_HOLDER_RELEASE_BATCH: 7,
    syncDecodeEligible: () => true, decodeSendable() {}, logE: s => errors.push(s),
    taskpool: { execute: (_fn, name) => new Promise(resolve => jobs.push({ name, resolve })) },
    sendableImage: { convertToPixelMap: p => p },
    image: { PixelMapFormat: { RGB_565: 1 }, createImageSource: name => ({
      createPixelMapSync: () => pixels(name), release() {} }) },
    setTimeout: fn => { timers.set(++nextTimer, fn); return nextTimer; },
    clearTimeout: id => timers.delete(id)
  });
  for (const path of [base + 'pixelCacheKey.ets', base + 'boundedPins.ets', file]) {
    const text = fs.readFileSync(path, 'utf8').replace(/^import\s[\s\S]*?;\r?\n/gm, '').replace(/\bexport /g, '');
    vm.runInContext(ts.transpileModule(text, { compilerOptions: { target: ts.ScriptTarget.ES2020 } }).outputText, ctx);
  }
  vm.runInContext('globalThis.PixelHandle = PixelHandle', ctx);
  return { ctx, jobs, freed, errors, timers, pixels, request: name => ({ path: name, width: 24, height: 16, opaque: true }),
    drain() { let batches = 0; while (timers.size) {
      const [id, fn] = timers.entries().next().value; timers.delete(id); fn(); batches++;
      assert.ok(batches < 10000, 'release queue must terminate');
    } return batches; }
  };
}
async function exercise(file) {
  const r = rig(file), c = r.ctx, req = r.request;
  const promises = [];
  for (let i = 0; i < 100; i++) promises.push(c.loadPixelMap(req(String(i))));
  assert.deepEqual(r.jobs.map(j => j.name), ['0', '1', '2']);
  const shared = c.loadPixelMap(req('77'));
  c.cancelPixelMap(req('77')); // one live waiter remains
  for (let i = 3; i < 100; i += 2) if (i !== 77) c.cancelPixelMap(req(String(i)));
  const takeover = c.loadPixelMapSync(req('50'));
  assert.equal((await promises[50]), takeover);
  for (let index = 0; index < r.jobs.length; index++) {
    const job = r.jobs[index]; job.resolve(r.pixels(job.name)); await flush();
  }
  const handles = await Promise.all(promises);
  assert.equal(await shared, handles[77]);
  const expected = Array.from({length: 100}, (_, i) => i)
    .filter(i => i < 3 || i === 77 || (i % 2 === 0 && i !== 50)).map(String);
  assert.deepEqual(r.jobs.map(j => j.name), expected, 'FIFO after arbitrary cancellation and sync takeover');
  for (const h of handles) if (h) c.retainPixelMap(h);
  r.drain();
  const held = handles.filter(Boolean);
  c.pinPixelMap(held[1]);
  c.cachedPixelMap(req('0')); // bump LRU
  c.setPixelCacheBudget(0); c.trimPixelCache(0); r.drain();
  assert.equal(r.freed.length, 0, 'eviction must preserve holders');
  for (const h of held) c.releasePixelMap(h);
  r.drain();
  assert.equal(r.freed.length, held.length - 1, 'pinned bitmap survives');
  c.unpinPixelMap(held[1]); c.setPixelCacheBudget(0); c.trimPixelCache(0); r.drain();
  assert.equal(r.freed.length, held.length);
  assert.equal(new Set(r.freed).size, r.freed.length, 'release exactly once');
  assert.deepEqual(r.errors, []);
  return { jobs: r.jobs.map(j => j.name), freed: r.freed };
}
const current = base + 'pixelCache.ets';
const result = await exercise(current);
if (process.argv[2]) assert.deepEqual(result, await exercise(process.argv[2]), 'same decode order and ownership as baseline');
{
  const r = rig(current), c = r.ctx;
  const pending = c.loadPixelMap(r.request('cancel-active'));
  c.cancelPixelMap(r.request('cancel-active'));
  r.jobs[0].resolve(r.pixels('cancel-active', 123, 45)); await flush();
  const h = await pending;
  assert.equal(h.width, 123); assert.equal(h.height, 45, 'decoder metadata travels with the handle');
  r.drain(); c.setPixelCacheBudget(0); c.trimPixelCache(0); r.drain(); assert.deepEqual(r.freed, ['cancel-active']);
}
{
  // A long teardown crosses compaction boundaries and receives more releases
  // between timer ticks. The reference accounting must remain identical.
  const r = rig(current), c = r.ctx, handles = [];
  for (let i = 0; i < 5000; i++) {
    const h = new c.PixelHandle(r.pixels('release-' + i), 4); handles.push(h); c.releasePixelMap(h);
  }
  const [id, fn] = r.timers.entries().next().value; r.timers.delete(id); fn();
  assert.equal(r.freed.length, 7, 'bounded work per event-loop turn');
  const extra = new c.PixelHandle(r.pixels('late-release'), 4); c.releasePixelMap(extra);
  r.drain(); assert.equal(r.freed.length, 5001); assert.equal(new Set(r.freed).size, 5001);
  assert.ok(handles.every(h => h.refs === 0 && h.released));
}
{
  const r = rig(current), c = r.ctx, count = 10007;
  for (let i = 0; i < count + 3; i++) c.loadPixelMap(r.request('bulk-' + i));
  assert.equal(r.jobs.length, 3);
  vm.runInContext(`{
    let previous, cursor = queueHead, visited = 0;
    while (cursor !== undefined) {
      if (cursor.previous !== previous || !cursor.queued) throw Error('broken queue link');
      previous = cursor; cursor = cursor.next; visited++;
    }
    if (previous !== queueTail || visited !== 10007) throw Error('bad queue endpoints');
  }`, c);
  // A permutation removes heads, tails and middle nodes without array scans.
  for (let i = 0; i < count; i++) c.cancelPixelMap(r.request('bulk-' + (3 + i * 7919 % count)));
  assert.equal(vm.runInContext('queueHead === undefined && queueTail === undefined && pending.size === 3', c), true);
  for (const job of r.jobs) job.resolve(r.pixels(job.name));
  await flush(); r.drain(); c.trimPixelCache(0); r.drain();
  assert.equal(r.jobs.length, 3); assert.equal(r.freed.length, 3);
}
console.log('PASS: FIFO/shared waiters/cancellation/sync takeover, baseline parity, pinned LRU ownership, 5001 batched releases, 10007 arbitrary queue removals and decode metadata.');
