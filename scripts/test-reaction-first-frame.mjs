// Exercise production lifecycle/render methods with deterministic native doubles.
// Successful Canvas submission is tested here; pixels/compositor timing need device QA.
import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
const ts=(await import(process.env.TYPESCRIPT_MODULE||'typescript')).default;
const root='entry/src/main/ets/';
const pending=[];
const ctx=vm.createContext({chatEnv:{},RenderingContextSettings:class{},
 CanvasRenderingContext2D:class{clearRect(){}drawImage(){}},
 TgsRenderTicket:class{},queueTgsRenderTicketed:()=>new Promise((resolve,reject)=>pending.push({resolve,reject})),
 logE:()=>{},logW:()=>{},forgetPlayedOnce:()=>{},clearTimeout:()=>{}});
function load(name){
 let source=fs.readFileSync(root+'pages/chat/'+name+'.ets','utf8').replace(/^import\s[\s\S]*?;\r?\n/gm,'').replace(/\bexport /g,'');
 source=source.slice(0,source.indexOf('  build() {'))+'\n}';
 source=source.replace(/@ComponentV2\s*/g,'').replace(/\bstruct\b/g,'class').replace(/@(?:Require|Param|Event|Local|Computed)\s*/g,'').replace(/@Monitor\([^)]*\)\s*/g,'');
 vm.runInContext(ts.transpileModule(source+'\nglobalThis.'+name+'='+name+';',{compilerOptions:{target:ts.ScriptTarget.ES2020}}).outputText,ctx,{filename:name});
}
load('TgsNativeStickerView');
const make=()=>{
 const v=new ctx.TgsNativeStickerView();
 for(const method of ['open','close','releaseSlot','clearFrameCache','maybeStart'])v[method]=()=>{};
 v.inSafeTimelineViewport=()=>true;v.loop=false;v.handle=1;return v;
};
const bitmap=()=>({released:0,release(){this.released++;}});
const drain=async()=>{await Promise.resolve();await Promise.resolve();};
{
 const v=make();v.drawBitmap(bitmap());assert.equal(v.painted,true,'old callers need no callback');
}
{
 const v=make();let started=0,failed=0;v.onWorking=()=>started++;v.onFailed=()=>failed++;
 v.ctx.drawImage=()=>{throw Error('canvas not ready');};v.drawBitmap(bitmap());assert.equal(started,0);assert.equal(v.painted,false);
 v.ctx.drawImage=()=>{};v.drawBitmap(bitmap());v.drawBitmap(bitmap());assert.equal(started,1);
 v.playOnce=true;v.replayToken=1;v.onReplayRequested();assert.equal(v.painted,false);v.drawBitmap(bitmap());assert.equal(started,2,'same path replay must notify once again');
 v.tgsPath='b.tgs';v.onPathChanged();v.drawBitmap(bitmap());assert.equal(started,3);
 v.failed=true;v.drawBitmap(bitmap());assert.equal(started,3);v.failed=false;
 v.aboutToRecycle();v.drawBitmap(bitmap());assert.equal(started,3,'recycled view must not notify');
 v.aboutToReuse();v.drawBitmap(bitmap());assert.equal(started,4);assert.equal(failed,0);
}
{
 const v=make();let started=0,failed=0;v.onWorking=()=>started++;v.onFailed=()=>failed++;
 v.renderFrame(0);const stale=pending.shift();v.resetForNewSource();const old=bitmap();stale.resolve({frame:old,skipped:false});await drain();
 assert.equal(old.released,1);assert.equal(started,0);
 v.renderFrame(0);const current=pending.shift(),fresh=bitmap();current.resolve({frame:fresh,skipped:false});await drain();assert.equal(started,1);assert.equal(fresh.released,1);
 v.resetForNewSource();v.renderFrame(0);pending.shift().resolve({frame:null,skipped:false});await drain();assert.equal(failed,1);assert.equal(started,1);
 v.resetForNewSource();v.renderFrame(0);const retired=pending.shift();v.aboutToRecycle();retired.reject(Error('late failure'));await drain();assert.equal(failed,1);assert.equal(started,1);
 v.aboutToReuse();v.renderFrame(0);const aba=pending.shift();v.aboutToDisappear();v.disposed=false;aba.resolve({frame:bitmap(),skipped:false});await drain();assert.equal(started,1,'disappear/reappear cannot accept old generation');
 v.resetForNewSource();v.frameCache.set(0,bitmap());v.renderFrame(0);assert.equal(started,2,'cached first frame uses the same successful-draw callback');
}
load('ReactionAnimationView');
{
 const v=new ctx.ReactionAnimationView();v.source={path:'a'};v.replayToken=1;let starts=0,failures=0;
 v.onStarted=()=>starts++;v.onFailed=()=>failures++;
 // The build callback can be prepared before the attach hook. It must survive attach.
 const builtStart=v.started(),builtFailure=v.failure();v.aboutToAppear();builtStart();builtFailure();
 assert.equal(starts,1);assert.equal(failures,1);
 v.aboutToRecycle();builtStart();builtFailure();assert.equal(starts,1);assert.equal(failures,1);
 const reusedStart=v.started(),reusedFailure=v.failure();v.aboutToReuse();reusedStart();reusedFailure();
 assert.equal(starts,2);assert.equal(failures,2,'new callbacks prepared during reuse survive its attach hook');
 builtStart();builtFailure();assert.equal(starts,2);assert.equal(failures,2,'old lifecycle callbacks remain retired after reuse');
 v.aboutToDisappear();reusedStart();reusedFailure();assert.equal(starts,2);assert.equal(failures,2);
}
{
 const v=new ctx.ReactionAnimationView(),a={path:'a'},b={path:'b'};let starts=0,failures=0;
 v.onStarted=()=>starts++;v.onFailed=()=>failures++;v.source=a;v.replayToken=1;v.aboutToAppear();
 const current=v.started();current();assert.equal(starts,1);
 const replay=v.started();v.replayToken=2;replay();assert.equal(starts,1);
 const path=v.started();v.source=b;path();assert.equal(starts,1);
 v.source=a;const retired=v.started(),retiredFailure=v.failure();v.aboutToRecycle();retired();retiredFailure();assert.equal(starts,1);assert.equal(failures,0);
 v.aboutToReuse();retired();retiredFailure();assert.equal(starts,1);assert.equal(failures,0,'same source/token after reuse rejects old lifecycle');
 v.started()();v.failure()();assert.equal(starts,2);assert.equal(failures,1);
 const source=fs.readFileSync(root+'pages/chat/ReactionAnimationView.ets','utf8');
 assert.equal((source.match(/onWorking: this\.started\(\)/g)||[]).length,2,'both TGS and Alpha notify parent only after first draw');
}
console.log('PASS: default-compatible TGS first-frame callback, failed draws, replay/path reset, cache hit, stale async render/failure, recycle and same-source lifecycle guards; both overlay formats forward readiness.');
