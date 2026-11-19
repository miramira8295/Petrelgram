import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
const imported=await import(process.env.TYPESCRIPT_MODULE||'typescript'),ts=imported.default||imported;
let allocations=0,shapes=0,strokes=0,aa=0;const painted=[],arcs=[];let saves=0;
class Paint {constructor(){allocations++;}setAntiAlias(){aa++;}setColor(){}setCapStyle(){}setJoinStyle(){}setStrokeWidth(){strokes++;}}
class Path {constructor(){allocations++;}reset(){}moveTo(){}lineTo(){}cubicTo(){}close(){} }
class RoundRect {constructor(rect){allocations++;this.rect=rect;}}
class LabelCache {prepare(content,max,font,color,env){if(this.content===content&&this.max===max&&this.font===font&&this.env===env)return this.current;shapes++;this.content=content;this.max=max;this.font=font;this.env=env;return this.current={widthPx:content.length*font/2,heightPx:font,paragraph:{paint:(_c,x,y)=>painted.push({content,x,y})}};}}
const ctx=vm.createContext({DrawModifier:class{invalidate(){}},DrawnTextLineCache:LabelCache,drawnColor:c=>({alpha:c==='#00000000'?0:255,red:1,green:2,blue:3}),drawing:{Brush:Paint,Pen:Paint,Path,RoundRect,CapStyle:{ROUND_CAP:1},JoinStyle:{ROUND_JOIN:1}}});
function load(path,name){const source=fs.readFileSync(path,'utf8').replace(/^import\s[\s\S]*?;\r?\n/gm,'').replace(/\bexport /g,'');vm.runInContext(ts.transpileModule(source+`\nglobalThis.${name}=${name};`,{compilerOptions:{target:ts.ScriptTarget.ES2020}}).outputText,ctx);}
load('entry/src/main/ets/util/drawnTextUnits.ets','DrawnTextUnits');load('entry/src/main/ets/pages/chat/DrawnMediaControl.ets','DrawnMediaControl');load('entry/src/main/ets/pages/chat/DrawnVideoNoteOverlay.ets','DrawnVideoNoteOverlay');
const p=new ctx.DrawnVideoNoteOverlay(),ui={vp2px:n=>n,fp2px:n=>n};let paths=0;
const dc={canvas:{save(){saves++;},restore(){saves--;},translate(){},attachBrush(){},detachBrush(){},attachPen(){},detachPen(){},drawRoundRect(){},drawRect(){},drawCircle(){},drawLine(){},drawPath(){paths++;},drawArc:(rect,start,sweep)=>arcs.push(sweep)}};
p.bind(ui,'1',180,false,20,true,'0:15');p.drawBehind(dc);assert.equal(painted.at(-1).content,'0:15');assert.ok(paths>0);assert.equal(arcs.at(-1),72);assert.equal(saves,0);
const cold={allocations,shapes,strokes,aa};for(let i=0;i<1000;i++){p.bind(ui,'1',180,false,i%99+1,true,'0:15');p.drawBehind(dc);}assert.deepEqual({allocations,shapes,strokes,aa},cold,'download ticks reuse duration/glyph/background geometry');
paths=0;arcs.length=0;p.bind(ui,'1',180,true,100,false,'0:15');p.drawBehind(dc);assert.equal(paths,0);assert.equal(arcs.length,0,'native playback retains only the duration overlay');
p.bind(ui,'1',120,false,0,false,'1:00');p.drawBehind(dc);assert.equal(painted.at(-1).content,'1:00');assert.ok(shapes>cold.shapes);assert.equal(saves,0);
console.log('PASS: video-note play/ring/duration overlay, native playback decoration state, 1000 ticks without native geometry/paragraph/stroke/AA churn, width/text invalidation.');
