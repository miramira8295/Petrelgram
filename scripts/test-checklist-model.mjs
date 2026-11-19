import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
const imported=await import(process.env.TYPESCRIPT_MODULE||'typescript'),ts=imported.default||imported;
const ctx=vm.createContext({});
const source=fs.readFileSync('entry/src/main/ets/util/checklistModel.ets','utf8').replace(/^import\s[\s\S]*?;\r?\n/gm,'').replace(/\bexport /g,'');
vm.runInContext(ts.transpileModule(source+'\nglobalThis.parse=parseChecklist;',{compilerOptions:{target:ts.ScriptTarget.ES2020}}).outputText,ctx);
const ft=(text,entities=[])=>({text,entities});
const task=(id,text,done=0)=>({id,text:ft(text),completed_by:done?{'@type':'messageSenderUser',user_id:70}:null,completion_date:done});
const raw={title:ft('Plan'),tasks:[task(42,'First'),task(7,'Second',100)],can_mark_tasks_as_done:true};
const original=JSON.stringify(raw),first=ctx.parse(raw);assert.ok(first);assert.equal(first.completedCount,1);assert.deepEqual(Array.from(first.tasks,t=>t.id),[42,7]);assert.equal(first.taskById.get(7).text,'Second');assert.equal(first.preview,'Plan\n☐ First\n☑ Second');assert.equal(JSON.stringify(raw),original);
for(let i=0;i<1000;i++)assert.equal(ctx.parse(raw),first);
let current=first;
for(let i=0;i<1000;i++) {
 const snap=JSON.parse(original);snap.tasks[0].completion_date=i%2?102:0;snap.tasks[0].completed_by=i%2?{'@type':'messageSenderChat',chat_id:-100}:null;
 const next=ctx.parse(snap,current);assert.equal(next.geometry,first.geometry);assert.equal(next.tasks[1],first.tasks[1]);assert.equal(next.title,first.title);assert.equal(next.tasks[0].completed,!!(i%2));current=next;
}
const identical=ctx.parse(JSON.parse(JSON.stringify({...raw,tasks:[task(42,'First'),task(7,'Second',100)]})),first);assert.equal(identical,first,'equivalent fresh TD snapshots preserve all identities');
const permissions=ctx.parse({...raw,can_mark_tasks_as_done:false},first);assert.equal(permissions.geometry,first.geometry);assert.equal(permissions.tasks[0],first.tasks[0]);assert.notEqual(permissions.signature,first.signature);
const changed=ctx.parse({...raw,tasks:[task(42,'edited'),task(7,'Second',100)]},first);assert.notEqual(changed.geometry,first.geometry);assert.equal(changed.tasks[1],first.tasks[1]);assert.equal(changed.geometry.tasks[1],first.geometry.tasks[1]);
const reordered=ctx.parse({...raw,tasks:[raw.tasks[1],raw.tasks[0]]},first);assert.deepEqual(Array.from(reordered.tasks,t=>t.id),[7,42]);assert.equal(reordered.taskById.get(42),first.taskById.get(42));assert.notEqual(reordered.geometry,first.geometry);
for(const value of [undefined,null,{}, {...raw,tasks:[null]}, {...raw,tasks:[task(1,'a'),task(1,'duplicate')]}, {...raw,tasks:[task(Infinity,'bad')]}, {...raw,tasks:[task(1.2,'bad')]}, {...raw,tasks:[{id:1,text:ft('x',[{offset:0,length:2,type:{'@type':'textEntityTypeBold'}}])}]}])assert.equal(ctx.parse(value),null);
assert.equal(ctx.parse({...raw,tasks:[]}).tasks.length,0);
const many={title:ft('Large'),tasks:Array.from({length:10000},(_,i)=>task(i,`task ${i}`)),can_mark_tasks_as_done:true};const all=ctx.parse(many);assert.equal(all.tasks.length,10000);assert.equal(all.taskById.get(9999).text,'task 9999');assert.ok(all.preview.endsWith('☐ task 9999'));
const largeDone=ctx.parse({...many,tasks:many.tasks.map((t,i)=>i===9999?{...t,completion_date:123,completed_by:{'@type':'messageSenderUser',user_id:7}}:t)},all);assert.equal(largeDone.geometry,all.geometry);assert.equal(largeDone.tasks[0],all.tasks[0]);assert.equal(largeDone.completedCount,1);
console.log('PASS: immutable checklist model, ordered sparse IDs, 1000 raw/equivalent/status snapshots without geometry churn, permissions/reorder/edit, malformed atomic rejection and complete 10000-task list.');
