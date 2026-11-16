// Real compiled getters: removing Computed must preserve dependency reads and
// existing bounded caches, rather than replace them with repeated work.
import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
const ts=(await import(process.env.TYPESCRIPT_MODULE||'typescript')).default;
const root='entry/src/main/ets/';
const compiled='entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/'+root;
const file=compiled+'pages/chat/DrawnMessageRow.ts',text=fs.readFileSync(file,'utf8');
const ast=ts.createSourceFile(file,text,ts.ScriptTarget.Latest,true);
const row=ast.statements.find(n=>ts.isClassDeclaration(n)&&n.name.text==='DrawnMessageRow');
const names=['rowGroup','rowData','footerPaintKey','mediaChatId','mediaSlots','useAlbumCanvas'];
const getters=names.map(name=>row.members.find(n=>ts.isGetAccessor(n)&&n.name.getText(ast)===name).getText(ast));
const ctx=vm.createContext({});
function evaluate(s){vm.runInContext(ts.transpileModule(s.replace(/@Computed\s*/g,''),{compilerOptions:{target:ts.ScriptTarget.ES2020}}).outputText,ctx);}
const slotsSource=fs.readFileSync(root+'util/drawnMediaSlot.ets','utf8').replace(/\bexport /g,'');
evaluate(slotsSource+'\nglobalThis.Slots=DrawnMediaSlots;');
evaluate(`class Projection {${getters.join('\n')}};globalThis.Projection=Projection;`);
const reads=new Set();
const track=(label,obj)=>new Proxy(obj,{get(t,k){reads.add(label+'.'+String(k));return t[k];}});
const probe=new ctx.Projection();
let views='1K';Object.defineProperty(probe,'views',{get(){reads.add('views');return views;}});
Object.assign(probe,{group:track('group',{head:track('head',{date:10,editDate:0})}),data:track('data',{chatId:1}),
 nativeTiles:[{},{},{}],mediaSlotCache:new ctx.Slots(),presentationActive:true,retainedCanvasMode:false,
 albumCanvas:{state:track('canvas',{ready:false})}});
const first=probe.mediaSlots;
for(let i=0;i<1000;i++){assert.equal(probe.footerPaintKey,'1K:10:0');assert.equal(probe.mediaChatId,1);assert.equal(probe.mediaSlots,first);assert.equal(probe.useAlbumCanvas,false);}
for(const key of ['views','group.head','head.date','head.editDate','data.chatId','canvas.ready'])assert.ok(reads.has(key),key);
views='2K';probe.group.head.editDate=20;assert.equal(probe.footerPaintKey,'2K:10:20');
probe.data={chatId:2};assert.equal(probe.mediaChatId,2);
probe.nativeTiles=[{}];assert.equal(probe.mediaSlots.length,1);assert.equal(probe.mediaSlots[0],first[0]);
probe.nativeTiles=Array(9).fill({});assert.equal(probe.mediaSlots.length,9);
probe.albumCanvas.state.ready=true;assert.equal(probe.useAlbumCanvas,true);
probe.presentationActive=false;assert.equal(probe.useAlbumCanvas,false);
probe.retainedCanvasMode=true;probe.albumCanvas.state.ready=false;assert.equal(probe.useAlbumCanvas,true);
const reset=row.members.find(n=>n.name?.getText(ast)==='resetStateVarsOnReuse').getText(ast);
for(const name of ['footerPaintKey','mediaChatId'])assert.ok(!reset.includes(`resetComputed("${name}")`));
for(const name of ['plan','nativeTiles','mediaFrames','deleteNodeKey','deleteCaptureSupported','roleEnvironment','albumCanvasEnabled','mediaSlots','useAlbumCanvas'])assert.ok(reset.includes(`resetComputed("${name}")`));
assert.equal((reset.match(/this.resetComputed\(/g)||[]).length,13);
const video=fs.readFileSync(compiled+'pages/chat/DrawnAlbumVideo.ts','utf8');
assert.ok(video.includes('this.resetComputed("observedCell")'));
assert.ok(!video.includes('this.resetComputed("meta")'));
console.log('PASS: compiled row preserves nine visual boundaries plus three publication projections, video 2→1; 1000 getter reads preserve cache identity and live footer/chat/canvas/shrink state; nullable monitor anchor retained.');
