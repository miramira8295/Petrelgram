// Real channel stores/controller and real CompileArkTS constructor/reset order.
// The small View double models computed invalidation, not ArkUI scheduling or ms.
import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
const ts=(await import(process.env.TYPESCRIPT_MODULE||'typescript')).default;
const root='entry/src/main/ets/',compiled='entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/'+root;
let pins=0,prepares=0,reads=0,subscribes=0,activeSubscriptions=0;
const animated=new Set(),snapshots=[];
class View {
  initParam(k,v){this[k]=v;}
  resetParam(k,v){this[k]=v;}
  finalizeConstruction(){}
  resetComputed(k){
    if(k==='plan'){
      snapshots.push([this.group.head.id,this.views,this.role,this.translation,this.sendState,this.avatarAnimated]);
      this.cachedPlan=planGetter.call(this);this.planDirty=false;
    }
  }
  resetMonitorsOnReuse(){} // The tested first plan is computed before monitors.
  getUIContext(){return ui;}
}
const ui={};
const ctx=vm.createContext({ViewV2:View,ViewPU:View,
  chatEnv:{langEpoch:1,appearanceEpoch:1,bubbleMaterialOn:false,bubbleRadius:12,msgTextSize:16},
  a11yRuntimeState:{active:false},scrollPlaceholderState:{active:false},textMeasureEnvironment:{epoch:1},
  drawnAlbumEligible:()=>true,drawnTextRowEligible:()=>true,drawnSingleMediaEligible:()=>true,
  drawnChromeTextSupported:()=>true,drawnTextUsesRtlLayout:()=>false,drawnLiveSurface:()=>false,
  senderHasAnimatedPhoto:(id,isUser)=>{reads++;return isUser&&animated.has(id);},
  pinForTranslationGrowth:()=>{pins++;},logW:message=>{throw new Error(message);}});
function load(path,names){
 const source=fs.readFileSync(path,'utf8').replace(/^import\s[\s\S]*?;\r?\n/gm,'')
  .replace(/@(?:Require|Param|Local|Computed|Event)\s*/g,'').replace(/@Monitor\([^)]*\)\s*/g,'').replace(/\bexport /g,'');
 const code=source+names.map(n=>`\nglobalThis.${n}=${n};`).join('');
 vm.runInContext('(function(){'+ts.transpileModule(code,{compilerOptions:{target:ts.ScriptTarget.ES2020}}).outputText+'})()',ctx,{filename:path});
}
load(root+'util/sendStateChannel.ets',['sendStateFor','subscribeSendState','publishSendState']);
load(root+'util/viewCountChannel.ets',['viewCountLabelFor','subscribeViewCount','publishViewCount']);
load(root+'util/senderRoleChannel.ets',['senderRoleFor','senderRoleKey','subscribeSenderRole','publishSenderRole']);
load(root+'util/translationChannel.ets',['translationStatusFor','subscribeTranslationStatus','publishTranslating','publishTranslationFailed','clearTranslationStatus','pushTranslationStatusHold','flushHeldTranslationStatus']);
for(const name of ['sendStateFor','viewCountLabelFor','senderRoleFor','translationStatusFor']){
 const fn=ctx[name];ctx[name]=(...args)=>{reads++;return fn(...args);};
}
for(const name of ['subscribeSendState','subscribeViewCount','subscribeSenderRole','subscribeTranslationStatus']){
 const fn=ctx[name];ctx[name]=(...args)=>{subscribes++;activeSubscriptions++;const unsub=fn(...args);return()=>{activeSubscriptions--;unsub();};};
}
load(root+'util/drawnSenderRoleBinding.ets',['DrawnSenderRoleBinding']);
load(root+'pages/chat/DrawnBubbleController.ets',['DrawnBubbleController']);
load(root+'util/drawnRouteMetrics.ets',['DrawnRouteReason','DrawnRouteTracker','drawnRouteMetrics']);
load(root+'util/drawnStageMetrics.ets',['drawnStageMetrics','DrawnStage']);
load(root+'util/drawnMediaSlot.ets',['DrawnMediaSlots']);
// Native resources are doubles; initialization/channel behavior remains real.
for(const name of ['DrawnRowLeaveCapture','DrawnBubblePainter','DrawnBubbleAvatar','DrawnBubbleForeground',
 'AlbumCornerRadiiCache','MessageMenuTransitions','MessageDragGesture','DrawnMediaFrames','DrawnMediaAnchorPool','DrawnCanvasAttributes'])ctx[name]=class {reset(){}press(){}bind(){}invalidate(){}};
load(root+'pages/chat/DrawnPainterReserve.ets',['drawnPainterReserve']);
ctx.DrawnMediaController=class {prepare(){}recycle(){}dispose(){}};
for(const name of ['DrawnAlbumLayouts','DrawnSingleMediaLayouts','DrawnTextLayouts'])ctx[name]=class {
 prepare(_ui,_group,_data,style){prepares++;return{style,nativeTiles:[]};}
};
load(root+'pages/chat/DrawnLayoutWarmCache.ets',['takeDrawnWarmLayout']);
ctx.getTdClient ??= () => ctx; ctx.setTimeout ??= () => 0; ctx.clearTimeout ??= () => {};
load(root+'pages/chat/DrawnRecycledLayouts.ets',['DrawnLayoutRetention','takeDrawnRecycledLayout','drawnRecycledLayouts']);
load(compiled+'pages/chat/DrawnMessageRow.ts',['DrawnMessageRow']);
const planGetter=Object.getOwnPropertyDescriptor(ctx.DrawnMessageRow.prototype,'plan').get;
const parameters=(id,chatId=1,extra={},data={})=>({kind:'album',group:{caption:'',memberIds:[id],showSenderName:true,head:{text:'',replyText:'',senderName:'',forwardFrom:'',id,rowId:id,senderId:id+1000,senderIsUser:true,senderTag:'',sendState:'sent',isOutgoing:false,...extra}},data:{chatId,isGroup:true,...data},actions:{}});
function observe(row){
 // Preserve real getters and callbacks; only model the state invalidation that
 // attach would cause if the reset initializers still supplied blank values.
 row.planDirty=true;
 for(const name of ['views','role','translation','sendState','avatarAnimated']){
  let value=row[name];Object.defineProperty(row,name,{get:()=>value,set(next){if(value!==next){value=next;if(['views','role','translation'].includes(name))row.planDirty=true;}}});
 }
 Object.defineProperty(row,'plan',{get(){if(this.planDirty){this.cachedPlan=planGetter.call(this);this.planDirty=false;}return this.cachedPlan;}});
 return row;
}
const pa=parameters(1),pb=parameters(2,2);
ctx.publishSendState(1,'read');ctx.publishSendState(2,'sending');
ctx.publishViewCount(1,1,1234);ctx.publishViewCount(2,2,6789);
ctx.publishSenderRole('1:1001','admin A');ctx.publishSenderRole('2:1002','admin B');animated.add(1002);
const row=observe(new ctx.DrawnMessageRow(null,pa));
assert.equal(row.views,'1.2K');assert.equal(row.role,'admin A');assert.equal(row.sendState,'read');
assert.equal(subscribes,0,'constructor snapshots never subscribe');
row.aboutToAppear();assert.equal(prepares,1);assert.equal(activeSubscriptions,4);assert.equal(pins,0);
for(const kind of ['text','single','album'])for(const params of [pb,pa,pb]){
 row.aboutToRecycle();const before=prepares,beforeSubs=subscribes,beforeReads=reads;
 row.resetStateVarsOnReuse({...params,kind});
 const expected=params===pa?[1,'1.2K','admin A',null,'read',false]:[2,'6.7K','admin B',null,'sending',true];
 assert.deepEqual(snapshots.at(-1),expected);
 assert.equal(reads-beforeReads,5,'fixed five store reads independent of row kind/album size');
 assert.equal(subscribes,beforeSubs,'reset never subscribes');
 assert.equal(prepares,before+1,'first computed plan sees current metadata');
 row.aboutToReuse();assert.equal(prepares,before+1,'channel reseed must not cause another prepare');
 assert.equal(activeSubscriptions,4);
}
// Empty, outgoing, hidden-name and embedded tags use the exact controller rules.
for(const [params,label,expectedSubs]of [
 [parameters(3),'',4],[parameters(3,1,{senderTag:'embedded'}),'embedded',3],
 [parameters(2,2,{isOutgoing:true}),'',3],
 [{...pb,group:{...pb.group,showSenderName:false}},'',3],
 [parameters(2,2,{}, {isGroup:false}),'',3]]){
 row.aboutToRecycle();row.resetStateVarsOnReuse(params);assert.equal(row.role,label);
 const before=prepares;row.aboutToReuse();assert.equal(row.role,label);assert.equal(prepares,before);assert.equal(activeSubscriptions,expectedSubs);
}
// Initial translation falls back immediately without a spurious growth pin.
for(const failed of [false,true]){
 if(failed)ctx.publishTranslationFailed(1,'network');else ctx.publishTranslating(1);
 row.aboutToRecycle();const before=prepares,beforePins=pins;
 row.resetStateVarsOnReuse(pa);assert.equal(row.plan,null);assert.equal(prepares,before);
 assert.equal(row.translation.phase,failed?'failed':'loading');row.aboutToReuse();assert.equal(pins,beforePins);
 ctx.clearTranslationStatus(1);assert.equal(row.translation,null);assert.equal(pins,beforePins+1);assert.notEqual(row.plan,null);
}
// State arriving after the snapshot is not lost; later updates remain subscribed.
row.aboutToRecycle();row.resetStateVarsOnReuse(pb);
ctx.publishViewCount(2,2,9876);ctx.publishSendState(2,'read');ctx.publishSenderRole('2:1002','new role');animated.delete(1002);
const before=prepares;row.aboutToReuse();assert.equal(row.views,'9.8K');assert.equal(row.role,'new role');assert.equal(row.sendState,'read');assert.equal(row.avatarAnimated,false);assert.equal(prepares,before+1);
ctx.publishViewCount(2,2,12000);assert.equal(row.views,'12K');ctx.publishSenderRole('2:1002','latest');assert.equal(row.role,'latest');
// Translation hold still defers existing row growth, but a newly reused row
// reads the stored final state without creating then tearing down a drawn plan.
const release=ctx.pushTranslationStatusHold(()=>true),beforePins=pins;
ctx.publishTranslating(2);assert.equal(row.translation,null);
row.aboutToRecycle();row.resetStateVarsOnReuse(pb);assert.equal(row.plan,null);row.aboutToReuse();assert.equal(pins,beforePins);
release();assert.equal(pins,beforePins);ctx.clearTranslationStatus(2);assert.equal(pins,beforePins+1);
// Repeated reuse cannot accumulate subscriptions or scale reads with history.
let maxReads=0;
for(let i=0;i<1000;i++){
 row.aboutToRecycle();const r=reads,p=prepares;
 row.resetStateVarsOnReuse(i%2?pa:pb);maxReads=Math.max(maxReads,reads-r);
 row.aboutToReuse();assert.equal(prepares,p+1);assert.equal(activeSubscriptions,4);
}
assert.equal(maxReads,5);row.aboutToRecycle();assert.equal(activeSubscriptions,0);
assert.equal(ctx.drawnPainterReserve.hits + ctx.drawnPainterReserve.misses, 3,
 '1000 compiled reuse resets keep the original three painter owners, without reacquiring resources');
console.log('PASS: compiled constructor/reset seed current state before plan; text/single/album A-B-A, role visibility/tags, sends/views/animated avatar, translation fallback/hold/late updates; 1000 reuse cycles keep five snapshot reads and zero duplicate layout on unchanged channels.');
