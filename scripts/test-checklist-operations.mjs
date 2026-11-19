import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
const imported=await import(process.env.TYPESCRIPT_MODULE||'typescript'),ts=imported.default||imported;
class TdError extends Error {constructor(code,message){super(message);this.code=code;}}
const ctx=vm.createContext({TdError,str:key=>key});
function load(name,exports){const s=fs.readFileSync('entry/src/main/ets/util/'+name+'.ets','utf8').replace(/^import\s[\s\S]*?;\r?\n/gm,'').replace(/\bexport /g,'');vm.runInContext(ts.transpileModule(s+exports.map(n=>`\nglobalThis.${n}=${n};`).join(''),{compilerOptions:{target:ts.ScriptTarget.ES2020}}).outputText,ctx);}
load('checklistStateChannel',['IDLE_CHECKLIST_ACTION','checklistActionState','publishChecklistAction','subscribeChecklistAction']);
load('checklistRequest',['inputChecklist','markChecklistRequest']);load('checklistOperations',['ChecklistOperations']);
const plain=value=>JSON.parse(JSON.stringify(value));
const deferred=()=>{let resolve,reject;const promise=new Promise((a,b)=>{resolve=a;reject=b;});return{promise,resolve,reject};};
const flush=async()=>{for(let i=0;i<5;i++)await Promise.resolve();};
function client(){const calls=[],jobs=[];return{calls,jobs,send(request){calls.push(plain(request));const job=deferred();jobs.push(job);return job.promise;}};}
const model=(done=false)=>({taskById:new Map([[42,{id:42,completionDate:done?123:0}],[7,{id:7,completionDate:0}]])});
const state=(c,id=10)=>ctx.checklistActionState(c,5,id);
const doneRequest={ '@type':'markChecklistTasksAsDone',chat_id:5,message_id:10,marked_as_done_task_ids:[42],marked_as_not_done_task_ids:[] };
assert.deepEqual(plain(ctx.markChecklistRequest(5,10,42,true)),doneRequest);
assert.deepEqual(plain(ctx.markChecklistRequest(5,10,42,false)),{...doneRequest,marked_as_done_task_ids:[],marked_as_not_done_task_ids:[42]});
for(const id of [NaN,Infinity,1.5,2147483648,-2147483649])assert.throws(()=>ctx.markChecklistRequest(5,10,id,true));
const input=plain(ctx.inputChecklist(' Plan ',[' one ','','two','  '],true,false));assert.equal(input['@type'],'inputChecklist');assert.equal(input.title.text,'Plan');assert.deepEqual(input.tasks.map(t=>[t['@type'],t.id,t.text.text]),[['inputChecklistTask',1,'one'],['inputChecklistTask',2,'two']]);assert.equal(input.others_can_add_tasks,true);assert.equal(input.others_can_mark_tasks_as_done,false);assert.throws(()=>ctx.inputChecklist(' ',['one'],false,false));assert.throws(()=>ctx.inputChecklist('Plan',[' '],false,false));
// Pending is immediate, one in-flight command per message, and completion is
// never synthesized before the server refresh has supplied authoritative data.
{
 const c=client();let current=model(),refreshes=0;const refreshed=deferred();const op=new ctx.ChecklistOperations(c,5,()=>current,async id=>{assert.equal(id,10);refreshes++;await refreshed.promise;current=model(true);},()=>true);
 const work=op.toggle(10,42,true);assert.equal(state(c).pendingTaskIds.has(42),true);assert.equal(op.toggle(10,7,true),work);await flush();assert.deepEqual(c.calls,[{'@type':'getMessageProperties',chat_id:5,message_id:10}]);
 c.jobs[0].resolve({can_mark_tasks_as_done:true});await flush();assert.deepEqual(c.calls[1],doneRequest);assert.equal(current.taskById.get(42).completionDate,0);c.jobs[1].resolve({'@type':'ok'});await flush();assert.equal(refreshes,1);assert.equal(current.taskById.get(42).completionDate,0);assert.equal(state(c).pendingTaskIds.has(42),true);
 refreshed.resolve();await work;assert.equal(current.taskById.get(42).completionDate,123);assert.equal(state(c),ctx.IDLE_CHECKLIST_ACTION);assert.equal(op.pending.size,0);
}
// Permission is read before mutation and Premium/server errors are surfaced in
// the local fixed footer state, with an empty pending set and a usable retry.
{
 const c=client();let refreshes=0;const op=new ctx.ChecklistOperations(c,5,()=>model(),async()=>{refreshes++;},()=>true);let work=op.toggle(10,42,true);const denied=assert.rejects(work,e=>e.code===403&&e.message==='checklist_readonly');await flush();c.jobs[0].resolve({can_mark_tasks_as_done:false});await denied;assert.equal(c.calls.length,1);assert.equal(refreshes,0);assert.equal(state(c).error,'checklist_readonly');assert.equal(state(c).pendingTaskIds.size,0);
 work=op.toggle(10,42,true);const premium=assert.rejects(work,e=>e.code===400&&e.message==='PREMIUM_ACCOUNT_REQUIRED');assert.equal(state(c).error,'');await flush();c.jobs[1].resolve({can_mark_tasks_as_done:true});await flush();c.jobs[2].reject(new TdError(400,'PREMIUM_ACCOUNT_REQUIRED'));await premium;assert.equal(refreshes,0);assert.equal(state(c).error,'PREMIUM_ACCOUNT_REQUIRED');assert.equal(state(c).pendingTaskIds.size,0);assert.equal(op.pending.size,0);
}
// A server update that wins the race while permissions load must prevent a
// second completion mutation, rather than toggling from the initial snapshot.
{
 const c=client();let current=model(),refreshes=0;const op=new ctx.ChecklistOperations(c,5,()=>current,async()=>{refreshes++;},()=>true);const work=op.toggle(10,42,true);await flush();current=model(true);c.jobs[0].resolve({can_mark_tasks_as_done:true});await work;assert.equal(c.calls.length,1);assert.equal(refreshes,0);assert.equal(state(c),ctx.IDLE_CHECKLIST_ACTION);
 const missing=op.toggle(10,999,true);await assert.rejects(missing,e=>e.code===400);assert.equal(c.calls.length,1);
}
// Failed authoritative refresh is not replaced with optimistic checkbox data.
{
 const c=client(),current=model();const op=new ctx.ChecklistOperations(c,5,()=>current,async()=>{throw new Error('refresh failed');},()=>true);const work=op.toggle(10,42,true),rejected=assert.rejects(work,/refresh failed/);await flush();c.jobs[0].resolve({can_mark_tasks_as_done:true});await flush();c.jobs[1].resolve({'@type':'ok'});await rejected;assert.equal(current.taskById.get(42).completionDate,0);assert.equal(state(c).error,'refresh failed');assert.equal(state(c).pendingTaskIds.size,0);
}
// close() invalidates queued permissions/mutation acknowledgements and clears
// only the state owned by that operation, never a newer controller's pending.
{
 const c=client();let refreshes=0;const op=new ctx.ChecklistOperations(c,5,()=>model(),async()=>{refreshes++;},()=>true);const work=op.toggle(10,42,true);await flush();op.close();assert.equal(state(c),ctx.IDLE_CHECKLIST_ACTION);c.jobs[0].resolve({can_mark_tasks_as_done:true});await work;assert.equal(c.calls.length,1);assert.equal(refreshes,0);await op.toggle(10,7,true);assert.equal(c.calls.length,1);
}
{
 const c=client();let current=true,refreshes=0;const op=new ctx.ChecklistOperations(c,5,()=>model(),async()=>{refreshes++;},()=>current);const work=op.toggle(10,42,true);await flush();current=false;c.jobs[0].resolve({can_mark_tasks_as_done:true});await work;op.close();assert.equal(refreshes,0);assert.equal(c.calls.length,1);assert.equal(state(c),ctx.IDLE_CHECKLIST_ACTION,'inactive completion then late close cannot leave an old-account spinner forever');
}
{
 const c=client();let refreshes=0;const a=new ctx.ChecklistOperations(c,5,()=>model(),async()=>{refreshes++;},()=>true);const first=a.toggle(10,42,true);await flush();c.jobs[0].resolve({can_mark_tasks_as_done:true});await flush();const b=new ctx.ChecklistOperations(c,5,()=>model(),async()=>{},()=>true);const second=b.toggle(10,7,true);await flush();const secondState=state(c);assert.equal(secondState.pendingTaskIds.has(7),true);a.close();assert.equal(state(c),secondState,'old close cannot erase newer message action state');c.jobs[1].resolve({'@type':'ok'});await first;assert.equal(refreshes,0);assert.equal(state(c),secondState);b.close();c.jobs[2].resolve({can_mark_tasks_as_done:true});await second;assert.equal(state(c),ctx.IDLE_CHECKLIST_ACTION);
}
// An active subscriber's state is not part of the bounded recent-error cache;
// unsubscribe is idempotent and other subscribers retain their own deliveries.
{
 const a={},b={},seenA=[],seenB=[];const offA=ctx.subscribeChecklistAction(a,1,999,s=>seenA.push(s));const offB=ctx.subscribeChecklistAction(a,1,999,s=>seenB.push(s));const pending={pendingTaskIds:new Set([42]),error:''};ctx.publishChecklistAction(a,1,999,pending);assert.equal(seenA.length,1);assert.equal(seenB.length,1);
 for(let i=0;i<200;i++)ctx.publishChecklistAction(a,1,i,{pendingTaskIds:new Set(),error:`error ${i}`});assert.equal(ctx.checklistActionState(a,1,999),pending);assert.equal(ctx.checklistActionState(a,1,0),ctx.IDLE_CHECKLIST_ACTION);assert.equal(ctx.checklistActionState(a,1,71),ctx.IDLE_CHECKLIST_ACTION);assert.equal(ctx.checklistActionState(a,1,72).error,'error 72');let count=0;for(let i=0;i<200;i++)if(ctx.checklistActionState(a,1,i)!==ctx.IDLE_CHECKLIST_ACTION)count++;assert.equal(count,128);
 offA();offA();const failure={pendingTaskIds:new Set(),error:'failure'};ctx.publishChecklistAction(a,1,999,failure);assert.equal(seenA.length,1);assert.equal(seenB.length,2);offB();offB();assert.equal(ctx.checklistActionState(a,1,999),failure);ctx.publishChecklistAction(a,1,999,ctx.IDLE_CHECKLIST_ACTION);assert.equal(ctx.checklistActionState(a,1,999),ctx.IDLE_CHECKLIST_ACTION);ctx.publishChecklistAction(b,1,999,pending);assert.equal(ctx.checklistActionState(a,1,999),ctx.IDLE_CHECKLIST_ACTION);assert.equal(ctx.checklistActionState(b,1,999),pending);
}
// No-op and cancelled preflight do not flash pending or issue stale account IO.
{
 const c=client();const op=new ctx.ChecklistOperations(c,5,()=>model(true),async()=>{throw new Error('no refresh');},()=>true);await op.toggle(10,42,true);assert.equal(c.calls.length,0);assert.equal(state(c),ctx.IDLE_CHECKLIST_ACTION);assert.equal(op.pending.size,0);
 const closed=new ctx.ChecklistOperations(c,5,()=>model(),async()=>{},()=>true);const work=closed.toggle(10,42,true);closed.close();await work;assert.equal(c.calls.length,0);assert.equal(state(c),ctx.IDLE_CHECKLIST_ACTION);
 let current=true;const switched=new ctx.ChecklistOperations(c,5,()=>model(),async()=>{},()=>current);const old=switched.toggle(10,42,true);current=false;await old;assert.equal(c.calls.length,0);assert.equal(state(c),ctx.IDLE_CHECKLIST_ACTION);
}
// Task removal between permission lookup and mutation is surfaced atomically.
{
 const c=client();let current=model();const op=new ctx.ChecklistOperations(c,5,()=>current,async()=>{},()=>true);const work=op.toggle(10,42,true),removed=assert.rejects(work,e=>e.code===400&&e.message==='checklist_task_missing');await flush();current=null;c.jobs[0].resolve({can_mark_tasks_as_done:true});await removed;assert.equal(c.calls.length,1);assert.equal(state(c).pendingTaskIds.size,0);assert.equal(state(c).error,'checklist_task_missing');
}
// A late mutation error is observed by its caller but cannot publish into a
// new account or replace a newer operation's state under the same old account.
{
 const c=client(),other={};let current=true;const op=new ctx.ChecklistOperations(c,5,()=>model(),async()=>{throw new Error('must not refresh');},()=>current);const work=op.toggle(10,42,true),late=assert.rejects(work,/late mutation/);await flush();c.jobs[0].resolve({can_mark_tasks_as_done:true});await flush();const newer={pendingTaskIds:new Set([7]),error:''};ctx.publishChecklistAction(c,5,10,newer);const otherState={pendingTaskIds:new Set(),error:'new account error'};ctx.publishChecklistAction(other,5,10,otherState);current=false;c.jobs[1].reject(new Error('late mutation'));await late;op.close();assert.equal(state(c),newer);assert.equal(ctx.checklistActionState(other,5,10),otherState);
}
// Serialization is by message ID, not a global lock across different messages.
{
 const c=client();const op=new ctx.ChecklistOperations(c,5,()=>model(),async()=>{},()=>true);const a=op.toggle(10,42,true),b=op.toggle(11,7,true);await flush();assert.deepEqual(c.calls.map(r=>r.message_id),[10,11]);op.close();for(const job of c.jobs)job.resolve({can_mark_tasks_as_done:true});await Promise.all([a,b]);assert.equal(c.calls.length,2);
}
console.log('PASS: official checklist requests, permission/Premium errors and retries, per-message dedup, authoritative refresh, server-update race, close/account/late ownership guards and bounded account-isolated action channel.');
