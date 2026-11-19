import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
const imported=await import(process.env.TYPESCRIPT_MODULE||'typescript'),ts=imported.default||imported;
let allocations=0,strokes=0,invalidations=0;const calls=[];
class Paint {constructor(){allocations++;}setAntiAlias(){}setCapStyle(){}setStrokeWidth(){strokes++;}setColor(c){this.color=c;} }
class Units {density=0;prepare(ui){this.density=ui.density;return this;}}
const ctx=vm.createContext({DrawModifier:class{invalidate(){invalidations++;}},drawing:{Brush:Paint,Pen:Paint,CapStyle:{ROUND_CAP:1}},DrawnTextUnits:Units,drawnColor:c=>c});
function source(path,names){const s=fs.readFileSync(path,'utf8').replace(/^import\s[\s\S]*?;\r?\n/gm,'').replace(/\bexport /g,'').replace(/@(?:Require|Param|Local|Computed|Event)\s*/g,'').replace(/@Monitor\([^)]*\)\s*/g,'');vm.runInContext(ts.transpileModule(s+names.map(n=>`\nglobalThis.${n}=${n};`).join(''),{compilerOptions:{target:ts.ScriptTarget.ES2020}}).outputText,ctx);}
source('entry/src/main/ets/pages/chat/DrawnSeekTrack.ets',['DrawnSeekTrack']);
const p=new ctx.DrawnSeekTrack(),ui={density:2},dc={canvas:{attachPen(){},detachPen(){},attachBrush(){},detachBrush(){},drawLine:(...args)=>calls.push(['line',...args]),drawCircle:(...args)=>calls.push(['thumb',...args])}};
function bind(f=.25,drag=false,width=240,environment='env'){return p.bind(ui,environment,width,20,f,drag,'active','track');}
bind();p.drawForeground(dc);assert.deepEqual(calls,[['line',16,20,464,20],['line',16,20,128,20],['thumb',128,20,12]]);
let before=[allocations,strokes,invalidations];for(let i=0;i<1000;i++){bind();p.drawForeground(dc);}assert.deepEqual([allocations,strokes,invalidations],before);
before=[allocations,strokes];for(let i=0;i<1000;i++){bind(i/999,!!(i%2));p.drawForeground(dc);}assert.deepEqual([allocations,strokes],before,'progress and drag cannot allocate/reconfigure pens');
calls.length=0;bind(NaN);p.drawForeground(dc);assert.equal(calls.length,2);assert.deepEqual(calls.at(-1),['thumb',16,20,12]);calls.length=0;bind(2,true);p.drawForeground(dc);assert.deepEqual(calls.at(-1),['thumb',464,20,16]);
calls.length=0;bind(.5,false,8);p.drawForeground(dc);assert.deepEqual(calls.at(-1),['thumb',8,20,6]);
// Exercise the compiled UI to prove native Slider input survives with exactly
// one painted track, without hiding the semantic host using opacity/visibility.
const created=[],slider=[],colors=[],changes=[],modifiers=[];let id=0;
class View {static create(){} }
class Child {constructor(_p,params){this.params=params;}}
class Painter {bind(...args){this.args=args;return this;}}
Object.assign(ctx,{ViewV2:View,ViewPU:class{},DrawnDocumentAudioCover:Child,DrawnLoadingSpinner:Child,LiveProgressRing:Child,chatEnv:{appearanceEpoch:1,langEpoch:1},textMeasureEnvironment:{epoch:1},str:k=>k,formatVoiceDuration:n=>String(n),COLOR_PRIMARY:'active',COLOR_TEXT_PRIMARY:'primary',COLOR_TEXT_SECONDARY:'secondary',SliderStyle:{NONE:2},SliderChangeMode:{Begin:0,Moving:1,End:2,Click:3},HitTestMode:{None:0},HorizontalAlign:{Start:0},documentFileId:f=>f?.id??0});
for(const name of ['Row','Column','Stack','If','Slider'])ctx[name]=new Proxy({}, {get:(_t,k)=>(...args)=>{if(k.startsWith('create')){created.push(name);if(name==='Slider')slider.push(args[0]);}if(name==='Slider'){if(k==='trackColor'||k==='selectedColor')colors.push(args[0]);if(k==='onChange')changes.push(args[0]);if(k==='drawModifier')modifiers.push(args[0]);assert.notEqual(k,'opacity');assert.notEqual(k,'visibility');}}});
source('entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/pages/chat/DrawnDocumentAudio.ts',['DrawnDocumentAudio']);
const card=Object.assign(Object.create(ctx.DrawnDocumentAudio.prototype),{widget:{file:{id:5},title:'title',performer:'artist',duration:30},boxWidth:240,env:ctx.chatEnv,generation:1,progress:.25,elapsed:0,seekDragging:false,pending:false,loading:false,playing:false,preparing:false,failed:false,seekPainter:new Painter(),controlPainter:new Painter(),labelPainter:new Painter(),labels:{prepare(){return{width:192,height:30};}},getUIContext:()=>ui,observeComponentCreation2:fn=>fn(++id,true),ifElseBranchUpdateFunction:(_i,fn)=>fn()});
card.initialRender();assert.equal(created.filter(n=>n==='Slider').length,1);assert.equal(slider[0].style,2);assert.equal(slider[0].value,.25);assert.deepEqual(colors,['#00000000','#00000000']);assert.equal(changes.length,1);assert.equal(modifiers[0],card.seekPainter);assert.equal(card.seekPainter.args[2],192);
console.log('PASS: retained seek track/thumb geometry, 1000 stable and moving paints without allocations/pen setup, clamp/narrow boxes and compiled native Slider input with transparent visuals.');
