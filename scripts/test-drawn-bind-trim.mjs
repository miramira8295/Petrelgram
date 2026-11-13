// Production bounded snapshots and real compiled lifecycle; no host timing claims.
import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
const ts=(await import(process.env.TYPESCRIPT_MODULE||'typescript')).default;
const root='entry/src/main/ets/';
const trace=[];
const ctx=vm.createContext({hiTraceMeter:{HiTraceOutputLevel:{COMMERCIAL:3},
 startSyncTrace:(level,name)=>trace.push(['start',level,name]),finishSyncTrace:level=>trace.push(['end',level])},
 DrawModifier:class{invalidate(){}},drawing:{Brush:class{setAntiAlias(){}setColor(){}setMaskFilter(){}},Pen:class{setAntiAlias(){}setStrokeWidth(){}setCapStyle(){}},
 MaskFilter:{createBlurMaskFilter:()=>({})},BlurType:{NORMAL:0},CapStyle:{ROUND_CAP:1},RoundRect:class{}},DrawnChromePainter:class{bind(){}}});
function load(file,names){const src=fs.readFileSync(root+file,'utf8').replace(/^import\s[\s\S]*?;\r?\n/gm,'').replace(/\bexport /g,'');
 vm.runInContext(ts.transpileModule(src+names.map(n=>`\nglobalThis.${n}=${n};`).join(''),{compilerOptions:{target:ts.ScriptTarget.ES2020}}).outputText,ctx);}
load('util/drawnStageMetrics.ets',['DrawnStageMetrics','drawnStageMetrics','DrawnStage']);
load('util/thumbBackdrop.ets',[]);load('pages/chat/DrawnMediaFrames.ets',['DrawnMediaFrames']);
load('pages/chat/DrawnBubblePainter.ets',['DrawnBubblePainter','DrawnBubbleAvatar','DrawnBubbleForeground']);
const metrics=ctx.drawnStageMetrics,S=ctx.DrawnStage;
for(let i=0;i<10000;i++){metrics.end(metrics.begin(S.Media));metrics.skip(S.Media);}
assert.equal(trace.length,0);assert.equal(metrics.summary(),'','disabled stage diagnostics do no trace/counter work');
metrics.setEnabled(true);const outer=metrics.begin(S.Layout),inner=metrics.begin(S.Media);metrics.end(inner);
metrics.setEnabled(false);metrics.end(outer);assert.deepEqual(trace.map(t=>t[0]),['start','start','end','end']);
metrics.reset();assert.equal(metrics.summary(),'');trace.length=0;
const cache=new ctx.DrawnMediaFrames();
const tiles=Array.from({length:9},(_,i)=>({x:i*100,y:0,width:100,height:90,cell:{isVideo:false,messageId:i+1}}));
const first=cache.prepare(tiles,10,false),json=JSON.stringify(first);
for(let i=0;i<2000;i++){
 const fresh=tiles.map(t=>({...t,cell:{...t.cell,thumbPath:'/new'+i,progress:i%100,selected:!!(i%2),isPlaySlot:!!(i%2)}}));
 assert.equal(cache.prepare(fresh,10,false),first,'media-only snapshots cannot publish anchor attributes');
}
let next=cache.prepare(tiles.map((t,i)=>i===3?{...t,width:101}:t),10,false);
assert.notEqual(next,first);assert.notEqual(next[3],first[3]);assert.equal(next[2],first[2]);assert.equal(JSON.stringify(first),json);
assert.equal(cache.prepare(tiles,10,false)[3].width,100);
next=cache.prepare(tiles,11,false);assert.equal(next[0].transition,'media_11_1');
const video=tiles.map((t,i)=>i===0?{...t,cell:{...t.cell,isVideo:true}}:t);
next=cache.prepare(video,11,false);assert.equal(next[0].transition,'');assert.equal(next[0].backdrop,'#AEB6C0');
next=cache.prepare(video,11,true);assert.equal(next[0].transition,'media_11_1');assert.equal(next[0].radius,0);
assert.equal(cache.prepare(tiles.slice(0,2),10,false).length,2);assert.equal(first.length,9);assert.equal(cache.prepare([],10,false).length,0);
assert.equal(cache.prepare(tiles,10,false)[8].transition,'media_10_9');
// Actual painters skip stable bindings; status updates don't invalidate background/avatar.
metrics.setEnabled(true);metrics.reset();trace.length=0;
const bg=new ctx.DrawnBubblePainter(),fg=new ctx.DrawnBubbleForeground(),av=new ctx.DrawnBubbleAvatar();
const plan={density:2,statusSize:12,avatar:{width:38}},media={};
bg.bind(plan,true);fg.bind(plan,'sent');av.bind(plan,media);
for(let i=0;i<1000;i++){bg.bind(plan,true);fg.bind(plan,'sent');av.bind(plan,media);}
assert.equal(trace.filter(t=>t[0]==='start').length,3);
assert.match(metrics.summary(),/stage=PG\/background-bind calls=1 skips=1000/);
fg.bind(plan,'read');assert.equal(trace.filter(t=>t[0]==='start').length,4);
metrics.reset();trace.length=0;
bg.invalidate=()=>{throw Error('test painter failure');};assert.throws(()=>bg.bind(plan,false));
assert.deepEqual(trace.map(t=>t[0]),['start','end'],'finally closes a failed business stage');

const shared=await import('./test-drawn-text-row.mjs');
const c=shared.ctx;
let attachCalls=0,fail=false;
c.senderHasAnimatedPhoto=()=>false;
const row=Object.assign(Object.create(c.DrawnMessageRow.prototype),{layoutRetention:new c.DrawnLayoutRetention(),
 active:false,attachedGroup:null,attachedData:null,attachedEnvironment:'',inputIdentity:'',
 group:{head:{rowId:7,id:7,senderId:8,isOutgoing:false},showSenderName:true},data:{chatId:2,isGroup:true},
 env:{langEpoch:0,bubbleMaterialOn:false},foreground:{press(){}},
 channels:{attach(){attachCalls++;if(fail)throw Error('test attachment failure');},detach(){}},
 media:{prepare(){},recycle(){}},leaveCapture:{reset(){},bind(){}},dragGesture:{reset(){}},getUIContext:()=>({})});
Object.defineProperty(row,'plan',{value:{},configurable:true});
row.syncDeleteCapture=()=>{};
row.aboutToAppear();for(let i=0;i<1000;i++){row.inputChanged();row.layoutChanged();}assert.equal(attachCalls,1);
row.group={...row.group};row.inputChanged();assert.equal(attachCalls,2,'new group still reseeds channels');
row.env.langEpoch++;row.roleEnvironmentChanged();assert.equal(attachCalls,3,'language refresh cannot hit attachment guard');
row.aboutToRecycle();row.inputChanged();assert.equal(attachCalls,3,'inactive row never resubscribes');
row.aboutToReuse();assert.equal(attachCalls,4,'same snapshots must reattach after recycle');
row.data={...row.data};fail=true;assert.throws(()=>row.inputChanged());fail=false;row.inputChanged();assert.equal(attachCalls,6,'failed attachment is not cached');
const previousData=row.data;row.data={...row.data};fail=true;assert.throws(()=>row.inputChanged());
row.data=previousData;fail=false;row.inputChanged();assert.equal(attachCalls,8,'A/B-failure/A must restore attachment');
console.log('PASS: 2000 media-only updates reuse native frames; resize/transition/video/shrink invalidate; duplicate lifecycle attachment skips, recycle/environment/retry remain live; trace disabled/balanced/painter stages.');
