import assert from 'node:assert/strict';
import vm from 'node:vm';
import {ctx,ui,data,style,group,layoutCounters} from './test-drawn-text-row.mjs';
vm.runInContext('globalThis.drawnFirstStrongRtl=drawnFirstStrongRtl',ctx);
for(const [content,rtl] of [['مرحبا',true],['שלום',true],['123 مرحبا',true],['😀 שלום',true],['abc مرحبا',false],['中文 שלום',false],['\u200f123',true],['\u200eשלום',false],['a\tb',false],['\ufeff中文',false]]){
 assert.equal(ctx.drawnFirstStrongRtl(content),rtl,content);
 const source=new ctx.DrawnRichSourceCache().prepare(content,[]);assert.ok(source);assert.equal(source.content,content);assert.equal(source.rtl,rtl);
 const plan=new ctx.DrawnTextLayouts().prepare(ui,group(content),data,style);assert.ok(plan);
 assert.equal(plan.caption.paragraph.native.style.textDirection,rtl?'RTL':'LTR');
}
const original='مرحبا link 😀';
const entities=[{offset:6,length:4,type:{'@type':'textEntityTypeTextUrl',url:'https://bidi.test'}}];
const source=new ctx.DrawnRichSourceCache().prepare(original,entities);
assert.equal(source.links[0].start,6);assert.equal(source.links[0].end,10);
const engine=new ctx.DrawnTextLayouts(),message=group('a\tb\ufeffc\u202ed',[]),plan=engine.prepare(ui,message,data,style);
const before=layoutCounters();for(let i=0;i<1000;i++)assert.equal(engine.prepare(ui,message,data,style),plan);
assert.deepEqual(layoutCounters(),before);
console.log('PASS: first-strong base direction, preserved UTF-16/control characters and warm caches. Native BiDi visual ordering still needs device validation.');
