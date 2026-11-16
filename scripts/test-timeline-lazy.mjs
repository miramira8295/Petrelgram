// Exercise the compiled adapter and row callback closures. Native List anchoring
// and actual pixels still require the device A/B; these tests do not predict ms.
import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
const ts = (await import(process.env.TYPESCRIPT_MODULE || 'typescript')).default;
const root = 'entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/';
const source = fs.readFileSync(root + 'pages/chat/TimelineLazyDataSource.ts', 'utf8');
assert.match(source, /@ObservedV2/);
assert.match(source, /@Trace\s+item:/);
assert.doesNotMatch(source, /@Trace\s+index:/);
const operations = { ADD: 'add', DELETE: 'delete', RELOAD: 'reload' };
const ctx = vm.createContext({ DataOperationType: operations, DrawnStage: { LazySetRows: 0 }, drawnStageMetrics: { begin(){return false;}, end(){}, rowChanged() {} }, DrawnRowChangeSource: { List: 0 } });
const evaluate = s => vm.runInContext(ts.transpileModule(s, { compilerOptions: { target: ts.ScriptTarget.ES2020 } }).outputText, ctx);
evaluate(source.replace(/^import.*;\n/gm, '').replace(/@(?:ObservedV2|Trace)\s*/g, '').replace(/\bexport /g, '') + '\nglobalThis.Source = TimelineLazyDataSource;');
const ds = new ctx.Source();
let calls = 0, writes = 0, notifications = 0, expected = [], mirror = [];
const keyOf = row => { calls++; return `${row.id}:0`; };
const listener = { onDatasetChange(ops) {
  notifications++;
  assert.equal(ds.totalCount(), expected.length, 'new data is visible before notification');
  for (let i = 0; i < expected.length; i++) {
    assert.equal(ds.getData(i).item, expected[i]);
    assert.equal(ds.getData(i).index, i);
  }
  for (const op of ops) {
    if (op.type === operations.ADD) {
      assert.equal(op.key, undefined, 'keys must be generated through the framework callback');
      mirror.splice(op.index, 0, ...Array.from({length: op.count}, (_, i) => ds.getData(op.index + i).key));
    }
    else if (op.type === operations.DELETE) mirror.splice(op.index, op.count);
    else mirror = expected.map(row => `${row.id}:0`);
  }
  assert.deepEqual(mirror, expected.map(row => `${row.id}:0`));
} };
ds.registerDataChangeListener(listener);
const publish = next => { expected = next; ds.setRows(next, keyOf, 0, 0); };
let rows = Array.from({length: 40}, (_, i) => ({ id: i + 100 }));
publish(rows);
const retained = Array.from({length: ds.totalCount()}, (_, i) => ds.getData(i));
for (const row of retained) {
  let current = row.item;
  Object.defineProperty(row, 'item', { get: () => current, set: v => { writes++; current = v; } });
}
// A whole history page exceeds the current 3-row cache. The data source must
// still retain existing bindings; production keeps chunking for the first A/B.
const head = Array.from({length: 29}, (_, i) => ({ id: i + 1 }));
rows = head.concat(rows); publish(rows);
for (let i = 0; i < retained.length; i++) {
  assert.equal(ds.getData(i + 29), retained[i]);
  assert.equal(retained[i].index, i + 29);
}
assert.equal(writes, 0);
const before = { calls, notifications };
for (let i = 0; i < 1000; i++) publish(rows);
assert.equal(calls, before.calls); assert.equal(notifications, before.notifications); assert.equal(writes, 0);
rows = rows.slice(); rows[29] = { id: 100, caption: 'changed', memberIds: [100, 101], initialDeferred: false };
publish(rows);
assert.equal(writes, 1); assert.equal(notifications, before.notifications); assert.equal(calls, before.calls + 1);
assert.equal(ds.getData(29), retained[0]);
// Retained callback reads the shifted index, not its original position.
const delayedSize = () => [retained[0].index, retained[0].item];
assert.equal(delayedSize()[0], 29);
rows = rows.filter(row => row.id !== 100); publish(rows);
assert.equal(delayedSize()[0], -1);

// Deterministic mixed insert/delete/reorder/patch cases, independent observer
// applies notifications to its own key list. Check cache bounds after each.
let serial = 1000;
for (let turn = 0; turn < 500; turn++) {
  const mode = turn % 6;
  if (mode === 0) rows = [{id: serial++}, ...rows];
  else if (mode === 1) rows = [...rows, {id: serial++}];
  else if (mode === 2 && rows.length > 3) rows = rows.filter((_, i) => i !== 2);
  else if (mode === 3) rows = rows.slice().reverse();
  else if (mode === 4) rows = rows.map((row, i) => i === 0 ? {...row, caption: String(turn)} : row);
  else rows = rows.slice(1);
  const oldCalls = calls;
  publish(rows);
  assert.ok(calls - oldCalls <= rows.length);
  assert.equal(ds.byKey.size, rows.length); assert.equal(ds.byRow.size, rows.length);
  for (let i = 0; i < rows.length; i++) assert.equal(ds.getData(i).item, rows[i]);
}

// Test the real CompileArkTS-generated binding closure, including its update
// path. Same key + changed content must re-read the wrapper, not a captured item.
const hostSource = fs.readFileSync(root + 'pages/chat/ChatTimelineHost.ts', 'utf8');
const ast = ts.createSourceFile('host.ts', hostSource, ts.ScriptTarget.Latest, true);
const host = ast.statements.find(n => ts.isClassDeclaration(n) && n.name.text === 'ChatTimelineHost');
const member = name => host.members.find(n => n.name?.getText(ast) === name).getText(ast);
assert.match(hostSource, /LazyForEach\.create/);
assert.match(hostSource, /this\.session\.lazyRows/);
assert.match(member('timelineRow'), /ri\.index < 0/);
ctx.MessageRowHost = class { constructor(parent, params) { this.params = params; } };
ctx.ViewV2 = { create(v) { ctx.created = v; } };
evaluate(`class Host { ${member('preparedMessageBubble')} } globalThis.Host = Host;`);
const h = new ctx.Host();
let renderCallback, update;
h.observeComponentCreation2 = cb => { renderCallback = cb; cb(1, true); };
h.updateStateVarsOfChildByElmtId = (_, p) => { update = p; };
h.prepareRowData = group => ({ from: group });
const binding = ds.getData(0);
h.preparedMessageBubble(binding);
assert.equal(ctx.created.params.group, binding.item);
const changed = {...binding.item, caption: 'latest'};
binding.item = changed; renderCallback(1, false);
assert.equal(update.group, changed); assert.equal(update.data.from, changed);
assert.equal(ctx.created.paramsGenerator_().group, changed);

// All four session publication entry points route to the same source only in
// lazy mode; preserve geometry-before-notify and the existing Repeat branch.
const sessionSource = fs.readFileSync(root + 'pages/chat/ChatTimelineSession.ts', 'utf8');
const sa = ts.createSourceFile('session.ts', sessionSource, ts.ScriptTarget.Latest, true);
const session = sa.statements.find(n => ts.isClassDeclaration(n) && n.name.text === 'ChatTimelineSession');
const sm = name => session.members.find(n => n.name?.getText(sa) === name).getText(sa);
for (const name of ['replaceTimelineGroups', 'splicePrependGroups', 'spliceAppendGroups', 'spliceDropGroups']) {
  const method = sm(name);
  assert.ok(method.indexOf('this.viewportGeometry.reconcile') < method.indexOf('this.publishLazyRows'));
  assert.match(method, /this\.lazyTimelineEnabled/);
}
assert.match(sm('publishLazyRows'), /this\.groups = groups/);
assert.match(sm('publishLazyRows'), /this\.lazyRows\.setRows/);
assert.match(sessionSource, /KEY_DEBUG_TIMELINE_LAZY/);
console.log('PASS: compiled lazy source retains 40 rows through 29-row prepend; 1000 unchanged publications cause no key work, item writes or notifications; 500 mixed changes match independent observer; compiled row closure sees same-key edits; all session publication paths wired.');

// Run the actual compiled paging gates with pending history, without a UI.
evaluate(`class Gates { ${sm('maybeLoadOlder')} ${sm('flushQueuedOlderLoad')} } globalThis.Gates = Gates;`);
ctx.logW = () => {};
const gate = new ctx.Gates();
let pending = 20, loads = 0;
const store = { loadOlderMerged() { loads++; return true; }, getHasMoreOlder() { return true; } };
gate.bindings = { store: () => store };
gate.prependChunker = { pendingRows: () => pending };
gate.olderArmed = true; gate.olderLoadQueued = true; gate.listTouchActive = false;
gate.groups = []; gate.curStartIdx = 0;
for (let i = 0; i < 1000; i++) { gate.maybeLoadOlder(); gate.flushQueuedOlderLoad(); }
assert.equal(loads, 0); assert.equal(gate.olderArmed, true); assert.equal(gate.olderLoadQueued, true);
pending = 0; gate.flushQueuedOlderLoad(); gate.maybeLoadOlder();
assert.equal(loads, 1, 'drain resumes queued load once, not twice');
console.log('PASS timeline pending-history backpressure');

// Larger LazyForEach batches remain bounded and preserve the shown suffix.
evaluate(fs.readFileSync(root + 'util/timelineCacheBudget.ts', 'utf8').replace(/\bexport /g, '') + '\nglobalThis.budget = timelinePrependRows;');
evaluate(fs.readFileSync(root + 'util/prependChunker.ts', 'utf8').replace(/^import.*;\n/gm, '').replace(/\bexport /g, '') + '\nglobalThis.Chunker = PrependChunker;');
for (const moving of [true, false]) {
  let now = 0, scheduled = null, publications = 0;
  const clock = { now: () => now, schedule: cb => { scheduled = cb; return 1; }, cancel: () => { scheduled = null; } };
  const chunker = new ctx.Chunker(x => x, true, clock);
  let displayed = ['old0', 'old1'];
  const target = [...Array.from({length: 29}, (_, i) => `new${i}`), ...displayed];
  const publish = () => {
    const prev = displayed.length;
    displayed = chunker.shape(displayed, target); publications++;
    assert.ok(displayed.length - prev <= (moving ? 8 : 16));
    assert.deepEqual(Array.from(displayed.slice(-2)), ['old0', 'old1']);
  };
  chunker.bind({ chunkRows: () => ctx.budget(8, true, moving), allowed: () => true, republish: publish });
  publish();
  while (scheduled) { const cb = scheduled; scheduled = null; now += 120; cb(); }
  assert.equal(publications, moving ? 4 : 2);
  assert.equal(chunker.pendingRows(), 0); assert.equal(displayed, target);
}
console.log('PASS lazy bounded 8/16-row drain');
