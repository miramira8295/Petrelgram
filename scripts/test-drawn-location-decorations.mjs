import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import {ctx,ui,shapes,paints} from './test-drawn-media-text.mjs';
const imported=await import(process.env.TYPESCRIPT_MODULE||'typescript'),ts=imported.default||imported;
let allocations=0;
class Paint {constructor(){allocations++;}setAntiAlias(){}setCapStyle(){}setJoinStyle(){}setStrokeWidth(){}setColor(){} }
class Path {constructor(){allocations++;}reset(){}moveTo(){}lineTo(){}cubicTo(){}close(){} }
class RoundRect {constructor(rect,x,y){allocations++;this.rect=rect;this.x=x;this.y=y;} }
Object.assign(ctx,{drawing:{Brush:Paint,Pen:Paint,Path,RoundRect,CapStyle:{ROUND_CAP:1},JoinStyle:{ROUND_JOIN:1}},ColorMetrics:{resourceColor:()=>({alpha:255,red:1,green:2,blue:3})},COLOR_TEXT_PRIMARY:'primary',COLOR_TEXT_SECONDARY:'secondary',COLOR_ICON_SECONDARY:'icon'});
function load(path,names){const s=fs.readFileSync(path,'utf8').replace(/^import\s[\s\S]*?;\r?\n/gm,'').replace(/\bexport /g,'').replace(/@(?:Require|Param|Local|Computed|Event)\s*/g,'').replace(/@Monitor\([^)]*\)\s*/g,'');vm.runInContext(ts.transpileModule(s+names.map(n=>`\nglobalThis.${n}=${n};`).join(''),{compilerOptions:{target:ts.ScriptTarget.ES2020}}).outputText,ctx);}
const src='entry/src/main/ets/pages/chat/';
ctx.AppStorage={get:()=>undefined};
load('entry/src/main/ets/util/systemFontWeight.ets',[]);
load(src+'DrawnTextLine.ets',['DrawnTextLineCache']);
load(src+'DrawnMediaControl.ets',['DrawnMediaControl']);
load(src+'DrawnLocationDecorations.ets',['DrawnLocationPreview','DrawnLocationBadge','DrawnLocationStop']);
const dc={canvas:new Proxy({}, {get:()=>()=>{}})};
for(const [name,bind] of [
 ['DrawnLocationBadge',p=>p.bind(ui,'loc','live',true,240)],
 ['DrawnLocationStop',p=>p.bind(ui,'loc','stop sharing',240)],
 ['DrawnLocationPreview',p=>p.bind(ui,'loc',240,false,'missing coordinates')]]) {
 const p=new ctx[name]();bind(p);p.drawBehind(dc);const initial=allocations,before=new Map(shapes);
 for(let i=0;i<1000;i++){bind(p);p.drawBehind(dc);}
 assert.equal(allocations,initial,`${name}: stable paints cannot allocate native geometry`);assert.deepEqual(shapes,before);
}
const badge=new ctx.DrawnLocationBadge();badge.bind(ui,'loc','live',true,240);const w=badge.widthVp;
badge.bind(ui,'loc','ended',false,240);paints.length=0;badge.drawBehind(dc);assert.equal(paints.at(-1).content,'ended');assert.notEqual(badge.widthVp,w);
badge.bind(ui,'loc','ended',false,40);assert.ok(badge.widthVp<=40);badge.bind(ui,'font','ended',false,240);
const preview=new ctx.DrawnLocationPreview();preview.bind(ui,'loc',240,false,'missing coordinates');preview.bind(ui,'loc',240,true,'missing coordinates');paints.length=0;preview.drawBehind(dc);assert.equal(paints.length,0,'reused valid preview cannot retain unavailable label');
// Run the compiled UI, not source-pattern checks: all states retain their actions
// and map ownership while title/badge/action decoration has no native text/icon.
const created=[],children=[],clicks=[];let next=0;
class View {initParam(k,v){this[k]=v;}finalizeConstruction(){}static create(c){children.push(c);}}
class Child {constructor(_parent,params){this.params=params;}}
Object.assign(ctx,{ViewV2:View,ViewPU:class{},DrawnDocumentMap:Child,chatEnv:{appearanceEpoch:1,langEpoch:1},textMeasureEnvironment:{epoch:1},str:k=>k,plural:(k,n)=>`${k}:${n}`,HitTestMode:{None:0},Curve:{EaseOut:1},DrawnMediaTexts:ctx.Layouts,DrawnMediaTextPainter:ctx.Painter});
for(const name of ['ViewStackProcessor','Context','Row','Column','Stack','If','__Common__','Text','SymbolGlyph','Circle','Divider'])ctx[name]=new Proxy({}, {get:(_t,k)=>(...args)=>{if(k.startsWith('create'))created.push(name);if(k==='onClick')clicks.push(args[0]);}});
load(src+'DrawnLocationCardLayout.ets',['DrawnLocationCardLayouts']);
load('entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/pages/chat/LocationBubble.ts',['LocationBubble']);
let opened=0,stopped=0;
const b=Object.assign(Object.create(ctx.LocationBubble.prototype),{cardLayouts:new ctx.DrawnLocationCardLayouts(),paintEnv:ctx.chatEnv,texts:new ctx.Layouts(),textPainter:new ctx.Painter(),previewPainter:new ctx.DrawnLocationPreview(),badgePainter:new ctx.DrawnLocationBadge(),stopPainter:new ctx.DrawnLocationStop(),chevronPainter:new ctx.DrawnMediaControl(),maxWidth:240,fitAvailableWidth:true,valid:true,realMap:true,livePeriod:3600,expiresIn:100,messageDate:100,nowSec:200,sharing:true,venueTitle:'Cafe',venueAddress:'Road',accuracy:0,proximityRadius:0,latitude:22,longitude:33,chatId:1,getUIContext:()=>ui,onOpen:()=>opened++,onStopLive:()=>stopped++,observeComponentCreation2:fn=>fn(++next,true),ifElseBranchUpdateFunction:(_i,fn)=>fn()});
function render(){created.length=0;children.length=0;clicks.length=0;b.initialRender();for(const node of ['Text','SymbolGlyph','Circle','Divider'])assert.equal(created.includes(node),false,node);}
render();assert.equal(children[0].params.boxHeight,195);assert.equal(children[0].params.widget.latitude,22);clicks.at(-1)();assert.equal(stopped,1);clicks[0]();assert.equal(opened,1);
const titleShapes=shapes.get('Cafe'),map=b.mapWidget;for(let i=0;i<1000;i++){b.nowSec=200+i;b.textPlan();b.badgeForPaint();}assert.equal(shapes.get('Cafe'),titleShapes);assert.deepEqual(b.mapWidget,map);
b.venueAddress='';b.textPlan();const stableTitle=shapes.get('Cafe');for(let i=0;i<1000;i++){b.nowSec=200+i;b.textPlan();}assert.equal(shapes.get('Cafe'),stableTitle,'countdown cannot reshape title');
b.realMap=false;b.valid=false;b.expiresIn=0;render();assert.equal(children.length,0);assert.equal(b.badgeForPaint().active,false);
b.maxWidth=120;assert.ok(b.textPlan().width<=120);b.paintEnv.langEpoch++;assert.ok(b.textPlan());
console.log('PASS: location static Canvas routes, fixed map geometry, stop/open semantics, 1000 countdowns without title shaping, bounded labels, expiry/reuse and allocation-free stable drawing.');
