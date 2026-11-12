// Differential checks of production preparation and candidate lifecycle methods.
// BEFORE_ALBUM_PREPARATION points at the batch's source backup for parity checks.
import fs from 'node:fs';
import vm from 'node:vm';
import path from 'node:path';
import assert from 'node:assert/strict';
const imported = await import(process.env.TYPESCRIPT_MODULE || 'typescript');
const ts = imported.default || imported;
const root = new URL('../', import.meta.url);
const read = name => fs.readFileSync(new URL(name, root), 'utf8');
const beforeRoot = process.env.BEFORE_ALBUM_PREPARATION;
const cacheFile = 'entry/src/main/ets/util/albumCellRenderData.ets';
// The preserved fallback owns the original candidate lifecycle now.
const componentFile = 'entry/src/main/ets/pages/chat/LegacyAlbumMessageBubble.ets';
const beforeComponentFile = 'entry/src/main/ets/pages/chat/AlbumMessageBubble.ets';
const oldRead = name => fs.readFileSync(path.join(beforeRoot, name), 'utf8');
function compile(source) {
  const instrument = context => {
    const visit = node => {
      const updated = ts.visitEachChild(node, visit, context);
      const helper = ts.isArrayLiteralExpression(node) ? '__array' :
        ts.isObjectLiteralExpression(node) ? '__object' : '';
      return helper ? ts.factory.createCallExpression(ts.factory.createIdentifier(helper), undefined, [updated]) : updated;
    };
    return node => ts.visitNode(node, visit);
  };
  return ts.transpileModule(source.replace(/^import[\s\S]*?;\n/gm, '').replace(/\bexport /g, ''),
    { compilerOptions: { target: ts.ScriptTarget.ES2020 }, transformers: { before: [instrument] } }).outputText;
}
function context() {
  const allocations = { arrays: 0, objects: 0, maps: 0 };
  const ctx = vm.createContext({ allocations,
    __array: value => { allocations.arrays++; return value; },
    __object: value => { allocations.objects++; return value; },
    Map: class extends Map { constructor(...args) { super(...args); allocations.maps++; } }
  });
  vm.runInContext(`for (const name of ['map','slice']) {
    const original = Array.prototype[name];
    Array.prototype[name] = function(...args) { allocations.arrays++; return original.apply(this,args); };
  }`, ctx);
  return { ctx, allocations, reset() { for (const key of Object.keys(allocations)) allocations[key] = 0; } };
}
function cacheSetup(source = read(cacheFile)) {
  const host = context();
  const slot = read('entry/src/main/ets/pages/chat/playSlot.ets').match(/export function slotKey\([\s\S]*?\n}/)[0];
  vm.runInContext(compile(read('entry/src/main/ets/util/packAlbumRows.ets') + '\n' + slot + '\n' + source) +
    '\nglobalThis.cache = new AlbumCellRenderCache();', host.ctx);
  return { ...host, cache: host.ctx.cache };
}
const data = () => ({ chatId: -100, selectionActive: false, selectedMemberIds: [],
  playSlotKey: '', autoplayMuted: true, playSlotStartMs: 0 });
function group(count = 6) {
  const result = { head: { rowId: 10, isAnimation: false, sendState: '' }, photoRatios: [],
    memberIds: [], photoPaths: [], photoFileIds: [], photoMinis: [], photoProgress: [], photoFailed: [],
    photoIsVideo: [], photoIsLive: [], videoFileIds: [], videoFileSizes: [], videoDurations: [],
    videoMimeTypes: [], inlineFileIds: [], inlineFileSizes: [] };
  for (let i = 0; i < count; i++) {
    result.photoRatios.push(0.7 + (i % 4) * 0.4); result.memberIds.push(100 + i);
    result.photoPaths.push(`/image/${i}`); result.photoFileIds.push(1000 + i);
  }
  return result;
}
const plain = x => JSON.parse(JSON.stringify(x));
function freezeSnapshot(rows) { for (const row of rows) { for (const cell of row) Object.freeze(cell); Object.freeze(row); } Object.freeze(rows); }
let scenarios = 0;
function check(name, run) { run(); scenarios++; console.log(`PASS ${name}`); }
check('unchanged six-cell input allocates no temporary containers or cells', () => {
  const s = cacheSetup(), g = group(), d = data(), first = s.cache.prepare(g, d, 280);
  freezeSnapshot(first); s.reset();
  for (let i = 0; i < 1000; i++) assert.equal(s.cache.prepare(g, d, 280), first);
  assert.deepEqual(s.allocations, { arrays: 0, objects: 0, maps: 0 });
  if (beforeRoot) {
    const old = cacheSetup(oldRead(cacheFile)); old.cache.prepare(g, d, 280); old.reset();
    for (let i = 0; i < 1000; i++) old.cache.prepare(g, d, 280);
    console.log('1000 unchanged reads, before:', old.allocations, 'after:', s.allocations);
  }
});
check('one cell change only replaces its cell, owning row and outer snapshot', () => {
  const s = cacheSetup(), g = group(), d = data(), first = s.cache.prepare(g, d, 280);
  freezeSnapshot(first); s.reset(); g.photoFailed[0] = true;
  const next = s.cache.prepare(g, d, 280);
  assert.notEqual(next, first); assert.notEqual(next[0], first[0]);
  assert.notEqual(next[0][0], first[0][0]); assert.equal(next[0][1], first[0][1]);
  for (let i = 1; i < next.length; i++) assert.equal(next[i], first[i]);
  assert.equal(first[0][0].failed, false); assert.equal(next[0][0].failed, true);
  assert.deepEqual(s.allocations, { arrays: 2, objects: 1, maps: 0 });
});
check('shrink, empty and regrow release private stale references without mutating snapshots', () => {
  const s = cacheSetup(), d = data(), first = s.cache.prepare(group(10), d, 280);
  const saved = plain(first); freezeSnapshot(first);
  for (const n of [2, 0, 9, 1, 18, 0, 6]) {
    const rows = s.cache.prepare(group(n), d, 280);
    assert.equal(rows.flat().length, n); assert.equal(s.cache.cells.length, n);
    assert.deepEqual(plain(first), saved);
  }
});
if (beforeRoot) check('4000 state transitions match previous values and row/cell reuse decisions', () => {
  const old = cacheSetup(oldRead(cacheFile)), next = cacheSetup();
  let seed = 81273;
  const random = max => { seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0; return seed % max; };
  let g = group(), d = data(), width = 280, previousOld, previousNext;
  const arrays = ['memberIds','photoPaths','photoFileIds','photoMinis','photoProgress','photoFailed',
    'photoIsVideo','photoIsLive','videoFileIds','videoFileSizes','videoDurations','videoMimeTypes',
    'inlineFileIds','inlineFileSizes'];
  const strings = new Set(['photoPaths','photoMinis','videoMimeTypes']);
  const booleans = new Set(['photoFailed','photoIsVideo','photoIsLive']);
  const identities = (rows, previous) => ({ outer: rows === previous,
    rows: rows.map((row,i) => row === previous?.[i]),
    cells: rows.map((row,i) => row.map((cell,j) => cell === previous?.[i]?.[j])) });
  for (let step = 0; step < 4000; step++) {
    const kind = random(10), idx = random(Math.max(1,g.photoRatios.length));
    if (kind === 0) g = group(random(19));
    else if (kind < 5) {
      const field = arrays[random(arrays.length)];
      g[field][idx] = strings.has(field) ? `value-${random(8)}` : booleans.has(field) ? random(2) === 1 : random(400);
    } else if (kind === 5) { width = [200,280,280.005,320][random(4)]; g.photoRatios[idx] = [0.1,0.7,1,2,8][random(5)]; }
    else if (kind === 6) { d.selectedMemberIds = [g.memberIds[idx]]; d.selectionActive = random(2) === 1; }
    else if (kind === 7) { d.chatId = -random(4); d.playSlotKey = `${g.memberIds[idx]}:${idx}`; }
    else if (kind === 8) { d.playSlotStartMs = random(10000); d.autoplayMuted = random(2) === 1; g.head.isAnimation = random(2) === 1; }
    else { g.head.sendState = ['sending','sent','failed',''][random(4)]; }
    const oldSnapshot = previousOld ? plain(previousOld) : null;
    const nextSnapshot = previousNext ? plain(previousNext) : null;
    const a = old.cache.prepare(g,d,width), b = next.cache.prepare(g,d,width);
    assert.deepEqual(plain(b),plain(a), `values at transition ${step}`);
    assert.deepEqual(plain(identities(b,previousNext)),plain(identities(a,previousOld)), `identity at transition ${step}`);
    if (previousOld) assert.deepEqual(plain(previousOld),oldSnapshot);
    if (previousNext) assert.deepEqual(plain(previousNext),nextSnapshot);
    freezeSnapshot(a); freezeSnapshot(b); previousOld=a; previousNext=b;
  }
});

function method(source, name) {
  const start = source.indexOf(`  private ${name}(`), end = source.indexOf('\n  }', start);
  assert.ok(start >= 0 && end > start); return source.slice(start, end + 4);
}
function candidatesSetup(source = read(componentFile)) {
  const host = context(), gone = [];
  vm.runInContext(compile(`class CandidateHost {
    competing = new Map<number, number>(); centers = new Map<number, number>(); attachedRowId = 0;
    ${method(source, 'syncCandidates')}
    ${method(source, 'releaseCandidates')}
  } globalThis.host = new CandidateHost();`), host.ctx);
  const component = host.ctx.host; component.actions = { onMediaGone(id, index) { gone.push([id, index]); } };
  return { ...host, component, gone };
}
check('photo-only lifecycle creates no empty video maps and still clears old centers', () => {
  const s = candidatesSetup(); s.component.group = group(); s.component.centers.set(0, 12); s.reset();
  for (let i = 0; i < 1000; i++) { s.component.releaseCandidates(); s.component.syncCandidates(); }
  assert.equal(s.allocations.maps, 0); assert.equal(s.component.centers.size, 0);
  assert.equal(s.component.attachedRowId, 10); assert.deepEqual(s.gone, []);
});
check('video update, video-to-photo and late removal preserve callbacks exactly once', () => {
  const s = candidatesSetup(), g = group(); s.component.group = g;
  g.photoIsVideo[0] = true; g.photoIsVideo[2] = true; s.component.syncCandidates();
  s.component.syncCandidates(); assert.deepEqual(s.gone, []);
  g.memberIds[0] = 999; s.component.syncCandidates(); assert.deepEqual(s.gone, [[100, 0]]);
  g.photoIsVideo = []; s.component.syncCandidates(); s.component.syncCandidates();
  s.component.releaseCandidates();
  assert.deepEqual(s.gone, [[100, 0], [999, 0], [102, 2]]);
  assert.equal(s.component.competing.size, 0);
});
if (beforeRoot) check('candidate events and maps match old methods across 1000 lifecycle transitions', () => {
  const old = candidatesSetup(oldRead(beforeComponentFile)), next = candidatesSetup();
  for (let i = 0; i < 1000; i++) {
    const g = group(i % 11); g.head.rowId = Math.floor(i / 3);
    g.photoIsVideo = g.memberIds.map((_,j) => (i+j) % 5 === 0);
    if (i % 7 === 0) g.memberIds[0] = -i;
    for (const s of [old,next]) {
      s.component.group = g; s.component.centers.set(0,10);
      if (i % 4 === 0) s.component.releaseCandidates();
      s.component.syncCandidates();
    }
    assert.deepEqual(next.gone,old.gone);
    assert.deepEqual([...next.component.competing],[...old.component.competing]);
    assert.deepEqual([...next.component.centers],[...old.component.centers]);
    assert.equal(next.component.attachedRowId,old.component.attachedRowId);
  }
});
console.log(`Album preparation: ${scenarios} scenarios passed; device rendering/performance still require verification`);
