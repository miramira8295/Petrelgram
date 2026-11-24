// Real send planning, recovery and receiver lifecycle, with device I/O replaced.
import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
const imported = await import(process.env.TYPESCRIPT_MODULE || 'typescript');
const ts = imported.default || imported;
const read = p => fs.readFileSync(`entry/src/main/ets/${p}.ets`, 'utf8');
const js = source => ts.transpileModule(source.replace(/^import[\s\S]*?;\r?\n/gm, '')
  .replace(/@(?:ObservedV2|Component)\s*/g, '').replace(/@StorageProp\([^\n]*?\)\s*/g, '')
  .replace(/@Watch\([^\n]*?\)\s*/g, '').replace(/@(?:Trace|State)\s*/g, '')
  .replace(/\bexport /g, '').replace(/\bstruct /g, 'class '),
  { compilerOptions: { target: ts.ScriptTarget.ES2020 } }).outputText;
class TdError extends Error { constructor(code, message) { super(message); this.code = code; } }
class SendPermissionError extends Error {}
let animated = true, nextTimer = 0;
const timers = new Map(), allTimers = new Map(), cleanups = [], dialogs = [], toasts = [];
const ctx = vm.createContext({ TdError, SendPermissionError, str:x=>x, $r:x=>x, logE:()=>{}, logI:()=>{}, showToast:t=>toasts.push(t),
  isAnimationPath:p=>p.endsWith('.gif'), powerAnimationDuration:(_key,d)=>animated?d:0, KEY_POWER_SMOOTH_TRANSITIONS:'animation',
  setTimeout(fn, delay) { const id=++nextTimer;const fire=()=>{timers.delete(id);fn();};timers.set(id,{fn:fire,delay});allTimers.set(id,fire);return id; },
  clearTimeout:id=>timers.delete(id), getActiveTdAccountSlot:()=> 'account',
  isSameChatMessageDragExtra:x=>x==='self', isSameChatMessageDrag:x=>x==='self',
  fs:{rmdir:async p=>{cleanups.push(p);}}, sweepStaging:()=>{}, ensureStagingDir:(_p,_n,_t,id)=>`/cache/${id}`,
  decodeDrop:async data=>data.payload, fileUri:{getUriFromPath:p=>p},
  udc:{FileConflictOptions:{SKIP:0},ProgressIndicator:{DEFAULT:0}},
  DragResult:{DRAG_CANCELED:'cancel',DRAG_FAILED:'failed',DRAG_SUCCESSFUL:'ok'},DragBehavior:{COPY:0},
  openDropRecovery(ui, payload, target, active, send, closed, initial) {
    const dialog={payload,target,active,send,closed,initial};dialogs.push(dialog);
    return ()=>{dialog.closedByReceiver=true;closed();};
  }
});
const load = (p,names) => vm.runInContext(js(read(p)+`\nObject.assign(globalThis,{${names.join(',')}});`),ctx);
load('util/directSharePlan',['directShareSteps']);load('util/sendProgress',['SendProgress']);
load('util/shareArrival',['sendShareDirectly','remainingDirectShare']);load('util/dropSend',['sendDropBatch']);
load('util/dropArrival',['DropArrivalSession']);load('pages/chat/ChatDropReceiver',['ChatDropReceiver']);
load('pages/chat/DropHoverState',['DropHoverState']);
const item=(uri,kind='file')=>({uri,kind,title:uri,text:'',sourceUri:''});
const payload=(...items)=>({caption:'caption',media:items});
function host() {
  const h={calls:[],draft:'existing',scrolls:0,alive:true,fail:null,
    checkPermissions:async()=>{}, appendMedia:()=>0, draftText:()=>h.draft,setDraft:t=>h.draft=t,
    scrollToBottom:()=>h.scrolls++};
  for(const [method,kind] of [['sendDocument','file'],['sendAudio','audio'],['sendMedia','media'],['sendText','text']]) {
    h[method]=async (data,caption)=>{h.calls.push({kind,data,caption});if(h.fail)await h.fail(h.calls.at(-1));};
  }
  return h;
}
let tests=0;
async function check(name, fn) { try { await fn();tests++; } catch(e) { e.message=`${name}: ${e.message}`;throw e; } }
const plain=x=>JSON.parse(JSON.stringify(x));
const tick=async()=>{for(let i=0;i<40;i++)await Promise.resolve();};
const deferred=()=>{let resolve,reject;const promise=new Promise((a,b)=>{resolve=a;reject=b;});return {promise,resolve,reject};};
await check('partial failure retries only unsent remainder, without duplicating caption',async()=>{
  const h=host(),p=payload(item('a'),item('b'),item('c'));
  h.fail=async c=>{if(c.data==='b')throw new TdError(500,'failed');};
  const result=await ctx.sendDropBatch(p,h,()=>h.alive);
  assert.deepEqual(plain(result.remaining),{caption:'',media:[item('b'),item('c')]});assert.equal(result.uncertain,false);
  h.fail=null;assert.equal((await ctx.sendDropBatch(result.remaining,h,()=>h.alive)).remaining,null);
  assert.deepEqual(h.calls.map(c=>c.data),['a','b','b','c']);assert.equal(h.calls[2].caption,'');
});
await check('first failure preserves caption and timeout marks unknown outcome',async()=>{
  const h=host(),p=payload(item('a'),item('b'));h.fail=async()=>{throw new TdError(-1,'timeout');};
  const result=await ctx.sendDropBatch(p,h,()=>true);
  assert.equal(result.uncertain,true);assert.deepEqual(plain(result.remaining),p);assert.equal(h.calls.length,1);
});
await check('mixed album and document recovery preserves order',async()=>{
  const h=host();h.fail=async c=>{if(c.kind==='audio')throw new TdError(500,'failed');};
  const result=await ctx.sendDropBatch(payload(item('image','image'),item('video','video'),item('song','audio'),item('doc')),h,()=>true);
  assert.deepEqual(h.calls.map(c=>c.kind),['media','audio']);
  assert.deepEqual(plain(result.remaining),{caption:'',media:[item('song','audio'),item('doc')]});
});
await check('permission denial sends nothing and can recover',async()=>{
  const h=host();h.checkPermissions=async()=>{throw new SendPermissionError('denied');};
  const result=await ctx.sendDropBatch(payload(item('a')),h,()=>true);
  assert.equal(result.error,'denied');assert.equal(h.calls.length,0);
});
await check('leaving during last response never scrolls another page',async()=>{
  const h=host();h.fail=async()=>{h.alive=false;};
  await ctx.sendDropBatch(payload(item('a')),h,()=>h.alive);assert.equal(h.scrolls,0);
});
await check('leaving mid batch stops remaining sends',async()=>{
  const h=host();h.fail=async()=>{h.alive=false;};
  assert.equal((await ctx.sendDropBatch(payload(item('a'),item('b')),h,()=>h.alive)).remaining,null);
  assert.equal(h.calls.length,1);assert.equal(h.scrolls,0);
});
await check('large-batch work stays linear',async()=>{
  const h=host();let reads=0;const items=Array.from({length:1000},(_,i)=>({get kind(){reads++;return 'file';},uri:`${i}`}));
  h.fail=async c=>{if(c.data==='999')throw new TdError(500,'failed');};
  const result=await ctx.sendDropBatch(payload(...items),h,()=>true);
  assert.equal(h.calls.length,1000);assert.equal(result.remaining.media.length,1);assert.ok(reads<=10000);
});
const event=p=>({getData:()=>({getRecords:()=>[1],properties:{tag:''},payload:p}),setResult(r){this.result=r;}});
const receive=(r,h,p,extra)=>{const e=event(p);r.receive(e,{cacheDir:'/cache'},{},h,()=>h.alive,'Chat',1,extra);return e;};
await check('successful drop sends immediately without dialog',async()=>{
  const h=host(),r=new ctx.ChatDropReceiver(),count=dialogs.length;
  receive(r,h,payload(item('a')));await tick();assert.equal(h.calls.length,1);assert.equal(dialogs.length,count);assert.equal(r.pending,false);
});
await check('receiver retains first permission failure for retry, checking once per attempt',async()=>{
  const h=host(),r=new ctx.ChatDropReceiver(),p=payload(item('photo','image'),item('document'));
  const cleanupCount=cleanups.length,dialogCount=dialogs.length;let checks=0,denied=true;
  h.checkPermissions=async()=>{checks++;if(denied)throw new SendPermissionError('denied');};
  receive(r,h,p);await tick();
  assert.equal(checks,1);assert.equal(h.calls.length,0);assert.equal(dialogs.length,dialogCount+1);
  assert.equal(cleanups.length,cleanupCount);assert.equal(r.isPending(),true);
  const d=dialogs.at(-1);assert.deepEqual(plain(d.payload),p);assert.equal(d.initial.error,'denied');
  assert.equal(d.initial.uncertain,false);
  const stillDenied=await d.send(d.payload);
  assert.deepEqual(plain(stillDenied.remaining),p);assert.equal(h.calls.length,0);assert.equal(checks,2);
  denied=false;assert.equal((await d.send(d.payload)).remaining,null);d.closed();
  assert.equal(checks,3);assert.equal(r.isPending(),false);assert.equal(h.calls.length,2);
  assert.equal(h.calls[0].caption,'caption');assert.equal(h.calls[1].caption,'');
});
await check('permission timeout before any send is safe to retry',async()=>{
  const h=host(),r=new ctx.ChatDropReceiver(),p=payload(item('file'));
  h.checkPermissions=async()=>{throw new TdError(-1,'permission query timeout');};
  receive(r,h,p);await tick();const d=dialogs.at(-1);
  assert.equal(h.calls.length,0);assert.deepEqual(plain(d.payload),p);assert.equal(d.initial.uncertain,false);
  r.cancel();assert.equal(d.closedByReceiver,true);assert.equal(r.isPending(),false);
});
await check('text permission denial preserves draft and cleans its staging directory',async()=>{
  const h=host(),r=new ctx.ChatDropReceiver(),dialogCount=dialogs.length,cleanupCount=cleanups.length;
  h.checkPermissions=async()=>{throw new SendPermissionError('denied');};
  receive(r,h,{caption:'incoming',media:[]});await tick();
  assert.equal(h.draft,'existing');assert.equal(h.calls.length,0);assert.equal(dialogs.length,dialogCount);
  assert.equal(cleanups.length,cleanupCount+1);assert.equal(r.isPending(),false);
});
await check('leaving during initial media check prevents send and recovery',async()=>{
  const h=host(),r=new ctx.ChatDropReceiver(),wait=deferred(),dialogCount=dialogs.length;
  h.checkPermissions=()=>wait.promise;
  receive(r,h,payload(item('photo','image')));await tick();assert.equal(r.isPending(),true);
  r.cancel();wait.resolve();await tick();
  assert.equal(h.calls.length,0);assert.equal(dialogs.length,dialogCount);assert.equal(r.isPending(),false);
});
await check('text only appends draft and self drags are ignored',async()=>{
  const h=host(),r=new ctx.ChatDropReceiver();receive(r,h,{caption:'incoming',media:[]});await tick();
  assert.equal(h.draft,'existing\nincoming');assert.equal(h.calls.length,0);assert.equal(r.pending,false);
  assert.equal(receive(r,h,payload(item('a')),'self').result,'cancel');assert.equal(h.calls.length,0);
});
await check('failure opens only remaining batch and blocks concurrent drop until dismissed',async()=>{
  const h=host(),r=new ctx.ChatDropReceiver();h.fail=async c=>{if(c.data==='b')throw new TdError(500,'failed');};
  receive(r,h,payload(item('a'),item('b')));await tick();const d=dialogs.at(-1);
  assert.deepEqual(plain(d.payload),{caption:'',media:[item('b')]});assert.equal(r.pending,true);
  assert.equal(receive(r,h,payload(item('c'))).result,'failed');h.fail=null;
  await d.send(d.payload);d.closed();assert.equal(r.pending,false);
  assert.deepEqual(h.calls.map(c=>c.data),['a','b','b']);
});
await check('cancel closes recovery and stale completions cannot release newer drop',async()=>{
  const h=host(),r=new ctx.ChatDropReceiver(),wait=deferred();h.sendDocument=()=>wait.promise;
  receive(r,h,payload(item('old')));await tick();r.cancel();
  h.sendDocument=async()=>{throw new TdError(500,'failed');};receive(r,h,payload(item('new')));await tick();
  const d=dialogs.at(-1);wait.resolve();await tick();assert.equal(r.pending,true);assert.equal(d.payload.media[0].uri,'new');
  r.cancel();assert.equal(d.closedByReceiver,true);assert.equal(r.pending,false);
});
await check('cancel while loading never sends delayed payload',async()=>{
  const h=host(),r=new ctx.ChatDropReceiver(),wait=deferred();const original=ctx.decodeDrop;ctx.decodeDrop=()=>wait.promise;
  receive(r,h,payload(item('a')));r.cancel();wait.resolve(payload(item('a')));await tick();
  assert.equal(h.calls.length,0);assert.equal(r.pending,false);ctx.decodeDrop=original;
});
await check('hover timers bounded, stale enter/leave ignored, reduced motion immediate',async()=>{
  timers.clear();const s=new ctx.DropHoverState();s.setVisible(true);const enter=allTimers.get(nextTimer);
  for(let i=0;i<1000;i++)s.setVisible(true);assert.equal(timers.size,1);
  s.dispose();enter();assert.equal(s.visible,false);assert.equal(s.shown,false);
  s.setVisible(true);allTimers.get(nextTimer)();s.setVisible(false);const leave=allTimers.get(nextTimer);
  s.setVisible(true);leave();assert.equal(s.visible,true);
  s.dispose();animated=false;s.setVisible(true);assert.equal(s.shown,true);assert.equal(timers.size,0);
  s.setVisible(false);assert.equal(s.visible,false);animated=true;
});
// Test real dialog callbacks without creating UI or sending any real messages.
const dialogSource=read('pages/chat/DropRecoveryDialog');
const component=dialogSource.slice(dialogSource.indexOf('@Component'),dialogSource.indexOf('  build() {'))+'}\nglobalThis.Recovery=DropRecoveryDialog;';
vm.runInContext(js(component),ctx);
await check('unknown outcome disables retry even for queued callback',async()=>{
  const d=new ctx.Recovery();let calls=0;d.active=()=>true;d.payload=payload(item('a'));
  d.initialResult={uncertain:true,error:'',remaining:d.payload};d.onSend=async()=>{calls++;};
  d.aboutToAppear();d.send();await tick();assert.equal(calls,0);assert.equal(d.uncertain,true);
});
await check('retry double click and closed dialog cannot issue extra send',async()=>{
  const d=new ctx.Recovery(),wait=deferred();let calls=0,closes=0;
  d.active=()=>true;d.payload=payload(item('a'));d.onClose=()=>closes++;d.onSend=()=>{calls++;return wait.promise;};
  d.aboutToAppear();d.send();d.send();assert.equal(calls,1);assert.equal(closes,0);
  wait.resolve({remaining:null,uncertain:false,error:''});await tick();d.send();assert.equal(calls,1);assert.equal(closes,1);
});
// Page routing must preserve the outgoing hint while its exit animation runs.
const page=read('pages/chat/ChatPage');
const methods=page.slice(page.indexOf('  private setDropHover('),page.indexOf('  private shareHost('));
vm.runInContext(js('class DropPageHarness { '+methods+' }\nglobalThis.DropPageHarness=DropPageHarness;'),ctx);
await check('hover and receiver agree during loading, sending, recovery and after dismissal',async()=>{
  const h=host(),r=new ctx.ChatDropReceiver(),wait=deferred(),send=deferred(),p=new ctx.DropPageHarness();
  Object.assign(p,{dropReceiver:r,timeline:{pageVisible:true},appIsForeground:true,viewerOpen:()=>false,
    search:{mode:false},selection:{active:false},composer:{editingId:0},recording:{isRecording:false},membershipState:'writable'});
  const original=ctx.decodeDrop;ctx.decodeDrop=()=>wait.promise;let sends=0;
  h.sendDocument=()=>{sends++;return send.promise;};
  assert.equal(p.dropHoverAllowed(),true);receive(r,h,payload(item('first')));await tick();
  assert.equal(p.dropHoverAllowed(),false);
  assert.equal(receive(r,h,payload(item('second'))).result,'failed');assert.equal(toasts.at(-1),'app.string.processing');
  assert.equal(sends,0);wait.resolve(payload(item('first')));await tick();ctx.decodeDrop=original;
  assert.equal(p.dropHoverAllowed(),false);assert.equal(sends,1);
  send.reject(new TdError(500,'failed'));await tick();assert.equal(p.dropHoverAllowed(),false);
  dialogs.at(-1).closed();assert.equal(p.dropHoverAllowed(),true);
  h.sendDocument=async()=>{sends++;};receive(r,h,payload(item('third')));await tick();
  assert.equal(sends,2);assert.equal(p.dropHoverAllowed(),true);
});
await check('unknown types stay neutral and fading hint does not change on drop',async()=>{
  const p=new ctx.DropPageHarness();p.dropHover=new ctx.DropHoverState();p.dropHoverHideTimer=-1;p.chatId=1;
  const data=types=>({getData:()=>({getRecords:()=>types.map(type=>({getType:()=>type}))})});
  assert.equal(p.dropSendsDirectly(data(['general.plain-text','general.hyperlink'])),false);
  assert.equal(p.dropSendsDirectly(data(['general.image'])),true);
  assert.equal(p.dropSendsDirectly(data([])),null);
  assert.equal(p.dropSendsDirectly({getData(){throw new Error('deferred');}}),null);
  p.setDropHover(true,undefined,true);p.setDropHover(false);assert.equal(p.dropHover.sendMode,true);p.dropHover.dispose();
});
const rendered=[],glass=[];
class View {
  initParam(k,v){this[k]=v;} finalizeConstruction(){} observeComponentCreation2(fn){fn(1,true);}
  ifElseBranchUpdateFunction(_i,fn){fn();} static create(){}
}
const ui=vm.createContext({ViewV2:View,ViewPU:class{},systemMaterialState:{chatEnabled:false},
  immersiveMaterialAvailable:()=>true,NativeGlassHost:class{constructor(_parent,params){glass.push(params);}},
  str:k=>k,COLOR_PRIMARY:'primary',COLOR_TEXT_PRIMARY:'text',COLOR_TEXT_SECONDARY:'secondary',
  Color:{Transparent:'transparent'},Alignment:{Center:0,TopStart:1},HitTestMode:{None:0},
  BorderStyle:{Dashed:0},FontWeight:{Medium:0},TextAlign:{Center:0},TextOverflow:{Ellipsis:0},Curve:{EaseOut:0,EaseIn:1},
  KEY_POWER_SMOOTH_TRANSITIONS:'animation',powerAnimationDuration:(_k,d)=>animated?d:0});
for(const type of ['Context','If','Stack','Column','Circle','SymbolGlyph','Text'])ui[type]=new Proxy({}, {get:(_t,key)=>(...args)=>rendered.push({type,key,args})});
const compiled='entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/pages/chat/DropHoverOverlay.ts';
vm.runInContext(js(fs.readFileSync(compiled,'utf8').replace(/@(?:Require|Param|Local)\s*/g,'')+'\nglobalThis.Overlay=DropHoverOverlay;'),ui);
await check('compiled overlay follows material, reduced motion and pass-through hit testing',async()=>{
  const o=new ui.Overlay(null,{state:{visible:true,shown:true,sendMode:true},target:'Chat'});o.cardW=300;o.cardH=220;
  o.initialRender();assert.equal(glass.length,0);assert.ok(rendered.some(r=>r.key==='hitTestBehavior'&&r.args[0]===0));
  ui.systemMaterialState.chatEnabled=true;o.initialRender();assert.equal(glass.length,1);assert.equal(glass[0].surface,'control');
  rendered.length=0;animated=false;o.initialRender();
  assert.ok(rendered.filter(r=>r.key==='animation'&&r.args[0]).every(r=>r.args[0].duration===0));animated=true;
  rendered.length=0;o.state.visible=false;o.initialRender();assert.ok(!rendered.some(r=>r.type==='Stack'&&r.key==='create'));
});
console.log(`PASS: ${tests} drop direct-send/recovery/lifecycle/complexity cases; no real messages sent.`);
