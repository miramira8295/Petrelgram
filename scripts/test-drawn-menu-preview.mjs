// Execute HAP-compiled builders; this checks capture ownership and playback
// isolation, not native screenshot pixels (those require a connected device).
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import {ctx,load,compiled,root,data,group,layoutCounters} from './test-drawn-text-row.mjs';
const imported=await import(process.env.TYPESCRIPT_MODULE||'typescript'),ts=imported.default||imported;
const children=[],draws=[],players=[];
for(const name of ['DrawnRowAccessibility','DrawnMenuMedia','DrawnMenuSticker','DrawnChecklistMessage','DrawnPollMessage','DrawnVideoNoteMessage','StickerMessageBubble','DrawnSingleMediaVideo','DrawnAlbumVideo']) {
  ctx[name]=class {constructor(_parent,params){this.name=name;this.params=params;}};
}
ctx.ViewV2.create=child=>{children.push(child);if(['StickerMessageBubble','DrawnSingleMediaVideo','DrawnAlbumVideo','DrawnVideoNoteMessage'].includes(child.name))players.push(child);};
for(const type of ['Stack','Row','Column','__Common__','If','ForEach'])ctx[type]=new Proxy({}, {get:(_t,k)=>(...args)=>{if(k==='drawModifier')draws.push(args[0]);}});
const liveBackground={},liveForeground={},previewBackground={},previewForeground={};
const previewPaint={background:{bind:()=>previewBackground},foreground:{bind:()=>previewForeground},attributes:{bind:()=>({})}};
let paintAllocations=0;
ctx.DrawnMenuPaintState=class {constructor(){paintAllocations++;Object.assign(this,previewPaint);}};
const g=group('');Object.assign(g.head,{contentType:'checklist',photoPath:'/cover',photoMini:'mini',stickerFileId:3,photoFileId:4});
const widget={key:'tasks',kind:'message-checklist'},placement={widget,x:0,y:0,width:240,height:300};
const plan={width:260,height:330,grid:{x:8,y:8,width:240,height:140},captionX:10,captionY:10,
  nativeTiles:[],tiles:[],avatar:{width:0},caption:{widgets:[placement],hitsByUrl:new Map(),source:{links:[]},media:[],tables:[],icons:[],maths:[],emojis:[]}};
const host=Object.create(ctx.DrawnMessageRow.prototype);
for(const [k,v] of Object.entries({plan,rowGroup:g,rowData:data,kind:'text',sendState:'sent',views:'',env:{},
  actions:{},a11y:{active:false},interaction:{},jumpFocus:0,claimed:false,deleteCaptureSupported:false,footerPaintKey:'',menuPaintState:null,
  canvasAttributes:{bind:()=>({})},painter:{bind:()=>liveBackground},foreground:{bind:()=>liveForeground},
  canDragMessage:()=>false,observeComponentCreation2:fn=>fn(1,true),ifElseBranchUpdateFunction:(_id,fn)=>fn(),
  forEachUpdateFunction:(_id,items,fn)=>items.forEach(fn),presentationReady:()=>true,
  nativeTiles:[],useAlbumCanvas:false,canvasTransitionIndex:-1,gridRadii:()=>0,
  imageSlot:index=>({path:'/current-cover',mini:'mini',content:{cell:host.nativeTiles[index]?.cell}}),mediaSlots:[],media:{slots:[]}}))Object.defineProperty(host,k,{value:v,writable:true,configurable:true});

host.canvasContent();
assert.equal(children.filter(c=>c.name==='DrawnChecklistMessage').length,1,'checklist is inside the captured bubble, not a sibling');
assert.equal(paintAllocations,0,'normal scrolling does not allocate preview painters');
assert.deepEqual(draws,[liveBackground,liveForeground]);
children.length=0;host.a11y.active=true;host.canvasContent();assert.deepEqual(children.map(c=>c.name),['DrawnRowAccessibility','DrawnChecklistMessage'],'interactive card remains above the virtual body target');host.a11y.active=false;
children.length=0;widget.kind='message-poll';host.canvasContent();
assert.equal(children.filter(c=>c.name==='DrawnPollMessage').length,1,'poll shares complete capture ownership');

widget.kind='message-sticker';g.head.contentType='sticker';children.length=0;draws.length=0;players.length=0;
const before=layoutCounters();host.menuPreview();
assert.equal(children.filter(c=>c.name==='DrawnMenuSticker').length,1);
assert.equal(players.length,0,'menu never mounts a second sticker player');
assert.deepEqual(draws,[previewBackground,previewForeground]);
assert.equal(paintAllocations,1);assert.deepEqual(layoutCounters(),before,'preview reuses prepared geometry');
host.menuPreview();assert.equal(paintAllocations,1,'one popup reuses its own painter state');

host.kind='album';g.head.contentType='video';plan.caption.widgets=[];
for(let n=1;n<=10;n++) {
  host.nativeTiles=Array.from({length:n},(_,i)=>({key:`${i}`,x:i*20,y:0,width:20,height:30,
    cell:{chatId:1,messageId:100+i,thumbFileId:200+i,thumbPath:'/old-cover',mini:'',isVideo:i%2===0}}));
  children.length=0;players.length=0;host.menuPreview();
  assert.equal(children.filter(c=>c.name==='DrawnMenuMedia').length,n);
  assert.ok(children.every(c=>c.params.path==='/current-cover'),'preview uses latest slot path');
  assert.equal(players.length,0,'mixed album preview creates only static images');
}
const currentTile=host.nativeTiles[0],savedSlot=host.imageSlot;host.imageSlot=()=>({path:'/unrelated',content:{cell:{chatId:9,messageId:9,thumbFileId:9}}});assert.equal(host.menuMediaPath(currentTile,0),currentTile.cell.thumbPath,'recycled old slot cannot supply a different message cover');host.imageSlot=savedSlot;
host.kind='text';host.nativeTiles=[];plan.caption.widgets=[placement];widget.kind='message-video-note';g.head.contentType='videoNote';
children.length=0;players.length=0;host.menuPreview();assert.equal(players.length,0);
assert.equal(children[0].params.corners.topLeft,placement.width/2,'video-note cover stays circular');

// Read the actual compiled binding's options: compact windows still get a menu,
// ordinary rows get a complete snapshot, surfaces/stickers get a custom cover.
const code=fs.readFileSync(compiled+'pages/chat/DrawnMessageRow.ts','utf8');
const ast=ts.createSourceFile('row.ts',code,ts.ScriptTarget.Latest,true);let options;
function visit(n){if(ts.isCallExpression(n)&&n.expression.getText(ast)==='Row.bindContextMenu')options=n.arguments[2];ts.forEachChild(n,visit);}visit(ast);
assert.ok(options,'existing capture Row owns the menu, no extra normal-row wrapper');
const getter=vm.runInContext(ts.transpileModule(`(function(){return ${options.getText(ast)};})`,{compilerOptions:{target:ts.ScriptTarget.ES2020}}).outputText,ctx);
Object.assign(host,{menuFx:{preview:()=>({}),menu:()=>({})},menuOffset:0});
ctx.menuPreviewCompact=()=>false;ctx.drawnLiveSurface=()=>false;
g.head.contentType='checklist';assert.equal(getter.call(host).preview,ctx.MenuPreviewMode.IMAGE);
// ArkUI invokes the preview as a detached callback. Direct host.menuPreview()
// above alone cannot detect a lost component receiver (device TypeError).
g.head.contentType='sticker';widget.kind='message-sticker';
let previewCallback=getter.call(host).preview;
children.length=0;assert.doesNotThrow(()=>Reflect.apply(previewCallback,undefined,[]));
assert.equal(children.filter(c=>c.name==='DrawnMenuSticker').length,1);
g.head.contentType='video';ctx.drawnLiveSurface=()=>true;
widget.kind='message-video-note';previewCallback=getter.call(host).preview;
children.length=0;assert.doesNotThrow(()=>Reflect.apply(previewCallback,undefined,[]));
assert.equal(children.filter(c=>c.name==='DrawnMenuMedia').length,1);
ctx.menuPreviewCompact=()=>true;assert.equal(getter.call(host).preview,ctx.MenuPreviewMode.NONE);
getter.call(host).onDisappear();assert.equal(host.menuPaintState,null,'dismiss releases retained preview plan/painters');

// Static preview source fallback and native component isolation.
ctx.DrawnBubblePainter=class{};ctx.DrawnBubbleForeground=class{};ctx.DrawnCanvasAttributes=class{};
load(root+'util/cachedImageSpec.ets',['CachedImageSpecCache']);
load(compiled+'pages/chat/DrawnMenuPreview.ts',['DrawnMenuMedia','DrawnMenuSticker']);
const sticker=Object.assign(Object.create(ctx.DrawnMenuSticker.prototype),{msg:{...g.head,photoPath:'',stickerPath:'/animation',stickerFormat:'tgs'}});
assert.equal(sticker.path(),'');sticker.msg.stickerFormat='webm';assert.equal(sticker.path(),'');
sticker.msg.photoPath='/thumbnail';assert.equal(sticker.path(),'/thumbnail');sticker.msg.photoPath='';sticker.msg.stickerFormat='webp';assert.equal(sticker.path(),'/animation');
const media=Object.assign(Object.create(ctx.DrawnMenuMedia.prototype),{path:'/thumbnail',sourceKey:'A',boxWidth:160,boxHeight:80,contain:true,specs:new ctx.CachedImageSpecCache()});
ctx.ImageFit={Contain:1,Cover:0};const spec=media.spec();for(let i=0;i<1000;i++)assert.equal(media.spec(),spec);
assert.equal(spec.opaque,false);assert.equal(spec.fit,ctx.ImageFit.Contain);media.sourceKey='B';assert.notEqual(media.spec(),spec);
console.log('PASS: complete checklist/poll capture; static sticker/video/mixed-album previews; independent lazy painters; no repeat layout or second player; compact-menu policy, dismissal and source ownership.');
