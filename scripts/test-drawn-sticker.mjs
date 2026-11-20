import assert from 'node:assert/strict';
import {ctx,load,compiled,ui,data,style,group,layoutCounters} from './test-drawn-text-row.mjs';
const g=group('🙂');Object.assign(g.head,{contentType:'sticker',rowId:71,photoWidth:512,photoHeight:256,photoFileId:22,stickerFileId:23,photoProgress:0,stickerProgress:0,stickerFormat:'tgs',stickerPath:'',photoPath:''});
const engine=new ctx.DrawnTextLayouts(),plan=engine.prepare(ui,g,data,style),slot=plan.caption.widgets[0],counts=layoutCounters();
assert.equal(slot.widget.kind,'message-sticker');assert.equal(slot.width,160);assert.equal(slot.height,80);assert.equal(plan.caption.source.blocks.length,1,'emoji alternative is not duplicated as caption');
for(let i=0;i<1000;i++)assert.equal(engine.prepare(ui,{...g,head:{...g.head,stickerPath:i%2?'/anim':'',photoPath:i%2?'/poster':'',stickerProgress:i%100}},data,style),plan);
assert.deepEqual(layoutCounters(),counts);
const narrow=engine.prepare(ui,g,{...data,contentWidth:130},style).caption.widgets[0];assert.ok(narrow.width<160);assert.equal(narrow.width/narrow.height,2);
// The footer follows the actual sticker, even when a name, quote or reactions
// widen the row. Both send directions retain their complete status bounds.
for (const [w,h] of [[512,512],[512,256],[256,512]]) {
  for (const outgoing of [false,true]) for (const withChrome of [false,true]) {
    const fixture=group('🙂');Object.assign(fixture.head,g.head,{photoWidth:w,photoHeight:h,isOutgoing:outgoing,
      senderName:withChrome?'A very long sender name':'',replyToMessageId:withChrome?30:0,
      replySenderName:'quoted sender',replyText:'a long quoted message that widens the row',
      reactions:withChrome?[{emoji:'👍',customEmojiId:'',count:123,chosen:false}]:[]});
    const p=new ctx.DrawnTextLayouts().prepare(ui,fixture,{...data,isGroup:withChrome},style);
    const tile=p.caption.widgets[0],r=p.footerBackdrop.rect,d=p.density;
    const bounds={left:(p.captionX+tile.x)*d,top:(p.captionY+tile.y)*d,
      right:(p.captionX+tile.x+tile.width)*d,bottom:(p.captionY+tile.y+tile.height)*d};
    assert.equal(p.onMedia,true);assert.ok(r.left>=bounds.left && r.top>=bounds.top);
    assert.ok(r.right<=bounds.right && r.bottom<=bounds.bottom,'time pill stays inside actual sticker');
    assert.ok(Math.abs(r.right-(bounds.right-4*d))<.01);
    assert.ok(Math.abs(r.bottom-(bounds.bottom-2*d))<.01);
    if(outgoing)assert.ok((p.statusX+p.statusSize*4/3)*d<=r.right);
    if(withChrome)assert.ok(p.chrome.reactionsY*d>=bounds.bottom+8*d,'reactions do not move time off the sticker');
  }
}
for(const [w,h] of [[16,512],[512,16]]) {
  const tiny=group('🙂');Object.assign(tiny.head,g.head,{photoWidth:w,photoHeight:h});
  const p=new ctx.DrawnTextLayouts().prepare(ui,tiny,data,style),tile=p.caption.widgets[0];
  assert.ok(p.footerY>=p.captionY+tile.y+tile.height,'extreme aspect ratios keep a readable footer');
  assert.ok(p.footerX+p.footerWidth<=p.width);
}
// Replay the actual compiled host: one native sticker BEFORE the time layer,
// and retained child bindings get the new message/geometry after row reuse.
const paintOrder=[],observers=[],updates=[];let child;
ctx.StickerMessageBubble=class {constructor(_parent,params){this.params=params;child=this;}};
ctx.ViewV2.create=()=>paintOrder.push('sticker');
ctx.__Common__=new Proxy({}, {get:()=>()=>{}});
ctx.Row=new Proxy({}, {get:(_t,key)=>(...args)=>{if(key==='drawModifier')paintOrder.push('foreground');}});
const host=Object.create(ctx.DrawnMessageRow.prototype);
for(const [key,value] of Object.entries({plan,rowGroup:g,rowData:data,kind:'text',sendState:'sent',views:'',env:{},
  actions:{},interaction:{},jumpFocus:0,claimed:false,deleteCaptureSupported:false,footerPaintKey:'',
  canvasAttributes:{bind:()=>({})},painter:{bind:()=>({})},foreground:{bind:()=>({})},
  menuFx:{preview:()=>({}),menu:()=>({})},menu:()=>{},canDragMessage:()=>false,
  observeComponentCreation2:fn=>{observers.push(fn);fn(observers.length,true);},
  ifElseBranchUpdateFunction:(_id,fn)=>fn(),updateStateVarsOfChildByElmtId:(_id,params)=>updates.push(params),
  presentationReady:()=>true}))Object.defineProperty(host,key,{value,writable:true,configurable:true});
host.canvasContent();assert.deepEqual(paintOrder,['sticker','foreground']);
assert.equal(child.params.contentOnly,true);assert.equal(child.params.onClaim(),true);assert.equal(host.claimed,true);
const replacement=group('🙂');Object.assign(replacement.head,g.head,{id:21,rowId:72,photoWidth:256,photoHeight:512});
host.rowGroup=replacement;host.plan=new ctx.DrawnTextLayouts().prepare(ui,replacement,data,style);
for(const observer of observers.slice())observer(1,false);
assert.ok(updates.some(params=>params.msg===replacement.head),'retained sticker child receives replacement identity');
console.log('PASS: sticker time overlays native content once; clicks claimed; retained native sticker updates after reuse.');

ctx.MessageBubbleContext=class{};ctx.chatEnv={};
ctx.progressForOr=(_id,fallback)=>fallback;const callbacks=new Map();ctx.subscribeProgress=(id,fn)=>{callbacks.set(id,fn);return()=>{};};
load(compiled+'pages/chat/StickerMessageBubble.ts',['StickerMessageBubble']);
const local=Object.assign(Object.create(ctx.StickerMessageBubble.prototype),{msg:g.head,channelGeneration:0,unsubPhotoProgress:null,unsubStickerProgress:null,contentRowId:0,stickerPlaybackFailed:false,context:{gestureClaimed:false},contentOnly:true,onClaim:()=>true});
local.attachMessageChannels(g.head);const oldProgress=callbacks.get(23),oldFailure=local.playbackFailure();oldProgress(40);assert.equal(local.liveStickerProgress,40);
local.msg={...g.head,rowId:72,stickerFileId:24,stickerPath:'/new',stickerProgress:7};local.attachMessageChannels(local.msg);oldProgress(99);oldFailure();assert.equal(local.liveStickerProgress,7);assert.equal(local.stickerPlaybackFailed,false);
local.playbackFailure()();assert.equal(local.stickerPlaybackFailed,true);local.stickerPlaybackFailed=false;const detached=local.playbackFailure();local.aboutToRecycle();detached();assert.equal(local.stickerPlaybackFailed,false);
local.onClaim=()=>false;assert.equal(local.claimContent(),false);
console.log('PASS: sticker source/ratio/narrow geometry, 1000 media updates reuse layout, stale progress/playback failure and recycle/selection guards.');
