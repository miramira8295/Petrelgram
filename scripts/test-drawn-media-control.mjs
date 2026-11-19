import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
const imported=await import(process.env.TYPESCRIPT_MODULE||'typescript'), ts=imported.default||imported;
let allocations=0,shapes=0,invalidations=0,strokeWrites=0;
class Paint {constructor(){allocations++;}setAntiAlias(){}setCapStyle(){}setJoinStyle(){}setStrokeWidth(){strokeWrites++;}setColor(){} }
class Path {constructor(){allocations++;}reset(){}moveTo(){}lineTo(){}cubicTo(){}close(){} }
class RoundRect {constructor(rect,x,y){allocations++;this.rect=rect;this.x=x;this.y=y;} }
class Units {density=1;prepare(){return this;}fp2px(n){return n;} }
class Labels {prepare(label,max,font,color,env){if(this.label===label&&this.max===max&&this.font===font&&this.env===env)return this.hit;shapes++;this.label=label;this.max=max;this.font=font;this.env=env;return this.hit={widthPx:label.length*5,heightPx:font,paragraph:{paint(){}}};} }
const ctx=vm.createContext({DrawModifier:class {invalidate(){invalidations++;}},DrawnTextUnits:Units,DrawnTextLineCache:Labels,drawnColor:c=>({alpha:c==='#00000000'?0:255,red:1,green:2,blue:3}),drawing:{Brush:Paint,Pen:Paint,Path,RoundRect,CapStyle:{ROUND_CAP:1},JoinStyle:{ROUND_JOIN:1}}});
const source=fs.readFileSync('entry/src/main/ets/pages/chat/DrawnMediaControl.ets','utf8').replace(/^import\s[\s\S]*?;\r?\n/gm,'').replace(/\bexport /g,'');
vm.runInContext(ts.transpileModule(source+'\nglobalThis.Control=DrawnMediaControl;',{compilerOptions:{target:ts.ScriptTarget.ES2020}}).outputText,ctx);
const calls=[];
const dc={canvas:{attachBrush(){},detachBrush(){},attachPen(){},detachPen(){},drawRoundRect:r=>calls.push(['background',r.rect.right]),drawArc:(r,a,s)=>calls.push(['arc',{...r},a,s]),drawPath:()=>calls.push(['path']),drawRect:()=>calls.push(['rect']),drawCircle:()=>calls.push(['circle']),drawLine:()=>calls.push(['line'])}};
const p=new ctx.Control();const bind=(glyph,progress=0,label='')=>p.bind({},'env',48,'background','foreground',glyph,progress,true,label);
bind('percent',25,'25');p.drawBehind(dc);assert.equal(calls.find(c=>c[0]==='arc')[3],90);assert.ok(calls.some(c=>c[0]==='background'));
const coldAllocations=allocations,coldShapes=shapes,coldInvalidations=invalidations;
for(let i=0;i<1000;i++){bind('percent',25,'25');p.drawBehind(dc);}
assert.equal(allocations,coldAllocations);assert.equal(shapes,coldShapes);assert.equal(invalidations,coldInvalidations);
for(let i=0;i<1000;i++){bind('percent',i%100,`${i%100}`);p.drawBehind(dc);}
assert.equal(allocations,coldAllocations,'changing progress cannot allocate native brushes/paths/background geometry');
for(const glyph of ['play','pause','retry','download','upload','save','label-check','lock','lock-open','phone','person','pin','photo','chevron','info','warning','stop','error','']){
 calls.length=0;bind(glyph,0,glyph==='label-check'?'PDF':glyph==='error'?'!':'');p.drawBehind(dc);
 if(glyph==='pin'||glyph==='photo'){assert.ok(calls.some(c=>c[0]==='path'));assert.equal(calls.filter(c=>c[0]==='circle').length,1);}
 if(glyph==='pause')assert.equal(calls.filter(c=>c[0]==='rect').length,2);
 if(glyph==='retry')assert.equal(calls.find(c=>c[0]==='arc')[3],300);
 if(glyph==='label-check')assert.equal(calls.filter(c=>c[0]==='line').length,2);
 if(['play','retry','download','upload','save'].includes(glyph))assert.ok(calls.some(c=>c[0]==='path'));
}
calls.length=0;bind('percent',Infinity);p.drawBehind(dc);assert.equal(calls.some(c=>c[0]==='arc'),false);
calls.length=0;bind('percent',200);p.drawBehind(dc);assert.equal(calls.find(c=>c[0]==='arc')[3],360);
console.log('PASS: retained media controls, 1000 stable binds/no-shape paints, progress without native geometry allocation, playback/transfer glyphs, completed badge and clamp/reset.');

calls.length=0;p.bind({},'env',28,'#00000000','foreground','download');p.drawBehind(dc);assert.equal(calls.some(c=>c[0]==='background'),false,'transparent icon controls do not record a background fill');

const pinUI={};p.bind(pinUI,'pin',30,'#00000000','foreground','pin');const pinAlloc=allocations,pinShapes=shapes,pinInvalidations=invalidations;for(let i=0;i<1000;i++){p.bind(pinUI,'pin',30,'#00000000','foreground','pin');p.drawBehind(dc);}assert.equal(allocations,pinAlloc);assert.equal(shapes,pinShapes);assert.equal(invalidations,pinInvalidations);

for(const glyph of ['info','warning','stop']) {
 calls.length=0;bind(glyph);p.drawBehind(dc);
 assert.equal(calls.filter(c=>c[0]==='circle').length,glyph==='stop'?1:2);
 assert.equal(calls.filter(c=>c[0]==='rect').length,glyph==='stop'?1:0);
 const before=[allocations,shapes,invalidations];
 for(let i=0;i<1000;i++){bind(glyph);p.drawBehind(dc);}
 assert.deepEqual([allocations,shapes,invalidations],before);
}

const badgeSource=fs.readFileSync('entry/src/main/ets/pages/chat/DrawnSingleVideoBadge.ets','utf8').replace(/^import\s[\s\S]*?;\r?\n/gm,'').replace(/\bexport /g,'');
vm.runInContext(ts.transpileModule(badgeSource+'\nglobalThis.VideoBadge=DrawnSingleVideoBadge;',{compilerOptions:{target:ts.ScriptTarget.ES2020}}).outputText,ctx);
for(const state of ['play','download','retry','warning','wait']) {
 const badge=new ctx.VideoBadge();badge.bind({},'env',56,state,25);badge.drawBehind({...dc,canvas:{...dc.canvas,save(){},restore(){},translate(){},scale(){}}});
 const before=[allocations,invalidations,strokeWrites];
 for(let i=0;i<1000;i++){badge.bind({},'env',56,state,25);badge.drawBehind({...dc,canvas:{...dc.canvas,save(){},restore(){},translate(){},scale(){}}});}
 assert.deepEqual([allocations,invalidations,strokeWrites],before);
}
console.log('PASS: single-video overlay glyphs and 1000 stable binds/paints allocate no native geometry.');

ctx.COLOR_TEXT_PRIMARY='#222222';
const inlineSource=fs.readFileSync('entry/src/main/ets/pages/chat/DrawnInlineIconDecoration.ets','utf8').replace(/^import\s[\s\S]*?;\r?\n/gm,'').replace(/\bexport /g,'');
vm.runInContext(ts.transpileModule(inlineSource+'\nglobalThis.InlinePlaceholder=DrawnInlineIconDecoration;',{compilerOptions:{target:ts.ScriptTarget.ES2020}}).outputText,ctx);
const placeholder=new ctx.InlinePlaceholder();
for(const [width,height]of [[8,12],[24,24],[48,20],[0,0]]) {
 const transforms=[],canvas={...dc.canvas,save(){},restore(){},translate:(...a)=>transforms.push(['translate',...a]),scale:(...a)=>transforms.push(['scale',...a])};
 placeholder.bind({},'inline',width,height);placeholder.drawBehind({canvas});const before=[allocations,invalidations,strokeWrites];
 for(let i=0;i<1000;i++){placeholder.bind({},'inline',width,height);placeholder.drawBehind({canvas});}
 assert.deepEqual([allocations,invalidations,strokeWrites],before);
 if(width===0)assert.equal(transforms.length,0);else assert.equal(transforms.find(t=>t[0]==='scale')[1],Math.min(width,height)/24);
}
console.log('PASS: inline picture placeholder scales below 24vp and stable painting allocates/reconfigures no native geometry.');
