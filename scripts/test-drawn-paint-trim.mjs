// Real painter replay with stateful native doubles. Checks drawing commands and
// native call counts, not raster pixels or device milliseconds.
import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
const ts=(await import(process.env.TYPESCRIPT_MODULE||'typescript')).default;
const root='entry/src/main/ets/';
function runtime(baseline='') {
 const counts={aa:0,width:0,objects:0,invalidations:0},trace=[],commands=[];
 class Brush {
  constructor(){counts.objects++;this.aa=false;this.color=null;}
  setAntiAlias(v){counts.aa++;this.aa=v;}setColor(v){this.color=v;}setMaskFilter(v){this.filter=v;}
 }
 class Pen extends Brush {
  constructor(){super();this.width=0;this.cap='butt';}
  setStrokeWidth(v){counts.width++;this.width=v;}setCapStyle(v){this.cap=v;}
 }
 let brush=null,pen=null;
 const copy=x=>JSON.parse(JSON.stringify(x));
 const canvas=new Proxy({}, {get:(_t,k)=> (...args)=> {
  if(k==='attachBrush'){brush=args[0];return;}if(k==='detachBrush'){brush=null;return;}
  if(k==='attachPen'){pen=args[0];return;}if(k==='detachPen'){pen=null;return;}
  const entry={op:k,args};
  if(k.startsWith('draw')) {
   if(brush)entry.brush={aa:brush.aa,color:brush.color,filter:brush.filter};
   if(pen)entry.pen={aa:pen.aa,color:pen.color,width:pen.width,cap:pen.cap};
  }
  commands.push(copy(entry));
 }});
 const ctx=vm.createContext({DrawModifier:class{invalidate(){counts.invalidations++;}},
  drawing:{Brush,Pen,CapStyle:{ROUND_CAP:'round'},RoundRect:class{constructor(rect,x,y){counts.objects++;Object.assign(this,{rect,x,y});}},
   MaskFilter:{createBlurMaskFilter:(kind,r)=>({kind,r})},BlurType:{NORMAL:0},Path:class{buildFromSvgString(s){this.svg=s;return true;}}},
  drawnColor:x=>x,$r:x=>x,glassBubbleCommands:()=> 'outline',cornerPx:x=>x??0,
  hiTraceMeter:{HiTraceOutputLevel:{COMMERCIAL:3},startSyncTrace:(_l,n)=>trace.push(n),finishSyncTrace:()=>trace.push('end')}});
 function load(file,names){let path=root+file;
  if(baseline&&file.startsWith('pages/chat/'))path=baseline+'/'+file.split('/').at(-1);
  const src=fs.readFileSync(path,'utf8').replace(/^import\s[\s\S]*?;\r?\n/gm,'').replace(/\bexport /g,'');
  vm.runInContext(ts.transpileModule(src+names.map(n=>`\nglobalThis.${n}=${n};`).join(''),{compilerOptions:{target:ts.ScriptTarget.ES2020}}).outputText,ctx,{filename:path});
 }
 load('util/drawnStageMetrics.ets',['drawnStageMetrics','DrawnInvalidation','DrawnStage']);
 for(const name of ['DrawnChromePainter','DrawnBubblePainter','DrawnAlbumGridSelection','DrawnPlainTextPainter','DrawnContentOutline'])
  load('pages/chat/'+name+'.ets',name==='DrawnBubblePainter'?['DrawnBubblePainter','DrawnBubbleForeground','DrawnBubbleAvatar']:[name]);
 return {ctx,counts,trace,commands,canvas};
}
const ink={alpha:255,red:50,green:60,blue:70};
const text={paragraph:{paint(c,x,y){c.text(x,y);}},widthPx:40,heightPx:12};
function plan(d=2,size=13,outgoing=true){return {density:d,statusSize:size,statusX:120,statusY:70,
 fill:ink,accent:ink,secondary:ink,onMedia:false,outgoing,outline:'outline',bubbleX:20,bubbleY:4,
 avatar:{width:38,x:0,y:10},avatarColor:ink,initials:text,
 header:{paint(c){c.header();}},headerX:2,headerY:3,quote:null,quoteBackground:null,
 caption:text,captionX:8,captionY:24,footer:text,footerX:80,footerY:70,footerTextOffset:10,footerBackdrop:'backdrop',views:'12',footerEye:'eye',
 tiles:[{x:0,y:0,width:120,cell:{selectionActive:true,selected:true}},{x:120,y:0,width:120,cell:{selectionActive:true,selected:false}}],
 chrome:{content:{forward:text,comments:text},forwardRect:{x:1,y:2},reactionsX:2,reactionsY:100,
 reactions:{chips:[{x:0,y:0,width:30,height:24,reaction:{customEmojiPath:''},fill:ink,background:'chip',emoji:null,count:text,iconWidth:15},
 {x:50,y:0,height:24,reaction:null}]},commentsRect:{x:0,y:150,width:200,height:30},commentsTextX:8}};}
function replay(rt){
 const {ctx,commands,canvas}=rt,bg=new ctx.DrawnBubblePainter(),fg=new ctx.DrawnBubbleForeground(),av=new ctx.DrawnBubbleAvatar();
 const media={avatarHasPath:false,avatar:{drawFront(){canvas.image();}}},draw={canvas};
 for(const d of [1,2,3,2])for(const state of ['','none','sending','failed','sent','read'])for(const outgoing of [false,true]){
  const p=plan(d, d===3?20:13,outgoing);
  bg.bind(p,true);av.bind(p,media);fg.bind(p,state,'12');
  for(let i=0;i<2;i++){bg.drawBehind(draw);av.drawBehind(draw);fg.drawBehind(draw);}
  fg.setPress({x:1,y:2,widthVp:10,heightVp:8},d);fg.drawBehind(draw);fg.press(null);
  fg.pressReaction(p.chrome.reactions.chips[0]);fg.drawBehind(draw);fg.pressReaction(null);
 }
 return commands;
}
const r=runtime();replay(r);
const oldDir=process.env.DRAWN_PAINT_BASELINE;
if(oldDir){const old=runtime(oldDir);assert.deepEqual(r.commands,replay(old),'all geometry, colors, widths, caps and command order match before the change');
 console.log(`PASS: ${r.commands.length} draw commands match before/after across density/status/selection/press/reuse.`);}
// Warm draw: native properties and objects never change inside painting.
const {ctx,counts,canvas}=r,p=plan(),fg=new ctx.DrawnBubbleForeground(),bg=new ctx.DrawnBubblePainter(),av=new ctx.DrawnBubbleAvatar();
const grid=new ctx.DrawnAlbumGridSelection(),plain=new ctx.DrawnPlainTextPainter(),outline=new ctx.DrawnContentOutline();
const media={avatarHasPath:false,avatar:{drawFront(){}}},frame={canvas,sizeInPixel:{width:400,height:200}};
fg.bind(p,'read','12');bg.bind(p,true);av.bind(p,media);grid.bind(p,1);
const lp={density:2,iconPx:26,outline:'outline',fill:ink,accent:ink,secondary:ink,outgoing:true,
 header:null,quote:null,body:{paint(){}},footer:{paint(){}},bodyX:2,bodyY:4,footerX:50,footerY:80,statusX:120,statusY:80};
plain.bind(lp,'read',true);outline.bind(true,true,{},ink,'1',true,2);
const painters=[fg,bg,av,grid,plain,outline];for(const v of painters)v.drawBehind(frame);
const warm={...counts};r.commands.length=0;
for(let i=0;i<1000;i++)for(const v of painters)v.drawBehind(frame);
assert.equal(counts.aa,warm.aa);assert.equal(counts.width,warm.width);assert.equal(counts.objects,warm.objects);
assert.equal(counts.invalidations,warm.invalidations);assert.equal(r.trace.length,0);assert.equal(ctx.drawnStageMetrics.summary(),'');
const widths=()=>r.commands.filter(x=>x.pen).map(x=>x.pen.width);
r.commands.length=0;fg.drawBehind(frame);assert.ok(widths().includes(2));assert.ok(widths().includes(2.6));
const resized=plan(3,20);fg.bind(resized,'sending','12');r.commands.length=0;fg.drawBehind(frame);
assert.ok(widths().includes(3));assert.ok(widths().includes(6));assert.ok(!widths().includes(2.6));
const aa=counts.aa,w=counts.width;
for(let i=0;i<1000;i++)fg.bind({...resized},i%2?'failed':'read',String(i));
assert.equal(counts.aa,aa);assert.equal(counts.width,w,'same-density new plans/footer/state do not reset pen properties');
fg.bind(null,'none');fg.bind(p,'sent');r.commands.length=0;fg.drawBehind(frame);assert.ok(widths().includes(2.6));
// Enabled telemetry: binding vs actual paints, primary cause, stable-bind skips.
const m=ctx.drawnStageMetrics;m.setEnabled(true);m.reset();r.trace.length=0;
const f=new ctx.DrawnBubbleForeground();f.bind(p,'sent','12');
for(let i=0;i<100;i++){f.bind(p,'sent','12');f.drawBehind(frame);}
f.bind(p,'read','12');f.bind(p,'read','13');f.setPress({x:0,y:0,widthVp:8,heightVp:8},2);
f.pressReaction(p.chrome.reactions.chips[0]);const n=counts.invalidations;f.press(null);
assert.equal(counts.invalidations,n+1,'clear body and reaction highlights invalidates only once');
assert.match(m.summary(),/reason=foreground\/plan calls=1/);assert.match(m.summary(),/reason=foreground\/status calls=1/);
assert.match(m.summary(),/reason=foreground\/footer calls=1/);assert.match(m.summary(),/reason=foreground\/press calls=3/);
assert.match(m.summary(),/stage=PG\/foreground-paint calls=100/);
const b=new ctx.DrawnBubblePainter(),a=new ctx.DrawnBubbleAvatar();b.bind(p,false);b.bind(p,true);a.bind(p,media);
b.drawBehind(frame);a.drawBehind(frame);
assert.match(m.summary(),/reason=background\/plan calls=1/);assert.match(m.summary(),/reason=background\/shadow calls=1/);
assert.match(m.summary(),/reason=avatar\/plan calls=1/);
const starts=r.trace.filter(x=>x!=='end').length;assert.equal(r.trace.filter(x=>x==='end').length,starts);
r.trace.length=0;assert.throws(()=>f.drawBehind({canvas:{save(){throw Error('paint failure');}}}));assert.equal(r.trace.at(-1),'end');
m.setEnabled(false);const summary=m.summary();for(let i=0;i<1000;i++){m.invalidated(ctx.DrawnInvalidation.AvatarImage);f.drawBehind(frame);}
assert.equal(m.summary(),summary);m.reset();assert.equal(m.summary(),'');
console.log('PASS: 6000 warm paint callbacks perform zero AA/width setters or native allocations; density/status isolation, null reuse, O(1) disabled diagnostics, balanced paint traces and coalesced press invalidation.');
