import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import {ctx,ui,shapes,paints} from './test-drawn-media-text.mjs';
const imported=await import(process.env.TYPESCRIPT_MODULE||'typescript'),ts=imported.default||imported;
let allocations=0;
class Paint {constructor(){allocations++;}setAntiAlias(){}setCapStyle(){}setJoinStyle(){}setStrokeWidth(){}setColor(){} }
class Path {constructor(){allocations++;}reset(){}moveTo(){}lineTo(){}cubicTo(){}close(){} }
class RoundRect {constructor(rect,x,y){allocations++;this.rect=rect;this.x=x;this.y=y;} }
Object.assign(ctx,{drawing:{Brush:Paint,Pen:Paint,Path,RoundRect,CapStyle:{ROUND_CAP:1},JoinStyle:{ROUND_JOIN:1}},ColorMetrics:{resourceColor:()=>({alpha:255,red:1,green:2,blue:3})}});
function load(name,exports){let s=fs.readFileSync('entry/src/main/ets/pages/chat/'+name+'.ets','utf8').split('@ComponentV2')[0].replace(/^import\s[\s\S]*?;\r?\n/gm,'').replace(/\bexport /g,'');vm.runInContext(ts.transpileModule(s+exports.map(n=>`\nglobalThis.${n}=${n};`).join(''),{compilerOptions:{target:ts.ScriptTarget.ES2020}}).outputText,ctx);}
load('DrawnTextLine',['DrawnTextLineCache']);load('DrawnMediaControl',['DrawnMediaControl']);load('DrawnMediaRetry',['DrawnRetryDecoration']);
const p=new ctx.DrawnRetryDecoration(),dc={canvas:new Proxy({}, {get:()=>()=>{}})};
const bind=(content='retry',width=100,env='env',color='#FFFFFF',d=1)=>p.bind({...ui,density:d},env,content,width,17,7,7,'#80000000',color);
bind();p.drawBehind(dc);const original=allocations,before=new Map(shapes);
for(let i=0;i<1000;i++){bind();p.drawBehind(dc);}assert.equal(allocations,original);assert.deepEqual(shapes,before);
bind('long translated retry label',40);assert.ok(p.width<=40);assert.ok(p.height>17);
bind('',40);paints.length=0;p.drawBehind(dc);assert.equal(paints.length,0,'icon-only reuse clears old label');
bind('new message',100);paints.length=0;p.drawBehind(dc);assert.equal(paints.at(-1).content,'new message');
const count=shapes.get('new message');bind('new message',100,'env','#FF0000');assert.equal(shapes.get('new message'),count,'recolor never reshapes');
bind('new message',100,'font');assert.equal(shapes.get('new message'),count+1);bind('new message',100,'density','#FF0000',2);assert.equal(shapes.get('new message'),count+2);
console.log('PASS: shared retry decoration, 1000 stable no-allocation/no-shape binds/paints, bounded localization, icon-only reuse, recolor and font/density changes.');
