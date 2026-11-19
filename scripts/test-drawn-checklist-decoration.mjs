import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
const imported=await import(process.env.TYPESCRIPT_MODULE||'typescript'),ts=imported.default||imported;
let allocations=0,strokes=0,invalidations=0;const calls=[];
class Paint {constructor(){allocations++;}setAntiAlias(){}setCapStyle(){}setJoinStyle(){}setStrokeWidth(){strokes++;}setColor(color){this.color=color;}}
class RoundRect {constructor(rect,x,y){allocations++;this.rect=rect;this.x=x;this.y=y;}}
class Units {density=1;prepare(ui){this.density=ui.density;return this;}}
const ctx=vm.createContext({DrawModifier:class{invalidate(){invalidations++;}},drawing:{Brush:Paint,Pen:Paint,RoundRect,CapStyle:{ROUND_CAP:1},JoinStyle:{ROUND_JOIN:1}},DrawnTextUnits:Units,COLOR_PRIMARY:'accent',COLOR_TEXT_SECONDARY:'disabled',drawnColor:c=>c});
const s=fs.readFileSync('entry/src/main/ets/pages/chat/DrawnChecklistDecoration.ets','utf8').replace(/^import\s[\s\S]*?;\r?\n/gm,'').replace(/\bexport /g,'');vm.runInContext(ts.transpileModule(s+'\nglobalThis.Decoration=DrawnChecklistDecoration;',{compilerOptions:{target:ts.ScriptTarget.ES2020}}).outputText,ctx);
const p=new ctx.Decoration(),ui={density:2};let pen,brush;
const dc={canvas:{attachPen:p=>pen=p,detachPen:()=>pen=null,attachBrush:p=>brush=p,detachBrush:()=>brush=null,drawRoundRect:r=>calls.push(['rect',r.rect,pen?.color,brush?.color]),drawLine:(...a)=>calls.push(['line',...a])}};
const bind=(done=false,pending=false,allowed=true,env='env')=>p.bind(ui,env,36,20,8,done,pending,allowed);
bind();p.drawBehind(dc);assert.equal(calls.length,1);assert.deepEqual({...calls[0][1]},{left:16,top:16,right:56,bottom:56});assert.equal(calls[0][2],'accent');
let before=[allocations,strokes,invalidations];for(let i=0;i<1000;i++){bind();p.drawBehind(dc);}assert.deepEqual([allocations,strokes,invalidations],before);
before=[allocations,strokes];for(let i=0;i<1000;i++){bind(!!(i%2),!!(i%3===0),!!(i%4));p.drawBehind(dc);}assert.deepEqual([allocations,strokes],before,'completion/pending/permission cannot allocate or reconfigure geometry');
calls.length=0;bind(true,false,false);p.drawBehind(dc);assert.equal(calls.filter(c=>c[0]==='line').length,2);assert.equal(calls[0][3],'disabled');
calls.length=0;bind(true,true,true);p.drawBehind(dc);assert.equal(calls.length,0,'pending spinner replaces stale checkmark');
calls.length=0;bind(false,false,true,'theme');p.drawBehind(dc);assert.equal(calls.length,1);
console.log('PASS: checkbox bounds, completion and disabled paint, spinner isolation, 1000 stable binds/paints without allocation/invalidation and 1000 state changes without native geometry/pen setup.');
