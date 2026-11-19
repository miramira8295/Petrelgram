// Pure production motion model: semantic diff, linear work and bounded lifetime.
// This does not substitute for native pixels or device frame-time verification.
import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
const ts=(await import(process.env.TYPESCRIPT_MODULE||'typescript')).default;
const path='entry/src/main/ets/pages/chat/ReactionMotion.ets';
const calls={get:0,has:0,set:0};
class CountedMap extends Map {
 get(key){calls.get++;return super.get(key);}
 has(key){calls.has++;return super.has(key);}
 set(key,value){calls.set++;return super.set(key,value);}
}
const context=vm.createContext({Map:CountedMap});
const code=fs.readFileSync(path,'utf8').replace(/^import\s[\s\S]*?;\r?\n/gm,'').replace(/\bexport /g,'');
vm.runInContext(ts.transpileModule(code+'\nglobalThis.ReactionMotion=ReactionMotion;globalThis.DURATION=REACTION_MOTION_MS;',
 {compilerOptions:{target:ts.ScriptTarget.ES2020}}).outputText,context,{filename:path});
const {ReactionMotion,DURATION}=context;
assert.ok(DURATION>0&&DURATION<=220);
const color=(r=40,g=100,b=150,a=40)=>Object.freeze({alpha:a,red:r,green:g,blue:b});
let shapeId=0,labelId=0;
function chip(key,count=1,chosen=false,extra={}){
 const label=Object.freeze({id:++labelId,widthPx:String(count).length*8,heightPx:14,paragraph:{paint(){throw new Error('Motion must not paint or shape');}}});
 return Object.freeze({key,reaction:Object.freeze({count,isChosen:chosen}),x:0,y:0,width:60,height:26,
  count:label,emoji:null,iconWidth:20,countX:32,avatarCount:0,background:Object.freeze({id:++shapeId}),
  fill:chosen?color(60,120,180,255):color(),...extra});
}
const plan=chips=>({chips});
const snapshot=()=>({...calls});
function stable(motion){
 const array=motion.items,items=[...array],fills=items.map(x=>x.fill),shapes=items.map(x=>x.chip.background),labels=items.map(x=>x.chip.count);
 return {array,items,fills,shapes,labels};
}
function assertStable(motion,s){
 assert.equal(motion.items,s.array);
 for(let i=0;i<motion.items.length;i++){
  assert.equal(motion.items[i],s.items[i]);assert.equal(motion.items[i].fill,s.fills[i]);
  assert.equal(motion.items[i].chip.background,s.shapes[i]);assert.equal(motion.items[i].chip.count,s.labels[i]);
 }
}
{
 const motion=new ReactionMotion(),first=plan([chip('a',1,true)]);
 assert.equal(motion.bind(first,'chat:1',0,true,'day'),'','cold selected row must not replay animation');
 assert.equal(motion.items[0].progress,1);assert.equal(motion.sample(20),false);
 const s=stable(motion),before=snapshot();
 first.chips=new Proxy(first.chips,{get(){throw Error('warm binding must not read chips');}});
 for(let i=0;i<10000;i++)assert.equal(motion.bind(first,'chat:1',i,true,'day'),'');
 assert.deepEqual(calls,before);assertStable(motion,s);
}
{
 const motion=new ReactionMotion(),a=chip('a',1),b=chip('a',2,true);
 motion.bind(plan([a]),'row',0,true);
 assert.equal(motion.bind(plan([b]),'row',10,true),'a');
 const item=motion.items[0];assert.equal(item.previous,a);assert.equal(item.countChanged,true);assert.equal(item.selectionChanged,true);assert.equal(item.direction,1);
 assert.deepEqual({...item.fill},{...a.fill});
 const s=stable(motion),before=snapshot(),native={shapeId,labelId};
 for(let i=0;i<1000;i++)assert.equal(motion.sample(10+DURATION*.5),true);
 assertStable(motion,s);assert.deepEqual(calls,before);assert.deepEqual({shapeId,labelId},native);
 assert.ok(item.fill.alpha>a.fill.alpha&&item.fill.alpha<b.fill.alpha);
 const progress=item.progress;motion.sample(0);assert.equal(item.progress,progress,'backwards clock cannot rewind');
 assert.equal(motion.sample(10+DURATION),false);assert.equal(item.previous,null);assert.equal(item.direction,0);
 assert.deepEqual({...item.fill},{...b.fill});assert.equal(item.scale,1);
 assert.equal(motion.bind(plan([chip('a',1,false)]),'row',500,true),'');assert.equal(motion.items[0].direction,-1);
 motion.finish();assert.equal(motion.sample(501),false);assert.equal(motion.items[0].previous,null);
}
{
 const motion=new ReactionMotion();motion.bind(plan([chip('a')]),'row',0,true);
 const changed=plan([chip('a',2,true)]);motion.bind(changed,'row',10,true);motion.sample(50);
 const item=motion.items[0],progress=item.progress,start=item.startedAt;
 // A new photo path/snapshot and changed wrapping are not a second reaction.
 const reflow=plan([chip('a',2,true,{x:80,y:30,width:90})]);
 assert.equal(motion.bind(reflow,'row',50,true),'');assert.equal(motion.items[0],item);assert.equal(item.startedAt,start);assert.equal(item.progress,progress);
 assert.equal(item.x,80);assert.equal(item.y,30);assert.equal(item.chip.width,90);
 assert.equal(motion.sample(10+DURATION),false);
}
{
 const motion=new ReactionMotion();motion.bind(plan([chip('a',1,false)]),'row',0,true);
 motion.bind(plan([chip('a',2,true)]),'row',10,true);motion.sample(80);
 const midpoint={...motion.items[0].fill};
 motion.bind(plan([chip('a',1,false)]),'row',80,true);
 assert.deepEqual({...motion.items[0].fill},midpoint,'interrupted color starts from displayed fill, not the previous endpoint');
 assert.equal(motion.items[0].direction,-1);assert.equal(motion.items[0].previous.reaction.count,2);
 motion.sample(80+DURATION);assert.deepEqual({...motion.items[0].fill},{...color()});
}
{
 const motion=new ReactionMotion();motion.bind(plan([chip('a')]),'row',0,true);
 assert.equal(motion.bind(plan([chip('b',1,true)]),'row',10,true),'b');
 assert.equal(motion.items.length,2);assert.equal(motion.items[0].entering,true);assert.equal(motion.items[1].leaving,true);
 assert.equal(motion.items[0].scale,.75);motion.sample(10+DURATION*.5);
 assert.ok(motion.items[0].scale>.75);assert.ok(motion.items[1].scale<1);
 assert.equal(motion.sample(10+DURATION),false);assert.equal(motion.items.length,1);assert.equal(motion.items[0].chip.key,'b');
 assert.equal(motion.items[0].entering,false);
 // Repeated interrupted revisions only keep current targets plus one set of exits.
 for(let i=0;i<1000;i++){
  motion.bind(plan([chip('k'+i,1,i%2===0)]),'row',1000+i,true);
  assert.ok(motion.items.length<=2);assert.equal(motion.byKey.size,1);
 }
 motion.finish();assert.equal(motion.items.length,1);assert.equal(motion.items[0].previous,null);
}
{
 const motion=new ReactionMotion();motion.bind(plan([chip('a')]),'row',0,true,'day');
 const b=plan([chip('a',2,true)]);motion.bind(b,'row',10,true,'day');
 assert.equal(motion.bind(b,'row',20,false,'day'),'');assert.equal(motion.items[0].progress,1);
 assert.equal(motion.sample(25),false,'scroll/power gate settles immediately even without a plan change');
 motion.bind(plan([chip('a',8,true)]),'row',26,false,'day');assert.equal(motion.items[0].direction,0);assert.equal(motion.items[0].countChanged,false);
 assert.equal(motion.bind(plan([chip('a',3,true)]),'other',30,true,'day'),'');assert.equal(motion.items[0].progress,1);
 assert.equal(motion.bind(plan([chip('a',4,true)]),'row',40,true,'day'),'');assert.equal(motion.items[0].progress,1,'A/B/A owner must not replay A');
 assert.equal(motion.bind(plan([chip('a',5,true)]),'row',50,true,'night'),'');assert.equal(motion.items[0].progress,1);
 motion.bind(plan([chip('a',6,true)]),'row',60,true,'night');assert.equal(motion.sample(NaN),false);assert.equal(motion.items[0].progress,1);
 motion.clear();assert.equal(motion.items.length,0);assert.equal(motion.byKey.size,0);assert.equal(motion.sample(999),false);
 assert.equal(motion.bind(b,'row',1000,true,'day'),'');assert.equal(motion.items[0].progress,1);
}
{
 const motion=new ReactionMotion(),N=12000;
 const old=plan(Array.from({length:N},(_,i)=>chip(String(i))));motion.bind(old,'row',0,true);
 const before=snapshot();
 const next=plan(Array.from({length:N},(_,i)=>chip(String(N-1-i),2,i===0,{x:i%10*64,y:Math.floor(i/10)*30})));
 assert.equal(motion.bind(next,'row',10,true),String(N-1));
 assert.equal(calls.get-before.get,N);assert.equal(calls.has-before.has,N);assert.equal(calls.set-before.set,N);
 assert.equal(motion.items.length,N);assert.equal(motion.items[0].previous.key,String(N-1));
 const s=stable(motion),beforeSample=snapshot();motion.sample(10+DURATION/2);assert.deepEqual(calls,beforeSample);assertStable(motion,s);
 motion.finish();assert.equal(motion.items.length,N);
 // Width-only or count-preserving snapshots do not start a new animation.
 const reflow=plan(next.chips.map((c,i)=>Object.freeze({...c,width:100,x:i%7*104,y:Math.floor(i/7)*30})));
 assert.equal(motion.bind(reflow,'row',500,true),'');assert.equal(motion.sample(501),false);
}
{
 const motion=new ReactionMotion();motion.bind(plan([chip('a')]),'row',0,true);
 const arrow=chip('reactors',0,false,{reaction:null,count:null});
 motion.bind(plan([arrow]),'row',10,true);assert.equal(motion.items[0].progress,1,'navigation arrow is not a reaction animation');
 motion.finish();assert.equal(motion.items.length,1);motion.bind(plan([]),'row',20,true);assert.equal(motion.items.length,0);
 assert.equal(motion.sample(21),false);assert.equal(motion.bind(plan([chip('new',1,true)]),'row',30,true),'new');
}
console.log('PASS: reaction count/color/entry/exit motion, 10000 O(1) warm binds, 12000-chip linear keyed diff, allocation-free sampled identities, interrupt/reflow continuity, owner/environment/gate reset and bounded cleanup.');
