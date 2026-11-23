// Replay actual compiler-output methods. Thumbnail state must never consume
// original-media open intent; stale owners and physical gestures stay guarded.
import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
const imported = await import(process.env.TYPESCRIPT_MODULE || 'typescript');
const ts = imported.default || imported;
const base = 'entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/pages/chat/';
const toasts = [];
const resourceNames = new Map(JSON.parse(fs.readFileSync(
  'entry/build/default/intermediates/res/default/ids_map/id_defined.json', 'utf8')).record
  .map(r => [Number(r.id), `app.${r.type}.${r.name}`]));
const ctx = vm.createContext({
  SourceType: { TouchScreen: 1, Mouse: 2 },
  mediaEntryIsPhoto: e => e.contentType === 'photo', mediaEntryIsVideo: e => e.contentType === 'video',
  showToast: text => toasts.push(typeof text === 'string' ? text : resourceNames.get(text.id)), $r: x => x, KEY_POWER_SMOOTH_TRANSITIONS: 'smooth',
  Curve: { Friction: 0 }, takeAlbumCanvasAnchor: () => null, albumCanvasTransitionFor: () => false,
  animateToUI: (_, fn) => fn(),
  albumRectContains: (r, x, y) => x >= r.x && x < r.x + r.width && y >= r.y && y < r.y + r.height,
  drawnAnimationPlaying: () => false, fileOpenMimeType: () => 'application/pdf', logE() {}
});
function methods(file, names) {
  const source = ts.createSourceFile(file, fs.readFileSync(base + file + '.ts', 'utf8'), ts.ScriptTarget.Latest, true);
  const cls = source.statements.find(n => ts.isClassDeclaration(n) && n.name.text === file);
  assert.ok(cls, file);
  const parts = names.map(name => {
    const m = cls.members.find(m => m.name?.getText(source) === name);
    assert.ok(m, name);
    return m.getText(source);
  });
  vm.runInContext(ts.transpileModule('globalThis.' + file + '=class {' + parts.join('\n') + '}',
    { compilerOptions: { target: ts.ScriptTarget.ES2020 } }).outputText, ctx);
  return ctx[file];
}
const Viewer = methods('ChatViewerSession', ['open']);
let cases = 0;
for (const contentType of ['photo', 'video']) for (const photoFailed of [false, true])
for (const photoPath of ['', '/thumb']) for (const original of ['local', 'remote', 'missing']) {
  const calls = [];
  const e = { contentType, photoFailed, photoPath, photoFileId: 0,
    photoFullPath: contentType === 'photo' && original === 'local' ? '/full' : '',
    photoFullFileId: contentType === 'photo' && original === 'remote' ? 22 : 0,
    videoPath: contentType === 'video' && original === 'local' ? '/video' : '',
    videoFileId: contentType === 'video' && original === 'remote' ? 33 : 0,
    videoFileSize: 100, videoFailed: false };
  const v = new Viewer();
  Object.assign(v, { viewerClosing: false, host: { logOpen() {}, entryById: () => e,
    store: () => ({ retryPhoto: () => calls.push('retry') }), effectDuration: () => 0 },
    underlay: { holdSource() {} }, onMediaTap: () => calls.push('open') });
  v.open(7);
  const available = original !== 'missing' || (contentType === 'photo' && photoPath !== '');
  assert.equal(calls.includes('open'), available, JSON.stringify(e));
  assert.equal(calls.includes('retry'), available && photoPath === '' && photoFailed);
  cases++;
}
// Closing, missing messages, locks and unknown stream size retain their behavior.
for (const mode of ['closing', 'missing', 'locked', 'unknown-size']) {
  const calls = [];
  const e = mode === 'missing' ? null : {contentType: mode === 'locked' ? 'paidMedia' : 'video',
    paidMediaLocked: true, videoFileId: 33, videoPath: '', videoFileSize: 0, photoPath: '', photoFailed: false};
  const v = new Viewer();
  Object.assign(v, {viewerClosing: mode === 'closing', host: {logOpen() {}, entryById: () => e,
    unlockPaidMedia: () => calls.push('unlock'), store: () => ({requestVideoForPlayback: () => calls.push('download')})},
    notePlaybackRequest: () => calls.push('intent'), onMediaTap: () => calls.push('open')});
  v.open(7);
  assert.deepEqual(calls, mode === 'locked' ? ['unlock'] : mode === 'unknown-size' ? ['download', 'intent'] : []);
}
const Row = methods('DrawnMessageRow', ['click']);
for (const kind of ['single', 'album']) for (const isVideo of [false, true]) {
  const out = [], tile = {x: 0, y: 0, width: 100, height: 100,
    cell: {failed: true, thumbFileId: 11, messageId: 7, idx: 0, isVideo}};
  const r = new Row();
  Object.assign(r, {claimed: false, plan: {avatar: {width: 0}, tiles: [tile]}, kind,
    rowGroup: {head: {rowId: 7, id: 7, photoPath: '', photoFullPath: '/full', videoPath: '/video'}},
    rowData: {chatId: 1, selectionActive: false}, touchRowId: 7, touchChatId: 1,
    albumCanvas: {state: {ready: false}}, actions: {onSpecialPhotoRetry: () => out.push('retry'),
      onMediaTap: () => out.push('open'), onToggleSelectedMessage: () => out.push('select'),
      onAnimationTap: () => out.push('animation')}, openCanvasMedia: () => out.push('canvas')});
  const event = {source: 1, x: 20, y: 20};
  r.click(event); assert.deepEqual(out.splice(0), ['open']);
  r.albumCanvas.state.ready = true; r.click(event); assert.deepEqual(out.splice(0), ['canvas']);
  r.rowData.selectionActive = true; r.click(event); assert.deepEqual(out.splice(0), ['select']);
  r.rowData.selectionActive = false; r.albumCanvas.state.ready = false;
  r.claimed = true; r.click(event); assert.equal(out.length, 0, 'claimed physical gesture stays blocked');
  r.click(event, 20, 20, true); assert.deepEqual(out.splice(0), ['open'], 'fresh semantic intent ignores prior gesture');
  assert.equal(r.claimed, true, 'semantic activation cannot unclaim the prior physical gesture');
  r.claimed = false; r.touchRowId = 99; r.click(event); assert.equal(out.length, 0, 'stale touch owner stays blocked');
  if (kind === 'single') {
    r.touchRowId = 7; r.rowGroup.head.isAnimation = true; r.click(event);
    assert.deepEqual(out.splice(0), ['animation'], 'GIF keeps its own playback action');
  }
}
const Accessibility = methods('DrawnRowAccessibility', ['activate']);
const semantic = new Accessibility(), currentTarget = {menu: false, x: 0, y: 0, width: 10, height: 10};
let activated = 0;
Object.assign(semantic, {targets: [currentTarget], onActivate: () => activated++});
semantic.activate({...currentTarget}, {}); assert.equal(activated, 0, 'stale virtual target rejected');
semantic.activate(currentTarget, {}); assert.equal(activated, 1);

const Surface = methods('DrawnSingleMediaSurface', ['clickCallback']);
const Grid = methods('DrawnAlbumGrid', ['clickCallback']);
for (const contentType of ['photo', 'video']) for (const album of [false, true]) {
  const out = [], tile = {key: '7:0', cell: {idx: 0, messageId: 7, failed: true, thumbFileId: 11, selectionActive: false}};
  const surface = album ? new Grid() : new Surface();
  Object.assign(surface, {bindIdentity: () => 1, generation: 1, touchedGeneration: 1, active: true,
    plan: {tiles: [tile]}, missing: () => true, msg: {id: 7, contentType, photoPath: '', photoFailed: true, photoFileId: 11},
    data: {chatId: 1, selectionActive: false}, context: {gestureClaimed: false},
    actions: {onSpecialPhotoRetry: () => out.push('retry'), onMediaTap: () => out.push('open'),
      onToggleSelectedMessage: () => out.push('select')}});
  const click = album ? surface.clickCallback(tile) : surface.clickCallback(), event = {source: 1};
  click(event); assert.deepEqual(out.splice(0), ['open']);
  surface.context.gestureClaimed = true; click(event); assert.equal(out.length, 0);
  surface.context.gestureClaimed = false; surface.data.selectionActive = true; tile.cell.selectionActive = true;
  click(event); assert.deepEqual(out.splice(0), ['select']);
  surface.generation++; click(event); assert.equal(out.length, 0, 'reused handler stays rejected');
}

const Transfers = methods('MediaSaveState', ['openDownloadedFile', 'resetFileOpenIntent', 'dispose']);
const pending = [];
ctx.openLocalFile = () => new Promise((resolve, reject) => pending.push({resolve, reject}));
const transfer = new Transfers();
Object.assign(transfer, {fileOpenGeneration: 0, fileOpenInFlightId: 0, host: {context: () => ({})},
  manualGalleryIds: new Set(), pendingGallerySaveProgress: null});
const file = {id: 7, videoPath: '/file', videoFileName: 'file.pdf', videoMimeType: 'application/pdf'};
const flush = async () => { await Promise.resolve(); await Promise.resolve(); };
transfer.openDownloadedFile({...file, videoPath: ''}); assert.equal(pending.length, 0);
transfer.openDownloadedFile(file); transfer.openDownloadedFile({...file, id: 8});
assert.equal(pending.length, 1, 'never launch another chooser while one request is outstanding');
assert.equal(toasts.at(-1), 'app.string.opening');
pending[0].resolve(true); await flush(); assert.equal(transfer.fileOpenInFlightId, 0);
for (const reset of ['resetFileOpenIntent', 'dispose']) for (const reject of [false, true]) {
  transfer.openDownloadedFile(file); const old = pending.at(-1);
  transfer[reset](); transfer.openDownloadedFile(file); const fresh = pending.at(-1);
  const count = toasts.length;
  if (reject) old.reject(new Error('old session')); else old.resolve(false);
  await flush(); assert.equal(transfer.fileOpenInFlightId, 7, 'same-id old completion cannot release a new owner');
  assert.equal(toasts.length, count, 'old session cannot show an error on the new page');
  fresh.resolve(true); await flush(); assert.equal(transfer.fileOpenInFlightId, 0);
}
for (const reject of [false, true]) {
  transfer.openDownloadedFile(file);
  if (reject) pending.at(-1).reject(new Error('current')); else pending.at(-1).resolve(false);
  await flush(); assert.equal(transfer.fileOpenInFlightId, 0);
  assert.equal(toasts.at(-1), reject ? 'app.string.cp_file_open_failed' : 'app.string.cp_no_app_for_file');
}
console.log(`PASS: ${cases} viewer availability cases; single/album/native and canvas media taps; semantic/stale target isolation; file busy feedback and cross-session completion guards.`);
