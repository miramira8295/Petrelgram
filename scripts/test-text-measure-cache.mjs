import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
const imported=await import(process.env.TYPESCRIPT_MODULE || 'typescript');const ts=imported.default||imported;
const read=name=>fs.readFileSync(new URL('../entry/src/main/ets/'+name,import.meta.url),'utf8');
const shell=read('pages/chat/MessageBubbleShell.ets');
function method(name){const a=shell.indexOf('  private '+name+'(');return shell.slice(a,shell.indexOf('\n  }',a)+4);}
const capability=shell.match(/^let sharedTextMeasurementSupported:.*$/m)[0];
const source=capability+read('util/textMeasureCache.ets')+read('util/reactionsWidth.ets')+`
let nextScope=100;
class Host {
 scope=nextScope++;density=1;fontScale=1;scopeThrows=false;scopeReads=0;
 textMeasureCache=new TextMeasureCache();textMeasureFailed=false;rxWidthSig='';rxWidthCache=0;
 env={langEpoch:0,appearanceEpoch:0};available=300;clock='12:30';
 msg={reactions:[{emoji:'👍',customEmojiId:'',count:1}],editDate:0,isOutgoing:false};
 context={liveViews:''};data={isChannel:false};
 inlineMaxW(){return this.available;} messageTimeText(){return this.clock;}
 getUIContext(){return {getId:()=>{this.scopeReads++;if(this.scopeThrows)throw Error('no context');return this.scope;},vp2px:()=>this.density,fp2px:()=>this.fontScale,getMeasureUtils:()=>({measureTextSize:({textContent,fontSize})=>({width:measure(textContent,fontSize)})})};}
 ${method('reactionsRowWidth')} ${method('measureTextVp')} ${method('reactorsArrowShown')}
}
globalThis.Host=Host;globalThis.Cache=TextMeasureCache;globalThis.Pool=TextMeasureCachePool;globalThis.invalidate=invalidateTextMeasurements;`;
let calls=0,fail=false,scale=1;
const deviceInfo={sdkApiVersion:22};
const globals={measure:(text,size)=>{calls++;if(fail)throw Error('temporary');return text.length*size*scale;},px2vp:n=>n,str:()=> 'edited', REACTORS_ARROW_PAD_H:9,REACTORS_ARROW_ICON_VP:16,REACTORS_ARROW_MARGIN_R:4};
const compiled=ts.transpileModule(source.replace(/\bexport /g,'').replace(/@(?:ObservedV2|Trace)\s*/g,''),{compilerOptions:{target:ts.ScriptTarget.ES2020}}).outputText;
function setup(deviceInfo){const ctx=vm.createContext({...globals,deviceInfo});vm.runInContext(compiled,ctx);return ctx;}
const ctx=setup(deviceInfo);
let count=0;function test(name,fn){try{fn();count++;}catch(e){e.message=name+': '+e.message;throw e;}}
test('identical labels across different rows reuse native measurements',()=>{
 const h=new ctx.Host();h.reactionsRowWidth();const first=calls;
 h.msg={...h.msg,reactions:[{emoji:'👍',customEmojiId:'',count:2}]};h.reactionsRowWidth();assert.equal(calls,first+1);
 h.msg={...h.msg,reactions:[{emoji:'👍',customEmojiId:'',count:1}]};h.reactionsRowWidth();assert.equal(calls,first+1);
});
test('available width changes invalidate row clamp without remeasuring glyphs',()=>{
 const h=new ctx.Host();h.msg.reactions=Array.from({length:8},()=>({emoji:'👍',customEmojiId:'',count:123}));
 const wide=h.reactionsRowWidth(),n=calls;h.available=150;assert.ok(h.reactionsRowWidth()<wide);assert.equal(calls,n);
});
test('configuration and language changes remeasure and rebuild row width',()=>{
 const h=new ctx.Host();h.reactionsRowWidth();let n=calls;scale=2;ctx.invalidate();h.reactionsRowWidth();assert.ok(calls>n);
 n=calls;h.env.langEpoch++;h.reactionsRowWidth();assert.ok(calls>n);scale=1;
});
test('temporary native failure cannot poison either cache',()=>{
 const h=new ctx.Host();fail=true;h.reactionsRowWidth();assert.equal(h.rxWidthSig,'');let n=calls;
 fail=false;h.reactionsRowWidth();assert.ok(calls>n);assert.notEqual(h.rxWidthSig,'');
});
test('time, edited status, views, direction and custom emoji retain width semantics',()=>{
 const h=new ctx.Host();
 for(const change of [()=>h.clock='1:23',()=>h.msg.editDate=1,()=>h.context.liveViews='10K',()=>h.msg.isOutgoing=true,()=>h.msg.reactions[0].customEmojiId='123']){
  h.reactionsRowWidth();change();const measured=h.reactionsRowWidth();const cached=h.textMeasureCache;h.textMeasureCache=new ctx.Cache();h.rxWidthSig='';assert.equal(h.reactionsRowWidth(),measured);h.textMeasureCache=cached;
 }
});
test('cache bounded, long strings bypass storage, distinct sizes remain independent',()=>{
 const c=new ctx.Cache();let n=0;const measure=()=>++n;
 for(let i=0;i<200;i++)c.width(String(i),12,measure);assert.ok(c.values.size<=64);
 c.width('x'.repeat(129),12,measure);c.width('x'.repeat(129),12,measure);assert.equal(n,202);
 assert.notEqual(c.width('same',12,measure),c.width('same',13,measure));
});
test('one time lookup per width evaluation including cache misses',()=>{
 const h=new ctx.Host();let timeReads=0;const original=h.messageTimeText;
 h.messageTimeText=function(){timeReads++;return original.call(this);};
 h.reactionsRowWidth();assert.equal(timeReads,1);
 h.reactionsRowWidth();assert.equal(timeReads,2);
 h.context.liveViews='10K';h.reactionsRowWidth();assert.equal(timeReads,3);
});
test('different bubble owners share identical labels only within their UI instance',()=>{
 const a=new ctx.Host(),b=new ctx.Host();b.scope=a.scope;
 const start=calls,width=a.reactionsRowWidth(),n=calls;
 assert.equal(b.reactionsRowWidth(),width);assert.equal(calls,n);
 console.log(`Shared labels (host): first owner ${n-start} native calls, second owner ${calls-n}`);
 const c=new ctx.Host();assert.equal(c.reactionsRowWidth(),width);assert.ok(calls>n);
 const reads=a.scopeReads;a.rxWidthSig='';a.reactionsRowWidth();assert.equal(a.scopeReads,reads);
});
test('new owners cannot reuse measurements after density, font or appearance changes',()=>{
 const a=new ctx.Host();a.reactionsRowWidth();
 for(const change of [h=>h.density=2,h=>h.fontScale=3,h=>h.env.appearanceEpoch++,h=>h.env.langEpoch++,()=>ctx.invalidate()]){
  const h=new ctx.Host();h.scope=a.scope;change(h);const n=calls;h.reactionsRowWidth();assert.ok(calls>n);
 }
});
test('old SDKs never call getId and retain native measurements per owner',()=>{
 for(const api of [20,21]){
  const oldSdk=setup({sdkApiVersion:api});const a=new oldSdk.Host(),b=new oldSdk.Host();b.scope=a.scope;
  a.reactionsRowWidth();const n=calls;b.reactionsRowWidth();assert.ok(calls>n);
  assert.equal(a.scopeReads,0);assert.equal(b.scopeReads,0);assert.equal(b.textMeasureFailed,false);
 }
});
test('SDK capability is read once across owners, misses and configuration invalidation',()=>{
 let reads=0;const current=setup({get sdkApiVersion(){reads++;return 26;}});
 assert.equal(reads,0);
 const a=new current.Host();a.reactionsRowWidth();assert.equal(reads,1);
 const b=new current.Host();b.reactionsRowWidth();
 a.msg.reactions[0].count=42;a.reactionsRowWidth();current.invalidate();a.reactionsRowWidth();
 assert.equal(reads,1);assert.ok(a.scopeReads>0);assert.ok(b.scopeReads>0);
});
test('a failed SDK read can recover on the next measurement',()=>{
 let reads=0;const current=setup({get sdkApiVersion(){reads++;if(reads===1)throw Error('temporary');return 26;}});
 const a=new current.Host();a.measureTextVp('label',12);assert.equal(a.textMeasureFailed,true);
 const n=calls;a.textMeasureFailed=false;a.measureTextVp('label',12);assert.equal(a.textMeasureFailed,false);
 assert.equal(reads,2);assert.equal(calls,n+1);
});
test('unavailable identity or invalid units falls back to real measurements',()=>{
 for(const change of [h=>h.scopeThrows=true,h=>h.scope=-1,h=>h.density=NaN,h=>h.fontScale=0]){
  const a=new ctx.Host(),b=new ctx.Host();b.scope=a.scope;change(a);change(b);
  const width=a.reactionsRowWidth(),n=calls;assert.equal(b.reactionsRowWidth(),width);
  assert.ok(calls>n);assert.equal(b.textMeasureFailed,false);
 }
});
test('failed native measurements recover across owners without shared approximate values',()=>{
 const a=new ctx.Host(),b=new ctx.Host();b.scope=a.scope;fail=true;a.reactionsRowWidth();
 assert.equal(a.textMeasureFailed,true);const n=calls;fail=false;b.reactionsRowWidth();assert.ok(calls>n);
 assert.equal(b.textMeasureFailed,false);const recovered=calls;
 a.reactionsRowWidth();assert.equal(calls,recovered);assert.equal(a.textMeasureFailed,false);
});
test('pool retains at most four instances and 256 short labels per instance',()=>{
 const pool=new ctx.Pool();let n=0;const measure=()=>++n;
 for(let id=0;id<10;id++)for(let i=0;i<300;i++)pool.width(id,'epoch',String(i),12,measure);
 assert.equal(pool.scopes.size,4);for(const cache of pool.scopes.values())assert.ok(cache.values.size<=256);
 const before=n;pool.width(0,'epoch','299',12,measure);assert.equal(n,before+1);
});
test('pool rejects bad results, long strings and invalid instance IDs',()=>{
 const pool=new ctx.Pool();let n=0;const measure=()=>++n;
 for(const id of [-1,NaN,Infinity,0.5]){const before=n;pool.width(id,'e','x',12,measure);pool.width(id,'e','x',12,measure);assert.equal(n,before+2);}
 for(const bad of [NaN,Infinity,-1]){pool.width(1,'e','bad',12,()=>bad);assert.ok(pool.width(1,'e','bad',12,measure)>0);pool.width(1,'new'+bad,'x',12,measure);}
 const before=n;pool.width(2,'e','x'.repeat(129),12,measure);pool.width(2,'e','x'.repeat(129),12,measure);assert.equal(n,before+2);
});
console.log(`Text measurement: ${count} host scenarios passed`);
