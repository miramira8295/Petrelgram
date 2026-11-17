import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
const ts=(await import(process.env.TYPESCRIPT_MODULE || 'typescript')).default;
const tasks=[],timers=new Map(),events=[],warnings=[];
let timerId=0;
const ctx=vm.createContext({setTimeout:fn=>{timers.set(++timerId,fn);return timerId;},clearTimeout:id=>timers.delete(id),logW:s=>warnings.push(s)});
for(const [path,name] of [['util/albumCanvasTransition','withAlbumCanvasAnchor'],['util/viewerUnderlay','ViewerUnderlay'],['pages/chat/DrawnMediaFrames','drawnAlbumTransitionFrame'],['pages/chat/DrawnAlbumTransition','DrawnAlbumTransition']]){
 const source=fs.readFileSync(`entry/src/main/ets/${path}.ets`,'utf8').replace(/^import .*;$/mg,'').replace(/\bexport /g,'');
 vm.runInContext(ts.transpileModule(source+`\nglobalThis.${name}=${name};`,{compilerOptions:{target:ts.ScriptTarget.ES2020}}).outputText,ctx);
}
vm.runInContext('globalThis.take=takeAlbumCanvasAnchor;globalThis.fade=albumCanvasTransitionFor;',ctx);
const anchor=new ctx.DrawnAlbumTransition(i=>events.push(i),fn=>tasks.push(fn));
const underlay=new ctx.ViewerUnderlay(()=>{});
let opens=0;
const open=()=>{opens++;assert.equal(ctx.fade(42),false);underlay.holdSource(ctx.take(42));};
anchor.begin(2,42,()=>true,open);assert.equal(events.at(-1),2);assert.equal(opens,0);
anchor.ready();anchor.ready();assert.equal(tasks.length,1);tasks.shift()();
assert.equal(opens,1);assert.equal(timers.size,0);assert.equal(events.at(-1),2);
const session=underlay.mount();underlay.unmount(session+1);assert.equal(events.at(-1),2);
underlay.unmount(session);assert.equal(events.at(-1),-1);
// Old frame tasks and viewer releases cannot remove a new owner's source.
anchor.begin(0,42,()=>true,open);anchor.ready();const stale=tasks.shift();anchor.cancel();
anchor.begin(1,42,()=>true,open);stale();assert.equal(opens,1);assert.equal(events.at(-1),1);
anchor.ready();tasks.shift()();const release=underlay.sourceRelease;
anchor.begin(3,42,()=>true,open);release();assert.equal(events.at(-1),3);
anchor.cancel();
// Layout watchdog opens once via the established fade path; no frozen taps.
anchor.begin(0,42,()=>true,()=>{opens++;assert.equal(ctx.fade(42),true);});
[...timers.values()][0]();assert.equal(events.at(-1),-1);assert.equal(timers.size,0);
anchor.ready();assert.equal(tasks.length,0);
// Reuse/hidden source invalidation must cancel, never open a different message.
const before=opens;
anchor.begin(0,42,()=>false,()=>opens++);anchor.ready();tasks.shift()();assert.equal(opens,before);assert.equal(events.at(-1),-1);
// Rejected viewer action releases a measured anchor, nested scope cannot leak.
anchor.begin(0,42,()=>true,()=>{});anchor.ready();tasks.shift()();assert.equal(events.at(-1),-1);
anchor.begin(0,42,()=>true,()=>{throw Error('rejected');});anchor.ready();tasks.shift()();assert.equal(warnings.length,1);assert.equal(events.at(-1),-1);
for(let i=0;i<1000;i++){anchor.begin(i%10,42,()=>true,open);anchor.cancel();}
assert.equal(timers.size,0);assert.equal(tasks.length,0);
console.log('PASS: one measured source, viewer release, stale generation, invalid/rejected/throwing open, watchdog fallback, 1000 cancellations with no retained timers.');
// Replay the actual compiled row's bridge, not a mirrored implementation.
const compiled='entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/pages/chat/DrawnMessageRow.ts';
const rowFile=ts.createSourceFile(compiled,fs.readFileSync(compiled,'utf8'),ts.ScriptTarget.Latest,true);
const rowClass=rowFile.statements.find(n=>ts.isClassDeclaration(n)&&n.name.text==='DrawnMessageRow');
const method=rowClass.members.find(n=>ts.isMethodDeclaration(n)&&n.name.getText(rowFile)==='openCanvasMedia');
vm.runInContext(ts.transpileModule(`class RowProbe {${method.getText(rowFile)}};globalThis.RowProbe=RowProbe;`,{compilerOptions:{target:ts.ScriptTarget.ES2020}}).outputText,ctx);
ctx.cornerPx=v=>Number(v)||0;
ctx.OneShotFrameCallback=class{constructor(task){this.onFrame=task;}};
const row=new ctx.RowProbe(),frames=[],taps=[];
Object.assign(row,{canvasTransition:null,canvasTransitionIndex:-1,active:true,presentationReady:()=>true,
 rowData:{chatId:7},rowGroup:{head:{rowId:22}},albumCanvas:{state:{ready:true}},
 nativeTiles:[{x:0,y:0,width:100,height:200,cell:{idx:0,messageId:42}}],
 mediaFrames:[{width:100,height:200,position:{x:0,y:0},backdrop:'#ddd',radius:4,transition:'media_7_42',messageId:42,chatId:7}],
 gridRadii:()=>({topLeft:13,topRight:13,bottomLeft:13,bottomRight:13}),
 rowContext:()=>({postFrameCallback:f=>frames.push(f)}),actions:{onMediaTap:(...args)=>{taps.push(args);underlay.holdSource(ctx.take(42));}}});
row.openCanvasMedia(row.nativeTiles[0],{windowX:25,windowY:90});
assert.equal(row.canvasTransitionIndex,0);assert.equal(taps.length,0);
row.canvasTransition.ready();frames.shift().onFrame();
assert.deepEqual(taps,[[42,25,90]]);underlay.holdSource(null);assert.equal(row.canvasTransitionIndex,-1);
row.openCanvasMedia(row.nativeTiles[0],{windowX:25,windowY:90});row.canvasTransition.ready();
row.rowGroup={head:{rowId:23}};frames.shift().onFrame();assert.equal(taps.length,1);
assert.equal(row.canvasTransitionIndex,-1);assert.equal(timers.size,0);
console.log('PASS: compiled row uses selected source index and event coordinates; reuse cancels the pending open.');

const effective=ctx.drawnAlbumTransitionFrame(row.mediaFrames[0],{width:100,height:200,edgeMask:11,corners:{topLeft:0,topRight:4,bottomLeft:0,bottomRight:4}},row.gridRadii());
assert.equal(JSON.stringify(effective.radius),JSON.stringify({topLeft:13,topRight:4,bottomLeft:13,bottomRight:4}));
assert.equal(effective.transition,'media_7_42');
console.log('PASS: transient source preserves parent outer contour and internal corners without new image decoding.');
