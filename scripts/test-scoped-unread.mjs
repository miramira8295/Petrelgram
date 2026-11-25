import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
const ts = (await import(process.env.TYPESCRIPT_MODULE || 'typescript')).default;
const base = 'entry/src/main/ets/';
const timers = new Map(); let timerId = 0;
const ctx = vm.createContext({
  setTimeout: fn => { timers.set(++timerId, fn); return timerId; },
  clearTimeout: id => timers.delete(id)
});
function run(code) { vm.runInContext(ts.transpileModule(code, { compilerOptions: { target: ts.ScriptTarget.ES2020 } }).outputText, ctx); }
function load(path, names) {
  const code = fs.readFileSync(base + path, 'utf8').replace(/^import\s[\s\S]*?;\r?\n/gm, '').replace(/\bexport /g, '');
  run(code + names.map(n => `\nglobalThis.${n}=${n};`).join(''));
}
function method(path, cls, name) {
  const ast = ts.createSourceFile(path, fs.readFileSync(base + path, 'utf8'), ts.ScriptTarget.Latest, true);
  return ast.statements.find(n => ts.isClassDeclaration(n) && n.name.text === cls).members
    .find(n => ts.isMethodDeclaration(n) && n.name.getText(ast) === name).getText(ast);
}
const flush = async () => { for (let i = 0; i < 8; i++) await Promise.resolve(); };
const tick = async () => { const pending = [...timers.values()]; timers.clear(); pending.forEach(fn => fn()); await flush(); };
load('util/messageTopicScope.ets', ['messageOutsideTopicScope']);
load('store/ScopedUnreadState.ets', ['ScopedUnreadState']);
load('util/viewReceiptQueue.ets', ['ViewReceiptQueue']);

function scope(thread=40, forum=0, direct=0) {
  const pending=[], events=new Map(), values=[];
  const host={send:req=>new Promise((resolve,reject)=>pending.push({req,resolve,reject})),
    onUpdate:(type,fn)=>{events.set(type,fn);return()=>events.delete(type);}};
  const state=new ctx.ScopedUnreadState(host, -100, thread, forum, direct);
  state.subscribe(n=>values.push(n)); state.open();
  return {state,pending,events,values};
}
const threadResult=(n,last=90)=>({chat_id:-100,message_thread_id:40,unread_message_count:n,reply_info:{last_message_id:last}});
const s=scope(); assert.equal(s.pending[0].req['@type'],'getMessageThread');
s.pending.shift().resolve(threadResult(6)); await flush(); assert.deepEqual(s.values,[0,6]);
// Other-thread updates do not query; a burst in the same thread coalesces.
s.events.get('updateNewMessage')({message:{chat_id:-100,message_thread_id:41}});
assert.equal(timers.size,0);
for(let i=0;i<100;i++) s.events.get('updateMessageInteractionInfo')({chat_id:-100,message_id:40});
assert.equal(timers.size,1); await tick(); assert.equal(s.pending.length,1);
const stale=s.pending.shift(); s.state.readConfirmed(90); assert.equal(s.values.at(-1),0);
stale.resolve(threadResult(6)); await flush(); assert.equal(s.values.at(-1),0);
await tick(); s.pending.shift().resolve(threadResult(6)); await flush();
assert.equal(s.values.at(-1),0,'stale server count cannot undo acknowledged full read');
s.events.get('updateNewMessage')({message:{chat_id:-100,message_thread_id:40}});
await tick(); s.pending.shift().resolve(threadResult(1,91)); await flush(); assert.equal(s.values.at(-1),1);
s.state.readConfirmed(91); await tick(); s.pending.shift().reject(new Error('network')); await flush();
assert.equal(timers.size,0,'query failures do not spin'); assert.equal(s.values.at(-1),0);
s.state.close(); assert.equal(s.events.size,0);
const partial=scope(); partial.pending.shift().resolve(threadResult(8)); await flush();
partial.state.readConfirmed(60); await tick(); partial.pending.shift().resolve(threadResult(4)); await flush();
assert.equal(partial.values.at(-1),4,'partial read uses scoped server count'); partial.state.close();
for(const [forum,direct,type,result] of [
 [12,0,'getForumTopic',{info:{chat_id:-100,forum_topic_id:12},unread_count:3,last_message:{id:99}}],
 [0,12,'getDirectMessagesChatTopic',{chat_id:-100,id:12,unread_count:3,last_message:{id:99}}]
]) {
 const t=scope(0,forum,direct); assert.equal(t.pending[0].req['@type'],type);
 t.pending.shift().resolve(result); await flush(); assert.equal(t.values.at(-1),3);
 t.state.readConfirmed(99); assert.equal(t.values.at(-1),0); t.state.close();
}
const closed=scope(); closed.state.close(); closed.pending.shift().resolve(threadResult(20)); await flush();
assert.deepEqual(closed.values,[0]); assert.equal(timers.size,0);

const pending=[], confirmed=[]; let failures=0;
const q=new ctx.ViewReceiptQueue({send:id=>new Promise((resolve,reject)=>pending.push({id,resolve,reject})),
 confirmed:id=>confirmed.push(id),failed:()=>failures++});
q.mark(50); for(let i=51;i<=100;i++)q.mark(i);
assert.equal(pending.length,1,'only one in-flight receipt');
pending.shift().reject(new Error('network')); await flush(); assert.deepEqual(confirmed,[]);
await tick(); assert.equal(pending[0].id,100,'retry coalesces latest visible ID');
pending.shift().reject(new Error('network')); await flush(); assert.equal(timers.size,0);
q.mark(100); assert.equal(pending.length,1,'same visible ID retries after exhaustion');
pending.shift().resolve(); await flush(); assert.deepEqual(confirmed,[100]); q.mark(80); assert.equal(pending.length,0);
q.mark(110); q.mark(120); pending.shift().resolve(); await flush(); assert.equal(pending[0].id,120);
q.close(); pending.shift().resolve(); await flush(); assert.deepEqual(confirmed,[100,110]); assert.equal(failures,2);
// Exercise real MessageStore wiring: failed -> same target -> successful,
// with typed source preserved and only success advancing viewedUpTo.
Object.assign(ctx,{drawnStageMetrics:{begin(){},end(){}},DrawnStage:{ReadViewed:0},logE(){}});
run(`class StoreProbe { ${method('store/MessageStore.ets','MessageStore','markViewed')} } globalThis.StoreProbe=StoreProbe;`);
const store=new ctx.StoreProbe(), requests=[], read=[];
Object.assign(store,{viewedUpTo:0,viewReceiptQueue:null,chatId:-100,
 clearManualUnreadFlag(){},viewSource:()=>({'@type':'messageSourceMessageThreadHistory'}),
 scopedUnread:{readConfirmed:id=>read.push(id)},client:{send:req=>new Promise((resolve,reject)=>requests.push({req,resolve,reject}))}});
store.markViewed(80); assert.equal(requests[0].req.source['@type'],'messageSourceMessageThreadHistory');
requests.shift().reject(new Error('timeout')); await flush(); assert.equal(store.viewedUpTo,0);
await tick(); requests.shift().resolve({}); await flush(); assert.equal(store.viewedUpTo,80); assert.deepEqual(read,[80]);
store.viewReceiptQueue.close();
store.closed=true; store.viewReceiptQueue=null; store.markViewed(100);
assert.equal(requests.length,0,'late visible callbacks cannot restart a closed store');
// Exercise real header refresh: the parent group's 999 must never overwrite
// a thread/forum/direct badge; the ordinary chat must still receive it.
const badge=[];
ctx.getChatStore=()=>({entryOf:()=>({title:'group',avatarPath:'',kind:'supergroup',background:null,unreadCount:999})});
run(`class HeaderProbe { ${method('pages/chat/HeaderIdentitySession.ets','HeaderIdentitySession','refresh')} } globalThis.HeaderProbe=HeaderProbe;`);
for(const ids of [[40,0,0],[0,12,0],[0,0,12],[0,0,0]]) {
 const h=new ctx.HeaderProbe(); Object.assign(h,{identityResolved:true,chatHeaderTitleNow:t=>t,
  host:{chatId:()=>-100,threadRootId:()=>ids[0],forumTopicId:()=>ids[1],directMessagesTopicId:()=>ids[2],
   onUnreadCount:n=>badge.push(n),onLiveEntry(){}}}); h.refresh();
}
assert.deepEqual(badge,[999]); assert.equal(timers.size,0);
console.log('scoped unread: PASS (scope isolation, live/partial/full reads, stale replies, burst coalescing, bounded retry, closure, real store/header wiring)');
