// Actual production methods; native drawing is stubbed to count work, not to
// predict device frame time. Requires a successful HAP build first.
import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
const ts = (await import(process.env.TYPESCRIPT_MODULE || 'typescript')).default;
const root = 'entry/src/main/ets/';
const compiled = 'entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/' + root;
let paths = 0, invalidations = 0, draws = 0;
class View { initParam(k,v) { this[k]=v; } finalizeConstruction(){} }
const context = vm.createContext({ViewV2:View,ViewPU:View,
  DrawModifier:class {invalidate(){invalidations++;}},
  drawing:{Path:class {buildFromSvgString(s){this.svg=s;paths++;return true;}},
    Brush:class {setAntiAlias(){}setColor(){}setMaskFilter(){}},
    MaskFilter:{createBlurMaskFilter:()=>({})},BlurType:{NORMAL:0}},
  drawnColor:c=>c, chatEnv:{langEpoch:1}, slotKey:(id,i)=>`${id}:${i}`,
  formatFileSize:n=>`${n}B`, formatMediaDuration:n=>`${n}s`,
  textMeasureEnvironment:{epoch:1},str:x=>x
});
function load(path,names) {
  let text=fs.readFileSync(path,'utf8').replace(/^import\s[\s\S]*?;\r?\n/gm,'')
    .replace(/@(?:Require|Param|Local|Computed|Event|ObservedV2|Trace)\s*/g,'').replace(/@Monitor\([^)]*\)\s*/g,'').replace(/\bexport /g,'');
  vm.runInContext(ts.transpileModule(text+names.map(n=>`\nglobalThis.${n}=${n};`).join(''),
    {compilerOptions:{target:ts.ScriptTarget.ES2020}}).outputText,context,{filename:path});
}
for(const file of ['bubbleCornerInset','bubbleGlassPath','reactionsWidth','drawnContentPolicy'])load(root+'util/'+file+'.ets',[]);
load(root+'pages/chat/DrawnContentOutline.ets',['DrawnContentOutline']);
const outline=new context.DrawnContentOutline(),corners={topLeft:15,topRight:15,bottomLeft:15,bottomRight:15};
const canvas={save(){},translate(){},attachBrush(){},drawPath(){draws++;},detachBrush(){},restore(){}};
const frame={sizeInPixel:{width:400,height:180},canvas};
outline.bind(false,true,corners,'#fff','1',false,2);outline.drawBehind(frame);
const svg=outline.path.svg;
assert.equal(svg,context.glassBubbleCommands(200,90,false,true,15,15,15,15,8,12,2,0,7));
for(let i=0;i<1000;i++){outline.bind(false,true,corners,'#fff','1',false,2);outline.drawBehind(frame);}
assert.equal(paths,1);assert.equal(invalidations,1);assert.equal(draws,1001);
outline.bind(false,true,corners,'#000','2',true,2);outline.drawBehind(frame);assert.equal(paths,1);
frame.sizeInPixel.width=420;outline.drawBehind(frame);assert.equal(paths,2);
outline.bind(false,true,corners,'#000','2',true,3);outline.drawBehind(frame);assert.equal(paths,3);
const resourceA={id:1},resourceB={id:2};
outline.bind(false,true,corners,resourceA,'2',true,3);assert.equal(outline.fill,resourceA);
outline.bind(true,true,corners,resourceB,'2',true,3);assert.equal(outline.fill,resourceB);
outline.bind(true,true,corners,123,'2',true,3);assert.equal(outline.fill,123);
console.log('PASS: 1000 unchanged paints build no additional paths; appearance/shadow retain geometry; dimensions/density invalidate once.');

context.DrawnVideoDecoration=class {};context.a11yRuntimeState={active:false};
load(root+'pages/chat/DrawnVideoMeta.ets',['drawnVideoMetaCache']);
load(root+'util/drawnStageMetrics.ets',['drawnStageMetrics','DrawnStage']);
load(root+'util/mediaThumbChannel.ets',['publishThumbPath','subscribeThumbPath','thumbPathFor']);
load(root+'pages/chat/DrawnMediaPosition.ets',['DrawnMediaPosition']);
load(compiled+'pages/chat/DrawnAlbumVideo.ts',['DrawnAlbumVideo']);
let positionReads=0, geometryTop=200;
const geometryUi={getFrameNodeById:()=>{positionReads++;return {getMeasuredSize:()=>({height:200}),getPositionToWindowWithTransform:()=>({y:geometryTop})};},px2vp:n=>n/2};
View.prototype.getUIContext=()=>geometryUi;
const events=[],actions=new Proxy({}, {get:(_t,k)=>(...args)=>events.push([k,...args])});
const cell={chatId:1,messageId:10,idx:2,width:150,height:100,isVideo:true,isLive:false,isPlaySlot:true,videoFileId:8,inlineFileId:9,videoFileSize:30,videoDuration:2};
const video=new context.DrawnAlbumVideo(null,{cell,actions});
// Callbacks can be installed before aboutToAppear, as in native initialRender.
const ratio=video.ratioCallback(cell),position=video.positionCallback(cell),ended=video.endedCallback(cell);
ratio(true,.9);assert.equal(events.length,0);assert.equal(positionReads,0);video.aboutToAppear();
ratio(true,.9);assert.deepEqual(events.at(-1),['onMediaRatio',10,2,.9,250]);
position(200);assert.deepEqual(events.at(-1),['onPlaySlotPositionChanged',10,2,200]);
ended();assert.deepEqual(events.at(-1),['onPlaySlotEnded',10,2]);
assert.equal(video.meta,'2s · 30B');
video.cell={...cell,messageId:11};video.changed();video.cell=cell;video.changed();
let count=events.length;ratio(true,1);position(400);ended();assert.equal(events.length,count,'A/B/A rejects original callback');
const removed=video.ratioCallback(cell);video.cell=undefined;video.changed();video.cell=cell;video.changed();
count=events.length;removed(true,1);assert.equal(events.length,count,'A/undefined/A rejects original callback');
const resize=video.ratioCallback(cell);video.cell={...cell,width:160};video.changed();count=events.length;resize(true,1);assert.equal(events.length,count);
const oldPlayer=video.positionCallback(video.cell);video.cell={...video.cell,isPlaySlot:false};
count=events.length;oldPlayer(99);assert.equal(events.length,count,'slot change rejected even before monitor');video.changed();
const retired=video.ratioCallback(video.cell);video.aboutToRecycle();count=events.length;retired(true,1);assert.equal(events.length,count);
const fresh=video.ratioCallback(video.cell);video.aboutToReuse();fresh(true,.5);assert.equal(events.at(-1)[0],'onMediaRatio');
console.log('PASS: mixed-video pre-appear, position/end/ratio, A/B/A, removal, resize, slot change, recycle/reuse callbacks.');

load(compiled+'pages/chat/BubbleContentLayout.ts',['BubbleContentLayout']);
const content=Object.create(context.BubbleContentLayout.prototype);
let measure=0,iterations=0;
const reactions=[{emoji:'x',customEmojiId:'',count:3},{emoji:'',customEmojiId:'1',count:5}];
reactions[Symbol.iterator]=function*(){iterations++;yield* Array.prototype.values.call(this);};
Object.assign(content,{msg:{reactions,editDate:0,isOutgoing:false},context:{liveViews:''},env:{langEpoch:1,appearanceEpoch:1},
  textMeasureCache:{prepare(){}},inlineMaxW:()=>250,reactorsArrowShown:()=>false,messageTimeText:()=> '12:34',
  measureTextVp:(s,n)=>{measure++;return s.length*n/2;}});
const width=content.reactionsRowWidth(),reads=measure;
for(let i=0;i<1000;i++)assert.equal(content.reactionsRowWidth(),width);
assert.equal(iterations,1);assert.equal(measure,reads);
content.msg={...content.msg,reactions:[...reactions,{emoji:'z',customEmojiId:'',count:20}]};
assert.ok(content.reactionsRowWidth()>width);assert.ok(measure>reads);
const viewsReads=measure;content.context.liveViews='1K';content.reactionsRowWidth();assert.ok(measure>viewsReads);
console.log('PASS: reaction-width memo hits perform no traversal/measurement; replacement and footer changes invalidate.');

const progress=[],posters=[],published=[];
for(const name of ['LegacySingleMediaBubble','LegacyAlbumMessageBubble','LegacyTextMessageBubble','MessageBubble']) {
  const source=fs.readFileSync(compiled+'pages/chat/'+name+'.ts','utf8');
  assert.match(source,/new DrawnContentRow\(/);assert.doesNotMatch(source,/new MessageBubbleShell\(/);
}
assert.equal(context.drawnContentEligible('photo',false),true);
for(const type of ['text','video','file','richMessage'])assert.equal(context.drawnContentEligible(type,false),true);
for(const type of ['system','hidden','emoji','sticker','customEmoji','videoNote','dice'])assert.equal(context.drawnContentEligible(type,false),false);
assert.equal(context.drawnContentEligible('photo',true),false);
const ids=new Proxy(Array.from({length:1000},(_,i)=>i+1),{get(t,k){if(typeof k==='string'&&/^\d+$/.test(k))indexed++;return t[k];}});
let indexed=0;const group={head:{id:1,isAnimation:false},memberIds:ids,videoFileIds:Array(1000).fill(9)};
assert.equal(context.drawnLiveSurface(group,{playSlotKey:'1000:999'}),true);assert.equal(indexed,1);
assert.equal(context.drawnLiveSurface(group,{playSlotKey:'1000:998'}),false);
console.log('PASS: four compiled entries use new content row; material/bare compatibility stays; slot lookup reads one member index.');

video.cell={...cell,uploading:true};video.sendState='sending';video.changed();
assert.equal(video.uploading(),true);assert.equal(video.attachedId,0);
const duringUpload=video.ratioCallback(video.cell);const beforeUpload=events.length;
duringUpload(true,1);assert.equal(events.length,beforeUpload);
video.sendState='sent';video.changed();assert.equal(video.uploading(),false,'live state overrides stale album snapshot');
assert.equal(video.attachedId,cell.messageId);duringUpload(true,1);assert.equal(events.length,beforeUpload);
video.ratioCallback(video.cell)(true,.9);assert.equal(events.at(-1)[0],'onMediaRatio');video.aboutToRecycle();
console.log('PASS: album live send state suppresses upload playback, overrides stale snapshots after completion, rejects old visibility callbacks.');

// A stable publication channel is read by the video child, not copied through
// its parent. Exercise real compiled callback guards before Monitor delivery.
load(root+'pages/chat/DrawnSlotContent.ets',['DrawnSlotContent']);
let publish;
const channel=new context.DrawnSlotContent({scheduleContent(callback){publish=callback;}});
const local=new context.DrawnAlbumVideo(null,{content:channel,cell,actions});
local.aboutToAppear();
assert.equal(local.currentCell,undefined,'empty channel must not revive a direct legacy payload');
channel.bind(cell,true);local.changed();
assert.equal(local.currentCell,cell);
let callback=local.positionCallback(cell);
const old=events.length;channel.recycle();callback(700);
assert.equal(events.length,old,'late player callback is rejected immediately, before Monitor');
local.changed();
for(let i=0;i<1000;i++){
 const next={...cell,messageId:100+i,isPlaySlot:false};
 channel.bind(next,true);assert.equal(local.currentCell,undefined);publish();local.changed();
 assert.equal(local.currentCell,next);assert.equal(local.content,channel);
 callback=local.ratioCallback(next);
 channel.bind({...next,messageId:2000+i},true);
 const n=events.length;callback(true,.9);assert.equal(events.length,n,'old owner is rejected before the next Monitor');
 publish();local.changed();
}
channel.bind({...cell,uploading:true},true);assert.equal(local.currentCell.uploading,true,'uploads publish immediately');
channel.bind({...cell,isPlaySlot:true},true);assert.equal(local.currentCell.isPlaySlot,true,'playing input publishes immediately');
channel.recycle();local.changed();assert.equal(local.attachedId,0);
local.content=undefined;assert.equal(local.currentCell,cell,'legacy direct-cell entry remains supported');
console.log('PASS: 1000 local publication transfers, synchronous stale callback rejection, empty-channel isolation, immediate upload/play and legacy direct input.');

const albumVideoSource=fs.readFileSync(root+'pages/chat/DrawnAlbumVideo.ets','utf8');
assert.ok(!albumVideoSource.includes("@Monitor('content.cell'"));
assert.ok(albumVideoSource.includes("@Monitor('observedCell', 'sendState')"));
local.content=undefined;assert.equal(local.observedCell,cell);
local.content=channel;assert.equal(local.observedCell,undefined);
channel.bind({...cell,isPlaySlot:true},true);assert.equal(local.observedCell,channel.cell);
console.log('PASS: nullable channel is monitored through a computed root; callbacks retain synchronous current-payload guards.');

// Per-island numeric memo survives recursive reuse without a global LRU lookup.
let metaLookups=0;
const sharedPrepare=context.drawnVideoMetaCache.prepare.bind(context.drawnVideoMetaCache);
context.drawnVideoMetaCache.prepare=(...args)=>{metaLookups++;return sharedPrepare(...args);};
const cachedVideo=new context.DrawnAlbumVideo(null,{cell:{...cell},actions});
cachedVideo.aboutToAppear();const label=cachedVideo.meta,initialLookups=metaLookups;
for(let i=0;i<1000;i++){cachedVideo.aboutToReuse();cachedVideo.changed();assert.equal(cachedVideo.meta,label);}
assert.equal(metaLookups,initialLookups,'1000 warm recursive reuses do not touch the global label LRU');
cachedVideo.cell={...cell,width:80};assert.equal(cachedVideo.meta,'30B');
cachedVideo.cell={...cell,videoDuration:8};assert.equal(cachedVideo.meta,'8s · 30B');
context.chatEnv.langEpoch++;assert.equal(cachedVideo.meta,'8s · 30B');
assert.equal(metaLookups,initialLookups+3,'width category, metadata and language each invalidate once');
cachedVideo.cell=undefined;assert.equal(cachedVideo.meta,'');
cachedVideo.cell={...cell,videoDuration:8};assert.equal(cachedVideo.meta,'8s · 30B');
assert.equal(metaLookups,initialLookups+3,'empty payload does not poison the numeric memo');
const originalGeneration=cachedVideo.generation;cachedVideo.aboutToRecycle();assert.equal(cachedVideo.generationCell,undefined);
assert.ok(cachedVideo.generation>originalGeneration);
// Guard must still invalidate before returning early for an attached same-ID cell.
cachedVideo.cell={...cell};cachedVideo.aboutToReuse();const oldSizeCallback=cachedVideo.ratioCallback(cachedVideo.cell);
cachedVideo.cell={...cell,width:160};cachedVideo.changed();const eventCount=events.length;
oldSizeCallback(true,.9);assert.equal(events.length,eventCount);
// Repeated same immutable input avoids rebuilding its multi-field identity key.
let widthReads=0;const immutableCell=new Proxy({...cell},{get(t,k){if(k==='width')widthReads++;return t[k];}});
cachedVideo.cell=immutableCell;cachedVideo.changed();const afterIdentity=widthReads;
for(let i=0;i<1000;i++){cachedVideo.changed();cachedVideo.aboutToReuse();}
assert.equal(widthReads,afterIdentity,'same-snapshot bind does not regenerate the identity string');
console.log('PASS: numeric video memo, width/language/data invalidation, empty payload, stable identity fast path and stale resize callback protection.');

// Video publication deliberately excludes only four fields owned by other UI.
// Audit the full interface so newly added fields cannot silently be ignored.
const cellInterface = fs.readFileSync(root+'util/albumCellRenderData.ets','utf8').match(/export interface AlbumCellRenderData \{([\s\S]*?)\n\}/)[1];
const fields = [...cellInterface.matchAll(/\s+(\w+): (number|string|boolean);/g)];
const ignored = new Set(['progress','failed','selectionActive','selected']);
const complete = Object.fromEntries(fields.map(([,name,type]) => [name,type==='number'?1:type==='string'?'a':false]));
Object.assign(complete,{isVideo:true,isPlaySlot:false});
const isolated=new context.DrawnSlotContent({scheduleContent(){}});
isolated.bind(complete,false);
let contentWrites=0, current=isolated.cell;
Object.defineProperty(isolated,'cell',{get:()=>current,set:v=>{contentWrites++;current=v;}});
for(let i=0;i<1000;i++) isolated.bind({...complete,progress:i,failed:!!(i%2),selectionActive:true,selected:!!(i%2)},false);
assert.equal(contentWrites,0);assert.equal(isolated.cell,complete);
for(const [,name,type] of fields){
 isolated.bind(complete,false);
 const changed={...complete,[name]:type==='number'?2:type==='string'?'b':!complete[name]};
 isolated.bind(changed,false);
 if(ignored.has(name))assert.equal(isolated.cell,complete,`${name} belongs to another UI`);
 else if(name==='isVideo')assert.equal(isolated.cell,undefined,'photo clears video content');
 else assert.equal(isolated.cell,changed,`${name} must publish`);
}
// Recycling and pending ownership transfers must still replace/clear the input.
isolated.recycle();assert.equal(isolated.cell,undefined);
isolated.bind({...complete,messageId:99},false);assert.equal(isolated.cell.messageId,99);
const videoCode=fs.readFileSync(root+'pages/chat/DrawnAlbumVideo.ets','utf8');
for(const field of ignored)assert.doesNotMatch(videoCode,new RegExp('\\.(?:'+field+')\\b'),'new consumer requires revisiting the filter');
console.log('PASS: video input 1000 progress/selection updates produce zero publications; every other schema field remains live; recycle ownership intact.');

// Fixed diagnostics: disabled reads nothing; enabled preserves no message text.
const metric=context.drawnStageMetrics;metric.reset();metric.setEnabled(false);
metric.rowChanged(0,new Proxy({}, {get(){throw Error('disabled field read');}}),{});
const oldGroup={key:'a',head:{id:1,rowId:1},memberIds:[1],photoFileIds:[7],photoPaths:[''],photoFailed:[false]};
context.hiTraceMeter={HiTraceOutputLevel:{COMMERCIAL:0},startSyncTrace(){},finishSyncTrace(){}};
metric.setEnabled(true);metric.setTraceOutput(false);
metric.rowChanged(0,oldGroup,{...oldGroup,head:{...oldGroup.head,mediaDownloadActive:true},photoPaths:['/new']});
assert.match(metric.summary(),/PG\/change\/list\/thumbnail calls=1/);
assert.match(metric.summary(),/PG\/change\/list\/transfer calls=1/);
assert.doesNotMatch(metric.summary(),/\/new/);
metric.reset();metric.setEnabled(false);assert.equal(metric.summary(),'');
console.log('PASS: row change categories gated O(1) when disabled, separate thumbnail/transfer causes, no message data retained.');

// The actual island reads posters locally while its row/cell snapshot stays old.
const localPosterCell={...cell,thumbFileId:95001,thumbPath:'',isPlaySlot:true};
const island=new context.DrawnAlbumVideo(null,{cell:localPosterCell,actions});
island.aboutToAppear();assert.equal(island.posterPath,'');
context.publishThumbPath(95001,'/fresh-poster');
assert.equal(island.posterPath,'/fresh-poster');assert.equal(island.cell,localPosterCell);
island.changed();assert.equal(island.posterPath,'/fresh-poster','stale parent input cannot roll back delivered poster');
const retainedSubscribe=context.subscribeThumbPath;const callbacks=[];
context.subscribeThumbPath=(id,cb)=>{callbacks.push(cb);return retainedSubscribe(id,cb);};
island.cell={...localPosterCell,messageId:999,thumbFileId:95002};island.changed();
const retiredPoster=callbacks.at(-1);
island.cell={...localPosterCell,messageId:1000,thumbFileId:95003};
retiredPoster('/too-late');assert.notEqual(island.posterPath,'/too-late','input changes before Monitor reject old callback');
island.changed();island.cell={...localPosterCell,messageId:999,thumbFileId:95002};island.changed();
retiredPoster('/old-A');assert.notEqual(island.posterPath,'/old-A','A/B/A generation rejects retired subscription');
island.aboutToRecycle();callbacks.at(-1)('/recycled');assert.equal(island.posterPath,'');
context.publishThumbPath(95002,'/while-offscreen');island.aboutToReuse();assert.equal(island.posterPath,'/while-offscreen');
island.cell={...localPosterCell,thumbFileId:0,thumbPath:'/local'};island.changed();assert.equal(island.posterPath,'/local');
island.cell={...localPosterCell,thumbFileId:0,thumbPath:''};island.changed();assert.equal(island.posterPath,'');
island.aboutToDisappear();context.subscribeThumbPath=retainedSubscribe;
assert.match(albumVideoSource,/posterPath: this.posterPath/);
console.log('PASS: video poster local delivery with unchanged parent, stale input, before-Monitor/A-B-A/recycle guards, cached reuse, fileless replacement and removal.');

// No persistent area listener: position is queried only for live candidates.
assert.doesNotMatch(albumVideoSource,/onAreaChange|areaCallback/);
let beforePosition=positionReads;
for(let i=0;i<1000;i++)ratio(true,.9); // expired original generation
assert.equal(positionReads,beforePosition,'stale callbacks do not enter native geometry');
const probe=new context.DrawnMediaPosition();
assert.equal(probe.center(geometryUi),250,'vp position plus converted px height');
geometryTop=300;assert.equal(probe.center(geometryUi),350,'reads current position without an area callback');
assert.equal(probe.center({...geometryUi,getFrameNodeById:()=>null}),undefined);
assert.equal(probe.center({...geometryUi,getFrameNodeById:()=>({getMeasuredSize:()=>({height:0})})}),undefined);
let geometryErrors=0;context.logW=()=>geometryErrors++;
for(let i=0;i<3;i++)assert.equal(probe.center({...geometryUi,getFrameNodeById:()=>{throw Error('detached');}}),undefined);
assert.equal(geometryErrors,1,'failure logs once and never reuses previous owner coordinates');
assert.notEqual(probe.nodeId,new context.DrawnMediaPosition().nodeId);
console.log('PASS: on-demand geometry uses correct vp/px units, fresh position, unique physical id, no stale callback queries, null/unlaid-out nodes and bounded error logging.');

// An admitted video shell may remain in a photo slot; only the shell survives.
local.content=channel;local.active=true;
channel.bind({...cell,isVideo:true,isPlaySlot:true},true);local.changed();
const beforePhoto=local.positionCallback(local.currentCell), photoEvents=events.length;
channel.bind({...cell,isVideo:false,isLive:false,isPlaySlot:false},true);
assert.equal(channel.cell,undefined);assert.equal(channel.hostReady,true);
beforePhoto(123);assert.equal(events.length,photoEvents,'photo switch rejects late video callback before Monitor');
local.changed();assert.equal(local.attachedId,0);assert.equal(local.posterPath,'');
channel.recycle();assert.equal(channel.hostReady,true,'physical shell eligibility survives recycle');
console.log('PASS: retained video shell clears playback candidate/poster and rejects stale callbacks when reused as a photo.');

// Geometry and readiness follow the physical channel without parent params.
local.content=channel;
channel.setGeometry(123,234);channel.setThumbReady(true);
assert.equal(local.slotWidth,123);assert.equal(local.slotHeight,234);assert.equal(local.slotThumbReady,true);
let presentationWrites=0;
for(const key of ['width','height','thumbReady']) {
 let value=channel[key];
 Object.defineProperty(channel,key,{get(){return value;},set(next){presentationWrites++;value=next;},configurable:true});
}
for(let i=0;i<1000;i++){channel.setGeometry(123,234);channel.setThumbReady(true);}
assert.equal(presentationWrites,0,'equal presentation performs no state writes');
channel.setGeometry(321,432);channel.setThumbReady(false);
assert.equal(presentationWrites,3);assert.equal(local.slotWidth,321);assert.equal(local.slotThumbReady,false);
channel.setThumbReady(true);channel.recycle();assert.equal(local.slotThumbReady,false);
local.content=undefined;local.mediaWidth=55;local.mediaHeight=66;local.thumbReady=true;
assert.equal(local.slotWidth,55);assert.equal(local.slotHeight,66);assert.equal(local.slotThumbReady,true);
console.log('PASS: slot-local geometry/readiness, 1000 equal updates without writes, recycle reset and legacy presentation.');
