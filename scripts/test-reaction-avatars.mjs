import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
import {ctx,load,root,compiled,ui,data,style,group,layoutCounters} from './test-drawn-text-row.mjs';
const ts=(await import(process.env.TYPESCRIPT_MODULE||'typescript')).default;
vm.runInContext('globalThis.Reactions=DrawnReactionLayouts;',ctx);
const source=fs.readFileSync(root+'store/MessageEntry.ets','utf8');
const parser=source.slice(source.indexOf('export function reactionsFromInteraction('),source.indexOf('\nfunction albumIdOf('));
vm.runInContext(ts.transpileModule(parser.replace('export ',''),{compilerOptions:{target:ts.ScriptTarget.ES2020}}).outputText,ctx);
load(root+'util/interactionDelta.ets',['interactionChanged']);
const user=id=>({'@type':'messageSenderUser',user_id:id});
const chat=id=>({'@type':'messageSenderChat',chat_id:id});
const raw=(senders,count=senders.length,extra={})=>({type:{'@type':'reactionTypeEmoji',emoji:'👍'},total_count:count,recent_sender_ids:senders,...extra});
const parse=(list,are_tags=false)=>ctx.reactionsFromInteraction({reactions:{reactions:list,are_tags}});
const r=parse([raw([user(2),user(1)])])[0];
assert.equal(r.recentSenderKey,'u1,u2');assert.equal(r.recentSenders.length,2);
assert.equal(parse([raw([user(2),user(2),chat(-3)])])[0].recentSenderKey,'c-3,u2');
assert.equal(parse([raw([user(0),user(NaN),{'@type':'bad'}])])[0].recentSenderKey,'');
assert.equal(parse([raw(Array.from({length:10000},(_,i)=>user(i+1)))])[0].recentSenders.length,3);
assert.equal(ctx.interactionChanged(0,[],[r],0,[],parse([raw([user(1),user(2)])])),false,'server ordering alone is not a row update');
assert.equal(ctx.interactionChanged(0,[],[r],0,[],parse([raw([user(1),user(3)])])),true,'same count with different people must publish');
for(const privateChat of [false,true])for(const channel of [false,true])for(const total of [2,5]){
 const expected=!channel&&(privateChat||total<=3)?2:0;
 assert.equal(ctx.reactionAvatarCount(r,total,channel,privateChat),expected);
}
for(const invalid of [{...r,count:3},{...r,areTags:true},{...r,isPaid:true},{...r,count:0}])assert.equal(ctx.reactionAvatarCount(invalid,2,false,true),0);
const reactions=new ctx.Reactions();reactions.measure(ui,[r],250,true,'1',false,false);
let plan=reactions.flow(250),chip=plan.chips[0];
assert.equal(chip.count,null);assert.equal(chip.avatarCount,2);assert.equal(chip.width,71);assert.equal(chip.height,26);
assert.equal(plan.avatars.length,1);assert.equal(plan.hit(10,10),chip);
const stable=layoutCounters();for(let i=0;i<1000;i++){reactions.measure(ui,reactions.source,250,true,'1',false,false);assert.equal(reactions.flow(250),plan);}assert.deepEqual(layoutCounters(),stable);
const many=[r,{...r,emoji:'🔥',count:2}];reactions.measure(ui,many,250,true,'1',false,false);assert.equal(reactions.flow(250).avatars.length,0);
reactions.measure(ui,many,250,true,'1',false,true);assert.equal(reactions.flow(250).avatars.length,2);
reactions.measure(ui,[r],250,false,'1',false,true);assert.equal(reactions.flow(250).avatars.length,0);
const g=group('hello');g.head.reactions=[r];const engine=new ctx.DrawnTextLayouts();
const a=engine.prepare(ui,g,{...data,isGroup:true,isChannel:false},style);
g.head={...g.head,reactions:[{...r,isChosen:true}]};const b=engine.prepare(ui,g,{...data,isGroup:true,isChannel:false},style);
assert.equal(a.caption,b.caption,'selection update retains body paragraph');
const islandKey=ctx.reactionAvatarIslandKey(chip);
assert.equal(ctx.reactionAvatarIslandKey({...chip,reaction:{...r,isChosen:true}}),islandKey);
assert.notEqual(ctx.reactionAvatarIslandKey({...chip,y:30}),islandKey,'wrapped avatars must move with their chip');
assert.notEqual(ctx.reactionAvatarIslandKey({...chip,x:80}),islandKey);
assert.notEqual(ctx.reactionAvatarIslandKey({...chip,reaction:{...r,recentSenderKey:'u8,u9'}}),islandKey);
reactions.measure(ui,[r],40,true,'1',false,true);assert.equal(reactions.flow(40).avatars.length,0,'narrow panel uses count, never clipped identities');
for(const filename of ['MessageBubbleShell','BubbleContentLayout']){
 const code=fs.readFileSync(root+'pages/chat/'+filename+'.ets','utf8');
 const at=code.indexOf('  private reactionAvatars('),method=code.slice(at,code.indexOf('\n  }',at)+4);
 vm.runInContext(ts.transpileModule('(function(){class ReactionCompatPolicy {'+method+'} globalThis.ReactionCompatPolicy=ReactionCompatPolicy;})();',{compilerOptions:{target:ts.ScriptTarget.ES2020}}).outputText,ctx);
 const compat=new ctx.ReactionCompatPolicy(),items=[r];let scans=0;
 items[Symbol.iterator]=function*(){scans++;yield*Array.prototype.values.call(this);};
 compat.msg={reactions:items};compat.data={isChannel:false,isGroup:true};
 for(let n=0;n<1000;n++)assert.equal(compat.reactionAvatars(r),2);
 assert.equal(scans,1,'compatibility path computes total once per reaction revision');
 compat.data.isChannel=true;assert.equal(compat.reactionAvatars(r),0);
 compat.data.isChannel=false;compat.msg={reactions:[r,{...r,count:3}]};assert.equal(compat.reactionAvatars(r),0);
 compat.data.isGroup=false;assert.equal(compat.reactionAvatars(r),2);
}
const custom=parse([raw([user(1)],1,{type:{'@type':'reactionTypeCustomEmoji',custom_emoji_id:'9007199254740999'}})])[0];
assert.equal(custom.customEmojiId,'9007199254740999');assert.equal(custom.recentSenderKey,'u1');
const storeSource=fs.readFileSync(root+'store/MessageStore.ets','utf8'),methodStart=storeSource.indexOf('  private updatedReactionCustomEmojiPaths(');
const hydrateMethod=storeSource.slice(methodStart,storeSource.indexOf('\n  }',methodStart)+4);
vm.runInContext(ts.transpileModule('class HydrationOwner {'+hydrateMethod+'} globalThis.HydrationOwner=HydrationOwner;',{compilerOptions:{target:ts.ScriptTarget.ES2020}}).outputText,ctx);
const store=new ctx.HydrationOwner();store.inlineCustomEmojiPathById=new Map([[custom.customEmojiId,'emoji.webp']]);
const hydrated=store.updatedReactionCustomEmojiPaths({reactions:[custom]})[0];
assert.equal(hydrated.customEmojiPath,'emoji.webp');assert.equal(hydrated.recentSenders,custom.recentSenders);assert.equal(hydrated.recentSenderKey,'u1');
assert.equal(store.updatedReactionCustomEmojiPaths({reactions:[hydrated]}),null);
console.log('PASS: bounded TDLib identity parsing, canonical ordering, same-count swaps, privacy/tag/paid rules, private/group policy, avatar geometry, 1000 warm hits and retained body.');

// Actual native painter/ownership controller; model the asynchronous channels,
// not their network implementations (shared cache has its own regression).
const peers=[],files=[],sessions=[],frames=[];let paints=0,shapes=0,measures=0;
ctx.DrawModifier=class{invalidate(){paints++;}};
ctx.drawing.RoundRect=class{constructor(){shapes++;}};
ctx.ImageFit={Cover:0};ctx.watchPeer=(id,user,callback)=>{const entry={id,user,callback,off:false};peers.push(entry);callback(null);return()=>entry.off=true;};
ctx.documentFileId=f=>f?.id??0;ctx.documentFilePath=f=>f?.local?.path??'';ctx.documentFileState=f=>({path:ctx.documentFilePath(f)});
ctx.requestDocumentFile=()=>{};ctx.THUMBNAIL_PRIORITY=1;
ctx.watchDocumentFile=(file,callback)=>{const entry={file,callback,off:false};files.push(entry);return()=>entry.off=true;};
ctx.CachedImageSession=class{constructor(callback){this.callback=callback;this.active=false;sessions.push(this);}activate(spec){this.active=true;this.spec=spec;}update(spec){this.spec=spec;}dispose(){this.active=false;}};
ctx.DrawnImageReceiver=class{bind(){}setPixels(p){this.pixels=p;}drawFront(){}};
ctx.OneShotFrameCallback=class{constructor(fn){this.fn=fn;}};
load(root+'util/drawnFrameBatch.ets',['DrawnFrameBatch']);
load(root+'pages/chat/DrawnReactionAvatarsPainter.ets',['DrawnReactionAvatarsPainter']);
const testUi={...ui,postFrameCallback:cb=>frames.push(cb.fn),fp2px:n=>{measures++;return n;}};
const painter=new ctx.DrawnReactionAvatarsPainter();painter.bind(testUi,r.recentSenders,'chat:row','1');
assert.equal(peers.length,2);assert.equal(frames.length,1,'all cold metadata paint notifications coalesce');frames.shift()();
for(let i=0;i<1000;i++)painter.bind(testUi,[...r.recentSenders],'chat:row','1');
assert.equal(peers.length,2);assert.equal(shapes,1);assert.equal(frames.length,0);
const photo={id:11,local:{path:'A.webp'}};peers[0].callback({name:'Alice',photo});sessions[0].callback({id:'A'},true,20,20);
assert.equal(painter.slots[0].receiver.pixels.id,'A');assert.equal(frames.length,1);
const oldFile=files[0];peers[0].callback({name:'Alice',photo:{id:12,local:{path:'new.webp'}}});
assert.equal(oldFile.off,true);oldFile.callback({path:'stale.webp'});assert.notEqual(sessions[0].spec.path,'stale.webp');
peers[0].callback({name:'Alice',photo:undefined});assert.equal(painter.slots[0].receiver.pixels,undefined);
const beforePaint={shapes,measures,layouts:layoutCounters()};
const canvas={save(){},restore(){},translate(){},clipRoundRect(){},attachBrush(){},detachBrush(){},drawCircle(){}};
for(let i=0;i<1000;i++)painter.drawBehind({canvas});
assert.equal(shapes,beforePaint.shapes);assert.equal(measures,beforePaint.measures);assert.deepEqual(layoutCounters(),beforePaint.layouts);
const oldPeer=peers[0],oldSession=sessions[0];painter.bind(testUi,[{id:9,user:true,key:'u9'}],'chat:other','1');
assert.equal(oldPeer.off,true);oldPeer.callback({name:'OLD',photo});oldSession.callback({id:'OLD'},true,20,20);
assert.equal(painter.slots[0].receiver.pixels,undefined);assert.equal(peers.length,3);
painter.dispose();const disposed=paints;for(const frame of frames.splice(0))frame();assert.equal(paints,disposed,'recycle cancels all queued publications');
assert.ok(peers.every(peer=>peer.off));assert.ok(files.every(file=>file.off));
painter.bind(testUi,r.recentSenders,'chat:row','1');oldPeer.callback({name:'STALE',photo});assert.notEqual(painter.slots[0].name,'STALE');painter.dispose();
console.log('PASS: real avatar painter 1000 stable binds/paints, frame-coalesced invalidation, photo removal/change, stale file/peer/decode, A-B-A and disposal.');

// Embedded painter: one callback per frame, only after disposal is complete.
{
 for(const frame of frames.splice(0))frame();
 const beforePeer=peers.length,beforeSession=sessions.length;let nested=0,cleared=0;
 let model;
 model=new ctx.DrawnReactionAvatarsPainter(()=>{
  nested++;
  if(model.clip===null){assert.equal(model.slots.length,0);cleared++;}
  model.drawBehind({canvas});
 });
 model.bind(testUi,r.recentSenders,'embedded','1');assert.equal(nested,0);assert.equal(frames.length,1);
 peers[beforePeer].callback({name:'Nested',photo:{id:88,local:{path:'nested.webp'}}});
 for(let n=0;n<100;n++)sessions[beforeSession].callback({id:'pixel'+n},true,20,20);
 assert.equal(frames.length,1,'all embedded metadata/pixels share the frame');frames.shift()();assert.equal(nested,1);
 sessions[beforeSession].callback({id:'last'},true,20,20);assert.equal(frames.length,1);
 model.dispose();assert.equal(cleared,1);const retired=nested;
 for(const frame of frames.splice(0))frame();
 peers[beforePeer].callback({name:'Stale',photo:{id:99,local:{path:'stale.webp'}}});
 sessions[beforeSession].callback({id:'stale'},true,20,20);
 assert.equal(nested,retired);assert.equal(model.slots.length,0);model.dispose();assert.equal(nested,retired,'repeated dispose does not repaint parent');
}
console.log('PASS: embedded avatar painter batches parent paint notifications and clears resources before notifying disposal; retired frame/peer/decode callbacks remain silent.');
