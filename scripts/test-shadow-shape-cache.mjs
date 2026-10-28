// Exercise production path preparation with a frozen PathShape stand-in.
// Optionally compare every command with the pre-change bubbleTail source.
// Native drawing and scheduling still require device verification.
import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
const imported = await import(process.env.TYPESCRIPT_MODULE || 'typescript');
const ts = imported.default || imported;
const read = relative => fs.readFileSync(new URL(relative, import.meta.url), 'utf8');
const geometry = read('../entry/src/main/ets/util/bubbleGlassPath.ets');
const tail = read('../entry/src/main/ets/util/bubbleTail.ets');
function compile(text) {
  return ts.transpileModule(text.replace(/^import[\s\S]*?;\n/gm, '').replace(/\bexport /g, ''),
    { compilerOptions: { target: ts.ScriptTarget.ES2020 } }).outputText;
}
function setup(tailSource = tail, before = false) {
  let density = 1, allocations = 0, outlineLookups = 0;
  const ctx = vm.createContext({
    vp2px: value => value * density,
    Map: class extends Map { get(key) { outlineLookups++; return super.get(key); } },
    PathShape: class {
      constructor(options) { this.commands = options.commands; allocations++; Object.freeze(this); }
    }
  });
  vm.runInContext(compile(geometry + '\n' + tailSource) + `
    globalThis.reset = clearOutlineCache;
    globalThis.create = ${before ? '() => ({prepare: solidBubbleShadowShape})' : '() => new SolidBubbleShadowCache()'};
    globalThis.expected = (w,h,outgoing,hasTail,r) => glassBubbleCommands(w,h,outgoing,hasTail,
      typeof r.topLeft === 'number' ? r.topLeft : 0,
      typeof r.topRight === 'number' ? r.topRight : 0,
      typeof r.bottomRight === 'number' ? r.bottomRight : 0,
      typeof r.bottomLeft === 'number' ? r.bottomLeft : 0,
      TAIL_W,TAIL_H,vp2px(1),0,TAIL_W-(hasTail ? 2 : 1));`, ctx);
  return { create: ctx.create, expected: ctx.expected, reset: ctx.reset,
    density(value) { density = value; ctx.reset(); }, allocations: () => allocations,
    lookups: () => outlineLookups };
}
const radii = () => ({ topLeft: 12, topRight: 13, bottomRight: 14, bottomLeft: 15 });
let scenarios = 0;
function check(name, run) { run(); scenarios++; console.log(`PASS ${name}`); }
check('equal geometry reuses one shape; equivalent radii objects do not defeat it', () => {
  const s = setup(), cache = s.create(), first = cache.prepare(120, 80, false, true, radii());
  for (let i = 0; i < 1000; i++) assert.equal(cache.prepare(120, 80, false, true, radii()), first);
  assert.equal(s.allocations(), 1);
  assert.equal(s.lookups(), 1);
});
check('each effective geometry input invalidates and never mutates an earlier shape', () => {
  const s = setup(), cache = s.create();
  const base = [120, 80, false, true, radii()];
  for (const index of [0, 1, 2, 3, 'topLeft', 'topRight', 'bottomRight', 'bottomLeft']) {
    // A no-tail shape exposes every corner in both directions.
    base[3] = false;
    const previous = cache.prepare(...base), oldCommands = previous.commands;
    const next = [...base.slice(0, 4), radii()];
    if (typeof index === 'string') next[4][index] += 1;
    else next[index] = typeof next[index] === 'boolean' ? !next[index] : next[index] + 1;
    const changed = cache.prepare(...next);
    assert.notEqual(changed, previous, String(index));
    assert.equal(changed.commands, s.expected(...next));
    assert.equal(previous.commands, oldCommands);
  }
});
check('in-place radius changes are observed and identical final px commands stay reusable', () => {
  const s = setup(), cache = s.create(), r = radii();
  const first = cache.prepare(120, 80, false, false, r);
  r.topLeft = 17;
  assert.notEqual(cache.prepare(120, 80, false, false, r), first);
  r.topLeft = 500; const capped = cache.prepare(120, 80, false, false, r);
  r.topLeft = 600; assert.equal(cache.prepare(120, 80, false, false, r), capped);
});
check('density invalidation rebuilds px geometry, same-density clear remains visually identical', () => {
  const s = setup(), cache = s.create();
  const first = cache.prepare(120, 80, false, true, radii());
  s.density(2); const second = cache.prepare(120, 80, false, true, radii());
  assert.notEqual(second, first); assert.notEqual(second.commands, first.commands);
  assert.equal(second.commands, s.expected(120, 80, false, true, radii()));
  s.reset(); assert.equal(cache.prepare(120, 80, false, true, radii()), second);
  assert.equal(s.lookups(), 3);
});
check('component caches never share native objects and preserve detached-node snapshots', () => {
  const s = setup(), a = s.create(), b = s.create();
  const old = a.prepare(120, 80, false, true, radii());
  const other = b.prepare(120, 80, false, true, radii());
  assert.notEqual(old, other); assert.equal(old.commands, other.commands);
  a.prepare(200, 100, true, false, radii());
  assert.equal(b.prepare(120, 80, false, true, radii()), other);
  assert.equal(old.commands, other.commands);
});
check('bounded outline eviction does not invalidate an unchanged component shape', () => {
  const s = setup(), a = s.create(), b = s.create();
  const first = a.prepare(120, 80, false, true, radii());
  for (let i = 0; i < 300; i++) b.prepare(200 + i, 80, false, true, radii());
  assert.equal(a.prepare(120, 80, false, true, radii()), first);
});
let combinations = 0;
check('path parity across sizes, direction, tails, radii and densities', () => {
  const s = setup(), cache = s.create();
  const old = process.env.BEFORE_BUBBLE_TAIL ? setup(fs.readFileSync(process.env.BEFORE_BUBBLE_TAIL, 'utf8'), true) : null;
  const oldCache = old?.create();
  for (const density of [1, 1.5, 2, 3.25]) {
    s.density(density); old?.density(density);
    for (const w of [6, 10, 38, 120, 320.25]) for (const h of [1, 12, 38, 80, 500.5]) {
      for (const outgoing of [false, true]) for (const tail of [false, true]) {
        for (const r of [radii(), {}, {topLeft:'12vp'}, {topLeft:0,topRight:0,bottomLeft:0,bottomRight:0},
          {topLeft:99,topRight:3,bottomLeft:15,bottomRight:21}]) {
          const args = [w,h,outgoing,tail,r], shape = cache.prepare(...args);
          assert.equal(shape.commands, s.expected(...args));
          if (oldCache) assert.equal(shape.commands, oldCache.prepare(...args).commands);
          combinations++;
        }
      }
    }
  }
  console.log(`Compared ${combinations} geometries${old ? ' against pre-change implementation' : ''}`);
});
console.log(`Shadow shape cache: ${scenarios} scenarios passed; native drawing requires device verification`);
