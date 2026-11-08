import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
const imported = await import(process.env.TYPESCRIPT_MODULE || 'typescript');
const ts = imported.default || imported;
const source = fs.readFileSync('entry/src/main/ets/util/videoRelease.ets', 'utf8');
const context = vm.createContext({ exports: {} });
vm.runInContext(ts.transpileModule(source, {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
}).outputText, context);
const releaseVideoResources = (player, sources) => context.exports.releaseVideoResources(
  player === null ? null : () => player.releaseAsync(), () => player?.release(),
  sources.filter(source => source !== null).map(source => () => source.close()));
function deferred() {
  let resolve, reject;
  const promise = new Promise((ok, bad) => { resolve = ok; reject = bad; });
  return { promise, resolve, reject };
}
test('UI caller returns while native release is pending; sources stay alive', async () => {
  const native = deferred(), events = [];
  const done = releaseVideoResources({ releaseAsync: () => native.promise,
    release: () => { throw new Error('synchronous release on normal path'); } },
  ['http', 'tdfile', 'session'].map(name => ({ close: () => events.push(name) })));
  await Promise.resolve();
  assert.deepEqual(events, []);
  native.resolve(true); await done;
  assert.deepEqual(events, ['http', 'tdfile', 'session']);
});
test('overlapping generations only close their own detached resources', async () => {
  const a = deferred(), b = deferred(), closed = [];
  const player = native => ({ releaseAsync: () => native.promise, release() { assert.fail(); } });
  const first = releaseVideoResources(player(a), [{ close: () => closed.push('old') }]);
  const second = releaseVideoResources(player(b), [{ close: () => closed.push('new') }]);
  a.resolve(true); await first; assert.deepEqual(closed, ['old']);
  b.resolve(true); await second; assert.deepEqual(closed, ['old', 'new']);
});
for (const failure of ['throw', 'reject', 'false']) {
  test(`native ${failure} recovers before closing its source`, async () => {
    const events = [];
    await releaseVideoResources({ releaseAsync() {
      if (failure === 'throw') throw new Error('queue failed');
      return failure === 'reject' ? Promise.reject(new Error('queue failed')) : Promise.resolve(false);
    }, release() { events.push('release'); } }, [{ close() { events.push('close'); } }]);
    assert.deepEqual(events, ['release', 'close']);
  });
}
test('failed recovery preserves sources still potentially owned by a decoder', async () => {
  let closed = false;
  await assert.rejects(releaseVideoResources({ releaseAsync: () => Promise.resolve(false),
    release() { throw new Error('native failure'); } }, [{ close() { closed = true; } }]), /native failure/);
  assert.equal(closed, false);
});
test('preparation cancelled before player creation still closes its sources', async () => {
  let closed = 0;
  await releaseVideoResources(null, [null, { close() { closed++; } }, null]);
  assert.equal(closed, 1);
});
test('one failed source close does not prevent the remaining sources closing', async () => {
  const closed = [];
  await assert.rejects(releaseVideoResources(null, [
    { close() { throw new Error('close failed'); } }, { close() { closed.push('session'); } }
  ]), /cleanup failed/);
  assert.deepEqual(closed, ['session']);
});
