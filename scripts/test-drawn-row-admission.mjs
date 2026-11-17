// Work-count and lifecycle tests against the real queue, layout engine and
// CompileArkTS host. No claims about native pixels or frame duration here.
import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
import {ctx,load,root,ui,data,group,layoutCounters} from './test-drawn-text-row.mjs';
const ts=(await import(process.env.TYPESCRIPT_MODULE||'typescript')).default;
const compiled='entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/'+root;
load(root+'util/drawnRowAdmissionQueue.ets',['DrawnRowAdmissionQueue']);
let now=0,callbacks=[],calls=[],failures=[];
const queue=new ctx.DrawnRowAdmissionQueue(()=>now,e=>failures.push(e.message),128);
const schedule=f=>callbacks.push(f);
const advance=frame=>{now++;const next=callbacks.splice(0);for(const f of next)f(frame);};
for(let i=0;i<3;i++)queue.enqueue(schedule,()=>calls.push(i));
assert.equal(callbacks.length,1);advance(100);assert.deepEqual(calls,[0]);
advance(100);assert.deepEqual(calls,[0],'same actual frame cannot release another row');
advance(101);assert.deepEqual(calls,[0,1]);advance(102);assert.deepEqual(calls,[0,1,2]);
// A callback delivered twice cannot consume a newly posted callback's token.
queue.enqueue(schedule,()=>calls.push(3));const duplicate=callbacks[0];advance(103);
queue.enqueue(schedule,()=>calls.push(4));duplicate(104);assert.equal(calls.at(-1),3);
advance(104);assert.equal(calls.at(-1),4);
// 10k cancellations keep exactly one callback, no tombstones/held closures.
for(let i=0;i<10000;i++) {
 const work=queue.enqueue(schedule,()=>{throw Error('cancelled work ran');});queue.cancel(work);
 assert.equal(work.owner,null);assert.equal(work.run,null);assert.equal(work.schedule,null);
 assert.equal(work.previous,null);assert.equal(work.next,null);
}
assert.equal(callbacks.length,1);assert.equal(queue.count,0);advance(105);
const nodes=[];for(let i=0;i<128;i++)nodes.push(queue.enqueue(schedule,()=>calls.push(i+100)));
assert.equal(queue.enqueue(schedule,()=>{}),null);assert.equal(queue.count,128);
for(const n of nodes)queue.cancel(n);advance(106);
queue.enqueue(schedule,()=>{throw Error('injected');});queue.enqueue(schedule,()=>calls.push(999));
advance(107);advance(108);assert.deepEqual(failures,['injected']);assert.equal(calls.at(-1),999);
// Re-entrant enqueue still waits for a new frame; no per-row private drain.
queue.enqueue(schedule,()=>queue.enqueue(schedule,()=>calls.push(1000)));
advance(109);advance(109);assert.equal(calls.at(-1),999);advance(110);assert.equal(calls.at(-1),1000);
console.log('PASS: actual-frame cap, duplicate/stale callback tokens, reentrancy, 10000 O(1) cancellations, bounded overflow, exception recovery.');

// Actual media geometry with deterministic native font doubles from text suite.
for(const f of ['albumGeometryCache','albumCellRenderData'])load(root+'util/'+f+'.ets');
for(const f of ['DrawnAlbumGridLayout','DrawnSingleMediaGeometry','DrawnMediaLayout','DrawnAlbumLayout'])load(root+'pages/chat/'+f+'.ets',f==='DrawnAlbumLayout'?['DrawnAlbumLayouts']:[]);
function loadObserved(file,names){
 const source=fs.readFileSync(file,'utf8').replace(/^import\s[\s\S]*?;\r?\n/gm,'')
 .replace(/@(?:ObservedV2|Trace|Param|Require|Local|Computed)\s*/g,'').replace(/@Monitor\([^)]*\)\s*/g,'').replace(/\bexport /g,'');
 vm.runInContext(ts.transpileModule(source+names.map(n=>`\nglobalThis.${n}=${n};`).join(''),{compilerOptions:{target:ts.ScriptTarget.ES2020}}).outputText,ctx,{filename:file});
}
load(root+'util/drawnRowRetention.ets',['DrawnRowRetention','drawnRowRetention']);
load(root+'util/drawnRowInput.ets',['sameDrawnRowData','sameDrawnAlbumInput','sameDrawnAlbumGeometryData']);
loadObserved(root+'pages/chat/DrawnPreparedAlbum.ets',['DrawnPreparedAlbum','DrawnAlbumPublication']);
let owner={};ctx.getTdClient=()=>owner;ctx.translationStatusFor=()=>null;ctx.viewCountLabelFor=()=>'';
ctx.senderRoleFor=()=>'';ctx.senderRoleKey=(c,s)=>`${c}:${s}`;
ctx.textMeasureEnvironment={epoch:1};ctx.chatEnv={drawnAlbumStaging:true,langEpoch:1,appearanceEpoch:1,bubbleRadius:12,msgTextSize:16};
ctx.a11yRuntimeState={active:false};ctx.logW=m=>{throw Error(m);};
const hostQueue=new ctx.DrawnRowAdmissionQueue(()=>now,e=>{throw e;});
ctx.drawnRowAdmission=hostQueue;ctx.enqueueDrawnRow=(_ui,run,visible)=>hostQueue.enqueue(schedule,run,visible);
loadObserved(compiled+'pages/chat/DrawnStagedAlbumRow.ts',['DrawnStagedAlbumRow']);
function album(id,count=6,caption='caption') {
 const g=group(caption);Object.assign(g.head,{id,rowId:id,contentType:'photo'});
 Object.assign(g,{caption,captionEntities:[],memberIds:Array.from({length:count},(_,i)=>id+i),photoRatios:Array(count).fill(1),
 photoPaths:[],photoFileIds:[],photoMinis:[],photoProgress:[],photoFailed:[],photoIsVideo:[],photoIsLive:[],videoFileIds:[],videoFileSizes:[],videoDurations:[],videoMimeTypes:[],inlineFileIds:[],inlineFileSizes:[]});return g;
}
function host(g=album(100)) {
 const h=Object.assign(Object.create(ctx.DrawnStagedAlbumRow.prototype),{group:g,data:{...data},actions:{},leaving:0,
 env:ctx.chatEnv,a11y:ctx.a11yRuntimeState,layouts:null,prepared:null,publication:new ctx.DrawnAlbumPublication(),
 owner:undefined,work:null,requested:null,generation:0,active:false,visible:false,warned:false,getUIContext:()=>ui});
 h.dropRetained=()=>{if(!h.active){h.publication.packet=null;h.prepared=null;h.layouts=null;h.owner=undefined;}};return h;
}
const hosts=[host(album(100)),host(album(200)),host(album(300))];
for(const h of hosts){h.aboutToAppear();assert.equal(h.publication.packet,null);assert.equal(h.pending,true);}
assert.equal(hostQueue.count,3);advance(200);assert.equal(hosts.filter(h=>h.publication.packet).length,1);
advance(201);advance(202);assert.ok(hosts.every(h=>!h.pending));
const h=hosts[0],packet=h.publication.packet,before=layoutCounters();
for(let i=0;i<1000;i++)assert.equal(h.target,packet);
assert.deepEqual(layoutCounters(),before,'exact host snapshots do not parse or remeasure');
// Child consumes the prepared geometry and never allocates a second engine.
const child=Object.assign(Object.create(ctx.DrawnMessageRow.prototype),{interaction:new ctx.DrawnRowInteraction(),kind:'album',group:packet.group,data:packet.data,
 env:ctx.chatEnv,a11y:ctx.a11yRuntimeState,translation:null,role:'',views:'',preparedAlbum:packet,
 getUIContext:()=>{throw Error('child prepare must not run');}});
assert.equal(child.plan,packet.plan);assert.deepEqual(layoutCounters(),before);
const captionPlan=child.plan.caption, footerWork=layoutCounters();child.presentationActive=true;
for(let i=0;i<300;i++) {
 child.views=['11','22',''][i%3];const refreshed=child.plan;
 assert.equal(refreshed.caption,captionPlan,'late footer values keep the host paragraph cache');
 if(child.views!=='')assert.ok(refreshed.footer.paragraph.content.startsWith(child.views));
 else assert.ok(!refreshed.footer.paragraph.content.startsWith('22'),'returning to the original style cannot use a stale mutable footer');
}
assert.equal(layoutCounters().bodyLayouts,footerWork.bodyLayouts);
assert.equal(child.albumLayouts,undefined,'metadata refresh never allocates a child layout engine');

for(const field of ['radius','fontSize','environment','textEnvironment','role','views']) {
 const changed={...packet.style,[field]:typeof packet.style[field]==='number'?packet.style[field]+1:'changed'};
 assert.equal(packet.matches(packet.group,packet.data,changed),false,field);
}
assert.equal(packet.matches({...packet.group},packet.data,packet.style),true);
assert.equal(packet.matches(packet.group,{...packet.data},packet.style),true);
assert.equal(packet.height(),packet.plan.height+6);
// A -> B -> C before the next frame: no B publication; old child packet stays
// mounted/hidden, then switches once. A recycled owner cannot publish late work.
h.aboutToRecycle();h.group=album(400);h.aboutToReuse();const old=h.publication.packet;
assert.equal(old,packet);assert.equal(h.pending,true);const stale=callbacks[0];
h.aboutToRecycle();h.group=album(500);h.aboutToReuse();advance(203);
assert.equal(h.publication.packet.group.head.id,500);stale(204);assert.equal(h.publication.packet.group.head.id,500);
// Same-row selection/progress updates are immediate and preserve interaction.
const updates=hostQueue.completed;h.data={...h.data,selectionActive:true,selectedMemberIds:[500]};h.request();
assert.equal(h.pending,false);assert.equal(hostQueue.completed,updates);assert.equal(h.publication.packet.data.selectionActive,true);
for(const state of ['sending','sent','read']){h.group={...h.group,head:{...h.group.head,sendState:state}};h.request();assert.ok(h.target);assert.equal(h.pending,false);}
// Special outer heights and policies use original behavior, no fake estimate.
for(const change of [x=>x.data.showUnreadDivider=true,x=>x.group.head.inlineButtons=[{}],
 x=>x.env={...ctx.chatEnv,drawnAlbumStaging:false}]) {
 const x=host(album(600));change(x);assert.equal(x.target,null);x.aboutToAppear();assert.equal(x.work,null);
}
const gone=host(album(700));gone.aboutToAppear();gone.aboutToDisappear();advance(205);assert.equal(gone.publication.packet,null);
// Height is exact for all bounded album counts, names/replies/captions/reactions
// share the production plan. Account replacement cannot hit a previous engine.
for(let n=2;n<=10;n++)for(const caption of ['', 'long '.repeat(50)]) {
 const x=host(album(800+n,n,caption));const p=x.target;assert.ok(p);assert.equal(p.height(),p.plan.height+6);
}
const engine=h.layouts;owner={};h.group=album(900);h.request();assert.notEqual(h.layouts,engine);
h.aboutToDisappear();advance(206);
console.log('PASS: three real album hosts publish on separate frames, 1000 measured-plan hits, zero child reprepare, stale A/B/C cancellation, same-row updates, sending continuity, bounded album geometry, policy bypass, disposal and account isolation.');

// CompileArkTS reset ordering: publication is an ordinary owner field, so V2
// cannot reset it to null and dismantle its child branch on every reuse.
const proto=ctx.ViewV2.prototype;
proto.initParam=function(k,v){this[k]=v;};proto.resetParam=function(k,v){this[k]=v;};
proto.finalizeConstruction=function(){};proto.resetComputed=function(k){void this[k];};
proto.resetMonitorsOnReuse=function(){};proto.getUIContext=()=>ui;
const actual=new ctx.DrawnStagedAlbumRow(null,{group:album(1100),data:{...data},actions:{}});
actual.aboutToAppear();advance(300);const retained=actual.publication.packet;
actual.aboutToRecycle();actual.resetStateVarsOnReuse({group:album(1200),data:{...data},actions:{}});
assert.equal(actual.publication.packet,retained,'real reset does not erase the published packet');
actual.aboutToReuse();assert.equal(actual.pending,true);advance(301);assert.equal(actual.publication.packet.group.head.id,1200);

// Execute the generated builder's branches with native node doubles. Pending
// cold rows create only Stack + silhouette, no DrawnMessageRow/ForEach/player.
let childCalls=0,childParams=null,native=[];
const nativeDouble=name=>new Proxy({}, {get:(_t,key)=> (...args)=>{
 if(key==='create')native.push(name);
 if(name==='Common' && key==='visibility')native.push(['visibility',args[0]]);
}});
for(const name of ['Stack','Row','If','__Common__'])ctx[name]=nativeDouble(name==='__Common__'?'Common':name);
ctx.Alignment={TopStart:0};ctx.Visibility={None:0,Visible:1};ctx.HitTestMode={None:0,Default:1};
proto.observeComponentCreation2=function(fn,type){fn(1,false);};
proto.ifElseBranchUpdateFunction=function(_index,fn){fn();};
proto.updateStateVarsOfChildByElmtId=function(_id,params){childCalls++;childParams=params;};
const cold=new ctx.DrawnStagedAlbumRow(null,{group:album(1300),data:{...data},actions:{}});
cold.aboutToAppear();cold.initialRender();assert.equal(childCalls,0);assert.ok(native.includes('Stack'));assert.ok(native.includes('Row'));
advance(302);native=[];cold.initialRender();assert.equal(childCalls,1);assert.equal(childParams.publication.packet.group.head.id,1300);assert.equal(childParams.presentationActive,true);
cold.aboutToRecycle();cold.resetStateVarsOnReuse({group:album(1400),data:{...data},actions:{}});cold.aboutToReuse();native=[];cold.initialRender();
assert.equal(childParams.publication.packet.group.head.id,1300,'pending rebind must not forward new payload to heavy child');
assert.equal(childParams.presentationActive,false);assert.ok(native.some(x=>Array.isArray(x)&&x[0]==='visibility'&&x[1]===0));
advance(303);cold.initialRender();assert.equal(childParams.publication.packet.group.head.id,1400);assert.equal(childParams.presentationActive,true);
cold.aboutToDisappear();actual.aboutToDisappear();
console.log('PASS: generated V2 reuse preserves the child branch; generated pending builder creates no heavy child, hides old identity, and forwards new payload only after admission.');

// A released canvas must not become N native image nodes while its old packet
// waits hidden for admission. Exercise the real generated getter and builder.
const oldCanvasRow=Object.assign(Object.create(ctx.DrawnMessageRow.prototype),{interaction:new ctx.DrawnRowInteraction(),
 presentationActive:false,retainedCanvasMode:true,albumCanvas:{state:{ready:false}},kind:'album',
 env:{},data:{},group:{head:{isOutgoing:false,reactions:[]}},jumpFocus:0,allowBodyDrag:false,
 nativeAnchors:{},canvasAttributes:{bind(){}},foreground:{bind(){}},painter:{bind(){}},menuFx:{preview(){},menu(){}},
 media:{slots:[]},menuShown:false,menuOffset:0,gridRadii:()=>({}),menu:()=>{},canDragMessage:()=>false
});
Object.defineProperty(oldCanvasRow,'plan',{value:{width:200,height:100,grid:{width:180,height:80,x:5,y:2},caption:null,quote:null,chrome:null}});
assert.equal(oldCanvasRow.useAlbumCanvas,true);
oldCanvasRow.presentationActive=true;assert.equal(oldCanvasRow.useAlbumCanvas,false);
oldCanvasRow.albumCanvas.state.ready=true;assert.equal(oldCanvasRow.useAlbumCanvas,true);
console.log('PASS: hidden reuse preserves single-canvas/native branch choice until the new payload is admitted.');

// Visible rows jump ahead of prediction work, with a bounded fairness turn.
callbacks=[];calls=[];const prioritized=new ctx.DrawnRowAdmissionQueue(()=>now,e=>{throw e;});
const bg=prioritized.enqueue(schedule,()=>calls.push('background'));
for(let i=0;i<5;i++)prioritized.enqueue(schedule,()=>calls.push('visible'+i),true);
for(let i=0;i<6;i++)advance(400+i);
assert.deepEqual(calls,['visible0','visible1','visible2','background','visible3','visible4']);
const promoted=prioritized.enqueue(schedule,()=>calls.push('promoted'));
prioritized.enqueue(schedule,()=>calls.push('older-visible'),true);prioritized.priority(promoted,true);
advance(410);advance(411);assert.equal(calls.at(-1),'promoted');
// Retention owns at most eight inactive packets; takeover removes a ticket.
const retention=new ctx.DrawnRowRetention(),drops=[];
const owners=Array.from({length:10},(_,i)=>()=>drops.push(i));
for(const drop of owners)retention.hold(drop);
assert.equal(retention.entries.size,8);assert.deepEqual(drops,[0,1]);
retention.take(owners[2]);retention.clear();assert.equal(drops.includes(2),false);assert.equal(retention.entries.size,0);
assert.equal(drops.length,9);
console.log('PASS: O(1) visible priority with prediction fairness; retained inactive owners capped at eight, take/evict/clear release correctly.');

const ttl=new ctx.DrawnRowRetention();let expired=false;
const drop=()=>{expired=true;};ttl.hold(drop);const originalClock=ctx.Date.now;
ctx.Date.now=()=>20000;ttl.take(drop);ctx.Date.now=originalClock;
assert.equal(expired,true);assert.equal(ttl.entries.size,0);
console.log('PASS: expired retained owner is dropped before reuse; footer A/B/A refresh keeps one engine and never returns stale labels.');
// Execute the actual compiled canvas builder while its previous mode is latched.
oldCanvasRow.presentationActive=false;oldCanvasRow.albumCanvas.state.ready=false;
oldCanvasRow.data={playSlotKey:''};oldCanvasRow.forEachUpdateFunction=()=>{throw Error('hidden canvas created native tiles');};
ctx.JUMP_FOCUS_SCALE=.04;ctx.JUMP_FOCUS_BRIGHTNESS=.05;ctx.MenuPreviewMode={NONE:0,IMAGE:1};
ctx.ModalMode={TARGET_WINDOW:0};ctx.HapticFeedbackMode={AUTO:0};ctx.BlurStyle={BACKGROUND_THIN:0};
ctx.menuPreviewCompact=()=>false;ctx.containerBlur=()=>0;ctx.overlayMaterial=()=>0;
ctx.Color={Transparent:0};oldCanvasRow.canvasContent();
// Expiry during V2 reset must not discard the NEW input already prepared there.
const expiryHost=new ctx.DrawnStagedAlbumRow(null,{group:album(1500),data:{...data},actions:{}});
expiryHost.aboutToAppear();advance(500);expiryHost.aboutToRecycle();
expiryHost.resetStateVarsOnReuse({group:album(1600),data:{...data},actions:{}});
const nextPacket=expiryHost.prepared,nextEngine=expiryHost.layouts,workBeforeExpiry=layoutCounters();
const savedClock=ctx.Date.now;ctx.Date.now=()=>50000;expiryHost.aboutToReuse();ctx.Date.now=savedClock;
assert.equal(expiryHost.prepared,nextPacket);assert.equal(expiryHost.layouts,nextEngine);
assert.deepEqual(layoutCounters(),workBeforeExpiry);advance(501);assert.equal(expiryHost.publication.packet.group.head.id,1600);
expiryHost.aboutToDisappear();
console.log('PASS: compiled hidden canvas never enters ForEach; expiry between reset and reuse preserves newly prepared geometry.');

// Diagnostic markers must identify the existing decisions without changing
// layout/publication behavior or retaining message identifiers in trace names.
const targetTrace=[];
ctx.hiTraceMeter={HiTraceOutputLevel:{COMMERCIAL:3},startSyncTrace:(_level,name)=>targetTrace.push(name),finishSyncTrace:()=>{}};
ctx.drawnStageMetrics.setEnabled(true);
const diagnosticHost=host(album(1700));void diagnosticHost.target;void diagnosticHost.target;
diagnosticHost.data={...diagnosticHost.data,contentWidth:diagnosticHost.data.contentWidth+1};void diagnosticHost.target;
diagnosticHost.group=album(1800);void diagnosticHost.target;
const otherUi={...ui};diagnosticHost.getUIContext=()=>otherUi;diagnosticHost.hostUi=null;void diagnosticHost.target;
diagnosticHost.env={...ctx.chatEnv,bubbleRadius:15};void diagnosticHost.target;
for(const reason of ['initial','hit','data','group','context','style'])assert.ok(targetTrace.includes(`PG/row-target-${reason}`),reason);
ctx.drawnStageMetrics.setEnabled(false);
const bridgeFrames=[],bridgeTrace=[],bridgeTimers=[];let bridgeClock=0;
const bridge=vm.createContext({FrameCallback:class{},Date:{now:()=>bridgeClock},
 setTimeout:fn=>{bridgeTimers.push(fn);return 1;},logW:()=>{},
 hiTraceMeter:{HiTraceOutputLevel:{COMMERCIAL:3},startSyncTrace:(_level,name)=>bridgeTrace.push(name),finishSyncTrace:()=>{}}});
function bridgeLoad(file,names) {
 const source=fs.readFileSync(root+file,'utf8').replace(/^import\s[\s\S]*?;\r?\n/gm,'').replace(/\bexport /g,'');
 vm.runInContext(ts.transpileModule(source+names.map(n=>`\nglobalThis.${n}=${n};`).join(''),{compilerOptions:{target:ts.ScriptTarget.ES2020}}).outputText,bridge);
}
bridgeLoad('util/drawnStageMetrics.ets',['drawnStageMetrics']);
bridgeLoad('util/drawnRowAdmissionQueue.ets',[]);
bridgeLoad('util/drawnRowAdmission.ets',['drawnRowAdmission','enqueueDrawnRow']);
const bridgeUi={postDelayedFrameCallback:fn=>bridgeFrames.push(fn)};let granted=0;
bridge.enqueueDrawnRow(bridgeUi,()=>granted++,true);bridgeFrames.shift().onFrame(1);
assert.equal(granted,1);assert.equal(bridgeTrace.length,0,'disabled diagnostic path never calls native trace');
bridge.drawnStageMetrics.setEnabled(true);
const promotedWork=bridge.enqueueDrawnRow(bridgeUi,()=>granted++,false);
bridge.drawnRowAdmission.priority(promotedWork,true);bridgeClock=16;bridgeFrames.shift().onFrame(2);
assert.ok(bridgeTrace.includes('PG/row-publish-visible'));assert.ok(bridgeTrace.includes('PG/row-wait-9-16ms'));
bridge.enqueueDrawnRow(bridgeUi,()=>granted++,false);bridgeClock=100;bridgeFrames.shift().onFrame(3);
assert.ok(bridgeTrace.includes('PG/row-publish-predict'));assert.ok(bridgeTrace.includes('PG/row-wait-67plus'));
assert.equal(granted,3);assert.equal(bridgeTimers.length,0);
console.log('PASS: real target cache reason markers, trace-off no native calls, actual promoted priority and wait buckets, unchanged publication count.');

// Fixed-field guards are audited against the actual schemas, including inherited
// layout fields. New schema fields must be classified, not silently ignored.
function interfaceFields(file,name) {
 const source=ts.createSourceFile(file,fs.readFileSync(file,'utf8'),ts.ScriptTarget.Latest,true);
 const declaration=source.statements.find(n=>ts.isInterfaceDeclaration(n)&&n.name.text===name);
 assert.ok(declaration,name);return declaration.members.map(n=>n.name.text);
}
const dataFields=[...interfaceFields(root+'util/messageTextInput.ets','MessageTextLayout'),
 ...interfaceFields(root+'pages/chat/ReusableMessageBubble.ets','MessageBubbleRenderData')];
const groupFields=interfaceFields(root+'util/collapseAlbums.ets','AlbumGroup');
const inputSource=fs.readFileSync(root+'util/drawnRowInput.ets','utf8');
function compared(name) {return [...inputSource.match(new RegExp(`function ${name}[^]*?\\n}`))[0].matchAll(/a\.(\w+) === b\.\1/g)].map(m=>m[1]);}
assert.deepEqual(compared('sameDrawnRowData').sort(),dataFields.sort());
assert.deepEqual(compared('sameDrawnAlbumInput').sort(),groupFields.sort());
const geometryFields=new Set(compared('sameDrawnAlbumGeometryData'));
for(const name of ['pages/chat/DrawnMediaLayout.ets','pages/chat/DrawnAlbumGridLayout.ets','util/drawnContentPolicy.ets']) {
 for(const m of fs.readFileSync(root+name,'utf8').matchAll(/\bdata\.(\w+)/g))assert.ok(geometryFields.has(m[1]),`${name}:${m[1]}`);
}
for(const [fn,base,fields] of [[ctx.sameDrawnRowData,{...data},dataFields],[ctx.sameDrawnAlbumInput,album(2000),groupFields]]) {
 assert.equal(fn(base,{...base}),true);
 for(const field of fields)assert.equal(fn(base,{...base,[field]:Symbol(field)}),false,`field omitted: ${field}`);
}
// Real compiled host, fresh UI wrapper every access, 10k equal outer snapshots:
// exactly one context acquisition and no new prepare, packet, native shaping,
// queue work or publication notification. No body/array hashing is needed.
const stable=host(album(2100));let contextReads=0;
stable.getUIContext=()=>{contextReads++;return {...ui};};
stable.aboutToAppear();advance(600);
const stablePacket=stable.publication.packet,stableCounters=layoutCounters();
const prepareOriginal=stable.layouts.prepare.bind(stable.layouts);let prepares=0;
stable.layouts.prepare=(...args)=>{prepares++;return prepareOriginal(...args);};
const stableCompleted=hostQueue.completed;
for(let i=0;i<10000;i++) {
 stable.data={...stable.data};stable.group={...stable.group};
 stable.request();assert.equal(stable.target,stablePacket);assert.equal(stable.publication.packet,stablePacket);
}
assert.equal(contextReads,1);assert.equal(prepares,0);assert.equal(hostQueue.completed,stableCompleted);
assert.deepEqual(layoutCounters(),stableCounters);
// Permission/editing changes reach handlers immediately but never invoke the
// paragraph/grid preparer. Reverting A/B/A also retains the measured plan.
for(const canReply of [false,true,false]) {
 stable.data={...stable.data,canReply,editingActive:!canReply};stable.request();
 assert.equal(stable.publication.packet.data.canReply,canReply);
 assert.equal(stable.publication.packet.data.editingActive,!canReply);
 assert.equal(stable.publication.packet.plan,stablePacket.plan);
}
assert.equal(prepares,0);
// Selection, playback, width, theme, caption, progress and failure remain live.
for(const change of [x=>x.data={...x.data,selectionActive:true,selectedMemberIds:[2100]},
 x=>x.data={...x.data,playSlotKey:'2100:0',autoplayMuted:true,playSlotStartMs:200},
 x=>x.data={...x.data,contentWidth:x.data.contentWidth-20},
 x=>x.data={...x.data,themeBubbleOut:'blue'},
 x=>x.group={...x.group,caption:'changed caption'},
 x=>x.group={...x.group,photoProgress:[40,0,0,0,0,0]},
 x=>x.group={...x.group,photoFailed:[true,false,false,false,false,false]}]) {
 const count=prepares;change(stable);stable.request();assert.equal(prepares,count+1);
 assert.equal(stable.publication.packet.group,stable.group);assert.equal(stable.publication.packet.data,stable.data);
}
// Configuration epochs refresh native units even with a stable UIContext.
let density=2;const scaled=host(album(2200));scaled.getUIContext=()=>({vp2px:n=>n*density,fp2px:n=>n*density});
const initialScaled=scaled.target;assert.equal(initialScaled.plan.density,2);
density=3;ctx.textMeasureEnvironment.epoch++;const changedScaled=scaled.target;
assert.equal(changedScaled.plan.density,3);assert.notEqual(changedScaled,initialScaled);
// Real disappearance invalidates the window context; another mounted host
// cannot share it. Recycling in the same window retains it without new NAPI.
const windowHost=new ctx.DrawnStagedAlbumRow(null,{group:album(2300),data:{...data},actions:{}});
let currentWindow={...ui},windowReads=0;windowHost.getUIContext=()=>{windowReads++;return currentWindow;};
windowHost.aboutToAppear();advance(601);const firstWindow=windowHost.hostUi;
windowHost.aboutToRecycle();windowHost.group=album(2400);windowHost.aboutToReuse();advance(602);
assert.equal(windowHost.hostUi,firstWindow);assert.equal(windowReads,1);
windowHost.aboutToDisappear();assert.equal(windowHost.hostUi,null);
currentWindow={...ui};windowHost.aboutToAppear();advance(603);
assert.equal(windowHost.hostUi,currentWindow);assert.equal(windowReads,2);windowHost.aboutToDisappear();
stable.aboutToDisappear();
console.log('PASS: 10000 fresh wrapper/equal snapshot updates create zero plans or publications; all schema fields covered, interaction-only geometry reuse, live media/selection/content edits, density epoch and window lifetime isolation.');

// Native date header remains outside the body's fixed-height pending Stack.
// Run compiled builders, so a mere source gate removal cannot pass this test.
let dateNodes=[],dateStack=[];
for(const name of ['Column','Stack','Row','Text','If','__Common__'])ctx[name]=new Proxy({}, {get:(_t,k)=>(...args)=>{
 if(name==='If')return;
 if(k==='create'){const n={type:name,parent:dateStack.at(-1),args,attrs:{}};dateNodes.push(n);dateStack.push(n);}
 else if(k==='pop')dateStack.pop();else if(dateStack.length)dateStack.at(-1).attrs[k]=args;
}});
ctx.FontWeight={Medium:'Medium'};ctx.COLOR_TEXT_SECONDARY='secondary';ctx.$r=x=>x;
const datedGroup=album(2500);datedGroup.dateLabel='2026-11-16';
const dated=new ctx.DrawnStagedAlbumRow(null,{group:datedGroup,data:{...data},actions:{}});
dated.aboutToAppear();assert.ok(dated.target);assert.equal(dated.pending,true);
let dateChildCalls=0,dateChild=null;
dated.updateStateVarsOfChildByElmtId=(_id,params)=>{dateChildCalls++;dateChild=params;};
function renderDate(){dateNodes=[];dateStack=[];dated.initialRender();return dateNodes;}
let dn=renderDate(),header=dn.find(n=>n.type==='Text'),body=dn.find(n=>n.type==='Stack');
assert.equal(dateChildCalls,0,'cold dated row does not construct the heavy body before admission');
assert.equal(header.args[0],'2026-11-16');assert.equal(header.parent,body.parent);
assert.equal(header.parent.type,'Column');assert.equal(header.parent.attrs.height,undefined,'native header height is never guessed');
assert.deepEqual(header.attrs.fontSize,[12]);assert.deepEqual(header.attrs.fontWeight,['Medium']);
assert.deepEqual(JSON.parse(JSON.stringify(header.attrs.padding)),[{left:10,right:10,top:3,bottom:3}]);
assert.deepEqual(JSON.parse(JSON.stringify(header.attrs.margin)),[{top:5,bottom:3}]);
assert.deepEqual(body.attrs.height,[dated.target.height()]);
const dateShape=layoutCounters();for(let i=0;i<1000;i++)assert.equal(dated.target,dated.prepared);
assert.deepEqual(layoutCounters(),dateShape,'date does not add repeated paragraph measurement');
advance(700);dn=renderDate();assert.equal(dated.pending,false);assert.equal(dateChild.dateInHost,true);
assert.equal(dateChild.publication.packet.group,datedGroup,'no group copy or media-array copy to strip date');
assert.equal(dn.filter(n=>n.type==='Text').length,1);assert.deepEqual(dn.find(n=>n.type==='Stack').attrs.height,[undefined]);
const nextDate=album(2600);nextDate.dateLabel='2026-11-17';
dated.aboutToRecycle();dated.resetStateVarsOnReuse({group:nextDate,data:{...data},actions:{}});dated.aboutToReuse();
dn=renderDate();assert.equal(dn.find(n=>n.type==='Text').args[0],'2026-11-17');
assert.equal(dateChild.publication.packet.group,datedGroup);assert.equal(dateChild.presentationActive,false);
advance(701);renderDate();assert.equal(dateChild.publication.packet.group,nextDate);assert.equal(dateChild.presentationActive,true);
// Switching policy uses the original whole row and its own date, not two headers.
dated.env={...ctx.chatEnv,drawnAlbumStaging:false};dated.request();dn=renderDate();
assert.equal(dn.filter(n=>n.type==='Text').length,0);assert.notEqual(dateChild.dateInHost,true);
assert.equal(dateChild.group,nextDate);dated.aboutToDisappear();
// Suppression must survive every album compatibility branch; flags default off.
for(const file of ['DrawnMessageRow','LegacyAlbumMessageBubble','DrawnContentRow']) {
 const code=fs.readFileSync(compiled+'pages/chat/'+file+'.ts','utf8');
 assert.match(code,/dateInHost: this.dateInHost/,file+' forwards native-header ownership to fallback');
}
for(const file of ['DrawnMessageRow','DrawnContentRow','MessageBubbleShell']) {
 const code=fs.readFileSync(compiled+'pages/chat/'+file+'.ts','utf8');
 assert.match(code,/!this.dateInHost && this.(?:rowGroup|group).dateLabel !== ''/,file+' suppresses only externally owned dates');
}
console.log('PASS: dated albums enter the frame queue; compiled native header keeps original style outside exact body height, 1000 cache hits, reuse identity, no group copies, and policy/fallback date ownership.');

// New params may arrive before admission. All child reads stay on the single
// published packet, including geometry; no mixed new group / old render data.
const channelChild=Object.create(ctx.DrawnMessageRow.prototype);
channelChild.publication=new ctx.DrawnAlbumPublication();
const original={group:album(4000),data:{...data,chatId:5},plan:{id:1}};
channelChild.publication.packet=original;
for(let i=0;i<1000;i++) {
 channelChild.group=album(5000+i);channelChild.data={...data,chatId:6};
 assert.equal(channelChild.rowGroup,original.group);
 assert.equal(channelChild.rowData,original.data);
 assert.equal(channelChild.rowPreparedAlbum,original);
}
const replacement={group:channelChild.group,data:channelChild.data,plan:{id:2}};
channelChild.publication.packet=replacement;
assert.equal(channelChild.rowGroup,replacement.group);assert.equal(channelChild.rowData,replacement.data);
assert.equal(channelChild.rowPreparedAlbum,replacement);
channelChild.publication=undefined;
assert.equal(channelChild.rowGroup,channelChild.group);assert.equal(channelChild.rowData,channelChild.data);
console.log('PASS: stable publication channel atomically gates group/data/plan over 1000 pending parameter transfers.');

const epochHost=host(album(9100));epochHost.aboutToAppear();
const e=epochHost.publication.activationEpoch;assert.equal(epochHost.publication.hostActive,true);
epochHost.aboutToAppear();assert.equal(epochHost.publication.activationEpoch,e);
epochHost.aboutToRecycle();assert.equal(epochHost.publication.hostActive,false);
epochHost.aboutToReuse();assert.equal(epochHost.publication.activationEpoch,e+1);
epochHost.aboutToDisappear();assert.equal(epochHost.publication.hostActive,false);
console.log('PASS: real staged host publishes monotonic activation across recycle/reuse and closes the host gate on disappear.');
