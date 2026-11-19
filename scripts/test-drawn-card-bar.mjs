import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
const imported=await import(process.env.TYPESCRIPT_MODULE||'typescript'),ts=imported.default||imported;
let shapes=0,allocations=0,invalidations=0,resolutions=0;
const painted=[];
class Units {density=1;prepare(){return this;}fp2px(n){return n;} }
class Cache {prepare(content,width,font,color,env){if(this.content===content&&this.width===width&&this.font===font&&this.env===env){this.hit.color=color;return this.hit;}shapes++;this.content=content;this.width=width;this.font=font;this.env=env;return this.hit={widthPx:Math.min(width,content.length*5),heightPx:font,paragraph:{paint:(_c,x,y)=>painted.push({content,x,y})}};} }
class Brush {constructor(){allocations++;}setAntiAlias(){}setColor(){} }
class RoundRect {constructor(){allocations++;} }
const ctx=vm.createContext({DrawModifier:class{invalidate(){invalidations++;}},DrawnTextUnits:Units,DrawnTextLineCache:Cache,drawnColor:c=>{resolutions++;return {alpha:c==='#00000000'?0:255};},drawing:{Brush,RoundRect}});
const source=fs.readFileSync('entry/src/main/ets/pages/chat/DrawnCardBar.ets','utf8').replace(/^import\s[\s\S]*?;\r?\n/gm,'').replace(/\bexport /g,'');
vm.runInContext(ts.transpileModule(source+'\nglobalThis.Bar=DrawnCardBar;',{compilerOptions:{target:ts.ScriptTarget.ES2020}}).outputText,ctx);
const p=new ctx.Bar(),ui={},spec={width:220,height:34,environment:'1',left:'Votes',right:'Closed',leftColor:'primary',rightColor:'secondary',paddingRight:20,paddingBottom:10};
const canvas={attachBrush(){},detachBrush(){},drawRoundRect(){}};
p.bind(ui,spec);p.drawBehind({canvas});const cold={shapes,allocations,invalidations,resolutions};
for(let i=0;i<1000;i++){p.bind(ui,{...spec});p.drawBehind({canvas});}
assert.deepEqual({shapes,allocations,invalidations,resolutions},cold);
for(let i=0;i<1000;i++)p.bind(ui,{...spec,right:`${i}`});assert.equal(shapes,cold.shapes+1000,'right status does not reshape stable left text');assert.equal(allocations,cold.allocations);
painted.length=0;p.bind(ui,{...spec,left:'',right:'',center:'Submit',background:'primary',radius:9});p.drawBehind({canvas});assert.deepEqual(painted,[{content:'Submit',x:95,y:5.5}]);
painted.length=0;p.bind(ui,{...spec,left:'',right:'',center:''});p.drawBehind({canvas});assert.equal(painted.length,0,'pending/recycled control cannot keep the previous label');
const before=resolutions;p.bind(ui,{...spec,leftColor:{id:1},rightColor:{id:2}});assert.ok(resolutions>before,'ResourceColor objects are compared by reference, not stringification');
console.log('PASS: card chrome retains native shapes/paragraphs/colors across 1000 binds, independent status cache, centered labels, pending/reuse reset and resource colors.');

const preShaped={widthPx:20,heightPx:10,paragraph:{paint:(_c,x,y)=>painted.push({content:'prepared',x,y})}};
const shapeCount=shapes;painted.length=0;p.bind(ui,{...spec,left:'',right:'',centerPrepared:preShaped});p.drawBehind({canvas});
assert.equal(shapes,shapeCount,'prepared labels paint without duplicate shaping');assert.deepEqual(painted,[{content:'prepared',x:100,y:7}]);
