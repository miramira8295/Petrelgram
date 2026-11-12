// Exercise production grid preparation and HAP-transpiled component handlers.
// Native metrics/drawing are doubles; no device performance claim is made.
import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
const ts=(await import(process.env.TYPESCRIPT_MODULE || 'typescript')).default;
const root='entry/src/main/ets/';
const compiled='entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/'+root;
let binds=0,recycles=0,disposals=0,slotsCreated=0;
class Slot {
  constructor(notify){this.notify=notify;this.receiver={canDraw:()=>true};this.path='';slotsCreated++;}
  bind(_ui,tile){binds++;const changed=this.path!==tile.cell.thumbPath;this.path=tile.cell.thumbPath;if(changed)this.notify();}
  recycle(){recycles++;}dispose(){disposals++;}showMini(){return false;}
}
class View {initParam(k,v){this[k]=v;}finalizeConstruction(){}getUIContext(){return {vp2px:n=>n*2};}}
const ctx=vm.createContext({FrameCallback:class {},ViewV2:View,ViewPU:View,DrawnImageSlot:Slot,
  slotKey:(id,i)=>`${id}:${i}`,chatEnv:{appearanceEpoch:1,langEpoch:1},scrollPlaceholderState:{active:false},
  DrawnAlbumGridSelection:class {bind(){return this;}},SourceType:{TouchScreen:1,Mouse:2},TouchType:{Down:0,Up:1,Move:2,Cancel:3},
  str:(k,n)=>`${k}:${n}`,thumbBackdropColor:()=> '#aaa',MINI_PLACEHOLDER_BLUR:3});
function load(path,names=[]){const text=fs.readFileSync(path,'utf8').replace(/^import\s[\s\S]*?;\r?\n/gm,'')
  .replace(/@(?:Require|Param|Local|Computed|Event)\s*/g,'').replace(/@Monitor\([^)]*\)\s*/g,'').replace(/\bexport /g,'');
  vm.runInContext(ts.transpileModule(text+names.map(n=>`\nglobalThis.${n}=${n};`).join(''),{compilerOptions:{target:ts.ScriptTarget.ES2020}}).outputText,ctx,{filename:path});}
for(const file of ['packAlbumRows','albumCellRenderData','drawnContentPolicy','drawnAlbumPolicy'])load(root+'util/'+file+'.ets');
load(root+'pages/chat/DrawnAlbumGridLayout.ets',['DrawnAlbumGridLayouts']);
load(root+'util/drawnFrameBatch.ets');load(root+'util/oneShotFrameCallback.ets');
load(root+'pages/chat/DrawnAlbumGridMedia.ets',['DrawnAlbumGridMedia']);
load(compiled+'pages/chat/DrawnAlbumGrid.ts',['DrawnAlbumGrid']);
function group(n=6){return {head:{id:100,rowId:100,isAnimation:false,sendState:'sent',translatedText:'',reactions:[],inlineButtons:[],
  forwardFrom:'',commentCount:0,replyThumbPath:'',replyDiceLayers:[],linkUrl:'',linkTitle:'',linkSiteName:'',linkDescription:'',linkPhotoFileId:0},
  memberIds:Array.from({length:n},(_,i)=>100+i),photoPaths:Array(n).fill('/ready'),photoRatios:Array.from({length:n},(_,i)=>.5+i*.2),
  photoFileIds:Array.from({length:n},(_,i)=>i+10),photoMinis:[],photoProgress:[],photoFailed:[],photoIsVideo:[],photoIsLive:[],
  videoFileIds:[],videoFileSizes:[],videoDurations:[],videoMimeTypes:[],inlineFileIds:[],inlineFileSizes:[],caption:'',captionEntities:[]};}
const data={chatId:3,selectionActive:false,selectedMemberIds:[],playSlotKey:'',autoplayMuted:false,playSlotStartMs:0};
let cases=0;
for(let n=2;n<=10;n++)for(const w of [170,277,480])for(const selection of [false,true]){
  const g=group(n),d={...data,selectionActive:selection,selectedMemberIds:[100,103]};
  const p=new ctx.DrawnAlbumGridLayouts().prepare(g,d,w,2),rows=ctx.packAlbumRows(g.photoRatios,w);
  const cells=rows.flat();assert.equal(p.tiles.length,n);
  for(let i=0;i<n;i++){const t=p.tiles[i];assert.equal(t.width,cells[i].width);assert.equal(t.height,cells[i].height);
    assert.ok(t.x>=0&&t.y>=0&&t.x+t.width<=p.width+.01&&t.y+t.height<=p.height+.01);
    assert.equal(t.cell.selected,d.selectedMemberIds.includes(t.cell.messageId));}
  assert.equal(new Set(p.tiles.map(t=>t.key)).size,n);cases++;
}
const cache=new ctx.DrawnAlbumGridLayouts(),g=group(),first=cache.prepare(g,data,277,2);
// Pure chrome updates preserve every picture input, including all exclusion
// conditions of the full-row painter. No whole grid fallback is allowed.
const changes=[{translatedText:'translation'},{reactions:[{emoji:'ok',count:2}]},{inlineButtons:[[{text:'button'}]]},
 {forwardFrom:'sender'},{commentCount:2},{replyThumbPath:'/quote'},{replyDiceLayers:['/dice']},
 {linkUrl:'https://example.org'},{linkTitle:'title'},{linkSiteName:'site'},{linkDescription:'description'},{linkPhotoFileId:9}];
for(const change of changes){const updated={...g,head:{...g.head,...change},caption:'complex caption',captionEntities:[{}]};
  assert.equal(ctx.drawnAlbumEligible(updated,{...data,isChannel:true},false,false),
    'reactions' in change || 'forwardFrom' in change || 'commentCount' in change ||
      'inlineButtons' in change || 'replyThumbPath' in change || 'replyDiceLayers' in change);
  assert.equal(cache.prepare(updated,data,277,2),first);}
assert.equal(ctx.drawnAlbumEligible(g,data,true,false),false);assert.equal(ctx.drawnAlbumEligible(g,data,false,true),false);
for(let i=0;i<1000;i++)assert.equal(cache.prepare(g,{...data,playSlotKey:'999:2',playSlotStartMs:i},277,2),first);
const upload=cache.prepare({...g,head:{...g.head,sendState:'sending'}},data,277,2);assert.ok(upload.tiles.every(t=>t.cell.uploading));
const video={...g,photoIsVideo:[false,true],videoFileIds:[0,50],inlineFileIds:[0,51]};
const initial=cache.prepare(video,data,277,2),play=cache.prepare(video,{...data,playSlotKey:'101:1',autoplayMuted:true,playSlotStartMs:123},277,2);
assert.equal(play.tiles[1].cell.isPlaySlot,true);assert.equal(play.tiles[1].cell.autoplayMuted,true);assert.equal(play.tiles[1].cell.playSlotStartMs,123);
assert.equal(initial.tiles[1].key,play.tiles[1].key);assert.equal(initial.tiles[0].cell,play.tiles[0].cell);
assert.notEqual(cache.prepare(video,data,300,2).tiles[0].key,initial.tiles[0].key);
console.log(`PASS: ${cases} geometry/selection combinations; all full-row exclusions retain grid; 1000 external-player updates cache-hit; upload and playback remain live.`);
let notifications=0;const media=new ctx.DrawnAlbumGridMedia(()=>notifications++),ui={vp2px:n=>2*n};
media.prepare(ui,first);assert.equal(slotsCreated,6);assert.equal(notifications,1);const oldBinds=binds;
for(let i=0;i<1000;i++)media.prepare(ui,first);assert.equal(binds,oldBinds);
media.recycle();assert.equal(recycles,6);media.prepare(ui,first);assert.equal(binds,oldBinds+6);
media.prepare(ui,new ctx.DrawnAlbumGridLayouts().prepare(group(2),data,277,2));assert.equal(disposals,4);media.dispose();assert.equal(disposals,6);
console.log('PASS: one seeded publication, 1000 unchanged plans do not bind images, recycle reattaches, shrink/dispose release owners.');
const events=[],actions=new Proxy({}, {get:(_t,k)=>(...args)=>events.push([k,...args])});
const grid=new ctx.DrawnAlbumGrid(null,{group:g,data,actions,context:{gestureClaimed:false},gridWidth:277,gridCorners:{}});
const tap={source:1,windowX:4,windowY:5};
const early=grid.clickCallback(grid.plan.tiles[0]);early(tap);assert.equal(events.length,0);
grid.aboutToAppear();grid.touchedGeneration=grid.bindIdentity();early(tap);assert.deepEqual(events.at(-1),['onMediaTap',100,4,5]);
grid.context.gestureClaimed=true;let before=events.length;early(tap);assert.equal(events.length,before);grid.context.gestureClaimed=false;
grid.data={...data,selectionActive:true};grid.inputChanged();early(tap);assert.deepEqual(events.at(-1),['onToggleSelectedMessage',100]);
// Same native key, but latest failure data and live path must be read.
grid.data=data;grid.group={...g,photoFailed:[true],photoPaths:Array(6).fill('')};grid.inputChanged();early(tap);assert.deepEqual(events.at(-1),['onSpecialPhotoRetry',100]);
grid.group={...g,head:{...g.head,rowId:200}};grid.inputChanged();grid.group=g;grid.inputChanged();
before=events.length;early(tap);assert.equal(events.length,before,'old ABA handler rejected');
const fresh=grid.clickCallback(grid.plan.tiles[0]);fresh({...tap,source:2});assert.equal(events.at(-1)[0],'onMediaTap','accessibility/mouse needs no touch-down');
grid.aboutToRecycle();before=events.length;fresh(tap);assert.equal(events.length,before);
console.log('PASS: pre-appear, media tap, claimed swipe, selection, failure, stale ABA and recycled handlers.');
// Real compiled tree: 6 anchors + grid + selection overlay. No old per-photo
// component can be instantiated, including on the glass/accessibility routes.
const callbacks=[],created=[],children=[],touches=[];
for(const type of ['Stack','Row','Column','Text','Image','SymbolGlyph','If','ForEach'])ctx[type]=new Proxy({}, {get:(_t,k)=>(...args)=>{
  if(k==='create')created.push(type);if(k==='onTouch')touches.push(args[0]);}});
for(const type of ['Alignment','ImageFit','HitTestMode','Color'])ctx[type]=new Proxy({}, {get:(_t,k)=>k});
ctx.LiveProgressRing=class {constructor(_parent,params){children.push(['progress',params]);}};
ctx.DrawnAlbumVideo=class {constructor(_parent,params){children.push(['video',params]);}};
ctx.ViewV2.create=()=>{};
grid.observeComponentCreation2=fn=>{callbacks.push(fn);fn(1,true);};grid.ifElseBranchUpdateFunction=(_id,fn)=>fn();grid.forEachUpdateFunction=(_id,items,fn)=>items.forEach(fn);
grid.group=g;grid.data=data;grid.aboutToReuse();grid.initialRender();
assert.equal(created.filter(x=>x==='Stack').length,7);assert.equal(created.filter(x=>x==='Row').length,1);assert.equal(children.length,0);
touches.at(-1)({type:0,touches:[{}]});assert.equal(grid.touchedGeneration,grid.generation);
touches.at(-1)({type:3,touches:[]});assert.equal(grid.touchedGeneration,-1);
const staleBindings=[...callbacks];grid.group=group(0);grid.inputChanged();
grid.updateStateVarsOfChildByElmtId=()=>{};
for(const fn of staleBindings)fn(1,false);
callbacks.length=0;children.length=0;
grid.group={...video,head:{...video.head,sendState:'sending'},photoPaths:Array(6).fill('')};
grid.inputChanged();grid.initialRender();
assert.equal(children.filter(c=>c[0]==='progress').length,6,'one upload ring per tile, no second thumbnail ring');
assert.equal(children.filter(c=>c[0]==='video').length,1,'mixed album creates only the one video island');
const liveBindings=[...callbacks],updates=[];
grid.data={...data,playSlotKey:'101:1',autoplayMuted:true,playSlotStartMs:321};grid.inputChanged();
grid.updateStateVarsOfChildByElmtId=(_id,params)=>updates.push(params);
for(const fn of liveBindings)fn(1,false);
const videoUpdate=updates.find(p=>p.cell?.isVideo);
assert.equal(videoUpdate.cell.isPlaySlot,true);assert.equal(videoUpdate.cell.playSlotStartMs,321);
assert.equal(videoUpdate.cell.autoplayMuted,true,'stable tile key reads current playback data');
grid.group=group(0);grid.inputChanged();
for(const fn of liveBindings)fn(1,false);
console.log('PASS: mixed upload uses six rings and one video island; stable-key video bindings receive live playback state and tolerate shrink.');
const legacy=fs.readFileSync(compiled+'pages/chat/LegacyAlbumMessageBubble.ts','utf8');
assert.match(legacy,/new DrawnAlbumGrid\(/);assert.doesNotMatch(legacy,/new (AlbumRowView|AlbumCellView|LiveThumbImage)\(/);
assert.doesNotMatch(fs.readFileSync(root+'pages/chat/LegacyAlbumMessageBubble.ets','utf8'),/new Map|syncCandidates|releaseCandidates/);
console.log('PASS: six photos use seven Stack anchors plus selection Row, zero custom photo children; stale bindings tolerate an empty reused grid; every legacy body calls the new grid.');
// Compatibility glass/bare shell retains its rendering contract but must not
// retain repeated link parsing or reaction signature scans.
load(root+'util/reactionsWidth.ets');ctx.textMeasureEnvironment={epoch:1};ctx.str=k=>k;
const shell=fs.readFileSync(root+'pages/chat/MessageBubbleShell.ets','utf8');
function extract(name){const start=shell.indexOf(`  private ${name}(`);assert.ok(start>=0);return shell.slice(start,shell.indexOf('\n  }',start)+4);}
const methods=extract('hasInlineLink')+extract('reactionsRowWidth');
vm.runInContext(ts.transpileModule('class Compat { '+methods+' } globalThis.Compat=Compat;', {compilerOptions:{target:ts.ScriptTarget.ES2020}}).outputText,ctx);
const compat=new ctx.Compat();let parses=0,measures=0,rxScans=0;
const rx=[{emoji:'x',customEmojiId:'',count:1}];rx[Symbol.iterator]=function*(){rxScans++;yield*Array.prototype.values.call(this);};
Object.assign(compat,{msg:{text:'hello',textEntities:[],reactions:rx,editDate:0,isOutgoing:false},group:{caption:'',captionEntities:[]},
 env:{appearanceEpoch:1,langEpoch:1},context:{liveViews:''},textMeasureCache:{prepare(){}},inlineMaxW:()=>250,reactorsArrowShown:()=>false,
 messageTimeText:()=> '12:34',measureTextVp:(t,n)=>{measures++;return t.length*n/2;},formattedTextHasLink:()=>{parses++;return false;}});
compat.hasInlineLink();const firstWidth=compat.reactionsRowWidth(),initialMeasures=measures;
for(let i=0;i<1000;i++){assert.equal(compat.hasInlineLink(),false);assert.equal(compat.reactionsRowWidth(),firstWidth);}
assert.equal(parses,1);assert.equal(rxScans,1);assert.equal(measures,initialMeasures);
compat.msg={...compat.msg,text:'changed',reactions:[...rx,{emoji:'y',customEmojiId:'',count:7}]};compat.hasInlineLink();assert.equal(parses,2);assert.ok(compat.reactionsRowWidth()>firstWidth);
console.log('PASS: compatibility shell 1000 stable bindings do not reparse links or scan/measure reactions; content changes invalidate.');
