import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
const imported=await import(process.env.TYPESCRIPT_MODULE||'typescript'),ts=imported.default||imported;
const shapes=new Map(),paints=[],styles=[];
let invalidations=0;
class Units {density=1;prepare(ui){this.density=ui.density??1;return this;}fp2px(size){return size*this.density;} }
class Builder {constructor(options){this.options=options;styles.push(options);}addText(content){this.content=content;}build(){const content=this.content,font=this.options.textStyle.fontSize;shapes.set(content,(shapes.get(content)||0)+1);return {layoutSync(w){this.width=w;},getHeight(){return font*1.2;},getLongestLine(){return content.length*5;},updateColor(c){this.color=c;},paint(_c,x,y){paints.push({content,x,y});}};} }
const ctx=vm.createContext({DrawModifier:class{invalidate(){invalidations++;}},DrawnTextUnits:Units,drawnFirstStrongRtl:()=>false,drawnColor:c=>c,text:{ParagraphBuilder:Builder,FontCollection:{getGlobalInstance(){}},TextDirection:{RTL:1,LTR:0},TextAlign:{LEFT:0,CENTER:1},WordBreak:{BREAK_WORD:1},FontWeight:{W400:400,W500:500}}});
const source=fs.readFileSync('entry/src/main/ets/pages/chat/DrawnMediaText.ets','utf8').replace(/^import\s[\s\S]*?;\r?\n/gm,'').replace(/\bexport /g,'');
vm.runInContext(ts.transpileModule(source+'\nglobalThis.Layouts=DrawnMediaTexts;globalThis.Painter=DrawnMediaTextPainter;',{compilerOptions:{target:ts.ScriptTarget.ES2020}}).outputText,ctx);
const layouts=new ctx.Layouts(),painter=new ctx.Painter(),ui={density:1};
const prepare=(status,color='primary',width=140,env='1')=>layouts.prepare(ui,env,width,'stable filename',14.5,color,status,11,'secondary',2,true,4,48);
const p=prepare('initial');painter.bind(p);painter.drawBehind({canvas:{}});assert.equal(p.height,48);assert.equal(paints[0].content,'stable filename');assert.equal(paints[1].content,'initial');assert.ok(paints[1].y>paints[0].y);
for(let i=0;i<1000;i++){assert.equal(prepare('initial'),p);painter.bind(p);}
assert.equal(shapes.get('stable filename'),1);assert.equal(shapes.get('initial'),1);assert.equal(invalidations,1);
for(let i=0;i<1000;i++)painter.bind(prepare(`progress ${i}`));
assert.equal(shapes.get('stable filename'),1,'progress cannot reshape a filename');
const before=shapes.get('stable filename');const recolored=prepare('progress 999','changed');assert.equal(shapes.get('stable filename'),before);painter.bind(recolored);assert.equal(recolored.primary.paragraph.color,'changed');
prepare('progress 999','changed',100);assert.equal(shapes.get('stable filename'),before+1,'real width change reshapes');
prepare('progress 999','changed',100,'new-font-env');assert.equal(shapes.get('stable filename'),before+2);
const reused=layouts.prepare(ui,'1',70,'new message',15,'primary');painter.bind(reused);paints.length=0;painter.drawBehind({canvas:{}});assert.equal(paints.length,1);assert.equal(paints[0].content,'new message');assert.equal(reused.secondary,null,'reuse cannot retain former status label');
console.log('PASS: independent media text caches, 1000 status updates without title reshaping, retained color updates, width/font invalidation, measured pair height, paint positions and reuse reset.');

export { ctx,ui,shapes,paints,styles };
