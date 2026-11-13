// Real controller/session/receiver; only platform IO and channel delivery are mocked.
import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
const imported = await import(process.env.TYPESCRIPT_MODULE || 'typescript');
const ts = imported.default || imported;
const pending = [], cache = new Map(), thumbSubs = new Map(), thumbPaths = new Map(), avatarSubs = new Map();
let changes = 0, avatars = 0, infoReads = 0, nativeInvalidations = 0, densityQueries = 0;
const frames = [];
const ui = { vp2px: n => { densityQueries++; return n * 2; }, postFrameCallback: task => frames.push(task), postDelayedFrameCallback: task => frames.push(task) };
const key = r => `${r.path}:${r.width}:${r.height}:${r.opaque}`;
const fit = { Cover: 0, Contain: 1, Fill: 2 };
function subscribe(map, id, fn) { map.set(id, fn); return () => { if (map.get(id) === fn) map.delete(id); }; }
const ctx = vm.createContext({
  FrameCallback: class {}, ImageFit: fit, vp2pxUI: n => n * 2,
  DrawModifier: class { invalidate() { nativeInvalidations++; } },
  drawing: { SamplingOptions: class {}, FilterMode: { FILTER_MODE_LINEAR: 1 } },
  thumbPathFor: id => thumbPaths.get(id) || '',
  subscribeThumbPath: (id, fn) => subscribe(thumbSubs, id, fn),
  senderChannelKey: (id, user) => `${id}:${user}`, senderAvatarFor: () => '',
  subscribeSenderAvatar: (id, fn) => subscribe(avatarSubs, id, fn),
  cachedPixelMap: r => cache.get(key(r)), loadPixelMapSync: () => undefined,
  loadPixelMap: r => new Promise(resolve => pending.push({ r, resolve })), cancelPixelMap() {},
  retainPixelMap: h => h.refs++, releasePixelMap: h => h.refs--,
  pinPixelMap() {}, pinPixelMapBounded() {}, setTimeout, clearTimeout, logW() {}
});
function load(path, names = []) {
  const text = fs.readFileSync('entry/src/main/ets/' + path, 'utf8')
    .replace(/^import\s[\s\S]*?;\r?\n/gm, '').replace(/@(?:ObservedV2|Trace)\s*/g, '').replace(/\bexport /g, '');
  vm.runInContext(ts.transpileModule(text + names.map(n => `\nglobalThis.${n} = ${n};`).join(''),
    { compilerOptions: { target: ts.ScriptTarget.ES2020 } }).outputText, ctx);
}
for (const file of ['imageSwap', 'cachedImageSpec', 'CachedImageSession', 'liveThumbPath', 'miniThumbPlaceholder']) load(`util/${file}.ets`);
load('util/drawnImageRevision.ets'); load('util/drawnFrameBatch.ets'); load('util/oneShotFrameCallback.ets');
load('util/drawnStageMetrics.ets',['drawnStageMetrics','DrawnStage']);
load('util/drawnFrameQueue.ets'); load('util/drawnMediaActivation.ets', ['drawnMediaActivation']);
load('pages/chat/DrawnSlotActivation.ets');
load('pages/chat/DrawnSlotContent.ets');
load('pages/common/DrawnImageReceiver.ets'); load('pages/chat/DrawnMediaController.ets', ['DrawnMediaController']);
function handle(name) {
  return { refs: 1, width: 200, height: 160, pixelMap: { name, getImageInfoSync() {
    infoReads++; return { size: { width: 200, height: 160 } };
  } } };
}
function tile(id, path = '/' + id, mini = 'data:image/jpeg;base64,mini') {
  return { width: 100, height: 80, cell: { idx: id - 1, thumbFileId: id, thumbPath: path, mini } };
}
const group = { head: { senderId: 9, senderIsUser: true, senderAvatarPath: '/avatar' } };
const plan = tiles => ({ tiles, density: 2, avatar: { width: 0 } });
const flush = async () => { for (let i = 0; i < 8; i++) await Promise.resolve(); const ready = frames.splice(0); for (const frame of ready) frame.onFrame(0); };
const controller = new ctx.DrawnMediaController(() => changes++, () => avatars++);
const first = plan([tile(1), tile(2)]);
controller.prepare(ui, first, group);
assert.equal(densityQueries, 0, 'cold row forwards density to all slots and avatar without NAPI conversions');
assert.equal(changes, 0, 'image transitions never publish the avatar/row revision');
assert.deepEqual(Array.from(controller.slots, s=>s.state.revision), [1,1]);
assert.equal(pending.length, 2); assert.equal(thumbSubs.size, 2);
const p1 = handle('first'); pending[0].resolve(p1); await flush();
assert.equal(controller.slots[0].pixels, p1.pixelMap); assert.equal(infoReads, 0, 'forward metadata avoids a second native query');
assert.deepEqual(Array.from(controller.slots, s=>s.state.revision), [2,1], 'only the completed physical slot publishes');
const traceStages=[];
ctx.hiTraceMeter={HiTraceOutputLevel:{COMMERCIAL:3},startSyncTrace:(_level,name)=>traceStages.push(name),finishSyncTrace(){}};
ctx.drawnStageMetrics.setEnabled(true);ctx.drawnStageMetrics.reset();
const firstChanges = changes;
for (let i = 0; i < 1000; i++) controller.prepare(ui, first, group);
assert.equal(changes, firstChanges); assert.equal(pending.length, 2);
assert.equal(traceStages.length,0,'duplicate snapshots do not enter media preparation');
assert.match(ctx.drawnStageMetrics.summary(),/stage=PG\/media calls=0 skips=1000/);
controller.prepare(ui,{...first},group);assert.equal(traceStages.length,1,'changed plan remains eligible for binding');
controller.prepare(ui,first,{...group});assert.equal(traceStages.length,2,'new group still refreshes avatar metadata');
ctx.drawnStageMetrics.setEnabled(false);
// Distinct render data objects from selection/playback updates must not even
// enter image-session preparation when their image inputs are unchanged.
const session = controller.slots[0].session;
const originalUpdate = session.update;
let sessionUpdates = 0;
session.update = function (...args) { sessionUpdates++; return originalUpdate.apply(this, args); };
for (let i = 0; i < 1000; i++) {
  const changed = tile(1);
  changed.cell = { ...changed.cell, selected: i % 2 === 0, progress: i % 100,
    uploading: i % 3 === 0, playSlot: i % 2 === 1, autoplayMuted: i % 2 === 0 };
  controller.slots[0].bind(ui, changed);
}
assert.equal(sessionUpdates, 0, 'non-image changes skip session preparation');
controller.slots[0].bind(ui, { ...tile(1), width: 110 });
assert.equal(sessionUpdates, 1, 'geometry changes still update decode target');
controller.slots[0].bind(ui, tile(1));
assert.equal(sessionUpdates, 2);
session.update = originalUpdate;
const nativeBefore = nativeInvalidations;
const beforeUpgrade = pending.length;
const beforeUpgradeRevision=controller.slots[0].state.revision;
thumbSubs.get(1)('/upgrade'); assert.equal(pending.length, beforeUpgrade + 1);
const p2 = handle('upgrade'); pending.at(-1).resolve(p2); await flush();
assert.equal(controller.slots[0].pixels, p2.pixelMap);
assert.equal(changes, firstChanges, 'ready-to-ready upgrade invalidates bitmap only');
assert.equal(controller.slots[0].state.revision,beforeUpgradeRevision, 'ready-to-ready upgrade does not publish a structural slot revision');
assert.ok(nativeInvalidations > nativeBefore);
assert.equal(controller.slots[1].showMini(true), false);
assert.equal(controller.slots[1].showMini(false), true);
assert.equal(controller.slots[1].showMini(true), true, 'shown mini survives scrolling');
const oldListener = thumbSubs.get(1);
controller.prepare(ui, plan([tile(7)]), group);
assert.equal(thumbSubs.has(1), false); assert.equal(controller.slots.length, 1);
const count = pending.length;
oldListener('/stale'); assert.equal(pending.length, count);
// A -> B -> A: old A listener must not become valid just because ids match again.
controller.prepare(ui, plan([tile(1)]), group);
const currentCount = pending.length;
oldListener('/stale-a'); assert.equal(pending.length, currentCount);
assert.notEqual(controller.slots[0].path, '/stale-a');
const late = pending[1], latePixels = handle('late-removed'); late.resolve(latePixels); await flush();
assert.notEqual(controller.slots[0].pixels, latePixels.pixelMap);
controller.recycle(); assert.equal(thumbSubs.size, 0);
const beforeInactive = changes;
for (const request of pending.slice(3)) request.resolve(handle('late'));
await flush(); assert.equal(changes, beforeInactive);
controller.dispose(); assert.equal(p1.refs, 1); assert.equal(p2.refs, 1);
// Same sender identity, new initial path without a channel notification.
const av = new ctx.DrawnMediaController(() => changes++, () => avatars++);
const withAvatar = { tiles: [], avatar: { width: 38 } };
av.prepare(ui, withAvatar, group);
assert.equal(pending.at(-1).r.path, '/avatar');
av.prepare(ui, withAvatar, {head: {...group.head, senderAvatarPath: '/avatar-new'}});
assert.equal(pending.at(-1).r.path, '/avatar-new');
const oldAvatar = avatarSubs.values().next().value;
av.recycle(); av.prepare(ui, withAvatar, group);
const avCount = pending.length; oldAvatar('/stale-avatar'); assert.equal(pending.length, avCount);
av.dispose(); assert.equal(avatarSubs.size, 0);
console.log('PASS: 1000 unchanged binds, metadata forwarding, bitmap-only upgrades, batched placeholders, mini persistence, A/B/A stale callbacks, shrinking/recycle/dispose and avatar source updates.');

const singleMedia=new ctx.DrawnMediaController(()=>changes++,()=>{});
const singleTile={...tile(50,'/full-color'),opaque:false}, singlePlan=plan([singleTile]);
singleMedia.prepare(ui,singlePlan,group);assert.equal(pending.at(-1).r.opaque,false);
let binds=0;const imageSlot=singleMedia.slots[0], bind=imageSlot.bind.bind(imageSlot);
imageSlot.bind=(...args)=>{binds++;return bind(...args);};
for(let i=0;i<1000;i++)singleMedia.prepare(ui,singlePlan,group);
assert.equal(binds,0,'same tile array skips traversal/bind during non-image changes');
imageSlot.updateLocalPath('/local-poster');assert.equal(pending.at(-1).r.path,'/local-poster');
singleMedia.prepare(ui,plan([{...singleTile,opaque:true}]),group);assert.equal(pending.at(-1).r.opaque,true,'color format is a binding dependency');
singleMedia.recycle();const requests=pending.length;imageSlot.updateLocalPath('/stale');assert.equal(pending.length,requests);
singleMedia.dispose();
console.log('PASS: full-color single media, explicit opaque format change, 1000 stable tile arrays skip binds, local posters update pixels and reject detached writes.');

const localPosterMedia=new ctx.DrawnMediaController(()=>changes++,()=>{});
const noFile={...tile(1,''),cell:{...tile(1,'').cell,thumbFileId:0,chatId:9,messageId:100},opaque:false};
localPosterMedia.prepare(ui,plan([noFile]),group);localPosterMedia.slots[0].updateLocalPath('/generated-A');
localPosterMedia.prepare(ui,plan([{...noFile,width:120}]),group);assert.equal(localPosterMedia.slots[0].path,'/generated-A','resize keeps generated fileId=0 poster');
localPosterMedia.prepare(ui,plan([{...noFile,width:120,cell:{...noFile.cell,messageId:200}}]),group);
assert.equal(localPosterMedia.slots[0].path,'','same-size recycled fileId=0 tile must drop old message poster');
localPosterMedia.dispose();
console.log('PASS: local no-file poster survives geometry resize and never crosses recycled message identity.');

await flush();
// Nine asynchronous structural transitions in one frame publish once, not nine times.
let batched = 0;
const nine = new ctx.DrawnMediaController(() => batched++, () => {});
nine.prepare(ui, plan(Array.from({length:9},(_,i)=>tile(200+i,''))), group);
const initial = batched;
const revisions=Array.from(nine.slots,s=>s.state.revision);
for(let i=0;i<9;i++) thumbSubs.get(200+i)('/arrived-'+i);
assert.equal(batched, initial);
assert.equal(frames.length, 1, 'one callback for all nine images');
await flush(); assert.equal(batched, initial);
assert.deepEqual(Array.from(nine.slots,s=>s.state.revision),revisions.map(n=>n+1));
const onlyFirst=Array.from(nine.slots,s=>s.state.revision);
for(let i=0;i<100;i++)nine.markSlotDirty(nine.slots[0]);
assert.equal(frames.length,1);await flush();
assert.deepEqual(Array.from(nine.slots,s=>s.state.revision),onlyFirst.map((n,i)=>n+(i===0?1:0)), '100 repeated notifications publish one slot once');
// A recycled host rejects its old frame, even after becoming active again.
thumbSubs.get(200)(''); const oldFrames=frames.splice(0); nine.recycle();
nine.prepare(ui, plan([tile(300,'')]), group); const beforeOld=batched;
const beforeOldRevision=nine.slots[0].state.revision;
for(const frame of oldFrames)frame.onFrame(0);
assert.equal(batched,beforeOld); assert.equal(nine.slots[0].state.revision,beforeOldRevision); nine.dispose();
console.log('PASS: nine image transitions coalesce into one frame; recycled frame rejected.');
// Failed rebind cannot leave a previous snapshot marked prepared (A -> B -> A).
const guarded=new ctx.DrawnMediaController(()=>{},()=>{}),ga=plan([]),gb=plan([]);
let guardBinds=0,guardFail=false;
guarded.avatar.bind=()=>{guardBinds++;if(guardFail)throw Error('test avatar bind failure');};
guarded.prepare(ui,ga,group);guardFail=true;assert.throws(()=>guarded.prepare(ui,gb,group));
guardFail=false;guarded.prepare(ui,ga,group);assert.equal(guardBinds,3);
guarded.recycle();guarded.prepare(ui,ga,group);assert.equal(guardBinds,4,'recycled identical inputs bind again');
guarded.dispose();
console.log('PASS: media duplicate guard resets after failed A/B/A binding and recycling.');

// Production album staging: queue + session + receiver, cache and IO doubled.
const phased = new ctx.DrawnMediaController(()=>{},()=>{});
const albumTiles = Array.from({length:6},(_,i)=>({...tile(200+i),cell:{...tile(200+i).cell,chatId:1,messageId:200+i}}));
const readyPixel=handle('cache-hit');cache.set(key({path:'/200',width:200,height:160,opaque:true}),readyPixel);
const beginPending=pending.length;
phased.prepare(ui,plan(albumTiles),group,true);
assert.equal(pending.length,beginPending,'all cold decode submissions are deferred');
assert.equal(phased.slots[0].pixels,readyPixel.pixelMap,'warm bitmap is painted in the binding frame');
assert.equal(phased.slots[0].activated,true,'ready static pictures do not enqueue no-op activation');
assert.equal(phased.slots.filter(s=>s.activated).length,1);
const stableSlots=[...phased.slots];
await flush();
assert.ok(phased.slots.filter(s=>s.activated).length<=3,'global cap is at most two activations per frame');
for(let i=0;i<10;i++)await flush();
assert.equal(phased.slots.filter(s=>s.activated).length,6);
assert.equal(pending.length,beginPending+5);
assert.deepEqual([...phased.slots],stableSlots,'staging never replaces physical image slots');
// Cancel before frame, then reuse A -> B -> A; no old file request may escape.
phased.recycle();const oldCount=pending.length;
phased.prepare(ui,plan(albumTiles.map((t,i)=>({...t,cell:{...t.cell,messageId:300+i,thumbFileId:300+i,thumbPath:'/obsolete-'+i}}))),group,true);
phased.recycle();phased.prepare(ui,plan(albumTiles),group,true);
for(let i=0;i<10;i++)await flush();
assert.equal(pending.slice(oldCount).some(p=>p.r.path.startsWith('/obsolete')),false);
// Source change synchronously blanks old pixels before staged work starts.
const changedTiles=albumTiles.map((t,i)=>({...t,cell:{...t.cell,messageId:400+i,thumbFileId:400+i,thumbPath:'/next-'+i}}));
phased.prepare(ui,plan(changedTiles),group,true);
assert.equal(phased.slots[0].pixels,undefined,'no old message bitmap is retained while waiting');
const pausedCount=pending.length;phased.setVisible(false);
for(let i=0;i<10;i++)await flush();
assert.equal(pending.length,pausedCount,'leaving the viewport cancels pending work');
phased.setVisible(true);
for(let i=0;i<10;i++)await flush();
assert.equal(pending.length,pausedCount+6,'re-entering finishes the current attachment');
phased.recycle();phased.prepare(ui,plan(changedTiles),group,true);
phased.prepare(ui,plan([changedTiles[0]]),group,true);
const beforeShrink=pending.length;
for(let i=0;i<10;i++)await flush();
assert.equal(pending.length,beforeShrink+1,'removed slots cancel their queued decodes');
phased.dispose();await flush();
assert.match(ctx.drawnMediaActivation.summary(),/pending=0/);
// Playback and uploads retain their immediate lifecycle / progress indicators.
const playing=new ctx.DrawnMediaController(()=>{},()=>{});
playing.prepare(ui,plan([{...tile(501),cell:{...tile(501).cell,isPlaySlot:true}},
 {...tile(502),cell:{...tile(502).cell,uploading:true}}]),group,true);
assert.ok(playing.slots.every(s=>s.activated));playing.dispose();
console.log('PASS: staged cache-hit display, global batch bound, no cross-message pixels/requests, offscreen pause/resume, shrinking cancellation and immediate playback/uploads.');

// Switching a queued image to an immediate playback slot must restart the
// cancelled deferred decode even though its image spec itself is unchanged.
const switched=new ctx.DrawnMediaController(()=>{},()=>{}),switchTile={...tile(601),cell:{...tile(601).cell,chatId:1,messageId:601}};
switched.prepare(ui,plan([switchTile]),group,true);const switchCount=pending.length;
switched.prepare(ui,plan([{...switchTile,cell:{...switchTile.cell,isPlaySlot:true}}]),group,true);
assert.equal(pending.length,switchCount+1);assert.equal(switched.slots[0].activated,true);
for(let i=0;i<4;i++)await flush();assert.equal(pending.length,switchCount+1);switched.dispose();
const samePath=new ctx.DrawnMediaController(()=>{},()=>{}),fileless={...tile(0,'/same-file'),cell:{...tile(0,'/same-file').cell,chatId:1,messageId:701}};
samePath.prepare(ui,plan([fileless]),group,true);const sameCount=pending.length;
samePath.prepare(ui,plan([{...fileless,cell:{...fileless.cell,messageId:702}}]),group,true);
for(let i=0;i<4;i++)await flush();assert.equal(pending.length,sameCount+1);samePath.dispose();
console.log('PASS: queued-to-playing and identical-path/different-message changes cannot strand a deferred decode.');

const hitAlbum=new ctx.DrawnMediaController(()=>{},()=>{});
const hitTiles=Array.from({length:6},(_,i)=>{cache.set(key({path:'/cached-'+i,width:200,height:160,opaque:true}),handle('hit-'+i));return tile(800+i,'/cached-'+i);});
const framesBefore=frames.length,loadsBefore=pending.length;
hitAlbum.prepare(ui,plan(hitTiles),group,true);
assert.ok(hitAlbum.slots.every(s=>s.activated&&s.pixels));assert.equal(frames.length,framesBefore);assert.equal(pending.length,loadsBefore);
hitAlbum.dispose();
console.log('PASS: fully cached static album creates zero activation tasks or extra frame callbacks.');

// R18 device regression: readiness must belong to the physical slot, otherwise
// a cached video is removed and recreated on EVERY message reuse (10 -> 124).
const persistent=new ctx.DrawnMediaController(()=>{},()=>{});
const videoTiles=Array.from({length:6},(_,i)=>{const path='/stable-video-'+i;cache.set(key({path,width:200,height:160,opaque:true}),handle('stable'+i));return {...tile(900+i,path),cell:{...tile(900+i,path).cell,chatId:1,messageId:900+i,isVideo:true}};});
persistent.prepare(ui,plan(videoTiles),group,true);
assert.ok(persistent.slots.every(s=>!s.activated),'first native island activation remains staged');
for(let i=0;i<10;i++)await flush();assert.ok(persistent.slots.every(s=>s.activated));
const nativeSlots=[...persistent.slots],coldBefore=pending.length;
for(let reuse=0;reuse<1000;reuse++){
 persistent.recycle();
 persistent.prepare(ui,plan(videoTiles.map((t,i)=>({...t,cell:{...t.cell,messageId:10000+reuse*6+i}}))),group,true);
 assert.ok(persistent.slots.every(s=>s.activated),'warm native branches must never flip off');
 assert.deepEqual([...persistent.slots],nativeSlots);
 assert.ok(frames.length <= 1,'coalesced content publication has at most one posted callback');
 assert.ok(persistent.slots.every(s=>s.content.cell===undefined),'old video input is unavailable before publication');
}
assert.equal(pending.length,coldBefore);
persistent.recycle();
persistent.prepare(ui,plan(videoTiles.map((t,i)=>({...t,cell:{...t.cell,thumbFileId:20000+i,thumbPath:'/cold-video-'+i,messageId:20000+i}}))),group,true);
assert.ok(persistent.slots.every(s=>s.activated&&s.pixels===undefined),'keep native branch while clearing unrelated old poster');
assert.equal(pending.length,coldBefore,'a warm branch does not bypass cold-image scheduling');
for(let i=0;i<10;i++)await flush();assert.equal(pending.length,coldBefore+6);persistent.dispose();
console.log('PASS: 1000 cached video reuses preserve physical native branches with coalesced staged content; cold replacement posters still clear synchronously and load through the queue.');
