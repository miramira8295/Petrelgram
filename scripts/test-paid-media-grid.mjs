import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import {ctx,load,root,compiled,ui,data,style,group,layoutCounters} from './test-drawn-text-row.mjs';
const imported=await import(process.env.TYPESCRIPT_MODULE||'typescript'),ts=imported.default||imported;
vm.runInContext('globalThis.GridLayouts=DrawnPaidMediaGridLayouts;globalThis.paidMediaLayoutFor=paidMediaLayoutFor;',ctx);
const file=(id,path='')=>({id,size:100,local:{path,is_downloading_completed:!!path}});
const raw=Array.from({length:10},(_,i)=>({'@type':i%3===0?'paidMediaVideo':'paidMediaPhoto',
 video:{width:640,height:360,duration:30,video:file(100+i*2),thumbnail:{file:file(101+i*2)}},
 photo:{sizes:[{width:320+i*5,height:240,photo:file(101+i*2)},{width:1280+i*20,height:960,photo:file(100+i*2)}]}}));
for(let count=1;count<=10;count++)for(const width of [100,160,240,400]) {
 const set=ctx.parsePaidMediaSet(raw.slice(0,count)),engine=new ctx.GridLayouts(),plan=engine.prepare(set,width);
 assert.equal(plan.cells.length,count);assert.equal(new Set(plan.cells.map(c=>c.index)).size,count);
 for(const cell of plan.cells) {
  assert.ok(cell.width>0&&cell.height>0);assert.ok(cell.x>=-.01&&cell.y>=-.01);
  assert.ok(cell.x+cell.width<=plan.width+.01);assert.ok(cell.y+cell.height<=plan.height+.01);
 }
 for(let i=0;i<1000;i++)assert.equal(engine.prepare(set,width),plan);
 const equal=ctx.parsePaidMediaSet(raw.slice(0,count));assert.equal(engine.prepare(equal,width),plan);
}
const set=ctx.parsePaidMediaSet(raw.slice(0,6)),g=group('paid caption');
Object.assign(g.head,{contentType:'paidMedia',paidMediaSet:set,paidMediaCount:6,paidMediaLocked:false,paidMediaStarCount:10});
const layouts=new ctx.DrawnTextLayouts(),plan=layouts.prepare(ui,g,data,style),slot=plan.caption.widgets[0],geometry=ctx.paidMediaLayoutFor(slot.widget);
assert.equal(geometry.grid.cells.length,6);assert.equal(geometry.artworkHeight,geometry.grid.height);
const counts=layoutCounters();for(let i=0;i<1000;i++)assert.equal(layouts.prepare(ui,{...g,head:{...g.head,photoProgress:i%100}},data,style),plan);
assert.deepEqual(layoutCounters(),counts);
// Real controller with deterministic bitmap/channel boundaries.
const watchers=new Map(),requests=[],sessions=[],scheduled=[];let notifications=0,invalidations=0,decodes=0;
class Session {
 constructor(publish){this.publish=publish;sessions.push(this);this.active=false;this.spec=null;this.disposals=0;}
 activate(spec){this.active=true;this.apply(spec);}
 update(spec){this.apply(spec);}
 apply(spec){if(this.spec?.path===spec.path&&this.spec?.sourceKey===spec.sourceKey&&this.spec?.boxWidth===spec.boxWidth&&this.spec?.boxHeight===spec.boxHeight)return;
  this.spec=spec;if(this.active){if(spec.path){decodes++;this.publish({path:spec.path},true,100,100);}else this.publish(undefined,false);}}
 recycle(){this.active=false;}
 dispose(){this.active=false;this.spec=null;this.disposals++;}
}
class Receiver {
 invalidate(){invalidations++;}setPixels(p){this.pixels=p;this.invalidate();}canDraw(p){return !p?.native;}
 bind(){return this;}drawFront(){}
}
const local=vm.createContext({ViewV2:class{},ViewPU:class{},DrawModifier:class{},ImageFit:{Cover:1},
 SourceType:{TouchScreen:1,Mouse:2},CachedImageSession:Session,DrawnImageReceiver:Receiver,
 drawing:{Brush:class{setAntiAlias(){}setColor(){}},Path:class{buildFromSvgString(){}}},
 THUMBNAIL_PRIORITY:16,OneShotFrameCallback:class{constructor(task){this.task=task;}},
 documentFileId:f=>f?.id??0,documentFilePath:f=>f?.local?.is_downloading_completed?f.local.path:'',
 documentFileState:f=>({path:f.local?.is_downloading_completed?f.local.path:'',failed:false,progress:0}),
 watchDocumentFile:(f,fn)=>{watchers.set(f.id,fn);return()=>{};},requestDocumentFile:(f,p,retry)=>requests.push([f.id,p,!!retry])});
function loadLocal(path,names) {
 const code=fs.readFileSync(path,'utf8').replace(/^import\s[\s\S]*?;\r?\n/gm,'').replace(/\bexport /g,'')
 .replace(/@(?:Require|Param|Local|Computed|Event)\s*/g,'').replace(/@Monitor\([^)]*\)\s*/g,'');
 vm.runInContext(ts.transpileModule(code+names.map(n=>`\nglobalThis.${n}=${n};`).join(''),{compilerOptions:{target:ts.ScriptTarget.ES2020}}).outputText,local);
}
loadLocal(root+'util/drawnFrameBatch.ets',[]);
loadLocal(root+'pages/chat/DrawnPaidMediaImageReceiver.ets',[]);
loadLocal(root+'pages/chat/DrawnPaidMediaGridController.ets',['DrawnPaidMediaGridController']);
const ownerUi={postFrameCallback:cb=>scheduled.push(cb)},controller=new local.DrawnPaidMediaGridController(()=>notifications++);
controller.bind(ownerUi,set,geometry.grid,'A',true,2);assert.equal(requests.length,0,'locked assets never request full/thumbnail files');
controller.bind(ownerUi,set,geometry.grid,'A',false,2);assert.equal(requests.length,6);assert.equal(notifications,2);
const before=notifications;for(let i=0;i<1000;i++)controller.bind(ownerUi,set,geometry.grid,'A',false,2);
assert.equal(requests.length,6);assert.equal(notifications,before);
const old=watchers.get(101);old({path:'/old-A',failed:false});assert.equal(controller.slots[0].path,'/old-A');
controller.bind(ownerUi,set,geometry.grid,'B',false,2);const current=watchers.get(101);old({path:'/stale',failed:false});
assert.notEqual(controller.slots[0].path,'/stale','old A completion cannot repaint B');
current({path:'/B',failed:false});assert.equal(controller.slots[0].path,'/B');
const other=sessions[1].spec,otherDecodes=decodes;current({path:'/B',failed:false,progress:80});
assert.equal(sessions[1].spec,other);assert.equal(decodes,otherDecodes,'bytes do not restart decodes');
controller.recycle();current({path:'/detached',failed:false});assert.equal(controller.slots[0].pixels,undefined);
controller.bind(ownerUi,set,geometry.grid,'A',false,2);old({path:'/stale-A-again',failed:false});assert.notEqual(controller.slots[0].path,'/stale-A-again');
controller.dispose();for(const cb of scheduled)cb.task();assert.equal(controller.slots.length,0);
loadLocal(compiled+'pages/chat/DrawnPaidMediaGrid.ts',['DrawnPaidMediaGrid']);
const opened=[],grid=Object.assign(Object.create(local.DrawnPaidMediaGrid.prototype),{mediaSet:set,gridPlan:geometry.grid,
 ownerKey:'A',locked:false,density:2,active:true,generation:0,boundOwner:'',boundSet:null,touchGeneration:-1,
 media:new local.DrawnPaidMediaGridController(()=>{}),getUIContext:()=>ownerUi,onOpen:i=>opened.push(i)});
grid.sync();const stale=grid.click(2);grid.ownerKey='B';grid.sync();stale({source:2});assert.equal(opened.length,0);
grid.click(2)({source:2});assert.deepEqual(opened,[2]);grid.click(1)({source:1});assert.deepEqual(opened,[2]);
grid.touchGeneration=grid.generation;grid.click(1)({source:1});assert.deepEqual(opened,[2,1]);
grid.aboutToRecycle();grid.click(0)({source:2});assert.equal(opened.length,2);
// Invoke real card actions, including selecting a later valid item.
load(compiled+'pages/chat/PaidMediaBubble.ts',['PaidMediaBubble']);
const selected=[],unlocks=[];
const card=Object.assign(Object.create(ctx.PaidMediaBubble.prototype),{mediaSet:set,locked:false,pending:false,
 messageId:77,mediaReady:true,mediaKind:'photo',onBeforeAction:()=>true,onOpenAt:(id,index)=>selected.push([id,index]),onUnlock:id=>unlocks.push(id)});
card.trigger(4);assert.deepEqual(selected,[[77,4]]);card.pending=true;card.trigger(3);assert.equal(selected.length,1);
card.pending=false;card.locked=true;card.starCount=10;card.trigger(5);assert.deepEqual(unlocks,[77]);assert.equal(selected.length,1);
console.log('PASS: 1–10 paid grid geometries and bounds, cached dimensions/1000 progress plans, locked download isolation, per-asset decode, A/B/A stale completions/recycle, exact tile click index and pending/locked actions.');
