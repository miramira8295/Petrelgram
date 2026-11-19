// Production lifecycle methods with deterministic image/frame/gate doubles.
// Assertions concern ownership and updates, not native pixels or milliseconds.
import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
const ts=(await import(process.env.TYPESCRIPT_MODULE||'typescript')).default;
const root='entry/src/main/ets/';
const images=[],frames=[],gates=[],timers=new Map();let nextTimer=0,invalidations=0,now=100;
const env={appearanceEpoch:1,langEpoch:1,chatEffects:true,messageEffects:true,reactionEffects:true,animatedEmoji:true,emojiReactions:true,powerSaving:false,reduceAnim:false,appIsForeground:true};
const ctx=vm.createContext({Date:{now:()=>now},chatEnv:env,textMeasureEnvironment:{epoch:1},scrollActiveNow:()=>false,
 DrawModifier:class{invalidate(){invalidations++;}},
 ReactionImage:class{
  constructor(_ui,key,emoji,density,environment,color,changed){Object.assign(this,{key,emoji,density,environment,color,changed,starts:0,updates:0,cancelled:0,disposed:false,plays:[]});images.push(this);}
  start(path){this.path=path;this.starts++;}update(color,path){this.color=color;this.path=path;this.updates++;}
  play(cb){this.plays.push(cb);}cancelAnimation(){this.cancelled++;}dispose(){this.disposed=true;}draw(){}
 },
 drawnColor:x=>x,reactionForeground:(out,chosen)=>({out,chosen}),
 reactionKeyFrom:(emoji,id,paid)=>paid?'paid:stars':id?'ce:'+id:emoji,
 subscribeChatAnimationGate:(cb)=>{const gate={cb,off:false};gates.push(gate);cb(false);return()=>gate.off=true;},
 OneShotFrameCallback:class{constructor(fn){this.fn=fn;}},
 setTimeout:cb=>{const id=++nextTimer;timers.set(id,cb);return id;},clearTimeout:id=>timers.delete(id),
 logW:message=>{throw Error(message);},animationDurationFor:(enabled,scrolling,ms)=>enabled&&!scrolling?ms:0});
function load(file,names,component=false){
 let source=fs.readFileSync(root+file,'utf8').replace(/^import\s[\s\S]*?;\r?\n/gm,'').replace(/\bexport /g,'');
 if(component){source=source.slice(0,source.indexOf('  build() {'))+'\n}';source=source.replace(/@ComponentV2\s*/g,'').replace(/\bstruct\b/g,'class').replace(/@(?:Require|Param|Event|Local|Computed)\s*/g,'').replace(/@Monitor\([^)]*\)\s*/g,'');}
 vm.runInContext(ts.transpileModule(source+names.map(n=>'\nglobalThis.'+n+'='+n+';').join(''),{compilerOptions:{target:ts.ScriptTarget.ES2020}}).outputText,ctx,{filename:file});
}
load('util/drawnFrameBatch.ets',['DrawnFrameBatch']);load('pages/chat/ReactionIcon.ets',['ReactionIcon'],true);
const r={emoji:'👍',customEmojiId:'',customEmojiPath:'',count:2,isChosen:true};
const icon=new ctx.ReactionIcon();Object.assign(icon,{reaction:r,ownerKey:'chat1:row1',outgoing:false,getUIContext:()=>({vp2px:()=>2,postFrameCallback:frame=>frames.push(frame.fn)})});
icon.aboutToAppear();assert.equal(images.length,0,'offscreen appearance does not request resources');
icon.visibilityChanged(true);assert.equal(images.length,1);const a=images[0];assert.equal(a.starts,1);assert.equal(a.plays.length,0,'already-selected item does not replay on mount');
for(let i=0;i<1000;i++){icon.reaction={...r,count:i+2};icon.sourceChanged();}
assert.equal(images.length,1);assert.equal(a.starts,1);assert.equal(a.plays.length,0);assert.equal(timers.size,0);assert.equal(frames.length,0,'1000 stable updates schedule no timer or frame');
for(let i=0;i<1000;i++)a.changed();assert.equal(frames.length,1);const before=invalidations;frames.shift()();assert.equal(invalidations,before+1,'resource batch only invalidates the leaf painter');
icon.reaction={...r,isChosen:false};icon.sourceChanged();icon.reaction=r;icon.sourceChanged();assert.equal(a.plays.length,1);
assert.equal(icon.painter.pulseStarted,now,'static pulse starts even before movie data arrives');
now+=90;frames.shift()();assert.equal(icon.painter.scale,1.12);assert.equal(frames.length,1);
const transforms=[];icon.painter.drawBehind({canvas:{save:()=>transforms.push('save'),translate:(x,y)=>transforms.push(['translate',x,y]),scale:(x,y)=>transforms.push(['scale',x,y]),restore:()=>transforms.push('restore')}});
assert.deepEqual(transforms,['save',['translate',20,20],['scale',1.12,1.12],['translate',-20,-20],'restore'],'pulse transforms only the 20vp icon drawing about its center');assert.equal(timers.size,0,'pulse uses frame callbacks only');
now+=90;frames.shift()();assert.equal(icon.painter.scale,1);assert.equal(frames.length,0,'180ms pulse terminates without an idle frame loop');
const clip={path:'reaction.tgs',poster:'reaction.webp',format:'stickerFormatTgs'};a.plays[0](clip);assert.equal(icon.playbackSource,clip);assert.equal(icon.replay,1);assert.equal(timers.size,1);
assert.equal(icon.painter.hidden,false,'retain fallback before the first native frame');
const firstStarted=icon.overlayCallback(true),firstFailed=icon.overlayCallback(false);
firstStarted();assert.equal(icon.painter.hidden,true);assert.equal(icon.painter.scale,1);
gates[0].cb(true);assert.equal(icon.playbackSource,null);assert.equal(timers.size,0);assert.equal(icon.painter.hidden,false);assert.equal(icon.painter.scale,1);a.plays[0](clip);assert.equal(icon.playbackSource,null,'late animation cannot resurrect across gate close');
gates[0].cb(false);assert.equal(a.plays.length,1,'resume does not replay old selection');
icon.painter.startPulse();icon.requestPaint();now+=90;frames.shift()();assert.equal(icon.painter.scale,1.12);
gates[0].cb(true);assert.equal(icon.painter.scale,1);frames.shift()();assert.equal(frames.length,0,'gate cancels static pulse without continuing an idle frame loop');gates[0].cb(false);
icon.reaction={...r,isChosen:false};icon.sourceChanged();icon.reaction=r;icon.sourceChanged();assert.equal(a.plays.length,2);a.plays[1](clip);assert.equal(icon.replay,2,'same-path selection gets a new replay token');
firstStarted();firstFailed();assert.equal(icon.playbackSource,clip);assert.equal(icon.painter.hidden,false,'stale first-frame callback cannot hide current static icon');
now+=90;frames.shift()();assert.equal(icon.painter.scale,1.12);
icon.overlayCallback(true)();assert.equal(icon.painter.hidden,true);assert.equal(icon.painter.scale,1,'native first frame ends the static pulse');
frames.shift()();assert.equal(frames.length,0,'hidden movie fallback does not keep requesting pulse frames');
for(const flag of ['powerSaving','reduceAnim']){env[flag]=true;icon.policyChanged();assert.equal(icon.playbackSource,null);assert.equal(icon.painter.hidden,false);assert.equal(icon.painter.scale,1);env[flag]=false;}
for(const flag of ['chatEffects','messageEffects','reactionEffects','animatedEmoji','emojiReactions','appIsForeground']){
 env[flag]=false;assert.equal(icon.mayAnimate(),false);icon.policyChanged();env[flag]=true;
}
icon.ownerKey='chat1:row2';icon.sourceChanged();assert.equal(a.disposed,true);assert.equal(images.length,2);const b=images[1];
a.plays[1](clip);assert.equal(icon.playbackSource,null);const savedFrames=frames.length;a.changed();assert.equal(frames.length,savedFrames,'old pixels cannot invalidate another owner');
icon.visibilityChanged(false);assert.equal(b.disposed,true);assert.equal(icon.playbackSource,null);
icon.visibilityChanged(true);assert.equal(images.length,3);assert.equal(images[2].plays.length,0);
env.appearanceEpoch++;icon.sourceChanged();assert.equal(images.length,4);assert.equal(images[2].disposed,true,'theme/text configuration owns a fresh tinted fallback');
icon.aboutToRecycle();assert.equal(images[3].disposed,true);assert.ok(gates.every(g=>g.off));assert.equal(timers.size,0);
const recycledPaints=invalidations;for(const frame of frames.splice(0))frame();assert.equal(invalidations,recycledPaints);
icon.ownerKey='chat1:row1';icon.aboutToReuse();icon.visibilityChanged(true);a.plays[0](clip);assert.equal(icon.playbackSource,null,'A-B-A rejects original selection callback');icon.aboutToDisappear();
console.log('PASS: stable 1000 updates, no mount/reuse replay, frame-coalesced leaf-only updates, same-path replay, gate/power/visibility cancellation and A-B-A guards.');

const chipSource=fs.readFileSync(root+'pages/chat/ReactionChip.ets','utf8');
assert.doesNotMatch(chipSource,/\.animation\(/,'root chip must not animate measured width');
assert.match(chipSource,/\.accessibilitySelected\(this.reaction.isChosen\)/);
load('pages/chat/ReactionChip.ets',['ReactionChip'],true);
const chip=new ctx.ReactionChip(),calls=[];chip.reaction={...r,isChosen:false};chip.onToggle=(key,chosen)=>calls.push(['toggle',key,chosen]);chip.onShow=key=>calls.push(['show',key]);
chip.activate();chip.reaction={...r,count:7};chip.activate();chip.show();chip.reaction={...r,emoji:'⭐',isPaid:true};chip.activate();
assert.deepEqual(calls,[['toggle','👍',false],['toggle','👍',true],['show','👍'],['show','paid:stars']]);
load('pages/chat/ReactionAnimationView.ets',['ReactionAnimationView'],true);
const view=new ctx.ReactionAnimationView();view.aboutToAppear();view.source=clip;view.replayToken=1;let failures=0;view.onFailed=()=>failures++;
const stale=view.failure();view.replayToken=2;stale();assert.equal(failures,0);view.failure()();assert.equal(failures,1);const retired=view.failure();view.aboutToDisappear();retired();assert.equal(failures,1);
const alpha=fs.readFileSync(root+'pages/common/AlphaWebmStickerView.ets','utf8');
const start=alpha.indexOf('  private loopEnabled()'),method=alpha.slice(start,alpha.indexOf('\n  }',start)+4);
vm.runInContext(ts.transpileModule('class AlphaPolicy {'+method+'} globalThis.AlphaPolicy=AlphaPolicy;',{compilerOptions:{target:ts.ScriptTarget.ES2020}}).outputText,ctx);
const policy=new ctx.AlphaPolicy();policy.env={stickerLoop:true};policy.powerCategory='emojiReaction';policy.playOnce=false;assert.equal(policy.loopEnabled(),true);policy.playOnce=true;assert.equal(policy.loopEnabled(),false);
policy.powerCategory='sticker';policy.playOnce=false;policy.env.stickerLoop=false;assert.equal(policy.loopEnabled(),false);
assert.match(alpha,/@Monitor\('webmPath', 'replayToken'\)/);
for(const name of ['MessageBubbleShell','BubbleContentLayout']){
 const source=fs.readFileSync(root+'pages/chat/'+name+'.ets','utf8'),region=source.slice(source.indexOf('  reactionsRow()'),source.indexOf('  private reactionsRowWidth('));
 assert.match(region,/reaction: this\.msg\.reactions\[index\] \?\? r/);
 assert.match(region,/rx_\$\{reactionKeyFrom\(r\.emoji, r\.customEmojiId, r\.isPaid === true\)\}_\$\{index\}/);
 assert.doesNotMatch(region,/_\$\{r\.count\}/);
}
console.log('PASS: current Param click/count semantics, paid-reaction info-only action, stale overlay failures, single-play WebM policy and stable indexed compatibility wiring.');
