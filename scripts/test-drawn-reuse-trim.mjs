// Production caches and real CompileArkTS callbacks; no host timings are used as device evidence.
import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
const ts=(await import(process.env.TYPESCRIPT_MODULE||'typescript')).default;
const root='entry/src/main/ets/', compiled='entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/'+root;
const ctx=vm.createContext({ViewV2:class{},ViewPU:class{},ImageFit:{Cover:0},HitTestMode:{None:0},Color:{White:'white'},
  thumbBackdropColor:()=>0,MINI_PLACEHOLDER_BLUR:5});
function load(path,names){const source=fs.readFileSync(path,'utf8').replace(/^import\s[\s\S]*?;\r?\n/gm,'')
 .replace(/@(?:Require|Param|Local|Computed|Event|ObservedV2|Trace)\s*/g,'').replace(/@Monitor\([^)]*\)\s*/g,'').replace(/\bexport /g,'');
 vm.runInContext(ts.transpileModule(source+names.map(n=>`\nglobalThis.${n}=${n};`).join(''),{compilerOptions:{target:ts.ScriptTarget.ES2020}}).outputText,ctx,{filename:path});}
load(root+'util/drawnTextUnits.ets',['DrawnTextUnits']);
let conversions=0,density=2,fontScale=1;
const ui={vp2px:n=>{conversions++;return n*density;},fp2px:n=>{conversions++;return n*density*fontScale+(n>14?3:0);}};
const units=new ctx.DrawnTextUnits();
units.prepare(ui,'a');assert.equal(units.density,2);assert.equal(units.fp2px(16),35);assert.equal(units.fp2px(12),24);
const n=conversions;for(let i=0;i<1000;i++){units.prepare(ui,'a');units.fp2px(16);units.fp2px(12);}assert.equal(conversions,n);
fontScale=2;units.prepare(ui,'b');assert.equal(units.fp2px(16),67,'configuration epoch must remeasure nonlinear fonts');
density=3;units.prepare(ui,'c');assert.equal(units.density,3);assert.equal(units.fp2px(12),72);
const other={vp2px:()=>4,fp2px:n=>n*4};units.prepare(other,'c');assert.equal(units.density,4);assert.equal(units.fp2px(12),48,'context switch cannot reuse measurements');
for(let i=1;i<=1000;i++)units.fp2px(i);assert.ok(units.fonts.size<=32);
let fail=true;const flaky={vp2px:()=>fail?NaN:2,fp2px:()=>fail?NaN:24};
assert.throws(()=>units.prepare(flaky,'d'));fail=false;units.prepare(flaky,'d');fail=true;assert.throws(()=>units.fp2px(12));fail=false;assert.equal(units.fp2px(12),24);
load(root+'util/drawnPlainTextPolicy.ets',['DrawnPlainLayoutCache']);
load(root+'pages/chat/DrawnRichTextLayout.ets',['DrawnRichTextLayouts']);
const rich=new ctx.DrawnRichTextLayouts();let builds=0;rich.build=()=>{builds++;return {};};
const spec={source:{},maxWidthVp:200,minWidthVp:0,fontSize:16,reserve:'',foreground:'black',accent:'blue',environment:'a'};
const first=rich.prepare(ui,spec),after=conversions;for(let i=0;i<1000;i++)assert.equal(rich.prepare(ui,spec),first);
assert.equal(builds,1);assert.equal(conversions,after,'1000 warm production rich prepares do zero additional native unit conversions');
rich.prepare(ui,{...spec,fontSize:20});assert.equal(builds,2);assert.equal(conversions,after+2,'new actual sizes measured once');
rich.prepare(ui,{...spec,environment:'b'});assert.equal(builds,3);assert.equal(conversions,after+6);
console.log('PASS: nonlinear font/cache/context/configuration/density/failed-measurement invalidation, 32-size bound and 1000 warm production prepares without conversions.');

load(root+'util/drawnRouteMetrics.ets',['DrawnRouteReason','DrawnRouteTracker','drawnRouteMetrics']);
load(root+'util/drawnStageMetrics.ets',['drawnStageMetrics','DrawnStage']);
load(root+'pages/chat/DrawnMediaFrames.ets',['DrawnMediaFrames']);
load(root+'pages/chat/DrawnNativeAttributes.ets',['DrawnMediaAnchorPool','DrawnCanvasAttributes']);
load(root+'pages/chat/DrawnLayoutWarmCache.ets',['takeDrawnWarmLayout']);
ctx.getTdClient ??= () => ctx; ctx.setTimeout ??= () => 0; ctx.clearTimeout ??= () => {};
load(root+'pages/chat/DrawnRecycledLayouts.ets',['DrawnLayoutRetention','takeDrawnRecycledLayout','drawnRecycledLayouts']);
load(compiled+'pages/chat/DrawnMessageRow.ts',['DrawnMessageRow']);
let current=0,nextId=0,callbacks,branches,reads,calls;
for(const name of ['Stack','If','Image','Column','Text','SymbolGlyph'])ctx[name]=new Proxy({name},{get:(t,k)=>k==='name'?name:(...args)=>{
 if(k==='create')callbacks.get(current).args=args;
 if(k!=='create'&&k!=='pop')calls++;
}});
for(const name of ['DrawnAlbumVideo','DrawnSingleMediaVideo','LiveProgressRing'])ctx[name]=class{constructor(_owner,params){callbacks.get(current).params=params;}};
ctx.ViewV2.create=()=>{};
function execute(id,initial=false){const old=current;current=id;const c=callbacks.get(id);if(!c)return;reads=c.reads=new Set();c.fn(id,initial);current=old;reads=callbacks.get(old)?.reads;}
function descendants(id){for(const [child,c]of [...callbacks])if(c.parent===id){descendants(child);callbacks.delete(child);branches.delete(child);}}
function render(count){callbacks=new Map();branches=new Map();nextId=0;calls=0;
 const row=Object.assign(Object.create(ctx.DrawnMessageRow.prototype),{layoutRetention:new ctx.DrawnLayoutRetention(),mediaFrameCache:new ctx.DrawnMediaFrames(),nativeAnchors:new ctx.DrawnMediaAnchorPool(),canvasAttributes:new ctx.DrawnCanvasAttributes()}),tiles=Array.from({length:count},(_,i)=>({width:100,height:100,x:i*100,y:0,cell:{isVideo:false,isLive:false,messageId:i+1,thumbFileId:i+20,failed:false}}));
 const slots=tiles.map((_,i)=>{const state={};Object.defineProperty(state,'revision',{get(){reads?.add(i);return 0;}});return{content:{cell:tiles[i].cell},activated:true,state,pixels:{},path:'/ready',mini:'mini',receiver:{canDraw:()=>true},showMini(scrolling){return this.pixels===undefined&&this.path!==''&&(!scrolling||this.miniShown);}};});
 Object.assign(row,{kind:'album',sendState:'sent',scroll:{active:false},group:{head:{}},data:{},actions:{},media:{slots},
 observeComponentCreation2(fn,type){const id=++nextId;callbacks.set(id,{fn,type,parent:current,reads:new Set()});execute(id,true);},
 ifElseBranchUpdateFunction(branch,fn){if(branches.get(current)===branch)return;descendants(current);branches.set(current,branch);fn();},
 updateStateVarsOfChildByElmtId(id,params){callbacks.get(id).params=params;}});
 Object.defineProperty(row,'mediaFrames',{get:()=>{reads?.add('frames');return row.mediaFrameCache.prepare(tiles.slice(),1,row.kind==='single');}});
 Object.defineProperty(row,'nativeTiles',{get:()=>{reads?.add('tiles');return tiles;}});Object.defineProperty(row,'mediaChatId',{get:()=>1});
 for(let i=0;i<count;i++)row.mediaTile({index:i,key:String(i)});
 return{row,tiles,slots};
}
function countType(name){return[...callbacks.values()].filter(c=>(c.type.name||c.type)===name).length;}
function updateSlot(i){const ids=[...callbacks].filter(([,c])=>c.reads.has(i)).map(([id])=>id);for(const id of ids)if(callbacks.has(id))execute(id);return ids.length;}
for(const count of [1,3,6,9]){const {slots}=render(count);assert.equal(callbacks.size,3*count);assert.equal(countType('If'),2*count);
 assert.equal(calls,2*count,'each loaded tile submits one diff modifier and its drawing receiver');
 for(const c of callbacks.values())if(c.type.name==='Stack'){assert.ok(c.reads.has('frames'));assert.ok(!c.reads.has('tiles'),'geometry callback cannot depend on media-cell updates');}
 const before=callbacks.size;for(const id of [...callbacks.keys()])execute(id);assert.equal(callbacks.size,before);
 assert.equal(updateSlot(0),1,'loaded photo completion updates only its overlay predicate');
 slots[0].pixels=undefined;updateSlot(0);assert.equal(countType('Image'),1,'mini appears only in changed slot');
 assert.equal([...callbacks.values()].filter(c=>c.reads.has(1)).length,count>1?1:0,'siblings do not gain dependencies');
 slots[0].pixels={};updateSlot(0);assert.equal(countType('Image'),0);assert.equal(callbacks.size,before,'loaded image drops all placeholder child callbacks');
}
// Mini can stay underneath upload progress; native fallback can coexist with progress.
let {row,slots,tiles}=render(1);slots[0].pixels=undefined;row.sendState='sending';updateSlot(0);
assert.equal(countType('Image'),1);assert.equal(countType('LiveProgressRing'),1);
slots[0].pixels={native:true};slots[0].receiver.canDraw=()=>false;updateSlot(0);assert.equal(countType('Image'),1);assert.equal(countType('LiveProgressRing'),1);
row.sendState='sent';slots[0].pixels=undefined;slots[0].path='';updateSlot(0);assert.equal(countType('Image'),0);assert.equal(countType('LiveProgressRing'),1);
tiles[0].cell.failed=true;for(const id of [...callbacks.keys()])if(callbacks.has(id))execute(id);assert.equal(countType('LiveProgressRing'),0);assert.equal(countType('SymbolGlyph'),1);
// Video island remains outside the overlay predicate across poster availability.
({row,slots,tiles}=render(1));tiles[0].cell.isVideo=true;for(const id of [...callbacks.keys()])if(callbacks.has(id))execute(id);assert.equal(countType('DrawnAlbumVideo'),1);
slots[0].path='';slots[0].pixels=undefined;updateSlot(0);assert.equal(countType('DrawnAlbumVideo'),1);assert.equal([...callbacks.values()].find(c=>c.type.name==='DrawnAlbumVideo').params.thumbReady,false);
slots[0].path='/new';slots[0].pixels={};updateSlot(0);assert.equal([...callbacks.values()].find(c=>c.type.name==='DrawnAlbumVideo').params.thumbReady,true);
// A removed tile cannot create upload progress while old controller slots linger.
({row,slots,tiles}=render(1));row.sendState='sending';tiles.length=0;
assert.equal(row.mediaOverlay(0),false);
for(const id of [...callbacks.keys()])if(callbacks.has(id))execute(id);
assert.equal(countType('LiveProgressRing'),0);
// Already-scheduled callbacks are safe after shrinking the plan.
const stale=[...callbacks.values()].map(c=>c.fn);tiles.length=0;slots.length=0;for(const fn of stale){const id=++nextId;callbacks.set(id,{fn,type:{name:'stale'},parent:0,reads:new Set()});execute(id);}
console.log('PASS: compiled loaded grids use 3N callbacks / 2N If / 2N DSL attribute submissions (geometry now uses native modifier diff), one slot change leaves siblings untouched; mini/upload/native fallback/retry/video/shrink branches preserved.');

const visible=[];
const guarded=Object.assign(Object.create(ctx.DrawnMessageRow.prototype),{layoutRetention:new ctx.DrawnLayoutRetention(),active:true,data:{chatId:1},group:{head:{rowId:1}},mediaVisibilityEpoch:0,mediaVisibilityKey:'',media:{setVisible:v=>visible.push(v)}});
const oldA=guarded.mediaVisibility();guarded.group={head:{rowId:2}};const bCallback=guarded.mediaVisibility();guarded.group={head:{rowId:1}};const newA=guarded.mediaVisibility();
oldA(false,0);bCallback(false,0);assert.equal(visible.length,0);newA(true,1);assert.deepEqual(visible,[true]);
guarded.active=false;newA(false,0);assert.deepEqual(visible,[true]);
console.log('PASS: stale A/B/A visibility callbacks cannot pause a currently visible attachment.');
