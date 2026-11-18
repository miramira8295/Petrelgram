import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import {ctx,load,root,compiled,ui,data,style,group,layoutCounters} from './test-drawn-text-row.mjs';
const g=group('poll caption');
Object.assign(g.head,{contentType:'poll',pollId:'poll1',rowId:91,pollQuestion:'Question',pollQuestionEntities:[],pollDescription:'Description',pollDescriptionEntities:[],pollExplanation:'Explanation '.repeat(30),pollExplanationEntities:[],pollVoteError:'',pollIsQuiz:false,pollIsClosed:false,pollAllowMultiple:false,pollVotePending:false,pollCloseDate:0,
 pollOptions:[{text:'one',entities:[],isChosen:false,isBeingChosen:false},{text:'long option '.repeat(30),entities:[],isChosen:false,isBeingChosen:false}]});
vm.runInContext('globalThis.pollLayoutFor=pollLayoutFor;globalThis.PollRichSource=PollRichSource;globalThis.DrawnRichTextLayouts=DrawnRichTextLayouts',ctx);
const engine=new ctx.DrawnTextLayouts(),p=engine.prepare(ui,g,data,style),slot=p.caption.widgets[0],layout=ctx.pollLayoutFor(slot.widget);
assert.equal(slot.widget.kind,'message-poll');assert.equal(slot.height,layout.height);
assert.ok(layout.optionHeights[1]>layout.optionHeights[0]);assert.equal(layout.showSubmit,false);assert.equal(layout.explanation,null);
const counts=layoutCounters();
for(let i=0;i<1000;i++) {
 const message={...g.head,pollTotalVoterCount:i,pollVotePending:!!(i%2),pollOptions:g.head.pollOptions.map(o=>({...o,entities:[],voterCount:i,votePercentage:i%100}))};
 assert.equal(engine.prepare(ui,{...g,head:message},data,style),p);
}
assert.deepEqual(layoutCounters(),counts,'count-only snapshots do not parse/shape again');
assert.equal(engine.prepare(ui,g,data,{...style,mathRevision:999}),p,'no native size feedback revision needed');
const multi={...g,head:{...g.head,pollAllowMultiple:true}};
const multiPlan=engine.prepare(ui,multi,data,style),multiLayout=ctx.pollLayoutFor(multiPlan.caption.widgets[0].widget);
assert.equal(multiLayout.showSubmit,true);assert.ok(multiLayout.height>layout.height);
const pending=engine.prepare(ui,{...multi,head:{...multi.head,pollVotePending:true}},data,style);
assert.equal(ctx.pollLayoutFor(pending.caption.widgets[0].widget).showSubmit,false);
const closed=engine.prepare(ui,{...multi,head:{...multi.head,pollIsClosed:true}},data,style);
const closedLayout=ctx.pollLayoutFor(closed.caption.widgets[0].widget);assert.equal(closedLayout.showSubmit,false);assert.ok(closedLayout.explanation);
assert.equal(closedLayout.question,layout.question);assert.equal(closedLayout.options[1],layout.options[1]);
const expired=engine.prepare(ui,{...multi,head:{...multi.head,pollCloseDate:99999}},data,{...style,pollExpired:true});
assert.equal(ctx.pollLayoutFor(expired.caption.widgets[0].widget).showExplanation,true);
const error=engine.prepare(ui,{...g,head:{...g.head,pollVoteError:'Error '.repeat(100)}},data,style);
const errorLayout=ctx.pollLayoutFor(error.caption.widgets[0].widget);assert.ok(errorLayout.error);assert.ok(errorLayout.error.paragraph.getLineCount()<=3);
function expectedHeight(plan) {
 const blocks=[plan.headerHeight,plan.question.heightVp];
 if(plan.description)blocks.push(plan.description.heightVp+6);
 blocks.push(plan.unavailable?Math.max(17,plan.unavailable.heightVp)+18:plan.optionHeights.reduce((a,b)=>a+b,0)+Math.max(0,plan.options.length-1)*6);
 if(plan.showSubmit)blocks.push(plan.submitHeight);
 if(plan.explanation)blocks.push(Math.max(15,plan.explanation.heightVp)+14);
 blocks.push(plan.error?Math.max(14,plan.error.heightVp)+10:plan.footerHeight);
 return blocks.reduce((a,b)=>a+b,0)+(blocks.length-1)*8;
}
for(const geometry of [layout,multiLayout,closedLayout,errorLayout])assert.equal(geometry.height,expectedHeight(geometry));
const unavailable=engine.prepare(ui,{...g,head:{...g.head,pollOptions:[]}},data,style);
const unavailableLayout=ctx.pollLayoutFor(unavailable.caption.widgets[0].widget);
assert.ok(unavailableLayout.unavailable);assert.equal(unavailableLayout.height,expectedHeight(unavailableLayout));
const scaledUi={vp2px:n=>n*2,fp2px:n=>n*4};
const scaled=engine.prepare(scaledUi,g,data,{...style,environment:'font-scale-2',textEnvironment:'font-scale-2'});
const scaledLayout=ctx.pollLayoutFor(scaled.caption.widgets[0].widget);
assert.ok(scaledLayout.height>layout.height,'font scale participates in the first full geometry');
assert.ok(scaledLayout.headerHeight>layout.headerHeight);assert.ok(scaledLayout.footerHeight>layout.footerHeight);
assert.equal(scaledLayout.height,expectedHeight(scaledLayout));
const long={...g,head:{...g.head,pollQuestion:'Question '.repeat(1000)}};
const longPlan=engine.prepare(ui,long,data,style);assert.ok(longPlan.caption.widgets[0].height>1200,'full first plan has no 640vp/native cap');
for(const width of [160,240,400]) {
 const plan=engine.prepare(ui,g,{...data,contentWidth:width},style),geometry=ctx.pollLayoutFor(plan.caption.widgets[0].widget);
 assert.ok(geometry.width>0);assert.ok(geometry.height>0);assert.ok(geometry.options.every(t=>t.widthVp<=geometry.width));
}
const other=engine.prepare(ui,{...g,head:{...g.head,rowId:92,pollId:'poll2'}},data,style);assert.notEqual(other.caption.widgets[0].widget,slot.widget);
const crossChat=engine.prepare(ui,g,{...data,chatId:data.chatId+1},style);assert.notEqual(crossChat.caption.widgets[0].widget,slot.widget);
const deadlineRow=Object.create(ctx.DrawnMessageRow.prototype);
ctx.Date.now=()=>1000;
Object.defineProperty(deadlineRow,'rowGroup',{value:{head:{...g.head,pollCloseDate:2}},configurable:true});
deadlineRow.nowSec=1;assert.equal(deadlineRow.pollGeometryExpired,false);
deadlineRow.nowSec=2;assert.equal(deadlineRow.pollGeometryExpired,true);
Object.defineProperty(deadlineRow,'rowGroup',{value:{head:{...g.head,contentType:'text'}},configurable:true});
Object.defineProperty(deadlineRow,'nowSec',{get(){throw new Error('ordinary messages must not subscribe to the poll clock');}});
assert.equal(deadlineRow.pollGeometryExpired,false);
load(compiled+'pages/chat/DrawnPollText.ts',['DrawnPollText']);
const text=Object.assign(Object.create(ctx.DrawnPollText.prototype),{preparedLayout:layout.question,revealed:false,metricRevision:0});
const paintCounts=layoutCounters();for(let i=0;i<1000;i++)assert.equal(text.plan,layout.question);assert.deepEqual(layoutCounters(),paintCounts,'child consumes the exact prelaid paragraph without measuring');
const wrapper=fs.readFileSync(root+'pages/chat/DrawnPollMessage.ets','utf8');
assert.doesNotMatch(wrapper,/onAreaChange|setPollWidgetHeight|onMetricsChanged|measuredReady/);
console.log('PASS: first poll plan has complete geometry, 1000 results reuse text and plan, pending/closed/expired/error geometry, long content, narrow widths, ownership and zero-measure paragraph handoff.');
