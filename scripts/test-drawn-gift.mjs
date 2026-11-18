import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import {ctx,load,root,compiled,ui,data,style,group,layoutCounters} from './test-drawn-text-row.mjs';
vm.runInContext('globalThis.giftLayoutFor=giftLayoutFor;globalThis.DrawnGiftTextPainter=DrawnGiftTextPainter',ctx);
const g=group('gift note https://example.org');Object.assign(g.head,{contentType:'gift',rowId:51,giftKind:'code',
 giftTitle:'Premium gift '.repeat(10),giftValue:'12 months',giftCode:'CODE',giftRefunded:false,
 photoFileId:23,photoProgress:0,photoPath:''});
const engine=new ctx.DrawnTextLayouts(),plan=engine.prepare(ui,g,data,style),slot=plan.caption.widgets[0],counts=layoutCounters();
assert.equal(slot.widget.kind,'message-gift');assert.equal(plan.caption.source.blocks[1].source.content,g.head.text);
const geometry=ctx.giftLayoutFor(slot.widget);
assert.equal(slot.height,geometry.height);assert.ok(geometry.title.getLineCount()>2,'complete title is prelaid without the former two-line truncation');
assert.equal(geometry.height,geometry.artworkHeight+geometry.textHeight+geometry.footerHeight+16);
assert.equal(geometry.textHeight,geometry.title.getHeight()/geometry.density+8+geometry.value.getHeight()/geometry.density);
for(let i=0;i<1000;i++)assert.equal(engine.prepare(ui,{...g,head:{...g.head,giftKind:i%2?'code':'stars',giftCode:`CODE${i}`,
 giftRefunded:!!(i%2),giftStatus:`status${i}`,photoProgress:i%100,photoPath:i%2?'/gift':''}},data,style),plan);
assert.deepEqual(layoutCounters(),counts);
assert.equal(engine.prepare(ui,g,data,{...style,mathRevision:999}),plan,'gift geometry needs no native area feedback');
const noCode=engine.prepare(ui,{...g,head:{...g.head,giftCode:''}},data,style),noCodeLayout=ctx.giftLayoutFor(noCode.caption.widgets[0].widget);
assert.equal(noCodeLayout.hasCode,false);assert.ok(noCodeLayout.height<geometry.height);
assert.equal(noCodeLayout.title,geometry.title);assert.equal(noCodeLayout.value,geometry.value,'button changes do not remeasure static text');
const empty=engine.prepare(ui,{...g,head:{...g.head,giftTitle:' ',giftValue:' ',giftCode:''}},data,style);
const emptyLayout=ctx.giftLayoutFor(empty.caption.widgets[0].widget);
assert.equal(emptyLayout.titleText,'gift_regular_title');assert.equal(emptyLayout.value,null);
assert.equal(emptyLayout.textHeight,emptyLayout.title.getHeight()/emptyLayout.density);
const next=engine.prepare(ui,{...g,head:{...g.head,rowId:52}},data,style);assert.notEqual(next.caption.widgets[0].widget,slot.widget);
const crossChat=engine.prepare(ui,g,{...data,chatId:99},style);assert.notEqual(crossChat.caption.widgets[0].widget,slot.widget);
for(const contentWidth of [100,160,240,400]) {
 const prepared=engine.prepare(ui,g,{...data,contentWidth},style),layout=ctx.giftLayoutFor(prepared.caption.widgets[0].widget);
 assert.equal(layout.height,layout.artworkHeight+layout.textHeight+layout.footerHeight+16);
 assert.ok(layout.copyWidth<=layout.width*.55);assert.ok(layout.footerHeight>=layout.statusHeight+9);
 assert.ok(layout.footerHeight>=layout.copyHeight+9);
 assert.ok(layout.valueY>=layout.titleY+layout.title.getHeight()/layout.density);
}
const scaled=engine.prepare({vp2px:n=>n*2,fp2px:n=>n*4},g,data,{...style,environment:'font-scale-2',textEnvironment:'font-scale-2'});
const scaledLayout=ctx.giftLayoutFor(scaled.caption.widgets[0].widget);
assert.ok(scaledLayout.height>geometry.height);assert.ok(scaledLayout.footerHeight>geometry.footerHeight);
const long=engine.prepare(ui,{...g,head:{...g.head,giftTitle:'long gift title '.repeat(1000)}},data,style);
assert.ok(long.caption.widgets[0].height>1200,'first geometry includes the complete long title');
const wrapper=fs.readFileSync(root+'pages/chat/DrawnGiftMessage.ets','utf8');
assert.doesNotMatch(wrapper,/onAreaChange|setPollWidgetHeight|onMetricsChanged|measuredReady/);
const painter=new ctx.DrawnGiftTextPainter();let invalidations=0;
painter.invalidate=()=>invalidations++;
const resolved=[],painted=[],resolve=ctx.ColorMetrics.resourceColor;
ctx.ColorMetrics.resourceColor=color=>{resolved.push(color);return resolve(color);};
geometry.title.paint=(_canvas,x,y)=>painted.push(['title',x,y]);geometry.value.paint=(_canvas,x,y)=>painted.push(['value',x,y]);
painter.bind(geometry,false,'pink');assert.deepEqual(resolved,['black','pink']);
const colorCount=resolved.length,paintCounts=layoutCounters();
for(let i=0;i<1000;i++){painter.bind(geometry,false,'pink');painter.drawBehind({canvas:{}});}
assert.equal(invalidations,1);assert.equal(resolved.length,colorCount);assert.deepEqual(layoutCounters(),paintCounts);
assert.deepEqual(painted[0],['title',0,geometry.titleY*geometry.density]);
assert.deepEqual(painted[1],['value',0,geometry.valueY*geometry.density]);
painter.bind(geometry,true,'gray');assert.equal(invalidations,2);assert.equal(resolved.at(-2),'gray');
assert.deepEqual(layoutCounters(),paintCounts,'refund changes paint colors without reshaping');
painter.bind(null,false,'');const paintedBefore=painted.length;painter.drawBehind({canvas:{}});assert.equal(painted.length,paintedBefore);
ctx.ColorMetrics.resourceColor=resolve;
const callbacks=new Map();let offs=0;
ctx.progressForOr=(_id,fallback)=>fallback;ctx.subscribeProgress=(id,fn)=>{callbacks.set(id,fn);return()=>offs++;};
load(compiled+'pages/chat/DrawnGiftMessage.ts',['DrawnGiftMessage']);
const local=Object.assign(Object.create(ctx.DrawnGiftMessage.prototype),{msg:g.head,active:true,generation:0,off:null,progress:0});
local.bind();const old=callbacks.get(23);old(40);assert.equal(local.progress,40);
local.msg={...g.head,rowId:52,photoFileId:24,photoProgress:7};local.bind();old(99);assert.equal(local.progress,7);
local.aboutToRecycle();callbacks.get(24)(99);assert.equal(local.progress,7);assert.equal(offs,2);
load(compiled+'pages/chat/GiftBubble.ts',['GiftBubble']);
const copied=[],retried=[];
const card=Object.assign(Object.create(ctx.GiftBubble.prototype),{messageId:1,code:'OLD',onBeforeAction:()=>false,onCopyCode:code=>copied.push(code),onRetryPhoto:id=>retried.push(id)});
card.copyCode();card.retryPhoto();assert.equal(copied.length,0);assert.equal(retried.length,0);
card.onBeforeAction=()=>true;card.messageId=2;card.code='NEW';card.copyCode();card.retryPhoto();assert.deepEqual(copied,['NEW']);assert.deepEqual(retried,[2]);
card.code='';card.copyCode();assert.equal(copied.length,1);
load(root+'util/formatMsgContent.ets',['formatMsgContent']);
const entity={offset:0,length:4,type:{'@type':'textEntityTypeBold'}};
for(const type of ['messageGiftedPremium','messagePremiumGiftCode','messageGift']) {
 const result=ctx.formatMsgContent({content:{'@type':type,text:{text:'note',entities:[entity]},gift:{}}});
 assert.equal(result.entities[0],entity,`${type} retains note entities`);
}
console.log('PASS: gift complete first geometry, 1000 status/progress/kind/code updates retain plan, code visibility/font/narrow/full title geometry, shared paragraphs, paint-only refund, stale artwork callbacks, copy/retry ownership and full TD note entities.');
