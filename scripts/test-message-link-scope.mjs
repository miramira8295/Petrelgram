// Replay production link resolution/navigation with controlled TDLib responses.
// No device cache or network timing is required to exercise cold-page routing.
import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
const ts=(await import(process.env.TYPESCRIPT_MODULE||'typescript')).default;
const base='entry/src/main/ets/';
const compiled='entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/';
const ctx=vm.createContext({Number,Map,Set,Promise});
function run(code){vm.runInContext(ts.transpileModule(code,{compilerOptions:{target:ts.ScriptTarget.ES2020}}).outputText,ctx);}
function load(path,names){let code=fs.readFileSync(path,'utf8').replace(/^import\s[\s\S]*?;\r?\n/gm,'').replace(/@ObservedV2\s*/g,'').replace(/@Trace\s*/g,'').replace(/\bexport /g,'');run(code+names.map(n=>`\nglobalThis.${n}=${n};`).join(''));}
function methods(path,cls,names){const ast=ts.createSourceFile(path,fs.readFileSync(path,'utf8'),ts.ScriptTarget.Latest,true);const c=ast.statements.find(n=>ts.isClassDeclaration(n)&&n.name.text===cls);return names.map(k=>c.members.find(n=>ts.isMethodDeclaration(n)&&n.name.getText(ast)===k).getText(ast)).join('\n');}
load(base+'util/messageTopicScope.ets',['conversationScopeKey','routeScopeKey']);
load(base+'util/messageLinkRoute.ets',['messageLinkRoute']);
load(base+'util/chatJumpChannel.ets',['subscribeChatJump','requestChatJump','resetChatJumpChannel']);
const chat=-1002267417810, id=12988*1048576;
const topics=[null,{'@type':'messageTopicThread',message_thread_id:42},
 {'@type':'messageTopicForum',forum_topic_id:42},
 {'@type':'messageTopicDirectMessages',direct_messages_chat_topic_id:42}];
const scopes=['chat','thread:42','forum:42','direct:42'];
const makeInfo=topic=>({chat_id:chat,topic_id:topic,message:{id,chat_id:chat,message_thread_id:999}});
for(let i=0;i<topics.length;i++){
 const params=ctx.messageLinkRoute(makeInfo(topics[i]));assert.equal(params.jumpTo,id);assert.equal(ctx.routeScopeKey(params),scopes[i]);
}
assert.equal(ctx.routeScopeKey(ctx.messageLinkRoute(makeInfo(null))),'chat','message membership must not invent a link destination');
assert.equal(ctx.messageLinkRoute({chat_id:0,message:{id}}),null);
assert.equal(ctx.messageLinkRoute({...makeInfo(null),topic_id:{'@type':'messageTopicUnknown',id:42}}),null);
assert.equal(ctx.messageLinkRoute({...makeInfo(null),topic_id:{'@type':'messageTopicThread',message_thread_id:0}}),null);
assert.equal(ctx.routeScopeKey(ctx.messageLinkRoute({...makeInfo(topics[1]),message:null})),'thread:42','topic-only links keep their scope');
const receipts=[];const offs=scopes.map(scope=>ctx.subscribeChatJump(chat,msg=>receipts.push([scope,msg]),scope));
ctx.requestChatJump(chat,id,'thread:42');assert.deepEqual(receipts,[['thread:42',id]]);
offs[1]();ctx.requestChatJump(chat,id,'thread:42');assert.equal(receipts.length,1);
ctx.requestChatJump(chat,id);assert.deepEqual(receipts.at(-1),['chat',id]);ctx.resetChatJumpChannel();
let pending=[],routes=[],jumps=[],errors=[],ended=[];
const client={send:req=>new Promise((resolve,reject)=>pending.push({req,resolve,reject}))};let activeClient=client;
Object.assign(ctx,{normalizeTelegramLink:url=>url,endLinkNavIf:url=>ended.push(url),
 navigateToChat:(p,o)=>{routes.push([p,o]);return Promise.resolve();},logChatNavFailure:e=>errors.push(e),
 openTelegramLink:()=>errors.push('fallback'),str:key=>key,logE:msg=>errors.push(msg),
 getTdClient:()=>activeClient,onLinkUnresolved:()=>errors.push('unresolved')});
load(base+'pages/chat/ChatMessageActionCoordinator.ets',['ChatMessageActionCoordinator']);
const coordinator=new ctx.ChatMessageActionCoordinator();let currentScope=0,currentChat=chat;
coordinator.bind({client:()=>activeClient,chatId:()=>currentChat,threadRootId:()=>currentScope===1?42:0,
 forumTopicId:()=>currentScope===2?42:0,directMessagesTopicId:()=>currentScope===3?42:0,
 jumpToLinkedMessage:msg=>jumps.push(msg),context:()=>({}),toast:o=>errors.push(o),logError:e=>errors.push(e)});
const flush=async()=>{await Promise.resolve();await Promise.resolve();await Promise.resolve();};
// Full 4x4 scope matrix: same chat ID and same numeric topic ID are not enough.
for(let current=0;current<4;current++)for(let target=0;target<4;target++){
 currentScope=current;routes=[];jumps=[];
 coordinator.resolveMessageLink('https://t.me/c/2267417810/12988');
 const req=pending.shift();assert.equal(req.req['@type'],'getMessageLinkInfo');req.resolve(makeInfo(topics[target]));await flush();
 if(current===target){assert.deepEqual(jumps,[id]);assert.equal(routes.length,0);}
 else{assert.equal(jumps.length,0);assert.equal(ctx.routeScopeKey(routes[0][0]),scopes[target]);assert.equal(routes[0][0].jumpTo,id);}
}
currentScope=1;routes=[];jumps=[];
coordinator.resolveMessageLink('https://t.me/c/2267417810/12988');let late=pending.shift();coordinator.reset();late.resolve(makeInfo(null));await flush();assert.equal(routes.length,0);assert.equal(jumps.length,0);
coordinator.resolveMessageLink('https://t.me/c/2267417810/12988');late=pending.shift();currentScope=2;late.resolve(makeInfo(null));await flush();assert.equal(routes.length,0);
coordinator.resolveMessageLink('https://t.me/c/2267417810/12988');late=pending.shift();activeClient={};late.resolve(makeInfo(null));await flush();assert.equal(routes.length,0);activeClient=client;
coordinator.resolveMessageLink('first');late=pending.shift();coordinator.resolveMessageLink('second');pending.shift().resolve(makeInfo(topics[2]));await flush();late.resolve(makeInfo(null));await flush();assert.equal(routes.length,0,'older request cannot override a newer jump');
// The external/profile/deep-link entry uses the same destination parser.
const externalAst=ts.createSourceFile('openTelegramLink.ets',fs.readFileSync(base+'util/openTelegramLink.ets','utf8'),ts.ScriptTarget.Latest,true);
run(externalAst.statements.find(n=>ts.isFunctionDeclaration(n)&&n.name?.text==='openMessageLink').getText(externalAst)+'\nglobalThis.openMessageLink=openMessageLink;');
for(let target=0;target<4;target++){
 routes=[];ctx.openMessageLink({},'link','original',true);pending.shift().resolve(makeInfo(topics[target]));await flush();assert.equal(ctx.routeScopeKey(routes[0][0]),scopes[target]);assert.equal(routes[0][0].jumpTo,id);
}
// Real chatNav: pushing another thread must not be mistaken for skip; popTo
// sends the target only to that frame, leaving the full chat and other threads alone.
let frames=[],pushes=0,pops=0;
const stack={pushPath:p=>{pushes++;frames.push(p);},pop:()=>{pops++;frames.pop();},clear:()=>{frames=[];}};
Object.assign(ctx,{KEY_MAIN_TAB:'tab',CHAT_TAB_INDEX:0,AppStorage:{setOrCreate(){},get(){}},
 stackOf:()=>stack,snapshotOf:(_stack,key)=>frames.map(f=>({name:f.name,key:key(f.name,f.param)})),
 canPrefetchChat:()=>false,isSplitByBreakpoint:()=>false,setChatListRenderActive(){},
 KEY_WIDTH_BREAKPOINT:'w',KEY_HEIGHT_BREAKPOINT:'h',KEY_WINDOW_PORTRAIT:'p',KEY_FORCE_SINGLE_COLUMN:'single',WIDTH_BP_SM:0,HEIGHT_BP_LG:0});
load(base+'util/splitRouting.ets',['decideChatPush']);load(base+'util/chatNav.ets',['navigateToChat']);
const seen=[];for(const scope of scopes)ctx.subscribeChatJump(chat,msg=>seen.push([scope,msg]),scope);
frames=[{name:'ChatPage',param:{chatId:chat}}];
await ctx.navigateToChat({chatId:chat,threadRootId:42,jumpTo:id},'content');assert.equal(pushes,1);assert.equal(frames.length,2);
await ctx.navigateToChat({chatId:chat,threadRootId:43,jumpTo:id},'content');assert.equal(pushes,2);
await ctx.navigateToChat({chatId:chat,threadRootId:42,jumpTo:id},'content');assert.equal(pops,1);assert.deepEqual(seen,[['thread:42',id]]);
await ctx.navigateToChat({chatId:chat,jumpTo:id},'content');assert.equal(pops,2);assert.deepEqual(seen.at(-1),['chat',id]);
await ctx.navigateToChat({chatId:chat,forumTopicId:42,jumpTo:id},'content');assert.equal(pushes,3);
await ctx.navigateToChat({chatId:chat,directMessagesTopicId:42,jumpTo:id},'content');assert.equal(pushes,4);
// Verify the actual ChatPage subscription call carries all three scope fields.
const pageAst=ts.createSourceFile('ChatPage.ts',fs.readFileSync(compiled+'pages/chat/ChatPage.ts','utf8'),ts.ScriptTarget.Latest,true);
let subscriptionCall;
function findSubscription(n){if(ts.isCallExpression(n)&&n.expression.getText(pageAst)==='subscribeChatJump')subscriptionCall=n;ts.forEachChild(n,findSubscription);}
findSubscription(pageAst);assert.ok(subscriptionCall);
run(`globalThis.subscribePage=function(){return ${subscriptionCall.getText(pageAst)};};`);
ctx.resetChatJumpChannel();let pageHits=0;
const offPage=ctx.subscribePage.call({chatId:chat,threadRootId:42,forumTopicId:0,directMessagesTopicId:0,jumpToMessageId:()=>pageHits++});
ctx.requestChatJump(chat,id);ctx.requestChatJump(chat,id,'forum:42');assert.equal(pageHits,0);
ctx.requestChatJump(chat,id,'thread:42');assert.equal(pageHits,1);offPage();
// Real compiled ChatPage cold/warm branch: cold targets request history, warm
// targets scroll immediately. A disposed store cannot toast into a new page.
run(`class PageProbe {${methods(compiled+'pages/chat/ChatPage.ts','ChatPage',['jumpToLinkedMessageInThisChat'])}} globalThis.PageProbe=PageProbe;`);
run(`class StoreProbe {${methods(base+'store/MessageStore.ets','MessageStore',['historyRequest'])}} globalThis.StoreProbe=StoreProbe;`);
ctx.groupIndexOf=(groups,msg)=>groups.indexOf(msg);ctx.logW=()=>{};ctx.$r=key=>key;ctx.showToast=()=>errors.push('toast');
const storeProbe=new ctx.StoreProbe();Object.assign(storeProbe,{chatId:chat,threadRootId:42,forumTopicId:0,directMessagesTopicId:0,historyPageSize:30});
let around,completion,scrolled=0;
const page=new ctx.PageProbe();Object.assign(page,{chatId:chat,timeline:{groups:[]},prepareUserJump(){},beginJumpLanding(){},
 scrollAndSettleJumpTarget:()=>scrolled++,store:{loadAround:(msg,fn)=>{around=storeProbe.historyRequest(msg,-15);completion=fn;}}});
page.jumpToLinkedMessageInThisChat(id);assert.equal(around['@type'],'getMessageThreadHistory');assert.equal(around.message_id,42);assert.equal(around.from_message_id,id);
assert.equal(scrolled,0);page.store={};const oldErrors=errors.length;completion(false);assert.equal(errors.length,oldErrors);
page.timeline.groups=[id];page.jumpToLinkedMessageInThisChat(id);assert.equal(scrolled,1);
storeProbe.threadRootId=0;assert.equal(storeProbe.historyRequest(id,-15).only_local,false);
console.log('message link scope: PASS (16-scope matrix, resolved topics, isolated jump delivery, push/popTo/skip, stale request cancellation, cold/warm history and stale-store callback)');
