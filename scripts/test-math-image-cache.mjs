import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
const imported=await import(process.env.TYPESCRIPT_MODULE||'typescript'),ts=imported.default||imported;
let requests=[],releases=0,pixels=0;
const ctx=vm.createContext({AppStorage:{get:()=>false},KEY_APP_DARK:'dark',logW:()=>{},
 LatexMathColorFormat:{COLOR_FORMAT_BGRA_8888:1},TeXResultCode:{Success:0},
 latexStringToImageWithError:(expression,size,color)=>new Promise(resolve=>requests.push({expression,size,color,resolve})),
 image:{createImageSource:()=>({getImageInfo:async()=>({size:{width:120,height:40}}),
 createPixelMap:async()=>({id:++pixels}),release:()=>releases++})}});
const code=fs.readFileSync('entry/src/main/ets/util/mathImageCache.ets','utf8').replace(/^import\s[\s\S]*?;\r?\n/gm,'').replace(/\bexport /g,'');
vm.runInContext(ts.transpileModule(code+'\nglobalThis.api={ensureMathImage,mathImageFor,mathMetricsFor,mathKeyOf,resetMathImageCacheForTest,stats:()=>({jobs:jobs.size,running,queue:queue.length,failed:failed.size,cache:cache.size,metrics:metrics.size})};',{compilerOptions:{target:ts.ScriptTarget.ES2020}}).outputText,ctx);
const a=ctx.api,flush=async()=>{for(let i=0;i<12;i++)await Promise.resolve();};
let first=0,second=0;
const off=a.ensureMathImage('x',32,1,()=>first++);a.ensureMathImage('x',32,1,()=>second++);
assert.equal(requests.length,1);off();requests[0].resolve({resultCode:0,imageBytes:[]});await flush();
assert.equal(first,0);assert.equal(second,1);assert.equal(releases,1);assert.equal(pixels,1);
assert.equal(a.mathImageFor(a.mathKeyOf('x',32,1)).width,120);assert.equal(a.mathMetricsFor(a.mathKeyOf('x',32,1)).height,40);
a.ensureMathImage('x',32,1,()=>{throw Error('cache hit must not notify')});assert.equal(requests.length,1);
// Queue cancellation followed by same-key re-enqueue must not delete the new job.
a.resetMathImageCacheForTest();requests=[];
a.ensureMathImage('a',32,1,()=>{});a.ensureMathImage('b',32,1,()=>{});
const cancel=a.ensureMathImage('c',32,1,()=>{throw Error('cancelled')});cancel();let c=0;
a.ensureMathImage('c',32,1,()=>c++);assert.equal(requests.length,2);
requests[0].resolve({resultCode:0,imageBytes:[]});await flush();assert.equal(requests.length,3);assert.equal(requests[2].expression,'c');
requests[2].resolve({resultCode:0,imageBytes:[]});requests[1].resolve({resultCode:0,imageBytes:[]});await flush();assert.equal(c,1);
// A bad listener cannot starve siblings or leave the scheduler running forever.
a.ensureMathImage('d',32,1,()=>{throw Error('consumer')});let sibling=0;a.ensureMathImage('d',32,1,()=>sibling++);
requests.at(-1).resolve({resultCode:0,imageBytes:[]});await flush();assert.equal(sibling,1);assert.equal(a.stats().running,0);
// Cancelled queued owners stay bounded even while two native requests are blocked.
a.ensureMathImage('hold1',32,1,()=>{});a.ensureMathImage('hold2',32,1,()=>{});
for(let i=0;i<5000;i++)a.ensureMathImage('churn'+i,32,1,()=>{})();
assert.ok(a.stats().queue<=512);assert.equal(a.stats().jobs,2);
// Independent colors/fonts are separate cache keys; invalid sizes never reach native.
const count=requests.length;a.ensureMathImage('x',Infinity,1,()=>{});a.ensureMathImage('x',0,1,()=>{});assert.equal(requests.length,count);
console.log('PASS: formula single-flight multicast, detach/rebind safety, bounded cancellation queue, concurrency, resource cleanup and listener isolation.');
