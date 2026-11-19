import assert from 'node:assert/strict';
import vm from 'node:vm';
import {ctx,load,root,compiled,ui,data,style,group,layoutCounters} from './test-drawn-text-row.mjs';
ctx.AVATAR_PALETTE=['#112233','#223344','#334455'];ctx.ImageFit={Cover:0,Contain:1};
ctx.DrawnImageReceiver=class {setPixels(p){this.pixels=p;}bind(){return this;}drawFront(){} };
ctx.OneShotFrameCallback=class {constructor(fn){this.fn=fn;} };
load(root+'util/drawnFrameBatch.ets',['DrawnFrameBatch']);
vm.runInContext('globalThis.Audience=DrawnGiveawayAudienceLayout;globalThis.Audiences=DrawnGiveawayAudienceLayouts;globalThis.giveawayLayoutFor=giveawayLayoutFor;',ctx);
let nativeShapes=0;ctx.drawing.RoundRect=class {constructor(rect){this.rect=rect;nativeShapes++;}};
const frames=[],testUi={...ui,postFrameCallback:cb=>frames.push(cb.fn)};
const source={chatIds:[-1,-2],winnerUserIds:Array.from({length:100},(_,i)=>i+1),signature:'audience'};
for(const width of [100,160,260,400]){
 const model=new ctx.Audience(testUi,source,width,'1');assert.equal(model.slots.length,102);assert.ok(model.height>0);
 for(let i=0;i<model.slots.length;i++){
  const s=model.slots[i];assert.ok(s.x>=0&&s.x+s.width<=width+.001);assert.ok(s.y>=0&&s.y+s.height<=model.height+.001);
  assert.equal(model.hit(s.x+s.width/2,s.y+s.height/2),i);
 }
 assert.equal(model.hit(-1,-1),-1);assert.equal(model.hit(NaN,0),-1);
 let paints=0;model.onPaint(()=>paints++);const shapes=nativeShapes;
 for(let i=0;i<100;i++)model.queueName(i,`A long participant name ${i}`);
 assert.equal(frames.length,1,'all metadata changes within a frame share one layout pass');
 frames.shift()();assert.equal(paints,1);assert.equal(nativeShapes-shapes,102,'one new chip shape per member: line loops partition the list');
 const warm=nativeShapes;for(let i=0;i<100;i++)model.queueName(i,`A long participant name ${i}`);assert.equal(frames.length,0);assert.equal(nativeShapes,warm);
 model.queueName(0,'cancelled');model.cancelPending();frames.shift()();assert.notEqual(model.slots[0].name,'cancelled');
}
const layouts=new ctx.Audiences(),model=layouts.prepare(testUi,source,260,'1');
const paintCanvas={save(){},restore(){},translate(){},clipRoundRect(){},attachBrush(){},detachBrush(){},drawRoundRect(){},drawCircle(){}};
const shapeCount=nativeShapes,shapeCounters=layoutCounters();
for(let i=0;i<1000;i++)model.paint({canvas:paintCanvas});
assert.equal(nativeShapes,shapeCount,'warm painting cannot allocate native chip geometry');assert.deepEqual(layoutCounters(),shapeCounters);

for(let i=0;i<1000;i++)assert.equal(layouts.prepare(testUi,source,260,'1'),model);
assert.notEqual(layouts.prepare(testUi,source,160,'1'),model);
// Exercise the actual row preparation: only real height changes replace widget
// geometry, while prize/description paragraphs stay retained.
const g=group('');Object.assign(g.head,{contentType:'giveaway',giveawayState:'active',giveawayPrize:'Prize',giveawayDescription:'Description',giveawayWinnerCount:2,giveawayAudience:{chatIds:[-1,-2],winnerUserIds:[],signature:'c12'},giveawayMessageId:1});
const engine=new ctx.DrawnTextLayouts(),p=engine.prepare(testUi,g,data,style),geometry=ctx.giveawayLayoutFor(p.caption.widgets[0].widget);
assert.ok(geometry.audience);assert.equal(geometry.audienceHeight,geometry.audience.height);
const counts=layoutCounters();for(let i=0;i<1000;i++){geometry.audience.invalidate();assert.equal(engine.prepare(testUi,g,data,style),p);}assert.deepEqual(layoutCounters(),counts);
geometry.audience.queueName(0,'A very long channel name that fills the line');geometry.audience.queueName(1,'Another long channel name');frames.shift()();
const next=engine.prepare(testUi,g,data,style),nextGeometry=ctx.giveawayLayoutFor(next.caption.widgets[0].widget);
assert.equal(nextGeometry.prize,geometry.prize);assert.equal(nextGeometry.description,geometry.description);assert.equal(nextGeometry.audience,geometry.audience);
// Real controller with deterministic peers/files/decoder ownership doubles.
const peerCallbacks=[],fileCallbacks=[],sessions=[];
ctx.watchGiveawayPeer=(id,user,cb)=>{peerCallbacks.push({id,user,cb,off:false});const record=peerCallbacks.at(-1);cb(null);return()=>record.off=true;};
ctx.documentFileId=f=>f?.id??0;ctx.documentFilePath=f=>f?.local?.path??'';
ctx.documentFileState=f=>({path:ctx.documentFilePath(f)});ctx.requestDocumentFile=()=>{};ctx.THUMBNAIL_PRIORITY=1;
ctx.watchDocumentFile=(file,cb)=>{fileCallbacks.push({file,cb,off:false});const record=fileCallbacks.at(-1);return()=>record.off=true;};
ctx.CachedImageSession=class {constructor(publish){this.publish=publish;sessions.push(this);}activate(spec){this.spec=spec;this.active=true;}update(spec){this.spec=spec;}dispose(){this.active=false;} };
load(root+'pages/chat/DrawnGiveawayAudienceController.ets',['DrawnGiveawayAudienceController']);
const c=new ctx.DrawnGiveawayAudienceController(),a=new ctx.Audience(testUi,{chatIds:[-11],winnerUserIds:[12],signature:'a'},260,'1');
c.bind(testUi,a,'chat1:row1');const peerCount=peerCallbacks.length,sessionCount=sessions.length;
for(let i=0;i<1000;i++)c.bind(testUi,a,'chat1:row1');assert.equal(peerCallbacks.length,peerCount);assert.equal(sessions.length,sessionCount);
const oldPeer=peerCallbacks[peerCount-2];oldPeer.cb({name:'Channel',photo:{id:50,local:{path:'/first'}}});
const oldFile=fileCallbacks.at(-1),oldSession=sessions[sessionCount-2];oldSession.publish('pixels A',true,24,24);assert.equal(a.slots[0].receiver.pixels,'pixels A');
const height=a.height;for(let i=0;i<1000;i++)oldSession.publish(`pixels ${i}`,true,24,24);assert.equal(a.height,height,'bitmap arrivals never change height');
const b=new ctx.Audience(testUi,{chatIds:[-21],winnerUserIds:[],signature:'b'},260,'1');c.bind(testUi,b,'chat1:row2');
oldPeer.cb({name:'Wrong old name',photo:{id:55}});oldFile.cb({path:'/wrong'});oldSession.publish('wrong pixels',true,24,24);
assert.equal(b.slots[0].receiver.pixels,undefined);assert.equal(oldPeer.off,true);assert.equal(oldFile.off,true);
c.bind(testUi,a,'chat1:row1');const oldReceiver=a.slots[0].receiver.pixels;oldSession.publish('ABA stale',true,24,24);assert.equal(a.slots[0].receiver.pixels,oldReceiver);
c.dispose();assert.ok(peerCallbacks.every(r=>r.off));assert.ok(fileCallbacks.every(r=>r.off));
console.log('PASS: Android-style chip wrapping/centering and hit indices, O(N) partitioned geometry, per-frame name coalescing, O(1) warm prepares, retained parent text, paint-only pixels, subscriptions/decode cancellation and A/B/A reuse.');

load(compiled+'pages/chat/DrawnGiveawayAudience.ts',['DrawnGiveawayAudience']);
const activated=[],component=Object.assign(Object.create(ctx.DrawnGiveawayAudience.prototype),{model:a,ownerKey:'chat1:row1',attached:true,generation:2,touchGeneration:2,onActivate:(id,user)=>activated.push([id,user])});
const oldClick=component.pointerClick(),oldSemantic=component.semanticClick(0);
component.model=b;component.ownerKey='chat1:row2';component.generation=3;component.touchGeneration=3;
oldClick({x:1,y:1});oldSemantic();assert.equal(activated.length,0,'old pointer/semantic callbacks cannot activate a reused row');
const s=b.slots[0];component.pointerClick()({x:s.x+s.width/2,y:s.y+s.height/2});assert.deepEqual(activated,[[-21,false]]);
component.attached=false;component.pointerClick()({x:s.x+s.width/2,y:s.y+s.height/2});assert.equal(activated.length,1);
console.log('PASS: compiled audience pointer/semantic ownership, correct peer activation and detached guard.');
