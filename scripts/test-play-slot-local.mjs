// Real controller/channel and HAP-compiled media lifecycles; fake time/native
// surfaces verify ordering and isolation, not real-device frame durations.
import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
const ts=(await import(process.env.TYPESCRIPT_MODULE||'typescript')).default;
const root='entry/src/main/ets/',compiled='entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/'+root;
let now=1000,serial=0;const timers=new Map();
class View {initParam(k,v){this[k]=v;}finalizeConstruction(){}resetParam(k,v){this[k]=v;}resetMonitorsOnReuse(){}resetComputed(){} }
const ctx=vm.createContext({ViewV2:View,ViewPU:View,Date:{now:()=>now},logW:()=>{},
 setTimeout:(fn,ms)=>{const id=++serial;timers.set(id,{at:now+ms,fn});return id;},clearTimeout:id=>timers.delete(id),
 DrawnSingleVideoBadge:class{},DrawnVideoDecoration:class{},DrawnSingleInlineFile:class{prepare(m){return {fileId:m.videoFileId,fileSize:1};}},
 DrawnVideoMetaMemo:class{},chatEnv:{langEpoch:0},a11yRuntimeState:{active:false},progressForOr:(_id,n)=>n,
 subscribeProgress:()=>()=>{},subscribePoster:()=>()=>{},subscribeThumbPath:()=>()=>{},thumbPathFor:()=>'',posterFor:()=>'',requestPoster:()=>{},publishThumbPath:()=>{},
 drawnAnimationPlaying:()=>false,drawnAnimationDownloadExpected:()=>false,
 drawnStageMetrics:{skip(){},begin(){return false;},end(){}},DrawnStage:{VideoAttach:1}});
function load(file,names){const s=fs.readFileSync(file,'utf8').replace(/^import\s[\s\S]*?;\r?\n/gm,'')
 .replace(/@(?:Require|Param|Local|Computed|Event|ObservedV2|Trace)\s*/g,'').replace(/@Monitor\([^)]*\)\s*/g,'').replace(/\bexport /g,'');
 vm.runInContext(ts.transpileModule(s+names.map(n=>`\nglobalThis.${n}=${n};`).join(''),{compilerOptions:{target:ts.ScriptTarget.ES2020}}).outputText,ctx,{filename:file});}
for(const [f,n]of [['playSlot',['slotKey','slotKeyMessageId']],['PlaySlotRegistry',['PlaySlotRegistry']],['PlaySlotDriver',['PlaySlotDriver']],['PlaySlotChannel',['PlaySlotChannel','PlaySlotBinding','EMPTY_PLAY_SLOT']],['DrawnMediaPosition',['DrawnMediaPosition']]])load(root+'pages/chat/'+f+'.ets',n);
function advance(ms){const end=now+ms;let budget=10000;while(true){let next;for(const [id,t]of timers)if(t.at<=end&&(!next||t.at<next[1].at))next=[id,t];if(!next)break;assert.ok(--budget>0);now=next[1].at;timers.delete(next[0]);next[1].fn();}now=end;}
function driver(){timers.clear();const d=new ctx.PlaySlotDriver(),changes=[],state={visible:true,viewer:0,enabled:true};
 d.bind({viewerMsgId:()=>state.viewer,pageVisible:()=>state.visible,competeEnabled:()=>state.enabled,sizeAllowed:()=>true,applySlot:(key,ms)=>changes.push([key,ms])});d.subscribe();return {d,changes,state};}
{
 const {d,changes}=driver();d.setScrolling(true);d.reportMedia(1,-1,.9,200);advance(5000);d.armSettle();assert.equal(changes.length,0);
 d.setScrolling(false);advance(399);d.armSettle();assert.equal(changes.length,0);advance(1);assert.deepEqual(changes,[['1:-1',0]]);
 d.setScrolling(true);d.reportMedia(2,0,.9,200);d.reportMedia(1,-1,0,0);assert.deepEqual(changes.at(-1),['',0],'offscreen incumbent releases immediately');
 advance(2000);d.setScrolling(false);advance(300);d.setScrolling(true);advance(500);assert.equal(changes.length,2);
 d.setScrolling(false);advance(399);d.setScrolling(false);assert.equal(changes.length,2);advance(1);assert.deepEqual(changes.at(-1),['2:0',0],'second stop resets full 400ms; duplicate stop does not extend');d.dispose();
}
for(const action of ['suspend','onPolicyDisabled','dispose','viewer']){
 const {d,changes,state}=driver();d.setScrolling(true);d.reportMedia(1,-1,.9,100);advance(1000);d.setScrolling(false);advance(100);
 if(action==='viewer'){state.viewer=1;d.handoffToViewer(1);}else d[action]();advance(1000);assert.equal(changes.length,0,action+' cancels pending start');assert.equal(timers.size,0);
}
{
 const {d,changes,state}=driver();d.reportMedia(8,2,.9,100);advance(410);d.recordPosition(8,1234);
 state.viewer=8;assert.equal(d.handoffToViewer(8),1234);d.handoffFromViewer(8,2,3456);state.viewer=0;d.armSettle();assert.deepEqual(changes.at(-1),['8:2',3456]);
 state.visible=false;d.suspend();d.armSettle();advance(1000);assert.deepEqual(changes.at(-1),['',0]);state.visible=true;d.armSettle();advance(399);assert.equal(changes.at(-1)[0],'');advance(11);assert.deepEqual(changes.at(-1),['8:2',3456]);d.dispose();
}
{
 const {d,changes,state}=driver();d.setScrolling(true);state.enabled=false;d.onPolicyDisabled();advance(1000);
 state.enabled=true;d.reportMedia(9,-1,.9,100);advance(1000);d.armSettle();assert.equal(changes.length,0,'policy toggles cannot erase ongoing scrolling');
 d.setScrolling(false);advance(399);assert.equal(changes.length,0);advance(1);assert.deepEqual(changes.at(-1),['9:-1',0]);d.dispose();
}
console.log('PASS: scrolling never starts/switches players; stop+399ms blocked, +400ms starts; restart/duplicate-stop, immediate offscreen release, hide/viewer/policy/dispose cancellation and viewer position resume.');
const channel=new ctx.PlaySlotChannel(),deliveries=[],unsubs=[];
for(let i=0;i<10000;i++)unsubs.push(channel.subscribe(String(i),s=>deliveries.push([i,s.key,s.startMs,s.muted])));
channel.publish('1',10);channel.publish('2',20);assert.deepEqual(deliveries,[[1,'1',10,true],[1,'',0,true],[2,'2',20,true]]);
channel.publish('2',20);assert.equal(deliveries.length,3);channel.setMuted(false);assert.equal(deliveries.length,4);assert.deepEqual(deliveries.at(-1),[2,'2',20,false]);
for(const off of unsubs)off();assert.equal(channel.listeners.size,0);channel.publish('3',0);assert.equal(deliveries.length,4);
const reentrant=new ctx.PlaySlotChannel(),nested=[];
reentrant.subscribe('a',s=>{nested.push(s.key);if(!s.key)reentrant.publish('c',30);});reentrant.subscribe('b',s=>nested.push('b:'+s.key));reentrant.subscribe('c',s=>nested.push('c:'+s.startMs));
reentrant.publish('a',0);reentrant.publish('b',20);assert.deepEqual(nested,['a','','b:','c:30']);assert.equal(reentrant.read('b'),ctx.EMPTY_PLAY_SLOT);
const binding=new ctx.PlaySlotBinding();let local=ctx.EMPTY_PLAY_SLOT;binding.bind(channel,'3',s=>local=s);assert.equal(binding.read(channel,'3',local).key,'3');
const held=local;binding.bind(channel,'4',s=>local=s);assert.equal(binding.read(channel,'3',held),ctx.EMPTY_PLAY_SLOT);channel.publish('3',10);assert.equal(local,ctx.EMPTY_PLAY_SLOT);
binding.clear();assert.equal(channel.listeners.size,0);
console.log('PASS: 10000 unrelated keys receive no broadcasts; old/new-only, muted/no-op, reentrancy, stale binding and unsubscribe cleanup.');
load(compiled+'pages/chat/DrawnSingleMediaVideo.ts',['DrawnSingleMediaVideo']);
load(compiled+'pages/chat/DrawnAlbumVideo.ts',['DrawnAlbumVideo']);
const playback=new ctx.PlaySlotChannel(),events=[];
const actions={playback,onMediaGone:(...a)=>events.push(['gone',...a]),onMediaRatio:(...a)=>events.push(['ratio',...a]),onPlaySlotPositionChanged:(...a)=>events.push(['position',...a]),onPlaySlotEnded:(...a)=>events.push(['end',...a])};
View.prototype.getUIContext=()=>({px2vp:n=>n,getFrameNodeById:()=>({getMeasuredSize:()=>({height:100}),getPositionToWindowWithTransform:()=>({y:100})})});
const msg={id:10,rowId:10,isAnimation:false,videoFileId:7,photoFileId:5,videoPath:'',videoProgress:0,videoFileSize:1};
const data=Object.freeze({chatId:1,playSlotKey:'',playSlotStartMs:0,autoplayMuted:true});
const single=new ctx.DrawnSingleMediaVideo(null,{msg,data,actions,mediaWidth:100,mediaHeight:100});
const cell=Object.freeze({chatId:1,messageId:20,idx:1,width:100,height:100,isVideo:true,videoFileId:8,inlineFileId:8,thumbFileId:9,thumbPath:'',isPlaySlot:false,playSlotStartMs:0});
const album=new ctx.DrawnAlbumVideo(null,{cell,actions});
const initialRatio=single.ratioCallback(),initialAlbumRatio=album.ratioCallback(cell);
single.aboutToAppear();album.aboutToAppear();initialRatio(true,.9);initialAlbumRatio(true,.9);assert.deepEqual(events.slice(-2).map(e=>e[0]),['ratio','ratio'],'pre-appear visibility survives empty initial bind');
playback.publish('10:-1',222,false);assert.equal(single.playing(),true);assert.equal(single.startPosition(),222);assert.equal(single.localPlayback().muted,false);assert.equal(album.playing(),false);
const oldSingle=single.positionCallback();oldSingle(333);assert.deepEqual(events.at(-1),['position',10,-1,333]);
playback.publish('20:1',444);assert.equal(single.playing(),false);assert.equal(album.playing(),true);assert.equal(album.startPosition(),444);
const oldAlbum=album.positionCallback(cell);oldAlbum(555);assert.deepEqual(events.at(-1),['position',20,1,555]);
for(let i=0;i<1000;i++)playback.publish(i%2?'20:1':'10:-1',i);
assert.equal(single.data,data);assert.equal(single.msg,msg);assert.equal(album.currentCell,cell,'local transitions never replace immutable row/cell input');
playback.publish('10:-1',222);let n=events.length;oldSingle(999);oldAlbum(999);assert.equal(events.length,n,'A/B/A rejects old player callbacks without parent Monitor');
const fresh=single.positionCallback();playback.publish('',0);playback.publish('10:-1',222);n=events.length;fresh(999);assert.equal(events.length,n,'off/on rejects old player generation');
single.playbackState=ctx.EMPTY_PLAY_SLOT;single.aboutToReuse();assert.equal(single.playing(),true,'same binding reseeds reuse-reset Local');
const current=single.positionCallback();single.msg={...msg,id:11,rowId:11};n=events.length;current(999);assert.equal(events.length,n,'source changed before Monitor');single.changed();assert.equal(single.playing(),false);
playback.publish('20:1',100);const albumPosition=album.positionCallback(cell);album.content={cell:undefined};n=events.length;albumPosition(999);assert.equal(events.length,n,'staged empty source rejects late callback before Monitor');album.changed();assert.equal(album.playing(),false);
album.content={cell};album.changed();assert.equal(album.playing(),true);const late=album.endedCallback(cell);single.aboutToRecycle();album.aboutToRecycle();n=events.length;late();assert.equal(events.length,n);assert.equal(playback.listeners.size,0,'recycle releases both subscriptions');
console.log('PASS: real compiled single/album receive playback locally; initial visibility, atomic seek/mute, 1000 switches, A/B/A, off/on, reuse reseed, source-before-Monitor and recycle guards.');
// Use real layout cache to ensure channel delivery does not dirty row inputs.
const h=await import('./test-drawn-text-row.mjs');
const g=h.group('caption and https://example.test'),layout=new h.ctx.DrawnTextLayouts(),p=layout.prepare(h.ui,g,h.data,h.style),before=h.layoutCounters();
for(let i=0;i<1000;i++){channel.publish(String(i%3),i);assert.equal(layout.prepare(h.ui,g,h.data,h.style),p);}
assert.deepEqual(h.layoutCounters(),before);
let scans=0;const videoFlags=[false,true];videoFlags.some=new Proxy(videoFlags.some,{apply(fn,that,args){scans++;return Reflect.apply(fn,that,args);}});
const videoGroup={head:{videoFileId:0},photoIsVideo:videoFlags};
for(let i=0;i<1000;i++)assert.equal(h.ctx.drawnLiveSurface(videoGroup,{playSlotKey:''},true),true);
assert.equal(scans,1,'video snapshot safety scans immutable album once, not per paint');
console.log('PASS: 1000 switches reuse real paragraph/geometry caches; native-video snapshot safety has one scan per immutable album.');
