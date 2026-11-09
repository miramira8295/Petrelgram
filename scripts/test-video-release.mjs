import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
const imported = await import(process.env.TYPESCRIPT_MODULE || 'typescript');
const ts = imported.default || imported;
const source = fs.readFileSync('entry/src/main/ets/util/videoRelease.ets', 'utf8');
const compiled = ts.transpileModule(source, {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
}).outputText;
function load(timer = setTimeout) {
  const context = vm.createContext({ exports: {}, setTimeout: timer });
  vm.runInContext(compiled, context);
  return context.exports.enqueueNativeReleaseSync;
}
test('caller returns before native work; teardown precedes all source closes', async () => {
  const release = load(), events = [];
  const done = release(() => events.push('native'), [() => events.push('http'), () => events.push('tdfile')]);
  assert.deepEqual(events, []);
  await done;
  assert.deepEqual(events, ['native', 'http', 'tdfile']);
});
test('queued generations retain their own detached resources and source list', async () => {
  const release = load(), events = [], oldSources = [() => events.push('old-source')];
  const a = release(() => events.push('old-player'), oldSources);
  oldSources[0] = () => events.push('wrong-source');
  const b = release(() => events.push('new-player'), [() => events.push('new-source')]);
  await Promise.all([a, b]);
  assert.deepEqual(events, ['old-player', 'old-source', 'new-player', 'new-source']);
});
for (const failure of [new Error('native failure'), 'native failure', undefined]) {
  test(`native throw (${typeof failure}) is reported once and preserves decoder-owned sources`, async () => {
    const release = load(); let releases = 0, closed = false;
    await assert.rejects(release(() => { releases++; throw failure; }, [() => { closed = true; }]), /Native video release failed/);
    assert.equal(releases, 1); assert.equal(closed, false);
  });
}
test('native failure does not poison the next queued release', async () => {
  const release = load(), events = [];
  const failed = release(() => { throw new Error('first'); }, [() => events.push('unsafe-close')]);
  const observed = assert.rejects(failed, /first/);
  const next = release(() => events.push('next-native'), [() => events.push('next-close')]);
  await Promise.all([observed, next]);
  assert.deepEqual(events, ['next-native', 'next-close']);
});
test('close failures are reported after attempting every remaining source', async () => {
  const release = load(), events = [];
  await assert.rejects(release(() => events.push('native'), [
    () => { events.push('http'); throw new Error('http-failed'); },
    () => { events.push('tdfile'); throw new Error('td-failed'); },
    () => events.push('session')
  ]), /Video source cleanup failed: Error: http-failed/);
  await release(() => events.push('next'), []);
  assert.deepEqual(events, ['native', 'http', 'tdfile', 'session', 'next']);
});
test('cancelled preparation with no player still closes its sources', async () => {
  const release = load(); let closed = 0;
  await release(null, [() => closed++]); await release(null, []);
  assert.equal(closed, 1);
});
test('release failure rejects the caller success path (live count stays unchanged)', async () => {
  const release = load(); let live = 1, logged = false;
  await release(() => { throw new Error('failed'); }, [])
    .then(() => live--).catch(() => { logged = true; });
  assert.equal(live, 1); assert.equal(logged, true);
  await release(() => {}, []).then(() => live--);
  assert.equal(live, 0);
});
test('each release has a separate timer turn; microtasks alone cannot drain a batch', async () => {
  const timers = [], events = [];
  const release = load(fn => { timers.push(fn); return timers.length; });
  const a = release(() => events.push('a'), []);
  const b = release(() => events.push('b'), []);
  await Promise.resolve(); assert.equal(timers.length, 1); assert.deepEqual(events, []);
  timers.shift()(); await a; await Promise.resolve();
  assert.deepEqual(events, ['a']); assert.equal(timers.length, 1);
  timers.shift()(); await b; assert.deepEqual(events, ['a', 'b']);
});
test('a large batch releases every player once, including jobs after failures', async () => {
  const release = load(), calls = [], closed = [];
  await Promise.all(Array.from({ length: 30 }, (_, i) => {
    const job = release(() => { calls.push(i); if (i === 7) throw new Error('fail-7'); }, [() => closed.push(i)]);
    return i === 7 ? assert.rejects(job, /fail-7/) : job;
  }));
  assert.deepEqual(calls, Array.from({ length: 30 }, (_, i) => i));
  assert.deepEqual(closed, calls.filter(i => i !== 7));
});
