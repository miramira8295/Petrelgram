import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';

const ts = (await import(process.env.TYPESCRIPT_MODULE || 'typescript')).default;
const root = 'entry/src/main/ets/';
const source = fs.readFileSync(root + 'pages/Index.ets', 'utf8');
const start = source.indexOf('  onBackPress(): boolean');
assert.ok(start >= 0);
const ast = ts.createSourceFile('probe.ts', 'class Probe {\n' + source.slice(start), ts.ScriptTarget.Latest, true);
const method = ast.statements[0].members[0].getText(ast);
const compile = text => ts.transpileModule(text, { compilerOptions: { target: ts.ScriptTarget.ES2020 } }).outputText;

function setup(tab = 0, depth = 0) {
  const storage = new Map([['mainTabIndex', tab], ['chatFolderIndex', 3], ['archive', true]]);
  const pops = [], writes = [];
  let floating = false, forum = false;
  const ctx = vm.createContext({
    AuthStage: { Ready: 1 }, KEY_ARCHIVE_PANE_OPEN: 'archive',
    collapseFloatingVideo: () => floating,
    closeForumDrawer: () => { const open = forum; forum = false; return open; },
    AppStorage: { get: key => storage.get(key), setOrCreate: (key, value) => { writes.push(key); storage.set(key, value); } }
  });
  // Use the production stack registry; the native stack boundary is simulated.
  const registry = fs.readFileSync(root + 'util/navStacks.ets', 'utf8')
    .replace(/^import .*;\n/gm, '').replace(/^export /gm, '');
  vm.runInContext(compile(registry + '\nglobalThis.registerStack = registerStack;'), ctx);
  for (const kind of ['chat', 'contacts', 'settings', 'profile']) {
    ctx.registerStack(kind, { size: () => depth, pop: animated => { pops.push([kind, animated]); depth--; } });
  }
  vm.runInContext(compile(`class Probe { ${method} } globalThis.Probe = Probe;`), ctx);
  const page = new ctx.Probe();
  Object.assign(page, { stage: 1, showShareSheet: false, isAddingAccount: () => false, returnToOriginalAccount() {} });
  return { page, storage, pops, writes, setFloating: v => { floating = v; }, setForum: v => { forum = v; } };
}

for (const [tab, kind] of ['chat', 'contacts', 'settings', 'profile'].entries()) {
  for (const depth of [1, 3]) {
    const s = setup(tab, depth);
    assert.equal(s.page.onBackPress(), true);
    assert.deepEqual(s.pops, [[kind, true]], 'one back event pops only the active stack once');
    assert.deepEqual(s.writes, [], 'detail back must preserve tab, archive and folder selection');
  }
}
for (const blocker of ['floating', 'share', 'account', 'login']) {
  const s = setup(2, 3);
  if (blocker === 'floating') s.setFloating(true);
  if (blocker === 'share') s.page.showShareSheet = true;
  if (blocker === 'account') s.page.isAddingAccount = () => true;
  if (blocker === 'login') s.page.stage = 0;
  assert.equal(s.page.onBackPress(), blocker !== 'login');
  assert.deepEqual(s.pops, [], 'overlays/auth keep priority over root stack fallback');
}
for (const tab of [1, 2, 3]) {
  const s = setup(tab);
  assert.equal(s.page.onBackPress(), true);
  assert.deepEqual(s.writes, ['mainTabIndex']);
  assert.equal(s.storage.get('mainTabIndex'), 0);
}
const s = setup(); s.setForum(true);
assert.equal(s.page.onBackPress(), true); assert.deepEqual(s.writes, []);
assert.equal(s.page.onBackPress(), true); assert.deepEqual(s.writes, ['archive']);
assert.equal(s.page.onBackPress(), true); assert.deepEqual(s.writes, ['archive', 'chatFolderIndex']);
assert.equal(s.page.onBackPress(), false, 'root can still return to the desktop');
console.log('PASS: root back pops one active destination; preserves folder/archive state and existing overlay/auth/root ordering.');
