// Real compiled store methods: query complexity and reply resolution semantics.
import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
const ts=(await import(process.env.TYPESCRIPT_MODULE||'typescript')).default;
const path='entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/store/MessageStore.ts';
const source=fs.readFileSync(path,'utf8'),ast=ts.createSourceFile(path,source,ts.ScriptTarget.Latest,true);
const cls=ast.statements.find(n=>ts.isClassDeclaration(n)&&n.name.text==='MessageStore');
const names=['indexOf','resolveReplies','upsert','upsertBatch','fetchRepliedMessage'];
const methods=names.map(name=>cls.members.find(n=>n.name?.getText(ast)===name).getText(ast));
const ctx=vm.createContext({DrawnStage:{ReplyResolve:0},drawnStageMetrics:{begin:()=>false,end(){}},
 cloneMessage:m=>({...m}),replySnippetOf:m=>m.text,replyThumbOf:m=>m.photoPath,
 replyThumbIsSticker:()=>false,replyDiceLayers:()=>[]});
vm.runInContext(ts.transpileModule(`class Store {${methods.join('\n')}} globalThis.Store=Store;`,
 {compilerOptions:{target:ts.ScriptTarget.ES2020}}).outputText,ctx);
const store=new ctx.Store();
let reads=0;
for(const n of [0,1,2,3,17,400,4096]) {
 const ids=Array.from({length:n},(_,i)=>i*1048576+2);
 store.messages=ids.map(id=>({get id(){reads++;return id;}}));
 for(const id of [-1,0,1,...ids.filter((_,i)=>i%Math.max(1,Math.floor(n/30))===0),...ids.slice(-2).map(x=>x+1),Number.MAX_SAFE_INTEGER]) {
  reads=0;assert.equal(store.indexOf(id),ids.indexOf(id));
  assert.ok(reads<=Math.ceil(Math.log2(n+1))+1,`query must be logarithmic: n=${n}, reads=${reads}`);
 }
}
// Exact first-match behavior on duplicates and 53-bit IDs; no bitwise coercion.
store.messages=[-3,-3,0,2**40,Number.MAX_SAFE_INTEGER].map(id=>({id}));
assert.equal(store.indexOf(-3),0);assert.equal(store.indexOf(2**40),3);assert.equal(store.indexOf(Number.MAX_SAFE_INTEGER),4);
// The real insertion paths preserve the invariant used by binary search.
Object.assign(store,{messages:[],hydrateFromFileCache:e=>e,rememberMessageUsers(){},noteCustomEmoji(){}});
store.upsert({id:30});store.upsert({id:10});store.upsert({id:20});store.upsert({id:20,text:'replace'});
store.upsertBatch([{id:5},{id:40},{id:10,text:'batch'}]);
assert.deepEqual(Array.from(store.messages,m=>m.id),[5,10,20,30,40]);
assert.equal(store.messages[store.indexOf(10)].text,'batch');
const requested=[];
Object.assign(store,{messages:[{id:1,replyToMessageId:0,replyText:'',text:'local',senderName:'sender',photoPath:'/local'},
 {id:2,replyToMessageId:1,replyText:''},{id:3,replyToMessageId:99,replyText:''},
 {id:4,replyToMessageId:99,replyText:''},{id:5,replyToMessageId:88,replyText:''}],
 repliedPreview:new Map([[88,{senderName:'cached',text:'cached text',thumbPath:'/cached',thumbSticker:false,diceLayers:[]}]]),
 fetchRepliedMessage:id=>requested.push(id)});
store.resolveReplies();assert.equal(store.messages[1].replyText,'local');assert.equal(store.messages[1].replyThumbPath,'/local');
assert.equal(store.messages[4].replyText,'cached text');assert.deepEqual(requested,[99]);
// A window containing only unresolved unique replies must not scan the window per reply.
reads=0;store.messages=Array.from({length:400},(_,i)=>({get id(){reads++;return i+1;},replyToMessageId:10000+i,replyText:''}));
requested.length=0;store.resolveReplies();assert.equal(requested.length,400);assert.ok(reads<=400*10);
console.log('PASS: compiled logarithmic ID lookup, 53-bit/first-match/missing IDs, sorted real upserts, local/cached/deduplicated replies and bounded unresolved lookup work.');

const fetcher=new ctx.Store();let fetchCalls=0;
Object.assign(fetcher,{repliedFetched:new Set(),chatId:1,client:{send(){fetchCalls++;return new Promise(()=>{});}}});
for(let i=0;i<1000;i++)fetcher.fetchRepliedMessage(99);
assert.equal(fetchCalls,1);fetcher.fetchRepliedMessage(100);assert.equal(fetchCalls,2);
console.log('PASS: fetched-reply Set preserves one request per ID across 1000 repeated checks.');
