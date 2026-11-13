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
    .replace(/@(?:Require|Param|Local|Computed|Event)\s*/g,'').replace(/@Monitor\([^)]*\)\s*/g,'').replace(/\bexport /g,'');
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
load(compiled+'pages/chat/DrawnAlbumVideo.ts',['DrawnAlbumVideo']);
const events=[],actions=new Proxy({}, {get:(_t,k)=>(...args)=>events.push([k,...args])});
const cell={chatId:1,messageId:10,idx:2,width:150,height:100,isVideo:true,isLive:false,isPlaySlot:true,videoFileId:8,inlineFileId:9,videoFileSize:30,videoDuration:2};
const video=new context.DrawnAlbumVideo(null,{cell,actions});
// Callbacks can be installed before aboutToAppear, as in native initialRender.
const ratio=video.ratioCallback(cell),area=video.areaCallback(cell),position=video.positionCallback(cell),ended=video.endedCallback(cell);
ratio(true,.9);assert.equal(events.length,0);video.aboutToAppear();
area({}, {globalPosition:{y:200},height:100});ratio(true,.9);assert.deepEqual(events.at(-1),['onMediaRatio',10,2,.9,250]);
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
