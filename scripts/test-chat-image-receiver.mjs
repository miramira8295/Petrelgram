// Run after a debug HAP build. Exercises real session and compiled component
// lifecycle code; mocks only platform drawing/cache IO, not the swap policy.
import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
const imported = await import(process.env.TYPESCRIPT_MODULE || 'typescript');
const ts = imported.default || imported;
const compiled = 'entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/';
const fit = { Cover: 0, Contain: 1, Fill: 2 };
let density = 2, infoReads = 0, samples = 0, invalidations = 0, loads = 0;
let nodes = [], current;
const ui = { vp2px: n => n * density };
const cache = new Map(), pending = [], channels = new Map(), subscribers = new Map();
const requestKey = r => `${r.path}:${r.width}:${r.height}:${r.opaque}`;
class ViewV2 {
  initParam(k, v) { this[k] = v; }
  resetParam(k, v) { this[k] = v; }
  resetMonitorsOnReuse() {}
  finalizeConstruction() {}
  getUIContext() { return ui; }
  observeComponentCreation2(fn, type) {
    const previous = current; current = { type }; nodes.push(current); fn(1, true); current = previous;
  }
  ifElseBranchUpdateFunction(_id, fn) { fn(); }
}
function node(type) {
  return new Proxy({}, { get: (_t, method) => (...args) => {
    if (method !== 'pop') { current.kind = type; current[method] = args[0]; }
  } });
}
const ctx = vm.createContext({
  ViewV2, ViewPU: class {}, ImageFit: fit, Color: { Transparent: 0 },
  ImageInterpolation: { High: 1 }, Stack: node('Stack'), Image: node('Image'), If: node('If'),
  MINI_PLACEHOLDER_BLUR: 8, scrollPlaceholderState: { active: false },
  DrawModifier: class { invalidate() { invalidations++; } },
  drawing: { FilterMode: { FILTER_MODE_LINEAR: 1 },
    SamplingOptions: class { constructor() { samples++; } } },
  vp2pxUI: n => n * density,
  cachedPixelMap: r => cache.get(requestKey(r)),
  loadPixelMap: r => { loads++; return new Promise(resolve => pending.push({ r, resolve })); },
  cancelPixelMap() {}, loadPixelMapSync() { throw Error('unexpected sync decode'); },
  pinPixelMap() {}, pinPixelMapBounded() {},
  retainPixelMap: h => { assert.equal(h.released, false); h.refs++; },
  releasePixelMap: h => { if (--h.refs === 0) h.released = true; },
  thumbPathFor: id => channels.get(id) || '',
  subscribeThumbPath: (id, fn) => { subscribers.set(id, fn); return () => subscribers.delete(id); },
  warnStaleThumbAttach: (attached, expected) => assert.equal(attached, expected)
});
function load(path, names = []) {
  const source = fs.readFileSync(path, 'utf8').replace(/^import\s[\s\S]*?;\r?\n/gm, '')
    .replace(/@(?:Param|Event|Local|Computed)\s*/g, '').replace(/@Monitor\([^)]*\)\s*/g, '')
    .replace(/\bexport /g, '');
  vm.runInContext(ts.transpileModule(source + names.map(n => `\nglobalThis.${n} = ${n};`).join(''),
    { compilerOptions: { target: ts.ScriptTarget.ES2020 } }).outputText, ctx, { filename: path });
}
for (const file of ['imageSwap', 'cachedImageSpec', 'CachedImageSession', 'liveThumbPath', 'liveThumbAttach', 'liveThumbDisplayState']) {
  load(`entry/src/main/ets/util/${file}.ets`, file === 'cachedImageSpec' ? ['CachedImageSpecCache', 'sameCachedImageDecode'] : []);
}
load('entry/src/main/ets/pages/common/DrawnImageReceiver.ets', ['DrawnImageReceiver']);
load(compiled + 'pages/common/CachedImage.ts', ['CachedImage']);
load(compiled + 'pages/chat/LiveThumbImage.ts', ['LiveThumbImage', 'LiveThumbSpecCache']);
function handle(name, w = 400, h = 200) {
  const result = { name, refs: 1, released: false };
  result.pixelMap = { name, getImageInfoSync() {
    assert.equal(result.released, false, 'metadata read on a released bitmap');
    infoReads++; return { size: { width: w, height: h } };
  } };
  return result;
}
function spec(path, extra = {}) {
  return { path, boxWidth: 100, boxHeight: 100, fit: fit.Cover, radius: 12, drawOnCanvas: true, ...extra };
}
function seed(s, h) {
  cache.set(requestKey({ ...s, width: s.boxWidth * density, height: s.boxHeight * density, opaque: !!s.opaque }), h);
}
function paint(receiver) {
  const calls = [];
  receiver.drawFront({ canvas: { drawImageRectWithSrc(pixels, source, target) {
    calls.push({ name: pixels.name, source: { ...source }, target: { ...target } });
  } } });
  return calls;
}
function render(view) { nodes = []; view.initialRender(); return nodes; }
function recordWrites(view, key) {
  let value = view[key]; const writes = [];
  Object.defineProperty(view, key, { configurable: true, get() { return value; },
    set(next) { writes.push(next); value = next; } });
  return writes;
}
function checkPresentationReads(view) {
  const spec = view.spec, originalUse = view.useDrawnImage, originalBind = view.bindImageReceiver;
  let reads = 0;
  Object.defineProperty(view, 'spec', { configurable: true, get() { reads++; return spec; } });
  render(view); const after = reads;
  // Replay the former helper/root expressions against the same compiled tree.
  view.useDrawnImage = function () {
    return this.spec.drawOnCanvas === true && this.imageReceiver.canDraw(this.pixelMap, this.spec.fit ?? fit.Cover);
  };
  view.bindImageReceiver = function () {
    return this.spec.drawOnCanvas === true ? this.imageReceiver.bind(this.getUIContext(), this.spec.boxWidth,
      this.spec.boxHeight, this.spec.fit ?? fit.Cover, this.useDrawnImage()) : undefined;
  };
  reads = 0; render(view); const before = reads;
  assert.equal(before - after, 7, 'single spec reads remove seven reactive lookups per decoded image build');
  Object.defineProperty(view, 'spec', { configurable: true, writable: true, value: spec });
  view.useDrawnImage = originalUse; view.bindImageReceiver = originalBind;
  console.log(`${view.constructor.name} spec reads per decoded build: ${before} -> ${after}`);
}
function bind(view) {
  return view.imageReceiver.bind(ui, view.spec.boxWidth, view.spec.boxHeight,
    view.spec.fit ?? fit.Cover, view.useDrawnImage());
}
const a = handle('A'), receiver = new ctx.DrawnImageReceiver();
receiver.setPixels(a.pixelMap); receiver.bind(ui, 100, 100, fit.Cover, true);
assert.deepEqual(paint(receiver)[0], { name: 'A', source: { left: 100, top: 0, right: 300, bottom: 200 },
  target: { left: 0, top: 0, right: 200, bottom: 200 } });
receiver.bind(ui, 100, 100, fit.Contain, true);
assert.deepEqual(paint(receiver)[0].target, { left: 0, top: 50, right: 200, bottom: 150 });
const portrait = handle('portrait', 100, 400);
receiver.setPixels(portrait.pixelMap); receiver.bind(ui, 100, 100, fit.Cover, true);
assert.deepEqual(paint(receiver)[0].source, { left: 0, top: 150, right: 100, bottom: 250 });
const baseline = { infoReads, samples, invalidations };
for (let i = 0; i < 1000; i++) {
  receiver.setPixels(portrait.pixelMap); receiver.bind(ui, 100, 100, fit.Cover, true); paint(receiver);
}
assert.deepEqual({ infoReads, samples, invalidations }, baseline, 'unchanged frames do no preparation');
const shared = new ctx.DrawnImageReceiver(); shared.setPixels(portrait.pixelMap);
assert.equal(infoReads, baseline.infoReads, 'same cached avatar shares metadata across receivers');
density = 3; receiver.bind(ui, 100, 100, fit.Cover, true);
assert.equal(paint(receiver)[0].target.right, 300); density = 2;
assert.equal(receiver.canDraw(portrait.pixelMap, fit.Fill), false);
receiver.bind(ui, 0, 100, fit.Cover, true); assert.equal(paint(receiver).length, 0);
receiver.setPixels(undefined); assert.equal(paint(receiver).length, 0);

// Compiled CachedImage: remove the decoded Image leaf, retain its root clipping.
const sa = spec('/a'); seed(sa, a);
const view = new ctx.CachedImage(null, { spec: sa }); view.aboutToAppear();
let tree = render(view);
assert.equal(tree.filter(n => n.kind === 'Image').length, 0);
assert.equal(tree.find(n => n.kind === 'Stack').borderRadius, 12);
assert.equal(tree.find(n => n.kind === 'Stack').clip, true);
assert.equal(paint(view.imageReceiver)[0].name, 'A'); assert.equal(a.refs, 2);
checkPresentationReads(view);
view.aboutToRecycle(); assert.equal(a.refs, 2);
assert.equal(paint(view.imageReceiver)[0].name, 'A', 'recycle must not introduce a blank frame');
view.resetStateVarsOnReuse({ spec: sa }); view.aboutToReuse(); bind(view);
assert.equal(paint(view.imageReceiver)[0].name, 'A'); assert.equal(loads, 0);
// Switching render mode/fit is presentation-only and never starts a decode.
view.spec = { ...sa, drawOnCanvas: false }; view.onSourceChanged();
tree = render(view); assert.equal(tree.filter(n => n.kind === 'Image').length, 1);
assert.equal(tree.find(n => n.kind === 'Stack').drawModifier, undefined);
view.spec = { ...sa, fit: fit.Fill }; view.onSourceChanged();
assert.equal(render(view).filter(n => n.kind === 'Image').length, 1); assert.equal(loads, 0);
view.spec = sa; view.onSourceChanged(); render(view);
// Different source must blank before async decode, and a late B cannot overwrite C.
view.spec = spec('/b'); view.onSourceChanged(); bind(view);
assert.equal(paint(view.imageReceiver).length, 0);
const bPending = pending.at(-1);
view.spec = spec('/c'); view.onSourceChanged(); const cPending = pending.at(-1);
const b = handle('B'), c = handle('C'); bPending.resolve(b); await Promise.resolve();
assert.equal(paint(view.imageReceiver).length, 0);
cPending.resolve(c); await Promise.resolve(); bind(view);
assert.equal(paint(view.imageReceiver)[0].name, 'C'); assert.equal(b.refs, 1); assert.equal(c.refs, 2);
view.aboutToDisappear(); assert.equal(paint(view.imageReceiver).length, 0); assert.equal(c.refs, 1);
view.onSourceChanged(); assert.equal(paint(view.imageReceiver).length, 0, 'late monitor cannot resurrect disposed pixels');

// Live thumbnail: real file-channel changes, same-file quality upgrade and reuse.
const liveSpec = { fileId: 7, initialPath: '/a', boxWidth: 100, boxHeight: 100,
  fit: fit.Cover, radius: 6, radii: { topLeft: 12, topRight: 8, bottomLeft: 0, bottomRight: 0 },
  opaque: false, backdrop: '#333333', mini: '', drawOnCanvas: true };
const live = new ctx.LiveThumbImage(null, { spec: liveSpec, placeholder() {} });
const liveStates = recordWrites(live, 'displayState');
live.aboutToAppear(); tree = render(live);
assert.equal(liveStates.length, 1, 'path + cached pixels publish one final UI snapshot');
assert.equal(liveStates[0].hasPath, true); assert.equal(liveStates[0].pixels, a.pixelMap);
assert.equal(tree.filter(n => n.kind === 'Image').length, 0);
assert.equal(tree.find(n => n.kind === 'Stack').borderRadius, liveSpec.radii);
assert.equal(tree.find(n => n.kind === 'Stack').backgroundColor, '#333333');
checkPresentationReads(live);
subscribers.get(7)('/hq'); bind(live); const upgrade = pending.at(-1);
assert.equal(liveStates.length, 1, 'same-source pending path upgrade needs no display notification');
assert.equal(paint(live.imageReceiver)[0].name, 'A', 'same file quality upgrade holds old pixels');
const hq = handle('HQ'); upgrade.resolve(hq); await Promise.resolve(); bind(live);
assert.equal(paint(live.imageReceiver)[0].name, 'HQ');
assert.equal(liveStates.length, 2, 'ready HQ publishes once');
live.aboutToRecycle(); assert.equal(subscribers.size, 0); assert.equal(hq.refs, 2);
assert.equal(liveStates.length, 2, 'recycling preserves the current display');
channels.set(7, '/hq'); live.resetStateVarsOnReuse({ spec: liveSpec, placeholder() {} }); live.aboutToReuse(); bind(live);
assert.equal(liveStates.length, 4, 'one reset + one final reseed, rather than path/pixels separately');
assert.equal(paint(live.imageReceiver)[0].name, 'HQ'); assert.equal(subscribers.size, 1);
live.spec = { ...liveSpec, fileId: 8, initialPath: '' }; live.onSpecChanged(); bind(live);
assert.equal(paint(live.imageReceiver).length, 0); assert.equal(subscribers.has(7), false);
subscribers.get(8)('/late'); const late = pending.at(-1);
live.aboutToDisappear(); late.resolve(handle('late')); await Promise.resolve();
assert.equal(subscribers.size, 0); assert.equal(paint(live.imageReceiver).length, 0);
const afterDispose = liveStates.length;
live.publishDisplay(a.pixelMap);
assert.equal(liveStates.length, afterDispose, 'cannot publish a disposed image');

// Cached source swaps cannot briefly expose the previous source under a new path.
const pathOnlySpec = { ...liveSpec, fileId: 0, initialPath: '/a' };
const pathOnly = new ctx.LiveThumbImage(null, { spec: pathOnlySpec, placeholder() {} });
const pathStates = recordWrites(pathOnly, 'displayState');
pathOnly.aboutToAppear(); assert.equal(pathOnly.pixelMap, a.pixelMap);
const pd = handle('path-D'); seed({ ...sa, path: '/path-d', opaque: false }, pd);
pathOnly.spec = { ...pathOnlySpec, initialPath: '/path-d' }; pathOnly.onSpecChanged();
assert.equal(pathStates.length, 2); assert.equal(pathStates[1].pixels, pd.pixelMap);
pathOnly.spec = { ...pathOnlySpec, initialPath: '' }; pathOnly.onSpecChanged();
assert.equal(pathStates.length, 3); assert.equal(pathStates[2].hasPath, false);
assert.equal(pathStates[2].pixels, undefined); assert.equal(pathOnly.hasImagePath(), false);
pathOnly.spec = { ...pathOnlySpec, initialPath: '/missing' }; pathOnly.onSpecChanged();
assert.equal(pathStates.length, 4); assert.equal(pathStates[3].hasPath, true);
assert.equal(pathStates[3].pixels, undefined, 'unresolved new source shows placeholder, not old pixels');
const oldPending = pending.at(-1);
pathOnly.aboutToRecycle(); pathOnly.resetStateVarsOnReuse({ spec: pathOnlySpec, placeholder() {} });
pathOnly.aboutToReuse(); oldPending.resolve(handle('stale-path')); await Promise.resolve();
assert.equal(pathOnly.pixelMap, a.pixelMap);
pathOnly.aboutToDisappear();

// Metadata failures retain the native image renderer and mini placeholders.
const broken = handle('bad'); broken.pixelMap.getImageInfoSync = () => { throw Error('unsupported'); };
const brokenSpec = spec('/bad'); seed(brokenSpec, broken);
const fallback = new ctx.CachedImage(null, { spec: brokenSpec }); fallback.aboutToAppear();
assert.equal(render(fallback).filter(n => n.kind === 'Image').length, 1); fallback.aboutToDisappear();
const mini = new ctx.CachedImage(null, { spec: spec('/mini', { backdropImage: 'data:mini', deferBackdropOnScroll: true }) });
mini.aboutToAppear(); assert.equal(render(mini).filter(n => n.kind === 'Image').length, 1);
ctx.scrollPlaceholderState.active = true;
assert.equal(render(mini).filter(n => n.kind === 'Image').length, 0); mini.aboutToDisappear();

// Already visible album miniatures must not flash to their backdrop on scroll.
// First-time miniatures still defer while flinging, and cannot leak to new slots.
ctx.scrollPlaceholderState.active = false;
const albumMiniSpec = { ...liveSpec, fileId: 901, initialPath: '/mini-a', mini: 'data:mini-a', deferMiniOnScroll: true };
const albumMini = new ctx.LiveThumbImage(null, { spec: albumMiniSpec, placeholder() {} });
albumMini.aboutToAppear(); assert.equal(render(albumMini).filter(n => n.kind === 'Image').length, 1);
ctx.scrollPlaceholderState.active = true;
assert.equal(render(albumMini).filter(n => n.kind === 'Image').length, 1, 'retain an already shown miniature');
albumMini.aboutToRecycle();
albumMini.resetStateVarsOnReuse({ spec: { ...albumMiniSpec, fileId: 902, initialPath: '/mini-b' }, placeholder() {} });
albumMini.aboutToReuse();
assert.equal(render(albumMini).filter(n => n.kind === 'Image').length, 0, 'a new identity still defers first miniature during fling');
ctx.scrollPlaceholderState.active = false;
assert.equal(render(albumMini).filter(n => n.kind === 'Image').length, 1);
ctx.scrollPlaceholderState.active = true;
assert.equal(render(albumMini).filter(n => n.kind === 'Image').length, 1);
const finalMini = handle('mini-decoded'); pending.at(-1).resolve(finalMini); await Promise.resolve();
assert.equal(render(albumMini).filter(n => n.kind === 'Image').length, 0, 'real pixels replace the retained miniature');
albumMini.spec = { ...albumMiniSpec, fileId: 0, initialPath: '/mini-path-a' }; albumMini.onSpecChanged();
ctx.scrollPlaceholderState.active = false; assert.equal(albumMini.showMiniPlaceholder(), true);
ctx.scrollPlaceholderState.active = true;
albumMini.spec = { ...albumMiniSpec, fileId: 0, initialPath: '/mini-path-b' }; albumMini.onSpecChanged();
assert.equal(albumMini.showMiniPlaceholder(), false, 'path-only sources use path identity');
albumMini.aboutToDisappear();
console.log('PASS: album miniatures retained across scrolling, deferred on first fling entry, isolated across file/path reuse and replaced by decoded pixels.');

// Spec caches must publish a rendering policy change while decode identity stays equal.
const specs = new ctx.CachedImageSpecCache(); assert.equal(specs.prepare(sa), specs.prepare({ ...sa }));
const native = { ...sa, drawOnCanvas: false };
assert.notEqual(specs.prepare(native), sa); assert.equal(ctx.sameCachedImageDecode(sa, native), true);
const thumbs = new ctx.LiveThumbSpecCache(); assert.equal(thumbs.prepare(liveSpec), thumbs.prepare({ ...liveSpec }));
assert.notEqual(thumbs.prepare({ ...liveSpec, drawOnCanvas: false }), liveSpec);
console.log('PASS: crop/contain/density, no frame allocations/metadata reads, shared metadata, compiled native fallback/node removal, async identity/late decode, reuse, subscriptions, dispose, placeholders and spec caches.');

// Album badge uses this same path subscription. It follows path readiness,
// not decoder completion, including missing/failed sources and recycled slots.
let badges = 0;
const badgeSpec = { ...liveSpec, fileId: 701, initialPath: '', readyWithoutPath: false };
const badge = new ctx.LiveThumbImage(null, { spec: badgeSpec, placeholder() {}, readyContent() { badges++; } });
badge.aboutToAppear(); render(badge); assert.equal(badges, 0);
assert.equal(subscribers.has(701), true);
const latePath = subscribers.get(701);
channels.set(701, '/a'); subscribers.get(701)('/a'); render(badge); assert.equal(badges, 1);
badge.aboutToRecycle(); assert.equal(subscribers.has(701), false);
badge.resetStateVarsOnReuse({ spec: { ...badgeSpec, fileId: 702 }, placeholder() {}, readyContent() { badges++; } });
badge.aboutToReuse(); latePath('/stale'); render(badge); assert.equal(badges, 1);
badge.spec = { ...badgeSpec, fileId: 702, readyWithoutPath: true }; badge.onSpecChanged();
render(badge); assert.equal(badges, 2, 'failed thumbnail can show play without a path');
badge.spec = { ...badgeSpec, fileId: 0, readyWithoutPath: true }; badge.onSpecChanged();
render(badge); assert.equal(badges, 3, 'missing thumbnail does not hide a playable video');
badge.aboutToDisappear(); assert.equal(subscribers.has(702), false);
const badgeCache = new ctx.LiveThumbSpecCache();
const waitBadge = badgeCache.prepare(badgeSpec);
assert.notEqual(badgeCache.prepare({ ...badgeSpec, readyWithoutPath: true }), waitBadge);
console.log('PASS: shared album badge/path readiness, missing/failed sources, recycle and stale notification guard.');

// Optional previous compiled component for a direct lifecycle write-count A/B.
if (process.argv[2]) {
  const baselineSource = fs.readFileSync(process.argv[2], 'utf8');
  const component = baselineSource.slice(baselineSource.indexOf('export class LiveThumbImage extends'))
    .replace(/@(?:Param|Local)\s*/g, '').replace(/@Monitor\([^)]*\)\s*/g, '')
    .replace('export class LiveThumbImage', 'class LegacyLiveThumbImage');
  vm.runInContext(ts.transpileModule(component + '\nglobalThis.LegacyLiveThumbImage = LegacyLiveThumbImage;',
    { compilerOptions: { target: ts.ScriptTarget.ES2020 } }).outputText, ctx);
  const beforeView = new ctx.LegacyLiveThumbImage(null, { spec: pathOnlySpec, placeholder() {} });
  const afterView = new ctx.LiveThumbImage(null, { spec: pathOnlySpec, placeholder() {} });
  beforeView.aboutToAppear(); afterView.aboutToAppear();
  const beforePaths = recordWrites(beforeView, 'path'), beforePixels = recordWrites(beforeView, 'pixelMap');
  const afterStates = recordWrites(afterView, 'displayState');
  for (let i = 0; i < 1000; i++) {
    for (const v of [beforeView, afterView]) {
      v.aboutToRecycle(); v.resetStateVarsOnReuse({ spec: pathOnlySpec, placeholder() {} }); v.aboutToReuse();
    }
    assert.equal(afterView.pixelMap, beforeView.pixelMap);
    assert.equal(afterView.hasImagePath(), beforeView.drawPath() !== '');
  }
  assert.equal(beforePaths.length + beforePixels.length, 4000);
  assert.equal(afterStates.length, 2000);
  for (let i = 0; i < 300; i++) {
    const next = { ...pathOnlySpec, initialPath: ['', '/a', '/path-d'][i % 3],
      drawOnCanvas: i % 2 === 0, fit: i % 4 === 0 ? fit.Fill : fit.Cover };
    for (const v of [beforeView, afterView]) { v.spec = next; v.onSpecChanged(); }
    assert.equal(afterView.pixelMap, beforeView.pixelMap);
    assert.equal(afterView.hasImagePath(), beforeView.drawPath() !== '');
    assert.equal(afterView.useDrawnImage(), beforeView.useDrawnImage());
  }
  beforeView.aboutToDisappear(); afterView.aboutToDisappear();
  console.log('PASS: old/new actual compiled lifecycle differential; 1000 cached reuses local writes 4000 -> 2000, 300 path/render-mode transitions preserve final presentation.');
}
