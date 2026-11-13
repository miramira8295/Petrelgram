// Production selection, cache, prefetch and job orchestration. IO/native font
// objects are deterministic doubles; real paragraph handoff is also covered by
// test-drawn-text-row. No claim about on-device latency or cache hit rate.
import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
const ts=(await import(process.env.TYPESCRIPT_MODULE||'typescript')).default;
const root='entry/src/main/ets/';
function load(ctx,file,names){
 const s=fs.readFileSync(root+file,'utf8').replace(/^import\s[\s\S]*?;\r?\n/gm,'').replace(/\bexport /g,'');
 vm.runInContext('(function(){'+ts.transpileModule(s+names.map(n=>`\nglobalThis.${n}=${n};`).join(''),{compilerOptions:{target:ts.ScriptTarget.ES2020}}).outputText+'})()',ctx);
}
const msg=(id,text='hello',type='messageText')=>({id,chat_id:7,reply_markup:null,content:{'@type':type,text:{text,entities:[]},caption:{text,entities:[]}}});
function env(){
 let now=1000,nextTimer=0;const timers=new Map(),sent=[],parsed=[],decoded=[],prepared=[],warnings=[];
 let response=Array.from({length:20},(_,i)=>msg(100-i)),recent=[7],live=true;
 const chat={id:7,kind:'channel',unreadCount:0,lastReadInboxId:0};
 const listeners=new Map();
 const client={onUpdate:(type,fn)=>{const list=listeners.get(type)||new Set();list.add(fn);listeners.set(type,list);return()=>list.delete(fn);},send:async req=>{sent.push(req);return req['@type']==='getRecentlyOpenedChats'?{chat_ids:recent}:{messages:response};}};
 let active=client;
 const ctx=vm.createContext({Date:{now:()=>now},setTimeout:fn=>{const id=++nextTimer;timers.set(id,fn);return id;},clearTimeout:id=>timers.delete(id),
  getTdClient:()=>active,getChatStore:()=>({entryOf:()=>chat,isForum:()=>false,isAdministeredDirectMessagesGroup:()=>false}),
  recentChatHistory:()=>({filter:ids=>ids}),getUserStore:()=>({}),logW:s=>warnings.push(s),
  chatEnv:{drawnEnabled:true,drawnText:true,drawnSingle:true,drawnAlbum:true,drawnPlain:true,drawnRich:true,bubbleMaterialOn:false,msgTextSize:16,bubbleRadius:18,appearanceEpoch:1,langEpoch:1},
  chatContentWidth:()=>400,a11yRuntimeState:{active:false},textMeasureEnvironment:{epoch:1},drawnTextUsesRtlLayout:()=>false,
  canRenderLightweightPlainTextRow:()=>true,drawnTextRowEligible:()=>true,drawnSingleMediaEligible:()=>true,drawnAlbumEligible:()=>true,
  buildMessageEntry:(raw,_users,publish)=>{parsed.push({raw,publish});return{id:raw.id,contentType:raw.content['@type']==='messageText'?'text':'photo',senderTag:'',text:raw.content.text.text};},
  collapseAlbums:entries=>entries.map(head=>({head,memberIds:[head.id],photoRatios:[1],caption:''})),
  cachedPixelMap:()=>undefined,loadPixelMap:async req=>{decoded.push(req);return {};}});
 class Engine {prepare(ui,g,data,style){prepared.push({ui,g,data,style,engine:this});return{density:2,nativeTiles:Array.from({length:10},(_,i)=>({width:100,height:100,opaque:false,cell:{thumbPath:`/local/${i}`}}))};}}
 Object.assign(ctx,{DrawnTextLayouts:Engine,DrawnAlbumLayouts:Engine,DrawnSingleMediaLayouts:Engine});
 load(ctx,'util/drawnHomeMessagePlan.ets',['drawnHomeMessages']);
 load(ctx,'util/chatPrefetch.ets',['prefetchInitialPage','takePrefetchedPage','expirePrefetchedPage','initialPageRoute','PREFETCH_TTL_MS','hasPrefetchedPage']);
 load(ctx,'pages/chat/DrawnLayoutWarmCache.ets',['DrawnLayoutWarmCache','drawnLayoutWarmCache','takeDrawnWarmLayout']);
 load(ctx,'pages/main/DrawnHomeMessages.ets',['DrawnHomeMessages']);
 return {ctx,client,chat,timers,sent,parsed,decoded,prepared,warnings,listeners,emit:(type,event)=>{for(const fn of [...(listeners.get(type)||[])])fn(event);},gate:()=>live,
  setRecent:ids=>recent=ids,setPage:p=>response=p,stop:()=>live=false,account:()=>active={send:client.send,onUpdate:client.onUpdate},advance:ms=>now+=ms};
}
const flush=async()=>{await Promise.resolve();await Promise.resolve();};
{
 const r=env(),p=r.ctx.drawnHomeMessages;
 assert.deepEqual([...p(Array.from({length:100},(_,i)=>msg(100-i)),0)].map(x=>x.id),Array.from({length:12},(_,i)=>89+i));
 const around=p(Array.from({length:30},(_,i)=>msg(100-i)),85);assert.equal(around.length,12);assert.ok(around.some(x=>x.id===85));
 assert.equal(p([msg(1,'a'.repeat(2049))],0).length,0);
 const big=msg(1);big.content.text.entities=Array(65).fill({});assert.equal(p([big],0).length,0);
 assert.equal(p([msg(1,'x','messagePoll')],0).length,0);
 assert.equal(p([msg(1,'a'.repeat(2048)),msg(2,'a'.repeat(2048)),msg(3,'a'.repeat(2048)),msg(4,'a'.repeat(2048)),msg(5,'a'.repeat(2048))],0).length,4);
 const button=msg(2);button.reply_markup={};assert.equal(p([button,msg(1)],0).length,1,'null markup is allowed, real keyboard skipped');
}
{
 const r=env(),job=new r.ctx.DrawnHomeMessages(r.gate);await job.begin();
 assert.deepEqual(r.sent.map(x=>x['@type']),['getRecentlyOpenedChats','getChatHistory']);
 assert.equal(r.sent[1].only_local,true);assert.equal(r.sent[0].limit,1);
 const originalPromise=r.ctx.prefetchInitialPage(7,0,0);
 assert.equal(r.sent.length,2,'opening reuses same local request without resending');
 const page=await r.ctx.takePrefetchedPage(7,r.ctx.initialPageRoute(0,0));
 assert.equal(page,await originalPromise,'same raw entities can seed both prewarm and actual store');
 for(let n=0;n<40&&job.pending();n++){const before=r.parsed.length;job.step({vp2px:n=>n*2});assert.ok(r.parsed.length-before<=1);await flush();}
 assert.equal(r.parsed.length,12);assert.ok(r.parsed.every(x=>x.publish===false));
 assert.equal(r.prepared.length,2);assert.equal(r.decoded.length,8);
 assert.ok(r.prepared.every(x=>x.data.isGroup&&x.data.isChannel),'channels use the same group/avatar width as MessageStore');
 assert.ok(r.decoded.every(x=>x.width===200&&x.height===200&&!x.opaque));
 assert.equal(new Set(r.decoded.map(x=>x.path)).size,8,'shared tile paths deduplicated across candidate rows');
 const first=r.prepared[0],take=r.ctx.takeDrawnWarmLayout(7,first.g.head.id,'text');
 assert.equal(take,first.engine);assert.equal(r.ctx.takeDrawnWarmLayout(7,first.g.head.id,'text'),undefined,'exclusive transfer');
 r.account();assert.equal(r.ctx.takeDrawnWarmLayout(7,r.prepared[1].g.head.id,'text'),undefined,'account change invalidates reserve');
 assert.equal(r.warnings.length,0);
}
{
 const r=env(),cache=r.ctx.drawnLayoutWarmCache;
 for(let n=0;n<100;n++)cache.put(r.client,7,n,'text',{});
 assert.equal(cache.entries.size,2);r.advance(10000);assert.equal(cache.take(r.client,7,0,'text'),undefined);
 assert.equal(cache.entries.size,0);assert.equal(r.timers.size,0);
}
for(const stopAt of [0,1,12,14,16]){
 const r=env(),job=new r.ctx.DrawnHomeMessages(r.gate);await job.begin();
 for(let i=0;i<stopAt;i++){job.step({vp2px:n=>n*2});await flush();}
 job.cancel();const snapshot=[r.parsed.length,r.prepared.length,r.decoded.length];
 for(let i=0;i<30;i++)job.step({vp2px:n=>n*2});await flush();
 assert.deepEqual([r.parsed.length,r.prepared.length,r.decoded.length],snapshot);
 assert.equal(job.raw.length,0);assert.equal(job.requests.length,0);assert.equal(job.valid,undefined);
}
{
 const r=env();let reply;
 r.client.send=()=>new Promise(resolve=>reply=resolve);
 const job=new r.ctx.DrawnHomeMessages(r.gate),work=job.begin();job.cancel();reply({chat_ids:[7]});await work;
 assert.equal(r.parsed.length,0);assert.equal(job.chat,undefined,'late callback cannot resurrect cancelled job');
}
{
 const r=env(),job=new r.ctx.DrawnHomeMessages(r.gate);await job.begin();r.account();job.step({vp2px:n=>n*2});
 assert.equal(r.parsed.length,0);assert.equal(job.pending(),false);
}
{
 const r=env(),old=r.ctx.prefetchInitialPage(7,0,0);r.account();const next=r.ctx.prefetchInitialPage(7,0,0);
 assert.notEqual(next,old);r.ctx.expirePrefetchedPage(7,old);assert.ok(r.ctx.hasPrefetchedPage(7));
 assert.equal(r.ctx.takePrefetchedPage(7,r.ctx.initialPageRoute(1,50)),null,'changed anchor rejects old page');
}
console.log('PASS: bounded recent-chat local prefetch, shared raw page, one-step parsing, two-engine transfer, eight image keys, cancellation/account/TTL/anchor isolation');

for(const kind of ['updateMessageContent','updateMessageEdited','updateDeleteMessages','updateMessageInteractionInfo','updateChatReadInbox','updateChatLastMessage','updateNewMessage','updateMessageSendSucceeded','updateFile']){
 const r=env(),pending=r.ctx.prefetchInitialPage(7,0,0,true);await pending;
 const event=kind==='updateNewMessage'||kind==='updateMessageSendSucceeded'?{message:{chat_id:7}}:{chat_id:7};
 if(kind!=='updateFile'){r.emit(kind,{chat_id:8});assert.ok(r.ctx.hasPrefetchedPage(7));}
 r.emit(kind,event);assert.equal(r.ctx.hasPrefetchedPage(7),false,kind);
 assert.equal([...r.listeners.values()].reduce((n,s)=>n+s.size,0),0,kind+' removes all guards');
 assert.equal(r.timers.size,0,kind);
}
console.log('PASS: speculative page invalidates on edits/deletion/new arrivals/read-watermark/file completion; all guards cleaned up.');
