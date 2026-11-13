import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
const ts=(await import(process.env.TYPESCRIPT_MODULE||'typescript')).default;
const ctx=vm.createContext({});
const source=fs.readFileSync('entry/src/main/ets/util/drawnFrameQueue.ets','utf8').replace(/\bexport /g,'');
vm.runInContext(ts.transpileModule(source+'\nglobalThis.Queue=DrawnFrameQueue;', {compilerOptions:{target:ts.ScriptTarget.ES2020}}).outputText,ctx);
let now=0,frames=[],seen=[],errors=[];
const schedule=fn=>frames.push(fn);
const next=()=>{const jobs=frames;frames=[];for(const job of jobs)job();};
const q=new ctx.Queue(()=>now,e=>errors.push(e.message));
// All rows share the two-job cap; urgent jobs lead without starving prediction.
for(let i=0;i<6;i++)q.enqueue(schedule,()=>seen.push('background'+i),false);
for(let i=0;i<8;i++)q.enqueue(schedule,()=>seen.push('visible'+i),true);
assert.equal(frames.length,1);next();assert.deepEqual(seen,['visible0','visible1']);
next();assert.deepEqual(seen.slice(2),['visible2','background0']);
while(frames.length)next();assert.equal(seen.length,14);
// At least one long task can overrun; a second task cannot start after budget.
seen=[];q.enqueue(schedule,()=>{seen.push(1);now+=3;},true);q.enqueue(schedule,()=>seen.push(2),true);
next();assert.deepEqual(seen,[1]);next();assert.deepEqual(seen,[1,2]);
// Cancel unlinks immediately; the single generic frame can run only current work.
seen=[];let a=q.enqueue(schedule,()=>seen.push('old'),false);q.cancel(a);q.cancel(a);
q.enqueue(schedule,()=>seen.push('new'),false);assert.equal(frames.length,1);next();assert.deepEqual(seen,['new']);
// Promote/demote without queue scans and cap memory under cancellation churn.
seen=[];a=q.enqueue(schedule,()=>seen.push('a'),false);let b=q.enqueue(schedule,()=>seen.push('b'),false);q.priority(b,true);next();assert.deepEqual(seen,['b','a']);
for(let i=0;i<10000;i++){const n=q.enqueue(schedule,()=>{throw Error('cancelled');},false);q.cancel(n);}
assert.equal(frames.length,1,'cancellation churn keeps at most one posted frame');
while(frames.length)next();assert.match(q.summary(),/pending=0/);assert.equal(errors.length,0);
const bounded=new ctx.Queue(()=>now,e=>errors.push(e.message),2,1,3);
for(let i=0;i<3;i++)assert.ok(bounded.enqueue(schedule,()=>{},false));
assert.equal(bounded.enqueue(schedule,()=>{},false),null);assert.match(bounded.summary(),/overflow=1/);
while(frames.length)next();
// Re-entrant enqueue cannot drain unlimited work in the same callback.
seen=[];q.enqueue(schedule,()=>{seen.push('parent');q.enqueue(schedule,()=>seen.push('child'),true);},true);
next();assert.deepEqual(seen,['parent']);next();assert.deepEqual(seen,['parent','child']);
q.enqueue(schedule,()=>{throw Error('job failed');},true);q.enqueue(schedule,()=>seen.push('survivor'),true);
next();assert.deepEqual(errors,['job failed']);assert.equal(seen.at(-1),'survivor');
console.log('PASS: shared budget/count limit, FIFO and priority fairness, cancellation ABA, bounded occupancy, re-entrancy and error recovery.');
