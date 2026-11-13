// Real layout/policy/channel code and HAP-compiled host handlers. Native text
// metrics are deterministic doubles; this is not a device visual/perf test.
import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
const imported = await import(process.env.TYPESCRIPT_MODULE || 'typescript');
const ts = imported.default || imported;
const root = 'entry/src/main/ets/';
const compiled = 'entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/' + root;
let pathBuilds = 0, measureCalls = 0;
const ui = {vp2px: n => n * 2, fp2px: n => n * 2};
class TextCache { prepare(text, max, font) { measureCalls++; return {widthPx: Math.min(max, text.length * font / 2), heightPx: font + 4, paragraph: {paint(){}}}; } }
const ctx = vm.createContext({
  ViewV2: class {}, ViewPU: class {}, Color: { White: '#fff' }, $r: x => x,
  drawing: { Path: class {buildFromSvgString(s) {this.svg=s;pathBuilds++;return true;}}, RoundRect: class {constructor(rect){this.rect=rect;}} },
  DrawnTextLineCache: TextCache, drawnColor: x => x,
  DrawnTextFooterCache: class {prepare(ui,time,edited,views,outgoing,max,color,env){
    const line=new TextCache().prepare(time,max,ui.fp2px(11));
    return {line,widthPx:line.widthPx+(outgoing?36:0)+(views?26:0),heightPx:line.heightPx,iconPx:24,textOffsetPx:views?26:0};
  }},
  DrawnSenderHeaderCache: class { prepare(){return {heightPx:32};} },
  DrawnReplyQuoteCache: class { prepare(){return {heightPx:76};} },
  DrawnRichSourceCache: class {prepare(s){return s === 'unsupported' ? null : {text:s};}},
  DrawnRichTextLayouts: class {prepare(_ui, args){return {heightVp:44,widthVp:100,paragraph:{getLineCount:()=>2,getLineMetrics:()=>({left:0,width:100,baseline:60,ascent:30})}, ...args};}},
  getUserStore: () => ({accentColorId:()=>-1}), getAccentColorStore: () => ({}),
  AVATAR_PALETTE: ['red','blue'], COLOR_PRIMARY: 'blue', COLOR_TEXT_SECONDARY: 'gray',
  COLOR_BUBBLE_IN: 'white', COLOR_BUBBLE_OUT: 'green', accentSoft:()=> 'soft', bubbleTextFor:()=> 'black',
  BUBBLE_AVATAR_GUTTER_VP: 41, mediaThumbWidth: (width,gutter) => Math.min(280,width-gutter-40),
  formatClockTime:()=> '12:34', viewsReserve:()=> '', str:x=>x, plural:(k,n)=>`${n} comments`,reactionKeyFrom:(e,id)=>id||e, slotKey:(id,i)=>`${id}:${i}`,
  SourceType: {TouchScreen:1,Mouse:2}, TouchType:{Down:0,Up:1,Move:2,Cancel:3},
  firstFinger: list => list[0], messageGesturePolicy:()=>({tapOpensMenu:true,longPressSelects:false,longPressOpensMenu:true}),
  isEdgeSwipeStart:x=>x<36, SWIPE_REPLY_MAX:-70,SWIPE_REPLY_TRIGGER:-40,SWIPE_SELECT_MAX:70,SWIPE_SELECT_TRIGGER:40,
  Curve:{EaseOut:1}, tableScrollTouched:()=>false
});
function load(path,names=[]) {
  const text=fs.readFileSync(path,'utf8').replace(/^import\s[\s\S]*?;\r?\n/gm,'')
    .replace(/@(?:Require|Param|Local|Computed|Event)\s*/g,'').replace(/@Monitor\([^)]*\)\s*/g,'').replace(/\bexport /g,'');
  vm.runInContext(ts.transpileModule(text+names.map(n=>`\nglobalThis.${n}=${n};`).join(''),
    {compilerOptions:{target:ts.ScriptTarget.ES2020}}).outputText,ctx,{filename:path});
}
load(root+'util/drawnTextUnits.ets');
load(root+'pages/chat/DrawnMediaColors.ets');
for (const file of ['packAlbumRows','albumGeometryCache','albumCellRenderData','messageBubblePresentation','bubbleCornerInset','bubbleGlassPath','albumCornerRadii','drawnAlbumPolicy','drawnContentPolicy','drawnFooterPlacement']) load(root+'util/'+file+'.ets',file==='drawnAlbumPolicy'?['drawnAlbumEligible','albumRectContains']:[]);
for(const file of ['DrawnReactionLayout','DrawnBubbleChrome','DrawnAlbumGridLayout','DrawnBubbleGeometry','DrawnBubblePlan'])load(root+'pages/chat/'+file+'.ets');
load(root+'pages/chat/DrawnSingleMediaGeometry.ets');
load(root+'pages/chat/DrawnMediaLayout.ets');
load(root+'pages/chat/DrawnAlbumLayout.ets',['DrawnAlbumLayouts']);
load(root+'util/messageDragGesture.ets',['MessageDragGesture']);
load(root+'util/drawnMediaSlot.ets',['DrawnMediaSlots']);
load(root+'util/drawnRouteMetrics.ets',['DrawnRouteReason','DrawnRouteTracker','drawnRouteMetrics']);
load(root+'util/drawnStageMetrics.ets',['drawnStageMetrics','DrawnStage']);
load(root+'pages/chat/DrawnMediaFrames.ets',['DrawnMediaFrames']);
load(root+'pages/chat/DrawnNativeAttributes.ets',['DrawnMediaAnchorPool','DrawnCanvasAttributes']);
load(root+'pages/chat/DrawnLayoutWarmCache.ets',['takeDrawnWarmLayout']);
ctx.getTdClient ??= () => ctx; ctx.setTimeout ??= () => 0; ctx.clearTimeout ??= () => {};
load(root+'pages/chat/DrawnRecycledLayouts.ets',['DrawnLayoutRetention','takeDrawnRecycledLayout','drawnRecycledLayouts']);
load(compiled+'pages/chat/DrawnMessageRow.ts',['DrawnMessageRow']);
function group(n=6) {
  return { head:{id:10,rowId:10,date:1,editDate:0,isOutgoing:false,senderId:5,senderName:'',senderInitials:'AB',senderIsUser:true,
    sendState:'sent',senderTag:'',text:'',translatedText:'',reactions:[],inlineButtons:[],forwardFrom:'',commentCount:0,
    replyToMessageId:0,replySenderName:'',replyText:'',replyThumbPath:'',replyDiceLayers:[],linkUrl:'',linkTitle:'',linkSiteName:'',linkDescription:'',linkPhotoFileId:0},
    memberIds:Array.from({length:n},(_,i)=>100+i),photoRatios:Array.from({length:n},(_,i)=>.4+i*.25),
    photoPaths:[],photoFileIds:[],photoMinis:[],photoProgress:[],photoFailed:[],photoIsVideo:[],photoIsLive:[],
    videoFileIds:[],videoFileSizes:[],videoDurations:[],videoMimeTypes:[],inlineFileIds:[],inlineFileSizes:[],
    caption:'',captionEntities:[],showAvatar:true,showSenderName:true };
}
const data = {playSlotKey:'',autoplayMuted:false,playSlotStartMs:0,chatId:99,isGroup:false,isChannel:false,contentWidth:400,themeBubbleOut:'',selectionActive:false,selectedMemberIds:[]};
const style = {radius:20,fontSize:16,environment:'1',textEnvironment:'1',role:'',views:''};
const layouts = new ctx.DrawnAlbumLayouts();
let cases=0;
for(let n=2;n<=10;n++) for(const width of [260,400,800]) for(let flags=0;flags<16;flags++) {
  const g=group(n),d={...data,contentWidth:width,isGroup:!!(flags&1),selectionActive:true,selectedMemberIds:[101,104]};
  g.head.isOutgoing=!!(flags&2);g.showAvatar=!!(flags&4);if(flags&8){g.caption='caption';g.head.senderName='name';g.head.replyToMessageId=55;}
  const p=layouts.prepare(ui,g,d,style);
  assert.equal(p.tiles.length,n);assert.ok(p.height>0&&p.width>0);
  const expected=ctx.packAlbumRows(g.photoRatios,p.grid.width).flat();
  p.tiles.forEach((t,i)=>{
    assert.equal(t.width,expected[i].width);assert.equal(t.height,expected[i].height);assert.equal(t.cell.idx,i);
    assert.ok(t.x>=p.grid.x&&t.y>=p.grid.y);assert.ok(t.x+t.width<=p.grid.x+p.grid.width+.01);
    assert.ok(t.y+t.height<=p.grid.y+p.grid.height+.01);
    assert.equal(t.cell.selected,d.selectedMemberIds.includes(t.cell.messageId));
    assert.ok(ctx.albumRectContains(t,t.x,t.y));assert.equal(ctx.albumRectContains(t,t.x+t.width,t.y),false);
  });
  assert.ok(p.grid.y+p.grid.height<=p.height);
  assert.equal(p.avatar.width,d.isGroup&&!g.head.isOutgoing&&g.showAvatar?38:0);
  const old=JSON.stringify(p.tiles);layouts.prepare(ui,group(2),data,style);assert.equal(JSON.stringify(p.tiles),old,'published geometry immutable');
  cases++;
}
let g=group();assert.ok(ctx.drawnAlbumEligible(g,data,false,false));
for(const field of ['translatedText','linkUrl','linkTitle','linkSiteName','linkDescription']) {
  g=group();g.head[field]='x';assert.equal(ctx.drawnAlbumEligible(g,data,false,false),false,field);
}
for(const field of ['inlineButtons','replyDiceLayers']) {g=group();g.head[field]=[{}];assert.equal(ctx.drawnAlbumEligible(g,data,false,false),true,field);}
for(const field of ['photoIsVideo','photoIsLive']) {g=group();g[field][3]=true;assert.equal(ctx.drawnAlbumEligible(g,data,false,false),true,field);}
assert.equal(ctx.drawnAlbumEligible(group(),data,true,false),false);assert.equal(ctx.drawnAlbumEligible(group(),data,false,true),false);
g=group();g.caption='unsupported';assert.equal(layouts.prepare(ui,g,data,style),null);
// Replay actual compiled interaction handlers using an immutable plan.
const row=Object.assign(Object.create(ctx.DrawnMessageRow.prototype),{layoutRetention:new ctx.DrawnLayoutRetention(),mediaFrameCache:new ctx.DrawnMediaFrames(),nativeAnchors:new ctx.DrawnMediaAnchorPool(),canvasAttributes:new ctx.DrawnCanvasAttributes()}), events=[];
row.dragGesture=new ctx.MessageDragGesture();row.kind='album';row.group=group();row.data={...data,canReply:true};row.env={gestureScheme:0,screenWidthVp:400,powerSaving:false,reduceAnim:false};
row.actions=new Proxy({}, {get:(_t,k)=>(...args)=>events.push([k,...args])});
row.foreground={press(){},pressReaction(){},setPress(){}};row.media={slots:Array.from({length:6},()=>({activated:true,state:{revision:0},path:'/ready'}))};
row.getUIContext=()=>({animateTo:(_opts,fn)=>fn()});
const p=layouts.prepare(ui,row.group,row.data,style);Object.defineProperty(row,'plan',{configurable:true,value:p});
const tile=p.tiles[2];const click={x:tile.x+5,y:tile.y+5,windowX:100,windowY:200,source:1};
const down={type:0,changedTouches:[{x:click.x,y:click.y,windowX:100}],touches:[{x:click.x,y:click.y,windowX:100}]};
row.touch(down);row.rowTouch(down);row.click(click);assert.equal(events.at(-1)[0],'onMediaTap');assert.equal(events.at(-1)[1],102);
row.data.selectionActive=true;row.click(click);assert.deepEqual(events.at(-1),['onToggleSelectedMessage',102]);row.data.selectionActive=false;
const eventCount=events.length;row.group={...row.group,head:{...row.group.head,rowId:11}};row.click(click);assert.equal(events.length,eventCount,'late click cannot open recycled message');
row.rowTouch(down);row.swipe(-60);row.endSwipe();assert.equal(events.at(-1)[0],'onReplyTo');
row.rowTouch({...down,changedTouches:[{windowX:5}]});row.swipe(-60);row.endSwipe();assert.equal(events.filter(e=>e[0]==='onReplyTo').length,1,'edge swipe does not reply');
// Render-path guard: supported route cannot instantiate the old cell chain.
const code=fs.readFileSync(compiled+'pages/chat/DrawnMessageRow.ts','utf8');
assert.doesNotMatch(code,/new (MessageBubbleShell|AlbumRowView|AlbumCellView|LiveThumbImage)\(/);
assert.match(code,/attributeModifier(?:\.bind\(this\))?\(this.nativeAnchors.bind/);assert.match(code,/Stack\.clip\(true\)/);
assert.match(code,/new LegacyAlbumMessageBubble\(/);
console.log(`PASS: ${cases} album geometries match old packer, immutable snapshots/selection/bounds, unsupported policy, compiled media/selection/reuse/edge gestures and route shape.`);
// Replay the compiled native-node creation callbacks again after the input
// becomes a fallback and slots shrink. This is the reuse ordering that caused
// the earlier rich-text crash (old children run before their old if is removed).
const callbacks=[], created=[];
for(const type of ['Stack','Row','Image','If','ForEach','Column','Text','SymbolGlyph']) {
  ctx[type]=new Proxy({}, {get:(_t,method)=>(...args)=>{if(method==='create')created.push(type);}});
}
for(const name of ['Alignment','HitTestMode','MenuPreviewMode','BlurStyle','ModalMode','HapticFeedbackMode','FontWeight']) ctx[name]=new Proxy({}, {get:(_t,k)=>k});
ctx.ImageFit={Cover:0};ctx.JUMP_FOCUS_SCALE=.01;ctx.JUMP_FOCUS_BRIGHTNESS=.01;
ctx.menuPreviewCompact=()=>false;ctx.containerBlur=()=>0;ctx.overlayMaterial=()=>0;ctx.thumbBackdropColor=()=> '#aaa';
row.observeComponentCreation2=fn=>{callbacks.push(fn);fn(1,true);};
row.ifElseBranchUpdateFunction=(_id,fn)=>fn();row.forEachUpdateFunction=(_id,items,fn)=>items.forEach(fn);
row.gridCorners=vm.runInContext('new AlbumCornerRadiiCache()',ctx);
row.painter={bind:()=>({})};row.foreground.bind=()=>({});row.menuFx={preview:()=>({}),menu:()=>({})};
row.avatarStateRevision=0;row.scroll={active:false};row.group.dateLabel='';
row.media.slots=Array.from({length:6},()=>({activated:true,state:{revision:0},path:'/ready',pixels:{},receiver:{canDraw:()=>true},showMini:()=>false}));
row.mediaSlotCache=new ctx.DrawnMediaSlots();
row.canvasContent();assert.equal(created.filter(n=>n==='Stack').length,8);assert.equal(created.filter(n=>n==='Image'||n==='Text').length,0);
const oldBindings=[...callbacks];row.media.slots=[];Object.defineProperty(row,'plan',{configurable:true,value:null});
for(const callback of oldBindings) callback(1,false);
console.log('PASS: compiled six-photo paint tree has eight Stack anchors and no Image/Text leaves; stale native bindings survive shrink/fallback.');
// The new row channel owner also rejects A -> B -> A delayed callbacks without
// resubscribing during 1000 same-identity updates.
const channels=new Map(), deliveries=[];let attaches=0;
ctx.subscribeSendState=(id,fn)=>{attaches++;channels.set(id,fn);return()=>channels.delete(id);};
ctx.subscribeViewCount=()=>()=>{};ctx.subscribeTranslationStatus=()=>()=>{};
ctx.sendStateFor=()=>'';ctx.viewCountLabelFor=()=>'';ctx.translationStatusFor=()=>null;
ctx.DrawnSenderRoleBinding=class {attach(){return '';}detach(){}};
load(root+'pages/chat/DrawnBubbleController.ets',['DrawnBubbleController']);
const binding=new ctx.DrawnBubbleController({send:x=>deliveries.push(x),views(){},translation(){},role(){}});
const ma=group().head,mb={...ma,id:11,rowId:11};binding.attach(1,ma,false);const stale=channels.get(ma.rowId);
for(let i=0;i<1000;i++)binding.attach(1,ma,false);assert.equal(attaches,1);
binding.attach(1,mb,false);binding.attach(1,ma,false);const length=deliveries.length;stale('stale');assert.equal(deliveries.length,length);
binding.detach();assert.equal(channels.size,0);
console.log('PASS: 1000 same-row channel attaches keep one subscription; old A callbacks remain invalid after A/B/A.');

// Playback in another row must not invalidate this immutable geometry plan.
const mixed=group(6);mixed.photoIsVideo[2]=true;mixed.videoFileIds[2]=50;mixed.inlineFileIds[2]=51;
const memo=new ctx.DrawnAlbumLayouts(),mixedData={...data};
const idle=memo.prepare(ui,mixed,mixedData,style),oldPaths=pathBuilds,oldMeasures=measureCalls;
for(let i=0;i<1000;i++)assert.equal(memo.prepare(ui,mixed,{...mixedData,playSlotKey:'999:2',playSlotStartMs:i,autoplayMuted:!!(i%2)},style),idle);
assert.equal(pathBuilds,oldPaths);assert.equal(measureCalls,oldMeasures);
const playing=memo.prepare(ui,mixed,{...mixedData,playSlotKey:'102:2',playSlotStartMs:500,autoplayMuted:true},style);
assert.equal(playing.tiles[2].cell.isPlaySlot,true);assert.equal(playing.tiles[2].cell.inlineFileId,51);
assert.equal(playing.tiles[2].cell.playSlotStartMs,500);assert.equal(playing.tiles[2].cell.autoplayMuted,true);
assert.equal(playing.tiles[2].key,idle.tiles[2].key,'playback keeps stable native tile anchor');
assert.equal(playing.tiles[1].cell,idle.tiles[1].cell,'unaffected photo data retained');
assert.match(code,/cell: this.media.slots\[slot.index\]\?\.content.cell/);
console.log('PASS: 1000 other-row playback updates retain plan/no layout work; owned slot routes current cell/mute/start to stable anchor.');

// Physical-slot identity is deliberately independent of message/geometry. Keep
// the ForEach children, replay their actual compiled observers, and verify they
// read B's plan rather than the A tile captured when the child was first made.
const slots=new ctx.DrawnMediaSlots(), six=slots.prepare(6);
for(let i=0;i<1000;i++)assert.equal(slots.prepare(6),six);
const two=slots.prepare(2);assert.equal(two[1],six[1]);assert.equal(six.length,6);
const nine=slots.prepare(9);assert.equal(nine[0],two[0]);assert.equal(two.length,2);
assert.equal(new Set(nine.map(s=>s.key)).size,9);assert.equal(slots.prepare(0).length,0);

const replay=Object.assign(Object.create(ctx.DrawnMessageRow.prototype),{layoutRetention:new ctx.DrawnLayoutRetention(),mediaFrameCache:new ctx.DrawnMediaFrames(),nativeAnchors:new ctx.DrawnMediaAnchorPool(),canvasAttributes:new ctx.DrawnCanvasAttributes()});
Object.assign(replay,row);replay.mediaSlotCache=new ctx.DrawnMediaSlots();
replay.group=group();replay.data={...data};replay.sendState='sent';
let currentId=0,nextId=0,generated=0;
const observers=new Map(),branches=new Map(),loops=new Map(),nodes=new Map(),children=new Map();
function invoke(id,fn,initial){const previous=currentId;currentId=id;try{fn(id,initial);}finally{currentId=previous;}}
replay.observeComponentCreation2=(fn,type)=>{
  const id=++nextId;observers.set(id,fn);nodes.set(id,{type,attrs:{}});invoke(id,fn,true);
};
replay.ifElseBranchUpdateFunction=(branch,fn)=>{
  if(branches.get(currentId)!==branch){branches.set(currentId,branch);fn();}
};
replay.forEachUpdateFunction=(id,items,fn,key)=>{
  const previous=loops.get(id)||new Set(),next=new Set();
  for(const item of items){const k=key(item);next.add(k);if(!previous.has(k)){generated++;fn(item);}}
  loops.set(id,next);
};
for(const type of ['Stack','Row','Image','If','ForEach','Column','Text','SymbolGlyph']) {
  ctx[type]=new Proxy({}, {get:(_t,method)=>(...args)=>{
    const node=nodes.get(currentId);if(node)node.attrs[method]=args;
    if(method==='attributeModifier'){let peer;peer=new Proxy({}, {get:(_t,k)=>(...a)=>{node.attrs[k]=a;return peer;}});args[0].applyNormalAttribute(peer);}
  }});
}
ctx.ViewV2.create=()=>{};
ctx.DrawnAlbumVideo=class {constructor(_owner,params,_a,id){children.set(id,params);}};
replay.updateStateVarsOfChildByElmtId=(id,params)=>children.set(id,params);
const snapshot=(base,count=6)=>({...p,caption:null,chrome:null,quote:null,
  tiles:p.tiles.slice(0,count).map((t,i)=>({...t,width:90+base+i,height:120+base+i,x:base+i*23,y:base+i*17,
    cell:{...t.cell,messageId:base+i,thumbFileId:base+100+i,isVideo:i===2,failed:false}}))});
function setReplayPlan(plan){
  if(plan)plan.nativeTiles=plan.tiles.map(t=>({...t,x:t.x-plan.grid.x,y:t.y-plan.grid.y}));
  Object.defineProperty(replay,'plan',{configurable:true,value:plan});
  replay.media={slots:(plan?.tiles??[]).map(t=>({content:{cell:t.cell},activated:true,state:{revision:0},path:'/ready',pixels:{},receiver:{canDraw:()=>true},showMini:()=>false}))};
}
setReplayPlan(snapshot(100));replay.media.slots[2].activated=false;
replay.canvasContent();assert.equal(generated,6);
assert.equal(children.size,0,'pending video island is not created during initial row build');
const anchorBefore=[...nodes].filter(([,node])=>node.attrs.geometryTransition).map(([id,node])=>[id,JSON.stringify(node.attrs.size)]);
replay.media.slots[2].activated=true;replay.media.slots[2].state.revision++;
for(const [id,fn] of [...observers])invoke(id,fn,false);
assert.equal(generated,6,'activation keeps the existing six tile generators');
assert.equal(children.size,1,'only the activated video island appears');
for(const [id,size] of anchorBefore)assert.equal(JSON.stringify(nodes.get(id).attrs.size),size,'activation never changes measured tile size');
const tileNodes=[...nodes].filter(([,node])=>node.attrs.geometryTransition).map(([id])=>id);
assert.equal(tileNodes.length,6);assert.equal(children.size,1);
for(const base of [200,100,330]){
  setReplayPlan(snapshot(base));
  for(const [id,fn] of [...observers])invoke(id,fn,false);
  assert.equal(generated,6,'same six physical slots must not invoke item generators again');
  tileNodes.forEach((id,i)=>{
    const a=nodes.get(id).attrs,t=replay.plan.tiles[i];
    assert.equal(a.size[0].width,t.width);assert.equal(a.size[0].height,t.height);
    assert.equal(a.position[0].x,t.x-replay.plan.grid.x);assert.equal(a.position[0].y,t.y-replay.plan.grid.y);
    assert.equal(a.drawModifier[0],replay.media.slots[i].receiver);
    assert.equal(a.geometryTransition[0],i===2?'':`media_${data.chatId}_${base+i}`);
  });
  assert.equal([...children.values()][0].cell,replay.plan.tiles[2].cell,'video receives live cell after A/B/A');
}
// Old attribute observers can run before removed branches during shrink/fallback.
const retained=[...observers];setReplayPlan(snapshot(500,2));
for(const [id,fn] of retained)invoke(id,fn,false);
setReplayPlan(null);for(const [id,fn] of retained)invoke(id,fn,false);
for(const id of tileNodes){
 const a=nodes.get(id).attrs;assert.equal(a.size[0].width,0);assert.equal(a.size[0].height,0);
 assert.equal(a.geometryTransition[0],'');assert.equal(a.drawModifier[0],undefined);
}
// Re-enter the same retained callback set after empty/shrink; each physical
// anchor must bind current geometry, transition and receiver again.
setReplayPlan(snapshot(700));for(const [id,fn] of retained)invoke(id,fn,false);
tileNodes.forEach((id,i)=>{
 const a=nodes.get(id).attrs;assert.equal(a.size[0].width,replay.plan.tiles[i].width);
 assert.equal(a.drawModifier[0],replay.media.slots[i].receiver);
 assert.equal(a.geometryTransition[0],i===2?'':`media_${data.chatId}_${700+i}`);
});
console.log('PASS: 1000 slot-cache hits allocate nothing; compiled retained six-slot A/B/A updates geometry/receiver/transition/video cell without regenerating children; shrink/fallback is safe.');

// Real layout cache: grid-local tiles retain identity across changes outside
// the grid. The public absolute tiles remain suitable for hit-testing/painting.
const scopeLayouts=new ctx.DrawnAlbumLayouts(),scopeGroup=group(6);
scopeGroup.caption='caption';scopeGroup.photoIsVideo[2]=true;scopeGroup.videoFileIds[2]=50;
const scopeData={...data,isGroup:true},scopePlan=scopeLayouts.prepare(ui,scopeGroup,scopeData,style);
const native=scopePlan.nativeTiles,snapshotBefore=JSON.stringify(native);
assert.equal(native.length,6);
for(let i=0;i<1000;i++){
  const next=scopeLayouts.prepare(ui,scopeGroup,scopeData,{...style,views:String(i),radius:10+i%10});
  assert.equal(next.nativeTiles,native,'footer/shell changes must not publish another native grid');
}
const named={...scopeGroup,head:{...scopeGroup.head,senderName:'Sender'}};
const moved=scopeLayouts.prepare(ui,named,scopeData,style);
assert.notEqual(moved.grid.y,scopePlan.grid.y);assert.equal(moved.nativeTiles,native,'header moves the grid container, not its children');
moved.tiles.forEach((t,i)=>{
  assert.equal(t.x,moved.grid.x+native[i].x);assert.equal(t.y,moved.grid.y+native[i].y);
});
const rotated=scopeLayouts.prepare(ui,named,{...scopeData,contentWidth:260},style);
assert.notEqual(rotated.nativeTiles,native);assert.notEqual(rotated.nativeTiles[0].width,native[0].width);
const selected=scopeLayouts.prepare(ui,named,{...scopeData,selectionActive:true,selectedMemberIds:[102]},style);
assert.equal(selected.nativeTiles[2].cell.selected,true);
const playingNow=scopeLayouts.prepare(ui,named,{...scopeData,playSlotKey:'102:2',autoplayMuted:true,playSlotStartMs:123},style);
assert.equal(playingNow.nativeTiles[2].cell.isPlaySlot,true);assert.equal(playingNow.nativeTiles[2].cell.playSlotStartMs,123);
const changedPhoto={...named,photoPaths:['/new'],photoProgress:[50],photoFailed:[true]};
const changedPlan=scopeLayouts.prepare(ui,changedPhoto,scopeData,style);
assert.equal(changedPlan.nativeTiles[0].cell.thumbPath,'/new');assert.equal(changedPlan.nativeTiles[0].cell.failed,true);
assert.equal(JSON.stringify(native),snapshotBefore,'old immutable grid must remain unchanged');
Object.defineProperty(replay,'plan',{configurable:true,value:scopePlan});assert.equal(replay.nativeTiles,native);
Object.defineProperty(replay,'plan',{configurable:true,value:null});const emptyNative=replay.nativeTiles;
assert.equal(emptyNative.length,0);assert.equal(replay.nativeTiles,emptyNative);
const tileMethod=code.slice(code.indexOf('    mediaTile('),code.indexOf('    canvasContent('));
assert.doesNotMatch(tileMethod,/this\.plan\b/,'compiled tile observers must not subscribe to the entire row plan');
console.log('PASS: 1000 footer/shell changes preserve native grid identity; header movement preserves local geometry; rotation/selection/playback/photo updates stay live; no compiled tile observer reads whole plan.');

// Exercise the actual compiler-generated top-level dispatch. Its direct child
// must be the shared row, with all live parameters and opacity still forwarded.
const routeFile=compiled+'pages/chat/ReusableMessageBubble.ts';
const routeSource=ts.createSourceFile(routeFile,fs.readFileSync(routeFile,'utf8'),ts.ScriptTarget.Latest,true);
const routeClass=routeSource.statements.find(n=>ts.isClassDeclaration(n)&&n.name.text==='ReusableMessageBubble');
const render=routeClass.members.find(n=>ts.isMethodDeclaration(n)&&n.name.getText(routeSource)==='initialRender');
const routed=[],alphas=[];
class RouteChild {constructor(_parent,params){routed.push(params);}}
const routeCtx=vm.createContext({DrawnMessageRow:RouteChild,ViewV2:{create(){}},If:{create(){},pop(){}},
  __Common__:{create(){},opacity:n=>alphas.push(n),pop(){}}});
vm.runInContext(ts.transpileModule(`class RouteProbe {${render.getText(routeSource)}};globalThis.RouteProbe=RouteProbe;`,
  {compilerOptions:{target:ts.ScriptTarget.ES2020}}).outputText,routeCtx);
const router=new routeCtx.RouteProbe();router.observeComponentCreation2=fn=>fn(1,true);router.ifElseBranchUpdateFunction=(_id,fn)=>fn();
Object.assign(router,{data,actions:{},nowSec:50,jumpFocus:.2,leaving:.3,translationFade:.5});
for(const [contentType,photos,kind] of [['photo',6,'album'],['photo',1,'single'],['video',1,'single'],['text',0,'text'],['richMessage',0,'text']]){
  router.shownGroup={...group(),head:{...group().head,contentType},photoPaths:Array(photos).fill('')};router.initialRender();
  const params=routed.at(-1);assert.equal(params.kind,kind);assert.equal(params.group,router.shownGroup);
  assert.equal(params.data,data);assert.equal(params.actions,router.actions);assert.equal(params.nowSec,50);
  assert.equal(params.jumpFocus,.2);assert.equal(params.leaving,.3);assert.equal(alphas.at(-1),.5);
}
assert.doesNotMatch(render.getText(routeSource),/new\s+(TextMessageBubble|AlbumMessageBubble|SingleMediaBubble)\b/);
console.log('PASS: compiled album/photo/video/plain/rich routes directly instantiate shared row and preserve data/actions/focus/delete/translation opacity.');

const sharedSource=ts.createSourceFile('DrawnMessageRow.ts',code,ts.ScriptTarget.Latest,true);
const sharedClass=sharedSource.statements.find(n=>ts.isClassDeclaration(n)&&n.name.text==='DrawnMessageRow');
const sharedRender=sharedClass.members.find(n=>ts.isMethodDeclaration(n)&&n.name.getText(sharedSource)==='initialRender');
const legacyCalls=[];
function legacy(name){return class {constructor(_owner,params){legacyCalls.push({name,params});}};}
Object.assign(routeCtx,{LegacyTextRow:legacy('text'),LegacySingleMediaBubble:legacy('single'),LegacyAlbumMessageBubble:legacy('album')});
vm.runInContext(ts.transpileModule(`class FallbackProbe {${sharedRender.getText(sharedSource)}};globalThis.FallbackProbe=FallbackProbe;`,
  {compilerOptions:{target:ts.ScriptTarget.ES2020}}).outputText,routeCtx);
const fallback=new routeCtx.FallbackProbe();Object.assign(fallback,router,{plan:null,group:group()});
for(const kind of ['text','single','album']){
  fallback.kind=kind;fallback.initialRender();assert.equal(legacyCalls.at(-1).name,kind);
  assert.equal(legacyCalls.at(-1).params.group,fallback.group);assert.equal(legacyCalls.at(-1).params.actions,fallback.actions);
}
console.log('PASS: shared compiled row retains all three native fallback routes and forwards current group/actions.');
