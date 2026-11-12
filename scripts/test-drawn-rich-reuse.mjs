// Run after a debug HAP build. Replay actual compiled ArkUI callbacks and the
// production index/painter. Platform mocks do not prove native gesture arbitration.
import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
const imported = await import(process.env.TYPESCRIPT_MODULE || 'typescript');
const ts = imported.default || imported;
const file = process.argv[2] ||
  'entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/pages/chat/DrawnRichTextView.ts';
const callbacks = new Map(), nodes = new Map();
let current = -1, nextId = 1, paints = [], clicks = [], invalidations = 0, brushCount = 0;
let listener, epoch = 0;
function node() {
  return new Proxy({}, { get: (_target, prop) => (...args) => {
    if (prop !== 'create' && prop !== 'pop') nodes.get(current)[prop] = args[0];
  } });
}
class ViewV2 {
  initParam(key, value) { this[key] = value; }
  resetParam(key, value) { this[key] = value; }
  updateParam(key, value) { this[key] = value; }
  finalizeConstruction() {}
  getUIContext() { return { vp2px: n => n * 2 }; }
  observeComponentCreation2(fn, type) {
    const id = nextId++, previous = current;
    callbacks.set(id, { fn, type }); nodes.set(id, {}); current = id; fn(id, true); current = previous;
  }
  forEachUpdateFunction(id, items, create) {
    nodes.get(id).items = items;
    if (this.creating) items.forEach(create);
  }
  ifElseBranchUpdateFunction(_id, fn) { if (this.creating) fn(); }
}
const Row = node(), Stack = node(), ForEach = node(), If = node();
const ctx = vm.createContext({ chatEnv: {linkNavBusy:''}, ViewV2, ViewPU: class {}, Row, Stack, ForEach, If,
  DrawModifier: class { invalidate() { invalidations++; } },
  drawing: { Brush: class { constructor() { brushCount++; } setColor() {} } },
  drawnColor: c => c, $r: name => name,
  accessibility: { isOpenAccessibilitySync: () => false, on(_name, fn) { listener = fn; } },
  logE: msg => { throw Error(msg); }, AppStorage: { get: () => epoch, setOrCreate(_k, v) { epoch = v; } },
  Alignment: { TopStart: 0 }, HitTestMode: { None: 0 }, Color: { Transparent: 0 },
  TouchType: { Down: 0, Move: 1, Up: 2, Cancel: 3 }, SourceType: { TouchScreen: 0, Mouse: 1 },
  AccessibilityRoleType: { HYPERLINK: 0 }, ViewStackProcessor: { visualState() {} } });
function load(path, exports = []) {
  const source = fs.readFileSync(path, 'utf8').replace(/^import .*;\r?\n/gm, '')
    .replace(/@(?:ObservedV2|Trace|Param|Event|Local)\s*/g, '').replace(/\bexport /g, '');
  vm.runInContext(ts.transpileModule(source + exports.map(n => `\nglobalThis.${n} = ${n};`).join(''),
    { compilerOptions: { target: ts.ScriptTarget.ES2020 } }).outputText, ctx);
}
load('entry/src/main/ets/util/a11yState.ets', ['a11yRuntimeState', 'initA11yState', 'screenReaderOn']);
ctx.initA11yState(); assert.equal(ctx.screenReaderOn(), false);
listener(true); assert.equal(ctx.a11yRuntimeState.active, true); assert.equal(epoch, 1);
listener(true); assert.equal(epoch, 1); listener(false); assert.equal(epoch, 2);
load('entry/src/main/ets/util/drawnRichHitIndex.ets', ['DrawnRichHitIndex']);
load('entry/src/main/ets/pages/chat/DrawnRichTextPainter.ets', ['DrawnRichTextPainter']);
load(file, ['DrawnRichTextView']);
function plan(name, width, count = 1) {
  const hits = Array.from({ length: count }, (_, i) => ({ key: name + i,
    link: { url: name + i, accessibilityLabel: name + i, hidesUrl: i % 2 === 0 },
    widthVp: 12, heightVp: 20, x: (i % 3) * 25, y: Math.floor(i / 3) * 24, accessible: true }));
  return { emojis: [], widthVp: width, heightVp: 24 * Math.ceil(count / 3), source: { content: name, links: hits.map(h=>h.link), targets: new Set(hits.map(h=>h.link.url)) },
    paragraph: { paint() { paints.push(name); } }, hits, hitIndex: new ctx.DrawnRichHitIndex(hits) };
}
function render(view) {
  callbacks.clear(); nodes.clear(); view.creating = true; view.initialRender(); view.creating = false;
}
function update(id) { current = id; callbacks.get(id).fn(id, false); }
function event(type, x = 5, y = 5, fingers = 1) {
  return { type, changedTouches: [{ x, y }], touches: Array.from({ length: fingers }, () => ({ x, y })) };
}
const mouse = { x: 5, y: 5, source: 1 }, touchClick = { ...mouse, source: 0 };
const canvas = { attachBrush() {}, detachBrush() {}, drawRect(rect) { this.lastRect = { ...rect }; } };
const first = plan('first', 100, 57), second = plan('second', 200, 47);
const view = new ctx.DrawnRichTextView(null, { plan: first, onLinkTap: link => clicks.push(link.url) });
render(view);
assert.equal([...callbacks.values()].filter(c => c.type === Row).length, 2, '57 hits use only 2 Rows total');
assert.equal([...callbacks.values()].filter(c => c.type === ForEach).length, 0);
const root = [...callbacks.keys()].find(id => callbacks.get(id).type === Stack);
const paintRow = [...nodes.keys()].find(id => nodes.get(id).drawModifier);
const hitRow = [...nodes.keys()].find(id => nodes.get(id).onClick);
const oldClick = nodes.get(hitRow).onClick, oldTouch = nodes.get(hitRow).onTouch;
const painter = nodes.get(paintRow).drawModifier;
assert.equal(nodes.get(hitRow).responseRegion, first.hitIndex.regions, 'reuse cached region array');
oldClick({ ...mouse, x: 20 }); assert.deepEqual(clicks, [], 'gap is not a link');
oldClick(mouse); assert.deepEqual(clicks, ['first0']);
oldTouch(event(0)); painter.drawBehind({ canvas });
assert.deepEqual(canvas.lastRect, { left: 0, top: 0, right: 24, bottom: 40 });
assert.equal(brushCount, 1); oldTouch(event(2)); oldClick(touchClick);
assert.deepEqual(clicks, ['first0', 'first0']); assert.equal(painter.pressRect, null);
oldTouch(event(0)); oldTouch(event(1, 30)); oldClick(touchClick);
oldTouch(event(0)); oldTouch(event(3)); oldClick(touchClick);
oldTouch(event(0)); oldTouch(event(0, 5, 5, 2)); oldClick(touchClick);
assert.equal(clicks.length, 2, 'move outside, cancel and multitouch reject clicks');
oldTouch(event(0));
view.resetStateVarsOnReuse({ plan: null, onLinkTap: link => clicks.push(link.url) });
update(root); update(paintRow); update(hitRow);
assert.equal(nodes.get(root).width, 0); assert.equal(nodes.get(paintRow).height, 0);
assert.equal(nodes.get(paintRow).accessibilityText, '');
assert.equal(nodes.get(paintRow).accessibilityLevel, 'no');
assert.equal(nodes.get(hitRow).responseRegion.length, 0);
oldClick(mouse); oldTouch(event(2)); painter.drawBehind({ canvas });
assert.equal(clicks.length, 2); assert.equal(painter.pressRect, null);
view.resetStateVarsOnReuse({ plan: second, onLinkTap: link => clicks.push(link.url) });
update(paintRow); update(root); update(hitRow);
assert.equal(nodes.get(root).width, 200); assert.equal(nodes.get(paintRow).accessibilityText, 'second');
oldClick(mouse); nodes.get(hitRow).onClick(touchClick);
assert.equal(clicks.length, 2, 'neither old callback nor new callback may finish an old press');
nodes.get(hitRow).onTouch(event(0)); nodes.get(hitRow).onTouch(event(2)); nodes.get(hitRow).onClick(touchClick);
assert.equal(clicks.at(-1), 'second0');
const before = invalidations, regions = second.hitIndex.regions;
for (let i = 0; i < 1000; i++) { update(root); update(paintRow); update(hitRow); painter.drawBehind({ canvas }); }
assert.equal(invalidations, before); assert.equal(brushCount, 1);
assert.equal(nodes.get(hitRow).responseRegion, regions);
// Runtime accessibility toggle keeps the original independently spoken links.
listener(true); render(view);
assert.equal([...callbacks.values()].filter(c => c.type === Row).length, 48);
assert.equal([...nodes.values()].filter(n => n.accessibilityRole === 0).length, 47);
const accessibleClick = [...nodes.values()].find(n => n.onClick).onClick;
accessibleClick(); assert.equal(clicks.at(-1), 'second0');
view.resetStateVarsOnReuse({ plan: first, onLinkTap: link => clicks.push(link.url) });
const n = clicks.length; accessibleClick(); assert.equal(clicks.length, n);
listener(false); render(view);
assert.equal([...callbacks.values()].filter(c => c.type === Row).length, 2);
// Differential lookup, including unusual overlapping rectangles and input order.
let seed = 9;
function rand(n) { seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0; return seed % n; }
const mixed = Array.from({ length: 200 }, (_, i) => ({ ...first.hits[0], key: String(i),
  x: rand(120), y: rand(400), widthVp: rand(60) + 1, heightVp: rand(80) + 1 }));
const index = new ctx.DrawnRichHitIndex(mixed);
for (let i = 0; i < 10000; i++) {
  const x = rand(200), y = rand(500);
  const expected = mixed.findLast(h => x >= h.x && x < h.x + h.widthVp && y >= h.y && y < h.y + h.heightVp) || null;
  assert.equal(index.find(x, y), expected);
}
console.log('PASS: 57/47 hit nodes -> 1; null/stale reuse, gaps, press, cancel/multitouch, a11y toggles, cached regions/painter, 10000 differential hit tests.');
