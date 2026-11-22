import assert from 'node:assert/strict';
import fs from 'node:fs';
import {ctx,load,root,compiled,ui,data,style,group,layoutCounters} from './test-drawn-text-row.mjs';
for(const f of ['videoVariants','entryVideoVariant','drawnSingleInlineFile','drawnSingleMediaPolicy','drawnAnimationPolicy'])load(root+'util/'+f+'.ets',f==='videoVariants'?['pickInlineSource','pickInlineVariant','playableVariants']:f==='drawnSingleInlineFile'?['DrawnSingleInlineFile']:f==='drawnSingleMediaPolicy'?['drawnSingleMediaEligible']:[]);
for(const f of ['DrawnAlbumGridLayout','DrawnSingleMediaGeometry','DrawnMediaLayout','DrawnSingleMediaLayout'])load(root+'pages/chat/'+f+'.ets',f==='DrawnSingleMediaLayout'?['DrawnSingleMediaLayouts']:[]);
function single(caption='',video=false){const g=group(caption);Object.assign(g.head,{contentType:video?'video':'photo',isAnimation:false,photoFileId:5,photoWidth:200,photoHeight:1000,photoPath:'',photoMini:'',photoProgress:0,photoFailed:false,videoVariants:[],videoFileId:video?7:0,videoFileSize:1000,videoPath:'',videoProgress:0,videoDuration:12,videoFileName:''});return g;}
let cases=0;
for(const type of [false,true])for(const width of [180,260,400,800])for(const ratio of [.05,.2,.5,1,2,10])for(const caption of ['','short','multi link text and body '.repeat(8)])for(const isGroup of [false,true]){
 const g=single(caption,type);g.head.photoWidth=1000*ratio;const d={...data,contentWidth:width,isGroup};
 const p=new ctx.DrawnSingleMediaLayouts().prepare(ui,g,d,style);assert.ok(p);assert.equal(p.tiles.length,1);assert.equal(p.tiles[0].opaque,false);
 assert.ok(p.grid.x>=p.bubbleX);assert.ok(p.grid.x+p.grid.width<=p.width+1e-6);assert.ok(p.grid.y+p.grid.height<=p.height);
 assert.ok(p.footerX>=p.bubbleX);assert.ok(p.footerY>=0);assert.ok(p.footerY+p.statusSize<=p.height+1e-6);
 if(p.caption)assert.ok(p.captionX+p.caption.widthVp<=p.width+1e-6);
 if(p.onMedia)assert.ok(p.footerX+p.footerWidth<=p.grid.x+p.grid.width);
 cases++;
}
const g=single('caption with two links https://a.test https://b.test',true),cache=new ctx.DrawnSingleMediaLayouts();
let p=cache.prepare(ui,g,data,style);const before=layoutCounters(),body=p.caption;
for(let i=0;i<1000;i++){g.head.videoProgress=i%100;const next=cache.prepare(ui,g,{...data,playSlotKey:i%2?'10:-1':'',playSlotStartMs:i},style);assert.equal(next,p);}
assert.deepEqual(layoutCounters(),before,'play slot/progress must not build paragraphs, outlines or scan lines');
const refreshed={...g,head:{...g.head,photoPath:'/new'}};p=cache.prepare(ui,refreshed,data,style);assert.equal(p.caption,body);assert.equal(layoutCounters().bodyLayouts,before.bodyLayouts);
assert.equal(ctx.drawnSingleMediaEligible(g,false,false),true);assert.equal(ctx.drawnSingleMediaEligible(g,true,false),true);
assert.equal(ctx.drawnSingleMediaEligible({...g,head:{...g.head,isAnimation:true}},false,false),true);
// Differential: linear selector preserves duplicate heights, codec filtering,
// unknown sizes, original-file exclusion and cached-original preference.
let seed=7654321;const rand=n=>{seed=(Math.imul(seed,1664525)+1013904223)>>>0;return seed%n;};
for(let t=0;t<10000;t++){
 const original={fileId:1,width:[0,100,360,720,1080][rand(5)],height:[0,240,480,1080][rand(4)],size:rand(100),codec:''};
 const alternatives=Array.from({length:rand(20)},()=>({fileId:rand(15),width:[0,100,360,720,1080][rand(5)],height:[0,240,480,1080][rand(4)],size:rand(100)-20,codec:['h264','h265','av1','AV01',''][rand(5)]}));
 for(const local of [false,true])assert.deepEqual(ctx.pickInlineSource(original,alternatives,local),ctx.pickInlineVariant(ctx.playableVariants(original,alternatives),local));
}
let reads=0;const variants=new Proxy(g.head.videoVariants,{get(t,k){if(k===Symbol.iterator)reads++;return Reflect.get(t,k);}});g.head.videoVariants=variants;
const files=new ctx.DrawnSingleInlineFile();files.prepare(g.head);const scans=reads;for(let i=0;i<1000;i++)files.prepare({...g.head,videoProgress:i});assert.equal(reads,scans);
console.log(`PASS: ${cases} single photo/video geometries; 1000 playback/progress updates reuse plan; caption survives image upgrade; 20000 differential variant selections; cached selector has no repeated scan.`);

// Replay the actual HAP-compiled lifecycle, not a test replica.
const progress=[],posters=[],published=[],events=[],localPaths=[];
ctx.progressForOr=(_id,n)=>n;ctx.subscribeProgress=(id,fn)=>{progress.push(fn);return()=>{};};ctx.posterFor=()=>'';
ctx.subscribePoster=(_p,fn)=>{posters.push(fn);return()=>{};};ctx.requestPoster=()=>{};ctx.publishThumbPath=(...args)=>published.push(args);
ctx.chatEnv={langEpoch:0};ctx.formatFileSize=n=>String(n);ctx.formatMediaDuration=n=>String(n);ctx.isLivePhotoVideo=()=>false;
load(root+'pages/chat/DrawnMediaPosition.ets',['DrawnMediaPosition']);
load(root+'pages/chat/PlaySlotChannel.ets',['PlaySlotChannel','PlaySlotBinding','EMPTY_PLAY_SLOT']);
load(compiled+'pages/chat/DrawnSingleMediaVideo.ts',['DrawnSingleMediaVideo']);
const v=Object.create(ctx.DrawnSingleMediaVideo.prototype);const msg={...g.head,videoVariants:[],videoPath:'/a',videoProgress:0};
Object.assign(v,{playbackBinding:new ctx.PlaySlotBinding(),playbackState:ctx.EMPTY_PLAY_SLOT,msg,data:{...data,playSlotKey:'10:-1'},actions:new Proxy({},{get:(_,k)=>k==='playback'?undefined:(...a)=>events.push([k,...a])}),slot:{updateLocalPath:p=>localPaths.push(p)},files:new ctx.DrawnSingleInlineFile(),active:false,binding:'',generation:0,observationKey:'',observationEpoch:0,candidateId:0,mediaPosition:new ctx.DrawnMediaPosition(),getUIContext:()=>({getFrameNodeById:()=>({getMeasuredSize:()=>({height:200}),getPositionToWindowWithTransform:()=>({y:200})}),px2vp:n=>n/2}),unsubProgress:null,unsubPoster:null,mediaWidth:200,mediaHeight:300});
v.aboutToAppear();const oldProgress=progress.at(-1),oldPoster=posters.at(-1),oldPosition=v.positionCallback(),oldEnd=v.endedCallback(),oldRatio=v.ratioCallback();
oldProgress(40);assert.equal(v.progress,40);oldPoster('/pa');assert.equal(localPaths.at(-1),'/pa');oldPosition(33);assert.deepEqual(events.at(-1),['onPlaySlotPositionChanged',10,-1,33]);
const subscriptionCount=progress.length;for(let i=0;i<1000;i++){v.data={...v.data,playSlotStartMs:i};v.changed();}assert.equal(progress.length,subscriptionCount);
v.msg={...msg,id:20,rowId:20,videoPath:'/b'};v.changed();v.msg=msg;v.changed();const currentEvents=events.length,currentPublish=published.length,currentPaths=localPaths.length;
oldProgress(99);oldPoster('/stale');oldPosition(99);oldEnd();oldRatio(true,.9);assert.equal(events.length,currentEvents);assert.equal(published.length,currentPublish);assert.equal(localPaths.length,currentPaths);assert.equal(v.progress,0);
v.msg={...msg,photoFileId:0};v.changed();posters.at(-1)('/no-file-poster');assert.equal(localPaths.at(-1),'/no-file-poster');assert.equal(published.length,currentPublish);
const pos=v.positionCallback();v.data={...v.data,playSlotKey:''};v.changed();v.data={...v.data,playSlotKey:'10:-1'};v.changed();const n=events.length;pos(999);assert.equal(events.length,n);
const late=posters.at(-1);v.aboutToRecycle();const len=localPaths.length;late('/after-recycle');v.changed();assert.equal(localPaths.length,len);assert.equal(v.binding,'');
assert.match(fs.readFileSync(compiled+'pages/chat/DrawnMessageRow.ts','utf8'),/new SenderAnimatedLayer\(/);
assert.match(fs.readFileSync(compiled+'pages/chat/ReusableMessageBubble.ts','utf8'),/new DrawnMessageRow\(this,\s*\{\s*kind: 'single'/);
console.log('PASS: compiled single video callbacks reject A/B/A, detached and expired playback-slot events; stable subscription; fileId=0 generated poster; single transition route and local animated avatar mounted.');

load(root+'util/animationSlotPool.ets');
const animations=[],gates=[],parks=[],broken=[],timers=[];
ctx.senderChannelKey=(id,user)=>`${id}:${user}`;ctx.senderAnimationFor=()=>'/avatar-video';
ctx.subscribeSenderAnimation=(_key,fn)=>{animations.push(fn);return()=>{};};ctx.requestSenderAnimation=()=>{};
ctx.subscribeChatAnimationGate=fn=>{gates.push(fn);fn(false);return()=>{};};
ctx.subscribeSenderAnimationPark=fn=>{parks.push(fn);fn(false);return()=>{};};
ctx.markSenderAnimationBroken=k=>broken.push(k);ctx.logW=()=>{};
ctx.setTimeout=fn=>{timers.push(fn);return timers.length;};ctx.clearTimeout=()=>{};
load(compiled+'pages/chat/SenderAnimatedLayer.ts',['SenderAnimatedLayer']);
const av=Object.create(ctx.SenderAnimatedLayer.prototype);
Object.assign(av,{senderId:1,senderIsUser:true,avatarSize:38,videoPath:'',holding:false,gateSuspended:false,parked:false,shown:false,visible:true,
 disposed:true,attachmentEpoch:0,playbackEpoch:0,playbackKey:'',attachedKey:'',holdingKey:'',unsubPath:null,unsubGate:null,unsubPark:null,
 cancelWait:null,sameSenderWake:null,parkTimer:-1,env:{animatedAvatar:true,powerSaving:false,screenHeightVp:1000,keyboardHeightVp:0},
 getUIContext:()=>({px2vp:n=>n,getComponentUtils:()=>({getRectangleById:()=>({size:{height:38},windowOffset:{y:300}})})})});
av.aboutToAppear();assert.equal(av.holding,true);const working=av.workingCallback(),failure=av.failedCallback(),pathCallback=animations.at(-1),visibleCallback=av.visibleCallback();
working();assert.equal(av.shown,true);parks.at(-1)(true);const parkedTimer=timers.at(-1);
av.senderId=2;av.onSenderChanged();av.senderId=1;av.onSenderChanged();assert.equal(av.holding,true);assert.equal(av.shown,false);
working();failure();pathCallback('/stale-avatar');visibleCallback(false,0);parkedTimer();
assert.equal(av.shown,false);assert.equal(av.videoPath,'/avatar-video');assert.equal(broken.length,0);assert.equal(av.visible,true);assert.equal(av.parked,false);
const currentWork=av.workingCallback();av.releaseSlot();av.evaluate();currentWork();assert.equal(av.shown,false,'released and reacquired native session cannot accept old onWorking');
av.workingCallback()();assert.equal(av.shown,true);
av.aboutToRecycle();const count=animations.length;av.onSenderChanged();assert.equal(animations.length,count);assert.equal(av.attachedKey,'');
av.aboutToReuse();assert.equal(av.holding,true);av.aboutToDisappear();assert.equal(av.holding,false);
console.log('PASS: compiled dynamic-avatar A/B/A path, visibility, deferred park and native callbacks reject stale deliveries; detached monitors do not allocate; release/reacquire guards preserve static cover.');

v.msg=msg;v.sendState='sent';v.aboutToAppear();
const beforeUpload=v.ratioCallback(),beforeUploadPosition=v.positionCallback(),subsBeforeUpload=progress.length;
v.sendState='sending';v.changed();assert.equal(v.playing(),false);assert.equal(v.candidateId,0);
const uploadingEvents=events.length;beforeUpload(true,.9);beforeUploadPosition(111);v.ratioCallback()(true,.9);
assert.equal(events.length,uploadingEvents);assert.equal(progress.length,subsBeforeUpload);
v.sendState='sent';v.changed();assert.equal(v.candidateId,msg.id);assert.equal(progress.length,subsBeforeUpload);
v.ratioCallback()(true,.9);assert.equal(events.at(-1)[0],'onMediaRatio');v.aboutToRecycle();
assert.equal(ctx.drawnSingleMediaEligible({...g,head:{...g.head,sendState:'sending'}},false,false),true);
console.log('PASS: uploading keeps subscriptions, releases playback candidate, rejects stale playback, resumes after send.');

// The compiled single-video overlay uses the same retained meta/live painter as
// albums and a local control surface; progress must not recreate player hosts.
const created=[],videoChildren=[],badgeStates=[],decorations=[];let renderId=0;
for(const name of ['Stack','If','Row','Circle','Progress','LoadingProgress','Text','SymbolGlyph'])ctx[name]=new Proxy({}, {get:(_t,k)=>(..._args)=>{if(k.startsWith('create'))created.push(name);}});
class VideoChild {constructor(_parent,params){this.params=params;videoChildren.push(params);}}
ctx.DrawnLoadingSpinner=VideoChild;ctx.VideoBubbleSurface=VideoChild;ctx.SmartLoopVideo=VideoChild;ctx.ViewV2.create=()=>{};
ctx.textMeasureEnvironment={epoch:1};ctx.PLAY_SLOT_KEEP_RATIO=.4;ctx.PLAY_SLOT_ENTER_RATIO=.6;
v.badgePainter={bind:(_ui,_env,size,state,percent)=>{badgeStates.push({size,state,percent});return v.badgePainter;}};
v.decoration={bind:(...args)=>{decorations.push(args);return v.decoration;}};
Object.assign(v,{getUIContext:()=>ui,observeComponentCreation2:fn=>fn(++renderId,true),ifElseBranchUpdateFunction:(_i,fn)=>fn(),mediaWidth:240,mediaHeight:180,thumbReady:true,poster:'',progress:0,env:{appearanceEpoch:1,langEpoch:1},data:{...data,animationPlaybackFailed:false},msg:{...msg,videoPath:'',videoFileId:7,videoFailed:false,isAnimation:false,videoDuration:12,videoFileSize:1000}});
v.playing=()=>false;Object.defineProperty(v,'animationPlaying',{value:false,configurable:true});Object.defineProperty(v,'downloadExpected',{value:false,configurable:true});
function renderVideo(){created.length=0;videoChildren.length=0;badgeStates.length=0;v.initialRender();for(const name of ['Circle','Progress','LoadingProgress','Text','SymbolGlyph'])assert.equal(created.includes(name),false,name);}
renderVideo();assert.equal(badgeStates[0].state,'play');assert.equal(decorations.at(-1)[4],false,'single center icon has its own state surface');
v.progress=25;renderVideo();assert.equal(badgeStates[0].state,'download');assert.equal(badgeStates[0].percent,25);
v.progress=0;v.msg={...v.msg,videoFailed:true};renderVideo();assert.equal(badgeStates[0].state,'retry');
v.msg={...v.msg,videoFailed:false,videoFileId:0};renderVideo();assert.equal(badgeStates[0].state,'warning');
Object.defineProperty(v,'downloadExpected',{value:true,configurable:true});renderVideo();assert.equal(badgeStates[0].state,'wait');assert.ok(videoChildren.some(p=>p.ringSize>0));
ctx.isLivePhotoVideo=()=>true;renderVideo();assert.equal(badgeStates.length,0);assert.equal(decorations.at(-1)[6],'cp_live_photo');
console.log('PASS: compiled single-video play/download/retry/unavailable/wait/live overlays use retained Canvas decoration without native static controls.');
