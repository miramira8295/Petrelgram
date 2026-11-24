// PR51: replay production navigation guards, compiled button updates and media geometry.
import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
import {ctx,load,root,compiled,ui,data,style,group} from './test-drawn-text-row.mjs';
const ts=(await import(process.env.TYPESCRIPT_MODULE||'typescript')).default;
function method(source,name){
 const match=new RegExp(`^\\s*(?:private )?${name}\\(`,'m').exec(source);assert.ok(match,name);
 const ast=ts.createSourceFile('test.ts','class P {\n'+source.slice(match.index),ts.ScriptTarget.Latest,true);
 return ast.statements[0].members[0].getText(ast);
}
const nav=vm.createContext({});
function run(source){vm.runInContext(ts.transpileModule(source,{compilerOptions:{target:ts.ScriptTarget.ES2020}}).outputText,nav);}
run(fs.readFileSync(root+'util/searchPaging.ets','utf8').replace(/\bexport /g,''));
const session=fs.readFileSync(root+'pages/chat/SearchSession.ets','utf8');
run(`class Session {${['canNavigate','canLoadMoreResults','older','newer','applySearchStep'].map(n=>method(session,n)).join('\n')}}globalThis.Session=Session;`);
const s=new nav.Session();let jumps=[],fetches=[];
Object.assign(s,{disposed:false,mode:true,loading:false,results:[30,20],total:3,idx:0,resultsExhausted:false,
 jumpToResult:i=>{s.idx=i;jumps.push(i);},run:(id,i)=>{s.loading=true;fetches.push([id,i]);}});
assert.equal(s.canNavigate(false),false);assert.equal(s.canNavigate(true),true);
s.newer();assert.equal(jumps.length,0);s.older();assert.equal(s.idx,1);s.older();assert.deepEqual(fetches,[[20,2]]);
for(let i=0;i<1000;i++){s.older();s.newer();}assert.equal(fetches.length,1);assert.equal(jumps.length,1);
s.loading=false;s.resultsExhausted=true;assert.equal(s.canNavigate(true),false);s.older();assert.equal(fetches.length,1);
s.newer();assert.equal(s.idx,0);assert.equal(s.canNavigate(true),true);s.older();assert.equal(s.idx,1);
for(const field of ['disposed','mode','loading']){
 const value=s[field];s[field]=field!=='mode';assert.equal(s.canNavigate(true),false);assert.equal(s.canNavigate(false),false);s[field]=value;
}
s.results=[];assert.equal(s.canNavigate(false),false);assert.equal(s.canNavigate(true),false);

// Invoke the emitted native Button property callback again without rebuilding its parent.
const callbacks=[];let enabled,clicked,surfaces=0;
const noop=new Proxy({},{get:()=>()=>{}});
Object.assign(nav,{Stack:noop,If:noop,SymbolGlyph:noop,ButtonType:{Circle:1},Color:{Transparent:0},
 COLOR_TEXT_PRIMARY:'text',BOTTOM_PILL_HEIGHT:48,bottomPillRadius:()=>24,
 SystemGlassSurface:class{constructor(_owner,p){surfaces++;assert.equal(p.effectsEnabled,false);}},ViewV2:{create:()=>{}},
 Button:new Proxy({enabled:v=>{enabled=v;},onClick:f=>{clicked=f;}},{get:(t,k)=>t[k]||(()=>{})})});
run(`class Bar {${method(fs.readFileSync(compiled+'pages/chat/ChatSearchBars.ts','utf8'),'stepButton')}}globalThis.Bar=Bar;`);
const bar=new nav.Bar();let olderCalls=0,newerCalls=0;
Object.assign(bar,{search:s,onOlder:()=>{olderCalls++;s.older();},onNewer:()=>{newerCalls++;s.newer();},
 observeComponentCreation2:(fn,type)=>{callbacks.push([fn,type]);fn(0,true);},ifElseBranchUpdateFunction:(_i,fn)=>fn(),updateStateVarsOfChildByElmtId:()=>{}});
s.results=[30,20];s.idx=0;s.total=2;s.resultsExhausted=false;
bar.stepButton({},true,false);assert.equal(enabled,true);clicked();assert.equal(olderCalls,1);
const buttonUpdate=callbacks.find(([,type])=>type===nav.Button)[0];buttonUpdate(0,false);assert.equal(enabled,false);clicked();assert.equal(olderCalls,1);
s.idx=0;buttonUpdate(0,false);assert.equal(enabled,true);s.loading=true;clicked();assert.equal(olderCalls,1,'stale enabled visual must not issue a request');
assert.equal(surfaces,1,'navigation updates keep surface mounted');s.loading=false;
bar.stepButton({},false,false);assert.equal(enabled,false);s.idx=1;clicked();assert.equal(newerCalls,1);

for(const f of ['DrawnAlbumGridLayout','DrawnSingleMediaGeometry','DrawnMediaLayout','DrawnSingleMediaLayout'])load(root+'pages/chat/'+f+'.ets',f==='DrawnSingleMediaLayout'?['DrawnSingleMediaLayouts']:[]);
const realWidth=vm.runInContext('mediaThumbWidth',ctx);let cases=0;
for(const device of ['phone','tablet','2in1']){
 ctx.mediaThumbWidth=(w,g)=>realWidth(w,g,device);
 for(const w of [180,240,390,800])for(const isGroup of [false,true])for(const caption of ['', 'caption with link https://example.com '.repeat(4)]){
  const g=group(caption);Object.assign(g.head,{contentType:'photo',isAnimation:false,photoFileId:5,photoWidth:1000,photoHeight:1000,photoPath:'',photoMini:'',photoProgress:0,photoFailed:false});
  const p=new ctx.DrawnSingleMediaLayouts().prepare(ui,g,{...data,contentWidth:w,isGroup,splitLayout:true},style);assert.ok(p);
  const budget=realWidth(w,isGroup?41:0,device);
  assert.ok(p.grid.width<=budget+1e-6);if(!caption)assert.equal(p.grid.width,budget);
  assert.ok(p.grid.x+p.grid.width<=w);if(p.caption)assert.ok(p.captionX+p.caption.widthVp<=p.width+1e-6);
  cases++;
 }
}
const skeleton=fs.readFileSync(root+'pages/chat/InitialLoadingHint.ets','utf8');
Object.assign(nav,{BUBBLE_AVATAR_GUTTER_VP:41,bubbleMaxWidth:vm.runInContext('bubbleMaxWidth',ctx)});
run(`class Skeleton {${['effectiveIsOut','showGroupAvatarColumn','bubbleWidthVp'].map(n=>method(skeleton,n)).join('\n')}}globalThis.Skeleton=Skeleton;`);
for(const w of [0,40,80,180,240,390,800])for(const isGroup of [false,true])for(const isChannel of [false,true])for(const isOut of [false,true]){
 const sk=new nav.Skeleton();Object.assign(sk,{screenW:w,isGroup,isChannel,splitLayout:true});
 const width=sk.bubbleWidthVp({isOut,widthRatio:.84});assert.ok(width>=0&&width<=w);
}
assert.equal(nav.bubbleMaxWidth(390,0),358);assert.equal(nav.bubbleMaxWidth(390,41),317);
console.log(`PASS: search boundaries/loading/exhaustion/lifecycle and stale click guards; emitted Button reactive updates; ${cases} device/media/caption geometries; narrow skeleton bounds; unchanged text widths.`);
