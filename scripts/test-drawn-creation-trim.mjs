// Replay production lifecycle, painter and compiler output. Native drawing and
// text shaping are doubles; this checks work bounds/structure, not device ms.
import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
const ts=(await import(process.env.TYPESCRIPT_MODULE || 'typescript')).default;
const root='entry/src/main/ets/';
const compiled='entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/'+root;
let publishes=0, shapes=0, paths=0, conversions=0, invalidations=0;
const paints=[],completed=[];
class View {initParam(k,v){this[k]=v;}finalizeConstruction(){} }
const ctx=vm.createContext({ViewV2:View,ViewPU:View,
  DrawModifier:class {invalidate(){invalidations++;}},
  drawing:{Brush:class {setAntiAlias(){}setColor(){}},Pen:class {setAntiAlias(){}setColor(){}setStrokeWidth(){}},
    Path:class {constructor(){paths++;this.points=[];}moveTo(x,y){this.points.push([x,y]);}lineTo(x,y){this.points.push([x,y]);}close(){}},
    RoundRect:class {constructor(rect,x,y){this.rect=rect;this.x=x;this.y=y;}}},
  text:{FontWeight:{W500:500,W400:400},TextDirection:{LTR:0},TextAlign:{LEFT:0},FontCollection:{getGlobalInstance(){return {};}},
    ParagraphBuilder:class {constructor(style){this.style=style;}addText(content){this.content=content;}build(){shapes++;const text=this.content,style=this.style;return {
      layoutSync(width){this.width=width;},getHeight(){return style.textStyle.fontSize*1.2;},getLongestLine(){return Math.min(this.width,text.length*6);},
      paint(_canvas,x,y){paints.push({text,x,y});},updateColor(){}};}}},
  chatEnv:{langEpoch:1},textMeasureEnvironment:{epoch:1},a11yRuntimeState:{active:false},
  formatFileSize:n=>n+'B',formatMediaDuration:n=>n+'s', $r:x=>x,Color:{White:'#fff'},
  PLAY_SLOT_KEEP_RATIO:.2,PLAY_SLOT_ENTER_RATIO:.7
});
function load(path,names){
 const source=fs.readFileSync(path,'utf8').replace(/^import\s[\s\S]*?;\r?\n/gm,'')
  .replace(/@(?:Require|Param|Local|Computed|Event)\s*/g,'').replace(/@Monitor\([^)]*\)\s*/g,'').replace(/\bexport /g,'');
 vm.runInContext(ts.transpileModule(source+names.map(n=>`\nglobalThis.${n}=${n};`).join(''),{compilerOptions:{target:ts.ScriptTarget.ES2020}}).outputText,ctx,{filename:path});
}
load(root+'pages/chat/DrawnRowLeaveCapture.ets',['DrawnRowLeaveCapture']);
let captured='';const capture=new ctx.DrawnRowLeaveCapture(k=>{publishes++;captured=k;});
const a={complete:id=>completed.push(['a',id])},b={complete:id=>completed.push(['b',id])};
capture.bind('A',10,0,true,a);const pub=publishes;
for(let i=0;i<1000;i++)capture.bind('A',10,0,true,a);
assert.equal(publishes,pub,'ordinary updates do no state writes');
capture.bind('A',10,1,true,a);const old=capture.captured(),finish=capture.finished(10,a);
old();assert.equal(captured,'A');capture.bind('A',10,0,true,a);old();assert.equal(captured,'','restore rejects late capture');
capture.bind('A',10,1,true,a);const aba=capture.captured();capture.bind('B',11,1,true,b);capture.bind('A',10,1,true,a);
aba();assert.equal(captured,'','A/B/A callback cannot hide reused row');
capture.captured()();assert.equal(captured,'A');capture.reset();aba();assert.equal(captured,'');
capture.bind('B',11,1,true,b);finish();assert.deepEqual(completed.at(-1),['a',10],'old finish resolves original channel/id');
capture.bind('B',11,1,false,b);const before=completed.length;
for(let i=0;i<1000;i++)capture.bind('B',11,1,false,b);
assert.equal(completed.length,before,'unsupported capture completes once');assert.deepEqual(completed.at(-1),['b',11]);
capture.captured()();assert.equal(captured,'');
console.log('PASS: deletion restore/recycle/A-B-A reject late capture, old completion retains original channel, 1000 unchanged binds have no writes.');

load(root+'pages/chat/DrawnTextLine.ets',['DrawnTextLineCache']);
load(root+'pages/chat/DrawnVideoDecoration.ets',['DrawnVideoDecoration']);
const ui={vp2px:n=>{conversions++;return n*2;},fp2px:n=>{conversions++;return n*2;}};
const painter=new ctx.DrawnVideoDecoration(),draws=[];
const canvas=new Proxy({}, {get:(_t,k)=>(...args)=>draws.push([k,...args])});
painter.bind(ui,150,100,'2s · 30B',true,'1');painter.drawForeground({canvas});
assert.equal(shapes,1);assert.equal(paths,1);assert.equal(conversions,2);
assert.equal(paints.at(-1).x,22);assert.equal(paints.at(-1).y,156);
assert.deepEqual(draws.find(d=>d[0]==='drawCircle').slice(1),[150,100,40]);
const first={shapes,paths,conversions,invalidations};
for(let i=0;i<1000;i++){painter.bind(ui,150,100,'2s · 30B',true,'1');painter.drawForeground({canvas});}
assert.deepEqual({shapes,paths,conversions,invalidations},first,'steady bind/draw does not shape/allocate geometry/query metrics/invalidate');
for(let i=0;i<1000;i++)painter.bind(ui,150,100,'2s · 30B',i%2===0,'1');
assert.equal(shapes,1);assert.equal(paths,1);assert.equal(conversions,2,'play state does not remeasure');
painter.bind(ui,60,45,'very long duration and size',false,'1');assert.equal(shapes,2);
assert.ok(painter.background.rect.right<=108,'badge respects width including padding');
const last=paints.length;painter.bind(ui,60,45,'',false,'1');painter.drawForeground({canvas});assert.equal(paints.length,last,'suppressed native-accessibility badge leaves no old paint');
painter.bind(ui,60,45,'new',true,'2');assert.equal(conversions,4);assert.equal(shapes,3);
const pendingPainter = new ctx.DrawnVideoDecoration(), pendingPaths=paths, pendingShapes=shapes;
for(let i=0;i<1000;i++)pendingPainter.bind(ui,100+i%4,80+i%3,'',false,'1');
assert.equal(paths,pendingPaths);assert.equal(shapes,pendingShapes,'pending dimensions do not build paths or paragraphs');
pendingPainter.bind(ui,150,100,'latest',true,'1');assert.equal(paths,pendingPaths+1);assert.equal(shapes,pendingShapes+1);
const geometryPaths=paths;pendingPainter.bind(ui,200,120,'',false,'1');assert.equal(paths,geometryPaths);
pendingPainter.bind(ui,200,120,'new size',true,'1');assert.equal(paths,geometryPaths+1,'publication consumes the latest delayed geometry');
console.log('PASS: 1000 stable draws and 1000 playback changes reuse paragraph/path/metrics; resize/ellipsis/clear/environment refresh correctly.');

// Actual compiled video tree: inactive video has only its lifecycle Stack;
// player and accessible labels still use native children on demand.
load(root+'pages/chat/DrawnVideoMeta.ets',['drawnVideoMetaCache']);
load(compiled+'pages/chat/DrawnAlbumVideo.ts',['DrawnAlbumVideo']);
const created=[],native=[];let eid=0;
for(const name of ['If','Stack','Row','Circle','SymbolGlyph','Text','__Common__'])ctx[name]=new Proxy({}, {get:(_t,k)=>(...args)=>{if(k==='create')created.push(name);}});
for(const name of ['FontWeight','TextOverflow','HitTestMode'])ctx[name]=new Proxy({}, {get:(_t,k)=>k});
ctx.VideoBubbleSurface=class {constructor(_owner,params){native.push(params);}};ctx.ViewV2.create=()=>{};
const cell={chatId:1,messageId:10,idx:0,width:150,height:100,isVideo:true,isLive:false,isPlaySlot:false,videoFileId:8,inlineFileId:9,videoFileSize:30,videoDuration:2};
const video=new ctx.DrawnAlbumVideo(null,{cell,actions:{},thumbReady:true});
video.getUIContext=()=>ui;video.observeComponentCreation2=fn=>fn(++eid,true);video.ifElseBranchUpdateFunction=(_id,fn)=>fn();
video.initialRender();assert.equal(created.filter(n=>n==='Stack').length,1);assert.equal(created.filter(n=>['Text','Circle','SymbolGlyph'].includes(n)).length,0);
video.cell={...cell,isPlaySlot:true};video.initialRender();assert.equal(native.length,1);assert.equal(native[0].fileId,9);assert.equal(video.decoration.play,false);
video.sendState='sending';video.initialRender();assert.equal(native.length,1);assert.equal(video.decoration.play,false);
video.sendState='sent';video.cell={...cell,isLive:true};video.initialRender();assert.equal(video.decoration.play,false);assert.ok(created.includes('Text'),'Live Photo label preserved');
ctx.a11yRuntimeState.active=true;video.cell=cell;created.length=0;video.initialRender();assert.ok(created.includes('Text'));assert.ok(created.includes('Circle'));assert.equal(video.decoration.label,null);
ctx.a11yRuntimeState.active=false;video.cell=undefined;video.mediaWidth=150;video.mediaHeight=100;created.length=0;
const pendingNativeCount=native.length;video.initialRender();assert.equal(native.length,pendingNativeCount);
assert.equal(created.filter(n=>n==='Stack').length,1,'pending input keeps one fixed shell');
assert.equal(video.decoration.mediaWidth,150);assert.equal(video.decoration.mediaHeight,100);
assert.equal(video.decoration.label,null);assert.equal(video.decoration.play,false,'pending slot never paints old badges');
console.log('PASS: compiled idle video removes four native nodes; playback/upload/Live Photo/accessibility branches preserved.');

// The capture and press containers must remain distinct: both own opacity,
// while jump scale belongs to the inner canvas. Avatar remains their sibling.
load(root+'util/drawnRouteMetrics.ets',['DrawnRouteReason','DrawnRouteTracker','drawnRouteMetrics']);
load(root+'util/drawnStageMetrics.ets',['drawnStageMetrics','DrawnStage']);
load(root+'pages/chat/DrawnMediaFrames.ets',['DrawnMediaFrames']);
load(root+'pages/chat/DrawnLayoutWarmCache.ets',['takeDrawnWarmLayout']);
ctx.getTdClient ??= () => ctx; ctx.setTimeout ??= () => 0; ctx.clearTimeout ??= () => {};
load(root+'pages/chat/DrawnRecycledLayouts.ets',['DrawnLayoutRetention','takeDrawnRecycledLayout','drawnRecycledLayouts']);
load(compiled+'pages/chat/DrawnMessageRow.ts',['DrawnMessageRow']);
const row=Object.assign(Object.create(ctx.DrawnMessageRow.prototype),{layoutRetention:new ctx.DrawnLayoutRetention(),mediaFrameCache:new ctx.DrawnMediaFrames()}), nodes=[], stack=[];
for(const name of ['Column','Row','Stack','If','Text','Image','Gesture','GestureGroup','PanGesture','LongPressGesture'])ctx[name]=new Proxy({}, {get:(_t,k)=>(...args)=>{
 if(name==='If'||name.endsWith('Gesture')||name==='GestureGroup')return;
 if(k==='create'){const n={type:name,parent:stack.at(-1),attrs:{}};nodes.push(n);stack.push(n);}
 else if(k==='pop')stack.pop();else if(stack.length)stack.at(-1).attrs[k]=args;
}});
for(const name of ['Alignment','FlexAlign','PanDirection','GesturePriority','GestureMode','SourceType'])ctx[name]=new Proxy({}, {get:(_t,k)=>k});
ctx.TransitionEffect={IDENTITY:0};ctx.DRAWN_BUBBLE_PRESS={name:'press'};ctx.DRAWN_BUBBLE_PRESS_NONE={name:'none'};
ctx.ShatterDeleteOverlay=class {constructor(_owner,params){native.push(params);}};
Object.assign(row,{kind:'text',group:{dateLabel:'',showSenderName:false,showAvatar:false,head:{rowId:10,isOutgoing:false,inlineButtons:[],reactions:[]}},
 data:{chatId:1,showUnreadDivider:false,animateIn:false},actions:{rowLeave:{particleBudget:()=>8000}},env:{},leaving:0,capturedDeleteKey:'',avatarStateRevision:0,
 observeComponentCreation2:fn=>fn(++eid,true),ifElseBranchUpdateFunction:(_id,fn)=>fn(),canvasContent(){nodes.push({type:'canvas',parent:stack.at(-1),attrs:{}});},
 leaveCapture:capture,avatarPainter:{bind:()=>({})},media:{}});
Object.defineProperty(row,'plan',{configurable:true,value:{width:200,height:80,avatar:{width:38},caption:null}});
Object.defineProperty(row,'deleteCaptureSupported',{configurable:true,value:true});row.nativeAvatar=()=>false;
row.initialRender();
const shot=nodes.find(n=>n.attrs.id?.[0]==='dissolve-delete-message-1-10');assert.ok(shot);
const press=nodes.find(n=>n.attrs.attributeModifier);assert.equal(press.parent,shot);
assert.equal(nodes.find(n=>n.type==='canvas').parent,press);
const avatar=nodes.find(n=>n.attrs.drawModifier);assert.equal(avatar.parent,shot.parent,'avatar stays outside deletion/press capture');
assert.equal(nodes.filter(n=>n.type==='Stack').length,1,'no resident deletion Stack');
assert.equal(shot.attrs.opacity[0],1);assert.equal(native.filter(n=>n.nodeId).length,0,'no idle overlay');
row.leaving=1;row.capturedDeleteKey=row.deleteNodeKey;nodes.length=0;row.initialRender();
assert.equal(nodes.find(n=>n.attrs.id).attrs.opacity[0],0);assert.equal(native.at(-1).nodeId,row.deleteNodeKey);
const oldNative=native.length;Object.defineProperty(row,'deleteCaptureSupported',{configurable:true,value:false});nodes.length=0;row.initialRender();
assert.equal(nodes.find(n=>n.attrs.id).attrs.opacity[0],0);assert.equal(native.length,oldNative,'live surface skips snapshot overlay');
console.log('PASS: compiled capture/press/jump/independent-avatar hierarchy and deletion/live-surface branches preserved without resident wrapper.');
