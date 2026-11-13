// Verify production attribute snapshots, not device timing. The native-diff
// model below checks expected bridge work; real ArkUI scheduling needs Trace.
import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
const ts=(await import(process.env.TYPESCRIPT_MODULE||'typescript')).default;
const root='entry/src/main/ets/';
const ctx=vm.createContext({HitTestMode:{None:0}});
const source=fs.readFileSync(root+'pages/chat/DrawnNativeAttributes.ets','utf8').replace(/^import\s[^;]+;\n/gm,'').replace(/\bexport /g,'');
vm.runInContext(ts.transpileModule(source+'\nglobalThis.pool=DrawnMediaAnchorPool;globalThis.canvas=DrawnCanvasAttributes;', {compilerOptions:{target:ts.ScriptTarget.ES2020}}).outputText,ctx);
function snapshot(modifier){
 const attrs={};let node;node=new Proxy({}, {get:(_t,k)=>(...args)=>{attrs[k]=JSON.parse(JSON.stringify(args));return node;}});
 modifier.applyNormalAttribute(node);return attrs;
}
// Use meaningful fields for size: the native SizeOptions adapter ignores the
// message/transition fields also present on the immutable frame object.
function nativeState(modifier){const a=snapshot(modifier);a.size=[{width:a.size[0].width,height:a.size[0].height}];return a;}
function changes(a,b){return Object.keys(b).filter(k=>JSON.stringify(a[k])!==JSON.stringify(b[k]));}
const pool=new ctx.pool(),frames=Array.from({length:9},(_,i)=>({width:100+i,height:80+i,position:{x:i*20,y:i*15},backdrop:'#D7DCE2',radius:6,transition:`media_1_${i+1}`,messageId:i+1,chatId:1}));
const first=frames.map((f,i)=>pool.bind(i,f)),a=first.map(nativeState);
for(let n=0;n<1000;n++){
 for(let i=0;i<9;i++){
  assert.equal(pool.bind(i,frames[i]),first[i]);
  assert.deepEqual(changes(a[i],nativeState(first[i])),[],'steady full snapshot has no native attribute differences');
 }
}
for(let i=0;i<9;i++){
 const f={...frames[i],messageId:100+i,transition:`media_1_${100+i}`};
 assert.deepEqual(changes(a[i],nativeState(pool.bind(i,f))),['geometryTransition'],'new message with same geometry only changes its source ID');
 const resized={...f,width:150,height:160,position:{x:20,y:30}};
 assert.deepEqual(changes(nativeState(pool.bind(i,f)),nativeState(pool.bind(i,resized))),['size','position']);
 const video={...resized,transition:'',backdrop:'#AEB6C0'};
 assert.deepEqual(changes(nativeState(pool.bind(i,resized)),nativeState(pool.bind(i,video))),['backgroundColor','geometryTransition']);
 const empty=nativeState(pool.bind(i,undefined));
 assert.deepEqual(empty.size,[{width:0,height:0}]);assert.deepEqual(empty.geometryTransition,['']);
 assert.equal(Object.keys(empty).length,7,'stale removed slot still submits complete reset attributes');
 assert.deepEqual(nativeState(pool.bind(i,frames[i])),a[i],'shrink/fallback/A-B-A restores all attributes');
}
assert.equal(pool.anchors.length,9,'1000 reuses retain nine physical modifiers, not message history');
// New node receives full state even when the reused modifier/frame is identical.
assert.equal(Object.keys(nativeState(pool.bind(0,frames[0]))).length,7);
const c=new ctx.canvas();let state=nativeState(c.bind(200,300,1,50,1,false));
for(let i=0;i<1000;i++)assert.deepEqual(changes(state,nativeState(c.bind(200,300,1,50,1,false))),[]);
const focused=nativeState(c.bind(200,300,1.02,50,1.1,false));assert.deepEqual(changes(state,focused),['scale','brightness']);
const outgoing=nativeState(c.bind(200,300,1.02,'100%',1.1,true));assert.deepEqual(changes(focused,outgoing),['scale','draggable']);
assert.deepEqual(nativeState(c.bind(200,300,1,50,1,false)),state);
const compiled=fs.readFileSync('entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/'+root+'pages/chat/DrawnMessageRow.ts','utf8');
const tile=compiled.slice(compiled.indexOf('    mediaTile('),compiled.indexOf('    canvasContent('));
assert.match(tile,/Stack.attributeModifier(?:\.bind\(this\))?\(this.nativeAnchors.bind\(slot.index, this.mediaFrames\[slot.index\]\)\)/);
assert.match(tile,/Stack.drawModifier\(this.media.slots\[slot.index\]\?\.receiver\)/);
assert.doesNotMatch(tile,/Stack\.(size|position|borderRadius|clip|geometryTransition|backgroundColor|hitTestBehavior)\(/,'anchor properties have one owner');
assert.doesNotMatch(source,/\.drawModifier\(|\.bindContextMenu\(/,'unsupported builder/drawing APIs remain in the DSL');
assert.match(compiled,/Stack.bindContextMenu\(this.menuShown/,'context menu stays on original canvas host');
console.log('PASS: 9000 warm anchors have equal complete snapshots; same geometry/new message changes only transition; resize/video/fallback/recreated node/A-B-A/focus/drag preserved; nine-slot bound and compiled attribute ownership verified. Native diff counts are modeled, not device timing.');
