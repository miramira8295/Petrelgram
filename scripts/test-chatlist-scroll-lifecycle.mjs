// Replay the real compiled method with an unbound Scroller, as observed in
// the 2026-11-12 startup crash. No native UI scheduling is simulated here.
import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
const imported=await import(process.env.TYPESCRIPT_MODULE||'typescript');
const ts=imported.default||imported;
const path='entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/pages/chatlist/ChatListPage.ts';
const source=ts.createSourceFile(path,fs.readFileSync(path,'utf8'),ts.ScriptTarget.Latest,true);
const cls=source.statements.find(n=>ts.isClassDeclaration(n)&&n.name.text==='ChatListPage');
const method=cls.members.find(n=>ts.isMethodDeclaration(n)&&n.name.getText(source)==='syncFolderBarWithActiveList');
assert.ok(method);
const context=vm.createContext({});
vm.runInContext(ts.transpileModule(`class Probe {${method.getText(source)}}; globalThis.Probe=Probe;`,
  {compilerOptions:{target:ts.ScriptTarget.ES2020}}).outputText,context);
const page=new context.Probe(),events=[];
let offset,reads=0;
page.selectedIndex=0;page.tabs=()=>[{key:'main'}];
page.scrollerFor=key=>{assert.equal(key,'main');return {currentOffset:()=>{reads++;return offset;}};};
page.noteFolderBarScroll=(...args)=>events.push(args);
page.syncFolderBarWithActiveList();
assert.equal(events.length,0,'unbound controller must preserve folder-bar state');
assert.equal(reads,1,'one native read, no retry loop');
offset={xOffset:0,yOffset:100};page.syncFolderBarWithActiveList();
assert.deepEqual(events.at(-1),['main',0,false]);
offset={xOffset:0,yOffset:0};page.syncFolderBarWithActiveList();
assert.deepEqual(events.at(-1),['main',0,true]);
offset={xOffset:0,yOffset:-5};page.syncFolderBarWithActiveList();
assert.deepEqual(events.at(-1),['main',0,true]);
offset=undefined;const count=events.length;page.syncFolderBarWithActiveList();
assert.equal(events.length,count,'detaching controller must not invent a top position');
page.selectedIndex=1;const previousReads=reads;page.syncFolderBarWithActiveList();
assert.equal(reads,previousReads,'removed tab must not access a controller');
console.log('PASS: compiled folder-bar sync tolerates unbound/detached/removed tabs; bound positions preserve top detection with one offset read.');
