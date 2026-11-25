import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
const ts=(await import(process.env.TYPESCRIPT_MODULE||'typescript')).default;
const root='entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/';
const ctx=vm.createContext({Math,Number,Date:{now:()=>now},KEY_POWER_EFFECT_MENU:'menu',KEYBOARD_SETTLE_MS:300,
 holdPlayerJobs(){},ChatPageFrameCallback:class{constructor(fn){this.fn=fn;}},
 Alignment:{Top:0},ViewV2:{create(){}},ViewPU:{},Color:{Transparent:0}});
let now=0,frames=[];
function run(s){vm.runInContext(ts.transpileModule(s.replace(/^import[^\n]*\n/gm,'').replace(/\bexport /g,'').replace(/@(ObservedV2|Trace|Computed|Monitor\([^\n]*\))\s*/g,''),{compilerOptions:{target:ts.ScriptTarget.ES2020}}).outputText,ctx);}
function member(file,name){const a=ts.createSourceFile(file,fs.readFileSync(root+'pages/chat/'+file+'.ts','utf8'),ts.ScriptTarget.Latest,true);
 const c=a.statements.find(n=>ts.isClassDeclaration(n)&&n.name.text===file);return c.members.find(n=>n.name?.getText(a)===name).getText(a);}
for(const f of ['util/bottomSlot','util/drawerMetrics','pages/chat/EmojiDrawerState'])run(fs.readFileSync('entry/src/main/ets/'+f+'.ets','utf8'));
run('globalThis.Drawer=EmojiDrawerState;');
run(`class Page {${['toggleBotMenu','openBottomDrawer','applyBottomSlot','targetDrawerTotalHeight','targetDrawerLiftHeight','animateDrawerTo','closeCommandDrawer','onBotCommandDrawerChanged','botCommandDrawerOpen','syncOpenDrawerHeight','bottomPanelOpen','closeBottomPanels','fillCommand'].map(n=>member('ChatPage',n)).join('\n')}}globalThis.Page=Page;`);
ctx.commandLabel=x=>'/'+x.command;
function page(ime=0){
 const p=new ctx.Page(),command={commandMenuOpen:false,loads:0,filters:0,
 dismissPanel(){this.commandMenuOpen=false;},closePanel(){this.commandMenuOpen=false;},
 ensureCommandsLoaded(){this.loads++;},applyCommandFilter(){this.filters++;}};
 Object.assign(p,{command,emojiDrawer:new ctx.Drawer(),inputSwitch:{cancel(){},showKeyboard(){p.focusRequests++;}},mention:{clear(){}},
 bottomSlot:'none',showEmojiPanel:false,emojiPanelClosing:false,composerFocused:false,keyboardH:ime,bottomSafe:24,
 drawerAnimSeq:0,fullViewportH:800,focusRequests:0,viewportResizeSettleTimer:-1,
 composerViewport:{holdImeHeight(){p.held=true;}},timeline:{atBottom:false,driveVisibleWork(){}},
 composerController:{stopEditing(){}},currentImeOverlap:()=>ime,headerChromeHeight:()=>100,
 chatEffectDuration:(_k,n)=>n,armImeBridgeTimer(){},syncComposerBottomGap(){},viewerOpen:()=>false,
 clearImeBridge(){this.drawerClosingToIme=false;this.emojiDrawer.closingImeToDrawer=false;},
 startDrawerToImeBridge(slot){this.bridgeSlot=slot;this.drawerClosingToIme=true;this.emojiDrawer.closingToIme=true;},
 getUIContext:()=>({postFrameCallback:f=>frames.push(f)})});
 p.emojiDrawer.measureViewport(800);p.emojiDrawer.fullViewportH=800;p.emojiDrawer.setImeHeight(ime);
 return p;
}
function finish(){for(let i=0;frames.length&&i<15;i++){now+=100;const batch=frames;frames=[];for(const f of batch)f.fn();}assert.equal(frames.length,0);}
for(const ime of [0,220,420]){
 const p=page(ime);p.toggleBotMenu();assert.equal(p.bottomSlot,'commands');assert.equal(p.command.commandMenuOpen,true);
 assert.equal(p.emojiDrawer.activeSlot,'commands');assert.equal(p.emojiDrawer.shellHeight,ime);
 assert.equal(p.command.loads,1);assert.equal(p.command.filters,1);if(ime)assert.equal(p.held,true);
 finish();assert.equal(p.emojiDrawer.shellHeight,p.targetDrawerLiftHeight('commands'));
 assert.equal(p.emojiDrawer.topViewportHeight(),800-p.emojiDrawer.shellHeight,'reserved viewport lifts composer/list');
 assert.equal(p.bottomPanelOpen(),true);
 p.toggleBotMenu();assert.equal(p.bottomSlot,'none');assert.equal(p.command.commandMenuOpen,false);finish();
 assert.equal(p.emojiDrawer.shellHeight,0);assert.equal(p.emojiDrawer.activeSlot,'');
}
// A stale closing frame must never erase a newly opened owner.
for(const replacement of ['commands','attach']){
 const p=page();p.toggleBotMenu();finish();p.closeCommandDrawer();
 if(replacement==='commands')p.toggleBotMenu();else p.openBottomDrawer('attach');
 finish();assert.equal(p.bottomSlot,replacement);assert.equal(p.emojiDrawer.activeSlot,replacement);
 assert.equal(p.emojiDrawer.shellHeight,p.targetDrawerLiftHeight(replacement));
 p.onBotCommandDrawerChanged();assert.equal(p.bottomSlot,replacement);
}
// Send/touch controller changes close only their own drawer; replacement ownership survives.
const p=page();p.toggleBotMenu();finish();p.command.closePanel();p.onBotCommandDrawerChanged();finish();
assert.equal(p.emojiDrawer.shellHeight,0);
p.toggleBotMenu();finish();p.fillCommand({command:'help'});
assert.equal(p.draft,'/help ');assert.equal(p.bridgeSlot,'commands');assert.equal(p.focusRequests,1);
p.onBotCommandDrawerChanged();assert.equal(p.drawerClosingToIme,true,'monitor must not cancel IME handoff');
const q=page();q.toggleBotMenu();finish();q.closeBottomPanels();finish();assert.equal(q.emojiDrawer.shellHeight,0);
// Command size uses the same bounded geometry for rotation/multiline composer.
const g=page();g.toggleBotMenu();finish();g.emojiDrawer.measureViewport(390);g.syncOpenDrawerHeight();
assert.ok(g.emojiDrawer.shellHeight<=390-100-76);const seq=g.drawerAnimSeq;
for(let i=0;i<1000;i++)g.syncOpenDrawerHeight();assert.equal(g.drawerAnimSeq,seq);
// Real compiled drawer binds fixed card geometry, clips the shrinking shell,
// and disables pending clicks on its retained closing subtree.
const uiCalls=[],panels=[];for(const n of ['Stack','__Common__'])ctx[n]=new Proxy({}, {get:(_,k)=>(...a)=>uiCalls.push([n,k,...a])});
ctx.SuggestionPanel=class{constructor(_,params){panels.push(params);}};
run(`class View {${member('BotCommandDrawer','initialRender')}}globalThis.View=View;`);
for(const enabled of [false,true])for(const closing of [false,true]){
 const v=new ctx.View();Object.assign(v,{observeComponentCreation2:fn=>fn(1,true),
 command:{commandMenuOpen:enabled,commandItems:[],commandLoadState:'loading',catalogSize:()=>0},
 drawer:{shellHeight:80,cardOffsetY:5,cardOpacity:.9,closingToIme:closing},cardHeight:312,appDark:true});
 uiCalls.length=panels.length=0;v.initialRender();assert.equal(panels.length,1);assert.equal(panels[0].drawerHeight,312);
 assert.equal(uiCalls.find(x=>x[1]==='enabled')[2],enabled&&!closing);
 assert.equal(uiCalls.find(x=>x[1]==='height')[2],80);assert.equal(uiCalls.find(x=>x[1]==='clip')[2],true);
}
console.log('PASS: bot command drawer open/close, IME handoff, viewport lift, replacement ownership/stale frames, fill-to-keyboard, bounded geometry and compiled retained-shell hit guard.');
// Typed slash suggestions remain above the keyboard; explicit/closing drawer
// never mounts a second copy in that floating slot.
for(const n of ['Column','If'])ctx[n]=new Proxy({}, {get:()=>()=>{}});
run(`class Surface {${member('ChatPageSurface','bottomSuggestions')}}globalThis.Surface=Surface;`);
for(const [menu,slot,expected] of [[true,'commands',0],[false,'commands',0],[false,'',1]]){
 const s=new ctx.Surface();Object.assign(s,{observeComponentCreation2:fn=>fn(1,true),ifElseBranchUpdateFunction:(_,fn)=>fn(),
 timeline:{initialMessageTransitionSettled:true},membershipState:'writable',showEmojiPanel:false,replyKeyboardVisible:false,
 emojiDrawer:{activeSlot:slot},mention:{mentionItems:[]},command:{commandMenuOpen:menu,commandPanelActive:()=>true,catalogSize:()=>1}});
 panels.length=0;s.bottomSuggestions();assert.equal(panels.length,expected);
}
const swap=page();swap.toggleBotMenu();finish();swap.closeCommandDrawer(false,false);
swap.applyBottomSlot('replyKeyboard');assert.equal(swap.emojiDrawer.shellHeight,0);finish();
assert.equal(swap.bottomSlot,'replyKeyboard');
console.log('PASS: typed vs explicit command presentation, no duplicate panel, immediate handoff to four-square reply keyboard.');
// Replay real viewport compensation with asymmetrically sampled animation tails.
// Small deltas must accumulate, not disappear; settling must use the final inset.
let timerId=0;const timers=new Map();
ctx.setTimeout=fn=>{timers.set(++timerId,fn);return timerId;};ctx.clearTimeout=id=>timers.delete(id);
run(`class Resize {${['handleViewportHeightChange','onViewportResizeFrame','clearViewportResizeSettleTimer'].map(n=>member('ChatPage',n)).join('\n')}}globalThis.Resize=Resize;`);
function resized(atBottom=false){
 const r=new ctx.Resize();let offset=1000,glued=0;
 Object.assign(r,{viewportScrollRemainder:0,viewportResizeSettleTimer:-1,fullViewportH:800,
 keyboardH:0,drawerClosingToIme:false,imeTailPinned:false,viewerOpen:()=>false,
 emojiDrawer:{shellHeight:0,closingImeToDrawer:false},timeline:{atBottom,didInitialScroll:true,
 initialTimelineMasked:false,groups:[1],listTouchActive:false,pauseForViewportResize(){},resumeAfterViewportResize(){},driveVisibleWork(){},
 glueBottom(){glued++;},scroller:{scrollBy:(_x,y)=>{offset+=y;},isAtEnd:()=>true}}});
 return {r,offset:()=>offset,glued:()=>glued};
}
function settle(){const batch=[...timers.values()];timers.clear();for(const f of batch)f();}
const mid=resized();
for(let cycle=0;cycle<20;cycle++){
 // Open in one measurable step, close in sub-threshold steps.
 mid.r.handleViewportHeightChange(800,797);settle();
 for(let i=0;i<10;i++)mid.r.handleViewportHeightChange(797+i*.3,797+(i+1)*.3);
 settle();assert.ok(Math.abs(mid.offset()-1000)<1e-6,'open/close cannot accumulate fractional drift');
}
const tail=resized(true);tail.r.handleViewportHeightChange(500,800);
assert.equal(tail.glued(),1,'a transient isAtEnd cannot skip close correction');settle();
assert.equal(tail.glued(),2,'final composer inset settles before releasing tail pin');assert.equal(tail.r.imeTailPinned,false);
const touch=resized();touch.r.handleViewportHeightChange(800,799.7);touch.r.timeline.listTouchActive=true;settle();assert.equal(touch.offset(),1000,'user drag owns scroll');
const gone=resized();gone.r.handleViewportHeightChange(800,799.7);gone.r.clearViewportResizeSettleTimer();settle();assert.equal(gone.offset(),1000);assert.equal(gone.r.viewportScrollRemainder,0);
console.log('PASS: fractional viewport round trips, final tail/inset settlement, touch ownership and teardown.');
