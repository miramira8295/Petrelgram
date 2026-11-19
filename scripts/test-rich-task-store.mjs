import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
const imported = await import(process.env.TYPESCRIPT_MODULE || 'typescript'), ts = imported.default || imported;
class TdError extends Error { constructor(code, message) { super(message); this.code = code; } }
let accountClient;
const context = vm.createContext({ TdError, str: key => key, getTdClient: () => accountClient });
function compile(source) { return ts.transpileModule(source, { compilerOptions: { target: ts.ScriptTarget.ES2020 } }).outputText; }
function load(path, names) {
 const source = fs.readFileSync(path, 'utf8').replace(/^import\s[\s\S]*?;\r?\n/gm, '').replace(/\bexport /g, '');
 vm.runInContext(compile(source + names.map(name => `\nglobalThis.${name}=${name};`).join('')), context);
}
load('entry/src/main/ets/util/richMessageTaskEdit.ets', ['createRichTaskEditContent', 'updateRichTaskChecked']);
load('entry/src/main/ets/util/richMessageFullLoader.ets', ['RichMessageFullLoader']);
const storeSource = fs.readFileSync('entry/src/main/ets/store/MessageStore.ets', 'utf8');
// Extract the actual production methods, not a reimplementation of their guards.
const start = storeSource.indexOf('  private contentRequest('), end = storeSource.indexOf('  toggleChecklistTask(', start);
assert.ok(start > 0 && end > start);
const closeStart = storeSource.indexOf('  close(): void {'), closeEnd = storeSource.indexOf('    this.viewedMentions.clear();', closeStart);
assert.ok(closeStart > 0 && closeEnd > closeStart);
const closeOwnedResources = storeSource.slice(closeStart, closeEnd) + '\n  }';
vm.runInContext(compile(`class StoreHarness {
 client: Object; chatId: number; messages: Object[]; checklistClosed=false; checklistOps=null;
 fullRichLoader=null; richTaskRequests=new Map(); applied=[]; notices=0;
 constructor(client,chatId,messages){this.client=client;this.chatId=chatId;this.messages=messages;}
 indexOf(id){return this.messages.findIndex(m=>m.id===id);}
 patch(id,fn){const i=this.indexOf(id);if(i>=0)fn(this.messages[i]);}
 notifySoon(){this.notices++;}
 onContent(update){this.applied.push(update);const m=this.messages[this.indexOf(update.message_id)];if(!m)return;
 const full=update.new_content.message;m.richBlocks=full.blocks;m.richIsFull=full.is_full;m.richIsRtl=full.is_rtl;}
 ${closeOwnedResources}
 ${storeSource.slice(start, end)}
}\nglobalThis.StoreHarness=StoreHarness;`), context);
const deferred = () => { let resolve, reject; const promise = new Promise((a,b)=>{resolve=a;reject=b;}); return {promise,resolve,reject}; };
const flush = () => new Promise(resolve=>setImmediate(resolve));
function client() { const calls=[]; return {calls,send(request){const d=deferred();calls.push({request,...d});return d.promise;}}; }
const text = value => ({'@type':'richTextPlain',text:value});
const paragraph = value => ({'@type':'pageBlockParagraph',text:text(value)});
const blocks = () => [paragraph('before'),{'@type':'pageBlockList',items:[{'@type':'pageBlockListItem',has_checkbox:true,is_checked:false,blocks:[paragraph('zero')]}]},
 {'@type':'pageBlockTable',caption:text('table'),cells:[[{text:text('cell'),colspan:1,rowspan:1}]],is_bordered:true},
 {'@type':'pageBlockPhoto',photo:{sizes:[{width:20,height:10,photo:{id:321}}]},caption:{text:text('caption'),credit:text('credit')}}];
function message(extra={}) {return {id:10,isOutgoing:true,contentType:'richMessage',richIsFull:true,richIsRtl:true,richBlocks:blocks(),...extra};}
function setup(extra={}) {const td=client();accountClient=td;const m=message(extra);return {td,m,store:new context.StoreHarness(td,-100,[m])};}
const success = source => ({content:{'@type':'messageRichMessage',message:{is_full:true,is_rtl:true,blocks:source}}});
// Basic permissions and partial content never issue an edit or optimistic write.
for (const extra of [{isOutgoing:false},{richIsFull:false},{contentType:'text'},{richBlocks:undefined}]) {
 const {td,store}=setup(extra);await assert.rejects(store.toggleRichTask(10,0,true),e=>e.code===403);assert.equal(td.calls.length,0);
}
let state=setup(), original=state.m.richBlocks;
let work=state.store.toggleRichTask(10,0,true);await flush();assert.equal(state.td.calls.length,1);assert.equal(state.td.calls[0].request['@type'],'getMessageProperties');
state.td.calls[0].resolve({can_be_edited:false});await assert.rejects(work,e=>e.code===403);assert.equal(state.m.richBlocks,original);assert.equal(state.store.richTaskRequests.size,0);
// Task zero is valid; all unrelated content survives the real InputMessageRichMessage conversion.
state=setup();original=state.m.richBlocks;work=state.store.toggleRichTask(10,0,true);
assert.equal(state.store.toggleRichTask(10,0,false),work,'one request in flight per message');await flush();state.td.calls[0].resolve({can_be_edited:true});await flush();
assert.equal(state.td.calls.length,2);const edit=state.td.calls[1].request;assert.equal(edit['@type'],'editMessageText');assert.equal(edit.chat_id,-100);assert.equal(edit.message_id,10);
const input=edit.input_message_content;assert.equal(input['@type'],'inputMessageRichMessage');assert.equal(input.message.source['@type'],'richMessageSourceBlocks');assert.equal(input.message.is_rtl,true);
assert.equal(input.message.detect_automatic_blocks,false);const outgoing=input.message.source.blocks;assert.equal(outgoing.length,4);assert.equal(outgoing[0].text.text,'before');assert.equal(outgoing[1].items[0].is_checked,true);
assert.equal(outgoing[2].cells[0][0].text.text,'cell');assert.equal(outgoing[3].photo.photo.id,321);assert.equal(outgoing[3].caption.credit.text,'credit');assert.notEqual(state.m.richBlocks,original);assert.equal(original[1].items[0].is_checked,false);
const server=blocks();server[1].items[0].is_checked=true;state.td.calls[1].resolve(success(server));await work;assert.equal(state.m.richBlocks,server);assert.equal(state.store.richTaskRequests.size,0);
// Content changed while permissions were loading: no edit based on stale source.
state=setup();work=state.store.toggleRichTask(10,0,true);await flush();const external=blocks();state.m.richBlocks=external;state.td.calls[0].resolve({can_be_edited:true});await assert.rejects(work,e=>e.code===409);assert.equal(state.td.calls.length,1);assert.equal(state.m.richBlocks,external);
// Unknown task/readonly block fails atomically after permission verification.
for(const readonly of [false,true]) {
 state=setup();if(readonly)state.m.richBlocks.push({'@type':'pageBlockEmbedded',html:'unsupported'});original=state.m.richBlocks;work=state.store.toggleRichTask(10,readonly?0:999,true);await flush();state.td.calls[0].resolve({can_be_edited:true});await assert.rejects(work,e=>e.code===400);assert.equal(state.td.calls.length,1);assert.equal(state.m.richBlocks,original);
}
// Roll back only our exact optimistic identity. An external update wins both errors and successful old replies.
for(const externalUpdate of [false,true]) for(const fail of [false,true]) {
 state=setup();original=state.m.richBlocks;work=state.store.toggleRichTask(10,0,true);await flush();state.td.calls[0].resolve({can_be_edited:true});await flush();const optimistic=state.m.richBlocks,next=blocks();
 if(externalUpdate)state.m.richBlocks=next;
 if(fail){state.td.calls[1].reject(new Error('edit failed'));await assert.rejects(work,/edit failed/);}else{state.td.calls[1].resolve(success(server));await work;}
 assert.equal(state.m.richBlocks,externalUpdate?next:fail?original:server);assert.notEqual(optimistic,original);
}
// Close/reopen A -> B -> A uses a new request token; late A results cannot mutate it.
state=setup();work=state.store.toggleRichTask(10,0,true);await flush();const oldCall=state.td.calls[0];state.store.close();state.store.checklistClosed=false;
const newer=state.store.toggleRichTask(10,0,true);await flush();oldCall.resolve({can_be_edited:true});await work;assert.equal(state.td.calls.length,2);assert.equal(state.store.richTaskRequests.size,1);
state.td.calls[1].resolve({can_be_edited:true});await flush();state.td.calls[2].resolve(success(server));await newer;assert.equal(state.m.richBlocks,server);
// Account swap while permission or edit awaits suppresses all old-session writes.
for(const phase of ['permission','edit']) {
 state=setup();original=state.m.richBlocks;work=state.store.toggleRichTask(10,0,true);await flush();
 if(phase==='edit'){state.td.calls[0].resolve({can_be_edited:true});await flush();}
 const held=state.m.richBlocks;accountClient=client();state.td.calls.at(-1).resolve(phase==='edit'?success(server):{can_be_edited:true});await work;assert.equal(state.m.richBlocks,held);assert.equal(state.store.applied.length,0);
}
// Full-content fetching gates rendering updates and deduplicates requests.
state=setup({richIsFull:false});original=state.m.richBlocks;work=state.store.loadFullRichMessage(10);const duplicate=state.store.loadFullRichMessage(10);assert.equal(state.td.calls.length,1);assert.equal(state.td.calls[0].request['@type'],'getFullRichMessage');
state.td.calls[0].resolve({is_full:true,is_rtl:true,blocks:server});await Promise.all([work,duplicate]);assert.equal(state.m.richBlocks,server);assert.equal(state.m.richIsFull,true);
await state.store.loadFullRichMessage(10);assert.equal(state.td.calls.length,1);
for(const mode of ['partial','changed','closed','account','reopen']) {
 state=setup({richIsFull:false});original=state.m.richBlocks;work=state.store.loadFullRichMessage(10);const request=state.td.calls[0];
 if(mode==='changed')state.m.richBlocks=blocks();if(mode==='closed'||mode==='reopen')state.store.close();if(mode==='reopen')state.store.checklistClosed=false;if(mode==='account')accountClient=client();
 const held=state.m.richBlocks;request.resolve({is_full:mode!=='partial',blocks:server});if(mode==='closed'||mode==='reopen')await assert.rejects(work,/CLOSED/);else await work;
 assert.equal(state.m.richBlocks,held);assert.equal(state.store.applied.length,0);
}
// Real FIFO loader: four native requests maximum, dedup without scanning,
// failure immediately frees a slot, close rejects queued and later active results.
let td=client(),loader=new context.RichMessageFullLoader(td,-200),loads=[];
for(let id=0;id<10;id++)loads.push(loader.load(id));for(const load of loads)load.catch(()=>{});
assert.equal(td.calls.length,4);assert.equal(loader.load(2),loads[2]);assert.deepEqual(td.calls.map(c=>c.request.message_id),[0,1,2,3]);
td.calls[1].reject(new Error('native failed'));await assert.rejects(loads[1],/native failed/);await flush();assert.equal(td.calls.length,5);assert.equal(td.calls[4].request.message_id,4);
td.calls[0].resolve({id:0});await loads[0];await flush();assert.equal(td.calls[5].request.message_id,5);
loader.close();for(let id=6;id<10;id++)await assert.rejects(loads[id],/CLOSED/);assert.equal(td.calls.length,6);await assert.rejects(loader.load(10),/CLOSED/);
for(const i of [2,3,4,5])td.calls[i].resolve({id:td.calls[i].request.message_id});for(const id of [2,3,4,5])await assert.rejects(loads[id],/CLOSED/);await flush();assert.equal(loader.jobs.size,0);assert.equal(loader.active,0);
// A failed ID is retryable; loader does not cache a rejected/full response forever.
td=client();loader=new context.RichMessageFullLoader(td,1);work=loader.load(7);td.calls[0].reject(Error('retry'));await assert.rejects(work,/retry/);await flush();const retry=loader.load(7);assert.notEqual(retry,work);td.calls[1].resolve({is_full:true});await retry;await flush();loader.close();
console.log('PASS: actual rich task Store methods permissions/full gating/task 0/atomic content/optimistic identity rollback/external updates/session guards/single-flight; full-loader four-way FIFO/dedup/retry/close.');
