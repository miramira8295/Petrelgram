// Production paragraph/layout caches + compiled interaction/native bindings.
// Font metrics are deterministic doubles; this does not measure device speed.
import assert from 'node:assert/strict';
import { ctx, load, root, compiled, ui, data, style, group, layoutCounters } from './test-drawn-text-row.mjs';
for(const file of ['packAlbumRows','albumGeometryCache','albumCellRenderData'])load(root+'util/'+file+'.ets');
load(root+'pages/chat/DrawnAlbumGridLayout.ets');
load(root+'pages/chat/DrawnSingleMediaGeometry.ets');
load(root+'pages/chat/DrawnMediaLayout.ets');
load(root+'pages/chat/DrawnAlbumLayout.ets',['DrawnAlbumLayouts']);
function reactions(n){return Array.from({length:n},(_,i)=>({emoji:i%3?'👍':'🙂',count:i+1,isChosen:i%2===0,
 customEmojiId:i%5===0?String(i+1):'',customEmojiPath:i%10===0?'/emoji.png':''}));}
function message(n=4){const g=group('Body with several words');Object.assign(g.head,{reactions:reactions(n),
 forwardFrom:'Original author',forwardOriginChatId:21,forwardOriginMsgId:22,forwardOriginUserId:0,
 commentCount:15,commentReplierIds:[1,2,3],commentReplierAvatarPaths:['/a','/b','/c']});return g;}
function album(g){return {...g,caption:'Album caption with a link https://example.org',captionEntities:[],memberIds:[10,11,12,13,14,15],
 photoRatios:[1,.6,1.5,1,1,1],photoPaths:['/a','/b'],photoFileIds:[1,2],photoMinis:[],photoProgress:[],photoFailed:[],
 photoIsVideo:[],photoIsLive:[],videoFileIds:[],videoFileSizes:[],videoDurations:[],videoMimeTypes:[],inlineFileIds:[],inlineFileSizes:[]};}
const overlap=(a,b)=>a.x<b.x+b.width&&b.x<a.x+a.width&&a.y<b.y+b.height&&b.y<a.y+a.height;
let cases=0;
for(const kind of ['text','album'])for(const width of [180,280,400])for(const font of [12,24,32])for(const n of [0,1,5,40]){
 const layouts=kind==='text'?new ctx.DrawnTextLayouts():new ctx.DrawnAlbumLayouts();
 let g=message(n);if(kind==='album')g=album(g);
 const p=layouts.prepare(ui,g,{...data,isChannel:true,contentWidth:width},{...style,fontSize:font});
 assert.ok(p,`${kind}/${width}/${font}/${n}`);const c=p.chrome;
 assert.ok(c.forwardRect.y+c.forwardRect.height<=p.captionY);
 assert.ok(c.commentsRect.y+c.commentsRect.height<=p.height);
 const footer={x:p.footerX,y:p.footerY,width:p.footerWidth,height:p.footer.heightPx/p.density};
 assert.ok(footer.y+footer.height<=c.commentsRect.y);
 if(n){
  assert.equal(c.reactions.chips.length,n);assert.ok(c.reactionsY>=p.captionY+p.caption.heightVp);
  for(const t of c.reactions.chips){
   const chip={x:c.reactionsX+t.x,y:c.reactionsY+t.y,width:t.width,height:t.height};
   assert.ok(chip.x+chip.width<=p.width+.01);assert.ok(!overlap(chip,footer),'footer never overlaps a chip');
   assert.equal(c.reactions.hit(t.x+t.width/2,t.y+t.height/2),t);
  }
 }
 cases++;
}
console.log(`PASS: ${cases} text/album/width/font/reaction layouts, footer separation, forward/comment bounds and chip hit centres.`);
const g=message(),d={...data,isChannel:true},layouts=new ctx.DrawnTextLayouts();
let p=layouts.prepare(ui,g,d,style);const warm=layoutCounters();
for(let i=0;i<1000;i++)assert.equal(layouts.prepare(ui,g,d,style),p);
assert.deepEqual(layoutCounters(),warm,'warm chrome adds no shaping/parsing/path work');
const body=p.caption;
for(let i=0;i<100;i++){
 const m={...g,head:{...g.head,reactions:reactions(i%10+1),commentCount:i+1,forwardFrom:'author '+i}};
 p=layouts.prepare(ui,m,d,{...style,views:String(i)});assert.equal(p.caption,body);
}
assert.equal(layoutCounters().parseCalls,warm.parseCalls);assert.equal(layoutCounters().bodyLayouts,warm.bodyLayouts);
const albums=new ctx.DrawnAlbumLayouts(),a=album(g);p=albums.prepare(ui,a,d,style);
const tiles=p.tiles,caption=p.caption,albumWarm=layoutCounters();
for(let i=0;i<100;i++){
 const updated={...a,head:{...a.head,reactions:reactions(i%10+1),commentCount:i+1}};
 const next=albums.prepare(ui,updated,d,{...style,views:String(i)});
 assert.equal(next.tiles,tiles,'reaction/comment/footer changes preserve placed photo geometry');
 assert.equal(next.caption,caption,'caption paragraph independent of footer');
}
assert.equal(layoutCounters().bodyLayouts,albumWarm.bodyLayouts);assert.equal(layoutCounters().parseCalls,albumWarm.parseCalls);
console.log('PASS: 1000 warm hits do no layout work; 100 reaction/comment/forward/footer changes keep body; albums retain captions and tile geometry.');

// Compare the indexed hit lookup to a brute-force oracle, including row gaps.
p=new ctx.DrawnTextLayouts().prepare(ui,message(1000),data,style);
const rp=p.chrome.reactions;let probes=0;
rp.chips=new Proxy(rp.chips,{get(t,k){if(/^\d+$/.test(String(k)))probes++;return t[k];}});
rp.bands=new Proxy(rp.bands,{get(t,k){if(/^\d+$/.test(String(k)))probes++;return t[k];}});
let seed=17,maxProbes=0;
for(let i=0;i<1000;i++){
 seed=(seed*1664525+1013904223)>>>0;const x=seed/2**32*(rp.width+10);
 seed=(seed*1664525+1013904223)>>>0;const y=seed/2**32*(rp.height+10);
 probes=0;const hit=rp.hit(x,y);maxProbes=Math.max(maxProbes,probes);
 const expected=rp.chips.find(c=>x>=c.x&&x<c.x+c.width&&y>=c.y&&y<c.y+c.height)||null;
 assert.equal(hit,expected);
}
assert.ok(maxProbes<30,`indexed probes ${maxProbes}, not a 1000-chip scan`);
console.log(`PASS: 1000 differential hit tests over 1001 chips (including arrow); max ${maxProbes} indexed probes.`);

const row=Object.assign(Object.create(ctx.DrawnMessageRow.prototype),{layoutRetention:new ctx.DrawnLayoutRetention(),canvasAttributes:new ctx.DrawnCanvasAttributes()}),events=[];
row.group=message(3);row.data={...data,isChannel:false};row.kind='text';row.env={gestureScheme:0,screenWidthVp:400};
row.dragGesture=new ctx.MessageDragGesture();row.foreground={press(){},setPress(){},pressReaction(){}};
row.actions=new Proxy({},{get:(_t,k)=>(...args)=>events.push([k,...args])});
const pl=new ctx.DrawnTextLayouts().prepare(ui,row.group,row.data,style);
Object.defineProperty(row,'plan',{configurable:true,value:pl});
function down(x,y){const e={type:0,touches:[{x,y,windowX:100,windowY:200}],changedTouches:[{x,y,windowX:100,windowY:200}]};row.touch(e);row.rowTouch(e);}
const chip=pl.chrome.reactions.chips[0],x=pl.chrome.reactionsX+chip.x+2,y=pl.chrome.reactionsY+chip.y+2;
down(x,y);assert.equal(row.touchOnBody,false,'reaction hold does not arm text drag');
row.click({x,y,source:1});assert.deepEqual(events.at(-1),['onSetReaction',10,chip.key,true]);
down(x,y);row.longPress({fingerList:[{localX:x+4,localY:y+3}],target:{area:{width:400}}});
assert.deepEqual(events.at(-1),['onShowReactors',10,chip.key]);const held=events.length;row.click({x,y,source:1});assert.equal(events.length,held);
const arrow=pl.chrome.reactions.arrow;const ax=pl.chrome.reactionsX+arrow.x+2,ay=pl.chrome.reactionsY+arrow.y+2;
down(ax,ay);row.click({x:ax,y:ay,source:1});assert.deepEqual(events.at(-1),['onShowReactorsList',10,'reactors_anchor_9_10']);
const f=pl.chrome.forwardRect;down(f.x+1,f.y+1);row.click({x:f.x+1,y:f.y+1,source:1});assert.deepEqual(events.at(-1),['onForwardTap',21,22,0]);
row.data.selectionActive=true;const before=events.length;row.click({x,y,source:2});assert.equal(events.length,before);row.data.selectionActive=false;
down(x,y);Object.defineProperty(row,'plan',{configurable:true,value:new ctx.DrawnTextLayouts().prepare(ui,message(5),data,style)});
row.click({x,y,source:1});assert.equal(events.length,before,'plan changed during touch rejects old reaction');
row.data={...data,isChannel:true};const cp=new ctx.DrawnTextLayouts().prepare(ui,row.group,row.data,style);
Object.defineProperty(row,'plan',{configurable:true,value:cp});const cr=cp.chrome.commentsRect;
down(cr.x+1,cr.y+1);row.click({x:cr.x+1,y:cr.y+1,source:1});assert.deepEqual(events.at(-1),['onCommentTap',10]);
// Real input lifecycle invalidates even A -> B -> A with an identical cached plan.
row.active=true;row.channels={attach(){}};ctx.senderHasAnimatedPhoto=()=>false;
down(cr.x+1,cr.y+1);const old=row.group;row.group={...old,head:{...old.head,rowId:11}};row.attach();row.group=old;row.attach();
const count=events.length;row.click({x:cr.x+1,y:cr.y+1,source:1});assert.equal(events.length,count);
console.log('PASS: compiled reaction toggle/hold/list anchor, forward origin, comments, selection suppression, mid-touch layout change and A/B/A input guards.');

// Compiled resource islands keep custom emoji + commenter avatars, but no
// text/count/chip components. Replay old params after the group is emptied.
ctx.ViewV2.prototype.initParam=function(k,v){this[k]=v;};ctx.ViewV2.prototype.finalizeConstruction=function(){};
ctx.ViewV2.create=()=>{};
const created=[],callbacks=[],avatarParams=[],updates=[],ids=[];
for(const type of ['Stack','Row','Image','If','ForEach','Column','Text','__Common__'])ctx[type]=new Proxy({}, {get:(_t,k)=>(...args)=>{
 if(k==='create')created.push(type);if(k==='id')ids.push(args[0]);}});
ctx.OutlineStyle={SOLID:1};ctx.ImageFit={Contain:1};
ctx.MessageSenderAvatar=class{constructor(_parent,params){avatarParams.push(params);}};
load(compiled+'pages/chat/DrawnChromeIslands.ts',['DrawnChromeIslands']);
const ig=message(6),ip=new ctx.DrawnTextLayouts().prepare(ui,ig,{...data,isChannel:true},style);
const island=new ctx.DrawnChromeIslands(null,{plan:ip,msg:ig.head,chatId:9,themeBubbleOut:''});
island.observeComponentCreation2=fn=>{callbacks.push(fn);fn(1,true);};
island.ifElseBranchUpdateFunction=(_id,fn)=>fn();island.forEachUpdateFunction=(_id,items,fn)=>items.forEach(fn);
island.updateStateVarsOfChildByElmtId=(_id,params)=>updates.push(params);
island.initialRender();assert.equal(avatarParams.length,3);assert.equal(created.filter(n=>n==='Image').length,1);
assert.equal(created.filter(n=>n==='Text').length,0);
const beforeBindings=[...callbacks];island.msg={...ig.head,commentReplierIds:[7],commentReplierAvatarPaths:['/new']};
for(const fn of beforeBindings)fn(1,false);
assert.equal(updates[0].spec.senderId,7);assert.equal(updates[0].spec.initialPath,'/new');assert.equal(updates[1].spec.senderId,0);
island.plan=null;island.msg={...ig.head,commentReplierIds:[],commentReplierAvatarPaths:[]};
for(const fn of beforeBindings)fn(1,false);
island.plan=new ctx.DrawnTextLayouts().prepare(ui,ig,data,style);island.msg=ig.head;island.initialRender();
assert.equal(ids.at(-1),'reactors_anchor_9_10');
console.log('PASS: compiled islands retain one loaded custom image, three avatars, no Text children; live avatar paths/empty reuse and popup anchor preserved.');

let nativeObjects=0,paints=0;
const native=class{constructor(){nativeObjects++;return new Proxy({}, {get:()=>()=>{}});}};
ctx.drawing.Brush=native;ctx.drawing.Pen=native;
load(root+'pages/chat/DrawnChromePainter.ets',['DrawnChromePainter']);
const painter=new ctx.DrawnChromePainter(),allocated=nativeObjects,paintWarm=layoutCounters();
const canvas=new Proxy({}, {get:()=>()=>paints++});
painter.bind(2);
for(let i=0;i<100;i++)painter.paint(canvas,ip.chrome,2,{}, {},ip.chrome.reactions.chips[0]);
assert.equal(nativeObjects,allocated);assert.deepEqual(layoutCounters(),paintWarm);assert.ok(paints>0);
const cache=layouts.chrome.reactions;cache.measure(ui,reactions(1000),250,true,'1');cache.flow(250);
cache.measure(ui,reactions(2),250,true,'1');cache.flow(250);
assert.equal(cache.emojis.length,2);assert.equal(cache.counts.length,2);assert.equal(cache.metrics.length,3);
console.log('PASS: 100 paint passes allocate no native resources and shape no text; reaction slot caches shrink from 1000 to 2.');

// A supported ordinary-emoji channel message adds no native label/chip nodes.
const listeners=new Map();created.length=0;
ctx.Stack=new Proxy({}, {get:(_t,k)=>(...args)=>{if(k==='create')created.push('Stack');if(k.startsWith('on'))listeners.set(k,args[0]);}});
ctx.configureMessageDrag=()=>{events.push(['drag']);return {extraInfo:'message'};};
row.group=message(4);row.group.head.commentCount=0;
row.group.head.reactions=row.group.head.reactions.map(r=>({...r,customEmojiId:'',customEmojiPath:''}));
row.data={...data,isChannel:true};const plainChrome=new ctx.DrawnTextLayouts().prepare(ui,row.group,row.data,style);
Object.defineProperty(row,'plan',{configurable:true,value:plainChrome});
row.observeComponentCreation2=fn=>fn(1,true);row.ifElseBranchUpdateFunction=(_id,fn)=>fn();row.forEachUpdateFunction=(_id,items,fn)=>items.forEach(fn);
row.painter={bind:()=>({})};row.foreground.bind=()=>({});row.menuFx={preview:()=>({}),menu:()=>({})};
row.canvasContent();assert.equal(created.filter(n=>n==='Stack').length,1);assert.equal(created.filter(n=>n==='Row').length,1);
assert.equal(created.filter(n=>n==='Text'||n==='Image').length,0);
const r0=plainChrome.chrome.reactions.chips[0];down(plainChrome.chrome.reactionsX+r0.x+2,plainChrome.chrome.reactionsY+r0.y+2);
assert.equal(row.allowBodyDrag,false);const beforeDrag=events.length;listeners.get('onDragStart')({});assert.equal(events.length,beforeDrag);
down(plainChrome.captionX+2,plainChrome.captionY+2);assert.equal(row.allowBodyDrag,true);
listeners.get('onDragStart')({});assert.equal(events.at(-1)[0],'drag');
console.log('PASS: ordinary reaction+forward row still uses two paint nodes; chip drag exports no message while body drag remains available.');

const emptyLayout=new ctx.DrawnTextLayouts();emptyLayout.prepare(ui,group(),data,style);
assert.equal(emptyLayout.chrome.reactions,null);assert.equal(emptyLayout.chrome.forward,null);assert.equal(emptyLayout.chrome.comments,null);
emptyLayout.prepare(ui,message(10),{...data,isChannel:true},style);
emptyLayout.prepare(ui,group(),data,style);
assert.equal(emptyLayout.chrome.reactions,null);assert.equal(emptyLayout.chrome.forward,null);assert.equal(emptyLayout.chrome.comments,null);
console.log('PASS: plain rows allocate no label/reaction caches; reuse into a plain row drops old chrome caches.');
