import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';

const ts = (await import(process.env.TYPESCRIPT_MODULE || 'typescript')).default;
const read = path => fs.readFileSync(new URL('../entry/src/main/ets/' + path, import.meta.url), 'utf8');
function method(source, name) {
  const match = new RegExp(`^  (?:private )?${name}\\(`, 'm').exec(source);
  assert.ok(match, `missing production method: ${name}`);
  const ast = ts.createSourceFile('probe.ts', `class Probe {\n${source.slice(match.index)}`,
    ts.ScriptTarget.Latest, true);
  return ast.statements[0].members[0].getText(ast);
}
const storage = new Map();
let writes = 0;
const ctx = vm.createContext({ AppStorage: {
  get: key => storage.get(key),
  setOrCreate: (key, value) => { writes++; storage.set(key, value); }
} });
function run(source) {
  const clean = source.replace(/^import\s[\s\S]*?;\r?\n/gm, '').replace(/\bexport /g, '');
  vm.runInContext(ts.transpileModule(clean, {
    compilerOptions: { target: ts.ScriptTarget.ES2020 }
  }).outputText, ctx);
}
run(read('util/layoutBreakpoint.ets'));
run(read('util/navFullScreen.ets'));
run(read('util/viewerWindowCover.ets'));
run(`class Page { ${method(read('pages/chat/ChatPage.ets'), 'onViewerTargetChanged')} }
  class Session { ${method(read('pages/chat/ChatViewerSession.ets'), 'setTarget')} }
  class Navigation { ${method(read('pages/chatlist/ChatListPage.ets'), 'viewerHidesNavBar')} }
  class Main { ${method(read('pages/main/MainScreen.ets'), 'dockVisible')} }
  globalThis.page = new Page(); globalThis.session = new Session();
  globalThis.nav = new Navigation(); globalThis.main = new Main();`);
const { page, session, nav, main } = ctx;
Object.assign(session, {
  viewerClosing: false, viewerMsgId: 0, openState: false,
  host: { onTargetChanged: () => page.onViewerTargetChanged() }
});
Object.assign(page, { syncChatTgsGate() {}, viewerOpen: () => session.openState });
Object.assign(main, {
  dockActive: true, appIsForeground: true, tab: 0, chatDetailHiding: false,
  storedNavBarFlag: () => true, // Includes a delayed framework "navbar visible" callback.
  wallpaperSplit: () => ctx.isSplitByBreakpoint(nav.widthBp, nav.heightBp, nav.forceSingleColumn, nav.windowPortrait)
});
function layout(widthBp, heightBp, windowPortrait, forceSingleColumn = false) {
  // Layout can change without another media-target notification.
  Object.assign(page, { widthBp, heightBp, windowPortrait, forceSingleColumn });
  Object.assign(nav, { widthBp, heightBp, windowPortrait, forceSingleColumn });
  refresh();
}
function refresh() {
  const request = storage.get('chatViewerCoversWindow') ?? false;
  nav.viewerCoversWindow = request;
  main.chatViewerCoversWindow = request;
}
function target(id) { session.setTarget(id); refresh(); }

layout(1, 2, true);
target(10);
layout(3, 0, false);
assert.equal(nav.viewerHidesNavBar(), true,
  'portrait open then wide landscape must hide the left pane without a target change');
assert.equal(main.dockVisible(), false);
const rotations = [
  [1, 2, true], [2, 0, false], [3, 0, false], [4, 0, false],
  [2, 1, false], [2, 1, true], [3, 0, false, true]
];
const beforeRotations = writes;
for (let i = 0; i < 1000; i++) {
  const geometry = rotations[i % rotations.length];
  layout(...geometry);
  assert.equal(nav.viewerHidesNavBar(), ctx.isSplitByBreakpoint(
    nav.widthBp, nav.heightBp, nav.forceSingleColumn, nav.windowPortrait));
  assert.equal(main.dockVisible(), false, 'viewer owns the window during intermediate breakpoint updates');
}
assert.equal(writes, beforeRotations, 'rotation does not publish new state or traverse messages');
target(11);
assert.equal(writes, beforeRotations, 'swiping media does not republish the same open state');
for (const geometry of rotations) {
  layout(...geometry);
  target(0);
  assert.equal(nav.viewerHidesNavBar(), false, 'close releases the pane in every layout');
  assert.equal(main.dockVisible(), true, 'normal navigation policy resumes');
  target(12);
  assert.equal(main.dockVisible(), false);
}
session.viewerClosing = true;
target(0);
target(13);
assert.equal(storage.get('chatViewerCoversWindow'), false, 'late target cannot reopen a closing viewer');
ctx.publishViewerCoversWindow(false);
const afterClose = writes;
ctx.publishViewerCoversWindow(false);
assert.equal(writes, afterClose, 'teardown release is idempotent');
console.log('PASS: portrait-to-wide-landscape viewer, 1000 rotations, split/forced-single modes, close/reopen, stale target, no rotation publications.');
