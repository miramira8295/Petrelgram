import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
const imported=await import(process.env.TYPESCRIPT_MODULE||'typescript'),ts=imported.default||imported;
const rows=[],clicks=[],labels=[];
class View {
  observeComponentCreation2(fn){fn(1,true);}
  forEachUpdateFunction(_id,items,fn){items.forEach(fn);}
}
const ctx=vm.createContext({Context:{animation(){}},ViewPU:View,$r:key=>key,COLOR_TEXT_PRIMARY:'black',BOTTOM_DRAWER_HEIGHT:260,
  BarState:{Off:0},TextOverflow:{Ellipsis:0},TextAlign:{Center:0},FlexAlign:{Center:0},Curve:{EaseOut:0},TouchType:{Down:0,Up:1,Cancel:2}});
for(const name of ['Grid','GridItem','ForEach','Column','Stack','SymbolGlyph','Text'])ctx[name]=new Proxy({}, {
  get:(_t,key)=>(...args)=>{if(name==='Grid'&&key==='rowsTemplate')rows.push(args[0]);
    if(name==='Text'&&key==='create')labels.push(args[0]);if(key==='onClick')clicks.push(args[0]);}
});
function load(path,name){const src=fs.readFileSync(path,'utf8').replace(/^import\s[\s\S]*?;\r?\n/gm,'').replace(/\bexport /g,'');
  vm.runInContext(ts.transpileModule(src+`\nglobalThis.${name}=${name};`,{compilerOptions:{target:ts.ScriptTarget.ES2020}}).outputText,ctx);}
load('entry/src/main/ets/util/attachActions.ets','attachActions');
load('entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/pages/chat/AttachPanel.ts','AttachPanel');
for(const args of [[false,false,false],[true,false,false],[false,true,false],[false,false,true]]) {
  const panel=Object.create(ctx.AttachPanel.prototype),actions=ctx.attachActions(...args),picked=[];
  for(const [key,value] of Object.entries({actions,disabledKeys:[],pressedKey:'',onPick:key=>picked.push(key),effectDuration:x=>x}))
    Object.defineProperty(panel,key,{value,writable:true});
  rows.length=clicks.length=labels.length=0;panel.initialRender();
  const capacity=rows[0].split(' ').length*4;
  assert.ok(capacity>=actions.length,'every action fits the actual Grid template');
  assert.equal(labels.length,actions.length);assert.equal(clicks.length,actions.length);
  clicks.forEach(fn=>fn());assert.deepEqual(picked,Array.from(actions,a=>a.key),'each cell dispatches its own action');
  if(args[0]||args[2]) {
    assert.ok(labels.includes('app.string.poll_word'));
    assert.ok(labels.includes('app.string.checklist_title'));
  }
}
console.log('PASS: compiled attachment grid has room and distinct clickable cells for poll/checklist, private/group/channel/Saved or bot contexts.');
