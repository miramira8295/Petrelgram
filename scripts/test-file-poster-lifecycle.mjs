import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
const imported=await import(process.env.TYPESCRIPT_MODULE||'typescript'),ts=imported.default||imported;
const compile=s=>ts.transpileModule(s,{compilerOptions:{target:ts.ScriptTarget.ES2020}}).outputText;
const pending=[],calls=[],paths=new Map();let active=0,peak=0;
const context=vm.createContext({fileIo:{accessSync:()=>false,mkdirSync:()=>{}},VIDEO_POSTER_DIR:'posters',posterSignature:(p,s,t)=>`${p}:${s}:${t}`,posterPathFor:(r,s)=>r+'/'+s,logE:()=>{},extractFirstFrame:(path,dest)=>{calls.push(path);active++;peak=Math.max(peak,active);return new Promise(resolve=>pending.push(ok=>{active--;paths.set(path,dest);resolve(ok);}));}});
const source=fs.readFileSync('entry/src/main/ets/util/videoPosterStore.ets','utf8').replace(/^import\s[\s\S]*?;\r?\n/gm,'').replace(/\bexport /g,'');vm.runInContext(compile(source+'\nglobalThis.api={initVideoPosterStore,requestPoster,posterFor,subscribePoster,seedVideoPoster};'),context);const api=context.api;
const flush=async()=>{for(let i=0;i<8;i++)await Promise.resolve();};api.initVideoPosterStore('/cache');const received=[];const off=api.subscribePoster('/video0',x=>received.push(x));
for(let i=0;i<2000;i++){api.requestPoster('/video'+i,12,0);api.requestPoster('/video'+i,12,0);}
assert.equal(calls.length,1);for(let i=0;i<2000;i++){assert.equal(pending.length,1);pending.shift()(true);await flush();}assert.equal(calls.length,2000);assert.equal(new Set(calls).size,2000);assert.equal(peak,1);assert.equal(received.length,1);off();
api.requestPoster('/video0',12,0);assert.equal(calls.length,2000,'cached poster does not extract again');api.requestPoster('/broken',12,0);pending.shift()(false);await flush();api.requestPoster('/broken',12,0);assert.equal(calls.length,2002,'failed extraction can retry');pending.shift()(true);await flush();
// Real extractFirstFrame: resource cleanup also runs when encoding/opening fails.
const raw=fs.readFileSync('entry/src/main/ets/util/livePhotoSave.ets','utf8'),ast=ts.createSourceFile('livePhotoSave.ets',raw,ts.ScriptTarget.Latest,true);const fn=ast.statements.find(n=>ts.isFunctionDeclaration(n)&&n.name?.text==='extractFirstFrame');assert.ok(fn);
for(const stage of ['success','fetch','dest','pack']){
 const events=[];let opens=0;
 const frame={release:async()=>events.push('frame')},packer={packToFile:async()=>{if(stage==='pack')throw Error('encode');},release:async()=>events.push('packer')};
 const generator={fetchFrameByTime:async()=>{if(stage==='fetch')throw Error('decode');return frame;},release:async()=>events.push('generator')};
 const c=vm.createContext({logE:()=>{},fileIo:{OpenMode:{READ_ONLY:1,READ_WRITE:2,CREATE:4,TRUNC:8},open:async()=>{opens++;if(opens===2&&stage==='dest')throw Error('disk');return{fd:opens};},closeSync:f=>events.push('fd'+f.fd)},media:{AVImageQueryOptions:{AV_IMAGE_QUERY_NEXT_SYNC:0},createAVImageGenerator:async()=>generator},image:{createImagePacker:()=>packer}});
 vm.runInContext(compile(fn.getText(ast).replace(/^export /,'')+'\nglobalThis.extract=extractFirstFrame;'),c);assert.equal(await c.extract('/source','/dest'),stage==='success');assert.ok(events.includes('generator'));assert.ok(events.includes('fd1'));assert.equal(events.filter(x=>x==='frame').length,stage==='fetch'?0:1);assert.equal(events.filter(x=>x==='packer').length,['success','pack'].includes(stage)?1:0);assert.equal(events.includes('fd2'),['success','pack'].includes(stage));
}
console.log('PASS: 2000 serial FIFO poster jobs, duplicate/cache/failure retry handling and real native frame/packer/generator/file cleanup on success and failure.');
