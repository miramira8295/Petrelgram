import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import {ctx,load,root,compiled,ui,data,style,group,layoutCounters} from './test-drawn-text-row.mjs';
vm.runInContext('globalThis.giveawayLayoutFor=giveawayLayoutFor;globalThis.DrawnGiveawayTextPainter=DrawnGiveawayTextPainter',ctx);
const g=group('');Object.assign(g.head,{contentType:'giveaway',rowId:61,giveawayState:'active',giveawayWinnerCount:10,
 giveawayPrize:'Prize '.repeat(100),giveawayDescription:'Complete description '.repeat(200),giveawayUnclaimedCount:0,
 giveawayOnlyNewMembers:false,giveawayRefunded:false,giveawaySelectionDate:0,giveawayMessageId:99,giveawayBoostedChatId:7,photoPath:''});
const engine=new ctx.DrawnTextLayouts(),plan=engine.prepare(ui,g,data,style),slot=plan.caption.widgets[0],counts=layoutCounters();
assert.equal(slot.widget.kind,'message-giveaway');
const geometry=ctx.giveawayLayoutFor(slot.widget);
assert.equal(slot.height,geometry.height);assert.ok(geometry.prize.getLineCount()>2,'full prize is no longer truncated at two lines');
assert.ok(geometry.description);assert.ok(slot.height>1200,'complete first geometry has no native measured-height cap');
function expectedHeight(p) {return p.artworkHeight+p.textHeight+p.statsHeight+(p.hasOriginal?p.buttonHeight:0)+9+(p.hasOriginal?36:27);}
assert.equal(geometry.height,expectedHeight(geometry));
const states=['active','prize','winners','completed'];
for(let i=0;i<1000;i++)assert.equal(engine.prepare(ui,{...g,head:{...g.head,giveawayState:states[i%4],giveawayWinnerCount:i+1,
 giveawayUnclaimedCount:i%3,giveawayOnlyNewMembers:!!(i%2),giveawayMessageId:100+i,giveawayRefunded:!!(i%2),photoPath:i%2?'/art':''}},data,style),plan);
assert.deepEqual(layoutCounters(),counts);
assert.equal(engine.prepare(ui,g,data,{...style,mathRevision:999}),plan,'no native size feedback is needed');
const variants=[];
for(let i=0;i<4;i++) {
 const msg={...g.head,giveawayMessageId:i&2?99:0,giveawayWinnerCount:i&1?10:0};
 const p=engine.prepare(ui,{...g,head:msg},data,style),layout=ctx.giveawayLayoutFor(p.caption.widgets[0].widget);
 variants.push(layout);assert.equal(layout.height,expectedHeight(layout));
 assert.equal(layout.hasOriginal,!!(i&2));assert.equal(layout.statsHeight>0,!!(i&1));
 assert.equal(layout.prize,geometry.prize);assert.equal(layout.description,geometry.description);
 for(let j=0;j<5;j++)assert.equal(layout.titles[j],geometry.titles[j]);
}
const variantCounts=layoutCounters();
for(let i=0;i<1000;i++) {
 const index=i%4,msg={...g.head,giveawayMessageId:index&2?99:0,giveawayWinnerCount:index&1?10:0};
 const p=engine.prepare(ui,{...g,head:msg},data,style);
 assert.equal(ctx.giveawayLayoutFor(p.caption.widgets[0].widget),variants[index]);
}
const afterVariants=layoutCounters();
for(const key of ['parseCalls','bodyLayouts','totalLayouts'])assert.equal(afterVariants[key],variantCounts[key],key);
for(const contentWidth of [100,160,240,400]) {
 const p=engine.prepare(ui,g,{...data,contentWidth},style),layout=ctx.giveawayLayoutFor(p.caption.widgets[0].widget);
 assert.equal(layout.height,expectedHeight(layout));assert.ok(layout.prizeY>layout.titleY);assert.ok(layout.descriptionY>layout.prizeY);
}
const scaled=engine.prepare({vp2px:n=>n*2,fp2px:n=>n*4},g,data,{...style,environment:'font-scale-2',textEnvironment:'font-scale-2'});
const scaledLayout=ctx.giveawayLayoutFor(scaled.caption.widgets[0].widget);
assert.ok(scaledLayout.height>geometry.height);assert.ok(scaledLayout.buttonHeight>geometry.buttonHeight);
const empty=engine.prepare(ui,{...g,head:{...g.head,giveawayPrize:' ',giveawayDescription:''}},data,style);
const emptyLayout=ctx.giveawayLayoutFor(empty.caption.widgets[0].widget);assert.equal(emptyLayout.description,null);
const next=engine.prepare(ui,{...g,head:{...g.head,rowId:62}},data,style);assert.notEqual(next.caption.widgets[0].widget,slot.widget);
const crossChat=engine.prepare(ui,g,{...data,chatId:99},style);assert.notEqual(crossChat.caption.widgets[0].widget,slot.widget);
const wrapper=fs.readFileSync(root+'pages/chat/DrawnGiveawayMessage.ets','utf8');
assert.doesNotMatch(wrapper,/onAreaChange|onMetricsChanged|setPollWidgetHeight|measuredReady/);
const painter=new ctx.DrawnGiveawayTextPainter();let invalidations=0;const paints=[];
painter.invalidate=()=>invalidations++;
for(let i=0;i<5;i++)geometry.titles[i].paint=(_canvas,x,y)=>paints.push([`title${i}`,x,y]);
geometry.prize.paint=(_canvas,x,y)=>paints.push(['prize',x,y]);
geometry.description.paint=(_canvas,x,y)=>paints.push(['description',x,y]);
const paintCounts=layoutCounters();
for(let i=0;i<1000;i++){painter.bind(geometry,'active',false);painter.drawBehind({canvas:{}});}
assert.equal(invalidations,1);assert.deepEqual(layoutCounters(),paintCounts);
assert.deepEqual(paints[0],['title1',0,geometry.titleY*geometry.density]);
assert.deepEqual(paints[2],['description',0,geometry.descriptionY*geometry.density]);
for(const [state,refund,index] of [['prize',false,2],['winners',false,3],['completed',false,4],['active',true,0]]) {
 painter.bind(geometry,state,refund);const before=paints.length;painter.drawBehind({canvas:{}});assert.equal(paints[before][0],`title${index}`);
}
assert.deepEqual(layoutCounters(),paintCounts,'state/refund paint changes do not shape text');
painter.bind(null,'',false);const before=paints.length;painter.drawBehind({canvas:{}});assert.equal(paints.length,before);
load(compiled+'pages/chat/DrawnGiveawayMessage.ts',['DrawnGiveawayMessage']);
const local=Object.assign(Object.create(ctx.DrawnGiveawayMessage.prototype),{active:false});local.aboutToAppear();assert.equal(local.active,true);local.aboutToRecycle();assert.equal(local.active,false);
load(compiled+'pages/chat/GiveawayBubble.ts',['GiveawayBubble']);
const opened=[];
const card=Object.assign(Object.create(ctx.GiveawayBubble.prototype),{prepared:null,originalMessageId:99,boostedChatId:7,onBeforeAction:()=>false,onOpenOriginal:(...ids)=>opened.push(ids)});
card.openOriginal();assert.equal(opened.length,0);
card.onBeforeAction=()=>true;card.originalMessageId=100;card.boostedChatId=8;card.openOriginal();assert.deepEqual(opened,[[8,100]]);
card.originalMessageId=0;card.openOriginal();assert.equal(opened.length,1);
Object.assign(card,{state:'active',refunded:false});assert.equal(card.title(),'gw_channel');
card.state='prize';assert.equal(card.title(),'gw_you_won');card.state='winners';assert.equal(card.title(),'gw_results');card.refunded=true;assert.equal(card.title(),'gw_cancelled');
Object.assign(card,{prepared:geometry,state:'prize',refunded:false,description:g.head.giveawayDescription});
assert.equal(card.statusText(),g.head.giveawayDescription,'status retains awarded/returned semantics; full description also lives in the body');
console.log('PASS: giveaway complete first geometry, 1000 state/count/refund updates reuse plan, four bounded geometry variants preserve paragraphs, full prize/description, narrow/font/empty states, local painter and ownership/original-message action guards.');
