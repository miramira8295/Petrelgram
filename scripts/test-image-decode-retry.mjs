// Actual session code with deterministic cache/decoder/clock IO. A supplied
// baseline confirms the formerly terminal blank state after one failed decode.
import fs from 'node:fs';import vm from 'node:vm';import assert from 'node:assert/strict';
const imported=await import(process.env.TYPESCRIPT_MODULE||'typescript');const ts=imported.default||imported;
function rig(sessionFile){
 let nextId=1;const timers=new Map(),requests=[],published=[],warnings=[],cache=new Map();
 const ctx=vm.createContext({vp2pxUI:x=>x,setTimeout:(fn,delay)=>{const id=nextId++;timers.set(id,{fn,delay});return id;},clearTimeout:id=>timers.delete(id),
 cachedPixelMap:r=>cache.get(r.path),loadPixelMapSync:()=>undefined,
 loadPixelMap:r=>new Promise(resolve=>requests.push({r,resolve})),cancelPixelMap(){},
 retainPixelMap:h=>h.refs++,releasePixelMap:h=>h.refs--,pinPixelMap(){},pinPixelMapBounded(){},logW:s=>warnings.push(s)});
 function load(p){const s=fs.readFileSync(p,'utf8').replace(/^import\s[\s\S]*?;\r?\n/gm,'').replace(/\bexport /g,'');vm.runInContext(ts.transpileModule(s,{compilerOptions:{target:ts.ScriptTarget.ES2020}}).outputText,ctx);}
 load('entry/src/main/ets/util/imageSwap.ets');load('entry/src/main/ets/util/cachedImageSpec.ets');load(sessionFile);
 vm.runInContext('globalThis.Session=CachedImageSession;',ctx);
 const owner=new ctx.Session((pixels,ready)=>published.push({pixels,ready}));
 return {owner,timers,requests,published,warnings,cache,fire(){const [id,timer]=timers.entries().next().value;timers.delete(id);timer.fn();return timer.delay;}};
}
const current='entry/src/main/ets/util/CachedImageSession.ets', spec={path:'/a',sourceKey:'f1',boxWidth:80,boxHeight:60};
const flush=async()=>{await Promise.resolve();await Promise.resolve();};
if(process.argv[2]){const old=rig(process.argv[2]);old.owner.activate(spec);old.requests[0].resolve(undefined);await flush();old.owner.update({...spec});assert.equal(old.requests.length,1);assert.equal(old.timers.size,0);assert.equal(old.published.at(-1).pixels,undefined);console.log('REPRODUCED: baseline stays blank after failed decode and unchanged input.');}
let r=rig(current);r.owner.activate(spec);assert.equal(r.timers.size,0,'no retry while decode is pending');
for(let i=0;i<1000;i++)r.owner.update({...spec,backdrop:String(i)});
assert.equal(r.requests.length,1);
r.requests[0].resolve(undefined);await flush();assert.equal(r.timers.size,1);assert.equal(r.fire(),150);
assert.equal(r.requests.length,2);const image={refs:1,pixelMap:{name:'ok'}};r.requests[1].resolve(image);await flush();
assert.equal(r.published.at(-1).pixels,image.pixelMap);assert.equal(r.timers.size,0);r.owner.dispose();assert.equal(image.refs,1);
r=rig(current);r.owner.activate(spec);
for(let i=0;i<3;i++){r.requests[i].resolve(undefined);await flush();if(i<2)assert.equal(r.fire(),[150,600][i]);}
assert.equal(r.requests.length,3);assert.equal(r.timers.size,0);assert.equal(r.warnings.length,1);
for(let i=0;i<1000;i++)r.owner.update({...spec});assert.equal(r.requests.length,3);
for(const phase of ['recycle','dispose']){r=rig(current);r.owner.activate(spec);r.requests[0].resolve(undefined);await flush();const oldTimer=[...r.timers.values()][0].fn;r.owner[phase]();assert.equal(r.timers.size,0);oldTimer();assert.equal(r.requests.length,1);}
r=rig(current);r.owner.activate(spec);r.requests[0].resolve(undefined);await flush();const oldTimer=[...r.timers.values()][0].fn;
r.owner.update({...spec,path:'/b',sourceKey:'f2'});assert.equal(r.timers.size,0);oldTimer();assert.equal(r.requests.length,2);
r.requests[1].resolve({refs:1,pixelMap:{name:'b'}});await flush();assert.equal(r.published.at(-1).pixels.name,'b');
r=rig(current);r.owner.activate(spec);r.owner.recycle();r.requests[0].resolve(undefined);await flush();assert.equal(r.timers.size,0,'late failed decode cannot revive recycled owner');
r=rig(current);r.cache.set('/a',{refs:1,pixelMap:{name:'held'}});r.owner.activate(spec);r.owner.update({...spec,path:'/upgrade'});
assert.equal(r.published.at(-1).pixels.name,'held');r.requests[0].resolve(undefined);await flush();r.fire();assert.equal(r.published.at(-1).pixels.name,'held','failed same-file upgrade retains old bitmap');
r=rig(current);r.owner.activate(spec);r.requests[0].resolve(undefined);await flush();r.cache.set('/a',{refs:1,pixelMap:{name:'shared'}});r.fire();assert.equal(r.requests.length,1,'retry rechecks cache before starting new work');assert.equal(r.published.at(-1).pixels.name,'shared');
console.log('PASS: bounded failure-only retries, 2000 unchanged updates, source changes, cancellation, stale completions, held-image upgrades and shared cache recovery.');
