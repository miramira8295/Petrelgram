// Real controller/session/receiver; only platform IO and channel delivery are mocked.
import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
const imported = await import(process.env.TYPESCRIPT_MODULE || 'typescript');
const ts = imported.default || imported;
const pending = [], cache = new Map(), thumbSubs = new Map(), thumbPaths = new Map(), avatarSubs = new Map();
let changes = 0, avatars = 0, infoReads = 0, nativeInvalidations = 0, densityQueries = 0;
const frames = [];
const ui = { vp2px: n => { densityQueries++; return n * 2; }, postFrameCallback: task => frames.push(task) };
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
    .replace(/^import\s[\s\S]*?;\r?\n/gm, '').replace(/\bexport /g, '');
  vm.runInContext(ts.transpileModule(text + names.map(n => `\nglobalThis.${n} = ${n};`).join(''),
    { compilerOptions: { target: ts.ScriptTarget.ES2020 } }).outputText, ctx);
}
for (const file of ['imageSwap', 'cachedImageSpec', 'CachedImageSession', 'liveThumbPath', 'miniThumbPlaceholder']) load(`util/${file}.ets`);
load('util/drawnFrameBatch.ets'); load('util/oneShotFrameCallback.ets');
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
assert.equal(changes, 1, 'batch multiple placeholder changes into one publication');
assert.equal(pending.length, 2); assert.equal(thumbSubs.size, 2);
const p1 = handle('first'); pending[0].resolve(p1); await flush();
assert.equal(controller.slots[0].pixels, p1.pixelMap); assert.equal(infoReads, 0, 'forward metadata avoids a second native query');
const firstChanges = changes;
for (let i = 0; i < 1000; i++) controller.prepare(ui, first, group);
assert.equal(changes, firstChanges); assert.equal(pending.length, 2);
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
thumbSubs.get(1)('/upgrade'); assert.equal(pending.length, beforeUpgrade + 1);
const p2 = handle('upgrade'); pending.at(-1).resolve(p2); await flush();
assert.equal(controller.slots[0].pixels, p2.pixelMap);
assert.equal(changes, firstChanges, 'ready-to-ready upgrade invalidates bitmap only');
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
for(let i=0;i<9;i++) thumbSubs.get(200+i)('/arrived-'+i);
assert.equal(batched, initial);
assert.equal(frames.length, 1, 'one callback for all nine images');
await flush(); assert.equal(batched, initial+1);
// A recycled host rejects its old frame, even after becoming active again.
thumbSubs.get(200)(''); const oldFrames=frames.splice(0); nine.recycle();
nine.prepare(ui, plan([tile(300,'')]), group); const beforeOld=batched;
for(const frame of oldFrames)frame.onFrame(0);
assert.equal(batched,beforeOld); nine.dispose();
console.log('PASS: nine image transitions coalesce into one frame; recycled frame rejected.');
