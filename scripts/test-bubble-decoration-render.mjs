// Record the real ArkUI compiler output at the shell branch. The small layout
// model checks Row's absolute-child exclusion; it does not prove device pixels.
import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
const ts=(await import(process.env.TYPESCRIPT_MODULE||'typescript')).default;
const filename='entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/pages/chat/MessageBubbleShell.ts';
const source=fs.readFileSync(filename,'utf8');
const compile=s=>ts.transpileModule(s,{compilerOptions:{target:ts.ScriptTarget.ES2020}}).outputText;
function fragments(text){
 const ast=ts.createSourceFile('shell.ts',text,ts.ScriptTarget.Latest,true);let branch;const methods={};
 function visit(n){
  if(!branch&&ts.isIfStatement(n)&&n.expression.getText(ast)==='this.env.bubbleMaterialOn'&&n.getText(ast).includes('solidShellShadow'))branch=n.getText(ast);
  if(ts.isMethodDeclaration(n)&&['solidShellShadow','glassOutline'].includes(n.name.getText(ast)))methods[n.name.getText(ast)]=n.getText(ast);
  ts.forEachChild(n,visit);
 }visit(ast);assert.ok(branch);assert.equal(Object.keys(methods).length,2);
 return compile(`globalThis.render=function(){${branch}};globalThis.methods={${Object.values(methods).join(',')}};`);
}
function setup(text,cfg){
 const root={type:'root',props:{},children:[]};let stack=[root],snapshots=0;
 const enumOf=()=>new Proxy({},{get:(_o,k)=>String(k)});
 function node(type){return new Proxy({},{get:(_o,name)=>(...args)=>{
  if(type==='If')return;
  if(name==='create'){
   const n={type,props:{},children:[]};if(type==='Path')Object.assign(n.props,args[0]);stack.at(-1).children.push(n);stack.push(n);return;
  }
  if(name==='pop'){assert.equal(stack.pop().type,type);return;}
  const current=stack.at(-1);assert.equal(current.type,type);
  if(name==='background'){
   snapshots++;const saved=stack,bg={type:'root',props:{},children:[]};stack=[bg];args[0].builder();stack=saved;current.background=bg.children;return;
  }
  current.props[name]=args.length===1?args[0]:args;
 }});}
 const globals={Row:node('Row'),Column:node('Column'),Path:node('Path'),If:node('If'),
  Alignment:enumOf(),VerticalAlign:enumOf(),HitTestMode:enumOf(),Color:enumOf(),
  JUMP_FOCUS_SCALE:.025,JUMP_FOCUS_BRIGHTNESS:.08,GLASS_OUTLINE_COLOR:'#4DFFFFFF',GLASS_OUTLINE_WIDTH:1,
  bubbleGlassModifier:(...args)=>({args}),glassOutlineCommands:(...args)=>JSON.stringify(args)};
 const ctx=vm.createContext(globals);vm.runInContext(fragments(text),ctx);
 const host={env:{bubbleMaterialOn:cfg.material},msg:{isOutgoing:cfg.outgoing},glassW:cfg.w,glassH:cfg.h,jumpFocus:.4,
  observeComponentCreation2:fn=>{fn(1,true);if(stack.at(-1).type==='Path')stack.pop();},ifElseBranchUpdateFunction:(_n,fn)=>fn(),
  shadowShapeCache:{prepare:(...args)=>JSON.stringify(args)},
  hasBubbleTail:()=>cfg.tail,bubbleCornerRadius:()=>({topLeft:12,topRight:12,bottomLeft:cfg.tail?2:12,bottomRight:12}),
  isBareEmoji:()=>cfg.bare,glassReady:()=>cfg.ready,glassBodyOn:()=>cfg.body,
  containerGlassBg:()=>cfg.ready?'glass':'transparent',containerGlassBlurStyle:()=>cfg.ready?'blur':undefined,
  glassRadius:()=>({topLeft:12,topRight:12,bottomLeft:0,bottomRight:12}),
  tailGutterPadding:()=>cfg.outgoing?{right:7}:{left:7},
  bubbleCluster(){globals.Row.create();globals.Row.width(cfg.contentW);globals.Row.height(cfg.contentH);globals.Row.pop();}};
 Object.assign(host,ctx.methods);ctx.render.call(host);assert.equal(stack.length,1);
 return {root,snapshots,host};
}
function size(n){
 const flow=n.children.filter(c=>!c.props.position),sizes=flow.map(size),pad=n.props.padding??{};
 const hpad=(pad.left??0)+(pad.right??0),vpad=(pad.top??0)+(pad.bottom??0);
 return {w:n.props.width??(sizes.reduce((s,x)=>s+x.w,0)+hpad),h:n.props.height??(Math.max(0,...sizes.map(x=>x.h))+vpad)};
}
function decorations(n){return [...(n.background??[]).flatMap(d=>[d,...decorations(d)]),...n.children.flatMap(d=>[d,...decorations(d)])].filter(x=>x.type==='Column'||x.type==='Path');}
const plain=x=>JSON.parse(JSON.stringify(x));
function visual(n){const p=plain(n.props);delete p.position;delete p.hitTestBehavior;delete p.accessibilityLevel;return {type:n.type,props:p};}
const baseline=process.env.SHELL_BASELINE_COMPILED?fs.readFileSync(process.env.SHELL_BASELINE_COMPILED,'utf8'):null;
let cases=0;
for(const material of [false,true])for(const outgoing of [false,true])for(const tail of [false,true])for(const bare of [false,true])for(const stage of ['unmeasured','ready','fallback','transparent','shrink']){
 const cfg={material,outgoing,tail,bare,w:stage==='unmeasured'?0:stage==='shrink'?500:287,h:stage==='unmeasured'?0:stage==='shrink'?700:420,
  contentW:stage==='shrink'?120:280,contentH:stage==='shrink'?80:420,ready:stage==='ready',body:stage==='ready'||stage==='transparent'};
 const after=setup(source,cfg);assert.equal(after.snapshots,0);const owner=after.root.children[0];
 assert.deepEqual(size(owner),{w:cfg.contentW+7,h:cfg.contentH});
 const absolute=owner.children.filter(c=>c.props.position);for(const n of absolute){assert.deepEqual(plain(n.props.position),{x:0,y:0});assert.equal(n.props.hitTestBehavior,'None');assert.equal(n.props.accessibilityLevel,'no');}
 const callback=owner.props.onSizeChange;callback({}, {width:cfg.contentW+7,height:cfg.contentH});assert.equal(after.host.glassW,cfg.contentW+7);assert.equal(after.host.glassH,cfg.contentH);
 if(baseline){
  const before=setup(baseline,cfg),oldOwner=before.root.children[0];assert.equal(before.snapshots,1);
  assert.deepEqual(size(owner),size(oldOwner));
  assert.deepEqual(decorations(owner).map(visual),decorations(oldOwner).map(visual));
  for(const key of ['scale','brightness','backgroundColor','backgroundBlurStyle','borderRadius','attributeModifier'])assert.deepEqual(plain(owner.props[key]??null),plain(oldOwner.props[key]??null),key);
  const inner=owner.children.find(c=>!c.props.position);assert.deepEqual(plain(inner.props.padding),plain(oldOwner.props.padding));assert.equal(inner.props.alignItems,oldOwner.props.alignItems);
 }
 cases++;
}
console.log(`Bubble decoration: ${cases} compiled-builder cases passed; no background builder; Row dimensions, shrinking, decorative paths/shadows/material/transforms, padding, hit testing and size delivery matched.`);
