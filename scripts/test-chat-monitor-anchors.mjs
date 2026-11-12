// Check the actual compiled Computed accessors, including dependency reads.
// Native ArkUI scheduling is outside this host test.
import fs from 'node:fs';import vm from 'node:vm';import assert from 'node:assert/strict';
const imported=await import(process.env.TYPESCRIPT_MODULE||'typescript');const ts=imported.default||imported;
const base='entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/pages/';
const cases=[['chat/LightweightPlainTextBubble.ts','LightweightPlainTextBubble','drawnEnvironmentKey'],
 ['chat/SenderAnimatedLayer.ts','SenderAnimatedLayer','playbackEnvironmentKey'],
 ['chat/TgsStickerView.ts','TgsStickerView','playbackEnvironmentKey'],
 ['chat/TgsNativeStickerView.ts','TgsNativeStickerView','playbackEnvironmentKey'],
 ['common/AlphaWebmStickerView.ts','AlphaWebmStickerView','playbackEnvironmentKey'],
 ['common/AvatarFrameView.ts','AvatarFrameView','playbackEnvironmentKey']];
let combinations=0;
for(const [file,type,key] of cases){
 const source=fs.readFileSync(base+file,'utf8'),sf=ts.createSourceFile(file,source,ts.ScriptTarget.Latest,true);
 const cls=sf.statements.find(n=>ts.isClassDeclaration(n)&&n.name.text===type);
 const getter=cls.members.find(n=>ts.isGetAccessor(n)&&n.name.getText(sf)===key);
 assert.ok(getter,`${file} missing ${key}`);
 const body=getter.getText(sf).replace(/@Computed\s*/g,'');
 const fields=[...new Set([...body.matchAll(/this\.env\.(\w+)/g)].map(m=>m[1]))];
 const ctx=vm.createContext({textMeasureEnvironment:{epoch:0}});
 vm.runInContext(ts.transpileModule(`class Probe {${body}}; globalThis.Probe=Probe;`,{compilerOptions:{target:ts.ScriptTarget.ES2020}}).outputText,ctx);
 const view=new ctx.Probe(),outputs=new Set();
 for(let mask=0;mask<(1<<fields.length);mask++){
   const seen=new Set();view.env=new Proxy(Object.fromEntries(fields.map((f,i)=>[f,f==='langEpoch'?((mask>>i)&1):!!((mask>>i)&1)])),{get(o,k){seen.add(k);return o[k];}});
   const output=view[key];assert.equal(seen.size,fields.length,`${file}: all input dependencies must be read`);
   assert.equal(outputs.has(output),false,`${file}: distinct policies must not collapse to one key`);outputs.add(output);combinations++;
 }
 if(key==='drawnEnvironmentKey'){const before=view[key];ctx.textMeasureEnvironment.epoch++;assert.notEqual(view[key],before);}
}
console.log(`PASS: 6 compiled Computed monitor anchors, ${combinations} policy combinations, no short-circuited dependencies, text-environment invalidation.`);
