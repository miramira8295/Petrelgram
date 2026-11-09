import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';

const imported = await import(process.env.TYPESCRIPT_MODULE || 'typescript');
const ts = imported.default || imported;
const read = path => fs.readFileSync(new URL('../entry/src/main/ets/' + path, import.meta.url), 'utf8');
const main = read('pages/main/MainScreen.ets');
const pages = [
  ['pages/chatlist/ChatListPage.ets', 'CHAT_NAV_BAR_VISIBLE_KEY', 'chatNavBarVisible'],
  ['pages/main/ContactsPage.ets', 'CONTACTS_NAV_BAR_VISIBLE_KEY', 'contactsNavBarVisible'],
  ['pages/main/SettingsPage.ets', 'SETTINGS_NAV_BAR_VISIBLE_KEY', 'settingsNavBarVisible'],
  ['pages/main/MyProfilePage.ets', 'PROFILE_NAV_BAR_VISIBLE_KEY', 'profileNavBarVisible']
];

function method(source, name) {
  const match = new RegExp(`^  (?:private )?${name}\\(`, 'm').exec(source);
  assert.ok(match, `missing method ${name}`);
  const parsed = ts.createSourceFile('method.ts', `class Probe {\n${source.slice(match.index)}`,
    ts.ScriptTarget.Latest, true);
  return parsed.statements[0].members[0].getText(parsed);
}

function navCallback(source) {
  const marker = '.onNavBarStateChange(';
  const index = source.indexOf(marker);
  assert.ok(index >= 0);
  const parsed = ts.createSourceFile('callback.ts', 'const callback = ' + source.slice(index + marker.length),
    ts.ScriptTarget.Latest, true);
  const callback = parsed.statements[0].declarationList.declarations[0].initializer;
  assert.ok(ts.isArrowFunction(callback));
  return callback.getText(parsed);
}

const compile = source => ts.transpileModule(source, {
  compilerOptions: { target: ts.ScriptTarget.ES2020 }
}).outputText;

function setup() {
  const frames = [];
  const storage = new Map();
  let dock;
  const keys = Object.fromEntries(pages.map(([, key]) => [key, key]));
  const ctx = vm.createContext({
    ...keys,
    AppStorage: {
      get: key => storage.get(key),
      setOrCreate(key, value) {
        if (storage.get(key) === value) return;
        storage.set(key, value);
        const mapping = pages.find(([, candidate]) => key === candidate);
        if (mapping) { dock[mapping[2]] = value; dock.syncDock(); }
      }
    },
    OneShotFrameCallback: class { constructor(task) { this.task = task; } },
    DOCK_REVEAL_FRAME_DELAY_MS: 12, DOCK_FADE_DURATION: 120,
    KEY_POWER_SMOOTH_TRANSITIONS: 'smooth', Curve: { EaseOut: 'easeOut' },
    powerAnimationDuration: (_, duration) => duration,
    getCallSession: () => ({ current: () => ({ phase: 'idle' }) }),
    chatListInForeground: () => true,
    requestChatListFlush: () => {},
    isSplitByBreakpoint: (w, _h, force, portrait) => !force && !portrait && w >= 2
  });
  const methods = ['syncDock', 'dockVisible', 'storedNavBarFlag', 'onTabExternallyChanged',
    'aboutToDisappear', 'onAppForegroundChanged'].map(name => method(main, name)).join('\n');
  const fields = ['dockShown', 'dockMounted', 'dockBarOpen', 'dockRevealSeq', 'dockRevealPending', 'dockActive']
    .map(name => {
      const match = new RegExp(`(?:private )?${name}: (?:boolean|number) = [^;]+;`).exec(main);
      assert.ok(match, `missing field ${name}`);
      return match[0];
    }).join('\n');
  vm.runInContext(compile(`class DockProbe { ${fields}\n${methods} } globalThis.DockProbe = DockProbe;`), ctx);
  dock = new ctx.DockProbe();
  Object.assign(dock, {
    tab: 0, appliedTab: 0, appIsForeground: true,
    chatNavBarVisible: false, contactsNavBarVisible: false, settingsNavBarVisible: false, profileNavBarVisible: false,
    getUIContext: () => ({ postDelayedFrameCallback: cb => frames.push(cb.task), animateTo: (_, fn) => fn() }),
    miniBarHolder: { dispose() {} }, unsubNowPlaying: null, unsubVoice: null, unsubUnread: null,
    unsubStore: null, unsubCall: null, store: null
  });
  let chatPage = null;
  const handlers = pages.map(([path], tab) => {
    const source = read(path);
    const extra = tab === 0
      ? ['applyNavBarVisible', 'singleColDetailCoversNavBar', 'onChatDetailShownChanged', 'viewerHidesNavBar']
          .map(name => method(source, name)).join('\n')
      : '';
    vm.runInContext(compile(`{ class RootProbe { ${extra}\ncallback() { return ${navCallback(source)}; } }
      globalThis.RootProbe = RootProbe; }`), ctx);
    const page = new ctx.RootProbe();
    Object.assign(page, {
      navBarVisible: false, listRenderActive: false, lastReportedNavBarVisible: false,
      chatDetailShown: false, chatStack: { size: () => 0 },
      widthBp: 1, heightBp: 2, forceSingleColumn: false, windowPortrait: true, viewerCoversWindow: false,
      suspendListRendering() {}, flushFolderBadges() {}, resumeListRenderingAfterTransition() {}, closeQr() {}
    });
    if (tab === 0) chatPage = page;
    return page.callback();
  });
  return {
    dock, frames, handlers, chatPage,
    mount() { dock.dockActive = true; dock.syncDock(); },
    flush() { let n = 0; while (frames.length) { assert.ok(++n < 50); frames.shift()(); } },
    select(tab) { dock.tab = tab; dock.onTabExternallyChanged(); }
  };
}

function hidden(dock) {
  assert.equal(dock.dockShown, false);
  assert.equal(dock.dockMounted, false);
  assert.equal(dock.dockBarOpen, false);
}
function visible(dock) {
  assert.equal(dock.dockShown, true);
  assert.equal(dock.dockMounted, true);
  assert.equal(dock.dockBarOpen, true);
}
let passed = 0;
function check(name, run) {
  try { run(); passed++; } catch (error) { error.message = `${name}: ${error.message}`; throw error; }
}

check('cold start waits for the root visibility report', () => {
  const s = setup(); hidden(s.dock); s.mount(); s.flush(); hidden(s.dock);
  s.handlers[0](true); s.flush(); visible(s.dock);
});
for (let tab = 0; tab < pages.length; tab++) {
  check(`tab ${tab}: root -> detail -> root follows native reports`, () => {
    const s = setup(); s.mount(); s.select(tab);
    s.handlers[tab](true); s.flush(); visible(s.dock);
    s.handlers[tab](false); s.flush(); hidden(s.dock);
    s.handlers[tab](true); s.flush(); visible(s.dock);
  });
}
check('chat search and profile destinations remain hidden without any ChatPage state', () => {
  const s = setup(); s.mount(); s.handlers[0](true); s.flush();
  s.handlers[0](false); s.handlers[1](true); s.handlers[2](true); s.flush(); hidden(s.dock);
  s.select(1); s.flush(); visible(s.dock);
  s.select(0); s.flush(); hidden(s.dock);
});
check('a visible split root remains visible; a full-screen profile child hides', () => {
  const s = setup(); s.mount();
  Object.assign(s.dock, { widthBp: 3, heightBp: 1, windowPortrait: false });
  s.handlers[0](true); s.flush(); visible(s.dock);
  s.select(3); s.handlers[3](true); s.flush(); visible(s.dock);
  s.handlers[3](false); s.flush(); hidden(s.dock);
});
check('inactive tab reports do not replace the selected tab visibility', () => {
  const s = setup(); s.mount(); s.handlers[0](true); s.flush();
  s.handlers[2](false); s.flush(); visible(s.dock);
  s.select(2); s.flush(); hidden(s.dock);
  s.handlers[0](true); s.flush(); hidden(s.dock);
});
for (const frameCount of [0, 1]) {
  check(`hide cancels a reveal after ${frameCount} frames`, () => {
    const s = setup(); s.mount(); s.handlers[0](true);
    for (let i = 0; i < frameCount; i++) s.frames.shift()();
    s.handlers[0](false); s.flush(); hidden(s.dock);
    s.handlers[0](true); s.flush(); visible(s.dock);
  });
  check(`reveal rechecks visibility after ${frameCount} frames`, () => {
    const s = setup(); s.mount(); s.handlers[0](true);
    for (let i = 0; i < frameCount; i++) s.frames.shift()();
    s.dock.chatNavBarVisible = false;
    s.flush(); hidden(s.dock);
    assert.equal(s.dock.dockRevealPending, false);
  });
}
check('rapid switching cannot revive a pending reveal on a hidden root', () => {
  const s = setup(); s.mount(); s.handlers[0](true); s.select(2); s.flush(); hidden(s.dock);
  s.select(0); s.flush(); visible(s.dock);
});
check('destroy invalidates all pending frame callbacks', () => {
  const s = setup(); s.mount(); s.handlers[0](true); s.frames.shift()();
  s.dock.aboutToDisappear(); s.flush(); hidden(s.dock);
  s.handlers[1](true); s.flush(); hidden(s.dock);
});
check('foreground resumes a cancelled reveal and respects detail visibility', () => {
  const s = setup(); s.mount(); s.handlers[0](true);
  s.dock.appIsForeground = false; s.dock.onAppForegroundChanged(); s.flush(); hidden(s.dock);
  s.dock.appIsForeground = true; s.dock.onAppForegroundChanged(); s.flush(); visible(s.dock);
  s.handlers[0](false);
  s.dock.appIsForeground = false; s.dock.onAppForegroundChanged();
  s.dock.appIsForeground = true; s.dock.onAppForegroundChanged(); s.flush(); hidden(s.dock);
});
check('spurious visible=true on router.back() from GroupAdminPage stays hidden until chatStack empties', () => {
  const s = setup(); s.mount();
  let stackDepth = 0;
  s.chatPage.chatStack = { size: () => stackDepth };
  s.handlers[0](true); s.flush(); visible(s.dock);
  stackDepth = 2; s.chatPage.chatDetailShown = true;
  s.handlers[0](false); s.flush(); hidden(s.dock);
  s.handlers[0](true); s.flush(); hidden(s.dock);
  stackDepth = 1; s.chatPage.onChatDetailShownChanged(); s.flush(); hidden(s.dock);
  stackDepth = 0; s.chatPage.chatDetailShown = false;
  s.chatPage.onChatDetailShownChanged(); s.flush(); visible(s.dock);
});
console.log(`Dock visibility: ${passed} scenarios passed (native callbacks and frame scheduling are simulated).`);
