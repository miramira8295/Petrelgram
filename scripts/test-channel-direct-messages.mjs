import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
const ts=(await import(process.env.TYPESCRIPT_MODULE||'typescript')).default;
let current;
const routes=[],errors=[];
const ctx=vm.createContext({Number, getTdClient:()=>current,
 navigateToChat:async(p,o)=>routes.push(['chat',p,o]),
 navigateToDirectMessagesTopics:(p,o)=>routes.push(['topics',p,o]),
 showToast:s=>errors.push(s),str:s=>s,logW:()=>{},logE:()=>{}});
function load(file,names){
 const source=fs.readFileSync('entry/src/main/ets/'+file,'utf8')
 .replace(/^import\s[\s\S]*?;\r?\n/gm,'').replace(/\bexport /g,'').replace(/@(ObservedV2|Trace)\s*/g,'');
 vm.runInContext(ts.transpileModule(source+names.map(n=>`\nglobalThis.${n}=${n};`).join(''),
 {compilerOptions:{target:ts.ScriptTarget.ES2020}}).outputText,ctx);
}
load('pages/chat/ChannelDirectMessagesSession.ets',['ChannelDirectMessagesSession']);
function client(){
 const pending=[],listeners=new Set();
 return {pending,listeners,send:r=>new Promise((resolve,reject)=>pending.push({r,resolve,reject})),
 onUpdate:(t,fn)=>{assert.equal(t,'updateSupergroupFullInfo');listeners.add(fn);return()=>listeners.delete(fn);},
 emit:(id,info)=>{for(const fn of listeners)fn({supergroup_id:id,supergroup_full_info:info});}};
}
const flush=async()=>{for(let i=0;i<8;i++)await Promise.resolve();};
const group=(id,enabled=true)=>({id,is_channel:true,has_direct_messages_group:enabled});
const info=id=>({direct_messages_chat_id:id,linked_chat_id:-777});
current=client();const a=current,s=new ctx.ChannelDirectMessagesSession();
s.sync(a,-100,group(100));
assert.equal(a.pending[0].r['@type'],'getSupergroupFullInfo');
for(let i=0;i<1000;i++)s.sync(a,-100,group(100));
assert.equal(a.pending.length,1,'stable updates must not refetch');assert.equal(a.listeners.size,1);
a.emit(100,info(-200));assert.equal(s.targetChatId,-200);
a.pending.shift().resolve(info(-201));await flush();assert.equal(s.targetChatId,-200,'late read cannot undo update');
a.emit(999,info(-999));assert.equal(s.targetChatId,-200);
let opening=s.open();s.open();assert.equal(a.pending.length,1,'double click shares in-flight open');
a.emit(100,{...info(-200),description:'Updated description'}); // unrelated full-info must not swallow a tap
a.pending.shift().resolve({id:-200,title:'Inbox',type:{'@type':'chatTypeSupergroup',supergroup_id:200}});await flush();
a.pending.shift().resolve({is_direct_messages_group:true,is_administered_direct_messages_group:false});await opening;
assert.equal(routes[0][0],'chat');assert.equal(routes[0][1].chatId,-200);assert.equal(routes[0][2],'content');
opening=s.open();a.pending.shift().resolve({id:-200,type:{'@type':'chatTypeSupergroup',supergroup_id:200}});await flush();
a.pending.shift().resolve({is_direct_messages_group:true,is_administered_direct_messages_group:true});await opening;
assert.equal(routes[1][0],'topics');
opening=s.open();const late=a.pending.shift();a.emit(100,info(0));late.resolve({id:-200});await opening;
assert.equal(routes.length,2,'disabled destination cannot navigate');assert.equal(s.targetChatId,0);
a.emit(100,{linked_chat_id:-777});assert.equal(s.targetChatId,0,'discussion is not private messages');
a.emit(100,info(-100));assert.equal(s.targetChatId,0,'no self loop');
a.emit(100,info(-200));s.sync(a,-100,group(100,false));assert.equal(s.targetChatId,0);assert.equal(a.listeners.size,0);
s.sync(a,-100,group(100));const old=a.pending.shift();s.sync(a,-300,group(300));
old.resolve(info(-200));a.pending.shift().resolve(info(-400));await flush();assert.equal(s.targetChatId,-400);
s.sync(a,-500,{id:500,is_channel:false,has_direct_messages_group:true});assert.equal(s.targetChatId,0);
s.sync(a,-100,group(100));const disposed=a.pending.shift();s.dispose();disposed.resolve(info(-200));await flush();assert.equal(s.targetChatId,0);
s.sync(a,-100,group(100));const account=a.pending.shift();current=client();account.resolve(info(-200));await flush();assert.equal(s.targetChatId,0);
s.sync(current,-100,group(100));current.pending.shift().reject(new Error('offline'));await flush();assert.equal(s.targetChatId,0);
current.emit(100,info(-200));opening=s.open();current.pending.shift().resolve({id:-200,type:{'@type':'chatTypePrivate'}});await opening;
assert.equal(routes.length,2);assert.equal(errors.length,1);s.dispose();
// Exercise the actual membership controller: channel metadata corrects a stale
// group classification without granting posting rights; only subscriber DMs skip join.
load('util/chatPermissions.ets',['allPermissions']);
load('util/sendPermissions.ets',['effectiveSendPermissions','anySendPermission']);
load('util/membershipState.ets',['membershipStateOf']);
load('pages/chat/MembershipSession.ets',['MembershipSession']);
let channel=false,state='',targetGroups=0;
const membership=new ctx.MembershipSession();
const host={chatId:()=>-100,isChannel:()=>channel,client:()=>current,
 setIsChannel:v=>channel=v,setIsGroup:()=>{},commitTimelineSnapshot:()=>{},
 setMembershipState:v=>state=v,setJoiningChat:()=>{},closeComposerSurfaces:()=>{},
 onSupergroup:()=>targetGroups++};
membership.bind(host);
// Prime context before applySupergroup, like getChat does in refresh().
membership.refresh();current.pending.shift().resolve({type:{'@type':'chatTypeSupergroup',supergroup_id:100,is_channel:false}});await flush();
current.pending.shift().resolve({...group(100),status:{'@type':'chatMemberStatusMember'}});await flush();
assert.equal(channel,true);assert.equal(state,'readonly');assert.equal(targetGroups,1);
membership.applySupergroup({id:100,is_channel:false,is_direct_messages_group:true,
 is_administered_direct_messages_group:false,join_to_send_messages:false,status:{'@type':'chatMemberStatusLeft'}});
assert.equal(state,'writable');
membership.applySupergroup({id:100,is_channel:false,join_to_send_messages:false,status:{'@type':'chatMemberStatusLeft'}});
assert.equal(state,'joinable','ordinary groups retain join semantics');
membership.applySupergroup({id:100,is_channel:false,is_direct_messages_group:true,
 join_to_send_messages:false,status:{'@type':'chatMemberStatusBanned'}});assert.equal(state,'blocked');
membership.dispose();
console.log('channel direct messages: PASS (routing, permissions, live updates, stale reads, O(1) refresh)');
