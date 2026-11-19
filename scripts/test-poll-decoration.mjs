import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
const imported=await import(process.env.TYPESCRIPT_MODULE||'typescript'),ts=imported.default||imported;
let allocations=0,invalidations=0,strokeChanges=0,shapes=0;
const painted=[];
class LineCache {prepare(content,max,font,color,environment){shapes++;return {content,heightPx:14,color,paragraph:{paint:(_canvas,x,y)=>painted.push({content,x,y})}};}}
class Brush {constructor(){allocations++;}setAntiAlias(){}setColor(){} }
class Pen extends Brush {setCapStyle(){}setStrokeWidth(){strokeChanges++;}}
const ctx=vm.createContext({DrawModifier:class{invalidate(){invalidations++;}},drawing:{Brush,Pen,RoundRect:class{constructor(rect){allocations++;this.rect=rect;}},CapStyle:{ROUND_CAP:1}},drawnColor:()=>({alpha:255,red:1,green:2,blue:3}),DrawnTextLineCache:LineCache,Map,Number,Math});
const source=fs.readFileSync('entry/src/main/ets/pages/chat/DrawnPollOptionDecoration.ets','utf8').replace(/^import\s[\s\S]*?;\r?\n/gm,'').replace(/\bexport /g,'');
vm.runInContext(ts.transpileModule(source+'\nglobalThis.Decoration=DrawnPollOptionDecoration;globalThis.Labels=DrawnPollPercentLabels;',{compilerOptions:{target:ts.ScriptTarget.ES2020}}).outputText,ctx);
const painter=new ctx.Decoration();painter.bind(1,'#3390EC','vote',true,50);assert.equal(invalidations,1);
for(let i=0;i<1000;i++)painter.bind(1,'#3390EC','vote',true,50);
assert.equal(invalidations,1);assert.equal(strokeChanges,2);
const rects=[],circles=[],lines=[];
const context={sizeInPixel:{width:200,height:60},canvas:{attachBrush(){},detachBrush(){},attachPen(){},detachPen(){},drawRoundRect(){},drawRect:r=>rects.push({...r}),drawCircle:(...p)=>circles.push(p),drawLine:(...p)=>lines.push(p)}};
painter.drawBehind(context);const allocated=allocations;
for(let i=0;i<1000;i++)painter.drawBehind(context);assert.equal(allocations,allocated,'warm option repaint never reallocates its rounded geometry');
rects.splice(1);circles.splice(1);lines.splice(2);
assert.equal(rects[0].right,100);assert.equal(rects[0].top,57);assert.equal(circles[0][1],30);assert.equal(lines.length,2);
painter.bind(1,'#3390EC','neutral',false,0);rects.length=0;circles.length=0;lines.length=0;painter.drawBehind(context);
assert.equal(rects.length,0);assert.equal(circles.length,1);assert.equal(lines.length,0,'reused option clears old selection and progress');
painter.bind(2,'#3390EC','wrong',true,Infinity);assert.equal(strokeChanges,4);rects.length=0;lines.length=0;painter.drawBehind(context);assert.equal(lines.length,2);assert.equal(rects.length,0);
painter.bind(2,'#3390EC','selected',true,150);rects.length=0;circles.length=0;painter.drawBehind(context);assert.equal(rects[0].right,200);assert.equal(circles.at(-1)[2],7);
const poll=fs.readFileSync('entry/src/main/ets/pages/chat/PollBubble.ets','utf8');
const option=poll.slice(poll.indexOf('  private optionSlot('),poll.indexOf('  build()'));
assert.doesNotMatch(option,/optionBarPercent\(index\)\}%/,'bar percentage cannot set native layout width');
assert.match(option,/alignContent: Alignment.Center/,'minimum-height option centers marker and text together');
assert.doesNotMatch(option,/Circle\(|SymbolGlyph\(/,'selection decorations share the existing surface');
console.log('PASS: 1000 stable binds do not invalidate/reconfigure pens; decoration geometry, no native allocation in warm paint, percent clamp, state reset and no bar-width layout node.');

const labels=new ctx.Labels(),label=labels.prepare(50,'#3390EC',12,40,'env');
const shaped=shapes;
for(let i=0;i<1000;i++)assert.equal(labels.prepare(50,'#3390EC',12,40,'env'),label);
assert.equal(shapes,shaped,'stable percentage never reshapes');
painter.bind(1,'#3390EC','vote',true,50,label);painted.length=0;painter.drawBehind(context);
assert.deepEqual(painted,[{content:'50%',x:151,y:23}]);
const labelInvalidations=invalidations;painter.bind(1,'#3390EC','vote',true,50,label);assert.equal(invalidations,labelInvalidations);
painter.bind(1,'#3390EC','vote',true,50,null);painted.length=0;painter.drawBehind(context);assert.equal(painted.length,0,'hidden results clear old label');
assert.notEqual(labels.prepare(50,'#32A765',12,40,'env'),label,'shared paragraphs keep independent colors');
for(let i=0;i<300;i++)labels.prepare(i%101,`#${i}`,12,40,'env');assert.equal(labels.lines.size,128);
const changed=labels.prepare(50,'#3390EC',15,40,'new-env');assert.notEqual(changed,label);assert.equal(labels.lines.size,1);
assert.doesNotMatch(option,/Text\(`\$\{this.optionVotePercentage/,'percentage has no native text node');
assert.match(option,/right: 57/,'percentage reserve stays constant without its former Text node');
console.log('PASS: cached percentage paint positions, 1000 no-shape hits, color separation, hide/reset and 128-entry/font-environment bounds.');
