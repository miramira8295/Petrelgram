// Replay real snapshot/follow methods with deterministic native geometry/timers.
import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
const ts=(await import(process.env.TYPESCRIPT_MODULE||'typescript')).default;
const root='entry/src/main/ets/';
const read=p=>fs.readFileSync(root+p+'.ets','utf8');
function method(source,name){
  const match=new RegExp(`^  (?:private )?${name}\\(`,'m').exec(source);assert.ok(match,name);
  const ast=ts.createSourceFile('test.ts','class T {\n'+source.slice(match.index),ts.ScriptTarget.Latest,true);
  return ast.statements[0].members[0].getText(ast);
}
const session=read('pages/chat/ChatTimelineSession'),page=read('pages/chat/ChatPage');
let now=10000,id=0;const timers=new Map();
const c=vm.createContext({Date:{now:()=>now},Number,Math,Edge:{Bottom:1},TouchType:{Down:0,Up:1,Cancel:2},
 ScrollState:{Idle:0,Scroll:1},ScrollSource:{DRAG:0,FLING:1,EDGE_EFFECT:2,OTHER_USER_INPUT:3,SCROLL_BAR:4,SCROLL_BAR_FLING:5,SCROLLER:6,SCROLLER_ANIMATION:7},logW:()=>{},
 setTimeout(fn,delay){timers.set(++id,{fn,delay});return id;},clearTimeout:id=>timers.delete(id),
 drawnStageMetrics:{begin:()=>0,end:()=>{}},DrawnStage:new Proxy({}, {get:()=>0}),
 setScrollActive:()=>{},setStickerDecodePaused:()=>{},noteScrollPlaceholderMotion:()=>{},
 isResumeFragment:()=>false,publishMessageRowPresentations:()=>{}});
function run(s){vm.runInContext(ts.transpileModule(s.replace(/^import[\s\S]*?;\r?\n/gm,'').replace(/\bexport /g,''),{compilerOptions:{target:ts.ScriptTarget.ES2020}}).outputText,c);}
run(read('util/bottomFollow'));
run(`class Timeline {${['nearBottomFollow','canFollowTail','shouldFollowNewTail','armSelfSendFollow','selfSendFollowActive',
 'clearSelfSendFollow','glueBottom','rowBottomVp','invalidateScrollWork','handleTimelineTouch','handleTimelineWillScroll',
 'handleTimelineDidScroll','handleTimelineScrollStop'].map(n=>method(session,n)).join('\n')}} globalThis.Timeline=Timeline;`);
run(`class Page {${['shareHost','captureSendFollow','followNewTailIfAtBottom','scheduleBottomAfterLayout','onMessagesSnapshot','applyInitialOrFollowLanding']
 .map(n=>method(page,n)).join('\n')}} globalThis.Page=Page;`);
function setup(){
 timers.clear();const t=new c.Timeline(),p=new c.Page();
 const state={bottom:698,end:false,viewer:false,more:false,jump:false,pendingJump:0,reads:0,scrolls:0,refreshes:0,store:null};
 const store={getHasMoreNewer:()=>state.more,getInitialHistoryState:()=> 'ready',getOlderLoadState:()=>'',
 getNewerLoadState:()=>'',getInitialHistoryError:()=>'',isInitialFillPending:()=>false,prefetchOlder:()=>{},flushScrollDeferredUpdate:()=>{}};
 state.store=store;
 Object.assign(t,{bindings:{screenH:()=>800,bottomChromeH:()=>100,store:()=>state.store,viewerOpen:()=>state.viewer,
 pendingJumpId:()=>state.pendingJump,jumpLandingHolding:()=>state.jump,cancelImeFollow:()=>{},keyboardVisible:()=>false,
 flash:{cancelFlash:()=>{},syncFlashRect:()=>{}},closeBottomPanels:()=>{},imeTailPinned:()=>false,
 translation:{onListSettled:()=>{}},playSlot:{setScrolling:()=>{},armSettle:()=>{}},capMessageReuseBuckets:()=>{}},
 scroller:{isAtEnd:()=>state.end,getItemRect:()=>{state.reads++;return {width:100,height:100,y:state.bottom-100};},scrollEdge:()=>state.scrolls++},
 groups:[{head:{id:1}}],indexGroupsLen:1,curStartIdx:0,curEndIdx:0,atBottom:false,bottomFollowPending:false,
 pageVisible:true,didInitialScroll:true,stayAtUnread:false,listTouchActive:false,timelineScrollActive:false,
 scrollActionSeq:1,userTouchSeq:1,followIntentEpoch:0,bottomLayoutFollowSeq:0,selfSendFollowUntil:0,selfSendFollowToken:0,
 selfSendFollowActionSeq:0,selfSendFollowTouchSeq:0,scrollWorkEpoch:0,scrollWorkTimers:new Set(),
 refreshAtBottom:()=>state.refreshes++,finishInitialMessageStageForInteraction:()=>{},scheduleScrollWork:()=>{},
 userScrollOffsetTotal:0,accumulateNewerDrag:()=>{},updateFloatDate:()=>{},maybeTrimWindow:()=>{},
 resumeChatTgsAfterScroll:()=>{},driveVisibleWork:()=>{},flushQueuedOlderLoad:()=>{}});
 Object.assign(p,{timeline:t,store,routeResumeWaiting:false,pendingScrollBottom:false,lastMaxId:1,freshClearSeq:0,
 pendingJumpId:0,viewerOpen:()=>state.viewer,jumpLandingHolding:()=>state.jump,chatId:9,isChannel:false,
 isGroup:false,syncComposerSlot:()=>{},groupsWithClientJoinNotice:list=>list.map(head=>({head})),resolveResumeLandingChoice:()=>false,
 capturePrependAnchorSample:()=>({id:0}),captureAppendAnchorSample:()=>({id:0}),restoreCapturedAnchors:()=>{},
 publishSnapshotAndChrome:(_store,_list,groups)=>{t.groups=groups;state.bottom=Number.NaN;t.atBottom=false;},
 applyResumeLanding:()=>false,consumeLiveIncomingMediaAndCommands:()=>{},consumeJumpToLatestIntent:()=>{},
 scheduleNewerTailRefresh:()=>{},mediaSave:{onSnapshot:()=>{}},landPendingJump:()=>{},scheduleComposerEditorMount:()=>{}});
 return {t,p,state,store};
}
function fire(delay){const entries=[...timers].filter(([_id,x])=>x.delay===delay);for(const [id,x]of entries){timers.delete(id);x.fn();}}
let tests=0;function check(name,fn){try{fn();tests++;}catch(e){e.message=`${name}: ${e.message}`;throw e;}}
check('near-bottom band and short underfilled list',()=>{
 const {t,state}=setup();for(const bottom of [538,698,858]){state.bottom=bottom;assert.equal(t.nearBottomFollow(),true);}
 for(const bottom of [537,859,3000]){state.bottom=bottom;assert.equal(t.nearBottomFollow(),false);}
 state.bottom=100;state.end=true;assert.equal(t.nearBottomFollow(),true);
});
check('long partial final message never follows, even with stale atEnd',()=>{
 const {t,state}=setup();state.bottom=3000;t.atBottom=true;
 assert.equal(t.shouldFollowNewTail(),false);state.end=true;assert.equal(t.shouldFollowNewTail(),false);
});
check('snapshot samples old tail before publishing new unmeasured row',()=>{
 const {t,p,state,store}=setup();let measuredBefore=false;
 const publish=p.publishSnapshotAndChrome;p.publishSnapshotAndChrome=(...args)=>{measuredBefore=state.reads===1;publish(...args);};
 p.onMessagesSnapshot(store,[{id:1},{id:2}],'update');assert.equal(measuredBefore,true);assert.equal(t.bottomFollowPending,true);
 fire(32);assert.equal(state.scrolls,1);fire(60);assert.equal(state.refreshes,1);
});
check('long row snapshot, read receipts and history loading do not schedule',()=>{
 for(const [kind,bottom,max]of [['update',3000,2],['update',698,1],['newer',698,2]]){
  const {p,state,store}=setup();state.bottom=bottom;p.onMessagesSnapshot(store,[{id:1},{id:max}],kind);
  fire(32);assert.equal(state.scrolls,0);
 }
});
check('5000 pending rows do not increase work or inspect message contents',()=>{
 const {t,state}=setup();t.groups=new Proxy({length:5000},{get(o,k){if(k==='length')return o.length;throw new Error('row scan');}});
 t.curEndIdx=0;t.indexGroupsLen=5000;state.bottom=3000;
 for(let i=0;i<1000;i++)assert.equal(t.shouldFollowNewTail(),false);
 assert.equal(state.reads,1000);
});
check('missing geometry is not interpreted as zero height or near-bottom',()=>{
 const {t,state}=setup();state.bottom=NaN;assert.equal(t.nearBottomFollow(),false);
 state.end=true;t.atBottom=true;assert.equal(t.nearBottomFollow(),true);
 t.indexGroupsLen=0;assert.equal(t.nearBottomFollow(),false);
 t.scroller.getItemRect=()=>({width:0,height:0,y:0});assert.equal(t.nearBottomFollow(),false);
});
check('unread landing and unavailable viewport preserve position',()=>{
 const {t}=setup();t.stayAtUnread=true;assert.equal(t.shouldFollowNewTail(),false);
 t.stayAtUnread=false;t.bindings.screenH=()=>0;assert.equal(t.nearBottomFollow(),false);
});
check('stronger intentions suppress near-bottom and explicit send follow',()=>{
 for(const name of ['viewer','more','jump','pendingJump','touch','scroll','hidden','initial','closed']){
  const {t,state}=setup();t.armSelfSendFollow();
  if(name==='touch')t.listTouchActive=true;else if(name==='scroll')t.timelineScrollActive=true;
  else if(name==='hidden')t.pageVisible=false;else if(name==='initial')t.didInitialScroll=false;
  else if(name==='closed')state.store=null;else state[name]=true;
  assert.equal(t.shouldFollowNewTail(),false,name);
 }
});
check('own send intent expires, yields to touch/jump, and old failures cannot cancel newer send',()=>{
 const {t,state}=setup();state.bottom=3000;const first=t.armSelfSendFollow();assert.equal(t.shouldFollowNewTail(),true);
 const second=t.armSelfSendFollow();t.clearSelfSendFollow(first);assert.equal(t.selfSendFollowActive(),true);
 t.clearSelfSendFollow(second);assert.equal(t.selfSendFollowActive(),false);
 t.armSelfSendFollow();t.userTouchSeq++;assert.equal(t.selfSendFollowActive(),false);
 t.armSelfSendFollow();t.scrollActionSeq++;assert.equal(t.selfSendFollowActive(),false);
 t.armSelfSendFollow();now+=1500;assert.equal(t.selfSendFollowActive(),false);
});
check('Touch.Down and wheel scroll cancel queued follow and self-send window',()=>{
 const {t,p,state}=setup();t.armSelfSendFollow();p.scheduleBottomAfterLayout('test');t.handleTimelineTouch({type:0});
 fire(32);assert.equal(state.scrolls,0);assert.equal(t.selfSendFollowActive(),false);
 t.listTouchActive=false;t.armSelfSendFollow();p.scheduleBottomAfterLayout('wheel');
 t.handleTimelineWillScroll(10,1,3);t.handleTimelineDidScroll(10,1);fire(32);
 assert.equal(state.scrolls,0);assert.equal(t.selfSendFollowActive(),false);
});
check('continuing inertia and programmatic layout do not cancel a newer explicit send',()=>{
 for(const source of [1,2,5,6,7]){
  const {t}=setup();t.armSelfSendFollow();t.handleTimelineWillScroll(10,1,source);
  assert.equal(t.selfSendFollowActive(),true,source);
 }
});
check('timer rechecks viewer, history, jump, lifecycle and manual scrolling',()=>{
 for(const name of ['viewer','more','jump','pending','action','store','hidden','touch','scroll']){
  const {t,p,state}=setup();p.scheduleBottomAfterLayout('test');
  if(name==='pending')p.pendingJumpId=99;else if(name==='action')t.scrollActionSeq++;
  else if(name==='store')p.store={getHasMoreNewer:()=>false};else if(name==='hidden')t.pageVisible=false;
  else if(name==='touch')t.listTouchActive=true;else if(name==='scroll')t.timelineScrollActive=true;else state[name]=true;
  fire(32);assert.equal(state.scrolls,0,name);assert.equal(t.bottomFollowPending,false,name);
 }
});
check('burst updates keep latest pending follow even if new geometry missing',()=>{
 const {t,p,state,store}=setup();p.onMessagesSnapshot(store,[{id:1},{id:2}],'update');
 p.onMessagesSnapshot(store,[{id:1},{id:2},{id:3}],'update');assert.equal(t.bottomFollowPending,true);
 fire(32);assert.equal(state.scrolls,1);assert.equal(t.bottomFollowPending,false);
});
check('scroll-stop own send uses same gates rather than bypassing jump or viewer',()=>{
 for(const guard of ['none','viewer','more','jump','pendingJump','touch','hidden']){
  const {t,state}=setup();t.timelineScrollActive=true;t.armSelfSendFollow();
  if(guard==='touch')t.listTouchActive=true;else if(guard==='hidden')t.pageVisible=false;else if(guard!=='none')state[guard]=true;
  t.handleTimelineScrollStop();assert.equal(state.scrolls,guard==='none'?1:0,guard);
 }
});
check('exit invalidates queued timers and stale self send',()=>{
 const {t,p,state}=setup();p.scheduleBottomAfterLayout('test');t.armSelfSendFollow();t.invalidateScrollWork();
 fire(32);assert.equal(state.scrolls,0);assert.equal(t.bottomFollowPending,false);assert.equal(t.selfSendFollowActive(),false);
});
check('send completion follows published row but yields to gestures, jumps and page switches',()=>{
 for(const guard of ['none','touch','wheel','jump','exit-return','store','viewer','more']){
  const {t,p,state}=setup();state.bottom=3000;const complete=p.captureSendFollow();
  if(guard==='touch'){t.handleTimelineTouch({type:0});t.listTouchActive=false;}
  else if(guard==='wheel'){t.handleTimelineWillScroll(10,1,3);}
  else if(guard==='jump')t.scrollActionSeq++;
  else if(guard==='exit-return')t.invalidateScrollWork();
  else if(guard==='store')p.store={};
  else if(guard==='viewer'||guard==='more')state[guard]=true;
  complete();fire(32);assert.equal(state.scrolls,guard==='none'?1:0,guard);
 }
});
check('direct share/drop completion retains the send-time position owner',()=>{
 const {t,p,state,store}=setup();state.bottom=3000;
 const first=p.shareHost(store);t.handleTimelineWillScroll(10,1,3);
 first.scrollToBottom();fire(32);assert.equal(state.scrolls,0);
 p.shareHost(store).scrollToBottom();fire(32);assert.equal(state.scrolls,1);
});
run(`class Voice {${method(read('pages/chat/VoiceRecordingState'),'sendStoppedVoice')}} globalThis.Voice=Voice;`);
for(const cancelled of [false,true]){
 const {t,p,state,store}=setup();let resolve;store.sendVoiceNoteAsync=()=>new Promise(r=>resolve=r);
 const voice=new c.Voice();Object.assign(voice,{stoppedStore:store,stoppedPath:'voice',stoppedDuration:1,recordingSeq:7,
  host:{store:()=>store,canSend:()=>true,captureAfterSent:()=>p.captureSendFollow(),afterSent:()=>{throw new Error('uncaptured callback');}}});
 voice.sendStoppedVoice(7);if(cancelled)t.handleTimelineWillScroll(10,1,3);
 resolve();await Promise.resolve();fire(32);assert.equal(state.scrolls,cancelled?0:1);
}
tests++;
console.log(`PASS: ${tests} follow geometry/snapshot/ownership/constant-work cases.`);
