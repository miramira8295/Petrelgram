// Integration boundary: real media controller/session/activation queue and the
// HAP compiler's retained mediaTile observers. Native IO and child instances are
// doubles; video callback identity is covered by test-drawn-content-row.mjs.
import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
const imported = await import(process.env.TYPESCRIPT_MODULE || 'typescript');
const ts = imported.default || imported;
const root = 'entry/src/main/ets/';
const compiled = 'entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/' + root;
const frames = [], pending = [], cache = new Map();
const key = r => `${r.path}:${r.width}:${r.height}:${r.opaque}`;
const ui = { vp2px: n => n * 2, postFrameCallback: f => frames.push(f), postDelayedFrameCallback: f => frames.push(f) };
const ctx = vm.createContext({
  FrameCallback: class {}, DrawModifier: class { invalidate() {} },
  ImageFit: { Cover: 0, Contain: 1, Fill: 2 }, vp2pxUI: n => n * 2,
  drawing: { SamplingOptions: class {}, FilterMode: { FILTER_MODE_LINEAR: 1 } },
  thumbPathFor: () => '', subscribeThumbPath: () => () => {},
  senderChannelKey: (id, user) => `${id}:${user}`, senderAvatarFor: () => '', subscribeSenderAvatar: () => () => {},
  cachedPixelMap: r => cache.get(key(r)), loadPixelMapSync: () => undefined,
  loadPixelMap: r => new Promise(resolve => pending.push({ r, resolve })), cancelPixelMap() {},
  retainPixelMap: h => h.refs++, releasePixelMap: h => h.refs--,
  pinPixelMap() {}, pinPixelMapBounded() {}, setTimeout, clearTimeout, logW() {},
  ViewV2: { create() {} }, HitTestMode: { None: 0 }, Alignment: { Center: 0 }
});
function evaluate(source, filename) {
  vm.runInContext(ts.transpileModule(source, { compilerOptions: { target: ts.ScriptTarget.ES2020 } }).outputText, ctx, { filename });
}
function load(path, names = []) {
  const source = fs.readFileSync(root + path, 'utf8')
    .replace(/^import\s[\s\S]*?;\r?\n/gm, '').replace(/@(?:ObservedV2|Trace)\s*/g, '').replace(/\bexport /g, '');
  evaluate(source + names.map(n => `\nglobalThis.${n} = ${n};`).join(''), path);
}
for (const file of ['imageSwap', 'cachedImageSpec', 'CachedImageSession', 'liveThumbPath', 'miniThumbPlaceholder',
  'drawnImageRevision', 'drawnFrameBatch', 'oneShotFrameCallback', 'drawnStageMetrics', 'drawnFrameQueue', 'drawnMediaActivation']) load(`util/${file}.ets`);
load('pages/chat/DrawnSlotActivation.ets');
load('pages/chat/DrawnSlotContent.ets');
load('pages/common/DrawnImageReceiver.ets');
load('pages/chat/DrawnMediaController.ets', ['DrawnMediaController']);

// Extract actual compiled methods, avoiding constructor/service initialization.
const filename = compiled + 'pages/chat/DrawnMessageRow.ts';
const source = ts.createSourceFile(filename, fs.readFileSync(filename, 'utf8'), ts.ScriptTarget.Latest, true);
const rowClass = source.statements.find(n => ts.isClassDeclaration(n) && n.name.text === 'DrawnMessageRow');
const methods = ['imageSlot', 'readImageSlot', 'mediaActivated', 'mediaOverlay', 'mediaTile'];
const selected = methods.map(name => {
  const member = rowClass.members.find(n => ts.isMethodDeclaration(n) && n.name.getText(source) === name);
  assert.ok(member, `compiled row contains ${name}`);
  return member.getText(source);
});
evaluate(`class RowProbe { ${selected.join('\n')} }; globalThis.RowProbe = RowProbe;`, filename);

// Retain observers while an If keeps its branch; remove its descendants when
// the branch changes. A stale ready=false gate therefore really destroys and
// recreates the video double instead of merely updating an orphan observer.
let currentId = 0, nextId = 0, constructions = 0, destructions = 0;
const observers = new Map(), owners = new Map(), branches = new Map(), children = new Map();
function invoke(id, callback, initial) {
  const previous = currentId;
  currentId = id;
  try { callback(id, initial); } finally { currentId = previous; }
}
function removeDescendants(owner) {
  for (const [id, parent] of [...owners]) if (parent === owner) {
    removeDescendants(id);
    observers.delete(id); owners.delete(id); branches.delete(id);
    if (children.delete(id)) destructions++;
  }
}
const row = new ctx.RowProbe();
Object.assign(row, {
  kind: 'album', sendState: 'sent', scroll: { active: false }, actions: {},
  nativeAnchors: { bind() { return {}; } }, mediaFrames: Array(6).fill({})
});
row.observeComponentCreation2 = callback => {
  const id = ++nextId;
  owners.set(id, currentId); observers.set(id, callback); invoke(id, callback, true);
};
row.ifElseBranchUpdateFunction = (branch, create) => {
  if (branches.get(currentId) === branch) return;
  removeDescendants(currentId); branches.set(currentId, branch); create();
};
row.updateStateVarsOfChildByElmtId = (id, params) => {
  assert.ok(children.has(id), 'updates target a live retained video');
  children.get(id).params = params;
};
ctx.DrawnAlbumVideo = class {
  constructor(_owner, params, _a, id) { constructions++; this.params = params; children.set(id, this); }
};
for (const type of ['Stack', 'If', 'Image', 'Row', 'Text', 'SymbolGlyph']) ctx[type] = new Proxy({}, { get: () => () => {} });
function replay() {
  for (const [id, callback] of [...observers]) if (observers.has(id)) invoke(id, callback, false);
}
async function flushFrame() {
  for (let i = 0; i < 8; i++) await Promise.resolve();
  for (const frame of frames.splice(0)) frame.onFrame(0);
  replay();
}
async function drain() { for (let i = 0; i < 12; i++) await flushFrame(); assert.equal(frames.length, 0); }
function handle(name) { return { refs: 1, width: 200, height: 160, pixelMap: { name } }; }
function tiles(base, cold = false) {
  return Array.from({ length: 6 }, (_, i) => ({ width: 100, height: 80, cell: {
    idx: i, chatId: 1, messageId: base + i, thumbFileId: cold ? base + i : 10 + i,
    thumbPath: cold ? `/cold-${base}-${i}` : `/warm-${i}`, mini: '', isVideo: true,
    isLive: false, isPlaySlot: false, uploading: false, failed: false, videoFileId: base + 1000 + i
  } }));
}
const group = { head: { senderId: 1, senderIsUser: true, senderAvatarPath: '' } };
const media = new ctx.DrawnMediaController(() => {}, () => {});
row.media = media;
function bind(next) {
  row.nativeTiles = next;
  media.prepare(ui, { tiles: next, density: 2, avatar: { width: 0 } }, group, true);
}
for (let i = 0; i < 6; i++) cache.set(key({ path: `/warm-${i}`, width: 200, height: 160, opaque: true }), handle(`warm-${i}`));
bind(tiles(100));
for (let i = 0; i < 6; i++) row.mediaTile({ index: i, key: `physical-${i}` });
assert.equal(constructions, 0, 'unprepared video islands wait for a frame even when posters are cached');
await drain();
assert.equal(constructions, 6); assert.equal(children.size, 6); assert.equal(pending.length, 0);
const physicalSlots = [...media.slots], videoInstances = [...children.values()];
for (const base of [200, 100, 300]) {
  media.recycle(); bind(tiles(base)); replay();
  assert.equal(constructions, 6, 'prepared A/B/A reuse does not create another video island');
  assert.equal(destructions, 0, 'reuse keeps the video branch mounted');
  assert.deepEqual([...media.slots], physicalSlots);
  assert.deepEqual([...children.values()], videoInstances);
  assert.ok([...children.values()].every(child => child.params.cell === undefined), 'old video content is cleared before staged publication');
  let published = 0;
  for (let frame = 0; frame < 12 && published < 6; frame++) {
    await flushFrame();
    const now = [...children.values()].filter(child => child.params.cell !== undefined).length;
    assert.ok(now - published <= 2, 'at most two physical slots publish new video input per frame');
    assert.ok(now >= published, 'published current content does not disappear');
    published = now;
    assert.equal(constructions, 6); assert.equal(destructions, 0);
  }
  assert.equal(published, 6, 'all staged content becomes available within a bounded number of frames');
  await drain();
  [...children.values()].forEach((child, i) => assert.equal(child.params.cell, row.nativeTiles[i].cell));
  assert.equal(constructions, 6); assert.equal(destructions, 0);
}

// Keeping the native branch alive must not keep the old message's bitmap or
// bypass staged IO. Cancel B before its frame, then only C may start decoding.
media.recycle(); bind(tiles(400, true)); replay();
assert.ok(media.slots.every(slot => slot.pixels === undefined), 'cold source blanks warm pixels synchronously');
assert.equal(pending.length, 0, 'cold decode remains queued');
assert.equal(constructions, 6); assert.equal(destructions, 0);
media.recycle(); bind(tiles(500, true)); replay();
await drain();
assert.equal(pending.length, 6, 'only six requests for the current attachment start');
assert.ok(pending.every(request => request.r.path.startsWith('/cold-500-')), 'cancelled attachment submits no IO');
for (const [i, request] of pending.entries()) request.resolve(handle(`cold-500-${i}`));
await drain();
media.slots.forEach((slot, i) => assert.equal(slot.pixels?.name, `cold-500-${i}`));
assert.equal(constructions, 6); assert.equal(destructions, 0);
[...children.values()].forEach((child, i) => assert.equal(child.params.cell, row.nativeTiles[i].cell));
media.dispose();
console.log('PASS: real controller + compiled retained mediaTile keeps six video instances through A/B/A reuse, updates current cells, clears cold sources, defers decode and cancels obsolete queued requests.');
