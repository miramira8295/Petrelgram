// Run the real image methods with a controlled cache/decoder. ArkUI build and
// decorators are excluded; device rendering/reactive scheduling still need a trace.
import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
const imported = await import(process.env.TYPESCRIPT_MODULE || 'typescript');
const ts = imported.default || imported;
const sourceOf = path => fs.readFileSync(new URL(path, import.meta.url), 'utf8');
function compile(source) {
  return ts.transpileModule(source.replace(/^import[\s\S]*?;\n/gm, '')
    .replace(/@(?:ComponentV2|ObservedV2)\s*/g, '')
    .replace(/@Monitor\([^\n]*\)\s*/g, '')
    .replace(/@(?:Require|Param|Event|Local|Trace)\s*/g, '')
    .replace(/\bexport /g, '').replace(/\bstruct /g, 'class '),
  { compilerOptions: { target: ts.ScriptTarget.ES2020 } }).outputText;
}
const componentSource = sourceOf('../entry/src/main/ets/pages/common/CachedImage.ets');
const componentJs = compile(componentSource.slice(0, componentSource.indexOf('  build() {')) +
  '}\nglobalThis.ImageComponent = CachedImage;');
const helpersJs = compile(sourceOf('../entry/src/main/ets/util/imageSwap.ets') + '\n' +
  sourceOf('../entry/src/main/ets/util/cachedImageSpec.ets'));
const scrollJs = compile(sourceOf('../entry/src/main/ets/util/scrollEffects.ets'));
const flush = async () => { for (let i = 0; i < 5; i++) await Promise.resolve(); };
const spec = changes => ({ path: '/a', boxWidth: 100, boxHeight: 80, sourceKey: 'f1',
  backdrop: '#D7DCE2', backdropImage: 'mini-a', deferBackdropOnScroll: true, ...changes });
function setup(initial = spec()) {
  const cache = new Map(), requests = [], cancelled = [], retained = [], released = [], pins = [], timers = new Map();
  const storage = new Map();
  let nextTimer = 1, ready = 0, synchronous = 0, now = 0;
  const key = r => [r.path, r.width, r.height, r.opaque].join('|');
  const context = vm.createContext({
    ImageFit: { Cover: 0 }, vp2px: n => n * 3, Date: { now: () => now },
    AppStorage: { get: k => storage.get(k), setOrCreate: (k, v) => storage.set(k, v) },
    setTimeout: (f, ms) => { const id = nextTimer++; timers.set(id, { run: f, at: now + ms }); return id; },
    clearTimeout: id => timers.delete(id),
    cachedPixelMap: r => cache.get(key(r)),
    cancelPixelMap: r => cancelled.push(r),
    loadPixelMap: r => new Promise(resolve => requests.push({ request: r, resolve })),
    loadPixelMapSync: () => { synchronous++; return undefined; },
    retainPixelMap: h => retained.push(h), releasePixelMap: h => released.push(h),
    pinPixelMap: h => pins.push(h), pinPixelMapBounded: (_r, h) => pins.push(h)
  });
  vm.runInContext(helpersJs + scrollJs + componentJs, context);
  const image = new context.ImageComponent();
  image.spec = initial; image.onReady = () => ready++;
  return { image, requests, cancelled, retained, released, pins, timers, context,
    handle: name => ({ pixelMap: { name } }),
    get ready() { return ready; }, get synchronous() { return synchronous; },
    put(h) { cache.set(key(image.request()), h); },
    scroll(active) { vm.runInContext(`setScrollActive(${active})`, context); },
    motion() { vm.runInContext('noteScrollPlaceholderMotion()', context); },
    elapse(ms) { now += ms; },
    fireDue() {
      for (const [id, timer] of [...timers]) {
        if (timer.at <= now) { timers.delete(id); timer.run(); }
      }
    },
    update(next) { image.spec = next; image.onSourceChanged(); }
  };
}
let count = 0;
async function check(name, fn) {
  try { await fn(); count++; } catch (e) { e.message = `${name}: ${e.message}`; throw e; }
}
await check('same-source recycle reseeds the held bitmap without decode or another retain', () => {
  const s = setup(); const h = s.handle('a'); s.put(h); s.image.aboutToAppear();
  s.image.aboutToRecycle(); s.image.pixelMap = undefined; s.image.spec = spec(); s.image.aboutToReuse();
  assert.equal(s.image.pixelMap, h.pixelMap); assert.equal(s.requests.length, 0);
  assert.equal(s.retained.length, 1); assert.equal(s.ready, 2);
  s.image.aboutToDisappear(); assert.deepEqual(s.released, [h]);
});
await check('new source clears old image and releases it while awaiting decode', async () => {
  const s = setup(); const a = s.handle('a'); s.put(a); s.image.aboutToAppear();
  s.update(spec({ path: '/b', sourceKey: 'f2' }));
  assert.equal(s.image.pixelMap, undefined); assert.deepEqual(s.released, [a]);
  const b = s.handle('b'); s.requests[0].resolve(b); await flush();
  assert.equal(s.image.pixelMap, b.pixelMap);
});
await check('same-source path upgrade keeps old bitmap until the new one is retained', async () => {
  const s = setup(); const a = s.handle('a'); s.put(a); s.image.aboutToAppear();
  s.update(spec({ path: '/better' })); assert.equal(s.image.pixelMap, a.pixelMap);
  assert.equal(s.released.length, 0);
  const b = s.handle('better'); s.requests[0].resolve(b); await flush();
  assert.equal(s.image.pixelMap, b.pixelMap); assert.deepEqual(s.released, [a]);
});
await check('dimension change keeps same-source pixels until replacement is ready', () => {
  const s = setup(); const a = s.handle('a'); s.put(a); s.image.aboutToAppear();
  s.update(spec({ boxWidth: 120 })); assert.equal(s.image.pixelMap, a.pixelMap);
  assert.equal(s.requests[0].request.width, 360);
});
await check('presentation change does not restart or cancel pending decode', async () => {
  const s = setup(); s.image.aboutToAppear();
  s.update(spec({ radius: 12, backdropImage: 'new-mini', backdrop: '#000', syncDisplay: true }));
  assert.equal(s.requests.length, 1); assert.equal(s.cancelled.length, 0);
  const h = s.handle('a'); s.requests[0].resolve(h); await flush();
  assert.equal(s.image.pixelMap, h.pixelMap);
});
await check('recycle cancels pending decode and rejects its late result after reuse', async () => {
  const s = setup(); s.image.aboutToAppear(); s.image.aboutToRecycle();
  s.image.pixelMap = undefined; s.image.spec = spec({ path: '/b', sourceKey: 'f2' }); s.image.aboutToReuse();
  s.requests[0].resolve(s.handle('late-a')); await flush();
  assert.equal(s.image.pixelMap, undefined); assert.equal(s.cancelled.length, 1);
  assert.equal(s.retained.length, 0);
  const b = s.handle('b'); s.requests[1].resolve(b); await flush(); assert.equal(s.image.pixelMap, b.pixelMap);
});
await check('destroy cancels pending work and rejects a late decoded image', async () => {
  const s = setup(); s.image.aboutToAppear(); s.image.aboutToDisappear();
  s.requests[0].resolve(s.handle('late')); await flush();
  assert.equal(s.retained.length, 0); assert.equal(s.cancelled.length, 1); assert.equal(s.ready, 0);
});
await check('invalid image target stays empty without decoding', () => {
  const s = setup(spec({ boxWidth: 0 })); s.image.aboutToAppear();
  assert.equal(s.requests.length, 0); assert.equal(s.image.pixelMap, undefined);
});
await check('opaque format change cannot reuse a bitmap decoded under the old policy', () => {
  const s = setup(); const a = s.handle('rgba'); s.put(a); s.image.aboutToAppear();
  s.update(spec({ opaque: true })); assert.equal(s.requests.length, 1);
  assert.equal(s.requests[0].request.opaque, true);
});
await check('avatar sync decode and bounded pin policies still reach the cache', async () => {
  const s = setup(spec({ syncSmall: true, pinBounded: true })); s.image.aboutToAppear();
  assert.equal(s.synchronous, 1); const a = s.handle('a'); s.requests[0].resolve(a); await flush();
  assert.deepEqual(s.pins, [a]); assert.equal(s.ready, 1);
});
await check('album mini is suppressed throughout drag/inertia including beyond animation watchdog', () => {
  const s = setup(); assert.equal(s.image.showMiniPlaceholder(), true);
  s.scroll(true); assert.equal(s.image.showMiniPlaceholder(), false);
  s.elapse(2000); s.motion(); s.elapse(1000); s.fireDue();
  assert.equal(vm.runInContext('scrollActiveNow()', s.context), false);
  assert.equal(s.image.showMiniPlaceholder(), false);
  s.scroll(false); assert.equal(s.image.showMiniPlaceholder(), true);
  assert.equal(s.requests.length, 0);
});
await check('already decoded image never subscribes to scrolling or reverts to mini', () => {
  const s = setup(); const a = s.handle('a'); s.put(a); s.image.aboutToAppear();
  s.image.scrollState = { get active() { throw Error('loaded image subscribed to scroll'); } };
  assert.equal(s.image.showMiniPlaceholder(), false); assert.equal(s.image.pixelMap, a.pixelMap);
});
await check('other image callers do not subscribe to album scroll policy', () => {
  const s = setup(spec({ deferBackdropOnScroll: false }));
  s.image.scrollState = { get active() { throw Error('non-album image subscribed to scroll'); } };
  assert.equal(s.image.showMiniPlaceholder(), true);
});
await check('stopping after decode completed does not restore a mini overlay', async () => {
  const s = setup(); s.scroll(true); s.image.aboutToAppear();
  const h = s.handle('a'); s.requests[0].resolve(h); await flush(); s.scroll(false);
  assert.equal(s.image.showMiniPlaceholder(), false); assert.equal(s.image.pixelMap, h.pixelMap);
});
await check('equivalent upstream snapshots preserve image input identity; upgrades replace it', () => {
  const s = setup(); const cache = vm.runInContext('new CachedImageSpecCache()', s.context);
  const a = cache.prepare(spec()); assert.equal(cache.prepare(spec()), a);
  const b = cache.prepare(spec({ backdropImage: 'b' })); assert.notEqual(b, a);
  assert.equal(a.backdropImage, 'mini-a'); assert.equal(cache.prepare(spec({ backdropImage: 'b' })), b);
  const c = cache.prepare(spec({ path: '/new' })); assert.notEqual(c, b);
});
await check('missing scroll stop eventually restores mini after motion becomes idle', () => {
  const s = setup(); s.scroll(true); s.elapse(2000); s.motion(); s.elapse(1000); s.fireDue();
  assert.equal(s.image.showMiniPlaceholder(), false);
  s.elapse(2000); s.fireDue(); assert.equal(s.image.showMiniPlaceholder(), true);
  assert.equal(s.timers.size, 0);
});
await check('normal stop/page hide cancels watchdogs before the next scroll begins', () => {
  const s = setup(); s.scroll(true); s.elapse(1000); s.scroll(false);
  assert.equal(s.timers.size, 0); assert.equal(s.image.showMiniPlaceholder(), true);
  s.scroll(true); s.elapse(2000); s.fireDue(); assert.equal(s.image.showMiniPlaceholder(), false);
  s.scroll(false); assert.equal(s.image.showMiniPlaceholder(), true);
});
await check('a prolonged fling stays suppressed across multiple watchdog windows', () => {
  const s = setup(); s.scroll(true);
  for (let i = 0; i < 10; i++) { s.elapse(1000); s.motion(); s.fireDue(); }
  assert.equal(s.image.showMiniPlaceholder(), false); s.scroll(false);
  assert.equal(s.image.showMiniPlaceholder(), true);
});
await check('movement after an idle timeout suppresses mini even without a second start event', () => {
  const s = setup(); s.scroll(true); s.elapse(3000); s.fireDue();
  assert.equal(s.image.showMiniPlaceholder(), true); s.motion();
  assert.equal(s.image.showMiniPlaceholder(), false); assert.equal(s.timers.size, 1);
  s.scroll(false); assert.equal(s.image.showMiniPlaceholder(), true); assert.equal(s.timers.size, 0);
});
console.log(`Cached image lifecycle: ${count} scenarios passed`);
