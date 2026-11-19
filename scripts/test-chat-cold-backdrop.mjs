import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
const ts = (await import(process.env.TYPESCRIPT_MODULE || 'typescript')).default;
const root = 'entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/';
function parsed(file) { return ts.createSourceFile(file, fs.readFileSync(root + file + '.ts', 'utf8'), ts.ScriptTarget.Latest, true); }
const backdrop = parsed('pages/chat/ChatBackdrop');
const cls = backdrop.statements.find(n => ts.isClassDeclaration(n) && n.name.text === 'ChatBackdrop');
const method = name => cls.members.find(n => n.name?.getText(backdrop) === name).getText(backdrop);
const raster = parsed('util/chatBackgroundRaster');
const fn = name => raster.statements.find(n => ts.isFunctionDeclaration(n) && n.name.text === name).getText(raster).replace(/^export /, '');
const calls = [], children = [], timers = new Map(), captures = [], disk = new Map(), pixels = new Map();
let timerId = 0, released = 0, packed = 0;
const ui = name => new Proxy({}, { get: (_, key) => (...args) => calls.push([name, key, ...args]) });
const enums = new Proxy({}, { get: (_, key) => key });
const ctx = vm.createContext({
  Stack: ui('Stack'), Column: ui('Column'), If: ui('If'), __Common__: ui('Common'),
  Alignment: enums, SafeAreaType: enums, HitTestMode: enums, Color: enums, ImageFit: enums,
  CachedImage: class { constructor(_parent, spec) { children.push(spec); } }, ViewV2: { create() {} },
  gradientStops: colors => colors.map((c, i) => [c, i]), logI() {}, logE() {},
  RASTER_DEBOUNCE_MS: 280, SNAPSHOT_DELAY_MS: 100, CHATBG_TMP_SUFFIX: '.tmp',
  setTimeout: cb => { const id = ++timerId; timers.set(id, cb); return id; }, clearTimeout: id => timers.delete(id),
  rasterCache: new Map(), inFlight: new Map(), rasterWriting: new Set(),
  rasterSignature: p => `${p.path}:${p.width}:${p.height}`,
  cachedRaster: sig => disk.get(sig) || '', cachedPixelMap: req => pixels.get(req.path),
  retainRaster() {}, releaseRaster() {},
  ComponentContent: class {}, wrapBuilder: x => x, backgroundLayer() {},
  rasterPathFor: sig => sig + '.jpg', publishRaster: () => true,
  writeRasterTmp: async () => { packed++; },
  image: { createImagePacker: () => ({ release() { released++; } }) },
  fileIo: { unlinkSync() {} }
});
const run = s => vm.runInContext(ts.transpileModule(s, { compilerOptions: { target: ts.ScriptTarget.ES2020 } }).outputText, ctx);
run(`${fn('rasterizeBackground')}\n${fn('createBackgroundRaster')}\nglobalThis.rasterizeBackground = rasterizeBackground;
class Backdrop { ${['wallpaperLayer', 'syncRaster', 'setRasterPath', 'liveDarkMaskOpacity'].map(method).join('\n')} }
globalThis.Backdrop = Backdrop;`);
const snapshotUI = { vp2px: n => n * 2, getComponentSnapshot: () => ({ createFromComponent: () => new Promise((resolve, reject) => captures.push({ resolve, reject })) }) };
const params = path => ({ path, colors: ['#102030'], width: 360, height: 800 });
const flush = () => new Promise(resolve => setImmediate(resolve));
function fireTimers() { const pending = [...timers.values()]; timers.clear(); pending.forEach(cb => cb()); }
function row(path = 'a') {
  const b = new ctx.Backdrop();
  Object.assign(b, { rasterPath: '', rasterShown: false, rasterTimer: -1, pinAlive: true,
    chatBg: { path, colors: ['#102030', '#506070'], angle: 45, dimming: 0.2, isPattern: true },
    observeComponentCreation2: cb => cb(1, true), ifElseBranchUpdateFunction: (_, cb) => cb(),
    cacheDir: () => '/cache', rasterParams: () => params(b.chatBg.path), getUIContext: () => snapshotUI,
    layerW: () => 360, layerH: () => 800, dropPin() {}, pinForSlot() {},
    suppressedByUnifiedBg: () => false, splitNoWallpaper: () => false,
    darkMaskOpacity: () => 0.3, canBakeDarkMask: () => true
  });
  return b;
}
// Real raster function: 1000 subscribers, only one snapshot + encode; failures free
// the shared slot so a later request can retry (no persistent negative entry).
const requests = Array.from({ length: 1000 }, () => ctx.rasterizeBackground(snapshotUI, params('shared'), '/cache'));
assert.equal(captures.length, 1);
captures.shift().resolve({ release() { released++; } });
assert.ok((await Promise.all(requests)).every(p => p === 'shared:360:800.jpg'));
assert.equal(packed, 1); assert.equal(released, 2); assert.equal(ctx.inFlight.size, 0);
await ctx.rasterizeBackground(snapshotUI, params('shared'), '/cache'); assert.equal(captures.length, 0);
const failures = [1, 2].map(() => ctx.rasterizeBackground(snapshotUI, params('fail'), '/cache'));
assert.equal(captures.length, 1); captures.shift().reject(new Error('decode failed'));
assert.deepEqual(await Promise.all(failures), ['', '']); assert.equal(ctx.inFlight.size, 0);
const retry = ctx.rasterizeBackground(snapshotUI, params('fail'), '/cache');
assert.equal(captures.length, 1); captures.shift().resolve({ release() {} }); await retry;
assert.equal(await ctx.rasterizeBackground(snapshotUI, { ...params('invalid'), width: 0 }, '/cache'), '');
// Compiler-output rendering: cold pattern/photo, disk file awaiting decode,
// failed decode all retain fill, but never create a live image/filter/tile tree.
const b = row();
for (const isPattern of [true, false]) for (const colors of [[], ['#102030', '#506070']]) for (const path of ['', 'disk.jpg']) {
  Object.assign(b.chatBg, { isPattern, colors }); b.rasterPath = path; b.rasterShown = false;
  calls.length = 0; children.length = 0; b.wallpaperLayer();
  assert.ok(calls.some(c => c[0] === 'Column' && ['backgroundColor', 'linearGradient'].includes(c[1])));
  assert.ok(!calls.some(c => ['blur', 'backgroundBlurStyle', 'backdropBlur', 'shadow'].includes(c[1])));
  assert.equal(children.length, path ? 1 : 0);
  assert.equal(b.liveDarkMaskOpacity(), 0.3);
  if (path) {
    children[0].onReady(); assert.equal(b.rasterShown, true);
    calls.length = 0; b.wallpaperLayer();
    assert.ok(!calls.some(c => c[0] === 'Column' && c[1] === 'create'));
    assert.equal(b.liveDarkMaskOpacity(), 0, 'baked dark mask is not applied twice');
  }
}
b.setRasterPath('next.jpg'); assert.equal(b.rasterShown, false, 'source switch restores placeholder before decode');
pixels.set('hot.jpg', {}); b.setRasterPath('hot.jpg'); assert.equal(b.rasterShown, true);
// Concurrent visible slots both receive the shared result; stale or disposed
// pages never retain a completed image for a different wallpaper.
const a = row('dual'), c = row('dual'); a.syncRaster(); c.syncRaster(); fireTimers();
assert.equal(captures.length, 1); captures.shift().resolve({ release() {} }); await flush();
assert.equal(a.rasterPath, 'dual:360:800.jpg'); assert.equal(c.rasterPath, a.rasterPath);
const stale = row('old'), disposed = row('gone'); stale.syncRaster(); disposed.syncRaster(); fireTimers();
stale.chatBg.path = 'new'; disposed.pinAlive = false;
for (const capture of captures.splice(0)) capture.resolve({ release() {} }); await flush();
assert.equal(stale.rasterPath, ''); assert.equal(disposed.rasterPath, '');
const system = row(''); system.chatBg.colors = []; system.syncRaster();
assert.equal(timers.size, 0, 'theme-only background never snapshots a theme-dependent bitmap');
console.log('PASS: static cold fallback and ready-only removal, source replacement, dark mask, shared 1000-call raster job, failed-job retry, stale/disposed guards and theme-only path.');
