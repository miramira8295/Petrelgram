import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
const imported=await import(process.env.TYPESCRIPT_MODULE||'typescript'),ts=imported.default||imported;
let nativeAllocations=0,antiAlias=0,strokes=0,shapes=0,invalidations=0;
class Pen {constructor(){nativeAllocations++;}setAntiAlias(){antiAlias++;}setCapStyle(){}setStrokeWidth(){strokes++;}setColor(){} }
class Labels {prepare(content,max,font,color,environment){shapes++;return {widthPx:Math.min(max,content.length*font/2),heightPx:font,paragraph:{paint(_c,x,y){texts.push({content,x,y});}}};} }
const texts=[],arcs=[];
const ctx=vm.createContext({DrawModifier:class{invalidate(){invalidations++;}},drawing:{Pen,CapStyle:{ROUND_CAP:1}},DrawnTextLineCache:Labels,drawnColor:c=>({alpha:255,red:1,green:2,blue:3})});
function load(path,names){const source=fs.readFileSync(path,'utf8').replace(/^import\s[\s\S]*?;\r?\n/gm,'').replace(/\bexport /g,'');vm.runInContext(ts.transpileModule(source+names.map(n=>`\nglobalThis.${n}=${n};`).join(''),{compilerOptions:{target:ts.ScriptTarget.ES2020}}).outputText,ctx);}
load('entry/src/main/ets/util/drawnTextUnits.ets',['DrawnTextUnits']);load('entry/src/main/ets/pages/chat/DrawnProgressRing.ets',['DrawnProgressRing']);
let conversions=0;const ui={vp2px:n=>{conversions++;return n;},fp2px:n=>{conversions++;return n;}};
const canvas={attachPen(){},detachPen(){},drawArc:(rect,start,sweep)=>arcs.push({rect:{...rect},start,sweep})};
const p=new ctx.DrawnProgressRing();p.bind(ui,'1',36,'white',25,true);p.drawBehind({canvas});assert.equal(arcs.at(-1).sweep,90);assert.equal(texts.at(-1).content,'25%');
const cold={nativeAllocations,antiAlias,strokes,shapes,conversions,invalidations};
for(let i=0;i<1000;i++){p.bind(ui,'1',36,'white',25,true);p.drawBehind({canvas});}
assert.deepEqual({nativeAllocations,antiAlias,strokes,shapes,conversions,invalidations},cold);
for(let i=0;i<1000;i++){p.bind(ui,'1',36,'white',i%100,true);p.drawBehind({canvas});}
assert.equal(shapes,100,'one shared label per actual percentage');assert.equal(conversions,cold.conversions);assert.equal(antiAlias,cold.antiAlias);assert.equal(strokes,cold.strokes);assert.equal(nativeAllocations,cold.nativeAllocations);
const another=new ctx.DrawnProgressRing(),before=shapes;another.bind(ui,'1',36,'white',25,true);assert.equal(shapes,before,'sibling image reuses immutable percentage paragraph');
p.bind(ui,'1',36,'white',0,false,true);p.drawBehind({canvas});assert.equal(arcs.at(-1).sweep,270);
p.bind(ui,'1',36,'white',Infinity,true);texts.length=0;p.drawBehind({canvas});assert.equal(texts[0].content,'0%');
p.bind(ui,'1',36,'white',200,true);p.drawBehind({canvas});assert.equal(arcs.at(-1).sweep,360);
vm.runInContext('globalThis.labelCount=()=>progressLabels.get(globalThis.testUi)?.entries.size;',ctx);ctx.testUi=ui;
for(let i=0;i<600;i++)p.bind(ui,'1',36+i/100,'white',i%100,true);assert.equal(ctx.labelCount(),256);
p.bind(ui,'font2',36,'white',25,true);assert.equal(ctx.labelCount(),1,'environment changes discard stale font labels');
console.log('PASS: radial geometry/clamp/spinner, 1000 no-allocation/no-conversion warm binds, shared percentage labels and 256-entry/font reset bounds.');
