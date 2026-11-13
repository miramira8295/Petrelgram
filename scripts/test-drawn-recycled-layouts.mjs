// Exclusive layout leases: real paragraph/cache work is counted, never ms.
import assert from 'node:assert/strict';
import vm from 'node:vm';
import {ctx,load,root,ui,data,style,group,layoutCounters} from './test-drawn-text-row.mjs';
vm.runInContext('globalThis.DrawnRecycledLayouts = DrawnRecycledLayouts;',ctx);
let time=100, nextTimer=0;
const timers=new Map();
ctx.setTimeout=fn=>{timers.set(++nextTimer,fn);return nextTimer;};ctx.clearTimeout=id=>timers.delete(id);
const owner={}, other={}, pool=new ctx.DrawnRecycledLayouts(()=>time);
const a=new ctx.DrawnTextLayouts(), g=group('cached link https://a.test');
const first=a.prepare(ui,g,data,style), before=layoutCounters();
pool.put(owner,'1:10:text','text',a);
const adopted=pool.take(owner,'1:10:text','text');assert.equal(adopted,a);
assert.equal(pool.take(owner,'1:10:text','text'),undefined,'one engine never has two active owners');
const wrapper={vp2px:n=>n*2,fp2px:n=>n*2};
const current=adopted.prepare(wrapper,{...g,head:{...g.head}},{...data},style);
assert.equal(current.caption,first.caption);assert.equal(layoutCounters().bodyLayouts,before.bodyLayouts);
// Editing, width, font and environment must still validate on adoption.
for(const [message,d,s] of [
 [{...g,head:{...g.head,text:'edited'}},data,style],
 [g,{...data,contentWidth:200},style],
 [g,data,{...style,fontSize:24}],
 [g,data,{...style,environment:'new',textEnvironment:'new'}]
]) {
 pool.put(owner,'1:10:text','text',adopted);
 const engine=pool.take(owner,'1:10:text','text'),count=layoutCounters().bodyLayouts;
 const result=engine.prepare(wrapper,message,d,s);
 assert.ok(layoutCounters().bodyLayouts>count);assert.notEqual(result.caption,first.caption);
 const cold=new ctx.DrawnTextLayouts().prepare(wrapper,message,d,s);
 assert.equal(result.height,cold.height);assert.equal(result.width,cold.width);
 assert.equal(result.caption.source.content,cold.caption.source.content);
}
pool.clear();assert.equal(timers.size,0);
// Misses reuse the right engine TYPE without allocation or scanning other kinds.
const text={},album={},single={};
pool.put(owner,'t','text',text);pool.put(owner,'a','album',album);pool.put(owner,'s','single',single);
assert.equal(pool.take(owner,'new-album','album'),album);
assert.equal(pool.take(owner,'new-text','text'),text);
assert.equal(pool.take(owner,'new-single','single'),single);
assert.equal(pool.take(owner,'nothing','album'),undefined);
pool.clear();
const initialTimers=nextTimer;
for(let i=0;i<1000;i++) {
 pool.put(owner,`key${i}`,'album',{i});
 assert.ok(pool.entries.size<=8);assert.equal(pool.albums.size,pool.entries.size);
}
assert.equal(nextTimer-initialTimers,1,'rapid recycling posts one cleanup timer, not 1000');
assert.equal(pool.entries.has('key991'),false);assert.equal(pool.take(owner,'key999','album').i,999);
time+=10001;assert.equal(pool.take(owner,'key998','album'),undefined,'expired exact and fallback entries are not leased');
pool.put(owner,'one','text',a);assert.equal(pool.take(other,'one','text'),undefined,'account change drops old leases');
pool.clear();assert.equal(timers.size,0);
// Retention captures the old account; a recycle after switching cannot relabel it.
const global=ctx.drawnRecycledLayouts;global.clear();let account=owner;ctx.getTdClient=()=>account;
const retention=new ctx.DrawnLayoutRetention();retention.remember(g,data,'text',a);
account=other;retention.release();assert.equal(global.entries.size,0);
account=owner;retention.remember({...g,head:{...g.head,text:'x'.repeat(8193)}},data,'text',a);
retention.remember(g,data,'text',a);retention.release();assert.equal(global.entries.size,0,'large prior inputs disqualify the whole retained lease');
retention.remember(g,data,'text',new ctx.DrawnTextLayouts());retention.release();assert.equal(global.entries.size,1);
retention.release();assert.equal(global.entries.size,1,'double recycle cannot offer twice');
for(const fn of [...timers.values()])fn();assert.equal(global.entries.size,0);assert.equal(timers.size,0);
// Exercise the real compiler-generated row getter and recycle method together.
// A cached engine must be removed from the old owner before the new one uses it.
const makeRow = () => Object.assign(Object.create(ctx.DrawnMessageRow.prototype), {
 kind:'text', group:g, data, env:{appearanceEpoch:1,langEpoch:1,bubbleMaterialOn:false,bubbleRadius:20,msgTextSize:16},
 a11y:{active:false}, translation:null, role:'', views:'', textLayouts:null, albumLayouts:null, singleLayouts:null,
 layoutRetention:new ctx.DrawnLayoutRetention(), getUIContext:()=>wrapper,
 active:true, mediaVisibilityEpoch:0, routeTracker:undefined, leaveCapture:{reset(){}}, dragGesture:{reset(){}},
 channels:{detach(){}}, media:{recycle(){}}, foreground:{press(){}}
});
let previous=makeRow(), plan=previous.plan, work=layoutCounters().bodyLayouts;
const original=plan.caption;
for(let i=0;i<1000;i++) {
 const engine=previous.textLayouts;
 previous.aboutToRecycle();assert.equal(previous.textLayouts,null,'released owner drops its engine');
 const next=makeRow();assert.equal(next.plan.caption,original);assert.equal(next.textLayouts,engine);
 assert.equal(global.entries.size,0,'a live row exclusively owns the engine');
 previous=next;
}
assert.equal(layoutCounters().bodyLayouts,work,'1000 compiled handoffs never shape the same body again');
previous.aboutToRecycle();global.clear();assert.equal(timers.size,0);
console.log('PASS: exclusive real paragraph adoption, current wrapper/width/font/edit/theme validation, typed miss reuse, eight-engine bound, one timer for 1000 returns, TTL, account switch, oversized-history exclusion and double recycle.');
