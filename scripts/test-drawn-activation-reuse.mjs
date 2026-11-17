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
load('pages/chat/DrawnPreparedAlbum.ets', ['DrawnAlbumPublication']);

// Extract actual compiled methods, avoiding constructor/service initialization.
const filename = compiled + 'pages/chat/DrawnMessageRow.ts';
const source = ts.createSourceFile(filename, fs.readFileSync(filename, 'utf8'), ts.ScriptTarget.Latest, true);
const rowClass = source.statements.find(n => ts.isClassDeclaration(n) && n.name.text === 'DrawnMessageRow');
const methods = ['presentationReady', 'publicationActivated', 'publicationActivationEpoch', 'presentationChanged', 'rowGroup', 'rowData', 'rowContext', 'syncMedia', 'imageSlot', 'readImageSlot', 'mediaActivated', 'mediaOverlay', 'mediaTile'];
const selected = methods.map(name => {
  const member = rowClass.members.find(n => (ts.isMethodDeclaration(n) || ts.isGetAccessorDeclaration(n)) && n.name.getText(source) === name);
  assert.ok(member, `compiled row contains ${name}`);
  return member.getText(source).replace(/@Computed\s*/g,'').replace(/@Monitor\([^)]*\)\s*/g,'');
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
// Observe actual reads during compiled parent replay. Retained content objects
// are passed through, but their @Trace payload must only be read in the child.
let parentReplay=false,parentPayloadReads=0;
for(const slot of physicalSlots){
 for(const key of ['cell','width','height','thumbReady']) {
  let payload=slot.content[key];
  Object.defineProperty(slot.content,key,{get(){if(parentReplay)parentPayloadReads++;return payload;},set(v){payload=v;},configurable:true});
 }
}
parentReplay=true;for(let i=0;i<1000;i++)replay();parentReplay=false;
assert.equal(parentPayloadReads,0,'1000 parent replays do not subscribe to the published video payload');

for (const base of [200, 100, 300]) {
  media.recycle(); bind(tiles(base)); replay();
  assert.equal(constructions, 6, 'prepared A/B/A reuse does not create another video island');
  assert.equal(destructions, 0, 'reuse keeps the video branch mounted');
  assert.deepEqual([...media.slots], physicalSlots);
  assert.deepEqual([...children.values()], videoInstances);
  assert.ok([...children.values()].every(child => child.params.content.cell === undefined), 'old video content is cleared before staged publication');
  let published = 0;
  for (let frame = 0; frame < 12 && published < 6; frame++) {
    await flushFrame();
    const now = [...children.values()].filter(child => child.params.content.cell !== undefined).length;
    assert.ok(now - published <= 2, 'at most two physical slots publish new video input per frame');
    assert.ok(now >= published, 'published current content does not disappear');
    published = now;
    assert.equal(constructions, 6); assert.equal(destructions, 0);
  }
  assert.equal(published, 6, 'all staged content becomes available within a bounded number of frames');
  await drain();
  [...children.values()].forEach((child, i) => assert.equal(child.params.content.cell, row.nativeTiles[i].cell));
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
[...children.values()].forEach((child, i) => assert.equal(child.params.content.cell, row.nativeTiles[i].cell));
// Photo reuse releases the payload without destroying an already admitted shell.
const photos=tiles(550).map(t=>({...t,cell:{...t.cell,isVideo:false}}));
media.recycle();bind(photos);replay();await drain();
assert.equal(constructions,6);assert.equal(destructions,0);
assert.ok(media.slots.every(s=>s.content.cell===undefined && s.content.hostReady));
media.recycle();bind(tiles(560));replay();await drain();
assert.equal(constructions,6);assert.equal(destructions,0);
media.dispose();
console.log('PASS: real controller + compiled retained mediaTile keeps six video instances through A/B/A reuse, updates current cells, clears cold sources, defers decode and cancels obsolete queued requests.');

// Real controller under compiled row syncMedia: repeated Monitor callbacks and
// fresh getUIContext wrappers must not rebind six slots or restart activation.
const syncRow=new ctx.RowProbe();let uiReads=0,slotBinds=0;
const syncTiles=tiles(600);
const syncMedia=new ctx.DrawnMediaController(()=>{},()=>{});
Object.assign(syncRow,{active:true,presentationActive:true,kind:'album',group,data:{chatId:1},media:syncMedia,
 plan:{tiles:syncTiles,nativeTiles:syncTiles,density:2,avatar:{width:0}},
 albumCanvas:{bind(){},reset(){}},albumCanvasEnabled:true,getUIContext:()=>{uiReads++;return {...ui};}});
syncRow.syncMedia();
for(const slot of syncMedia.slots) {const bind=slot.bind.bind(slot);slot.bind=(...args)=>{slotBinds++;return bind(...args);};}
const queuedFrames=frames.length;
for(let i=0;i<1000;i++)syncRow.syncMedia();
assert.equal(uiReads,1);assert.equal(slotBinds,0);assert.equal(frames.length,queuedFrames);
syncMedia.recycle();syncRow.syncMedia();assert.equal(slotBinds,6,'recycle still rebinds current media');
syncRow.plan={...syncRow.plan,density:3};syncRow.syncMedia();assert.equal(slotBinds,12,'density change rebinds all affected slots');
syncMedia.dispose();await drain();
console.log('PASS: compiled row holds one UIContext; 1000 duplicate media monitors do zero slot binds, while recycle and density still rebind all six slots.');

// Exercise actual image-slot delivery, including the bind fast path and stale IO.
const thumbCallbacks=[];
ctx.subscribeThumbPath=(id,callback)=>{thumbCallbacks.push({id,callback});return()=>{};};
const presentationMedia=new ctx.DrawnMediaController(()=>{},()=>{});
function present(tile){presentationMedia.prepare(ui,{tiles:[tile],density:2,avatar:{width:0}}, {head:{}});}
let presentationTile=tiles(900,true)[0];presentationTile.cell.thumbPath='';
present(presentationTile);
const presentationSlot=presentationMedia.slots[0], presentation= presentationSlot.content;
assert.equal(presentation.width,100);assert.equal(presentation.height,80);assert.equal(presentation.thumbReady,false);
const late=thumbCallbacks.at(-1).callback;
late('/arrived');assert.equal(presentation.thumbReady,true);
late('');assert.equal(presentation.thumbReady,false);
presentationTile={...presentationTile,cell:{...presentationTile.cell,failed:true}};
present(presentationTile);assert.equal(presentation.thumbReady,true,'failure changes readiness even when bitmap bind exits early');
presentationTile={...presentationTile,cell:{...presentationTile.cell,failed:false}};
present(presentationTile);assert.equal(presentation.thumbReady,false);
presentationTile={...tiles(901,true)[0],width:140,height:90};presentationTile.cell.thumbPath='';
present(presentationTile);late('/stale');assert.equal(presentation.thumbReady,false);
assert.equal(presentation.width,140);assert.equal(presentation.height,90);
presentationSlot.updateLocalPath('/local');assert.equal(presentation.thumbReady,true);
presentationMedia.recycle();assert.equal(presentation.thumbReady,false);
thumbCallbacks.at(-1).callback('/after-recycle');assert.equal(presentation.thumbReady,false);
presentationMedia.dispose();
console.log('PASS: real slot late thumbnail, failure fast-path, resized reuse, local path and stale callback readiness.');

// Real controller/session/receiver: same-size A/B/A replacement must paint the
// current source, including direct retained-row updates without recycle hooks.
const sourceMedia=new ctx.DrawnMediaController(()=>{},()=>{});
const sourceTiles=[tiles(7100,true)[0],tiles(7200,true)[0]];
for(const t of sourceTiles)cache.set(key({path:t.cell.thumbPath,width:200,height:160,opaque:true}),handle(t.cell.messageId));
for(let i=0;i<1000;i++){
 if(i%3===0)sourceMedia.recycle();
 const tile=sourceTiles[i%2];
 sourceMedia.prepare(ui,{tiles:[tile],density:2,avatar:{width:0}},{head:{}});
 const slot=sourceMedia.slots[0], drawn=[];
 slot.receiver.drawFront({canvas:{drawImageRectWithSrc(pixel){drawn.push(pixel.name);}}});
 assert.deepEqual(drawn,[tile.cell.messageId]);
 assert.equal(slot.boundCell.messageId,tile.cell.messageId);
 assert.equal(slot.fileId,tile.cell.thumbFileId);
 assert.equal(slot.session.active,true);
 assert.equal(slot.session.heldReq.path,slot.session.spec.path);
 assert.equal(slot.session.heldKey,slot.session.spec.sourceKey);
}
sourceMedia.dispose();
console.log('PASS: 1000 same-size A/B/A swaps paint current file with and without recycle, current owner/source and actual drawn pixels agree.');

// Real-device ordering: reuse is delivered while presentationActive=false.
// Packet/input/layout updates precede the true Param update; that update can
// reseed Monitor without delivering presentationChanged. Bind on publication.
const retained=new ctx.RowProbe(), retainedMedia=new ctx.DrawnMediaController(()=>{},()=>{});
const publication=new ctx.DrawnAlbumPublication();
Object.assign(retained,{active:true,presentationActive:true,kind:'album',group,publication,media:retainedMedia,
 albumCanvas:{bind(){},reset(){}},albumCanvasEnabled:true,getUIContext:()=>ui,
 attach(){},syncDeleteCapture(){},channels:{detach(){}}});
for(let i=0;i<1000;i++) {
 const tile=sourceTiles[i%2];
 retained.active=false;retainedMedia.recycle();publication.deactivate();
 if(i>0){
  assert.notEqual(retainedMedia.slots[0].boundCell.messageId,tile.cell.messageId);
  assert.equal(retainedMedia.slots[0].fileId,-1);
  assert.equal(retainedMedia.slots[0].session.active,false);
  assert.notEqual(retainedMedia.slots[0].session.held,null);
 }
 // A late notification cannot restart a recycled row.
 retained.publicationActivated();assert.equal(retained.active,false);
 const oldEpoch=publication.activationEpoch;
 publication.activate();assert.equal(publication.activationEpoch,oldEpoch+1);
 publication.activate();assert.equal(publication.activationEpoch,oldEpoch+1,'duplicate appear/reuse is idempotent');
 retained.group={head:{...group.head,rowId:tile.cell.messageId}};
 retained.data={chatId:tile.cell.chatId};
 retained.presentationActive=false;
 retained.publicationActivated();assert.equal(retained.active,true);
 assert.equal(retainedMedia.active,false,'pending old packet stays unbound');
 retained.plan={tiles:[tile],nativeTiles:[tile],density:2,avatar:{width:0}};
 publication.packet={group:retained.group,data:retained.data};
 // No presentationChanged callback: reproduce the observed missing edge.
 retained.syncMedia();
 assert.equal(retained.presentationActive,false);
 assert.equal(retainedMedia.active,true,'published current packet binds before visibility Param catches up');
 retained.presentationActive=true;
 const slot=retainedMedia.slots[0],painted=[];
 slot.receiver.drawFront({canvas:{drawImageRectWithSrc(pixel){painted.push(pixel.name);}}});
 assert.deepEqual(painted,[tile.cell.messageId]);
 assert.equal(slot.boundCell.messageId,tile.cell.messageId);
 assert.equal(slot.fileId,tile.cell.thumbFileId);
 assert.equal(slot.session.active,true);
}
// Same packet/true presentation is also resumed by epoch, without a bool edge.
retained.active=false;retainedMedia.recycle();publication.deactivate();publication.activate();
retained.publicationActivated();assert.equal(retainedMedia.active,true);
retainedMedia.dispose();publication.deactivate();
console.log('PASS: 1000 publication-before-visibility cycles bind new pixels without presentationChanged; pending, stale, same-packet and duplicate callbacks covered.');
