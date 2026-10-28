// 执行产品 Overlay 的真实方法（只剥离 ArkUI build DSL），验证异步交接/资源释放。
import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
const imported = await import(process.env.TYPESCRIPT_MODULE || 'typescript');
const ts = imported.default || imported;
let source = fs.readFileSync(new URL('../entry/src/main/ets/pages/common/ShatterDeleteOverlay.ets', import.meta.url), 'utf8');
source = source.replace(/^import .*;\n/gm, '').replace('@Component\nexport struct', 'class').replace(/@State /g, '');
source = source.slice(0, source.indexOf('  build() {')) + '}\nglobalThis.Overlay = ShatterDeleteOverlay;';
const js = ts.transpileModule(source, { compilerOptions: { target: ts.ScriptTarget.ES2020 } }).outputText;
let fallbackSource = fs.readFileSync(new URL('../entry/src/main/ets/pages/common/ShatterCanvasFallback.ets', import.meta.url), 'utf8');
fallbackSource = fallbackSource.replace(/^import .*;\n/gm, '').replace('@Component\nexport struct', 'class')
  .replace(/@State /g, '').replaceAll('ShatterCaptureFrame', 'ShatterFallbackCaptureFrame');
fallbackSource = fallbackSource.slice(0, fallbackSource.indexOf('  build() {')) + '}\nglobalThis.Fallback = ShatterCanvasFallback;';
const fallbackJs = ts.transpileModule(fallbackSource, { compilerOptions: { target: ts.ScriptTarget.ES2020 } }).outputText;
const flush = async () => { for (let i = 0; i < 6; i++) await Promise.resolve(); };
function deferred() { let resolve, reject; const promise = new Promise((a, b) => { resolve = a; reject = b; }); return { promise, resolve, reject }; }
function setup({ duration = 1100 } = {}) {
  const capture = deferred(), prepare = deferred();
  const timers = new Map(), frames = [], closed = [], begun = [];
  let event, released = 0, captured = 0, finished = 0, attached = true, nextTimer = 1, draws = 0, canvasDuration = 0;
  const pixels = { release: () => { released++; }, getImageInfo: async () => ({ size: { width: 100, height: 40 } }) };
  const animator = { play() {}, cancel() {}, onFrame() {}, onFinish() {} };
  const ui = { getComponentSnapshot: () => ({ get: () => capture.promise }), vp2px: n => n * 3, px2vp: n => n / 3,
    postFrameCallback: frame => frames.push(frame), createAnimator: options => { canvasDuration = options.duration; return animator; } };
  const context = vm.createContext({
    FrameCallback: class {}, XComponentController: class { getXComponentSurfaceId() { return '123'; } },
    CanvasRenderingContext2D: class {
      clearRect() {} drawImage() { draws++; } save() {} restore() {} beginPath() {} rect() {} clip() {}
    }, RenderingContextSettings: class {}, LengthMetricsUnit: { PX: 0 },
    KEY_POWER_SMOOTH_TRANSITIONS: 'power', powerAnimationDuration: (_key, value) => duration === 0 ? 0 : value,
    logI: () => {}, logW: () => {},
    setTimeout: f => { const id = nextTimer++; timers.set(id, f); return id; }, clearTimeout: id => timers.delete(id),
    shatterPrepare: () => prepare.promise,
    shatterAttach: (_id, _surface, cb) => { event = cb; return attached; },
    shatterBegin: (id, ms) => begun.push([id, ms]), shatterClose: id => closed.push(id)
  });
  vm.runInContext(js, context);
  vm.runInContext(fallbackJs, context);
  const overlay = new context.Overlay();
  overlay.getUIContext = () => ui;
  overlay.onCaptured = () => captured++;
  overlay.onFinish = () => finished++;
  const prepared = { handle: 7, width: 1200, height: 216, surfaceWidth: 1490, surfaceHeight: 930, top: 713 };
  return { overlay, timers, frames, closed, begun, pixels, capture, prepare, prepared,
    get released() { return released; }, get captured() { return captured; }, get finished() { return finished; },
    get draws() { return draws; }, get canvasDuration() { return canvasDuration; }, animator,
    mountFallback() {
      const child = new context.Fallback();
      child.pixels = overlay.snapshot; child.getUIContext = () => ui;
      child.canDraw = () => overlay.active && !overlay.finished && overlay.fallback;
      child.onCaptured = () => overlay.markCaptured(); child.onFinish = () => overlay.finish();
      child.aboutToAppear(); return child;
    },
    emit: code => event(code), failAttach: () => { attached = false; },
    async load() {
      overlay.aboutToAppear(); capture.resolve(pixels); await flush();
      prepare.resolve(prepared); await flush(); overlay.attach();
    } };
}
{
  const s = setup(); await s.load();
  assert.equal(s.released, 0); assert.equal(s.captured, 0);
  s.emit(0); s.emit(0); assert.equal(s.captured, 0);
  for (const f of s.frames) f.onIdle(0);
  assert.equal(s.captured, 1); assert.deepEqual(s.begun, [[7, 1100]]);
  s.emit(1); s.emit(1); s.overlay.aboutToDisappear();
  assert.equal(s.finished, 1); assert.deepEqual(s.closed, [7]); assert.equal(s.timers.size, 0); assert.equal(s.released, 1);
}
{
  const s = setup(); s.overlay.aboutToAppear(); s.overlay.aboutToDisappear();
  s.capture.resolve(s.pixels); await flush();
  assert.equal(s.released, 1); assert.equal(s.finished, 1); assert.deepEqual(s.closed, []);
}
{
  const s = setup(); s.overlay.aboutToAppear(); s.capture.resolve(s.pixels); await flush();
  s.overlay.aboutToDisappear(); assert.equal(s.released, 0);
  s.prepare.resolve(s.prepared); await flush();
  assert.equal(s.released, 1); assert.equal(s.overlay.ready, false); assert.deepEqual(s.closed, [7]);
}
{
  const s = setup(); await s.load(); s.emit(0); s.timers.get(1)();
  s.frames[0].onIdle(0); s.emit(1);
  assert.equal(s.captured, 0); assert.equal(s.finished, 1); assert.deepEqual(s.begun, []);
}
{
  const s = setup(); s.overlay.aboutToAppear(); s.capture.reject(Error('capture failed')); await flush();
  assert.equal(s.finished, 1); assert.equal(s.released, 0);
}
{
  const s = setup(); s.overlay.aboutToAppear(); s.capture.resolve(s.pixels); await flush();
  s.prepare.resolve(null); await flush();
  assert.equal(s.finished, 0); assert.equal(s.released, 0); assert.equal(s.overlay.fallback, true);
  s.overlay.markCaptured(); s.overlay.finish();
  assert.equal(s.captured, 1); assert.equal(s.finished, 1); assert.equal(s.released, 1);
}
{
  const s = setup(); s.overlay.aboutToAppear(); s.capture.resolve(s.pixels); await flush();
  s.prepare.reject(Error('native prepare failed')); await flush();
  assert.equal(s.finished, 0); assert.equal(s.released, 0); assert.equal(s.overlay.fallback, true);
  s.overlay.finish(); assert.equal(s.released, 1);
}
{
  const s = setup(); s.failAttach(); await s.load();
  assert.equal(s.finished, 0); assert.deepEqual(s.closed, [7]); assert.equal(s.overlay.fallback, true);
  s.overlay.finish(); assert.equal(s.released, 1);
}
{
  const s = setup(); await s.load(); s.emit(-1); s.emit(0);
  assert.equal(s.finished, 0); assert.equal(s.frames.length, 0); assert.deepEqual(s.closed, [7]);
  assert.equal(s.overlay.fallback, true); s.overlay.finish(); assert.equal(s.released, 1);
}
{
  const s = setup({ duration: 0 }); s.overlay.aboutToAppear();
  assert.equal(s.finished, 1); assert.equal(s.timers.size, 0); assert.equal(s.overlay.ready, false);
}
{
  const s = setup(); await s.load(); s.emit(0); s.timers.get(2)();
  s.frames[0].onIdle(0); s.emit(1);
  assert.equal(s.overlay.fallback, true); assert.equal(s.finished, 0); assert.deepEqual(s.begun, []);
  s.overlay.markCaptured(); s.overlay.finish(); assert.equal(s.captured, 1); assert.equal(s.released, 1);
}
{
  const s = setup(); await s.load(); s.emit(0); s.frames[0].onIdle(0); s.emit(-1);
  s.overlay.markCaptured(); s.overlay.finish(); s.overlay.aboutToDisappear();
  assert.equal(s.captured, 1); assert.equal(s.finished, 1); assert.equal(s.released, 1);
}
{
  const s = setup(); s.overlay.aboutToAppear(); s.capture.resolve(s.pixels); await flush();
  s.timers.get(1)(); assert.equal(s.released, 0);
  s.prepare.resolve(null); await flush();
  assert.equal(s.overlay.fallback, false); assert.equal(s.finished, 1); assert.equal(s.released, 1);
}
{
  const s = setup(); s.overlay.aboutToAppear(); s.capture.resolve(s.pixels); await flush();
  s.prepare.resolve(null); await flush();
  const child = s.mountFallback(); await flush(); child.start();
  assert.equal(s.draws, 1); assert.equal(s.captured, 0);
  s.frames[0].onIdle(0); assert.equal(s.canvasDuration, 1100); s.animator.onFrame(.6);
  assert(s.draws > 1); assert.equal(s.captured, 1); assert.equal(s.finished, 0);
  s.animator.onFinish(); child.aboutToDisappear(); s.overlay.aboutToDisappear();
  const draws = s.draws; s.animator.onFrame(.8);
  assert.equal(s.draws, draws); assert.equal(s.finished, 1); assert.equal(s.released, 1);
}
console.log('Shatter lifecycle: 14 scenarios passed');
