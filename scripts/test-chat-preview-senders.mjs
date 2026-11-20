import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
const ts=(await import(process.env.TYPESCRIPT_MODULE||'typescript')).default;
const root='entry/src/main/ets/';
const ctx=vm.createContext({str:k=>k,logW:()=>{},formatPreview:m=>m?.preview??'',previewThumbOf:()=>'',actionBarKindOf:()=>'',actionBarCanUnarchiveOf:()=>false});
function compile(s){return ts.transpileModule(s,{compilerOptions:{target:ts.ScriptTarget.ES2020}}).outputText;}
function load(file,names=[]){const s=fs.readFileSync(root+file,'utf8').replace(/^import\s[\s\S]*?;\r?\n/gm,'').replace(/\bexport /g,'');vm.runInContext(compile(s+names.map(n=>`\nglobalThis.${n}=${n};`).join('')),ctx);}
load('store/ChatEntry.ets',['cloneEntry']);load('store/chatEntryFactory.ets',['buildChatEntry']);load('store/chatMirror.ets',['ChatMirror']);load('store/ChatPreviewSenders.ets',['ChatPreviewSenders']);
const source=fs.readFileSync(root+'store/ChatStore.ets','utf8'),ast=ts.createSourceFile('store.ts',source,ts.ScriptTarget.Latest,true);
const cls=ast.statements.find(n=>ts.isClassDeclaration(n)&&n.name.text==='ChatStore');
const names=['normalizePeer','compareWorkerEntries','onChatActionUser'];
vm.runInContext(compile('class Store {'+cls.members.filter(n=>names.includes(n.name?.getText(ast))).map(n=>n.getText(ast)).join('\n')+'}globalThis.Store=Store;'),ctx);
const userNames=new Map(),ensured=new Set(),notifications=[];
const store=new ctx.Store();Object.assign(store,{selfId:99,mirror:new ctx.ChatMirror(),previewSenders:new ctx.ChatPreviewSenders(),unreadSeen:new Map(),dirtyAvatarChatIds:new Set(),chatActions:new Map(),notify:id=>notifications.push(id),users:{knows:id=>userNames.has(id),ensure:id=>ensured.add(id),displayName:id=>userNames.get(id)??'',isDeleted:()=>false}});
function entry(id,senderId,isUser=true,out=false,title='Group',kind='chatTypeBasicGroup',messageId=1){return ctx.buildChatEntry({chat:{id,title,type:{'@type':kind},last_message:messageId===0?null:{id:messageId,preview:'hello',is_outgoing:out,sender_id:{'@type':isUser?'messageSenderUser':'messageSenderChat',[isUser?'user_id':'chat_id']:senderId}}},selfId:99,previous:undefined,senderName:()=>''});}
const a=entry(-10,7),b=entry(-11,8);assert.equal(a.lastSenderId,7);assert.equal(a.lastSenderIsUser,true);assert.equal(ctx.cloneEntry(a).lastSenderId,7);
store.compareWorkerEntries([a,b]);assert.equal(ensured.has(7),true);notifications.length=0;
userNames.set(7,'Alice');store.onChatActionUser({user:{id:7}});assert.deepEqual(notifications,[-10]);assert.equal(store.mirror.get(-10).lastSenderName,'Alice');
const stable=store.mirror.get(-10);notifications.length=0;for(let i=0;i<1000;i++)store.compareWorkerEntries([a]);assert.equal(store.mirror.get(-10),stable);assert.equal(notifications.length,0,'worker empty labels cannot erase resolved names or churn revisions');
userNames.set(7,'Renamed');store.onChatActionUser({user:{id:7}});assert.equal(store.mirror.get(-10).lastSenderName,'Renamed');
store.compareWorkerEntries([entry(-10,8,true,false,'Group','chatTypeBasicGroup',2)]);notifications.length=0;
userNames.set(7,'Old sender');store.onChatActionUser({user:{id:7}});assert.equal(notifications.length,0,'replaced last sender is detached');
userNames.set(8,'Bob');store.onChatActionUser({user:{id:8}});assert.deepEqual(new Set(notifications),new Set([-10,-11]));
store.compareWorkerEntries([entry(-12,99,true,true)]);assert.equal(store.mirror.get(-12).lastSenderName,'sm_you');
// User and chat IDs must be separate namespaces, and a sender chat can arrive
// after its dependent group in the same worker batch.
store.compareWorkerEntries([entry(-13,-20,false),entry(-20,7,true,false,'Channel identity','chatTypeSupergroup')]);
assert.equal(store.mirror.get(-13).lastSenderName,'Channel identity');
store.compareWorkerEntries([entry(-20,7,true,false,'Renamed channel','chatTypeSupergroup')]);assert.equal(store.mirror.get(-13).lastSenderName,'Renamed channel');
store.compareWorkerEntries([entry(-11,0,true,false,'Group','chatTypeBasicGroup',0)]);assert.equal(store.mirror.get(-11).lastSenderName,'');notifications.length=0;
userNames.set(8,'Bob2');store.onChatActionUser({user:{id:8}});assert.deepEqual(notifications,[-10]);
// The existing UI prefix is reused: no new sender Text node or lookup in build.
const row=fs.readFileSync(root+'pages/chatlist/ChatRow.ets','utf8');const start=row.indexOf('  private lastSendState(): string {'),end=row.indexOf('  // 这一行到底',start);
vm.runInContext(compile('class Row {'+row.slice(start,end)+'}globalThis.Row=Row;'),ctx);
const r=new ctx.Row();r.row={snapshot:{chat:store.mirror.get(-10)}};assert.equal(r.senderLabel(),'Bob2');r.row.snapshot.chat={...r.row.snapshot.chat,lastMessageSendState:'sending'};assert.equal(r.senderLabel(),'sm_you');r.row.snapshot.chat={...r.row.snapshot.chat,isSavedMessages:true};assert.equal(r.senderLabel(),'');
console.log('PASS: worker sender IDs, actual store/mirror/name resolution, 1000 stable merges, targeted rename/late metadata, old dependency removal, user/chat namespaces, batch order, self/saved prefix and empty-history cleanup.');
