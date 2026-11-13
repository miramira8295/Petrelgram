// Production layout/controller/painter tests. Native font shaping is a double;
// these are correctness/work-count tests, not a substitute for device pixels.
import assert from 'node:assert/strict';
import vm from 'node:vm';
import {ctx,load,root,ui,data,style,group,layoutCounters} from './test-drawn-text-row.mjs';
const metrics=ctx.drawnRouteMetrics,R=ctx.DrawnRouteReason;
metrics.reset();const tracker=new ctx.DrawnRouteTracker();
for(let i=0;i<10000;i++)tracker.record(1,10,R.Policy);
assert.match(metrics.summary(),/policy=1\b/);
tracker.record(1,10,R.Material);tracker.record(1,10,R.Drawn);tracker.record(1,10,R.Policy);
assert.match(metrics.summary(),/policy=2\b/);assert.match(metrics.summary(),/material=1\b/);
tracker.record(2,10,R.Policy);tracker.reset();tracker.record(2,10,R.Policy);
assert.match(metrics.summary(),/policy=4\b/);metrics.reset();tracker.record(2,10,R.Policy);
assert.match(metrics.summary(),/policy=1\b/,'clear epoch allows next observed route to be counted');
assert.equal(metrics.counts.length,11);assert.equal(Object.keys(tracker).length,4);
const trace=[];ctx.hiTraceMeter={HiTraceOutputLevel:{COMMERCIAL:3},startSyncTrace:(_level,name)=>trace.push(name),finishSyncTrace:()=>trace.push('end')};
ctx.drawnStageMetrics.setEnabled(true);metrics.reset();
for(let i=0;i<1000;i++)tracker.record(1,10,R.Policy);
assert.deepEqual(trace,['PG/route/policy','end']);ctx.drawnStageMetrics.setEnabled(false);
tracker.record(1,10,R.Drawn);assert.equal(trace.length,2,'disabled route telemetry must never enter native trace');

// Every early exit in the real compiled getter publishes a reason. The counter
// must not allocate layout engines or parse content just to identify a gate.
const makeRow=()=>Object.assign(Object.create(ctx.DrawnMessageRow.prototype),{layoutRetention:new ctx.DrawnLayoutRetention(),kind:'text',group:group('body'),data:{...data},
 env:{drawnEnabled:true,drawnText:true,drawnPlain:true,drawnRich:true,bubbleMaterialOn:false,langEpoch:1,appearanceEpoch:1,bubbleRadius:12,msgTextSize:16},
 a11y:{active:false},translation:null,role:'',views:'',failureLogged:false,textLayouts:{prepare:()=>({})},getUIContext:()=>ui});
ctx.logW=()=>{};
for(const [name,change]of [
 ['disabled',r=>r.env.drawnEnabled=false],['body-disabled',r=>r.env.drawnPlain=false],
 ['material',r=>r.env.bubbleMaterialOn=true],['a11y',r=>r.a11y.active=true],
 ['policy',r=>r.group.head.linkUrl='preview'],['translation',r=>r.translation={phase:'loading'}],
 ['chrome',r=>r.group.head.senderName='name\trole'],['layout-null',r=>r.textLayouts.prepare=()=>null],
 ['exception',r=>r.textLayouts.prepare=()=>{throw Error('injected');}]]){
 const row=makeRow();change(row);metrics.reset();assert.equal(row.plan,null,name);
 for(let i=0;i<1000;i++)assert.equal(row.plan,null);
 assert.match(metrics.summary(),new RegExp(`(?: |^)${name}=1(?: |\\n)`));
}
const row=makeRow();metrics.reset();assert.ok(row.plan);assert.match(metrics.summary(),/drawn=1\b/);
// Exercise RTL without relying on the host's process language.
vm.runInContext('globalThis.savedRtl=drawnTextUsesRtlLayout; drawnTextUsesRtlLayout=()=>true;',ctx);
metrics.reset();assert.equal(row.plan,null);assert.match(metrics.summary(),/rtl=1\b/);
vm.runInContext('drawnTextUsesRtlLayout=savedRtl;',ctx);
console.log('PASS: fixed 11 counters, 10000 repeated gates deduplicated, identity/recycle/clear epochs, compiled disabled/material/a11y/policy/body/translation/rtl/chrome/layout-null/exception/success reasons.');

for(const f of ['packAlbumRows','albumGeometryCache','albumCellRenderData'])load(root+'util/'+f+'.ets');
for(const f of ['DrawnAlbumGridLayout','DrawnSingleMediaGeometry','DrawnMediaLayout'])load(root+'pages/chat/'+f+'.ets',f==='DrawnMediaLayout'?['DrawnMediaLayouts']:[]);
function message(kind){const g=group('caption');if(kind!=='text'){
 Object.assign(g.head,{contentType:'photo',photoWidth:160,photoHeight:120,photoFileId:1,photoPath:'',photoMini:'',photoProgress:0,photoFailed:false});
 Object.assign(g,{caption:'caption',captionEntities:[],memberIds:kind==='album'?[10,11]:[10],photoRatios:[1,1],photoPaths:[],photoFileIds:[1,2],
 photoMinis:[],photoProgress:[],photoFailed:[],photoIsVideo:[],photoIsLive:[],videoFileIds:[],videoFileSizes:[],videoDurations:[],videoMimeTypes:[],inlineFileIds:[],inlineFileSizes:[]});}return g;}
for(const kind of ['text','album','single']){
 const cache=kind==='text'?new ctx.DrawnTextLayouts():new ctx.DrawnMediaLayouts(kind==='single');
 const g=message(kind),p=cache.prepare(ui,g,data,{...style,views:'11'}),before=layoutCounters();
 assert.ok(p);const originalLine=p.footer,shape=p.outline,body=p.caption,tiles=p.nativeTiles;
 for(let i=0;i<1000;i++){
  const label=i%2?'22':'33',next=cache.prepare(ui,g,data,{...style,views:label});
  assert.equal(next,p,`${kind}: same-size views retain entire plan`);
  assert.equal(next.outline,shape);assert.equal(next.caption,body);assert.equal(next.nativeTiles,tiles);
  assert.ok(next.footer.paragraph.content.startsWith(label),'foreground reads latest paragraph');
 }
 assert.notEqual(p.footer,originalLine);
 assert.equal(layoutCounters().bodyLayouts,before.bodyLayouts);assert.equal(layoutCounters().parseCalls,before.parseCalls);
 const oldWidth=p.footerWidth;
 const wider=cache.prepare(ui,g,data,{...style,views:'123456789'});
 assert.notEqual(wider,p);assert.notEqual(wider.footerWidth,oldWidth);assert.equal(wider.caption,body);
 assert.equal(p.footerWidth,oldWidth,'published geometry is immutable');
 // Same-size B footer is prepared before a later geometry step fails. A's paint
 // slot must remain unmodified until a successful matching-plan commit.
 const a=cache.prepare(ui,g,data,{...style,views:'11'}),line=a.footer;
 if(kind==='text'){
  const save=cache.corners.prepare;cache.corners.prepare=()=>{throw Error('geometry failure');};
  assert.throws(()=>cache.prepare(ui,{...g,head:{...g.head,senderId:99}},data,{...style,views:'22'}));cache.corners.prepare=save;
 }else{
  const save=cache.grids?.prepare;
  if(save){cache.grids.prepare=()=>{throw Error('grid failure');};assert.throws(()=>cache.prepare(ui,{...g},data,{...style,views:'22'}));cache.grids.prepare=save;}
 }
 assert.equal(a.footer,line);assert.ok(a.footer.paragraph.content.startsWith('11'));
 assert.equal(cache.prepare(ui,g,data,{...style,views:'11'}),a);
}
// Actual foreground binding gets a separate paint key, while background/avatar
// and the row plan keep their identity; repeated same key invalidates nothing.
let invalidations=0;
ctx.DrawModifier=class{invalidate(){invalidations++;}};
ctx.drawing.Brush=class{setAntiAlias(){}};ctx.drawing.Pen=class{setAntiAlias(){}setStrokeWidth(){}setCapStyle(){}};ctx.DrawnChromePainter=class{bind(){}};ctx.drawing.CapStyle={ROUND_CAP:1};
load(root+'pages/chat/DrawnBubblePainter.ets',['DrawnBubbleForeground']);
const fg=new ctx.DrawnBubbleForeground(),plan={density:2,statusSize:12};fg.bind(plan,'sent','11:1:0');const first=invalidations;
for(let i=0;i<1000;i++)fg.bind(plan,'sent','11:1:0');assert.equal(invalidations,first);
fg.bind(plan,'sent','22:1:0');assert.equal(invalidations,first+1);
console.log('PASS: text/single/album 1000 equal-size footer changes retain plan/body/grid/outline; larger footers change geometry; failed A-B-A cannot corrupt A; separate paint key invalidates only on content change.');
