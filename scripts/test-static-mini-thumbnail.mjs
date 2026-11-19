import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
const ts=(await import(process.env.TYPESCRIPT_MODULE||'typescript')).default;
const compile=s=>ts.transpileModule(s,{compilerOptions:{target:ts.ScriptTarget.ES2020}}).outputText;
const clean=s=>s.replace(/^import\s[\s\S]*?;\r?\n/gm,'').replace(/\bexport /g,'');
const ctx=vm.createContext({taskpool:{execute(){}},blurMiniThumb(){},logW(){}});
vm.runInContext(compile(clean(fs.readFileSync('entry/src/main/ets/util/miniThumbBlurCache.ets','utf8'))+'\nglobalThis.Cache=MiniThumbBlurCache;'),ctx);
const flush=async()=>{for(let i=0;i<6;i++)await Promise.resolve();};
const src=i=>'data:image/jpeg;base64,'+i;
let renders=0;const pending=[];
const cache=new ctx.Cache((...args)=>{renders++;return new Promise((resolve,reject)=>pending.push({args,resolve,reject}));});
const got=[];const offA=cache.request(src('A'),200,100,false,x=>got.push('A'+x));
cache.request(src('A'),200,100,false,x=>got.push('B'+x));
assert.equal(renders,1,'same source/geometry shares a single task');
for(let i=0;i<10000;i++)cache.request(src(i),200,100,false,()=>{})();
assert.equal(cache.jobs.size,1);assert.equal(cache.queue.size,0,'cancelled queued entries do not accumulate');
offA();pending.shift().resolve('blurred');await flush();assert.deepEqual(got,['Bblurred']);
for(let i=0;i<1000;i++)cache.request(src('A'),200,100,false,()=>{});
assert.equal(renders,1,'warm cache never reprocesses');
cache.request(src('A'),100,100,false,()=>{});cache.request(src('A'),100,100,true,()=>{});
assert.equal(renders,2);pending.shift().resolve('resized');await flush();assert.equal(renders,3);
pending.shift().reject(Error('decode'));await flush();cache.request(src('A'),100,100,true,()=>{});assert.equal(renders,3,'failed inputs do not loop');
for(let i=0;i<200;i++)cache.request(src('bounded'+i),40,40,false,()=>{});
assert.equal(cache.jobs.size,32);assert.equal(pending.length,1,'one worker even under overload');
while(pending.length){pending.shift().resolve('x');await flush();}
for(let i=0;i<1000;i++){cache.request(src('lru'+i),40,40,false,()=>{});pending.shift().resolve('x'.repeat(10000));await flush();}
assert.ok(cache.cache.size<=128);assert.ok(cache.bytes<=2*1024*1024);assert.equal(cache.jobs.size,0);
// Cancellation during notification must not dispatch the detached next listener.
let offSecond;const notified=[];
cache.request(src('cancel-on-delivery'),40,40,false,()=>{notified.push(1);offSecond();});
offSecond=cache.request(src('cancel-on-delivery'),40,40,false,()=>notified.push(2));
pending.shift().resolve('x');await flush();assert.deepEqual(notified,[1]);

// Production adapter submits a low-priority TaskPool task, not UI-thread filtering.
const submitted=[];ctx.taskpool.Task=class{constructor(...args){this.args=args;}};ctx.taskpool.Priority={LOW:2};
ctx.taskpool.execute=async(task,priority)=>{submitted.push({task,priority});return 'shared';};
vm.runInContext('globalThis.shared=miniThumbBlurCache;',ctx);
let delivered='';ctx.shared.request(src('shared'),400,200,false,x=>delivered=x);await flush();
assert.equal(delivered,'shared');assert.equal(submitted[0].priority,2);assert.deepEqual(submitted[0].task.args.slice(1),[src('shared'),400,200,false]);

// Native worker owns resources, including failure after a PixelMap has been created.
const worker=clean(fs.readFileSync('entry/src/main/ets/util/miniThumbBlurTask.ets','utf8')).replace('@Concurrent','');
for(const stage of ['ok','filter','pack','oversized']){
 const releases=[],radii=[];let decodes=0;
 const original={release:()=>releases.push('original')},filtered={release:()=>releases.push('filtered')};
 const c=vm.createContext({MINI_PLACEHOLDER_BLUR:12,util:{Base64Helper:class{decodeSync(){return new Uint8Array(4);}encodeToStringSync(){return 'encoded';}}},
  image:{PixelMapFormat:{RGBA_8888:3},createImageSource:()=>({getImageInfo:async()=>({size:{width:stage==='oversized'?257:40,height:20}}),createPixelMap:async()=>{decodes++;return original;},release:()=>releases.push('source')}),createImagePacker:()=>({packing:async()=>{if(stage==='pack')throw Error('pack');return new ArrayBuffer(4);},release:()=>releases.push('packer')})},
  effectKit:{createEffect:()=>({blur:r=>{radii.push(r);return{getEffectPixelMap:async()=>{if(stage==='filter')throw Error('filter');return filtered;}};}})}});
 vm.runInContext(compile(worker+'\nglobalThis.run=blurMiniThumb;'),c);
 if(['filter','pack'].includes(stage))await assert.rejects(c.run(src('x'),200,100,false));
 else assert.equal(await c.run(src('x'),200,100,false),stage==='ok'?'data:image/png;base64,encoded':'');
 assert.ok(releases.includes('source'));
 assert.equal(releases.includes('original'),stage!=='oversized');
 assert.equal(releases.includes('filtered'),stage==='ok'||stage==='pack');
 assert.equal(releases.includes('packer'),stage==='ok'||stage==='pack');
 if(stage==='ok')assert.equal(radii[0],2.4,'12 physical pixels at 5x maps to 2.4 source pixels');
 if(stage==='oversized')assert.equal(decodes,0);
}

// Replay actual compiler methods, including the pre-Monitor render window.
const path='entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/pages/common/StaticMiniThumbnail.ts';
const raw=fs.readFileSync(path,'utf8'),ast=ts.createSourceFile(path,raw,ts.ScriptTarget.Latest,true);
const cls=ast.statements.find(n=>ts.isClassDeclaration(n)&&n.name?.text==='StaticMiniThumbnail');
const names=['detach','bind','changed','aboutToAppear','aboutToReuse','aboutToRecycle','aboutToDisappear','shownSource'];
const methods=cls.members.filter(n=>names.includes(n.name?.getText(ast))).map(n=>n.getText(ast).replace(/@Monitor\([^)]*\)\s*/g,'')).join('\n');
const callbacks=[];let cancels=0;
const c=vm.createContext({ImageFit:{Cover:0,Contain:1},miniThumbBlurCache:{request:(s,w,h,fit,ready)=>{callbacks.push(ready);return()=>cancels++;}}});
vm.runInContext(compile(`class Mini {${methods}} globalThis.Mini=Mini;`),c);
const mini=Object.assign(new c.Mini(),{source:'A',boxW:200,boxH:100,imageFit:0,result:null,generation:0,active:false,cancel:null,getUIContext:()=>({vp2px:n=>n*2})});
mini.aboutToAppear();callbacks[0]('blurA');assert.equal(mini.shownSource(),'blurA');
mini.source='B';assert.equal(mini.shownSource(),'B','old pixels hidden even before monitor');mini.changed();callbacks[0]('lateA');assert.equal(mini.shownSource(),'B');
mini.source='A';mini.changed();callbacks[0]('ABA-old');assert.equal(mini.shownSource(),'blurA');callbacks[2]('newA');assert.equal(mini.shownSource(),'newA');
mini.boxW=100;assert.equal(mini.shownSource(),'A');mini.changed();mini.aboutToRecycle();callbacks.at(-1)('late-sized');assert.equal(mini.result,null);
const before=callbacks.length;mini.changed();assert.equal(callbacks.length,before,'detached parameters never enqueue');mini.aboutToReuse();callbacks.at(-1)('live');assert.equal(mini.shownSource(),'live');mini.aboutToDisappear();assert.ok(cancels>=5);
console.log('PASS: static mini worker radius/resource cleanup, 10000 O(1) queue cancellations, single-flight/serial/32 jobs/128 entries/2MiB bounds, failures/LRU; compiled pre-Monitor and A/B/A/detach guards.');
