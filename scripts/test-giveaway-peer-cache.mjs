import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
const imported=await import(process.env.TYPESCRIPT_MODULE||'typescript'),ts=imported.default||imported;
const requests=[],hooks=new Map();
function client(){return {send:req=>new Promise((resolve,reject)=>requests.push({req,resolve,reject})),onUpdate(type,cb){let set=hooks.get(type);if(!set)hooks.set(type,set=new Set());set.add(cb);return()=>set.delete(cb);}};}
let owner=client();
const ctx=vm.createContext({getTdClient:()=>owner,documentFileId:f=>f?.id??0,documentFilePath:f=>f?.local?.path??'',logW(){}});
const source=fs.readFileSync('entry/src/main/ets/services/GiveawayPeerCache.ets','utf8').replace(/^import\s[\s\S]*?;\r?\n/gm,'').replace(/\bexport /g,'');
vm.runInContext(ts.transpileModule(source+'\nglobalThis.api={watchGiveawayPeer,resetGiveawayPeers,stats:()=>({recent:recent.size,records:records.size,active})};',{compilerOptions:{target:ts.ScriptTarget.ES2020}}).outputText,ctx);
const {watchGiveawayPeer:watch,resetGiveawayPeers:reset,stats}=ctx.api;
const turn=()=>new Promise(resolve=>setImmediate(resolve));
const emit=(type,value)=>{for(const cb of hooks.get(type)??[])cb(value);};
const user=(id,name='User',fileId=id)=>({id,first_name:name,last_name:'Last',profile_photo:{small:{id:fileId}}});
const seen=[],offs=[];
for(let i=0;i<1000;i++)offs.push(watch(1,true,v=>seen.push(v)));
assert.equal(requests.length,1,'one request per shared peer');requests[0].resolve(user(1));await turn();assert.equal(seen.filter(Boolean).length,1000);
for(const off of offs)off();assert.equal(stats().records,0);assert.equal(stats().recent,1);
const before=requests.length,again=[];const un=watch(1,true,v=>again.push(v));assert.equal(requests.length,before);assert.equal(again[0].name,'User Last');
emit('updateUser',{user:user(1)});assert.equal(again.length,1,'equivalent metadata does not notify');
emit('updateUser',{user:user(1,'Changed')});assert.equal(again.at(-1).name,'Changed Last');un();
reset();requests.length=0;
const cancels=[];for(let id=1;id<=30;id++)cancels.push(watch(id,true,()=>{}));
assert.equal(requests.length,4);assert.equal(stats().active,4);
for(let id=6;id<=30;id+=2)cancels[id-1]();
let cursor=0;while(cursor<requests.length){const request=requests[cursor++];request.resolve(user(request.req.user_id));await turn();assert.ok(stats().active<=4);}
assert.equal(requests.length,17,'cancelled queued peers never start');for(const off of cancels)off();assert.equal(stats().records,0);
reset();requests.length=0;const channel=[];const offChat=watch(-10,false,v=>channel.push(v));
emit('updateChatTitle',{chat_id:-10,title:'New title'});
requests[0].resolve({id:-10,title:'Old title',photo:{small:{id:10}}});await turn();
assert.equal(channel.at(-1).name,'New title','late request must retain newer title');assert.equal(channel.at(-1).photo.id,10,'title-only update cannot discard the reply photo');
emit('updateChatPhoto',{chat_id:-10,photo:{small:{id:11}}});assert.equal(channel.at(-1).photo.id,11);offChat();
reset();requests.length=0;const a=owner,stale=[];watch(20,true,v=>stale.push(v));const reqA=requests.at(-1);owner=client();watch(20,true,()=>{});const reqB=requests.at(-1);owner=a;const fresh=[];const offFresh=watch(20,true,v=>fresh.push(v));const reqFresh=requests.at(-1);
reqFresh.resolve(user(20,'Current'));await turn();reqA.resolve(user(20,'Stale A'));reqB.resolve(user(20,'Stale B'));await turn();assert.equal(fresh.at(-1).name,'Current Last');assert.equal(stale.filter(Boolean).length,0);offFresh();
reset();requests.length=0;
for(let id=1;id<=600;id++){const off=watch(id,true,()=>{});requests.at(-1).resolve(user(id));await turn();off();}
assert.equal(stats().recent,512);assert.equal(stats().records,0);assert.equal(stats().active,0);
reset();requests.length=0;const offFailure=watch(99,true,()=>{});requests.at(-1).reject(new Error('offline'));await turn();offFailure();const offRetry=watch(99,true,()=>{});assert.equal(requests.length,2,'failed requests can retry on next activation');requests.at(-1).resolve(user(99));await turn();offRetry();
console.log('PASS: 1000 shared peer listeners/single-flight, four-request queue, O(1) queued cancellation, 512 recent bound, metadata dedup, late field merge, account A/B/A isolation and failed activation retry.');
