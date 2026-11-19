// Real plan/motion/painter/foreground and surface lifecycle, native/resource boundaries mocked.
import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
const ts=(await import(process.env.TYPESCRIPT_MODULE||'typescript')).default;
const root='entry/src/main/ets/';
function load(ctx,file,names,transform=s=>s){
 let src=fs.readFileSync(root+file,'utf8').replace(/^import\s[\s\S]*?;\r?\n/gm,'').replace(/\bexport /g,'');src=transform(src);
 vm.runInContext(ts.transpileModule(src+names.map(n=>`\nglobalThis.${n}=${n};`).join(''),{compilerOptions:{target:ts.ScriptTarget.ES2020}}).outputText,ctx,{filename:file});
}
let now=100,allocations=0;const frames=[],icons=[],avatars=[],overlays=[],paint=[],timers=new Map(),gates=[];
class Native{constructor(){allocations++;}setAntiAlias(){}setStrokeWidth(){}setColor(){}setCapStyle(){}}
class Modifier{invalidations=0;invalidate(){this.invalidations++;}}
class Icon{constructor(ui,key,emoji,density,env,color,changed){this.key=key;this.changed=changed;this.updates=0;this.disposed=false;icons.push(this);}start(){}update(){this.updates++;}draw(){paint.push(this.key);}play(callback){this.callback=callback;}cancelAnimation(){this.cancelled=true;}dispose(){this.disposed=true;}}
class Avatar{constructor(changed){this.changed=changed;avatars.push(this);}bind(){}drawBehind(){}dispose(){this.disposed=true;}}
const ui={postFrameCallback:cb=>frames.push(cb)};
const ctx=vm.createContext({Date:{now:()=>now},drawing:{Brush:Native,Pen:Native,CapStyle:{ROUND_CAP:1}},DrawModifier:Modifier,FrameCallback:class{},ReactionImage:Icon,DrawnReactionAvatarsPainter:Avatar,
 DrawnChromePainter:class{bind(){}},drawnStageMetrics:{begin(){},end(){},skip(){},invalidated(){}},DrawnStage:{},DrawnInvalidation:{},
 chatEnv:{appearanceEpoch:1,langEpoch:1,chatEffects:true,messageEffects:true,reactionEffects:true,animatedEmoji:true,emojiReactions:true,powerSaving:false,reduceAnim:false},textMeasureEnvironment:{epoch:1},scrollActiveNow:()=>false,logW:msg=>assert.fail(msg),
 subscribeChatAnimationGate:(cb)=>{const g={cb,off:false};gates.push(g);cb(false);return()=>g.off=true;},setTimeout:cb=>{const id=timers.size+1;timers.set(id,cb);return id;},clearTimeout:id=>timers.delete(id)});
load(ctx,'pages/chat/DrawnReactionLayout.ets',['DrawnReactionPlan']);load(ctx,'pages/chat/ReactionMotion.ets',['ReactionMotion']);load(ctx,'util/drawnFrameBatch.ets',['DrawnFrameBatch']);load(ctx,'util/oneShotFrameCallback.ets',['OneShotFrameCallback']);load(ctx,'pages/chat/DrawnReactionsPainter.ets',['DrawnReactionsPainter']);load(ctx,'pages/chat/DrawnBubblePainter.ets',['DrawnBubbleForeground']);
const canvas=new Proxy({}, {get:()=>()=>{}}),context={canvas};
function drain(ms=16){now+=ms;const batch=frames.splice(0);for(const cb of batch)cb.onFrame(now);}
function settle(){for(let i=0;i<20&&frames.length;i++)drain(20);assert.equal(frames.length,0);}
const color={alpha:255,red:80,green:90,blue:100};
function line(value){return {heightPx:12,paragraph:{paint(c,x,y){paint.push({value,x,y});}}};}
function plan(rows){const p=new ctx.DrawnReactionPlan();p.external=true;p.width=200;p.height=26;
 p.chips=rows.map(([key,count=1,selected=false,avatarCount=0],i)=>({key,reaction:{emoji:key,customEmojiPath:'',count,isChosen:selected,recentSenders:[]},x:i*60,y:0,width:56,height:26,countX:30,avatarCount,count:avatarCount?null:line(count),emoji:line(key),fill:color,foreground:color,background:{}}));for(const chip of p.chips)p.byKey.set(chip.key,chip);return p;}
const p0=plan([['A',1],['B',2,false,1]]),painter=new ctx.DrawnReactionsPainter(value=>overlays.push(value));
const bind=(p,active=true,animate=true,owner='owner')=>painter.bind(ui,p,owner,'env',1,active,animate);
bind(p0);settle();assert.equal(icons.length,2);assert.equal(avatars.length,1);
const warm={allocations,icons:icons.length,updates:icons.reduce((s,i)=>s+i.updates,0),invalidations:painter.invalidations};
for(let i=0;i<1000;i++){bind(p0);painter.drawBehind(context);}
assert.equal(allocations,warm.allocations);assert.equal(icons.length,warm.icons);assert.equal(icons.reduce((s,i)=>s+i.updates,0),warm.updates);assert.equal(painter.invalidations,warm.invalidations);assert.equal(frames.length,0);
// Press, image and avatar delivery are isolated from the row foreground modifier.
const foreground=new ctx.DrawnBubbleForeground();foreground.bind({density:1,statusSize:10,chrome:{reactions:p0}},'');const foregroundBefore=foreground.invalidations,localBefore=painter.invalidations;
foreground.pressReaction(p0.chips[0]);assert.equal(painter.invalidations,localBefore+1);foreground.press(null);assert.equal(p0.pressedKey,'');
for(let i=0;i<1000;i++)icons[0].changed();assert.equal(frames.length,1,'image notifications coalesce per frame');drain();avatars[0].changed();assert.equal(foreground.invalidations,foregroundBefore,'local reaction updates never redraw main foreground');
const p1=plan([['A',3,true],['B',2,false,1]]);bind(p1);assert.ok(icons[0].callback);icons[0].callback({path:'a.tgs',format:'stickerFormatTgs',poster:''});assert.equal(overlays.at(-1).key,'A');
paint.length=0;painter.drawBehind(context);assert.ok(paint.includes('A'),'static icon remains until overlay first frame');painter.overlayStarted('wrong');assert.equal(painter.hiddenIconKey,'');painter.overlayStarted('A');paint.length=0;painter.drawBehind(context);assert.equal(paint.includes('A'),false,'first frame hides static symbol without duplicate layers');
drain(60);paint.length=0;painter.drawBehind(context);assert.ok(paint.some(x=>x?.value===1));assert.ok(paint.some(x=>x?.value===3));
settle();paint.length=0;painter.drawBehind(context);assert.equal(paint.some(x=>x?.value===1),false,'old counter gone after finite animation');
const p2=plan([['A',3,true]]);bind(p2);assert.equal(icons[1].disposed,false,'retain outgoing resource during exit');settle();assert.equal(icons[1].disposed,true,'release resource when exit ends');
const late=icons[0].callback;bind(p2,true,false);assert.equal(overlays.at(-1),null);paint.length=0;painter.drawBehind(context);assert.ok(paint.includes('A'),'stopping overlay restores static icon');late({path:'late'});assert.equal(overlays.at(-1),null);settle();
bind(p2,false,false);assert.ok(icons.every(i=>i.disposed));assert.ok(avatars.every(i=>i.disposed));settle();bind(p2,true,true);settle();assert.equal(icons.at(-1).callback,undefined,'returning onscreen does not replay selection');
bind(p0,true,true,'second-owner');settle();late({path:'stale-owner'});assert.equal(overlays.at(-1),null);painter.dispose();settle();assert.ok(icons.every(i=>i.disposed));assert.ok(avatars.every(i=>i.disposed));
// Exercise actual surface lifecycle methods; omit only ArkUI declarative build syntax.
load(ctx,'pages/chat/DrawnReactionsSurface.ets',['DrawnReactionsSurface'],s=>(s.slice(0,s.indexOf('  build()'))+'}\n').replace(/@Monitor\([^)]*\)/g,'').replace(/@(ComponentV2|Computed|Local|Param)\b/g,'').replace(/\bstruct\b/g,'class'));
const surface=new ctx.DrawnReactionsSurface();surface.getUIContext=()=>ui;surface.ownerKey='row-A';surface.plan=p0;
const firstVisible=surface.visibleCallback();surface.aboutToAppear();firstVisible(true);assert.equal(surface.painter.active,true,'visibility captured before appear remains valid');settle();
const obsolete=surface.visibleCallback();surface.ownerKey='row-B';surface.changed();obsolete(false);assert.equal(surface.visible,true,'old owner visibility cannot hide new owner');
surface.visibleCallback()(false);assert.equal(surface.painter.active,false);surface.visibleCallback()(true);settle();surface.aboutToRecycle();assert.equal(surface.painter.active,false);assert.ok(gates.at(-1).off);assert.equal(timers.size,0);settle();
console.log('PASS: real reaction painter 1000 stable binds, finite counters/exit cleanup, bitmap coalescing, isolated foreground, gate/owner/disposal and pre-appear visibility lifecycle.');
