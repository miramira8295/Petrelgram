// Real painter + receiver/cache controller and compiled grid tree. Native raster
// calls are inspected here; pixel equivalence and milliseconds require a device.
import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
const imported = await import(process.env.TYPESCRIPT_MODULE || 'typescript'), ts = imported.default || imported;
const root = 'entry/src/main/ets/';
const frames = [], pending = [], cache = new Map(), thumbs = new Map();
let clips = 0, brushes = 0, info = 0;
const ctx = vm.createContext({
  FrameCallback: class {}, DrawModifier: class { invalidations = 0; invalidate() { this.invalidations++; } },
  ImageFit: { Cover: 0 }, vp2pxUI: n => n * 2,
  drawing: { CornerPos:{TOP_LEFT_POS:0,TOP_RIGHT_POS:1,BOTTOM_RIGHT_POS:2,BOTTOM_LEFT_POS:3}, RoundRect: class { constructor(rect, rx, ry) { clips++; Object.assign(this, {rect, rx, ry}); this.corners={}; } setCorner(pos,x,y){this.corners[pos]=[x,y];} },
    Brush: class { constructor() { brushes++; } setAntiAlias() {} setColor() {} },
    SamplingOptions: class {}, FilterMode: { FILTER_MODE_LINEAR: 1 }, ClipOp: { INTERSECT: 0 } },
  thumbPathFor: () => '', subscribeThumbPath: (id, fn) => { thumbs.set(id, fn); return () => thumbs.delete(id); },
  senderChannelKey: () => '', senderAvatarFor: () => '', subscribeSenderAvatar: () => () => {},
  cachedPixelMap: r => cache.get(`${r.path}:${r.width}:${r.height}:${r.opaque}`), loadPixelMapSync: () => undefined,
  loadPixelMap: r => new Promise(resolve => pending.push({r, resolve})), cancelPixelMap() {},
  retainPixelMap: h => h.refs++, releasePixelMap: h => h.refs--,
  pinPixelMap() {}, pinPixelMapBounded() {}, setTimeout, clearTimeout, logW() {}
});
function load(file, names = []) {
  const source = fs.readFileSync(root + file, 'utf8').replace(/^import\s[\s\S]*?;\r?\n/gm, '')
    .replace(/@(?:ObservedV2|Trace)\s*/g, '').replace(/\bexport /g, '');
  vm.runInContext(ts.transpileModule(source + names.map(n => `\nglobalThis.${n}=${n};`).join(''),
    {compilerOptions:{target:ts.ScriptTarget.ES2020}}).outputText, ctx, {filename:file});
}
for (const file of ['drawnFrameBatch','oneShotFrameCallback','imageSwap','cachedImageSpec','CachedImageSession',
  'liveThumbPath','miniThumbPlaceholder','drawnImageRevision','drawnStageMetrics','drawnFrameQueue','drawnMediaActivation']) load(`util/${file}.ets`);
load('pages/chat/DrawnSlotActivation.ets'); load('pages/chat/DrawnSlotContent.ets');
load('pages/common/DrawnImageReceiver.ets');
load('pages/chat/DrawnMediaController.ets', ['DrawnMediaController']);
load('pages/chat/DrawnAlbumCanvas.ets', ['DrawnAlbumCanvas']);
load('util/albumCanvasTransition.ets', ['withAlbumCanvasTransition','albumCanvasTransitionFor','withAlbumCanvasAnchor','takeAlbumCanvasAnchor']);
const ui = {postFrameCallback:f => frames.push(f),postDelayedFrameCallback:f => frames.push(f)};
const flush = () => { for (const f of frames.splice(0)) f.onFrame(0); };
const tile = (id, i = 0) => ({x:(i % 3)*102, y:Math.floor(i/3)*82, width:100, height:80,
  cell:{idx:i,chatId:1,messageId:id,thumbFileId:id,thumbPath:`/${id}`,mini:'',isVideo:false,isLive:false,uploading:false,failed:false}});
function pixels(id) { return {name:id,getImageInfoSync(){info++;throw Error('metadata already supplied');}}; }
function cached(id, path = `/${id}`) {
  const h = {refs:1,width:200,height:160,pixelMap:pixels(id)};
  cache.set(`${path}:200:160:true`,h); return h;
}
const group = {head:{senderId:0,senderIsUser:true,senderAvatarPath:''}};
const plan = tiles => ({tiles,nativeTiles:tiles,density:2,avatar:{width:0}});
const painter = new ctx.DrawnAlbumCanvas();
assert.equal(brushes,0,'text/single rows allocate no native brush or clip for this experiment');
const media = new ctx.DrawnMediaController(() => {}, () => {}, () => painter.imageChanged());
const a = Array.from({length:6},(_,i)=>tile(i+1,i));
const handles = a.map(t=>cached(t.cell.messageId));
media.prepare(ui,plan(a),group,true); painter.bind(ui,a,media.slots,2,true);
assert.equal(painter.state.ready,true); assert.equal(brushes,1); assert.equal(clips,6);
const records = [], translations = [], rounds = [];
let depth = 0;
const draw = {canvas:{save(){depth++;},restore(){depth--;},translate(x,y){translations.push([x,y]);},
  clipRoundRect(round){rounds.push(round);},attachBrush(){},drawRoundRect(){},detachBrush(){},
  drawImageRectWithSrc(p){records.push(p.name);}}};
painter.drawFront(draw); assert.deepEqual(records,[1,2,3,4,5,6]); assert.equal(depth,0);
assert.deepEqual(translations,[[0,0],[204,0],[408,0],[0,164],[204,164],[408,164]]);
assert.ok(rounds.every(r=>r.rx===8&&r.ry===8)); assert.equal(info,0);
const initialClips = clips;
for (let i=0;i<1000;i++) {
  const b = a.map(t=>({...t,cell:{...t.cell,messageId:t.cell.messageId+100}}));
  painter.bind(ui,b,media.slots,2,true); painter.drawFront(draw);
}
assert.equal(clips,initialClips,'same geometry survives 1000 message changes without native clip allocation');
assert.equal(painter.clips.length,6); assert.ok(handles.every(h=>h.refs===2),'canvas never retains/releases cache handles');
// Real session bitmap upgrade: readiness stays true and only the canvas is invalidated.
painter.bind(ui,a,media.slots,2,true); flush(); const revisions=media.slots.map(s=>s.state.revision);
const oldInvalidations=painter.invalidations;
const upgrades = a.map(t=>cached(t.cell.messageId+1000,`/upgrade${t.cell.messageId}`));
for(const t of a) thumbs.get(t.cell.thumbFileId)(`/upgrade${t.cell.messageId}`);
assert.equal(frames.length,1,'six bitmap upgrades coalesce into one canvas callback');
flush(); assert.equal(painter.invalidations,oldInvalidations+1); assert.equal(painter.state.ready,true);
assert.deepEqual(media.slots.map(s=>s.state.revision),revisions,'no per-image placeholder update for ready bitmap upgrades');
records.length=0;painter.drawFront(draw);assert.deepEqual(records,[1001,1002,1003,1004,1005,1006]);
assert.ok(handles.every(h=>h.refs===1));
// Cold/mixed/native/error/upload never remove progress or fallback hosts.
for(const flag of ['isVideo','isLive','uploading','failed']) {
  const b=a.map(t=>({...t,cell:{...t.cell}}));b[3].cell[flag]=true;
  painter.bind(ui,b,media.slots,2,true);assert.equal(painter.state.ready,false,flag);
}
painter.bind(ui,a,media.slots,2,false);assert.equal(painter.state.ready,false);
painter.bind(ui,a,media.slots,2,true);const slot=media.slots[0], saved=slot.pixels;
slot.pixels=undefined;painter.imageChanged();flush();assert.equal(painter.state.ready,false);
slot.pixels=saved;painter.imageChanged();flush();assert.equal(painter.state.ready,false);
const stableInvalidations=painter.invalidations;
for(let i=0;i<1000;i++)painter.imageChanged();
assert.equal(frames.length,0);assert.equal(painter.invalidations,stableInvalidations);
painter.bind(ui,a.map(t=>({...t,cell:{...t.cell}})),media.slots,3,true);
assert.equal(painter.state.ready,false,'geometry/density/new snapshot of same owner cannot rebuild the grid');
painter.reset();painter.bind(ui,a,media.slots,2,true);assert.equal(painter.state.ready,true);
const canDraw=slot.receiver.canDraw;slot.receiver.canDraw=()=>false;painter.imageChanged();flush();assert.equal(painter.state.ready,false);
slot.receiver.canDraw=canDraw;painter.imageChanged();flush();assert.equal(painter.state.ready,false);
const nextOwner=a.map(t=>({...t,cell:{...t.cell,messageId:t.cell.messageId+5000}}));
painter.bind(ui,nextOwner,media.slots,2,true);assert.equal(painter.state.ready,true,'new owner can select canvas again');
painter.imageChanged();const obsolete=frames.splice(0);painter.reset();const after=painter.invalidations;
for(const f of obsolete)f.onFrame(0);assert.equal(painter.invalidations,after);assert.equal(painter.slots,null);assert.equal(painter.tiles,null);
assert.equal(painter.state.ready,false);media.dispose();assert.ok(upgrades.every(h=>h.refs===1));
// Bounded 2..10 grids, density/size changes and rejection of oversized input.
for(let count=2;count<=10;count++) {
 const tiles=Array.from({length:count},(_,i)=>tile(i+1,i));
 const slots=tiles.map(t=>({path:'/x',pixels:{},receiver:{canDraw:()=>true,drawFront(){}}}));
 for(const density of [1,2,3]) {
  painter.bind(ui,tiles,slots,density,true);assert.equal(painter.state.ready,true);assert.equal(painter.clips.length,count);
  assert.equal(painter.clips[0].round.rx,4*density);
 }
 const narrow=tiles.map(t=>({...t,width:8,height:6}));painter.bind(ui,narrow,slots,2,true);assert.equal(painter.clips[0].round.rx,6);
}
painter.bind(ui,Array(11).fill(a[0]),Array(11).fill(slot),2,true);assert.equal(painter.state.ready,false);assert.ok(painter.clips.length<=10);
// Scoped transition cannot contaminate a later click, including exceptions/nesting.
assert.equal(ctx.albumCanvasTransitionFor(1),false);
ctx.withAlbumCanvasTransition(1,()=>{
 assert.equal(ctx.albumCanvasTransitionFor(1),true);assert.equal(ctx.albumCanvasTransitionFor(2),false);
 ctx.withAlbumCanvasTransition(2,()=>assert.equal(ctx.albumCanvasTransitionFor(2),true));
 assert.equal(ctx.albumCanvasTransitionFor(1),true);
});
assert.throws(()=>ctx.withAlbumCanvasTransition(1,()=>{throw Error('cancel');}));
assert.equal(ctx.albumCanvasTransitionFor(1),false);
console.log('PASS: single canvas 2–10 tiles, 4vp internal clips, 1000 geometry reuses, bounded ownership, six bitmap upgrades/one invalidation, fallback and stale-callback guards, scoped transition cleanup.');
// Actual viewer open method: fade is chosen after validation, and a subsequent
// ordinary thumbnail click restores the existing shared-element duration.
const viewerSource=ts.createSourceFile('ChatViewerSession.ets',fs.readFileSync(root+'pages/chat/ChatViewerSession.ets','utf8'),ts.ScriptTarget.Latest,true);
const viewerClass=viewerSource.statements.find(n=>ts.isClassDeclaration(n)&&n.name.text==='ChatViewerSession');
const open=viewerClass.members.find(n=>ts.isMethodDeclaration(n)&&n.name.getText(viewerSource)==='open');
vm.runInContext(ts.transpileModule(`class ViewerProbe {${open.getText(viewerSource)}};globalThis.ViewerProbe=ViewerProbe;`,{compilerOptions:{target:ts.ScriptTarget.ES2020}}).outputText,ctx);
const durations=[], opened=[];
ctx.mediaEntryIsPhoto=()=>true;ctx.mediaEntryIsVideo=()=>false;ctx.KEY_POWER_SMOOTH_TRANSITIONS='motion';ctx.Curve={Friction:0};
ctx.animateToUI=(options,fn)=>{durations.push(options.duration);fn();};
const viewer=new ctx.ViewerProbe();
Object.assign(viewer,{underlay:{fadeOnly:false,holdSource(release){this.release=release;}},host:{logOpen(){},entryById:()=>({photoPath:'/ready'}),effectDuration:(_key,n)=>n},onMediaTap:id=>opened.push(id)});
ctx.withAlbumCanvasTransition(7,()=>viewer.open(7));assert.equal(viewer.underlay.fadeOnly,true);assert.equal(durations.at(-1),160);
viewer.open(7);assert.equal(viewer.underlay.fadeOnly,false);assert.equal(durations.at(-1),300);
viewer.host.effectDuration=()=>0;ctx.withAlbumCanvasTransition(7,()=>viewer.open(7));assert.equal(durations.at(-1),0);
viewer.host.entryById=()=>null;const beforeOpen=opened.length;ctx.withAlbumCanvasTransition(8,()=>viewer.open(8));assert.equal(opened.length,beforeOpen);
assert.equal(ctx.albumCanvasTransitionFor(8),false);
console.log('PASS: real viewer open selects 160ms only for canvas actions; ordinary opens restore 300ms and reduced motion stays zero.');
// Cold arrival keeps the native per-image progress branch until ALL slots can
// draw, and keeps it for this owner even after completion; recycle cancels publication and late decode cannot repopulate the row.
painter.reset();flush();
const coldMedia=new ctx.DrawnMediaController(()=>{},()=>{},()=>painter.imageChanged());
const coldTiles=[tile(201,0),tile(202,1)], coldPlan=plan(coldTiles);
const startPending=pending.length;
coldMedia.prepare(ui,coldPlan,group);painter.bind(ui,coldTiles,coldMedia.slots,2,true);
assert.equal(painter.state.ready,false);assert.equal(pending.length,startPending+2);
const settle=async()=>{for(let i=0;i<8;i++)await Promise.resolve();flush();};
const firstCold={refs:1,width:200,height:160,pixelMap:pixels('cold1')};
pending[startPending].resolve(firstCold);await settle();assert.equal(painter.state.ready,false);
const secondCold={refs:1,width:200,height:160,pixelMap:pixels('cold2')};
pending[startPending+1].resolve(secondCold);await settle();assert.equal(painter.state.ready,false);
assert.equal(info,0);
// A path-only empty/nonempty transition must also reach the canvas readiness.
thumbs.get(201)('');await settle();assert.equal(painter.state.ready,false);
painter.reset();coldMedia.dispose();assert.equal(firstCold.refs,1);assert.equal(secondCold.refs,1);
const staleMedia=new ctx.DrawnMediaController(()=>{},()=>{},()=>painter.imageChanged());
const staleTiles=[tile(301,0),tile(302,1)], staleStart=pending.length;
staleMedia.prepare(ui,plan(staleTiles),group);painter.bind(ui,staleTiles,staleMedia.slots,2,true);
painter.reset();staleMedia.dispose();
const abandoned=[{refs:1,width:200,height:160,pixelMap:pixels('late1')},{refs:1,width:200,height:160,pixelMap:pixels('late2')}];
for(let i=0;i<2;i++)pending[staleStart+i].resolve(abandoned[i]);await settle();
assert.equal(painter.state.ready,false);assert.equal(painter.slots,null);assert.ok(abandoned.every(h=>h.refs===1));
console.log('PASS: partial cold decode preserves native progress; final decode keeps the grid stable, path-only loss keeps native mode, recycle releases owned references and never retains late decodes.');

// UI branch publication can lag one native paint behind ready=false/reset.
// The outgoing modifier must still cover every old cell; it must NOT keep an
// old bitmap after reset merely to hide a white frame.
const handoffTiles=[tile(401,0),tile(402,1)];
const handoffSlots=handoffTiles.map((t,i)=>({path:'/ready',pixels:{name:401+i},receiver:{canDraw:()=>true,
 drawFront(context){if(handoffSlots[i].pixels)context.canvas.drawImageRectWithSrc(handoffSlots[i].pixels);}}}));
const handoff=new ctx.DrawnAlbumCanvas();handoff.bind(ui,handoffTiles,handoffSlots,2,true);
let backgrounds=0;const shown=[];
const handoffDraw={canvas:{...draw.canvas,drawRoundRect(){backgrounds++;},drawImageRectWithSrc(p){shown.push(p.name);}}};
handoffSlots[0].pixels=undefined;handoff.imageChanged();flush();assert.equal(handoff.state.ready,false);
handoff.drawFront(handoffDraw);
assert.equal(backgrounds,2,'old canvas must cover the ready=false/native-placeholder handoff');
assert.deepEqual(shown,[402],'missing slot is a backdrop, valid same-message sibling remains drawable');
backgrounds=0;shown.length=0;handoff.reset();handoff.drawFront(handoffDraw);
assert.equal(backgrounds,2,'detached canvas still paints geometry-only backdrops until UI removes it');
assert.deepEqual(shown,[],'reset never retains or draws a previous message bitmap');
assert.equal(handoff.slots,null);assert.equal(handoff.tiles,null);
console.log('PASS: ready→not-ready and reset paint the outgoing geometry backdrop before branch commit, with zero old pixels after reset.');
// Sending -> sent retains the per-cell host for this physical message, even
// when upload completion changes tile snapshots/server message IDs.
const held=new ctx.DrawnAlbumCanvas(),readySlots=a.map(()=>({path:'/ready',pixels:{},receiver:{canDraw:()=>true}}));
const uploading=a.map(t=>({...t,cell:{...t.cell,uploading:true}}));
held.bind(ui,uploading,readySlots,2,true,true,'chat:stable-row');assert.equal(held.state.ready,false);
held.bind(ui,a,readySlots,2,true,false,'chat:stable-row');assert.equal(held.state.ready,false);
const confirmed=a.map(t=>({...t,cell:{...t.cell,messageId:t.cell.messageId+1000}}));
held.bind(ui,confirmed,readySlots,2,true,false,'chat:stable-row');assert.equal(held.state.ready,false);
held.reset();held.bind(ui,a,readySlots,2,true,false,'chat:next-row');assert.equal(held.state.ready,true);
console.log('PASS: upload completion/server IDs do not replace the mounted media host; recycled/new owner can use merged canvas.');
const localMedia=new ctx.DrawnMediaController(()=>{},()=>{});localMedia.prepare(ui,plan(a),group,true);
const bindCounts=Array(6).fill(0);localMedia.slots.forEach((s,i)=>{const bind=s.bind.bind(s);s.bind=(...args)=>{bindCounts[i]++;return bind(...args);};});
const changedTiles=a.slice();changedTiles[0]={...a[0],cell:{...a[0].cell,isPlaySlot:false}};changedTiles[1]={...a[1],cell:{...a[1].cell,isPlaySlot:true}};
localMedia.prepare(ui,plan(changedTiles),group,true);assert.deepEqual(bindCounts,[1,1,0,0,0,0]);
localMedia.prepare(ui,{...plan(changedTiles),density:3},group,true);assert.deepEqual(bindCounts,[2,2,1,1,1,1]);
localMedia.recycle();localMedia.prepare(ui,plan(changedTiles),group,true);assert.deepEqual(bindCounts,[3,3,2,2,2,2]);localMedia.dispose();
console.log('PASS: only changed tile identities enter binding; density changes and recycling still refresh every slot.');

// Per-corner geometry is shared with native anchor clipping. Native paths
// allocate at bind only, and react when edge membership changes at same size.
const corners={topLeft:0,topRight:4,bottomLeft:0,bottomRight:4};
const edgeTiles=a.map(t=>({...t,corners}));
const edgePainter=new ctx.DrawnAlbumCanvas();
const edgeSlots=edgeTiles.map(()=>({path:"/ready",pixels:{},receiver:{canDraw:()=>true}}));
edgePainter.bind(ui,edgeTiles,edgeSlots,2,true);
assert.equal(JSON.stringify(edgePainter.clips[0].round.corners),JSON.stringify({0:[0,0],1:[8,8],2:[8,8],3:[0,0]}));
const clipCount=clips;
for(let i=0;i<1000;i++)edgePainter.bind(ui,edgeTiles,edgeSlots,2,true);
assert.equal(clips,clipCount);
const moved=edgeTiles.map((t,i)=>i===0?{...t,corners:{...corners,topRight:0}}:t);
edgePainter.bind(ui,moved,edgeSlots,2,true);
assert.equal(clips,clipCount+1,'only a changed corner mask rebuilds its clip');
assert.deepEqual(edgePainter.clips[0].round.corners[1],[0,0]);
console.log('PASS: shared per-corner canvas geometry, stable binds allocate nothing, one changed edge rebuilds one clip.');
