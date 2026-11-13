// Actual reserve/scheduler/painter constructors, deterministic native/frame doubles.
// Verifies ownership and bounds, not device timing or native UI node precreation.
import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
const ts = (await import(process.env.TYPESCRIPT_MODULE || 'typescript')).default;
const root = 'entry/src/main/ets/';
function runtime() {
  let allocations = 0, nextTimer = 0;
  const frames = [], timers = new Map(), listeners = new Set(), logs = [];
  class Native { constructor() { allocations++; } setAntiAlias() {} setColor() {} setCapStyle() {} }
  const ctx = vm.createContext({ DrawnHomeMessages: class { begin() {} pending() { return false; } step() {} cancel() {} }, drawnHomeMessageSummary: () => '', FrameCallback: class {}, DrawModifier: class { invalidate() {} },
    drawing: { Brush: Native, Pen: Native, CapStyle: { ROUND_CAP: 1 } },
    logI: message => logs.push(message), logW: message => logs.push(message),
    setTimeout: fn => { const id = ++nextTimer; timers.set(id, fn); return id; },
    clearTimeout: id => timers.delete(id) });
  function load(path, names) {
    const src = fs.readFileSync(root + path, 'utf8').replace(/^import\s[\s\S]*?;\r?\n/gm, '').replace(/\bexport /g, '');
    vm.runInContext('(function(){' + ts.transpileModule(src + names.map(n => `\nglobalThis.${n}=${n};`).join(''),
      { compilerOptions: { target: ts.ScriptTarget.ES2020 } }).outputText + '})()', ctx);
  }
  load('pages/chat/DrawnChromePainter.ets', ['DrawnChromePainter']);
  load('pages/chat/DrawnBubblePainter.ets', ['DrawnBubblePainter', 'DrawnBubbleAvatar', 'DrawnBubbleForeground']);
  load('pages/chat/DrawnPainterReserve.ets', ['DrawnPainterReserve', 'drawnPainterReserve']);
  load('pages/main/DrawnHomeWarmup.ets', ['DrawnHomeWarmup']);
  const observer = { on: (_name, fn) => listeners.add(fn), off: (_name, fn) => listeners.delete(fn) };
  const ui = { getUIObserver: () => observer, postDelayedFrameCallback: (frame, delay) => frames.push({ frame, delay }) };
  return { ctx, frames, timers, listeners, logs, ui, allocations: () => allocations,
    tick(budget = 8e6) { const next = frames.shift(); assert.ok(next); next.frame.onIdle(budget); return next; } };
}
{
  const r = runtime(), pool = r.ctx.drawnPainterReserve;
  assert.equal(r.allocations(), 0, 'imports/pool creation must not allocate native resources');
  const w = new r.ctx.DrawnHomeWarmup(); w.update(r.ui, () => false);
  assert.equal(r.frames.length, 0, 'wait for home to become visible');
  w.update(r.ui, () => true); w.update(r.ui, () => true);
  assert.equal(r.frames.length, 1); assert.equal(r.frames[0].delay, 1000);
  r.tick(); assert.equal(r.allocations(), 0, 'message-job start occupies its own idle callback');
  for (let i = 0; i < 6; i++) { r.tick(); assert.equal(pool.prepared, i + 1); assert.ok(r.frames.length <= 1); }
  assert.equal(r.allocations(), 16, 'two rows: eight native brushes/pens each');
  assert.equal(r.listeners.size, 0); assert.equal(r.timers.size, 0); assert.equal(r.frames.length, 0);
  const originals = [...pool.backgrounds, ...pool.avatars, ...pool.foregrounds];
  const acquired = [];
  for (let i = 0; i < 2; i++) acquired.push(pool.takeBackground(), pool.takeAvatar(), pool.takeForeground());
  assert.equal(new Set(acquired).size, 6); assert.ok(acquired.every(x => originals.includes(x)));
  assert.equal(r.allocations(), 16, 'warm acquisition really skips native constructors');
  assert.equal(pool.hits, 6);
  acquired[0].plan = { identity: 'first-row' };
  const third = pool.takeBackground(); assert.ok(!acquired.includes(third)); assert.equal(third.plan, null);
  for (let i = 0; i < 10000; i++) pool.step();
  assert.equal(pool.prepared, 6); assert.equal(pool.backgrounds.length, 0);
  w.update(r.ui, () => true); assert.equal(r.frames.length, 0, 'never refill after consumption');
}
for (const reason of ['input', 'scroll', 'navigate', 'timeout', 'consumer']) {
  const r = runtime(), pool = r.ctx.drawnPainterReserve, w = new r.ctx.DrawnHomeWarmup();
  let home = true; w.start(r.ui, () => home); r.tick(); r.tick();
  const prepared = pool.prepared;
  if (reason === 'input') w.cancel();
  if (reason === 'scroll') for (const fn of r.listeners) fn({});
  if (reason === 'navigate') { home = false; w.update(r.ui, () => home); }
  if (reason === 'timeout') for (const fn of [...r.timers.values()]) fn();
  if (reason === 'consumer') pool.takeBackground();
  // Already enqueued native idle callbacks become harmless, even if delivered twice.
  for (const { frame } of [...r.frames]) { frame.onIdle(8e6); frame.onIdle(8e6); }
  assert.equal(pool.prepared, prepared, reason);
  assert.equal(r.listeners.size, 0, reason); assert.equal(r.timers.size, 0, reason);
  w.update(r.ui, () => true); assert.equal(pool.pending(), false, reason);
}
{
  const r = runtime(), w = new r.ctx.DrawnHomeWarmup(); w.start(r.ui, () => true);
  for (let i = 0; i < 40; i++) r.tick(2e6);
  assert.equal(r.allocations(), 0); assert.equal(r.frames.length, 0); assert.equal(r.listeners.size, 0);
}
{
  const r = runtime(), w = new r.ctx.DrawnHomeWarmup(); w.cancel(); w.start(r.ui, () => true);
  assert.equal(r.frames.length, 0, 'input before first visible callback cancels future start');
}
{
  const r = runtime(), w = new r.ctx.DrawnHomeWarmup();
  r.ui.postDelayedFrameCallback = () => { throw new Error('window gone'); };
  w.start(r.ui, () => true);
  assert.equal(r.listeners.size, 0); assert.equal(r.timers.size, 0);
  assert.ok(r.logs.some(x => x.includes('window gone')));
}
// Production wiring: all three existing renderer fields consume the reserve;
// no hidden messages, no changed component keys or recycled modifier returns.
const row = fs.readFileSync(root + 'pages/chat/DrawnMessageRow.ets', 'utf8');
for (const method of ['takeBackground', 'takeAvatar', 'takeForeground']) assert.ok(row.includes(`drawnPainterReserve.${method}()`));
const main = fs.readFileSync(root + 'pages/main/MainScreen.ets', 'utf8');
assert.ok(main.includes("stackOf('chat')?.size() === 0"));
assert.ok(main.includes('.onTouch((): void => { this.drawnWarmup.cancel(); })'));
console.log('PASS: home idle warmup bounds, native constructor savings, unique ownership, input/scroll/navigation/expiry, and cold fallback');
