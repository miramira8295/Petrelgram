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
  .replace(/@(?:Require|Param|Local|Computed|Event|ObservedV2|Trace)\s*/g,'').replace(/@Monitor\([^)]*\)\s*/g,'').replace(/\bexport /g,'');
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
ctx.DrawnAlbumCanvas=class {state={ready:false};bind(){}reset(){}imageChanged(){}};
ctx.DrawnMediaController=class {prepare(){}recycle(){}dispose(){}};
for(const name of ['DrawnAlbumLayouts','DrawnSingleMediaLayouts','DrawnTextLayouts'])ctx[name]=class {
 prepare(_ui,_group,_data,style){prepares++;return{style,nativeTiles:[]};}
};
load(root+'pages/chat/DrawnLayoutWarmCache.ets',['takeDrawnWarmLayout']);
ctx.getTdClient ??= () => ctx; ctx.setTimeout ??= () => 0; ctx.clearTimeout ??= () => {};
load(root+'pages/chat/DrawnRecycledLayouts.ets',['DrawnLayoutRetention','takeDrawnRecycledLayout','drawnRecycledLayouts']);
load(root+'util/drawnRowChromePolicy.ets',['drawnRowChromeReason']);
load(root+'pages/chat/DrawnRowInteraction.ets',['DrawnRowInteraction']);
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

// Real generated reuse must retain the interaction owner, not reconstruct it
// or write five default values before every computed reset.
const owner=row.interaction,fields=['menuShown','swipeX','capturedDeleteKey','allowBodyDrag','avatarRevision'];
let interactionWrites=0;
for(const field of fields){let value=owner[field];Object.defineProperty(owner,field,{get:()=>value,set(next){interactionWrites++;value=next;}});}
row.menuShown=true;row.swipeX=-42;row.capturedDeleteKey='old';row.allowBodyDrag=false;row.avatarStateRevision=17;
let prior=interactionWrites;row.aboutToRecycle();
assert.equal(interactionWrites-prior,4,'recycle clears only four changed interaction fields');
assert.equal(row.menuShown,false);assert.equal(row.swipeX,0);assert.equal(row.capturedDeleteKey,'');assert.equal(row.allowBodyDrag,true);
assert.equal(row.avatarStateRevision,17,'physical receiver revision survives recycle');
prior=interactionWrites;
for(let i=0;i<1000;i++){
 row.resetStateVarsOnReuse(i%2?pa:pb);assert.equal(row.interaction,owner);
 row.aboutToReuse();row.aboutToRecycle();
}
assert.equal(interactionWrites,prior,'1000 already-clean recycle/reset/reuse cycles perform zero interaction writes');
// Defensive reuse without the usual recycle callback also resets dirty UI.
row.menuShown=true;row.swipeX=40;row.capturedDeleteKey='previous';row.allowBodyDrag=false;
row.resetStateVarsOnReuse(pa);prior=interactionWrites;row.aboutToReuse();
assert.equal(interactionWrites-prior,4);assert.equal(row.menuShown,false);assert.equal(row.swipeX,0);
assert.equal(row.capturedDeleteKey,'');assert.equal(row.allowBodyDrag,true);
const other=new ctx.DrawnMessageRow(null,pb);assert.notEqual(other.interaction,owner);
other.menuShown=true;assert.equal(row.menuShown,false,'separate physical rows never share UI state');
row.avatarStateRevision++;assert.equal(row.avatarStateRevision,18);assert.equal(other.avatarStateRevision,0);
// Exercise actual deletion callback generations with the retained owner.
load(root+'pages/chat/DrawnRowLeaveCapture.ets',['DrawnRowLeaveCapture']);
row.leaveCapture=new ctx.DrawnRowLeaveCapture(key=>{row.capturedDeleteKey=key;});
const completed=[],leave={complete:id=>completed.push(id)};
row.leaveCapture.bind('A',1,1,true,leave);const staleCapture=row.leaveCapture.captured();
row.aboutToRecycle();row.resetStateVarsOnReuse(pb);row.aboutToReuse();
row.leaveCapture.bind('B',2,1,true,leave);staleCapture();assert.equal(row.capturedDeleteKey,'');
row.leaveCapture.captured()();assert.equal(row.capturedDeleteKey,'B');
row.aboutToRecycle();assert.equal(row.capturedDeleteKey,'');assert.equal(activeSubscriptions,0);
const compiledRow=fs.readFileSync(compiled+'pages/chat/DrawnMessageRow.ts','utf8');
const resetBody=compiledRow.slice(compiledRow.indexOf('public resetStateVarsOnReuse('),compiledRow.indexOf('this.resetMonitorsOnReuse();')+28);
for(const name of ['menuShown','swipeX','capturedDeleteKey','allowBodyDrag','avatarStateRevision','interaction'])
 assert.doesNotMatch(resetBody,new RegExp('this\\.'+name+'\\s*='),'generated reuse must not reset '+name);
for(const name of ['sendState','views','role','translation','avatarAnimated'])
 assert.match(resetBody,new RegExp('this\\.'+name+'\\s*='),'metadata still seeded before computed plan: '+name);
for(const name of ['plan','nativeTiles','mediaFrames','mediaSlots','useAlbumCanvas']) {
 assert.ok(resetBody.includes(`this.resetComputed("${name}")`),'retain geometry/visual equality boundary: '+name);
}
assert.equal((resetBody.match(/this.resetComputed\(/g)||[]).length,13,'nine visual boundaries, three publication projections and explicit host activation');
console.log('PASS: compiled reuse retains one interaction owner, 1000 clean cycles write zero UI fields, dirty recycle/reuse clears exactly four, avatar revision remains live, metadata stays pre-plan, rows and stale deletion callbacks stay isolated.');

// Retained staged children receive parameter updates WITHOUT Local reset. The
// layout must use B's metadata even while its subscribed Local values are A's.
// Run the real compiled plan/attach code before and after monitor delivery.
let refreshes=0;
const retained=new ctx.DrawnMessageRow(null,pa);
retained.aboutToAppear();
function packet(params){
 const style={radius:12,fontSize:16,environment:'1:1:1',textEnvironment:'1:1',
  role:params.group.head.senderTag || (params.data.isGroup&&!params.group.head.isOutgoing&&params.group.showSenderName
    ?ctx.senderRoleFor(ctx.senderRoleKey(params.data.chatId,params.group.head.senderId)):''),
  views:ctx.viewCountLabelFor(params.data.chatId,params.group.head.id)};
 return {group:params.group,data:params.data,style,plan:{style,nativeTiles:[]},engine:{},
  sameInput(g,d){return g===this.group&&d===this.data;},
  matches(g,d,s){return this.sameInput(g,d)&&Object.keys(style).every(k=>this.style[k]===s[k]);},
  refresh(s){refreshes++;this.style=s;return this.plan={style:s,nativeTiles:[]};}};
}
const handoffCases=[pa,pb,parameters(2,2,{senderTag:'embedded'}),parameters(2,2,{isOutgoing:true}),
 parameters(2,2,{}, {isGroup:false}),parameters(2,2),pa];
for(let i=0;i<1000;i++){
 const params=handoffCases[i%handoffCases.length],p=packet(params);
 // Same order as the parent's generated parameter publication; no reuse reset.
 retained.group=params.group;retained.data=params.data;retained.preparedAlbum=p;
 const before=refreshes,beforeSubs=subscribes;
 assert.equal(planGetter.call(retained),p.plan,'first plan consumes prepared current-owner metadata');
 assert.equal(refreshes,before,'handoff must not mutate the packet using previous-owner state');
 assert.equal(subscribes,beforeSubs,'plan stays subscription-free');
 retained.inputChanged();
 assert.equal(planGetter.call(retained),p.plan);
 assert.equal(refreshes,before,'attach does not prepare the same metadata a second time');
 assert.equal(retained.metadataOwner,retained.metadataKey());
}
// Current-owner asynchronous arrivals are not frozen to the prepared snapshot.
retained.group=pb.group;retained.data=pb.data;retained.preparedAlbum=packet(pb);
retained.inputChanged();let priorRefresh=refreshes;
ctx.publishViewCount(2,2,44000);planGetter.call(retained);
assert.equal(refreshes,priorRefresh+1);assert.equal(retained.preparedAlbum.style.views,'44K');
priorRefresh=refreshes;ctx.publishSenderRole('2:1002','owner B updated');planGetter.call(retained);
assert.equal(refreshes,priorRefresh+1);assert.equal(retained.preparedAlbum.style.role,'owner B updated');
// An old translated row cannot incorrectly force the next untranslated row to
// Legacy, nor can an untranslated old row suppress the new owner's fallback.
ctx.publishTranslating(2);assert.equal(planGetter.call(retained),null);
retained.group=pa.group;retained.data=pa.data;retained.preparedAlbum=packet(pa);
assert.equal(planGetter.call(retained),retained.preparedAlbum.plan);retained.inputChanged();
retained.group=pb.group;retained.data=pb.data;retained.preparedAlbum=packet(pb);
assert.equal(planGetter.call(retained),null);retained.inputChanged();
ctx.clearTranslationStatus(2);assert.notEqual(planGetter.call(retained),null);
retained.aboutToRecycle();assert.equal(activeSubscriptions,0);
console.log('PASS: 1000 retained param handoffs before/after Monitor cause zero prepared refreshes; A/B/A, role policy/tag changes, async views/role and translation fallback remain correct.');

// Recursive reset may reseed Computed epoch before Monitor delivery. Actual
// attach/inputChanged must still resume the retained child from its live host.
const hostSignal={hostActive:true,activationEpoch:1,packet:packet(pa)};
const orphan=observe(new ctx.DrawnMessageRow(null,{...pa,publication:hostSignal}));
orphan.aboutToAppear();assert.equal(activeSubscriptions,4);
for(let i=0;i<100;i++){
 hostSignal.hostActive=false;orphan.aboutToRecycle();
 orphan.resetStateVarsOnReuse({...((i%2)?pa:pb),publication:hostSignal});
 assert.equal(orphan.active,false);assert.equal(activeSubscriptions,0);
 hostSignal.hostActive=true;hostSignal.activationEpoch++;
 hostSignal.packet=packet((i%2)?pa:pb);
 // No aboutToReuse and no epoch callback, as in the retained child failure.
 orphan.inputChanged();assert.equal(orphan.active,true);assert.equal(activeSubscriptions,4);
}
hostSignal.hostActive=false;orphan.aboutToRecycle();orphan.inputChanged();
assert.equal(orphan.active,false);assert.equal(activeSubscriptions,0);
console.log('PASS: actual reset/packet monitor resumes 100 retained children even without reuse/epoch callbacks; inactive hosts stay detached.');
