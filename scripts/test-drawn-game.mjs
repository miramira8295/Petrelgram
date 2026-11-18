import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import {ctx,load,root,compiled,ui,data,style,group,layoutCounters} from './test-drawn-text-row.mjs';
vm.runInContext('globalThis.gameLayoutFor=gameLayoutFor',ctx);
const gameEntity={offset:0,length:4,type:{'@type':'textEntityTypeTextUrl',url:'https://game.example'}};
const g=group('');Object.assign(g.head,{contentType:'game',rowId:31,gameId:'9',gameTitle:'Game title '.repeat(20),
 gameShortName:'game',gameDescription:'Description '.repeat(20),gameText:'link '.repeat(100),gameTextEntities:[gameEntity],
 photoFileId:23,photoProgress:0,photoPath:''});
const engine=new ctx.DrawnTextLayouts(),plan=engine.prepare(ui,g,data,style),slot=plan.caption.widgets[0],counts=layoutCounters();
assert.equal(slot.widget.kind,'message-game');
const geometry=ctx.gameLayoutFor(slot.widget);
assert.equal(slot.height,geometry.height);assert.ok(geometry.title.heightVp>30);assert.ok(geometry.body.heightVp>40);
assert.equal(geometry.body.source.links[0].url,'https://game.example');
assert.equal(geometry.description,null,'Android shows game text instead of also repeating the static description');
for(let i=0;i<1000;i++)assert.equal(engine.prepare(ui,{...g,head:{...g.head,photoProgress:i%100,photoPath:i%2?'/cover':''}},data,style),plan);
assert.deepEqual(layoutCounters(),counts);
for(let i=0;i<1000;i++)assert.equal(engine.prepare(ui,{...g,head:{...g.head,gameTextEntities:[{...gameEntity}],photoProgress:i%100}},data,style),plan);
assert.deepEqual(layoutCounters(),counts,'equivalent entity snapshots reuse paragraph and complete row plan');
assert.equal(engine.prepare(ui,g,data,{...style,mathRevision:999}),plan,'game geometry needs no native height feedback');
const next=engine.prepare(ui,{...g,head:{...g.head,rowId:32,gameId:'10'}},data,style);assert.notEqual(next.caption.widgets[0].widget,slot.widget);
const crossChat=engine.prepare(ui,g,{...data,chatId:99},style);assert.notEqual(crossChat.caption.widgets[0].widget,slot.widget);
function expectedHeight(p) {
 const blocks=[p.coverHeight,p.title.heightVp];
 if(p.description)blocks.push(p.description.heightVp);
 if(p.body)blocks.push(p.body.heightVp);
 if(p.fallback)blocks.push(p.fallback.heightVp);
 blocks.push(p.buttonHeight,p.footerHeight);
 return blocks.reduce((a,b)=>a+b,0)+(blocks.length-1)*8;
}
for(const content of [{gameDescription:'',gameText:'',gameTextEntities:[]},
 {gameDescription:'',gameText:'short',gameTextEntities:[]},
 {gameDescription:'Description',gameText:'',gameTextEntities:[]},
 {gameDescription:'Description',gameText:'Both texts',gameTextEntities:[]},
 {gameTitle:'',gameShortName:'',gameDescription:'',gameText:'',gameTextEntities:[]}]) {
 const prepared=engine.prepare(ui,{...g,head:{...g.head,...content}},data,style);
 const layout=ctx.gameLayoutFor(prepared.caption.widgets[0].widget);
 assert.equal(layout.height,expectedHeight(layout));
 assert.equal(!!layout.fallback,content.gameDescription===''&&content.gameText==='');
 assert.equal(!!layout.description,content.gameDescription!==''&&content.gameText==='');
 if(content.gameTitle==='')assert.equal(layout.available,false);
}
for(const contentWidth of [100,160,240,400]) {
 const prepared=engine.prepare(ui,g,{...data,contentWidth},style);
 const layout=ctx.gameLayoutFor(prepared.caption.widgets[0].widget);
 assert.equal(layout.height,expectedHeight(layout));assert.ok(layout.body.widthVp<=layout.width);
}
const scaled=engine.prepare({vp2px:n=>n*2,fp2px:n=>n*4},g,data,{...style,environment:'large-font',textEnvironment:'large-font'});
const scaledLayout=ctx.gameLayoutFor(scaled.caption.widgets[0].widget);
assert.ok(scaledLayout.height>geometry.height);assert.ok(scaledLayout.buttonHeight>geometry.buttonHeight);
assert.ok(scaledLayout.footerHeight>geometry.footerHeight);assert.equal(scaledLayout.height,expectedHeight(scaledLayout));
const long=engine.prepare(ui,{...g,head:{...g.head,gameText:'long '.repeat(3000)}},data,style);
assert.ok(long.caption.widgets[0].height>1200,'first published geometry includes full long text');
const wrapper=fs.readFileSync(root+'pages/chat/DrawnGameMessage.ets','utf8');
assert.doesNotMatch(wrapper,/onAreaChange|onMetricsChanged|setPollWidgetHeight|measuredReady/);
const callbacks=new Map();let offs=0;
ctx.progressForOr=(_id,fallback)=>fallback;ctx.subscribeProgress=(id,fn)=>{callbacks.set(id,fn);return()=>offs++;};
load(compiled+'pages/chat/DrawnGameMessage.ts',['DrawnGameMessage']);
const local=Object.assign(Object.create(ctx.DrawnGameMessage.prototype),{msg:g.head,active:true,generation:0,off:null,progress:0});
local.bind();const old=callbacks.get(23);old(40);assert.equal(local.progress,40);
local.msg={...g.head,rowId:32,photoFileId:24,photoProgress:7};local.bind();old(99);assert.equal(local.progress,7);
local.aboutToRecycle();callbacks.get(24)(99);assert.equal(local.progress,7);assert.equal(offs,2);
ctx.Date={now:()=>10000};let timer=null,opens=[],retries=[];
ctx.setTimeout=fn=>{timer=fn;return 1;};ctx.clearTimeout=()=>{timer=null;};
load(compiled+'pages/chat/GameBubble.ts',['GameBubble']);
const game=Object.assign(Object.create(ctx.GameBubble.prototype),{prepared:null,title:'Game',shortName:'game',messageId:1,opening:false,photoActionAtMs:0,openingTimer:-1,onBeforeAction:()=>false,onOpen:id=>opens.push(id),onRetryPhoto:id=>retries.push(id)});
game.openGame();game.retryCover();assert.equal(opens.length,0);assert.equal(retries.length,0);assert.equal(game.opening,false);
game.onBeforeAction=()=>true;game.openGame();game.openGame();assert.deepEqual(opens,[1]);
game.messageId=2;game.onMessageChanged();assert.equal(timer,null);assert.equal(game.opening,false);game.openGame();assert.deepEqual(opens,[1,2]);game.aboutToRecycle();assert.equal(timer,null);
console.log('PASS: game complete first geometry, 1000 cover/entity updates reuse layout, full long text, narrow/font/empty states, owner isolation, stale cover callbacks and actual launch/retry/selection/timer guards.');
// Game formatted text must survive parsing and count-only UI updates.
load(root+'util/formatMsgContent.ets',['formatMsgContent']);
const linkEntity={offset:0,length:4,type:{'@type':'textEntityTypeTextUrl',url:'https://game.example'}};
const formatted={text:'link '.repeat(100),entities:[linkEntity]};
const parsed=ctx.formatMsgContent({content:{'@type':'messageGame',game:{id:9,title:'Game',text:formatted}}});
assert.equal(parsed.gameTextEntities,formatted.entities);
vm.runInContext('globalThis.PollRichSource=PollRichSource',ctx);
vm.runInContext('globalThis.DrawnRichTextLayouts=DrawnRichTextLayouts',ctx);
ctx.chatEnv={appearanceEpoch:0,langEpoch:0};ctx.textMeasureEnvironment={epoch:0};
load(compiled+'pages/chat/DrawnPollText.ts',['DrawnPollText']);
const text=Object.assign(Object.create(ctx.DrawnPollText.prototype),{msg:g.head,content:formatted.text,entities:formatted.entities,boxWidth:200,textSize:11.5,textColor:'#222222',bold:false,revealed:false,metricRevision:0,
 sources:new ctx.PollRichSource(),layouts:new ctx.DrawnRichTextLayouts(),env:ctx.chatEnv,getUIContext:()=>ui,failureLogged:false});
const paragraph=text.plan,textCounts=layoutCounters();
for(let i=0;i<1000;i++){text.msg={...g.head,photoProgress:i%100};text.entities=[{...linkEntity}];assert.equal(text.plan,paragraph);}
assert.deepEqual(layoutCounters(),textCounts);assert.equal(paragraph.source.links[0].url,'https://game.example');
text.content='short';text.entities=[];assert.ok(text.plan.heightVp<paragraph.heightVp,'complete game text has natural height');
const supplied=Object.assign(Object.create(ctx.DrawnPollText.prototype),{preparedLayout:geometry.body,revealed:false,metricRevision:0});
const suppliedCounts=layoutCounters();for(let i=0;i<1000;i++)assert.equal(supplied.plan,geometry.body);
assert.deepEqual(layoutCounters(),suppliedCounts,'child paints prelaid paragraph without another layout');
game.resetTransientState();game.onBeforeAction=()=>true;
const openCount=opens.length;assert.equal(game.claimTextLink(),true);game.openGame();assert.equal(opens.length,openCount,'link cannot also launch game');
game.onBeforeAction=()=>false;assert.equal(game.claimTextLink(),false);
console.log('PASS: full game rich entities and long text, 1000 equivalent updates reuse paragraph, text edits resize, links cannot launch game.');
