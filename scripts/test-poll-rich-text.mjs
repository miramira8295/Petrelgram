import assert from 'node:assert/strict';
import vm from 'node:vm';
import fs from 'node:fs';
import {ctx,load,root,compiled,ui,group,layoutCounters} from './test-drawn-text-row.mjs';
vm.runInContext('globalThis.PollRichSource=PollRichSource',ctx);
load(root+'util/formatMsgContent.ets',['formatMsgContent']);
const bold={offset:0,length:4,type:{'@type':'textEntityTypeBold'}};
const link={offset:5,length:4,type:{'@type':'textEntityTypeTextUrl',url:'https://example.org'}};
const description={text:'Bold link',entities:[bold,link]};
const explanation={text:'Long explanation '.repeat(100),entities:[bold]};
const parsed=ctx.formatMsgContent({content:{'@type':'messagePoll',description,poll:{id:1,question:{text:'Q',entities:[bold]},options:[{text:{text:'Bold link',entities:[bold,link]}}],type:{'@type':'pollTypeQuiz',explanation}}}});
assert.equal(parsed.pollDescriptionEntities,description.entities);
assert.equal(parsed.pollQuestionEntities[0],bold);
assert.equal(parsed.pollOptions[0].entities[1],link);
assert.equal(parsed.pollExplanationEntities,explanation.entities);
const cache=new ctx.PollRichSource(),source=cache.prepare(description.text,description.entities),counts=layoutCounters();
assert.ok(source);assert.equal(source.links[0].url,'https://example.org');
for(let i=0;i<1000;i++)assert.equal(cache.prepare(description.text,JSON.parse(JSON.stringify(description.entities))),source);
assert.deepEqual(layoutCounters(),counts,'equivalent server entity snapshots do not reparse');
const changed=cache.prepare(description.text,[bold,{...link,type:{'@type':'textEntityTypeTextUrl',url:'https://different.org'}}]);
assert.notEqual(changed,source);assert.equal(changed.links[0].url,'https://different.org');
ctx.chatEnv={appearanceEpoch:0,langEpoch:0};ctx.textMeasureEnvironment={epoch:0};
load(compiled+'pages/chat/DrawnPollText.ts',['DrawnPollText']);
vm.runInContext('globalThis.DrawnRichTextLayouts=DrawnRichTextLayouts',ctx);
let called=0;
const block=Object.assign(Object.create(ctx.DrawnPollText.prototype),{msg:group('').head,content:description.text,entities:description.entities,boxWidth:200,textSize:13.5,revealed:false,metricRevision:0,
 textColor:'#222222',bold:false,sources:new ctx.PollRichSource(),layouts:new ctx.DrawnRichTextLayouts(),env:ctx.chatEnv,getUIContext:()=>ui,onBeforeLink:()=>false,onLink:()=>called++,failureLogged:false});
const plan=block.plan,before=layoutCounters();
for(let i=0;i<1000;i++){block.msg={...block.msg,pollTotalVoterCount:i};assert.equal(block.plan,plan);}
assert.deepEqual(layoutCounters(),before);
block.activate(source.links[0]);assert.equal(called,0);block.onBeforeLink=()=>true;block.activate(source.links[0]);assert.equal(called,1);
block.content=explanation.text;block.entities=explanation.entities;assert.ok(block.plan.heightVp>plan.heightVp);
console.log('PASS: poll description/explanation entities survive TD parsing; 1000 equivalent arrays reuse source; 1000 results reuse layout; URL edits invalidate, selection guards links, full explanation grows.');

const store=fs.readFileSync(root+'store/MessageStore.ets','utf8');
const updatePoll=store.slice(store.indexOf('  private onPoll('),store.indexOf('  private onPoll(')+3200);
assert.doesNotMatch(updatePoll,/next\.pollDescription(?:Entities)?\s*=/,'global results must preserve message-level description');

const titleSource=cache.prepare('Title',[bold],true),titleCounts=layoutCounters();
for(let i=0;i<1000;i++)assert.equal(cache.prepare('Title',[{...bold}],true),titleSource);
assert.deepEqual(layoutCounters(),titleCounts);
assert.notEqual(cache.prepare('Title',[bold],false),titleSource,'title base bold is part of source identity');
load(root+'util/pollDraftState.ets',['PollDraftSync','summarizePollOptions']);
load(root+'util/pollOptionState.ets',['pollOptionState']);
load(compiled+'pages/chat/PollBubble.ts',['PollBubble']);
let timerCallback=null,votes=0;
ctx.setTimeout=callback=>{timerCallback=callback;return 1;};ctx.clearTimeout=()=>{timerCallback=null;};
const poll=Object.assign(Object.create(ctx.PollBubble.prototype),{msg:{id:1,rowId:1,pollId:'x',pollQuestion:'Q',pollOptions:[{text:'option',isChosen:false,isBeingChosen:false}],pollVotePending:false,pollVoteError:'',pollCloseDate:0,pollIsClosed:false,pollAllowMultiple:false,pollIsQuiz:false},
 context:{gestureClaimed:false},actions:{onPollVote:()=>votes++},onBeforeAction:()=>true,decorations:[],nowSec:0,draftIds:[],draftChanged:false,richLinkClaimed:false,richLinkTimer:-1});
poll.aboutToAppear();assert.equal(poll.claimTextLink(),true);poll.toggleOption(0);assert.equal(votes,0,'link dispatch cannot also vote');
timerCallback();poll.toggleOption(0);assert.equal(votes,1,'subsequent keyboard/pointer vote is not stuck');
assert.equal(poll.claimTextLink(),true);poll.aboutToRecycle();assert.equal(timerCallback,null);assert.equal(poll.richLinkClaimed,false);
console.log('PASS: poll question/option entities, cached title bold, same-dispatch link/vote isolation and timer cleanup.');
