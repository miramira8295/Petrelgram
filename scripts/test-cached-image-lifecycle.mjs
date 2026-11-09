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
    .replace(/@(?:Require|Param|Event|Local|Trace|BuilderParam)\s*/g, '')
    .replace(/\bexport /g, '').replace(/\bstruct /g, 'class '),
  { compilerOptions: { target: ts.ScriptTarget.ES2020 } }).outputText;
}
const componentSource = sourceOf('../entry/src/main/ets/pages/common/CachedImage.ets');
const componentJs = compile(componentSource.slice(0, componentSource.indexOf('  build() {')) +
  '}\nglobalThis.ImageComponent = CachedImage;');
const liveSource = sourceOf('../entry/src/main/ets/pages/chat/LiveThumbImage.ets');
const liveJs = compile(liveSource.slice(0, liveSource.indexOf('  @Builder\n')) +
  '}\nglobalThis.ThumbComponent = LiveThumbImage;');
const helpersJs = compile(sourceOf('../entry/src/main/ets/util/imageSwap.ets') + '\n' +
  sourceOf('../entry/src/main/ets/util/cachedImageSpec.ets') + '\n' +
  sourceOf('../entry/src/main/ets/util/CachedImageSession.ets') + '\n' +
  sourceOf('../entry/src/main/ets/util/liveThumbPath.ets') + '\n' +
  sourceOf('../entry/src/main/ets/util/liveThumbAttach.ets') + '\n' +
  sourceOf('../entry/src/main/ets/util/mediaThumbChannel.ets') + '\n' +
  sourceOf('../entry/src/main/ets/util/messageRowPresentationChannel.ets'));
const scrollJs = compile(sourceOf('../entry/src/main/ets/util/scrollEffects.ets'));
const flush = async () => { for (let i = 0; i < 5; i++) await Promise.resolve(); };
const spec = changes => ({ path: '/a', boxWidth: 100, boxHeight: 80, sourceKey: 'f1',
  backdrop: '#D7DCE2', backdropImage: 'mini-a', deferBackdropOnScroll: true, ...changes });
function setup(initial = spec(), thumbnail = false) {
  const cache = new Map(), requests = [], cancelled = [], retained = [], released = [], pins = [], timers = new Map();
  const storage = new Map();
  let nextTimer = 1, ready = 0, synchronous = 0, now = 0, density = 3;
  const key = r => [r.path, r.width, r.height, r.opaque === true].join('|');
  const context = vm.createContext({
    ImageFit: { Cover: 0 }, warnStaleThumbAttach() {}, vp2px: n => n * density, Date: { now: () => now },
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
  vm.runInContext(helpersJs + scrollJs + componentJs + liveJs, context);
  const image = thumbnail ? new context.ThumbComponent() : new context.ImageComponent();
  function assign(next) {
    image.spec = thumbnail ? {fileId: next.sourceKey ? Number(next.sourceKey.slice(1)) : 0,
      initialPath:next.path, boxWidth:next.boxWidth, boxHeight:next.boxHeight, radius:next.radius ?? 0,
      fit:next.fit ?? 0, opaque:next.opaque === true, backdrop:next.backdrop ?? '', mini:next.backdropImage ?? '',
      syncDisplay:next.syncDisplay === true, deferMiniOnScroll:next.deferBackdropOnScroll === true} : next;
  }
  assign(initial); image.onReady = () => ready++;
  return { image, requests, cancelled, retained, released, pins, timers, context,
    handle: name => ({ pixelMap: { name } }),
    setDensity(next) { density = next; },
    get ready() { return ready; }, get synchronous() { return synchronous; },
    put(h, override) {
      const current = override ?? (thumbnail ? { ...image.spec, path:image.spec.initialPath } : image.spec);
      cache.set(key({path:current.path,width:current.boxWidth*3,height:current.boxHeight*3,opaque:current.opaque === true}),h);
    },
    publish(fileId, path) {
      context.fileId = fileId; context.newPath = path;
      vm.runInContext('publishThumbPath(fileId, newPath)', context);
    },
    listeners(fileId) {
      context.fileId = fileId;
      return vm.runInContext('subs.get(fileId)?.size ?? 0', context);
    },
    scroll(active) { vm.runInContext(`setScrollActive(${active})`, context); },
    motion() { vm.runInContext('noteScrollPlaceholderMotion()', context); },
    elapse(ms) { now += ms; },
    fireDue() {
      for (const [id, timer] of [...timers]) {
        if (timer.at <= now) { timers.delete(id); timer.run(); }
      }
    },
    update(next) { assign(next); if (thumbnail) image.onSpecChanged(); else image.onSourceChanged(); },
    reuse(next) { assign(next); image.pixelMap = undefined; if (thumbnail) image.path = ''; image.aboutToReuse(); }
  };
}
let count = 0;
async function check(name, fn) {
  try { await fn(); count++; } catch (e) { e.message = `${name}: ${e.message}`; throw e; }
}
await check('album file delivery draws the bitmap with no row callback and retains the latest snapshot', async () => {
  const s = setup(spec({path:''}), true);
  s.image.aboutToAppear();
  const group = path => ({key:'album-1', head:{id:1,rowId:1,contentType:'photo',photoFileId:1,photoPath:path},
    memberIds:[1,2],photoFileIds:[1,2],photoPaths:[path,''],photoFailed:[false,false],photoIsVideo:[false,false]});
  const first = group('');
  s.context.publishMessageRowPresentations(123, [first]);
  let rows = 0;
  const unsub = s.context.subscribeMessageRowPresentation(123, 1, () => rows++);
  const input = s.image.spec;
  s.publish(1, '/downloaded');
  const next = group('/downloaded');
  s.context.publishMessageRowPresentations(123, [next]);
  assert.equal(rows, 0); assert.equal(s.image.spec, input);
  assert.equal(s.context.messageRowPresentationFor(123, 1), next);
  assert.equal(s.requests.length, 1);
  const bitmap = s.handle('downloaded'); s.requests[0].resolve(bitmap); await flush();
  assert.equal(s.image.pixelMap, bitmap.pixelMap);
  unsub(); s.image.aboutToDisappear();
  assert.deepEqual(s.released, [bitmap]);
});
await check('thumbnail spec checks every presentation and decode field without mutating the prior spec', () => {
  const changes={fileId:2,boxWidth:121,boxHeight:91,radius:4,fit:1,syncDisplay:true,
    opaque:true,backdrop:'#fff',mini:'mini-b',deferMiniOnScroll:false};
  for (const [field,value] of Object.entries(changes)) {
    const s=setup(spec(),true);s.image.aboutToAppear();const first=s.image.imageSpec();
    const saved=JSON.stringify(first);
    s.image.spec={...s.image.spec};assert.equal(s.image.imageSpec(),first);
    // Mutating the input in place must also be noticed; no identity-only shortcut.
    s.image.spec[field]=value;const next=s.image.imageSpec();
    assert.notEqual(next,first,field);assert.equal(JSON.stringify(first),saved);
    assert.equal(s.image.imageSpec(),next);s.image.aboutToDisappear();
  }
});
await check('thumbnail spec identity is stable until the independent channel path changes', () => {
  const s=setup(spec(),true);s.image.aboutToAppear();const first=s.image.imageSpec();
  assert.equal(s.image.imageSpec(),first);s.publish(1,'/new-path');const next=s.image.imageSpec();
  assert.notEqual(next,first);assert.equal(next.path,'/new-path');assert.equal(first.path,'/a');
  assert.equal(s.image.imageSpec(),next);s.image.aboutToDisappear();
});
await check('same-source recycle reseeds the held bitmap without decode or another retain', () => {
  const s = setup(); const h = s.handle('a'); s.put(h); s.image.aboutToAppear();
  s.image.aboutToRecycle(); s.image.pixelMap = undefined; s.image.spec = spec(); s.image.aboutToReuse();
  assert.equal(s.image.pixelMap, h.pixelMap); assert.equal(s.requests.length, 0);
  assert.equal(s.retained.length, 1); assert.equal(s.ready, 2);
  s.image.aboutToDisappear(); assert.deepEqual(s.released, [h]);
});
await check('repeated same-target activation reseeds without replacing ownership', () => {
  const s = setup(); const h = s.handle('a'); s.put(h); s.image.aboutToAppear();
  for (let i = 0; i < 1000; i++) { s.image.aboutToRecycle(); s.reuse(spec()); }
  assert.equal(s.image.pixelMap, h.pixelMap); assert.equal(s.ready, 1001);
  assert.equal(s.retained.length, 1); assert.equal(s.released.length, 0); assert.equal(s.requests.length, 0);
  s.image.aboutToDisappear(); assert.deepEqual(s.released, [h]);
});
await check('same-spec activation still re-evaluates density before reusing pixels', () => {
  const s = setup(); const h = s.handle('a'); s.put(h); s.image.aboutToAppear();
  s.image.aboutToRecycle(); s.setDensity(4); s.reuse(spec());
  assert.equal(s.requests.length, 1); assert.equal(s.requests[0].request.width, 400);
  assert.equal(s.requests[0].request.height, 320); assert.equal(s.image.pixelMap, h.pixelMap);
});
await check('equal path under a different source identity cannot keep old ownership', () => {
  const s = setup(); const h = s.handle('a'); s.put(h); s.image.aboutToAppear();
  s.image.aboutToRecycle(); s.reuse(spec({sourceKey:'f2'}));
  assert.deepEqual(s.released, [h]); assert.equal(s.retained.length, 2);
  assert.equal(s.image.pixelMap, h.pixelMap); assert.equal(s.ready, 2);
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
// The same shared session now drives the directly rendered live thumbnail.
// Exercise actual path notifications together with decode/retain/cancel timing.
await check('live thumbnail cache hit displays synchronously and owns exactly one reference', () => {
  const s = setup(spec({opaque:true,syncDisplay:true}),true), h=s.handle('a'); s.put(h);
  s.image.aboutToAppear(); assert.equal(s.image.pixelMap,h.pixelMap); assert.equal(s.requests.length,0);
  assert.equal(s.retained.length,1); assert.equal(s.listeners(1),1);
  s.image.aboutToDisappear(); assert.deepEqual(s.released,[h]); assert.equal(s.listeners(1),0);
});
await check('live same-source reuse reseeds both path and pixels without another retain', () => {
  const initial=spec({opaque:true}), s=setup(initial,true), h=s.handle('a');s.put(h);s.image.aboutToAppear();
  s.image.aboutToRecycle(); s.reuse(initial);
  assert.equal(s.image.path,'/a');assert.equal(s.image.pixelMap,h.pixelMap);
  assert.equal(s.requests.length,0);assert.equal(s.retained.length,1);assert.equal(s.listeners(1),1);
});
await check('live new-source reuse clears old pixels and rejects the previous file channel', async () => {
  const s=setup(spec(),true),h=s.handle('a');s.put(h);s.image.aboutToAppear();s.image.aboutToRecycle();
  s.reuse(spec({path:'/b',sourceKey:'f2'}));assert.equal(s.image.pixelMap,undefined);assert.deepEqual(s.released,[h]);
  s.publish(1,'/late-a');assert.equal(s.image.path,'/b');assert.equal(s.requests.length,1);
  const b=s.handle('b');s.requests[0].resolve(b);await flush();assert.equal(s.image.pixelMap,b.pixelMap);
});
await check('live path-only input replacement cancels the obsolete waiter', async () => {
  const s=setup(spec({sourceKey:''}),true);s.image.aboutToAppear();
  s.update(spec({path:'/b',sourceKey:''}));assert.equal(s.cancelled.length,1);assert.equal(s.requests.length,2);
  s.requests[0].resolve(s.handle('late'));await flush();assert.equal(s.retained.length,0);
  const b=s.handle('b');s.requests[1].resolve(b);await flush();assert.equal(s.image.pixelMap,b.pixelMap);
});
await check('live downloaded path starts decoding without any parent spec update', async () => {
  const s=setup(spec({path:''}),true);s.image.aboutToAppear();assert.equal(s.requests.length,0);
  const input=s.image.spec;s.publish(1,'/downloaded');assert.equal(s.image.spec,input);assert.equal(s.requests.length,1);
  const h=s.handle('downloaded');s.requests[0].resolve(h);await flush();assert.equal(s.image.pixelMap,h.pixelMap);
});
await check('live same-file channel upgrade retains old pixels until new pixels are ready', async () => {
  const s=setup(spec(),true),a=s.handle('a');s.put(a);s.image.aboutToAppear();s.publish(1,'/better');
  assert.equal(s.image.pixelMap,a.pixelMap);assert.equal(s.released.length,0);
  const b=s.handle('better');s.requests[0].resolve(b);await flush();assert.equal(s.image.pixelMap,b.pixelMap);
  assert.deepEqual(s.released,[a]);assert.deepEqual(s.retained,[a,b]);
});
await check('live resize during decode cancels the old-size request and rejects its completion', async () => {
  const s=setup(spec(),true);s.image.aboutToAppear();s.update(spec({boxWidth:120}));
  assert.equal(s.cancelled.length,1);assert.equal(s.requests[1].request.width,360);
  s.requests[0].resolve(s.handle('wrong-size'));await flush();assert.equal(s.retained.length,0);
  const h=s.handle('correct-size');s.requests[1].resolve(h);await flush();assert.equal(s.image.pixelMap,h.pixelMap);
});
await check('live presentation-only updates neither cancel nor restart decode', async () => {
  const s=setup(spec(),true);s.image.aboutToAppear();
  s.update(spec({radius:6,syncDisplay:true,backdropImage:'mini-b'}));assert.equal(s.requests.length,1);assert.equal(s.cancelled.length,0);
  const h=s.handle('a');s.requests[0].resolve(h);await flush();assert.equal(s.image.pixelMap,h.pixelMap);
});
await check('live recycled nodes release listeners and reject late decode while keeping held pixels', async () => {
  const s=setup(spec(),true),h=s.handle('a');s.put(h);s.image.aboutToAppear();s.publish(1,'/better');
  s.image.aboutToRecycle();assert.equal(s.listeners(1),0);assert.equal(s.cancelled.length,1);
  s.requests[0].resolve(s.handle('late'));await flush();assert.deepEqual(s.retained,[h]);assert.equal(s.released.length,0);
  s.image.aboutToDisappear();s.image.aboutToDisappear();assert.deepEqual(s.released,[h]);
});
await check('live thumbnail mini obeys scrolling and never replaces decoded pixels', async () => {
  const s=setup(spec(),true);s.image.aboutToAppear();assert.equal(s.image.showMiniPlaceholder(),true);
  s.scroll(true);assert.equal(s.image.showMiniPlaceholder(),false);s.scroll(false);assert.equal(s.image.showMiniPlaceholder(),true);
  const h=s.handle('a');s.requests[0].resolve(h);await flush();
  s.image.scrollState={get active(){throw Error('decoded live image observed scroll');}};
  assert.equal(s.image.showMiniPlaceholder(),false);assert.equal(s.image.pixelMap,h.pixelMap);
});
await check('shared session does not decode from monitor updates while recycled', () => {
  for (const thumbnail of [false,true]) {
    const s=setup(spec(),thumbnail);s.image.aboutToAppear();s.image.aboutToRecycle();
    s.update(spec({path:'/b',sourceKey:thumbnail?'':'f2'}));assert.equal(s.requests.length,1);
    s.reuse(spec({path:'/b',sourceKey:thumbnail?'':'f2'}));assert.equal(s.requests.length,2);
  }
});
await check('shared session reactivation after disposal never exposes an unowned old bitmap', () => {
  for (const thumbnail of [false,true]) {
    const initial=spec({sourceKey:''}),s=setup(initial,thumbnail),h=s.handle('a');s.put(h);s.image.aboutToAppear();
    s.image.aboutToDisappear();s.update(spec({path:'/b',sourceKey:''}));s.image.aboutToAppear();
    assert.equal(s.image.pixelMap,undefined);assert.deepEqual(s.released,[h]);assert.equal(s.requests.length,1);
  }
});
await check('synchronous different-source cache hit publishes only the replacement', () => {
  for (const thumbnail of [false,true]) {
    const s=setup(spec(),thumbnail),a=s.handle('a'),b=s.handle('b');s.put(a);s.image.aboutToAppear();
    const values=[],publish=s.image.imageSession.publish;
    s.image.imageSession.publish=(pixels,ready)=>{values.push(pixels);publish(pixels,ready);};
    const next=spec({path:'/b',sourceKey:'f2'});s.put(b,next);if(thumbnail)s.publish(2,'/b');s.update(next);
    assert.deepEqual(values,[b.pixelMap]);assert.deepEqual(s.released,[a]);assert.equal(s.requests.length,0);
  }
});
console.log(`Cached image lifecycle: ${count} scenarios passed`);
