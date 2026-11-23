import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
const ts = (await import(process.env.TYPESCRIPT_MODULE || 'typescript')).default;
const root = 'entry/src/main/ets/';
const compile = code => ts.transpileModule(code, { compilerOptions: { target: ts.ScriptTarget.ES2020 } }).outputText;
const drain = async () => { for (let i = 0; i < 10; i++) await Promise.resolve(); };
function method(path, name) {
  const source = fs.readFileSync(root + path, 'utf8');
  const match = new RegExp(`^  (?:private )?${name}\\(`, 'm').exec(source);
  assert.ok(match, name);
  const ast = ts.createSourceFile('method.ts', 'class Probe {\n' + source.slice(match.index), ts.ScriptTarget.Latest, true);
  return ast.statements[0].members[0].getText(ast);
}
function setup() {
  const timers = new Map(), marks = [], errors = [];
  let next = 0;
  const ctx = vm.createContext({
    setTimeout: (fn, delay) => { timers.set(++next, { fn, delay }); return next; },
    clearTimeout: id => timers.delete(id), logE: e => errors.push(e), logI() {}, logW() {},
    powerSavingActive: () => false, powerAnimationDuration: (_k, duration) => duration,
    KEY_POWER_SMOOTH_TRANSITIONS: 'smooth'
  });
  for (const [file, exports] of [['rowLeaveChannel', ['RowLeaveChannel', 'wholeDeleteRowIds']],
    ['remoteMessageDeleteEffects', ['RemoteMessageDeleteEffects']]]) {
    const source = fs.readFileSync(root + 'util/' + file + '.ets', 'utf8').replace(/^import .*;\n/gm, '').replace(/^export /gm, '');
    vm.runInContext(compile(source + exports.map(n => `\nglobalThis.${n}=${n};`).join('')), ctx);
  }
  const channel = new ctx.RowLeaveChannel(), effects = new ctx.RemoteMessageDeleteEffects(channel);
  const groups = [{ head: { rowId: 10, contentType: 'photo' }, memberIds: [1, 2] },
    { head: { rowId: 30, contentType: 'text' }, memberIds: [3] },
    { head: { rowId: 40, contentType: 'system' }, memberIds: [4] }];
  const off = channel.subscribe(10, value => marks.push([10, value]));
  channel.subscribe(30, value => marks.push([30, value])); marks.length = 0;
  const event = (ids, extra = {}) => ({ chat_id: 7, message_ids: ids, is_permanent: true, from_cache: false, ...extra });
  return { ctx, timers, marks, errors, channel, effects, groups, off, event };
}
for (const [ids, extra, enabled] of [[[1], {}, true], [[4], {}, true], [[999], {}, true], [[3], { chat_id: 8 }, true],
  [[3], { from_cache: true, is_permanent: false }, true], [[3], {}, false], [[], {}, true]]) {
  const s = setup(); s.effects.begin(s.event(ids, extra), 7, s.groups, enabled, () => assert.fail('no refresh'));
  assert.equal(s.effects.active(), false); assert.equal(s.timers.size, 0); assert.equal(s.marks.length, 0);
}
{
  const s = setup(); let delivered = '';
  s.effects.begin(s.event([1, 2, 1]), 7, s.groups, true, () => { delivered = 'fallback'; });
  for (let i = 0; i < 1000; i++) s.effects.begin(s.event([1, 2]), 7, s.groups, true, () => assert.fail('duplicate'));
  assert.deepEqual(s.marks, [[10, 1]]);
  s.effects.defer(() => { delivered = 'old'; }); s.effects.defer(() => { delivered = 'latest'; });
  assert.equal(delivered, ''); s.channel.complete(10); await drain();
  assert.equal(delivered, 'latest'); assert.equal(s.effects.active(), false); assert.equal(s.timers.size, 0);
  assert.equal(s.channel.value(10), 0);
}
{
  const s = setup(); let localDone = false;
  const local = s.channel.play([30], true).then(() => { localDone = true; });
  s.effects.begin(s.event([3]), 7, s.groups, true, () => assert.fail('local ack must not replay'));
  const duplicate = s.channel.play([30], true); await duplicate;
  assert.equal(localDone, false); assert.equal(s.effects.active(), false);
  s.channel.complete(30); await local; assert.equal(localDone, true);
}
{
  const s = setup(); let done = 0;
  s.effects.begin(s.event([1, 2]), 7, s.groups, true, () => { done++; });
  const deadline = s.effects.timer;
  s.effects.begin(s.event([3]), 7, s.groups, true, () => { done++; });
  assert.equal(s.effects.timer, deadline, 'a burst must not extend the hold deadline');
  assert.equal(s.channel.particleBudget(), 4000);
  s.channel.complete(10); await drain(); assert.equal(done, 0);
  s.channel.complete(30); await drain(); assert.equal(done, 1); assert.equal(s.timers.size, 0);
}
for (const how of ['recycle', 'timeout', 'flush', 'cancel']) {
  const s = setup(); let done = 0;
  s.effects.begin(s.event([1, 2]), 7, s.groups, true, () => { done++; });
  if (how === 'recycle') s.off();
  if (how === 'timeout') s.timers.get(s.effects.timer).fn();
  if (how === 'flush') s.effects.flush();
  if (how === 'cancel') s.effects.cancel();
  await drain(); assert.equal(done, how === 'cancel' ? 0 : 1); assert.equal(s.timers.size, 0);
}
{
  const s = setup(); let delivered = '';
  s.effects.begin(s.event([1, 2]), 7, s.groups, true, () => { delivered = 'old'; });
  s.effects.cancel();
  s.effects.begin(s.event([3]), 7, s.groups, true, () => { delivered = 'new'; });
  await drain(); assert.equal(s.effects.active(), true); assert.equal(delivered, '');
  s.channel.complete(30); await drain(); assert.equal(delivered, 'new');
}
// Replay the actual page registration and actual store deletion method. The
// server update removes authoritative data immediately, before animation ends.
{
  const s = setup(), handlers = new Map(), published = [];
  const client = { onUpdate(type, cb) {
    const list = handlers.get(type) || []; list.push(cb); handlers.set(type, list);
    return () => {};
  } };
  s.ctx.getTdClient = () => client;
  const storeMethod = method('store/MessageStore.ets', 'onDelete');
  vm.runInContext(compile(`class Store {${storeMethod}} globalThis.Store=Store;`), s.ctx);
  const store = new s.ctx.Store();
  Object.assign(store, { chatId: 7, messages: [{ id: 1 }, { id: 2 }, { id: 3 }], pinnedIds: [],
    getMessages() { return this.messages; }, getCurrentNotifyKind: () => 'update',
    notifySoon() { this.listener(this.messages); }, subscribe(cb) { this.listener = cb; cb(this.messages); return () => {}; } });
  const names = ['applyRouteParams', 'registerChatLevelSubscriptions', 'animateRemoteDeletion', 'deleteAnimationEnabled'];
  vm.runInContext(compile(`class Page {${names.map(n => method('pages/chat/ChatPage.ets', n)).join('\n')}} globalThis.Page=Page;`), s.ctx);
  const page = new s.ctx.Page();
  Object.assign(page, { remoteDelete: s.effects, rowLeave: s.channel, chatId: 7, powerParticles: true, appIsForeground: true,
    timeline: { pageVisible: true, curStartIdx: 0, curEndIdx: 1, groups: s.groups, anchorIndexFresh: () => true },
    viewerOpen: () => false, navigationCoordinator: { beginRouteApply: () => true }, resolveRouteAndResetSession: () => ({}),
    subscribeChatLevelUpdates() {}, startChatBackgroundStore() {}, subscribeMembershipUpdates() {}, subscribeLiveCallUpdatesAndTimers() {},
    selection: { applyDeletion() {} }, subscriptions: { set() {} }, registerHeaderDerivedSubscriptions() {}, openStoreForRoute() {},
    search: { scheduleEntrySearch() {} }, command: { ensureCommandsLoaded() {} },
    createMessageStore() { this.store = store; client.onUpdate('updateDeleteMessages', e => store.onDelete(e)); return store; },
    onMessagesSnapshot(_store, list, kind) { published.push({ ids: list.map(m => m.id), kind }); }
  });
  page.applyRouteParams(); published.length = 0;
  for (const cb of handlers.get('updateDeleteMessages')) cb(s.event([1, 2]));
  assert.deepEqual(Array.from(store.getMessages(), m => m.id), [3]);
  assert.equal(published.length, 0); assert.equal(s.effects.active(), true);
  // Updates arriving during dissolve replace the one pending publication.
  store.messages = [{ id: 3 }, { id: 5 }]; store.listener(store.messages);
  store.messages = [{ id: 3 }, { id: 5 }, { id: 6 }];
  s.channel.complete(10); await drain();
  assert.equal(published.length, 1); assert.deepEqual(Array.from(published[0].ids), [3, 5, 6]);
  assert.equal(published[0].kind, 'update');
  for (const disabled of ['background', 'hidden', 'stale', 'particles', 'viewer']) {
    const before = s.marks.length;
    page.appIsForeground = disabled !== 'background'; page.timeline.pageVisible = disabled !== 'hidden';
    page.timeline.anchorIndexFresh = () => disabled !== 'stale'; page.powerParticles = disabled !== 'particles';
    page.viewerOpen = () => disabled === 'viewer';
    page.animateRemoteDeletion(s.event([3])); assert.equal(s.marks.length, before);
  }
}
console.log('PASS: remote/local/cache/partial-album filtering, duplicate and concurrent notifications, latest-only publication, authoritative immediate deletion, bounded timeout, reuse/hide/dispose and policy guards.');
