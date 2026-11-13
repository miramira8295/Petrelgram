// Real caches/channels and CompileArkTS lifecycle methods. View/native doubles
// verify work bounds and state delivery; no assertion here claims device ms.
import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
const ts=(await import(process.env.TYPESCRIPT_MODULE||'typescript')).default;
const root='entry/src/main/ets/',compiled='entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/'+root;
function load(ctx,path,names,rename){
 let source=fs.readFileSync(path,'utf8').replace(/^import\s[\s\S]*?;\r?\n/gm,'')
  .replace(/@(?:Require|Param|Local|Computed|Event|__ReusableV2_Inner_Decorator__)\s*/g,'')
  .replace(/@Monitor\([^)]*\)\s*/g,'').replace(/\bexport /g,'');
 if(rename)source=source.replace(/\bReusableMessageBubble\b/g,rename);
 vm.runInContext('(function(){'+ts.transpileModule(source+names.map(n=>`\nglobalThis.${n}=${n};`).join(''),
  {compilerOptions:{target:ts.ScriptTarget.ES2020}}).outputText+'})()',ctx,{filename:path});
}
let formats=0,resolutions=0,language='en',theme=1,failFormat=false,failColor=false;
class View {
 initParam(k,v){this[k]=v;}resetParam(k,v){this[k]=v;}finalizeConstruction(){}resetMonitorsOnReuse(){}
 resetComputed(k){if(k==='meta')this.firstMeta=this.meta;if(k==='shownGroup')this.firstGroup=this.shownGroup;}
 getUIContext(){return ui;}
}
const cacheCtx=vm.createContext({ViewV2:View,ViewPU:View,DrawnVideoDecoration:class{},a11yRuntimeState:{active:false},chatEnv:{langEpoch:1},
 decimal(n,d){formats++;if(failFormat)throw Error('format unavailable');return new Intl.NumberFormat(language,{minimumFractionDigits:d,maximumFractionDigits:d}).format(n);},
 str:(k,n)=>`${language}:${k}:${n}`,ColorMetrics:{resourceColor(c){resolutions++;if(failColor)throw Error('color unavailable');return{alpha:255,red:theme,green:typeof c==='number'?c:2,blue:3};}}});
load(cacheCtx,root+'util/formatFileSize.ets',['formatFileSize']);
load(cacheCtx,root+'util/mediaDuration.ets',['formatMediaDuration']);
load(cacheCtx,root+'pages/chat/DrawnVideoMeta.ets',['DrawnVideoMetaCache','drawnVideoMetaCache']);
load(cacheCtx,root+'pages/chat/DrawnTextLine.ets',['drawnColor']);
load(cacheCtx,root+'pages/chat/DrawnMediaColors.ets',['DrawnMediaColors']);
load(cacheCtx,compiled+'pages/chat/DrawnAlbumVideo.ts',['DrawnAlbumVideo']);
const meta=new cacheCtx.DrawnVideoMetaCache();
// Independent old-expression oracle, including zero/one-sided values and width threshold.
for(const bytes of [0,-1,532,1024,1048576,4294967296])for(const seconds of [0,1,65.9,3600])for(const wide of [false,true]){
 const size=bytes>0?cacheCtx.formatFileSize(bytes):'',duration=seconds>0?cacheCtx.formatMediaDuration(seconds):'';
 assert.equal(meta.prepare(bytes,seconds,wide,1),duration&&size&&wide?`${duration} · ${size}`:size||duration);
}
const hot=new cacheCtx.DrawnVideoMetaCache(),before=formats;
for(let i=0;i<1000;i++)assert.equal(hot.prepare(2048,65,true,1),'1:05 · en:size_kb:2.0');
assert.equal(formats-before,1,'1000 cached labels perform one Intl format');
language='de';assert.equal(hot.prepare(2048,65,true,2),'1:05 · de:size_kb:2,0');assert.equal(formats-before,2);
assert.equal(hot.labels.size,1,'language change drops prior language entries');
language='en';const cell={videoFileSize:2048,videoDuration:65,width:150};
const video=new cacheCtx.DrawnAlbumVideo(null,{cell,actions:{}});const initial=video.meta,afterInitial=formats;
for(let i=0;i<1000;i++){
 video.resetStateVarsOnReuse({cell:{...cell,width:112+(i%40)},actions:{}});
 assert.equal(video.firstMeta,initial);
}
assert.equal(formats,afterInitial,'real compiled reuse of video island hits shared metadata cache');
video.resetStateVarsOnReuse({cell:{...cell,width:111},actions:{}});assert.equal(video.firstMeta,'en:size_kb:2.0');
video.resetStateVarsOnReuse({cell:undefined,actions:{}});assert.equal(video.firstMeta,'');
video.resetStateVarsOnReuse({cell:{...cell,videoFileSize:4096,videoDuration:3600},actions:{}});assert.equal(video.firstMeta,'1:00:00 · en:size_kb:4.0');
cacheCtx.chatEnv.langEpoch=2;language='de';assert.equal(video.meta,'1:00:00 · de:size_kb:4,0');
// Fixed bounds, LRU retention, A-B-A and failed formatting must remain retryable.
const bounded=new cacheCtx.DrawnVideoMetaCache();bounded.prepare(2048,1,true,2);
for(let i=0;i<1000;i++){bounded.prepare(3000+i,1,true,2);bounded.prepare(2048,1,true,2);assert.ok(bounded.labels.size<=128);}
const warm=formats;bounded.prepare(2048,1,true,2);assert.equal(formats,warm);
failFormat=true;assert.throws(()=>bounded.prepare(999999,1,true,2));failFormat=false;
assert.ok(bounded.prepare(999999,1,true,2).includes('976,6'));assert.ok(bounded.labels.size<=128);
const colors=new cacheCtx.DrawnMediaColors(),resource=Object.freeze({id:42}),first=colors.resolve(resource,'1');Object.freeze(first);
const r0=resolutions;for(let i=0;i<1000;i++)assert.equal(colors.resolve(resource,'1'),first);assert.equal(resolutions,r0);
theme=2;assert.equal(colors.resolve(resource,'2').red,2);assert.equal(first.red,1,'old published colors stay immutable');
for(let i=0;i<1000;i++){assert.equal(colors.resolve(i,'2').green,i);assert.ok(colors.colors.size<=16);}
assert.equal(colors.resolve(resource,'2').red,2);theme=1;assert.equal(colors.resolve(resource,'1').red,1);
failColor=true;assert.throws(()=>colors.resolve('bad','1'));failColor=false;assert.equal(colors.resolve('bad','1').red,1);
console.log('PASS: real compiled video reuse formats once across 1000 resets; metadata/width/language changes, 128-label bound/LRU/failure retry; 1000 color hits resolve zero times, theme/A-B-A/16-color bound/immutable old paints.');

let snapshotReads=0,subscriptions=0,active=0,animations=0,pins=0,instant=false;
const ui={animateTo(options,action){animations++;action();options.onFinish?.();}};
const ctx=vm.createContext({ViewV2:View,ViewPU:View,probeHit(){},logW(){},thumbPathFor:()=>'',
 Curve:{EaseOut:1,FastOutSlowIn:2},KEY_POWER_SMOOTH_TRANSITIONS:'smooth',powerAnimationDuration:(_k,v)=>v,
 TRANSLATION_FADE_IN_MS:100,TRANSLATION_FADE_OUT_MS:80,TRANSLATION_FADE_LOW:.3,
 takeTranslationInstant:()=>instant,pinForTranslationGrowth:()=>pins++,setTimeout,clearTimeout});
for(const [f,n]of [['bubbleFocusChannel',['BubbleFocusChannel']],['rowLeaveChannel',['RowLeaveChannel']],['translationLanding',['translationLanded']],['rowIdentityGuard',['checkRenderedGroup']],['messageRowPresentationChannel',['messageRowPresentationFor','subscribeMessageRowPresentation','publishMessageRowPresentations']]])load(ctx,root+'util/'+f+'.ets',n);
const getSnapshot=ctx.messageRowPresentationFor,subscribe=ctx.subscribeMessageRowPresentation;
ctx.messageRowPresentationFor=(...a)=>{snapshotReads++;return getSnapshot(...a);};
ctx.subscribeMessageRowPresentation=(...a)=>{subscriptions++;active++;const off=subscribe(...a);return()=>{active--;off();};};
load(ctx,compiled+'pages/chat/ReusableMessageBubble.ts',['ReusableMessageBubble']);
const actions={bubbleFocus:new ctx.BubbleFocusChannel(),rowLeave:new ctx.RowLeaveChannel()};
function group(id,path=''){return{key:'k'+id,head:{id,rowId:id,contentType:'photo',photoPath:path,translatedText:'',translationHidden:false},photoPaths:[path],photoFailed:[false],memberIds:[id],photoFileIds:[id]};}
const ga=group(10),gb=group(10),sa=group(10,'/a'),sb=group(10,'/b');
ctx.publishMessageRowPresentations(1,[sa]);ctx.publishMessageRowPresentations(2,[sb]);
const pa={group:ga,data:{chatId:1},actions},pb={group:gb,data:{chatId:2},actions};
const row=new ctx.ReusableMessageBubble(null,pa);assert.equal(row.shownGroup,sa);assert.equal(subscriptions,0);
row.aboutToAppear();assert.equal(active,1);let writes=0,current=row.liveGroup;
Object.defineProperty(row,'liveGroup',{get:()=>current,set(v){if(current!==v){writes++;current=v;}}});
for(let i=0;i<1000;i++){
 const args=i%2?pa:pb,expected=i%2?sa:sb;row.aboutToRecycle();assert.equal(active,0);
 const reads=snapshotReads,w=writes;row.resetStateVarsOnReuse(args);
 assert.equal(snapshotReads-reads,1,'one snapshot lookup before computed');assert.equal(row.firstGroup,expected);
 assert.equal(writes-w,1,'switching rows publishes only the current snapshot');
 const after=writes;row.aboutToReuse();assert.equal(row.shownGroup,expected);assert.equal(writes,after,'unchanged channel attach does not write again');assert.equal(active,1);
}
// Same-row reuse keeps its snapshot and subscription; late arrivals still win.
const s0=subscriptions,w0=writes;row.resetStateVarsOnReuse(pa);row.aboutToReuse();assert.equal(subscriptions,s0);assert.equal(writes,w0);
row.aboutToRecycle();row.resetStateVarsOnReuse(pb);
const late=group(10,'/late');ctx.publishMessageRowPresentations(2,[late]);row.aboutToReuse();assert.equal(row.shownGroup,late);
const live=group(10,'/live');ctx.publishMessageRowPresentations(2,[live]);assert.equal(row.shownGroup,live);
actions.bubbleFocus.set(10,.5);actions.rowLeave.mark([10]);assert.equal(row.jumpFocus,.5);assert.equal(row.leaving,1);
// An already translated snapshot must not replay translation landing on mount.
row.aboutToRecycle();const translated={...live,head:{...live.head,translatedText:'translated'}};ctx.publishMessageRowPresentations(2,[translated]);
row.resetStateVarsOnReuse(pb);row.aboutToReuse();assert.equal(animations,0);assert.equal(pins,0);
const translated2={...translated,head:{...translated.head,translatedText:'new'}};ctx.publishMessageRowPresentations(2,[translated2]);assert.equal(row.shownGroup,translated2);assert.equal(animations,2);assert.equal(pins,1);
instant=true;const hidden={...translated2,head:{...translated2.head,translationHidden:true}};ctx.publishMessageRowPresentations(2,[hidden]);assert.equal(row.shownGroup,hidden);assert.equal(animations,2);assert.equal(pins,2);
row.aboutToRecycle();const missing={group:group(12345),data:{chatId:3},actions};row.resetStateVarsOnReuse(missing);assert.equal(row.firstGroup,missing.group);row.aboutToReuse();assert.equal(row.shownGroup,missing.group);row.aboutToDisappear();assert.equal(active,0);
// Optional actual pre-change compiler output demonstrates the eliminated write,
// without pretending this View double reproduces ArkUI frame scheduling.
if(process.env.BEFORE_PRESENTATION_SEED){
 load(ctx,process.env.BEFORE_PRESENTATION_SEED,['BeforeReusableMessageBubble'],'BeforeReusableMessageBubble');
 const old=new ctx.BeforeReusableMessageBubble(null,pa);old.aboutToAppear();old.aboutToRecycle();let oldWrites=0,oldValue=old.liveGroup;
 Object.defineProperty(old,'liveGroup',{get:()=>oldValue,set(v){if(oldValue!==v){oldWrites++;oldValue=v;}}});
 old.resetStateVarsOnReuse(pb);assert.equal(old.firstGroup,gb);old.aboutToReuse();assert.equal(oldWrites,2);old.aboutToRecycle();
}
console.log('PASS: actual outer constructor/reset seeds correct chat snapshot before computed; 1000 A/B reuses do one write instead of null+fill, fixed one reset lookup; same-row/absent/late/live updates, focus/delete, translation landing/instant mode and unsubscribe preserved.');
