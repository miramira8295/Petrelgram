import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
const ts = (await import(process.env.TYPESCRIPT_MODULE || 'typescript')).default;
const root = 'entry/src/main/ets/';
const ctx = vm.createContext({ ObservedV2: c => c, Trace: () => {} });
function run(source) {
  vm.runInContext(ts.transpileModule(source.replace(/^import\s[\s\S]*?;\r?\n/gm, '')
    .replace(/\bexport /g, ''), { compilerOptions: {
      target: ts.ScriptTarget.ES2020, experimentalDecorators: true
    } }).outputText, ctx);
}
run(fs.readFileSync(root + 'util/sheetDismissStack.ets', 'utf8'));
run(fs.readFileSync(root + 'pages/chat/ViewerForwardSession.ets', 'utf8') +
  '\nglobalThis.Session = ViewerForwardSession;');
// Drain cross-context async menu/permission continuations without real timers.
const tick = () => new Promise(resolve => setImmediate(resolve));
const source = { chatId: -100, messageId: 22, threadRootId: 9, canRemoveCaption: true };
function fixture(playing = true) {
  let resolve, reject, current = true, requests = 0, toggles = 0, denied = 0, errors = 0;
  const controls = { snapshot: () => ({ playing }), toggle: () => { toggles++; playing = !playing; } };
  let activeControls = controls;
  const session = new ctx.Session();
  const host = {
    choose: async () => false,
    properties: s => { requests++; assert.equal(s.messageId, 22);
      return new Promise((ok, fail) => { resolve = ok; reject = fail; }); },
    isCurrent: () => current, controls: () => activeControls,
    denied: () => { denied++; }, failed: () => { errors++; }
  };
  return { session, host, resolve: x => setImmediate(() => resolve?.(x)),
    reject: e => setImmediate(() => reject?.(e)),
    stale: () => { current = false; }, replacePlayer: () => { activeControls = {}; },
    stats: () => ({ requests, toggles, denied, errors, playing }) };
}
const allowed = { can_be_forwarded: true };
let f = fixture();
for (const bad of [null, { ...source, chatId: 0 }, { ...source, messageId: 0 }]) f.session.open(bad, f.host);
assert.equal(f.stats().requests, 0);
const candidate = { ...source };
f.session.open(candidate, f.host); candidate.messageId = 999;
f.session.open(source, f.host);
await tick();
assert.equal(f.stats().requests, 1, 'duplicate taps share one pending permission check');
assert.equal(ctx.openSheetCount(), 1);
f.resolve(allowed); await tick();
assert.equal(f.session.source.messageId, 22, 'source is frozen before asynchronous work');
assert.equal(f.session.source.threadRootId, 9);
assert.equal(f.session.removeCaption, false, 'media + text keeps the caption');
assert.equal(f.stats().playing, false);
assert.equal(ctx.dismissTopSheet(), true, 'back dismisses picker, not viewer');
assert.equal(f.session.source, null); assert.equal(f.stats().toggles, 2);
f.session.close(); assert.equal(f.stats().toggles, 2, 'sent + close is idempotent');

f = fixture(); f.session.open(source, f.host);
ctx.dismissTopSheet(); f.resolve(allowed); await tick();
assert.equal(f.session.source, null, 'back cancels an in-flight permission response');
assert.equal(f.stats().toggles, 0);
f = fixture(); f.session.open(source, f.host); f.stale(); f.resolve(allowed); await tick();
assert.equal(f.session.source, null, 'swipe/exit/account switch cannot open a stale picker');
assert.equal(ctx.openSheetCount(), 0);
for (const properties of [{ can_be_forwarded: false }, {}]) {
  f = fixture(); f.session.open(source, f.host); f.resolve(properties); await tick();
  assert.equal(f.stats().denied, 1); assert.equal(f.stats().toggles, 0);
  assert.equal(f.session.source, null); assert.equal(ctx.openSheetCount(), 0);
}
f = fixture(); f.session.open(source, f.host); f.reject(new Error('offline')); await tick();
assert.equal(f.stats().errors, 1); assert.equal(f.session.checking, false);
assert.equal(ctx.openSheetCount(), 0);
f.session.open(source, f.host); f.resolve(allowed); await tick();
assert.equal(f.stats().requests, 2, 'failed permission check can be retried');
f.session.close(false); assert.equal(f.stats().toggles, 1, 'teardown does not restart video');
f = fixture(false); f.session.open(source, f.host); f.resolve(allowed); await tick(); f.session.close();
assert.equal(f.stats().toggles, 0, 'previously paused video stays paused');
f = fixture(); f.session.open(source, f.host); f.resolve(allowed); await tick();
f.replacePlayer(); f.session.close(); assert.equal(f.stats().toggles, 1, 'do not resume a replaced player');
f = fixture(); f.host.choose = async () => true;
f.session.open(source, f.host); f.resolve(allowed); await tick();
assert.equal(f.session.removeCaption, true, 'media-only choice reaches picker');
f.session.close();
f = fixture(); f.host.choose = async () => null;
f.session.open(source, f.host); await tick();
assert.equal(f.stats().requests, 0, 'cancelling choice sends no permission or forward request');
assert.equal(f.session.source, null); assert.equal(ctx.openSheetCount(), 0);
f = fixture(); let choose;
f.host.choose = () => new Promise(resolve => { choose = resolve; });
f.session.open(source, f.host); f.stale(); choose(true); await tick();
assert.equal(f.stats().requests, 0, 'late menu choice after leaving media is ignored');
assert.equal(ctx.openSheetCount(), 0);

// Replay SDK-compiled integration methods rather than duplicating their logic.
const base = 'entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/';
function compiledMethods(file, className, names) {
  const ast = ts.createSourceFile(file, fs.readFileSync(base + file, 'utf8'), ts.ScriptTarget.Latest, true);
  const cls = ast.statements.find(n => ts.isClassDeclaration(n) && n.name.text === className);
  assert.ok(cls, className);
  const parts = names.map(name => {
    const member = cls.members.find(m => m.name?.getText(ast) === name); assert.ok(member, name);
    return member.getText(ast);
  });
  run(`globalThis.${className} = class { ${parts.join('\n')} };`);
}
compiledMethods('pages/main/DownloadPreviewPage.ts', 'DownloadPreviewPage', ['forwardSource']);
ctx.viewerIndexOf = id => id - 1;
const downloads = new ctx.DownloadPreviewPage();
downloads.items = [{ chatId: -500, messageId: 800 }, { chatId: 0, messageId: 0 }];
assert.equal(downloads.forwardSource(1).messageId, 800, 'synthetic viewer ID resolves to real source');
assert.equal(downloads.forwardSource(1).chatId, -500);
for (const id of [0, 2, 3]) assert.equal(downloads.forwardSource(id), null);
compiledMethods('pages/chat/MediaViewerOverlay.ts', 'MediaViewerOverlay', ['forwardSource', 'forwardCurrent', 'forwardPicker']);
const overlay = new ctx.MediaViewerOverlay();
let entry = { id: 22, sendState: 'none', text: 'caption' }, client = {};
let target = null, capturedHost = null;
ctx.getTdClient = () => client;
Object.assign(overlay, { chatId: -100, threadRootId: 9, viewerMsgId: 22, closing: false,
  disappearing: false, dismissY: 0, hopSlideX: 0, entry: () => entry,
  forwarding: { open: (s, h) => { target = s; capturedHost = h; } } });
overlay.forwardCurrent(21); assert.equal(target, null, 'offscreen cached page cannot forward');
overlay.forwardCurrent(22); assert.equal(target.messageId, 22); assert.ok(capturedHost.isCurrent());
client = {}; assert.equal(capturedHost.isCurrent(), false, 'account/client change rejects old response');
overlay.forwardCurrent(22); entry = null; assert.equal(capturedHost.isCurrent(), false, 'deleted source rejects old response');
entry = { id: 22, sendState: 'sending', text: '' }; assert.equal(overlay.forwardSource(), null);
entry.sendState = 'failed'; assert.equal(overlay.forwardSource(), null);
overlay.downloadsMode = true; overlay.resolveForwardSource = id => downloads.forwardSource(id);
overlay.viewerMsgId = 1; assert.equal(overlay.forwardSource().messageId, 800);
assert.equal(overlay.forwardSource().canRemoveCaption, true, 'download source may have a caption absent from local records');
overlay.isVideo = () => false;
for (const index of [0, 1, 2]) {
  overlay.getUIContext = () => ({ getPromptAction: () => ({ showActionMenu: async options => {
    assert.equal(options.buttons.length, 2); return { index };
  } }) });
  assert.equal(await capturedHost.choose(), index === 0 ? false : index === 1 ? true : null);
}
overlay.getUIContext = () => ({ getPromptAction: () => ({ showActionMenu: async () => { throw new Error('cancel'); } }) });
assert.equal(await capturedHost.choose(), null);

let pickerParams;
ctx.ForwardSheet = class { constructor(_parent, params) { pickerParams = params; } };
ctx.ViewPU = { create() {} };
overlay.observeComponentCreation2 = callback => callback(1, true);
for (const removeCaption of [false, true]) {
  overlay.forwarding.removeCaption = removeCaption;
  overlay.forwardPicker(overlay.forwardSource());
  assert.equal(pickerParams.defaultRemoveCaption, removeCaption, 'compiled viewer passes the selected mode');
}
assert.equal(pickerParams.canRemoveCaption, true);

run(fs.readFileSync(root + 'util/forwardMessagesRequest.ets', 'utf8'));
run(fs.readFileSync(root + 'util/forwardSendTask.ets', 'utf8'));
run(fs.readFileSync(root + 'util/shareFanout.ets', 'utf8'));
compiledMethods('pages/chat/ForwardSheet.ts', 'ForwardSheet',
  ['aboutToAppear', 'sendToSelected', 'toggleHideSource', 'toggleRemoveCaption']);
ctx.getFolderStore = () => ({ subscribe: () => () => {} });
ctx.requireForwardPermissions = async () => {};
ctx.showToast = () => {};
const sentRequests = [];
ctx.sendWithChatPermissions = async (_client, request) => {
  sentRequests.push(request); return { messages: [{ id: 900 }] };
};
for (const mode of ['viewer', 'with-caption', 'normal', 'keep-caption', 'keep-source']) {
  const sheet = new ctx.ForwardSheet();
  let finish;
  const finished = new Promise(resolve => { finish = resolve; });
  Object.assign(sheet, { defaultRemoveCaption: mode !== 'normal' && mode !== 'with-caption', canRemoveCaption: true,
    startTargetFilter() {}, bindChats() {}, loadChats() {}, close() {}, resultMessage: () => '',
    sourceChatId: -500, messageIds: [800], threadRootId: 0,
    selectedIds: [123], allowedTargetIds: [123], sendSeq: 0, sendTask: null,
    sending: false, optionsLocked: false, onSent: finish });
  sheet.aboutToAppear();
  if (mode === 'keep-caption') sheet.toggleRemoveCaption();
  if (mode === 'keep-source') sheet.toggleHideSource();
  sheet.sendToSelected(); await finished;
  const request = sentRequests.at(-1);
  assert.equal(request['@type'], 'forwardMessages');
  assert.equal(request.from_chat_id, -500);
  assert.deepEqual(Array.from(request.message_ids), [800]);
  assert.equal(request.remove_caption, mode === 'viewer', mode);
  assert.equal(request.send_copy, mode === 'viewer' || mode === 'keep-caption', mode);
}
console.log('PASS: viewer forwarding identity, permission denial/retry, stale async work, duplicate input, back, video pause/resume and real-source mapping.');
console.log('PASS: compiled choice menu/picker/send task respects media+text or media-only (including downloads), cancellation, stale choices, ordinary forwarding and user overrides.');
