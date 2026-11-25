// Real PR50 geometry/focus methods, deterministic window/IME order and timers.
import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
const ts=(await import(process.env.TYPESCRIPT_MODULE||'typescript')).default;
const root='entry/src/main/ets/';
const read=p=>fs.readFileSync(root+p+'.ets','utf8');
const c=vm.createContext({Number,Math,ObservedV2:x=>x,Trace:()=>{},COMPOSER_GAP_TIGHT:6,
 SLOT_EMOJI:'emoji',SLOT_ATTACH:'attach',SLOT_COMMANDS:'commands',
 slotIsDrawer:s=>['emoji','attach','commands'].includes(s),composerDockBottomGap:n=>Math.max(6,Math.round(n*0.7))});
function run(s){vm.runInContext(ts.transpileModule(s.replace(/^import[\s\S]*?;\n/gm,'').replace(/\bexport /g,'').replace(/@ObservedV2\s*/g,'').replace(/@Trace\s*/g,''),{compilerOptions:{target:ts.ScriptTarget.ES2020}}).outputText,c);}
for(const name of ['util/drawerMetrics','pages/chat/ComposerViewportState','pages/chat/EmojiDrawerState','pages/chat/ComposerInputSwitch'])run(read(name));
run('globalThis.Viewport=ComposerViewportState;globalThis.Drawer=EmojiDrawerState;globalThis.Input=ComposerInputSwitch;');
function method(s,n){const m=new RegExp(`^  (?:private )?${n}\\(`,'m').exec(s);assert.ok(m,n);const ast=ts.createSourceFile('s.ts','class P {\n'+s.slice(m.index),ts.ScriptTarget.Latest,true);return ast.statements[0].members[0].getText(ast);}
const page=read('pages/chat/ChatPage');
run(`class Page {${['currentImeOverlap','publishComposerViewport','onComposerWindowChanged','handleResizeAreaChange','targetDrawerTotalHeight','targetDrawerLiftHeight','syncOpenDrawerHeight','composerBottomGap'].map(n=>method(page,n)).join('\n')}}globalThis.Page=Page;`);
let count=0;function check(n,f){try{f();count++;}catch(e){e.message=n+': '+e.message;throw e;}}
function model(w=390,h=844){const v=new c.Viewport();v.setWindow(w,h);v.resize(h);return v;}
check('window shrink without IME never creates keyboard height',()=>{
 for(const order of ['window-first','area-first']){
  const v=model();if(order==='area-first')v.resize(400);v.setWindow(600,400);v.resize(400);
  assert.equal(v.fullHeight,400);assert.equal(v.imeHeight,0);assert.equal(v.overlap(),0);
  const d=new c.Drawer();d.measureViewport(v.fullHeight);d.setImeHeight(v.imeHeight);
  assert.equal(d.totalHeight(100,24),216);assert.ok(d.totalHeight(100,24)<400);
 }
});
check('keyboard before/after RESIZE produces same full bounds and close restores them',()=>{
 for(const first of [true,false]){
  const v=model(390,800);if(first)v.setKeyboard(300);v.resize(500);if(!first)v.setKeyboard(300);
  assert.equal(v.fullHeight,800);assert.equal(v.imeHeight,300);assert.equal(v.overlap(),300);
  v.setKeyboard(0);v.resize(600);assert.equal(v.fullHeight,800);assert.equal(v.overlap(),200);
  v.resize(800);assert.equal(v.overlap(),0);assert.equal(v.imeHeight,300);
  v.setKeyboard(220);v.resize(580);assert.equal(v.imeHeight,220,'smaller IME must replace old maximum');
 }
});
check('initial page with keyboard visible and non-keyboard inset',()=>{
 const v=new c.Viewport();v.setWindow(390,844);v.setKeyboard(300);assert.equal(v.overlap(),300);v.resize(500);assert.equal(v.fullHeight,800);
 const inset=new c.Viewport();inset.setWindow(390,844);inset.resize(800);inset.setKeyboard(300);
 assert.equal(inset.fullHeight,800);inset.resize(500);assert.equal(inset.overlap(),300);
});
check('panel handoff retains its height through keyboard close animation',()=>{
 const v=model(390,800);v.setKeyboard(300);v.resize(500);v.holdImeHeight();
 for(const h of [220,120,1,0]){v.setKeyboard(h);v.resize(800-h);assert.equal(v.imeHeight,300);}
 v.setKeyboard(240);v.resize(560);assert.equal(v.imeHeight,240);
});
check('rotation with IME or drawer resets prior size; new keyboard relearns',()=>{
 const v=model();v.setKeyboard(400);v.resize(444);v.setWindow(844,390);
 assert.equal(v.imeHeight,0);assert.equal(v.overlap(),0);assert.equal(v.fullHeight,390);
 v.setKeyboard(150);v.resize(240);assert.equal(v.imeHeight,150);assert.equal(v.overlap(),150);
});
check('1000 resizes and invalid measurements keep bounded state, no history accumulation',()=>{
 const v=model();for(let i=0;i<1000;i++){
  const h=300+i%400;v.setWindow(500,h);v.resize(h);assert.equal(v.fullHeight,h);assert.equal(v.imeHeight,0);
 }
 const h=v.fullHeight;v.resize(NaN);v.resize(-1);v.setWindow(0,0);v.setKeyboard(NaN);assert.equal(v.fullHeight,h);
});
check('real page publishes one viewport source and clamps existing open panel on resize',()=>{
 const p=new c.Page();Object.assign(p,{composerViewport:model(),emojiDrawer:new c.Drawer(),screenW:390,screenH:844,
 keyboardH:0,showEmojiPanel:true,attachPanelOpen:false,bottomSlot:'emoji',bottomSafe:24,drawerAnimSeq:1,imeBridgeTimer:-1,
 headerChromeHeight:()=>100,clearImeBridge:()=>{},syncComposerBottomGap:()=>{}});
 p.publishComposerViewport();p.emojiDrawer.shellHeight=336;p.emojiDrawer.activeSlot='emoji';
 p.screenW=600;p.screenH=400;p.handleResizeAreaChange(844,400);
 assert.equal(p.fullViewportH,400);assert.equal(p.emojiDrawer.viewport,400);assert.equal(p.knownImeH,0);
 assert.equal(p.emojiDrawer.shellHeight,216);assert.equal(p.currentImeOverlap(),0);assert.equal(p.drawerAnimSeq,2);
});
check('composer reflow preserves in-flight opening unless the target actually changes',()=>{
 const p=new c.Page();Object.assign(p,{emojiDrawer:new c.Drawer(),showEmojiPanel:true,attachPanelOpen:false,bottomSlot:'emoji',
  bottomSafe:24,drawerTargetHeight:336,drawerAnimSeq:5,headerChromeHeight:()=>100});
 p.emojiDrawer.measureViewport(800);p.emojiDrawer.shellHeight=30;p.emojiDrawer.cardOffsetY=10;
 p.emojiDrawer.measureComposer(176);p.syncOpenDrawerHeight();
 assert.equal(p.drawerAnimSeq,5);assert.equal(p.emojiDrawer.shellHeight,30,'do not snap a normal opening');
 p.emojiDrawer.measureComposer(600);p.syncOpenDrawerHeight();
 assert.equal(p.emojiDrawer.shellHeight,192);assert.equal(p.drawerTargetHeight,192);assert.equal(p.drawerAnimSeq,6);
 for(let i=0;i<1000;i++)p.syncOpenDrawerHeight();assert.equal(p.drawerAnimSeq,6);
});
check('tight gap is shared by IME/drawer/open/close; idle keeps current dock inset',()=>{
 for(const state of ['keyboard','shell','slot','toIme','fromIme','idle']){
  const p=new c.Page();Object.assign(p,{emojiDrawer:new c.Drawer(),keyboardH:0,drawerClosingToIme:false,bottomSafe:30});
  if(state==='keyboard')p.keyboardH=300;if(state==='shell')p.emojiDrawer.shellHeight=1;
  if(state==='slot')p.emojiDrawer.activeSlot='emoji';if(state==='toIme')p.drawerClosingToIme=true;
  if(state==='fromIme')p.emojiDrawer.closingImeToDrawer=true;
  assert.equal(p.composerBottomGap(),state==='idle'?21:6);
 }
});
check('compact retains height across drafts; tall drafts and expansion stay bounded',()=>{
 const d=new c.Drawer();d.measureViewport(800);d.setImeHeight(350);d.measureComposer(76);
 assert.equal(d.totalHeight(100,24),350);d.measureComposer(176);assert.equal(d.totalHeight(100,24),350);
 d.measureComposer(600);assert.equal(d.totalHeight(100,24),192);d.expanded=true;
 assert.equal(d.totalHeight(100,24),92);assert.equal(d.topOverlap(24),0);
});
function focus(){
 let id=0;const queue=[];const state={active:true,key:1,open:true,keyboard:false,focus:0,fail:false};
 const x=new c.Input({schedule:(fn,delay=0)=>{queue.push({id:++id,fn,delay});return id;},cancel:()=>{}});
 const host={active:()=>state.active,contextKey:()=>state.key,emojiOpen:()=>state.open,
 setEmoji:o=>{x.cancel();state.open=o;},prepareEditor:()=>{},keyboardVisible:()=>state.keyboard,
 focusEditor:()=>{state.focus++;if(state.fail)throw Error('not mounted');}};
 x.bind(host);return {x,state,queue,host,fire:()=>{const batch=queue.splice(0);batch.forEach(e=>e.fn());}};
}
check('focus has at most one 120ms retry, including initially missing native editor',()=>{
 const {x,state,queue,fire}=focus();state.fail=true;x.showKeyboard();fire();assert.equal(state.focus,1);
 assert.equal(queue.length,1);assert.equal(queue[0].delay,120);state.fail=false;fire();assert.equal(state.focus,2);
 assert.equal(queue.length,0);fire();assert.equal(state.focus,2);
});
check('old visible keyboard cannot suppress the initial focus request',()=>{
 const {x,state,fire}=focus();state.keyboard=true;x.showKeyboard();fire();
 assert.equal(state.focus,1);fire();assert.equal(state.focus,1);
});
check('retry yields to keyboard, hide/return, chat change, reopen, dispose and rebind',()=>{
 for(const action of ['keyboard','hide','cancel-return','chat','reopen','dispose','rebind']){
  const {x,state,host,fire}=focus();x.showKeyboard();fire();
  if(action==='keyboard')state.keyboard=true;if(action==='hide')state.active=false;
  if(action==='cancel-return'){x.cancel();state.active=true;}if(action==='chat')state.key++;
  if(action==='reopen')x.toggleEmoji();if(action==='dispose')x.dispose();if(action==='rebind')x.bind(host);
  fire();assert.equal(state.focus,1,action);
 }
});
check('1000 rapid switches never focus canceled requests',()=>{
 const {x,state,fire}=focus();for(let i=0;i<1000;i++){x.showKeyboard();x.toggleEmoji();}
 fire();assert.equal(state.focus,0);assert.equal(state.open,true);
});
check('PR52 short IME/direct entry share settled shell and card, in both callback orders',()=>{
 for(const first of [true,false]){
  const v=model(),p=new c.Page();
  Object.assign(p,{composerViewport:v,emojiDrawer:new c.Drawer(),screenW:390,screenH:844,
   keyboardH:0,showEmojiPanel:true,attachPanelOpen:false,bottomSlot:'emoji',bottomSafe:28,drawerAnimSeq:0,
   drawerTargetHeight:0,imeBridgeTimer:-1,headerChromeHeight:()=>100,clearImeBridge:()=>{},syncComposerBottomGap:()=>{}});
  p.publishComposerViewport();p.syncOpenDrawerHeight();const direct=p.emojiDrawer.shellHeight;
  assert.equal(direct,340);
  p.keyboardH=334;if(first)v.setKeyboard(334);v.resize(510);if(!first)v.setKeyboard(334);
  p.publishComposerViewport();p.syncOpenDrawerHeight();
  assert.equal(p.emojiDrawer.viewport,844,'IME must not subtract the full-height budget twice');
  assert.equal(p.emojiDrawer.shellHeight,direct);
  assert.equal(p.emojiDrawer.cardHeight(100,28)+28,p.emojiDrawer.shellHeight);
  v.holdImeHeight();p.emojiDrawer.closingImeToDrawer=true;
  for(const keyboard of [220,120,1,0]){
   p.keyboardH=keyboard;v.setKeyboard(keyboard);p.handleResizeAreaChange(0,844-keyboard);
   assert.equal(p.emojiDrawer.cardHeight(100,28)+28,direct);
   assert.equal(p.emojiDrawer.shellHeight,direct);
  }
  assert.equal(p.currentImeOverlap(),0);assert.equal(p.emojiDrawer.closingImeToDrawer,false);
  p.emojiDrawer.measureComposer(176);p.syncOpenDrawerHeight();assert.equal(p.emojiDrawer.shellHeight,direct);
  p.screenW=844;p.screenH=390;p.handleResizeAreaChange(844,390);
  assert.equal(p.fullViewportH,390);assert.equal(p.knownImeH,0);assert.equal(p.emojiDrawer.shellHeight,206);
  assert.equal(p.emojiDrawer.cardHeight(100,28)+28,p.emojiDrawer.shellHeight);
 }
});
check('PR52 taller IME follows latest height; compact floor never replaces short-window clamp',()=>{
 const d=new c.Drawer();d.measureViewport(844);
 for(const [height,want] of [[480,480],[400,400],[334,340],[200,340],[0,340]]){
  d.setImeHeight(height);assert.equal(d.totalHeight(100,28),want);
 }
 for(let viewport=220;viewport<=1000;viewport+=13){
  d.measureViewport(viewport);d.setImeHeight(600);
  const total=d.totalHeight(100,28);assert.ok(total<=viewport-100-76-8);
  assert.equal(total,d.cardHeight(100,28)+28);
 }
});
check('PR52 expanded and collapse card geometry share current window after resize',()=>{
 const d=new c.Drawer();d.measureViewport(844);d.measureComposer(176);d.setImeHeight(220);d.expanded=true;
 assert.equal(d.totalHeight(100,28),560);d.expanded=false;d.closingExpanded=true;
 assert.equal(d.cardHeight(100,28),532);d.measureViewport(400);
 assert.equal(d.cardHeight(100,28),88);d.closingExpanded=false;assert.equal(d.totalHeight(100,28),216);
});
console.log(`PASS: ${count} composer window/IME ordering, geometry and focus ownership cases.`);
