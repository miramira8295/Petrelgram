import assert from 'node:assert/strict';
import fs from 'node:fs';
import './test-drawn-single-media.mjs';
import {ctx,load,root,compiled,ui,data,style,group,layoutCounters} from './test-drawn-text-row.mjs';
load(root+'util/inlineButtonKey.ets',['InlineKeyboardKeys','inlineButtonKey','inlineButtonRowKey']);
// Structural keyboard cache: nested loops visit each actual button once, no
// Cartesian product. Repeated prepares must not even iterate the input rows.
const button=(i)=>({text:`button|${i}`,url:`https://example.org/${i}`,callbackData:'',webAppUrl:'',isGame:false,style:''});
const rows=Array.from({length:50},(_,i)=>Array.from({length:i%7+1},(_,j)=>button(i*10+j)));
const keys=new ctx.InlineKeyboardKeys(),keyPlan=keys.prepare(rows);
for(let i=0;i<rows.length;i++){assert.equal(keyPlan.rows[i],ctx.inlineButtonRowKey(i,rows[i]));for(let j=0;j<rows[i].length;j++)assert.equal(keyPlan.buttons[i][j],ctx.inlineButtonKey(i,j,rows[i][j]));}
let scans=0;const tracked=new Proxy(rows,{get(t,k){if(k===Symbol.iterator||/^\d+$/.test(String(k)))scans++;return Reflect.get(t,k);}});
const saved=keys.prepare(tracked),initialScans=scans;for(let i=0;i<1000;i++)assert.equal(keys.prepare(tracked),saved);assert.equal(scans,initialScans);
assert.equal(keys.prepare([]).rows.length,0);

// Compare queue semantics against original array implementation under 20000
// deterministic mixed acquire/wait/cancel/release/reentrant-grant operations.
// AnimationSlotPool is already loaded by the dynamic-avatar harness.
const NewPool=ctx.AnimationSlotPool || (await import('node:vm')).runInContext('AnimationSlotPool',ctx);
class OldPool {constructor(c){this.c=c;this.live=0;this.waiters=[];}liveCount(){return this.live;}waitingCount(){return this.waiters.length;}tryAcquire(){if(this.live>=this.c)return false;this.live++;return true;}wait(cb){const f=()=>cb();this.waiters.push(f);return()=>{const i=this.waiters.indexOf(f);if(i>=0)this.waiters.splice(i,1);};}releaseQuietly(){if(this.live>0)this.live--;}release(){if(this.live<=0)return;const f=this.waiters.pop();if(f)f();else this.live--;}}
const old=new OldPool(2),next=new NewPool(2),oldLog=[],nextLog=[],cancels=[];let seed=383838;
const random=n=>{seed=(Math.imul(seed,1664525)+1013904223)>>>0;return seed%n;};
for(let i=0;i<20000;i++){
 switch(random(5)){
  case 0:assert.equal(next.tryAcquire(),old.tryAcquire());break;
  case 1:{const reentrant=i%17===0;const a=old.wait(()=>{oldLog.push(i);if(reentrant)old.release();}),b=next.wait(()=>{nextLog.push(i);if(reentrant)next.release();});cancels.push([a,b]);break;}
  case 2:if(cancels.length){const pair=cancels[random(cancels.length)];pair[0]();pair[1]();}break;
  case 3:old.release();next.release();break;
  case 4:old.releaseQuietly();next.releaseQuietly();break;
 }
 assert.equal(next.liveCount(),old.liveCount());assert.equal(next.waitingCount(),old.waitingCount());
}
assert.deepEqual(nextLog,oldLog);
const stress=new NewPool(1);stress.tryAcquire();const cancel=Array.from({length:20000},()=>stress.wait(()=>{}));
for(const f of cancel)f();assert.equal(stress.waitingCount(),0);assert.equal(stress.tail,null);stress.release();assert.equal(stress.liveCount(),0);
console.log('PASS: keyboard keys preserve original signatures and skip 1000 repeat scans; 20000 differential queue operations plus 20000 cancellations preserve LIFO/ownership without tombstones.');

// Reply media reserves 32vp + 6vp gap, regardless of the number of dice layers.
const quoted=group('short caption');Object.assign(quoted.head,{replyToMessageId:2,replySenderName:'name',replyText:'quoted body',replyThumbPath:'/thumb'});
const textLayouts=new ctx.DrawnTextLayouts();const p=textLayouts.prepare(ui,quoted,data,style);
assert.equal(p.quote.mediaWidthPx,76);assert.ok(p.quoteRect.width>=p.quote.widthPx/2);
const counts=layoutCounters(),body=p.caption;
const changed={...quoted,head:{...quoted.head,replyThumbPath:'/other',replyDiceLayers:['/a','/b','/c','/d','/e'],inlineButtons:rows}};
const q=textLayouts.prepare(ui,changed,data,style);assert.equal(q,p);assert.equal(q.caption,body);assert.deepEqual(layoutCounters(),counts);
const small=textLayouts.prepare(ui,group('x'),{...data,isGroup:true},{...style,fontSize:10});assert.equal(small.height,38);assert.ok(small.bubbleY>0);assert.equal(small.avatar.y,0);assert.ok(small.footerY+small.statusSize<=38);
// Actual keyboard handlers: same-label different target, immutable equivalent
// arrays, A/B/A and detached events; only O(1) indexed current-button lookup.
load(compiled+'pages/chat/BubbleInlineKeyboard.ts',['BubbleInlineKeyboard']);
const events=[];const keyboard=Object.create(ctx.BubbleInlineKeyboard.prototype);
Object.assign(keyboard,{active:false,identity:'',generation:0,msg:{id:1,rowId:1,inlineButtons:[[button(1)]]},data:{chatId:9},context:{gestureClaimed:false},actions:new Proxy({},{get:(_,k)=>(...a)=>events.push([k,...a])})});
keyboard.aboutToAppear();const click=keyboard.clickCallback(keyboard.msg.inlineButtons[0][0],0,0);click();assert.deepEqual(events.at(-1),['onLinkTap','https://example.org/1',true]);
keyboard.msg={...keyboard.msg,inlineButtons:[[button(1)]]};keyboard.changed();click();assert.equal(events.length,2);
keyboard.msg={...keyboard.msg,inlineButtons:[[button(2)]]};keyboard.changed();click();assert.equal(events.length,2);
keyboard.msg={...keyboard.msg,id:2,rowId:2};keyboard.changed();keyboard.msg={...keyboard.msg,id:1,rowId:1,inlineButtons:[[button(1)]]};keyboard.changed();click();assert.equal(events.length,2);
keyboard.aboutToRecycle();keyboard.clickCallback(button(1),0,0)();assert.equal(events.length,2);
console.log('PASS: reply images/dice and bot buttons retain row/body plans; short avatar rows preserve bubble height; compiled button events reject stale targets and A/B/A reuse.');

// Exhaustive fixed-field GIF policy parity with the pre-migration component.
for(let bits=0;bits<1024;bits++){
 const env={appIsForeground:!!(bits&1),powerSaving:!!(bits&2),reduceAnim:!!(bits&4),autoplayGif:!!(bits&8)};
 const d={animationPlaybackFailed:!!(bits&16),animationPaused:!!(bits&32),animationForcePlay:!!(bits&64)};
 const m={contentType:'video',isAnimation:true,videoPath:bits&128?'/gif':'',videoFileId:bits&256?9:0,videoFailed:!!(bits&512)};
 for(const visible of [false,true]){
  const expected=m.videoPath!==''&&visible&&env.appIsForeground&&!d.animationPlaybackFailed&&!d.animationPaused&&(d.animationForcePlay||(!env.powerSaving&&!env.reduceAnim&&env.autoplayGif));
  assert.equal(ctx.drawnAnimationPlaying(m,d,env,visible),expected);
 }
 assert.equal(ctx.drawnAnimationDownloadExpected(m,d,env),m.videoFileId!==0&&m.videoPath===''&&!m.videoFailed&&(d.animationForcePlay||(!env.powerSaving&&!env.reduceAnim&&env.autoplayGif)));
}
const deliveries=[],progress=[];ctx.progressForOr=(_id,p)=>p;ctx.subscribeProgress=(_id,fn)=>{progress.push(fn);return()=>{};};
const gif=Object.create(ctx.DrawnSingleMediaVideo.prototype);
const g=group('GIF');Object.assign(g.head,{contentType:'video',isAnimation:true,videoFileId:7,videoFileSize:100,videoPath:'',videoProgress:0,videoFailed:false,photoFileId:0,photoPath:'',photoWidth:100,photoHeight:100,videoVariants:[]});
Object.assign(gif,{msg:g.head,data:{...data,animationForcePlay:false,animationPaused:false,animationPlaybackFailed:false},env:{appIsForeground:true,autoplayGif:true,powerSaving:false,reduceAnim:false},mediaVisible:true,requestedDownload:false,active:false,binding:'',generation:0,observationEpoch:0,observationKey:'',candidateId:0,centerY:0,mediaWidth:100,mediaHeight:100,unsubPoster:null,unsubProgress:null,files:new ctx.DrawnSingleInlineFile(),actions:new Proxy({},{get:(_,k)=>(...a)=>deliveries.push([k,...a])})});
gif.aboutToAppear();assert.equal(deliveries.filter(e=>e[0]==='onAutoplayVideoNeedDownload').length,1);for(let i=0;i<1000;i++)gif.changed();assert.equal(deliveries.length,1);
gif.ratioCallback()(true,.9);assert.equal(deliveries.length,1,'GIF does not compete for a normal video slot');
gif.msg={...gif.msg,videoPath:'/gif'};gif.changed();assert.equal(gif.animationPlaying,true);const failed=gif.animationFailedCallback();
gif.msg={...gif.msg,id:20,rowId:20,videoPath:'/other'};gif.changed();gif.msg={...gif.msg,id:10,rowId:10,videoPath:'/gif'};gif.changed();failed();assert.equal(deliveries.filter(e=>e[0]==='onAnimationPlaybackFailed').length,0);
gif.animationFailedCallback()();assert.equal(deliveries.at(-1)[0],'onAnimationPlaybackFailed');gif.aboutToRecycle();
console.log('PASS: 2048 GIF playback policy combinations, download parity/dedup, no normal-slot competition, and compiled A/B/A playback failure isolation.');

load(compiled+'pages/chat/DrawnSingleMediaSurface.ts',['DrawnSingleMediaSurface']);
const surface=Object.create(ctx.DrawnSingleMediaSurface.prototype),seen=[];
Object.assign(surface,{active:false,identity:'',generation:0,touchedGeneration:-1,msg:{...g.head,isAnimation:false,photoFailed:false},data:{...data},context:{gestureClaimed:false},env:gif.env,slot:{bind(){},recycle(){},dispose(){}},getUIContext:()=>ui,actions:new Proxy({},{get:(_,k)=>(...a)=>seen.push([k,...a])})});
Object.defineProperty(surface,'tile',{value:{width:100,height:100}});surface.aboutToAppear();const tap=surface.clickCallback();tap({source:2,windowX:1,windowY:2});assert.equal(seen.at(-1)[0],'onMediaTap');
surface.data={...data,selectionActive:true};tap({source:2});assert.equal(seen.at(-1)[0],'onToggleSelectedMessage');
surface.data={...data};surface.msg={...surface.msg,id:20,rowId:20};surface.changed();surface.msg={...surface.msg,id:10,rowId:10};surface.changed();const size=seen.length;tap({source:2});assert.equal(seen.length,size);surface.aboutToRecycle();surface.clickCallback()({source:2});assert.equal(seen.length,size);
const legacy=fs.readFileSync(compiled+'pages/chat/LegacySingleMediaBubble.ts','utf8');assert.match(legacy,/new DrawnSingleMediaSurface\(/);assert.doesNotMatch(legacy,/new (LiveThumbImage|ThumbReadyGate|CachedImage)\(/);
console.log('PASS: all single-media fallback entries share the new image surface, keep selection/media clicks and reject recycled callbacks.');
